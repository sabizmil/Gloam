import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:matrix/matrix.dart' show PushRuleState;

import '../theme/gloam_theme_ext.dart';
import '../theme/spacing.dart';
import '../../features/chat/presentation/providers/timeline_provider.dart';
import '../../features/profile/presentation/user_profile_modal.dart';
import '../../features/rooms/presentation/widgets/invite_dialog.dart';
import '../../services/matrix_service.dart';
import '../../widgets/gloam_avatar.dart';
import 'right_panel.dart';

/// Right panel showing room details, members, and settings links.
class RoomInfoPanel extends ConsumerWidget {
  const RoomInfoPanel({
    super.key,
    required this.roomId,
    required this.onClose,
  });

  final String roomId;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final client = ref.watch(matrixServiceProvider).client;
    final room = client?.getRoomById(roomId);
    if (room == null) return const SizedBox.shrink();

    final members = room.getParticipants();
    final name = room.getLocalizedDisplayname();
    final topic = room.topic;

    return Container(
      width: GloamSpacing.rightPanelWidth,
      decoration: BoxDecoration(
        color: context.gloam.bgSurface,
        border: Border(
          left: BorderSide(color: context.gloam.border),
        ),
      ),
      child: Column(
        children: [
          // Header
          Container(
            height: GloamSpacing.headerHeight,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(color: context.gloam.border),
              ),
            ),
            child: Row(
              children: [
                Text(
                  'room info',
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: context.gloam.textPrimary,
                    letterSpacing: 0.5,
                  ),
                ),
                const Spacer(),
                IconButton(
                  onPressed: onClose,
                  icon: Icon(Icons.close,
                      size: 16, color: context.gloam.textTertiary),
                  hoverColor: context.gloam.border.withValues(alpha: 0.5),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                ),
              ],
            ),
          ),

          // Content
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                // Room avatar + name
                Center(
                  child: Column(
                    children: [
                      GloamAvatar(
                        displayName: name,
                        size: 64,
                        borderRadius: 16,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        name,
                        style: GoogleFonts.inter(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          color: context.gloam.textPrimary,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      if (topic.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          topic,
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            color: context.gloam.textSecondary,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                // Details section
                Text(
                  '// details',
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 10,
                    color: context.gloam.textTertiary,
                    letterSpacing: 1,
                  ),
                ),
                const SizedBox(height: 12),
                _DetailRow(
                  label: 'encryption',
                  value: room.encrypted ? 'enabled' : 'disabled',
                  valueColor:
                      room.encrypted ? context.gloam.accent : context.gloam.textSecondary,
                  icon: room.encrypted ? Icons.lock : Icons.lock_open,
                ),
                const SizedBox(height: 8),
                _NotificationSettingRow(room: room),
                const SizedBox(height: 24),

                // Members section
                Row(
                  children: [
                    Text(
                      '// members \u2014 ${members.length}',
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: 10,
                        color: context.gloam.textTertiary,
                        letterSpacing: 1,
                      ),
                    ),
                    const Spacer(),
                    if (room.canInvite)
                      IconButton(
                        onPressed: () => showInviteDialog(context, roomId),
                        icon: Icon(Icons.person_add,
                            size: 14, color: context.gloam.accent),
                        tooltip: 'Invite',
                        hoverColor: context.gloam.border.withValues(alpha: 0.5),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(
                            minWidth: 24, minHeight: 24),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                ...members.take(20).map((m) => _MemberRow(
                      member: m,
                      room: room,
                      roomId: roomId,
                      myPowerLevel: room.ownPowerLevel,
                    )),

                // Space rooms section (only for spaces)
                if (room.isSpace) ...[
                  const SizedBox(height: 24),
                  Text(
                    '// rooms in space',
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 10,
                      color: context.gloam.textTertiary,
                      letterSpacing: 1,
                    ),
                  ),
                  const SizedBox(height: 12),
                  ...room.spaceChildren
                      .where((c) => c.roomId != null)
                      .map((child) {
                    final childRoom = client?.getRoomById(child.roomId!);
                    final childName = childRoom?.getLocalizedDisplayname() ??
                        child.roomId ?? 'Unknown';
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Row(
                        children: [
                          Text('#',
                              style: GoogleFonts.jetBrainsMono(
                                fontSize: 14,
                                color: context.gloam.textTertiary,
                              )),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              childName,
                              style: GoogleFonts.inter(
                                fontSize: 13,
                                color: context.gloam.textPrimary,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (room.ownPowerLevel >= 50)
                            IconButton(
                              onPressed: () async {
                                final confirmed = await showDialog<bool>(
                                  context: context,
                                  builder: (ctx) => AlertDialog(
                                    title: Text('Remove $childName?'),
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
                                if (confirmed == true && child.roomId != null) {
                                  await room.removeSpaceChild(child.roomId!);
                                }
                              },
                              icon: Icon(Icons.close,
                                  size: 12,
                                  color: context.gloam.danger),
                              hoverColor:
                                  context.gloam.border.withValues(alpha: 0.5),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(
                                  minWidth: 24, minHeight: 24),
                              tooltip: 'Remove from space',
                            ),
                        ],
                      ),
                    );
                  }),
                ],

                // Room settings (if admin/mod)
                if (room.ownPowerLevel >= 50) ...[
                  const SizedBox(height: 24),
                  Text(
                    '// settings',
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 10,
                      color: context.gloam.textTertiary,
                      letterSpacing: 1,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _SettingsButton(
                    icon: Icons.edit,
                    label: 'edit room name',
                    onTap: () => _editRoomName(context, room),
                  ),
                  const SizedBox(height: 4),
                  _SettingsButton(
                    icon: Icons.short_text,
                    label: 'edit topic',
                    onTap: () => _editRoomTopic(context, room),
                  ),
                ],

                // Leave room
                const SizedBox(height: 24),
                Text(
                  '// actions',
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 10,
                    color: context.gloam.textTertiary,
                    letterSpacing: 1,
                  ),
                ),
                const SizedBox(height: 12),
                if (room.canInvite)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: _SettingsButton(
                      icon: Icons.person_add,
                      label: 'invite people',
                      color: context.gloam.accent,
                      onTap: () => showInviteDialog(context, roomId),
                    ),
                  ),
                _LeaveRoomButton(roomId: roomId),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _NotificationSettingRow extends StatefulWidget {
  const _NotificationSettingRow({required this.room});
  final dynamic room; // Room from matrix SDK

  @override
  State<_NotificationSettingRow> createState() =>
      _NotificationSettingRowState();
}

class _NotificationSettingRowState extends State<_NotificationSettingRow> {
  PushRuleState _pushRule = PushRuleState.mentionsOnly;

  @override
  void initState() {
    super.initState();
    _pushRule = widget.room.pushRuleState;
  }

  @override
  Widget build(BuildContext context) {
    final label = switch (_pushRule) {
      PushRuleState.notify => 'all messages',
      PushRuleState.mentionsOnly => 'mentions only',
      PushRuleState.dontNotify => 'muted',
    };
    final icon = switch (_pushRule) {
      PushRuleState.notify => Icons.notifications_active_outlined,
      PushRuleState.mentionsOnly => Icons.alternate_email,
      PushRuleState.dontNotify => Icons.notifications_off_outlined,
    };

    return GestureDetector(
      onTap: () async {
        final picked = await _showNotificationPicker(context, widget.room);
        if (mounted && picked != null) {
          setState(() => _pushRule = picked);
        }
      },
      child: _DetailRow(
        label: 'notifications',
        value: label,
        icon: icon,
        trailing: Icon(Icons.chevron_right,
            size: 14, color: context.gloam.textTertiary),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.label,
    required this.value,
    this.valueColor,
    this.icon,
    this.trailing,
  });

  final String label;
  final String value;
  final Color? valueColor;
  final IconData? icon;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: GoogleFonts.jetBrainsMono(
            fontSize: 11,
            color: context.gloam.textSecondary,
          ),
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 12, color: valueColor ?? context.gloam.textSecondary),
              const SizedBox(width: 4),
            ],
            Text(
              value,
              style: GoogleFonts.jetBrainsMono(
                fontSize: 11,
                color: valueColor ?? context.gloam.textSecondary,
              ),
            ),
            if (trailing != null) ...[
              const SizedBox(width: 4),
              trailing!,
            ],
          ],
        ),
      ],
    );
  }
}

Future<PushRuleState?> _showNotificationPicker(BuildContext context, dynamic room) {
  return showModalBottomSheet<PushRuleState>(
    context: context,
    backgroundColor: context.gloam.bgSurface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(
          top: Radius.circular(GloamSpacing.radiusLg)),
    ),
    builder: (_) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
              child: Text(
                '// notification settings',
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 10,
                  color: context.gloam.textTertiary,
                  letterSpacing: 1,
                ),
              ),
            ),
            _PushRuleOption(
              icon: Icons.notifications_active_outlined,
              label: 'All messages',
              subtitle: 'Notify for every new message',
              isSelected: room.pushRuleState == PushRuleState.notify,
              onTap: () {
                Navigator.pop(context, PushRuleState.notify);
                room.setPushRuleState(PushRuleState.notify);
              },
            ),
            _PushRuleOption(
              icon: Icons.alternate_email,
              label: 'Mentions only',
              subtitle: 'Only when you\'re @mentioned',
              isSelected: room.pushRuleState == PushRuleState.mentionsOnly,
              onTap: () {
                Navigator.pop(context, PushRuleState.mentionsOnly);
                room.setPushRuleState(PushRuleState.mentionsOnly);
              },
            ),
            _PushRuleOption(
              icon: Icons.notifications_off_outlined,
              label: 'Mute',
              subtitle: 'No notifications from this room',
              isSelected: room.pushRuleState == PushRuleState.dontNotify,
              onTap: () {
                Navigator.pop(context, PushRuleState.dontNotify);
                room.setPushRuleState(PushRuleState.dontNotify);
              },
            ),
          ],
        ),
      ),
    ),
  );
}

class _PushRuleOption extends StatelessWidget {
  const _PushRuleOption({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.isSelected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String subtitle;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          child: Row(
            children: [
              Icon(
                icon,
                size: 20,
                color: isSelected
                    ? context.gloam.accent
                    : context.gloam.textSecondary,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: GoogleFonts.inter(
                        fontSize: 14,
                        fontWeight:
                            isSelected ? FontWeight.w500 : FontWeight.w400,
                        color: isSelected
                            ? context.gloam.accent
                            : context.gloam.textPrimary,
                      ),
                    ),
                    Text(
                      subtitle,
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        color: context.gloam.textTertiary,
                      ),
                    ),
                  ],
                ),
              ),
              if (isSelected)
                Icon(Icons.check, size: 18, color: context.gloam.accent),
            ],
          ),
        ),
      ),
    );
  }
}

class _LeaveRoomButton extends ConsumerWidget {
  const _LeaveRoomButton({required this.roomId});
  final String roomId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.gloam;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () => _confirmLeave(context, ref),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(GloamSpacing.radiusSm),
            border: Border.all(color: colors.danger.withValues(alpha: 0.3)),
          ),
          child: Row(
            children: [
              Icon(Icons.logout, size: 16, color: colors.danger),
              const SizedBox(width: 10),
              Text(
                'Leave room',
                style: GoogleFonts.inter(
                  fontSize: 13,
                  color: colors.danger,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _confirmLeave(BuildContext context, WidgetRef ref) {
    final colors = context.gloam;
    showDialog(
      context: context,
      barrierColor: colors.overlay,
      builder: (ctx) => AlertDialog(
        backgroundColor: colors.bgSurface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: colors.border),
        ),
        title: Text(
          'leave room?',
          style: GoogleFonts.jetBrainsMono(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: colors.textPrimary,
          ),
        ),
        content: Text(
          'You can rejoin later if the room is still accessible.',
          style: GoogleFonts.inter(
            fontSize: 13,
            color: colors.textSecondary,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('cancel',
                style: GoogleFonts.jetBrainsMono(
                    fontSize: 12, color: colors.textSecondary)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: colors.danger),
            onPressed: () async {
              Navigator.pop(ctx);
              final client = ref.read(matrixServiceProvider).client;
              final room = client?.getRoomById(roomId);
              if (room != null) {
                await room.leave();
                ref.read(selectedRoomProvider.notifier).state = null;
                ref.read(rightPanelProvider.notifier).state =
                    RightPanelState.closed;
              }
            },
            child: Text('leave',
                style: GoogleFonts.jetBrainsMono(
                    fontSize: 12, color: colors.textPrimary)),
          ),
        ],
      ),
    );
  }
}

Future<void> _editRoomName(BuildContext context, dynamic room) async {
  final controller = TextEditingController(text: room.getLocalizedDisplayname());
  final result = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Edit room name'),
      content: TextField(
        controller: controller,
        autofocus: true,
        decoration: const InputDecoration(hintText: 'Room name'),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx, controller.text.trim()),
          child: const Text('save'),
        ),
      ],
    ),
  );
  if (result != null && result.isNotEmpty) {
    await room.setName(result);
  }
}

Future<void> _editRoomTopic(BuildContext context, dynamic room) async {
  final controller = TextEditingController(text: room.topic);
  final result = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Edit topic'),
      content: TextField(
        controller: controller,
        autofocus: true,
        maxLines: 3,
        decoration: const InputDecoration(hintText: 'Room topic'),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx, controller.text.trim()),
          child: const Text('save'),
        ),
      ],
    ),
  );
  if (result != null) {
    await room.setDescription(result);
  }
}

class _SettingsButton extends StatelessWidget {
  const _SettingsButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.color,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = color ?? context.gloam.textSecondary;
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(6),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        hoverColor: context.gloam.border.withValues(alpha: 0.3),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          child: Row(
            children: [
              Icon(icon, size: 14, color: c),
              const SizedBox(width: 10),
              Text(label,
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 12,
                    color: c,
                    letterSpacing: 0.5,
                  )),
            ],
          ),
        ),
      ),
    );
  }
}

class _MemberRow extends ConsumerWidget {
  const _MemberRow({
    required this.member,
    required this.room,
    required this.roomId,
    required this.myPowerLevel,
  });

  final dynamic member;
  final dynamic room;
  final String roomId;
  final int myPowerLevel;

  void _showContextMenu(BuildContext context, WidgetRef ref, Offset position) {
    final colors = context.gloam;
    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox;
    final relPos = RelativeRect.fromLTRB(
      position.dx, position.dy,
      overlay.size.width - position.dx,
      overlay.size.height - position.dy,
    );

    final canKick = room.canKick && member.powerLevel < myPowerLevel;
    final canBan = room.canBan && member.powerLevel < myPowerLevel;
    final canChangeRole =
        room.canChangePowerLevel && member.powerLevel < myPowerLevel;

    showMenu<String>(
      context: context,
      position: relPos,
      color: colors.bgSurface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: colors.border),
      ),
      items: [
        PopupMenuItem(
          value: 'profile',
          height: 36,
          child: Row(children: [
            Icon(Icons.person, size: 14, color: colors.textPrimary),
            const SizedBox(width: 10),
            Text('View profile',
                style: TextStyle(fontSize: 13, color: colors.textPrimary)),
          ]),
        ),
        if (canChangeRole) ...[
          const PopupMenuDivider(),
          if (member.powerLevel < 50)
            PopupMenuItem(
              value: 'mod',
              height: 36,
              child: Row(children: [
                Icon(Icons.shield_outlined, size: 14, color: colors.textPrimary),
                const SizedBox(width: 10),
                Text('Make moderator',
                    style: TextStyle(fontSize: 13, color: colors.textPrimary)),
              ]),
            ),
          if (member.powerLevel < 100)
            PopupMenuItem(
              value: 'admin',
              height: 36,
              child: Row(children: [
                Icon(Icons.admin_panel_settings_outlined,
                    size: 14, color: colors.textPrimary),
                const SizedBox(width: 10),
                Text('Make admin',
                    style: TextStyle(fontSize: 13, color: colors.textPrimary)),
              ]),
            ),
          if (member.powerLevel >= 50)
            PopupMenuItem(
              value: 'demote',
              height: 36,
              child: Row(children: [
                Icon(Icons.arrow_downward, size: 14, color: colors.textPrimary),
                const SizedBox(width: 10),
                Text('Remove role',
                    style: TextStyle(fontSize: 13, color: colors.textPrimary)),
              ]),
            ),
        ],
        if (canKick || canBan) ...[
          const PopupMenuDivider(),
          if (canKick)
            PopupMenuItem(
              value: 'kick',
              height: 36,
              child: Row(children: [
                Icon(Icons.person_remove, size: 14, color: colors.warning),
                const SizedBox(width: 10),
                Text('Kick',
                    style: TextStyle(fontSize: 13, color: colors.warning)),
              ]),
            ),
          if (canBan)
            PopupMenuItem(
              value: 'ban',
              height: 36,
              child: Row(children: [
                Icon(Icons.block, size: 14, color: colors.danger),
                const SizedBox(width: 10),
                Text('Ban',
                    style: TextStyle(fontSize: 13, color: colors.danger)),
              ]),
            ),
        ],
      ],
    ).then((value) async {
      if (value == null) return;
      switch (value) {
        case 'profile':
          if (context.mounted) {
            showUserProfile(context, ref,
                userId: member.id, roomId: roomId);
          }
        case 'mod':
          await room.setPower(member.id, 50);
        case 'admin':
          await room.setPower(member.id, 100);
        case 'demote':
          await room.setPower(member.id, 0);
        case 'kick':
          if (context.mounted) {
            final confirmed = await showDialog<bool>(
              context: context,
              builder: (ctx) => AlertDialog(
                title: Text('Kick ${member.calcDisplayname()}?'),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    child: const Text('cancel'),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    child: const Text('kick'),
                  ),
                ],
              ),
            );
            if (confirmed == true) await room.kick(member.id);
          }
        case 'ban':
          if (context.mounted) {
            final confirmed = await showDialog<bool>(
              context: context,
              builder: (ctx) => AlertDialog(
                title: Text('Ban ${member.calcDisplayname()}?'),
                content: const Text(
                    'This user will be removed and unable to rejoin.'),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    child: const Text('cancel'),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    child: const Text('ban'),
                  ),
                ],
              ),
            );
            if (confirmed == true) await room.ban(member.id);
          }
      }
    });
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.gloam;
    final name = member.calcDisplayname();

    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(6),
        child: InkWell(
          borderRadius: BorderRadius.circular(6),
          hoverColor: colors.border.withValues(alpha: 0.3),
          onTap: () => showUserProfile(context, ref,
              userId: member.id, roomId: roomId),
          onSecondaryTapUp: (details) =>
              _showContextMenu(context, ref, details.globalPosition),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: Row(
              children: [
                GloamAvatar(
                  displayName: name,
                  mxcUrl: member.avatarUrl,
                  size: 28,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    name,
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      color: colors.textPrimary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (member.powerLevel >= 100)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: colors.accentDim,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text('admin',
                        style: GoogleFonts.jetBrainsMono(
                          fontSize: 9,
                          color: colors.accent,
                          letterSpacing: 0.5,
                        )),
                  )
                else if (member.powerLevel >= 50)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1A2540),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text('mod',
                        style: GoogleFonts.jetBrainsMono(
                          fontSize: 9,
                          color: colors.info,
                          letterSpacing: 0.5,
                        )),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
