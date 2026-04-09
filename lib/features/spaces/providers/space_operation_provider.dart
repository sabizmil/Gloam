import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:matrix/matrix.dart' hide Visibility;
import 'package:matrix/matrix.dart' as sdk show Visibility;

import '../../../services/debug_server.dart';
import '../../../services/matrix_service.dart';

// ── Models ──

enum StepStatus { pending, running, done, failed }

class OperationStep {
  const OperationStep({
    required this.label,
    this.status = StepStatus.pending,
    this.error,
  });

  final String label;
  final StepStatus status;
  final String? error;

  OperationStep copyWith({StepStatus? status, String? Function()? error}) {
    return OperationStep(
      label: label,
      status: status ?? this.status,
      error: error != null ? error() : this.error,
    );
  }
}

enum OperationType { create, delete }

class SpaceOperationState {
  const SpaceOperationState({
    this.type,
    this.steps = const [],
    this.spaceId,
    this.firstRoomId,
    this.isComplete = false,
    this.fatalError,
    this.spaceName,
  });

  final OperationType? type;
  final List<OperationStep> steps;
  final String? spaceId;
  final String? firstRoomId;
  final bool isComplete;
  final String? fatalError;
  final String? spaceName;

  bool get isIdle => type == null;
  bool get isRunning => type != null && !isComplete && fatalError == null;
  bool get hasFailed => steps.any((s) => s.status == StepStatus.failed);

  SpaceOperationState copyWith({
    OperationType? Function()? type,
    List<OperationStep>? steps,
    String? Function()? spaceId,
    String? Function()? firstRoomId,
    bool? isComplete,
    String? Function()? fatalError,
    String? Function()? spaceName,
  }) {
    return SpaceOperationState(
      type: type != null ? type() : this.type,
      steps: steps ?? this.steps,
      spaceId: spaceId != null ? spaceId() : this.spaceId,
      firstRoomId: firstRoomId != null ? firstRoomId() : this.firstRoomId,
      isComplete: isComplete ?? this.isComplete,
      fatalError: fatalError != null ? fatalError() : this.fatalError,
      spaceName: spaceName != null ? spaceName() : this.spaceName,
    );
  }
}

// ── Params ──

class CreateSpaceParams {
  const CreateSpaceParams({
    required this.name,
    this.topic,
    this.avatar,
    required this.isPublic,
    this.alias,
    this.roomNames = const [],
    this.invites = const {},
  });

  final String name;
  final String? topic;
  final Uint8List? avatar;
  final bool isPublic;
  final String? alias;
  final List<String> roomNames;
  final Map<String, int> invites; // userId -> powerLevel
}

class DeleteSpaceParams {
  const DeleteSpaceParams({
    required this.spaceId,
    this.roomIdsToDelete = const {},
  });

  final String spaceId;
  final Set<String> roomIdsToDelete;
}

// ── Notifier ──

class SpaceOperationNotifier extends StateNotifier<SpaceOperationState> {
  SpaceOperationNotifier(this._ref) : super(const SpaceOperationState());

  final Ref _ref;
  Client? get _client => _ref.read(matrixServiceProvider).client;

  /// Reset to idle state.
  void reset() {
    state = const SpaceOperationState();
  }

  // ── Create Space ──

  Future<void> createSpace(CreateSpaceParams params) async {
    final client = _client;
    if (client == null) return;

    // Build step list
    final steps = <OperationStep>[
      const OperationStep(label: 'Creating space'),
      ...params.roomNames.map(
        (n) => OperationStep(label: 'Creating #$n'),
      ),
      if (params.invites.isNotEmpty)
        OperationStep(
          label: 'Inviting ${params.invites.length} member${params.invites.length > 1 ? 's' : ''}',
        ),
    ];

    state = SpaceOperationState(
      type: OperationType.create,
      steps: steps,
      spaceName: params.name,
    );

    // --- Step 1: Create the space ---
    _markStep(0, StepStatus.running);
    try {
      // Build initial state events
      final initialState = <StateEvent>[];

      // Power levels — creator as admin, pre-assign invitee levels
      if (params.invites.isNotEmpty) {
        final powerLevels = <String, dynamic>{
          client.userID!: 100,
          ...params.invites.map((k, v) => MapEntry(k, v)),
        };
        initialState.add(StateEvent(
          type: EventTypes.RoomPowerLevels,
          stateKey: '',
          content: {
            'users': powerLevels,
            'users_default': 0,
          },
        ));
      }

      // Avatar — upload first, then reference
      if (params.avatar != null) {
        final uri = await client.uploadContent(
          params.avatar!,
          filename: 'avatar.png',
          contentType: 'image/png',
        );
        initialState.add(StateEvent(
          type: EventTypes.RoomAvatar,
          stateKey: '',
          content: {'url': uri.toString()},
        ));
      }

      final spaceId = await client.createRoom(
        name: params.name,
        topic: params.topic,
        creationContent: {'type': 'm.space'},
        visibility: params.isPublic
            ? sdk.Visibility.public
            : sdk.Visibility.private,
        roomAliasName: params.isPublic ? params.alias : null,
        preset: params.isPublic
            ? CreateRoomPreset.publicChat
            : CreateRoomPreset.privateChat,
        initialState: initialState.isNotEmpty ? initialState : null,
      );

      state = state.copyWith(spaceId: () => spaceId);
      _markStep(0, StepStatus.done);
      _log('[SpaceOp] Created space $spaceId');
    } catch (e) {
      _markStep(0, StepStatus.failed, error: _humanReadableError(e));
      state = state.copyWith(
        fatalError: () => 'Failed to create space',
      );
      return; // Can't continue without the space
    }

    // --- Step 2: Create starter rooms ---
    final space = client.getRoomById(state.spaceId!);
    if (space == null) {
      _log('[SpaceOp] Space room not found locally yet');
      // Wait briefly for sync to pick up the new room
      await Future.delayed(const Duration(seconds: 1));
    }
    final spaceRoom = client.getRoomById(state.spaceId!);

    for (var i = 0; i < params.roomNames.length; i++) {
      final stepIndex = 1 + i;
      _markStep(stepIndex, StepStatus.running);
      try {
        final roomId = await client.createRoom(
          name: params.roomNames[i],
          preset: params.isPublic
              ? CreateRoomPreset.publicChat
              : CreateRoomPreset.privateChat,
          visibility: params.isPublic
              ? sdk.Visibility.public
              : sdk.Visibility.private,
        );

        if (spaceRoom != null) {
          await spaceRoom.setSpaceChild(roomId);
        }

        if (i == 0) {
          state = state.copyWith(firstRoomId: () => roomId);
        }
        _markStep(stepIndex, StepStatus.done);
        _log('[SpaceOp] Created room ${params.roomNames[i]} ($roomId)');
      } catch (e) {
        _markStep(stepIndex, StepStatus.failed,
            error: _humanReadableError(e));
        // Continue — don't block on a single room failure
      }
    }

    // --- Step 3: Invite members ---
    if (params.invites.isNotEmpty) {
      final inviteStepIndex = 1 + params.roomNames.length;
      _markStep(inviteStepIndex, StepStatus.running);

      final targetRoom = spaceRoom ?? client.getRoomById(state.spaceId!);
      if (targetRoom == null) {
        _markStep(inviteStepIndex, StepStatus.failed,
            error: 'Space not found');
      } else {
        var failures = 0;
        for (final userId in params.invites.keys) {
          try {
            await targetRoom.invite(userId);
          } catch (e) {
            failures++;
            _log('[SpaceOp] Failed to invite $userId: $e');
          }
        }
        _markStep(
          inviteStepIndex,
          failures > 0 ? StepStatus.failed : StepStatus.done,
          error: failures > 0 ? '$failures invite(s) failed' : null,
        );
      }
    }

    state = state.copyWith(isComplete: true);
    _log('[SpaceOp] Space creation complete');
  }

  // ── Delete Space ──

  Future<void> deleteSpace(DeleteSpaceParams params) async {
    final client = _client;
    if (client == null) return;

    final space = client.getRoomById(params.spaceId);
    if (space == null) return;

    final members = await space.requestParticipants();
    final joinedMembers = members
        .where((m) => m.membership == Membership.join && m.id != client.userID)
        .toList();

    // Build step list
    final steps = <OperationStep>[
      ...params.roomIdsToDelete.map((id) {
        final room = client.getRoomById(id);
        return OperationStep(
          label: 'Deleting #${room?.getLocalizedDisplayname() ?? id}',
        );
      }),
      if (joinedMembers.isNotEmpty)
        OperationStep(
          label: 'Removing ${joinedMembers.length} member${joinedMembers.length > 1 ? 's' : ''}',
        ),
      const OperationStep(label: 'Deleting space'),
    ];

    state = SpaceOperationState(
      type: OperationType.delete,
      steps: steps,
      spaceId: params.spaceId,
      spaceName: space.getLocalizedDisplayname(),
    );

    var stepIndex = 0;

    // --- Delete checked child rooms ---
    for (final roomId in params.roomIdsToDelete) {
      _markStep(stepIndex, StepStatus.running);
      try {
        // Remove from space hierarchy
        await space.removeSpaceChild(roomId);

        final room = client.getRoomById(roomId);
        if (room != null) {
          // Kick members from child room
          final roomMembers = await room.requestParticipants();
          for (final m in roomMembers.where(
            (m) => m.membership == Membership.join && m.id != client.userID,
          )) {
            try {
              await room.kick(m.id);
            } catch (_) {}
          }
          await room.leave();
          await room.forget();
        }
        _markStep(stepIndex, StepStatus.done);
      } catch (e) {
        _markStep(stepIndex, StepStatus.failed,
            error: _humanReadableError(e));
      }
      stepIndex++;
    }

    // --- Kick space members ---
    if (joinedMembers.isNotEmpty) {
      _markStep(stepIndex, StepStatus.running);
      var kickFailures = 0;
      for (final m in joinedMembers) {
        try {
          await space.kick(m.id);
        } catch (_) {
          kickFailures++;
        }
      }
      _markStep(
        stepIndex,
        kickFailures > 0 ? StepStatus.failed : StepStatus.done,
        error:
            kickFailures > 0 ? '$kickFailures member(s) could not be removed' : null,
      );
      stepIndex++;
    }

    // --- Leave + forget space ---
    _markStep(stepIndex, StepStatus.running);
    try {
      await space.leave();
      await space.forget();
      _markStep(stepIndex, StepStatus.done);
    } catch (e) {
      _markStep(stepIndex, StepStatus.failed,
          error: _humanReadableError(e));
    }

    state = state.copyWith(isComplete: true);
    _log('[SpaceOp] Space deletion complete');
  }

  // ── Helpers ──

  void _markStep(int index, StepStatus status, {String? error}) {
    if (!mounted) return;
    final updated = List<OperationStep>.from(state.steps);
    if (index >= updated.length) return;
    updated[index] = updated[index].copyWith(
      status: status,
      error: () => error,
    );
    state = state.copyWith(steps: updated);
  }

  String _humanReadableError(Object e) {
    final msg = e.toString();
    if (msg.contains('M_FORBIDDEN')) return 'Permission denied';
    if (msg.contains('M_ROOM_IN_USE')) return 'Address already in use';
    if (msg.contains('M_LIMIT_EXCEEDED')) return 'Rate limited — try again';
    if (msg.contains('M_UNKNOWN')) return 'Server error';
    if (msg.contains('SocketException')) return 'Network error';
    if (msg.contains('TimeoutException')) return 'Request timed out';
    // Strip class prefixes for cleaner display
    return msg.replaceAll(RegExp(r'^[A-Za-z]+Exception:\s*'), '');
  }

  void _log(String msg) {
    debugPrint(msg);
    DebugServer.logs.add('${DateTime.now().toIso8601String()} $msg');
  }
}

// App-level provider — NOT autoDispose so operations survive modal close.
final spaceOperationProvider =
    StateNotifierProvider<SpaceOperationNotifier, SpaceOperationState>(
  (ref) => SpaceOperationNotifier(ref),
);
