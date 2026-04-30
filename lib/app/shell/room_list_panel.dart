import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:matrix/matrix.dart' show EventTypes, Membership;

import '../theme/gloam_theme_ext.dart';
import '../theme/spacing.dart';
import '../../features/calls/data/adapters/matrix_rtc_adapter.dart';
import '../../features/calls/domain/voice_channel.dart';
import '../../features/calls/presentation/widgets/voice_channel_tile.dart';
import '../../features/chat/presentation/providers/timeline_provider.dart';
import '../../features/chat/presentation/screens/chat_screen.dart';
import '../../features/rooms/presentation/providers/room_list_provider.dart';
import '../../features/rooms/presentation/providers/space_hierarchy_provider.dart';
import '../../features/rooms/presentation/widgets/create_room_dialog.dart';
import '../../features/rooms/presentation/widgets/invite_dialog.dart';
import '../../features/rooms/presentation/widgets/invite_tile.dart';
import '../../features/rooms/presentation/widgets/room_list_tile.dart';
import '../../features/settings/presentation/bootstrap_dialog.dart';
import '../../services/matrix_service.dart';
import '../../services/voice_service.dart';
import '../../widgets/gloam_avatar.dart';
import '../../widgets/section_header.dart';
import 'right_panel.dart';
import 'space_management_modal.dart';
import 'space_rail.dart';

/// Room list panel — shows rooms filtered by the selected space.
class RoomListPanel extends ConsumerStatefulWidget {
  const RoomListPanel({super.key});

  @override
  ConsumerState<RoomListPanel> createState() => _RoomListPanelState();
}

class _RoomListPanelState extends ConsumerState<RoomListPanel> {
  _RoomFilter _filter = _RoomFilter.all;

  void _showRoomContextMenu(
      BuildContext ctx, RoomListItem room, Offset position) {
    final colors = ctx.gloam;
    final overlay =
        Overlay.of(ctx).context.findRenderObject() as RenderBox;
    final relPos = RelativeRect.fromLTRB(
      position.dx, position.dy,
      overlay.size.width - position.dx,
      overlay.size.height - position.dy,
    );

    final client = ref.read(matrixServiceProvider).client;
    final matrixRoom = client?.getRoomById(room.roomId);
    final canInvite = matrixRoom?.canInvite ?? false;

    showMenu<String>(
      context: ctx,
      position: relPos,
      color: colors.bgSurface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: colors.border),
      ),
      items: [
        if (canInvite)
          PopupMenuItem(
            value: 'invite',
            height: 36,
            child: Row(children: [
              Icon(Icons.person_add, size: 14, color: colors.accent),
              const SizedBox(width: 10),
              Text('Invite people',
                  style: TextStyle(fontSize: 13, color: colors.textPrimary)),
            ]),
          ),
        PopupMenuItem(
          value: 'info',
          height: 36,
          child: Row(children: [
            Icon(Icons.info_outline, size: 14, color: colors.textPrimary),
            const SizedBox(width: 10),
            Text('Room info',
                style: TextStyle(fontSize: 13, color: colors.textPrimary)),
          ]),
        ),
        const PopupMenuDivider(),
        PopupMenuItem(
          value: 'leave',
          height: 36,
          child: Row(children: [
            Icon(Icons.logout, size: 14, color: colors.danger),
            const SizedBox(width: 10),
            Text('Leave room',
                style: TextStyle(fontSize: 13, color: colors.danger)),
          ]),
        ),
      ],
    ).then((value) async {
      if (value == null) return;
      switch (value) {
        case 'invite':
          if (ctx.mounted) showInviteDialog(ctx, room.roomId);
        case 'info':
          _selectRoom(room.roomId);
          ref.read(rightPanelProvider.notifier).state =
              const RightPanelState(view: RightPanelView.roomInfo);
        case 'leave':
          if (ctx.mounted) {
            final confirmed = await showDialog<bool>(
              context: ctx,
              builder: (c) => AlertDialog(
                title: Text('Leave ${room.displayName}?'),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(c, false),
                    child: const Text('cancel'),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(c, true),
                    child: const Text('leave'),
                  ),
                ],
              ),
            );
            if (confirmed == true) {
              await matrixRoom?.leave();
              ref.read(selectedRoomProvider.notifier).state = null;
            }
          }
      }
    });
  }

  void _selectRoom(String roomId) {
    ref.read(selectedRoomProvider.notifier).state = roomId;
    ref.read(rightPanelProvider.notifier).state = RightPanelState.closed;

    // On mobile, push chat screen
    final width = MediaQuery.sizeOf(context).width;
    if (width < GloamSpacing.breakpointTablet) {
      ref.read(mobileChatRouteActiveProvider.notifier).state = true;
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => Scaffold(
            backgroundColor: context.gloam.bg,
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

    // Check if the selected space is an invite
    final isSpaceInvite = selectedSpace != null &&
        (() {
          final client = ref.read(matrixServiceProvider).client;
          final room = client?.getRoomById(selectedSpace);
          return room != null &&
              room.isSpace &&
              room.membership == Membership.invite;
        })();

    return Container(
      decoration: BoxDecoration(
        color: context.gloam.bgSurface,
        border: Border(
          right: BorderSide(color: context.gloam.border),
        ),
      ),
      child: isSpaceInvite
          ? _SpaceInviteCard(spaceId: selectedSpace!)
          : Column(
        children: [
          // Header with homeserver name
          _PanelHeader(selectedSpace: selectedSpace),

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
                            ? context.gloam.accentDim
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isActive
                              ? context.gloam.accent
                              : context.gloam.border,
                        ),
                      ),
                      child: Text(
                        f.label,
                        style: GoogleFonts.jetBrainsMono(
                          fontSize: 10,
                          color: isActive
                              ? context.gloam.accent
                              : context.gloam.textTertiary,
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
              loading: () => Center(
                child: CircularProgressIndicator(
                  color: context.gloam.accent,
                  strokeWidth: 2,
                ),
              ),
              error: (e, s) => Center(
                child: Text(
                  '// error loading rooms',
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 11,
                    color: context.gloam.danger,
                  ),
                ),
              ),
              data: (rooms) {
                var filtered =
                    _applyFilters(rooms, _filter, selectedSpace, ref);

                if (filtered.isEmpty) {
                  return Center(
                    child: Text(
                      '// no conversations',
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: 11,
                        color: context.gloam.textTertiary,
                        letterSpacing: 1,
                      ),
                    ),
                  );
                }

                final invites = filtered.where((r) => r.isInvite).toList();
                final dms = filtered.where((r) => r.isDirect && !r.isInvite).toList();
                final channels = filtered
                    .where((r) =>
                        !r.isDirect && !r.isInvite && !_isVoiceChannel(r.roomId, ref))
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
                    // Encryption setup banner
                    _EncryptionBanner(ref: ref),

                    if (invites.isNotEmpty) ...[
                      SectionHeader('invites (${invites.length})',
                          color: context.gloam.accent),
                      ...invites.map((room) => InviteTile(invite: room)),
                    ],
                    if (dms.isNotEmpty) ...[
                      const SectionHeader('direct messages'),
                      ...dms.map((room) => RoomListTile(
                            room: room,
                            isActive: room.roomId == selectedRoom,
                            onTap: () => _selectRoom(room.roomId),
                            onSecondaryTap: (pos) =>
                                _showRoomContextMenu(context, room, pos),
                          )),
                    ],
                    if (channels.isNotEmpty) ...[
                      const SectionHeader('channels'),
                      ...channels.map((room) => RoomListTile(
                            room: room,
                            isActive: room.roomId == selectedRoom,
                            onTap: () => _selectRoom(room.roomId),
                            onSecondaryTap: (pos) =>
                                _showRoomContextMenu(context, room, pos),
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
                    // Unjoined space children
                    if (selectedSpace != null)
                      ..._buildUnjoinedSection(
                        context, ref, selectedSpace!),
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
    _RoomFilter filter,
    String? spaceId,
    WidgetRef ref,
  ) {
    var result = rooms;

    // Space filter — use server-resolved hierarchy for complete child list
    if (spaceId != null) {
      final hierarchyAsync = ref.watch(spaceHierarchyProvider(spaceId));
      final hierarchyData = hierarchyAsync.whenOrNull(
        data: (rooms) => rooms,
      );
      if (hierarchyData != null) {
        final childIds = hierarchyData.map((r) => r.roomId).toSet();
        // Build a name lookup for hierarchy rooms
        final hierarchyNames = <String, String>{};
        for (final hr in hierarchyData) {
          if (hr.name != null) hierarchyNames[hr.roomId] = hr.name!;
        }
        result = result
            .where((r) => r.isInvite || childIds.contains(r.roomId))
            .map((r) {
              // Fix "Empty chat" names using hierarchy data
              if (r.displayName == 'Empty chat' &&
                  hierarchyNames.containsKey(r.roomId)) {
                return r.withDisplayName(hierarchyNames[r.roomId]!);
              }
              return r;
            })
            .toList();
      } else {
        // Hierarchy still loading — fall back to local spaceChildren
        final client = ref.read(matrixServiceProvider).client;
        final space = client?.getRoomById(spaceId);
        if (space != null && space.isSpace) {
          final localIds =
              space.spaceChildren.map((c) => c.roomId).toSet();
          result = result
              .where((r) => r.isInvite || localIds.contains(r.roomId))
              .toList();
        }
      }
    }

    // Resolve "Empty chat" fallback names from hierarchy data
    if (result.any((r) => r.displayName == 'Empty chat')) {
      result = result.map((r) {
        if (r.displayName != 'Empty chat') return r;
        final name = ref.read(hierarchyRoomNameProvider(r.roomId));
        return name != null ? r.withDisplayName(name) : r;
      }).toList();
    }

    // Category filter
    switch (filter) {
      case _RoomFilter.all:
        break;
      case _RoomFilter.unread:
        result = result.where((r) => r.isInvite || r.unreadCount > 0).toList();
      case _RoomFilter.mentions:
        result = result.where((r) => r.isInvite || r.mentionCount > 0).toList();
    }

    return result;
  }

  /// Build the "available rooms" section for unjoined space children.
  List<Widget> _buildUnjoinedSection(
      BuildContext context, WidgetRef ref, String spaceId) {
    final hierarchyAsync = ref.watch(spaceHierarchyProvider(spaceId));
    return hierarchyAsync.when(
      loading: () => [],
      error: (_, __) => [],
      data: (rooms) {
        // Filter out sub-spaces — they're not joinable rooms
        final unjoinable = rooms.where(
            (r) => !r.isJoined && r.roomType != 'm.space');
        final unjoinedRooms = unjoinable
            .where((r) => !_isVoiceChannelType(r.roomType))
            .toList();
        final unjoinedVoice = unjoinable
            .where((r) => _isVoiceChannelType(r.roomType))
            .toList();

        return [
          if (unjoinedRooms.isNotEmpty) ...[
            const SectionHeader('available rooms'),
            ...unjoinedRooms.map((r) => _UnjoinedRoomTile(
                  room: r,
                  onJoin: () => _doJoin(r),
                  onOpenPending: r.joinRule != 'restricted'
                      ? () => _selectRoom(r.roomId)
                      : null,
                )),
          ],
          if (unjoinedVoice.isNotEmpty) ...[
            const SectionHeader('available voice channels'),
            ...unjoinedVoice.map((r) => _UnjoinedRoomTile(
                  room: r,
                  isVoice: true,
                  onJoin: () => _doJoin(r),
                  onOpenPending: r.joinRule != 'restricted'
                      ? () => _selectRoom(r.roomId)
                      : null,
                )),
          ],
        ];
      },
    );
  }

  bool _isVoiceChannelType(String? roomType) {
    return roomType == 'im.gloam.voice_channel' ||
        roomType == 'org.matrix.msc3417.call';
  }

  /// Fire-and-forget join. Returns null on success, error message on failure.
  Future<String?> _doJoin(SpaceRoom spaceRoom) async {
    final client = ref.read(matrixServiceProvider).client;
    if (client == null) return 'not connected';
    try {
      await client.joinRoom(
        spaceRoom.roomId,
        serverName: spaceRoom.viaServers.isNotEmpty
            ? spaceRoom.viaServers
            : null,
      );
      return null; // success
    } catch (e) {
      final msg = e.toString().toLowerCase();
      if (msg.contains('forbidden') || msg.contains('403')) {
        return 'no access';
      }
      if (msg.contains('not invited') || msg.contains('invite')) {
        return 'invite required';
      }
      return 'failed to join';
    }
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

    // Filter by selected space using hierarchy
    if (selectedSpace != null) {
      final hierarchyAsync = ref.watch(spaceHierarchyProvider(selectedSpace));
      final childIds = hierarchyAsync.whenOrNull(
        data: (spaceRooms) => spaceRooms.map((r) => r.roomId).toSet(),
      );
      if (childIds != null) {
        rooms = rooms.where((r) => childIds.contains(r.id)).toList();
      } else {
        final space = client.getRoomById(selectedSpace);
        if (space != null && space.isSpace) {
          final localIds = space.spaceChildren.map((c) => c.roomId).toSet();
          rooms = rooms.where((r) => localIds.contains(r.id)).toList();
        }
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

/// Rich invite card shown when an invited space is selected in the space rail.
class _SpaceInviteCard extends ConsumerStatefulWidget {
  const _SpaceInviteCard({required this.spaceId});
  final String spaceId;

  @override
  ConsumerState<_SpaceInviteCard> createState() => _SpaceInviteCardState();
}

class _SpaceInviteCardState extends ConsumerState<_SpaceInviteCard> {
  bool _loading = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.gloam;
    final client = ref.watch(matrixServiceProvider).client;
    final room = client?.getRoomById(widget.spaceId);

    if (room == null || client == null) return const SizedBox.shrink();

    final spaceName = room.getLocalizedDisplayname();
    final topic = room.topic;

    // Resolve inviter from the membership event
    final myMemberEvent =
        room.getState(EventTypes.RoomMember, client.userID!);
    final inviterId = myMemberEvent?.senderId;
    String? inviterName;
    Uri? inviterAvatar;
    if (inviterId != null) {
      final inviter = room.unsafeGetUserFromMemoryOrFallback(inviterId);
      inviterName = inviter.calcDisplayname();
      inviterAvatar = inviter.avatarUrl;
    }

    // Member count from summary
    final memberCount = room.summary.mJoinedMemberCount ?? 0;

    // Best-effort channel preview via hierarchy
    final hierarchyAsync = ref.watch(spaceHierarchyProvider(widget.spaceId));

    return Column(
      children: [
        // Header
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(color: colors.border),
            ),
          ),
          child: Row(
            children: [
              Text(
                'space invite',
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 11,
                  color: colors.accent,
                  letterSpacing: 1,
                ),
              ),
            ],
          ),
        ),

        // Card content
        Expanded(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Large space avatar
                  GloamAvatar(
                    displayName: spaceName,
                    mxcUrl: room.avatar,
                    size: 72,
                    borderRadius: 16,
                  ),
                  const SizedBox(height: 16),

                  // Space name
                  Text(
                    spaceName,
                    style: GoogleFonts.inter(
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                      color: colors.textPrimary,
                    ),
                    textAlign: TextAlign.center,
                  ),

                  // Topic
                  if (topic != null && topic.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      topic,
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        color: colors.textSecondary,
                        height: 1.4,
                      ),
                      textAlign: TextAlign.center,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],

                  const SizedBox(height: 16),

                  // Inviter row
                  if (inviterName != null)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: colors.bgElevated,
                        borderRadius:
                            BorderRadius.circular(GloamSpacing.radiusSm),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          GloamAvatar(
                            displayName: inviterName,
                            mxcUrl: inviterAvatar,
                            size: 24,
                            borderRadius: 12,
                          ),
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text.rich(
                              TextSpan(children: [
                                TextSpan(
                                  text: inviterName,
                                  style: GoogleFonts.inter(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w500,
                                    color: colors.textPrimary,
                                  ),
                                ),
                                TextSpan(
                                  text: ' invited you',
                                  style: GoogleFonts.inter(
                                    fontSize: 13,
                                    color: colors.textSecondary,
                                  ),
                                ),
                              ]),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),

                  const SizedBox(height: 12),

                  // Member count
                  if (memberCount > 0)
                    Text(
                      '$memberCount ${memberCount == 1 ? 'member' : 'members'}',
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: 11,
                        color: colors.textTertiary,
                      ),
                    ),

                  // Channel preview (best-effort)
                  hierarchyAsync.when(
                    loading: () => Padding(
                      padding: const EdgeInsets.only(top: 16),
                      child: Text(
                        '// loading channels...',
                        style: GoogleFonts.jetBrainsMono(
                          fontSize: 11,
                          color: colors.textTertiary,
                        ),
                      ),
                    ),
                    error: (_, __) => const SizedBox.shrink(),
                    data: (channels) {
                      if (channels.isEmpty) return const SizedBox.shrink();
                      return Padding(
                        padding: const EdgeInsets.only(top: 16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${channels.length} ${channels.length == 1 ? 'channel' : 'channels'}',
                              style: GoogleFonts.jetBrainsMono(
                                fontSize: 10,
                                color: colors.textTertiary,
                                letterSpacing: 1,
                              ),
                            ),
                            const SizedBox(height: 8),
                            ...channels.take(8).map((ch) => Padding(
                                  padding:
                                      const EdgeInsets.only(bottom: 4),
                                  child: Row(
                                    children: [
                                      Text(
                                        '#',
                                        style: GoogleFonts.jetBrainsMono(
                                          fontSize: 12,
                                          color: colors.textTertiary,
                                        ),
                                      ),
                                      const SizedBox(width: 4),
                                      Expanded(
                                        child: Text(
                                          ch.name ?? ch.roomId,
                                          style: GoogleFonts.inter(
                                            fontSize: 13,
                                            color: colors.textSecondary,
                                          ),
                                          overflow:
                                              TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ],
                                  ),
                                )),
                            if (channels.length > 8)
                              Text(
                                '+ ${channels.length - 8} more',
                                style: GoogleFonts.jetBrainsMono(
                                  fontSize: 11,
                                  color: colors.textTertiary,
                                ),
                              ),
                          ],
                        ),
                      );
                    },
                  ),

                  const SizedBox(height: 24),

                  // Accept button (prominent)
                  SizedBox(
                    width: double.infinity,
                    child: MouseRegion(
                      cursor: SystemMouseCursors.click,
                      child: GestureDetector(
                        onTap: _loading ? null : () => _accept(room),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          decoration: BoxDecoration(
                            color: colors.accent,
                            borderRadius: BorderRadius.circular(
                                GloamSpacing.radiusSm),
                          ),
                          child: Center(
                            child: _loading
                                ? SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: colors.bg,
                                    ),
                                  )
                                : Text(
                                    'Join Space',
                                    style: GoogleFonts.inter(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                      color: colors.bg,
                                    ),
                                  ),
                          ),
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 8),

                  // Decline link (subtle)
                  MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: GestureDetector(
                      onTap: _loading ? null : () => _decline(room),
                      child: Text(
                        'Decline',
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          color: colors.textTertiary,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _accept(dynamic room) async {
    setState(() => _loading = true);
    try {
      await room.join();
      // Stay selected — panel will transition to normal channel list
      // once the sync picks up the joined state
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to join: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _decline(dynamic room) async {
    setState(() => _loading = true);
    try {
      await room.leave();
      // Reset selection back to DMs
      ref.read(selectedSpaceProvider.notifier).state = null;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to decline: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }
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
                color: context.gloam.textSecondary,
                letterSpacing: 1.5,
              ),
            ),
          ),
          if (selectedSpace != null)
            GestureDetector(
              onTap: () =>
                  showSpaceManagementModal(context, selectedSpace!),
              child: MouseRegion(
                cursor: SystemMouseCursors.click,
                child: Icon(Icons.settings,
                    size: 16, color: context.gloam.textSecondary),
              ),
            ),
          if (selectedSpace != null) const SizedBox(width: 12),
          GestureDetector(
            onTap: () async {
              final spaceId = ref.read(selectedSpaceProvider);
              final roomId = await showCreateRoomDialog(
                context,
                parentSpaceId: spaceId,
              );
              if (roomId != null) {
                ref.read(selectedRoomProvider.notifier).state = roomId;
              }
            },
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: Icon(Icons.add,
                  size: 18, color: context.gloam.textSecondary),
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

enum _JoinState { idle, joining, pending, failed }

/// Tile for an unjoined space child room with join-rule-aware affordances.
class _UnjoinedRoomTile extends StatefulWidget {
  const _UnjoinedRoomTile({
    required this.room,
    required this.onJoin,
    this.onOpenPending,
    this.isVoice = false,
  });

  final SpaceRoom room;
  /// Returns null on success, error message on failure.
  final Future<String?> Function() onJoin;
  final VoidCallback? onOpenPending;
  final bool isVoice;

  @override
  State<_UnjoinedRoomTile> createState() => _UnjoinedRoomTileState();
}

class _UnjoinedRoomTileState extends State<_UnjoinedRoomTile> {
  _JoinState _state = _JoinState.idle;
  String? _error;

  Future<void> _handleTap() async {
    if (_state == _JoinState.joining) return;

    // Pending = already joined but waiting for sync, tap to open
    if (_state == _JoinState.pending) {
      widget.onOpenPending?.call();
      return;
    }

    // Failed = tap to retry
    // Idle = tap to join
    setState(() {
      _state = _JoinState.joining;
      _error = null;
    });

    final error = await widget.onJoin();

    if (!mounted) return;

    if (error != null) {
      setState(() {
        _state = _JoinState.failed;
        _error = error;
      });
    } else {
      // Join API succeeded — room may take a moment to appear in sync
      setState(() => _state = _JoinState.pending);
      // Only navigate for non-restricted rooms (restricted = waiting for approval)
      widget.onOpenPending?.call();
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.gloam;
    final room = widget.room;
    final name = room.name ?? room.roomId;
    final memberText =
        '${room.numJoinedMembers} ${room.numJoinedMembers == 1 ? 'member' : 'members'}';
    final inviteOnly = room.isInviteOnly;

    return GestureDetector(
      onTap: inviteOnly ? null : _handleTap,
      child: MouseRegion(
        cursor: inviteOnly
            ? SystemMouseCursors.basic
            : SystemMouseCursors.click,
        child: Container(
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          margin: const EdgeInsets.symmetric(vertical: 1),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(GloamSpacing.radiusSm),
          ),
          child: Row(
            children: [
              // Room icon
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: colors.bgElevated,
                  borderRadius: BorderRadius.circular(
                      widget.isVoice ? 14 : GloamSpacing.radiusSm),
                ),
                child: Icon(
                  widget.isVoice
                      ? Icons.volume_up_outlined
                      : inviteOnly
                          ? Icons.lock_outline
                          : Icons.tag,
                  size: 14,
                  color: colors.textTertiary,
                ),
              ),
              const SizedBox(width: 10),
              // Name + subtitle
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        color: inviteOnly
                            ? colors.textTertiary.withValues(alpha: 0.5)
                            : colors.textTertiary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      memberText,
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: 9,
                        color: colors.textTertiary,
                      ),
                    ),
                  ],
                ),
              ),
              // Action indicator
              _buildAction(colors, inviteOnly),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAction(dynamic colors, bool inviteOnly) {
    if (inviteOnly) {
      return Text(
        'invite only',
        style: GoogleFonts.jetBrainsMono(
          fontSize: 9,
          color: colors.textTertiary,
        ),
      );
    }

    final isRestricted = widget.room.joinRule == 'restricted';
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 150),
      child: switch (_state) {
        _JoinState.idle => _actionLabel(
            isRestricted ? 'request' : 'join',
            colors.accent,
          ),
        _JoinState.joining => SizedBox(
            key: const ValueKey('joining'),
            width: 14,
            height: 14,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: colors.accent,
            ),
          ),
        _JoinState.pending => _actionLabel(
            isRestricted ? 'requested' : 'syncing',
            isRestricted ? colors.info : colors.warning,
          ),
        _JoinState.failed => _actionLabel(_error ?? 'failed', colors.danger),
      },
    );
  }

  Widget _actionLabel(String text, Color color) {
    return Text(
      text,
      key: ValueKey(text),
      style: GoogleFonts.jetBrainsMono(
        fontSize: 9,
        color: color,
        fontWeight: FontWeight.w500,
      ),
    );
  }
}

/// Banner prompting encryption setup. Hidden when already bootstrapped
/// or explicitly dismissed.
class _EncryptionBanner extends ConsumerStatefulWidget {
  const _EncryptionBanner({required this.ref});
  final WidgetRef ref;

  @override
  ConsumerState<_EncryptionBanner> createState() => _EncryptionBannerState();
}

class _EncryptionBannerState extends ConsumerState<_EncryptionBanner> {
  bool _dismissed = false;

  @override
  Widget build(BuildContext context) {
    if (_dismissed) return const SizedBox.shrink();

    final client = ref.watch(matrixServiceProvider).client;
    if (client == null) return const SizedBox.shrink();

    // Already bootstrapped — cross-signing is set up
    final crossSigningEnabled = client.encryption?.crossSigning.enabled ?? false;
    if (crossSigningEnabled) return const SizedBox.shrink();

    // Not logged in yet
    if (!client.isLogged()) return const SizedBox.shrink();

    final colors = context.gloam;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: colors.accentDim,
          borderRadius: BorderRadius.circular(GloamSpacing.radiusSm),
        ),
        child: Row(
          children: [
            Icon(Icons.lock_outlined, size: 14, color: colors.accentBright),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Set up encryption to secure your messages',
                style: GoogleFonts.inter(
                  fontSize: 12, color: colors.accentBright,
                ),
              ),
            ),
            const SizedBox(width: 4),
            MouseRegion(
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
                onTap: () => showBootstrapDialog(context),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: colors.accent,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    'Set up',
                    style: GoogleFonts.inter(
                      fontSize: 11, fontWeight: FontWeight.w600, color: colors.bg,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 4),
            MouseRegion(
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
                onTap: () => setState(() => _dismissed = true),
                child: Icon(Icons.close, size: 14, color: colors.accentBright),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
