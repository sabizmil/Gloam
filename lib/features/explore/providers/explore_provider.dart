import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:matrix/matrix.dart';

import '../../../services/debug_server.dart';
import '../../../services/matrix_service.dart';

/// State for the Explore modal — room search, pagination, join actions.
class ExploreState {
  const ExploreState({
    this.server = '',
    this.searchQuery = '',
    this.rooms = const [],
    this.nextBatch,
    this.totalEstimate,
    this.isLoading = false,
    this.joinedRoomIds = const {},
    this.joiningRoomIds = const {},
    this.error,
    this.spacesOnly = false,
  });

  final String server;
  final String searchQuery;
  final List<PublicRoomsChunk> rooms;
  final String? nextBatch;
  final int? totalEstimate;
  final bool isLoading;
  final Set<String> joinedRoomIds;
  final Set<String> joiningRoomIds;
  final String? error;
  final bool spacesOnly;

  ExploreState copyWith({
    String? server,
    String? searchQuery,
    List<PublicRoomsChunk>? rooms,
    String? Function()? nextBatch,
    int? Function()? totalEstimate,
    bool? isLoading,
    Set<String>? joinedRoomIds,
    Set<String>? joiningRoomIds,
    String? Function()? error,
    bool? spacesOnly,
  }) {
    return ExploreState(
      server: server ?? this.server,
      searchQuery: searchQuery ?? this.searchQuery,
      rooms: rooms ?? this.rooms,
      nextBatch: nextBatch != null ? nextBatch() : this.nextBatch,
      totalEstimate:
          totalEstimate != null ? totalEstimate() : this.totalEstimate,
      isLoading: isLoading ?? this.isLoading,
      joinedRoomIds: joinedRoomIds ?? this.joinedRoomIds,
      joiningRoomIds: joiningRoomIds ?? this.joiningRoomIds,
      error: error != null ? error() : this.error,
      spacesOnly: spacesOnly ?? this.spacesOnly,
    );
  }
}

class ExploreNotifier extends StateNotifier<ExploreState> {
  ExploreNotifier(this._ref) : super(const ExploreState()) {
    final client = _ref.read(matrixServiceProvider).client;
    if (client != null) {
      // Default to user's homeserver
      final homeserver = client.homeserver?.host ?? '';
      state = state.copyWith(
        server: homeserver,
        joinedRoomIds: client.rooms.map((r) => r.id).toSet(),
      );
    }
  }

  final Ref _ref;
  Timer? _debounce;

  Client? get _client => _ref.read(matrixServiceProvider).client;

  /// Change the server to browse.
  void setServer(String server) {
    state = state.copyWith(
      server: server,
      rooms: [],
      nextBatch: () => null,
      totalEstimate: () => null,
      error: () => null,
    );
    _search();
  }

  /// Update search query with debounce.
  void setSearchQuery(String query) {
    state = state.copyWith(searchQuery: query);
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), _search);
  }

  /// Toggle between all rooms and spaces only.
  void setSpacesOnly(bool spacesOnly) {
    state = state.copyWith(
      spacesOnly: spacesOnly,
      rooms: [],
      nextBatch: () => null,
      totalEstimate: () => null,
    );
    _search();
  }

  /// Initial load or after server/query change.
  Future<void> _search() async {
    final client = _client;
    if (client == null) return;

    state = state.copyWith(
      isLoading: true,
      rooms: [],
      error: () => null,
      nextBatch: () => null,
    );

    try {
      final filter = PublicRoomQueryFilter(
        genericSearchTerm:
            state.searchQuery.isNotEmpty ? state.searchQuery : null,
        roomTypes: state.spacesOnly ? ['m.space'] : null,
      );

      // Don't pass server param when browsing the user's own homeserver —
      // it triggers a federation self-request that fails with 403.
      final isHomeServer = state.server == client.homeserver?.host;
      final result = await client.queryPublicRooms(
        server: (!isHomeServer && state.server.isNotEmpty) ? state.server : null,
        limit: 20,
        filter: filter,
      );

      if (mounted) {
        state = state.copyWith(
          rooms: result.chunk,
          nextBatch: () => result.nextBatch,
          totalEstimate: () => result.totalRoomCountEstimate,
          isLoading: false,
          joinedRoomIds: client.rooms.map((r) => r.id).toSet(),
        );
      }
    } catch (e) {
      debugPrint('[Explore] search error: $e');
      if (mounted) {
        state = state.copyWith(
          isLoading: false,
          error: () => 'Failed to load rooms from ${state.server}: $e',
        );
      }
    }
  }

  /// Load the next page of results.
  Future<void> loadMore() async {
    final client = _client;
    if (client == null || state.isLoading || state.nextBatch == null) return;

    state = state.copyWith(isLoading: true);

    try {
      final filter = PublicRoomQueryFilter(
        genericSearchTerm:
            state.searchQuery.isNotEmpty ? state.searchQuery : null,
        roomTypes: state.spacesOnly ? ['m.space'] : null,
      );

      final isHomeServer = state.server == client.homeserver?.host;
      final result = await client.queryPublicRooms(
        server: (!isHomeServer && state.server.isNotEmpty) ? state.server : null,
        limit: 20,
        since: state.nextBatch,
        filter: filter,
      );

      if (mounted) {
        state = state.copyWith(
          rooms: [...state.rooms, ...result.chunk],
          nextBatch: () => result.nextBatch,
          totalEstimate: () => result.totalRoomCountEstimate,
          isLoading: false,
        );
      }
    } catch (e) {
      if (mounted) {
        state = state.copyWith(isLoading: false);
      }
    }
  }

  /// Join a room from the directory.
  Future<void> joinRoom(String roomId) async {
    final client = _client;
    if (client == null) return;

    _log('[Explore] Joining room $roomId via server ${state.server}');

    state = state.copyWith(
      joiningRoomIds: {...state.joiningRoomIds, roomId},
      error: () => null,
    );

    try {
      await client.joinRoom(
        roomId,
        serverName: state.server.isNotEmpty ? [state.server] : null,
      ).timeout(
        const Duration(seconds: 30),
        onTimeout: () => throw TimeoutException(
          'Join timed out after 30s — the server may be slow to federate',
        ),
      );

      _log('[Explore] Joined $roomId successfully');

      if (mounted) {
        state = state.copyWith(
          joinedRoomIds: {...state.joinedRoomIds, roomId},
          joiningRoomIds: state.joiningRoomIds
              .where((id) => id != roomId)
              .toSet(),
        );
      }
    } catch (e) {
      _log('[Explore] Join error for $roomId: $e');
      if (mounted) {
        state = state.copyWith(
          joiningRoomIds: state.joiningRoomIds
              .where((id) => id != roomId)
              .toSet(),
          error: () => 'Failed to join: $e',
        );
      }
    }
  }

  void _log(String msg) {
    debugPrint(msg);
    DebugServer.logs.add('${DateTime.now().toIso8601String()} $msg');
  }

  /// Join a room by alias or ID (for the "Join by Address" tab).
  Future<String?> joinByAddress(String address) async {
    final client = _client;
    if (client == null) return null;

    // Parse matrix.to links
    var input = address.trim();
    final matrixToMatch = RegExp(
      r'https?://matrix\.to/#/([@!#][^?]+)',
    ).firstMatch(input);
    if (matrixToMatch != null) {
      input = Uri.decodeComponent(matrixToMatch.group(1)!);
    }

    // Extract server hint from the address
    final serverMatch = RegExp(r':(.+)$').firstMatch(input);
    final serverHint = serverMatch?.group(1);

    try {
      final joinedId = await client.joinRoom(
        input,
        serverName: serverHint != null ? [serverHint] : null,
      );
      // Refresh joined room set
      if (mounted) {
        state = state.copyWith(
          joinedRoomIds: client.rooms.map((r) => r.id).toSet(),
        );
      }
      return joinedId;
    } catch (e) {
      throw Exception('Failed to join $input: $e');
    }
  }

  /// Trigger initial search.
  void initialLoad() => _search();

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }
}

final exploreProvider =
    StateNotifierProvider.autoDispose<ExploreNotifier, ExploreState>(
  (ref) => ExploreNotifier(ref),
);
