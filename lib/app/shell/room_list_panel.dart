import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:matrix/matrix.dart' show EventTypes;

import '../theme/color_tokens.dart';
import '../theme/spacing.dart';
import '../../features/calls/data/adapters/matrix_rtc_adapter.dart';
import '../../features/calls/domain/voice_channel.dart';
import '../../features/calls/presentation/widgets/voice_channel_tile.dart';
import '../../features/chat/presentation/providers/timeline_provider.dart';
import '../../features/chat/presentation/screens/chat_screen.dart';
import '../../features/rooms/presentation/providers/room_list_provider.dart';
import '../../features/rooms/presentation/widgets/create_room_dialog.dart';
import '../../features/rooms/presentation/widgets/room_list_tile.dart';
import '../../services/matrix_service.dart';
import '../../services/voice_service.dart';
import '../../widgets/section_header.dart';
import 'space_rail.dart';

/// Room list panel — shows rooms filtered by the selected space.
class RoomListPanel extends ConsumerStatefulWidget {
  const RoomListPanel({super.key});

  @override
  ConsumerState<RoomListPanel> createState() => _RoomListPanelState();
}

class _RoomListPanelState extends ConsumerState<RoomListPanel> {
  String _searchQuery = '';
  _RoomFilter _filter = _RoomFilter.all;

  void _selectRoom(String roomId) {
    ref.read(selectedRoomProvider.notifier).state = roomId;

    // On mobile, push chat screen
    final width = MediaQuery.sizeOf(context).width;
    if (width < GloamSpacing.breakpointTablet) {
      ref.read(mobileChatRouteActiveProvider.notifier).state = true;
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => Scaffold(
            backgroundColor: GloamColors.bg,
            body: SafeArea(
              child: _MobileChatScreen(roomId: roomId),
            ),
          ),
        ),
      ).then((_) {
        if (mounted) {
          ref.read(mobileChatRouteActiveProvider.notifier).state = false;
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final roomsAsync = ref.watch(roomListProvider);
    final selectedRoom = ref.watch(selectedRoomProvider);
    final selectedSpace = ref.watch(selectedSpaceProvider);

    return Container(
      width: GloamSpacing.roomListWidth,
      decoration: const BoxDecoration(
        color: GloamColors.bgSurface,
        border: Border(
          right: BorderSide(color: GloamColors.border),
        ),
      ),
      child: Column(
        children: [
          // Header with homeserver name
          _PanelHeader(selectedSpace: selectedSpace),

          // Search bar
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: _SearchBar(
              onChanged: (q) => setState(() => _searchQuery = q),
            ),
          ),

          // Filter chips
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: Row(
              children: _RoomFilter.values.map((f) {
                final isActive = f == _filter;
                return Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: GestureDetector(
                    onTap: () => setState(() => _filter = f),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: isActive
                            ? GloamColors.accentDim
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isActive
                              ? GloamColors.accent
                              : GloamColors.border,
                        ),
                      ),
                      child: Text(
                        f.label,
                        style: GoogleFonts.jetBrainsMono(
                          fontSize: 10,
                          color: isActive
                              ? GloamColors.accent
                              : GloamColors.textTertiary,
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),

          // Room list
          Expanded(
            child: roomsAsync.when(
              loading: () => const Center(
                child: CircularProgressIndicator(
                  color: GloamColors.accent,
                  strokeWidth: 2,
                ),
              ),
              error: (e, s) => Center(
                child: Text(
                  '// error loading rooms',
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 11,
                    color: GloamColors.danger,
                  ),
                ),
              ),
              data: (rooms) {
                var filtered = _applyFilters(
                    rooms, _searchQuery, _filter, selectedSpace, ref);

                if (filtered.isEmpty) {
                  return Center(
                    child: Text(
                      _searchQuery.isNotEmpty
                          ? '// no matches'
                          : '// no conversations',
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: 11,
                        color: GloamColors.textTertiary,
                        letterSpacing: 1,
                      ),
                    ),
                  );
                }

                final dms = filtered.where((r) => r.isDirect).toList();
                final channels = filtered
                    .where((r) =>
                        !r.isDirect && !_isVoiceChannel(r.roomId, ref))
                    .toList();
                final voiceChannels = _getVoiceChannels(ref);
                final voiceState = ref.watch(voiceServiceProvider);
                final connectedChannelId = voiceState is VoiceStateConnected
                    ? voiceState.channelId
                    : null;

                return ListView(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 4),
                  children: [
                    if (dms.isNotEmpty) ...[
                      const SectionHeader('direct messages'),
                      ...dms.map((room) => RoomListTile(
                            room: room,
                            isActive: room.roomId == selectedRoom,
                            onTap: () => _selectRoom(room.roomId),
                          )),
                    ],
                    if (channels.isNotEmpty) ...[
                      const SectionHeader('channels'),
                      ...channels.map((room) => RoomListTile(
                            room: room,
                            isActive: room.roomId == selectedRoom,
                            onTap: () => _selectRoom(room.roomId),
                          )),
                    ],
                    if (voiceChannels.isNotEmpty) ...[
                      const SectionHeader('voice channels'),
                      ...voiceChannels.map((vc) => VoiceChannelTile(
                            channel: vc,
                            isConnected: vc.id == connectedChannelId,
                            onTap: () => _handleVoiceChannelTap(vc),
                          )),
                    ],
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  List<RoomListItem> _applyFilters(
    List<RoomListItem> rooms,
    String query,
    _RoomFilter filter,
    String? spaceId,
    WidgetRef ref,
  ) {
    var result = rooms;

    // Space filter — show only rooms that are children of the selected space
    if (spaceId != null) {
      final client = ref.read(matrixServiceProvider).client;
      if (client != null) {
        final space = client.getRoomById(spaceId);
        if (space != null) {
          final childIds =
              space.spaceChildren.map((c) => c.roomId).toSet();
          result = result
              .where((r) => childIds.contains(r.roomId))
              .toList();
        }
      }
    }

    // Text search
    if (query.isNotEmpty) {
      final q = query.toLowerCase();
      result = result
          .where((r) => r.displayName.toLowerCase().contains(q))
          .toList();
    }

    // Category filter
    switch (filter) {
      case _RoomFilter.all:
        break;
      case _RoomFilter.unread:
        result = result.where((r) => r.unreadCount > 0).toList();
      case _RoomFilter.mentions:
        result = result.where((r) => r.mentionCount > 0).toList();
    }

    return result;
  }

  /// Check if a room is a voice channel by inspecting its create event.
  bool _isVoiceChannel(String roomId, WidgetRef ref) {
    final client = ref.read(matrixServiceProvider).client;
    if (client == null) return false;
    final room = client.getRoomById(roomId);
    if (room == null) return false;

    final createEvent = room.getState(EventTypes.RoomCreate);
    if (createEvent != null) {
      final roomType = createEvent.content['type'];
      if (roomType == 'im.gloam.voice_channel') return true;
      if (roomType == 'org.matrix.msc3417.call') return true;
    }
    return room.tags.containsKey('im.gloam.voice_channel');
  }

  /// Build voice channel list from Matrix rooms.
  List<VoiceChannel> _getVoiceChannels(WidgetRef ref) {
    final client = ref.read(matrixServiceProvider).client;
    if (client == null) return [];

    final selectedSpace = ref.watch(selectedSpaceProvider);

    var rooms = client.rooms.where((r) {
      final createEvent = r.getState(EventTypes.RoomCreate);
      final roomType = createEvent?.content['type'];
      if (roomType == 'im.gloam.voice_channel') return true;
      if (roomType == 'org.matrix.msc3417.call') return true;
      return r.tags.containsKey('im.gloam.voice_channel');
    }).toList();

    // Filter by selected space
    if (selectedSpace != null) {
      final space = client.getRoomById(selectedSpace);
      if (space != null) {
        final childIds = space.spaceChildren.map((c) => c.roomId).toSet();
        rooms = rooms.where((r) => childIds.contains(r.id)).toList();
      }
    }

    return rooms.map((room) {
      final memberStates =
          room.states['org.matrix.msc3401.call.member'] ?? {};
      final participants = <VoiceChannelParticipantSummary>[];

      for (final entry in memberStates.entries) {
        final userId = entry.key;
        final event = entry.value;
        final memberships = event.content['memberships'];
        if (memberships is! List || memberships.isEmpty) continue;

        final user = room.unsafeGetUserFromMemoryOrFallback(userId);
        participants.add(VoiceChannelParticipantSummary(
          userId: userId,
          displayName: user.calcDisplayname(),
          avatarUrl: user.avatarUrl,
        ));
      }

      return VoiceChannel(
        id: room.id,
        name: room.getLocalizedDisplayname(),
        description: room.topic,
        currentParticipantCount: participants.length,
        connectedParticipants: participants,
      );
    }).toList()
      // Sort: channels with participants first
      ..sort((a, b) =>
          b.currentParticipantCount.compareTo(a.currentParticipantCount));
  }

  void _handleVoiceChannelTap(VoiceChannel channel) {
    // Select the room first (shows the voice channel screen)
    _selectRoom(channel.id);

    // If not already connected to this channel, join it
    final voiceState = ref.read(voiceServiceProvider);
    final alreadyConnected = voiceState is VoiceStateConnected &&
        voiceState.channelId == channel.id;
    if (!alreadyConnected) {
      final client = ref.read(matrixServiceProvider).client;
      if (client != null) {
        final adapter = MatrixRTCAdapter(client: client);
        ref.read(voiceServiceProvider.notifier).joinChannel(
              adapter: adapter,
              channelId: channel.id,
            );
      }
    }
  }
}

enum _RoomFilter {
  all('all'),
  unread('unread'),
  mentions('mentions');

  const _RoomFilter(this.label);
  final String label;
}

class _PanelHeader extends ConsumerWidget {
  const _PanelHeader({this.selectedSpace});
  final String? selectedSpace;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Resolve space name
    String title = 'all chats';
    if (selectedSpace != null) {
      final client = ref.watch(matrixServiceProvider).client;
      final space = client?.getRoomById(selectedSpace!);
      title = space?.getLocalizedDisplayname() ?? 'space';
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: GoogleFonts.jetBrainsMono(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: GloamColors.textSecondary,
                letterSpacing: 1.5,
              ),
            ),
          ),
          GestureDetector(
            onTap: () async {
              final roomId = await showCreateRoomDialog(context);
              if (roomId != null) {
                ref.read(selectedRoomProvider.notifier).state = roomId;
              }
            },
            child: const Icon(Icons.add,
                size: 18, color: GloamColors.textSecondary),
          ),
        ],
      ),
    );
  }
}

class _SearchBar extends StatelessWidget {
  const _SearchBar({required this.onChanged});
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 36,
      decoration: BoxDecoration(
        color: GloamColors.bg,
        borderRadius: BorderRadius.circular(GloamSpacing.radiusSm),
        border: Border.all(color: GloamColors.border),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: Row(
        children: [
          const Icon(Icons.search,
              size: 14, color: GloamColors.textTertiary),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              onChanged: onChanged,
              style: GoogleFonts.jetBrainsMono(
                fontSize: 12,
                color: GloamColors.textPrimary,
              ),
              decoration: InputDecoration(
                hintText: 'search or jump to...',
                hintStyle: GoogleFonts.jetBrainsMono(
                  fontSize: 12,
                  color: GloamColors.textTertiary,
                ),
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                contentPadding: EdgeInsets.zero,
                isDense: true,
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: GloamColors.bgElevated,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: GloamColors.border),
            ),
            child: Text(
              '\u2318K',
              style: GoogleFonts.jetBrainsMono(
                fontSize: 10,
                color: GloamColors.textTertiary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Mobile chat screen that auto-pops when the viewport widens past mobile.
class _MobileChatScreen extends StatelessWidget {
  const _MobileChatScreen({required this.roomId});
  final String roomId;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    if (width >= GloamSpacing.breakpointPhone) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (Navigator.of(context).canPop()) {
          Navigator.of(context).pop();
        }
      });
    }
    return ChatScreen(roomId: roomId);
  }
}
