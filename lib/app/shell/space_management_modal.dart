import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:matrix/matrix.dart';

import '../theme/gloam_theme_ext.dart';
import '../theme/spacing.dart';
import '../../features/chat/presentation/providers/timeline_provider.dart';
import '../../features/rooms/presentation/providers/space_hierarchy_provider.dart';
import '../../features/rooms/presentation/widgets/create_room_dialog.dart';
import '../../features/rooms/presentation/widgets/invite_dialog.dart';
import '../../services/matrix_service.dart';
import '../../widgets/gloam_avatar.dart';
import 'right_panel.dart';

/// Full-screen modal for managing a space — rooms, members, settings.
class SpaceManagementModal extends ConsumerStatefulWidget {
  const SpaceManagementModal({super.key, required this.spaceId});
  final String spaceId;

  @override
  ConsumerState<SpaceManagementModal> createState() =>
      _SpaceManagementModalState();
}

class _SpaceManagementModalState extends ConsumerState<SpaceManagementModal>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.gloam;
    final client = ref.watch(matrixServiceProvider).client;
    final space = client?.getRoomById(widget.spaceId);
    if (space == null) return const SizedBox.shrink();

    final name = space.getLocalizedDisplayname();

    return Dialog(
      backgroundColor: colors.bgSurface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(GloamSpacing.radiusLg),
        side: BorderSide(color: colors.border),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560, maxHeight: 600),
        child: Column(
          children: [
            // Header
            Container(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
              child: Row(
                children: [
                  GloamAvatar(
                    displayName: name,
                    size: 36,
                    borderRadius: 10,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          style: GoogleFonts.inter(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: colors.textPrimary,
                          ),
                        ),
                        if (space.topic.isNotEmpty)
                          Text(
                            space.topic,
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              color: colors.textTertiary,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: Icon(Icons.close,
                        size: 18, color: colors.textTertiary),
                    hoverColor: colors.border.withValues(alpha: 0.5),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Tabs
            Container(
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: colors.border),
                ),
              ),
              child: TabBar(
                controller: _tabController,
                labelColor: colors.accent,
                unselectedLabelColor: colors.textTertiary,
                indicatorColor: colors.accent,
                indicatorSize: TabBarIndicatorSize.label,
                labelStyle: GoogleFonts.jetBrainsMono(
                  fontSize: 12,
                  letterSpacing: 0.5,
                ),
                tabs: const [
                  Tab(text: 'rooms'),
                  Tab(text: 'members'),
                  Tab(text: 'settings'),
                ],
              ),
            ),

            // Tab content
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _RoomsTab(space: space, spaceId: widget.spaceId),
                  _MembersTab(space: space, spaceId: widget.spaceId),
                  _SettingsTab(space: space),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Rooms Tab ──

class _RoomsTab extends ConsumerWidget {
  const _RoomsTab({required this.space, required this.spaceId});
  final Room space;
  final String spaceId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.gloam;
    final hierarchyAsync = ref.watch(spaceHierarchyProvider(spaceId));
    final canManage = space.ownPowerLevel >= 50;

    return hierarchyAsync.when(
      loading: () => Center(
        child: CircularProgressIndicator(
            strokeWidth: 2, color: colors.accent),
      ),
      error: (_, __) => Center(
        child: Text('// failed to load rooms',
            style: GoogleFonts.jetBrainsMono(
                fontSize: 11, color: colors.textTertiary)),
      ),
      data: (rooms) => ListView(
        padding: const EdgeInsets.all(16),
        children: [
          ...rooms.map((room) => Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Material(
                  color: Colors.transparent,
                  borderRadius: BorderRadius.circular(6),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(6),
                    hoverColor: colors.border.withValues(alpha: 0.3),
                    onTap: room.isJoined
                        ? () {
                            // Navigate to the room and open info panel
                            ref.read(selectedRoomProvider.notifier).state =
                                room.roomId;
                            ref.read(rightPanelProvider.notifier).state =
                                const RightPanelState(
                                    view: RightPanelView.roomInfo);
                            Navigator.pop(context);
                          }
                        : null,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 8),
                      child: Row(
                        children: [
                          Text(
                            room.roomType == 'org.matrix.msc3417.call'
                                ? '\u{1F50A}'
                                : '#',
                            style: GoogleFonts.jetBrainsMono(
                              fontSize: 14,
                              color: colors.textTertiary,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment:
                                  CrossAxisAlignment.start,
                              children: [
                                Text(
                                  room.name ?? room.roomId,
                                  style: GoogleFonts.inter(
                                    fontSize: 13,
                                    color: colors.textPrimary,
                                  ),
                                ),
                                Text(
                                  room.isJoined
                                      ? '${ref.read(matrixServiceProvider).client?.getRoomById(room.roomId)?.summary.mJoinedMemberCount ?? room.numJoinedMembers} members'
                                      : 'not joined',
                                  style: GoogleFonts.jetBrainsMono(
                                    fontSize: 10,
                                    color: colors.textTertiary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (!room.isJoined && room.isJoinable)
                            _ActionChip(
                              label: 'join',
                              color: colors.accent,
                              onTap: () async {
                                final client =
                                    ref.read(matrixServiceProvider).client;
                                await client?.joinRoom(
                                  room.roomId,
                                  serverName: room.viaServers,
                                );
                              },
                            ),
                          if (room.isJoined && canManage)
                            IconButton(
                              onPressed: () async {
                                final confirmed =
                                    await showDialog<bool>(
                                  context: context,
                                  builder: (ctx) => AlertDialog(
                                    title: Text(
                                        'Remove ${room.name ?? room.roomId}?'),
                                    content: const Text(
                                        'This room will be unlinked from the space.'),
                                    actions: [
                                      TextButton(
                                        onPressed: () =>
                                            Navigator.pop(ctx, false),
                                        child: const Text('cancel'),
                                      ),
                                      TextButton(
                                        onPressed: () =>
                                            Navigator.pop(ctx, true),
                                        child: const Text('remove'),
                                      ),
                                    ],
                                  ),
                                );
                                if (confirmed == true) {
                                  await space
                                      .removeSpaceChild(room.roomId);
                                }
                              },
                              icon: Icon(Icons.close,
                                  size: 12, color: colors.danger),
                              hoverColor: colors.border
                                  .withValues(alpha: 0.5),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(
                                  minWidth: 24, minHeight: 24),
                              tooltip: 'Remove from space',
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              )),
          if (canManage) ...[
            const SizedBox(height: 8),
            Divider(color: colors.border),
            const SizedBox(height: 4),
            Material(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(6),
              child: InkWell(
                borderRadius: BorderRadius.circular(6),
                hoverColor: colors.border.withValues(alpha: 0.3),
                onTap: () async {
                  await showCreateRoomDialog(
                    context,
                    parentSpaceId: space.id,
                  );
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 8),
                  child: Row(
                    children: [
                      Icon(Icons.add, size: 16, color: colors.accent),
                      const SizedBox(width: 10),
                      Text('create new room',
                          style: GoogleFonts.jetBrainsMono(
                            fontSize: 12,
                            color: colors.accent,
                            letterSpacing: 0.5,
                          )),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ── Members Tab ──

class _MembersTab extends ConsumerStatefulWidget {
  const _MembersTab({required this.space, required this.spaceId});
  final Room space;
  final String spaceId;

  @override
  ConsumerState<_MembersTab> createState() => _MembersTabState();
}

class _MembersTabState extends ConsumerState<_MembersTab> {
  List<User> _members = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadMembers();
  }

  Future<void> _loadMembers() async {
    try {
      final members = await widget.space.requestParticipants();
      if (mounted) {
        setState(() {
          _members = members
              .where((m) => m.membership == Membership.join)
              .toList();
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.gloam;

    if (_loading) {
      return Center(
        child: CircularProgressIndicator(
            strokeWidth: 2, color: colors.accent),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (widget.space.canInvite)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Material(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(6),
              child: InkWell(
                borderRadius: BorderRadius.circular(6),
                hoverColor: colors.border.withValues(alpha: 0.3),
                onTap: () => showInviteDialog(context, widget.spaceId),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                  child: Row(
                    children: [
                      Icon(Icons.person_add,
                          size: 16, color: colors.accent),
                      const SizedBox(width: 10),
                      Text('invite to space',
                          style: GoogleFonts.jetBrainsMono(
                            fontSize: 12,
                            color: colors.accent,
                            letterSpacing: 0.5,
                          )),
                    ],
                  ),
                ),
              ),
            ),
          ),
        Text(
          '// ${_members.length} members',
          style: GoogleFonts.jetBrainsMono(
            fontSize: 10,
            color: colors.textTertiary,
            letterSpacing: 1,
          ),
        ),
        const SizedBox(height: 8),
        ..._members.map((m) => Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                child: Row(
                  children: [
                    GloamAvatar(
                      displayName: m.calcDisplayname(),
                      mxcUrl: m.avatarUrl,
                      size: 28,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        m.calcDisplayname(),
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          color: colors.textPrimary,
                        ),
                      ),
                    ),
                    if (m.powerLevel >= 100)
                      _RoleBadge(label: 'admin', color: colors.accent,
                          bgColor: colors.accentDim)
                    else if (m.powerLevel >= 50)
                      _RoleBadge(label: 'mod', color: colors.info,
                          bgColor: const Color(0xFF1A2540)),
                  ],
                ),
              ),
            )),
      ],
    );
  }
}

// ── Settings Tab ──

class _SettingsTab extends StatelessWidget {
  const _SettingsTab({required this.space});
  final Room space;

  @override
  Widget build(BuildContext context) {
    final colors = context.gloam;
    final canEdit = space.ownPowerLevel >= 50;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (canEdit) ...[
          _SettingRow(
            label: 'space name',
            value: space.getLocalizedDisplayname(),
            onTap: () async {
              final controller = TextEditingController(
                  text: space.getLocalizedDisplayname());
              final result = await showDialog<String>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('Edit space name'),
                  content: TextField(
                      controller: controller, autofocus: true),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('cancel'),
                    ),
                    TextButton(
                      onPressed: () =>
                          Navigator.pop(ctx, controller.text.trim()),
                      child: const Text('save'),
                    ),
                  ],
                ),
              );
              if (result != null && result.isNotEmpty) {
                await space.setName(result);
              }
            },
          ),
          const SizedBox(height: 8),
          _SettingRow(
            label: 'topic',
            value: space.topic.isEmpty ? 'not set' : space.topic,
            onTap: () async {
              final controller =
                  TextEditingController(text: space.topic);
              final result = await showDialog<String>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('Edit topic'),
                  content: TextField(
                    controller: controller,
                    autofocus: true,
                    maxLines: 3,
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('cancel'),
                    ),
                    TextButton(
                      onPressed: () =>
                          Navigator.pop(ctx, controller.text.trim()),
                      child: const Text('save'),
                    ),
                  ],
                ),
              );
              if (result != null) {
                await space.setDescription(result);
              }
            },
          ),
        ],
        if (!canEdit)
          Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Text(
                '// you need moderator permissions to edit settings',
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 11,
                  color: colors.textTertiary,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ),
      ],
    );
  }
}

// ── Shared Widgets ──

class _ActionChip extends StatelessWidget {
  const _ActionChip({
    required this.label,
    required this.color,
    required this.onTap,
  });
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: color),
          ),
          child: Text(label,
              style: GoogleFonts.jetBrainsMono(
                fontSize: 11, color: color, letterSpacing: 0.5)),
        ),
      ),
    );
  }
}

class _RoleBadge extends StatelessWidget {
  const _RoleBadge({
    required this.label,
    required this.color,
    required this.bgColor,
  });
  final String label;
  final Color color;
  final Color bgColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(label,
          style: GoogleFonts.jetBrainsMono(
            fontSize: 9, color: color, letterSpacing: 0.5)),
    );
  }
}

class _SettingRow extends StatelessWidget {
  const _SettingRow({
    required this.label,
    required this.value,
    required this.onTap,
  });
  final String label;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.gloam;
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(6),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        hoverColor: colors.border.withValues(alpha: 0.3),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label,
                        style: GoogleFonts.jetBrainsMono(
                          fontSize: 10,
                          color: colors.textTertiary,
                          letterSpacing: 1,
                        )),
                    const SizedBox(height: 4),
                    Text(value,
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          color: colors.textPrimary,
                        )),
                  ],
                ),
              ),
              Icon(Icons.edit, size: 14, color: colors.textTertiary),
            ],
          ),
        ),
      ),
    );
  }
}

/// Shows the space management modal.
Future<void> showSpaceManagementModal(
    BuildContext context, String spaceId) {
  return showDialog(
    context: context,
    barrierColor: context.gloam.overlay,
    builder: (_) => SpaceManagementModal(spaceId: spaceId),
  );
}
