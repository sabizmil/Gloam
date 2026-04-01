import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:matrix/matrix.dart' show PushRuleState;

import '../theme/gloam_theme_ext.dart';
import '../theme/spacing.dart';
import '../../features/chat/presentation/providers/timeline_provider.dart';
import '../../features/profile/presentation/user_profile_modal.dart';
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
                Text(
                  '// members \u2014 ${members.length}',
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 10,
                    color: context.gloam.textTertiary,
                    letterSpacing: 1,
                  ),
                ),
                const SizedBox(height: 12),
                ...members.take(20).map((m) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: MouseRegion(
                        cursor: SystemMouseCursors.click,
                        child: GestureDetector(
                          onTap: () => showUserProfile(context, ref,
                              userId: m.id, roomId: roomId),
                          child: Row(
                        children: [
                          GloamAvatar(
                            displayName: m.calcDisplayname(),
                            mxcUrl: m.avatarUrl,
                            size: 28,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  m.calcDisplayname(),
                                  style: GoogleFonts.inter(
                                    fontSize: 13,
                                    color: context.gloam.textPrimary,
                                  ),
                                ),
                                if (m.powerLevel >= 100)
                                  Text(
                                    'admin',
                                    style: GoogleFonts.jetBrainsMono(
                                      fontSize: 10,
                                      color: context.gloam.accent,
                                    ),
                                  )
                                else if (m.powerLevel >= 50)
                                  Text(
                                    'moderator',
                                    style: GoogleFonts.jetBrainsMono(
                                      fontSize: 10,
                                      color: context.gloam.textTertiary,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    )))),

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
