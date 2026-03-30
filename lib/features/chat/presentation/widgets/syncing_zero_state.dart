import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../app/theme/gloam_color_extension.dart';
import '../../../../app/theme/gloam_theme_ext.dart';
import '../../../../app/theme/spacing.dart';

/// Zero-state shown when a room is joined but has no messages yet
/// (federation bootstrap in progress).
///
/// Replaces the timeline body and composer with a progress stepper
/// and a disabled footer. The header stays unchanged.
class SyncingZeroState extends StatelessWidget {
  const SyncingZeroState({
    super.key,
    required this.roomName,
    required this.serverName,
    required this.memberCount,
    this.onLeave,
  });

  final String roomName;
  final String serverName;
  final int memberCount;
  final VoidCallback? onLeave;

  @override
  Widget build(BuildContext context) {
    final colors = context.gloam;
    return Column(
      children: [
        // Body: progress timeline
        Expanded(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(40),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Title
                  Text(
                    'Joining #$roomName',
                    style: GoogleFonts.inter(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: colors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Your server is connecting to the federation',
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      color: colors.textTertiary,
                    ),
                  ),
                  const SizedBox(height: 28),

                  // Steps
                  SizedBox(
                    width: 360,
                    child: Column(
                      children: [
                        _Step(
                          state: _StepState.complete,
                          title: 'Room joined',
                          subtitle: memberCount > 0
                              ? '$memberCount members · $serverName'
                              : 'Membership confirmed',
                        ),
                        _Step(
                          state: _StepState.active,
                          title: 'Syncing room state',
                          subtitle:
                              'Downloading members, permissions, and metadata',
                          isLast: false,
                        ),
                        _Step(
                          state: _StepState.pending,
                          title: 'Loading message history',
                          subtitle: 'Recent messages will appear here',
                          isLast: true,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 28),

                  // Info hint
                  Container(
                    constraints: const BoxConstraints(maxWidth: 460),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: colors.bgSurface,
                      borderRadius:
                          BorderRadius.circular(GloamSpacing.radiusMd),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(top: 1),
                          child: Icon(Icons.info_outline,
                              size: 14, color: colors.textTertiary),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Large rooms may take a few minutes on first join. '
                            'You can navigate away — syncing continues in the background.',
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              color: colors.textTertiary,
                              height: 1.5,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),

        // Disabled footer (replaces composer)
        Container(
          height: 56,
          padding: const EdgeInsets.symmetric(horizontal: 20),
          decoration: BoxDecoration(
            border: Border(
              top: BorderSide(color: colors.border),
            ),
          ),
          child: Row(
            children: [
              Icon(Icons.chat_bubble_outline,
                  size: 14, color: colors.textTertiary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Messaging available after sync completes',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    fontStyle: FontStyle.italic,
                    color: colors.textTertiary,
                  ),
                ),
              ),
              if (onLeave != null)
                GestureDetector(
                  onTap: onLeave,
                  child: Container(
                    height: 28,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      color: colors.bgSurface,
                      borderRadius:
                          BorderRadius.circular(GloamSpacing.radiusSm),
                      border: Border.all(color: colors.border),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.logout,
                            size: 12, color: colors.textTertiary),
                        const SizedBox(width: 6),
                        Text(
                          'Leave Room',
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            color: colors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

// =============================================================================
// Step widget
// =============================================================================

enum _StepState { complete, active, pending }

class _Step extends StatelessWidget {
  const _Step({
    required this.state,
    required this.title,
    required this.subtitle,
    this.isLast = false,
  });

  final _StepState state;
  final String title;
  final String subtitle;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final colors = context.gloam;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Dot + line
        SizedBox(
          width: 24,
          child: Column(
            children: [
              _buildDot(colors),
              if (!isLast)
                Container(
                  width: 2,
                  height: 32,
                  color: state == _StepState.complete
                      ? colors.accent
                      : colors.border,
                ),
            ],
          ),
        ),
        const SizedBox(width: 14),

        // Text
        Expanded(
          child: Padding(
            padding: EdgeInsets.only(bottom: isLast ? 0 : 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 2),
                Text(
                  title,
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: switch (state) {
                      _StepState.complete => colors.accent,
                      _StepState.active => colors.textPrimary,
                      _StepState.pending => colors.textTertiary,
                    },
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    color: colors.textTertiary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDot(GloamColorExtension colors) {
    return switch (state) {
      _StepState.complete => Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: colors.accent,
          ),
          child: Center(
            child: Icon(Icons.check, size: 12, color: colors.bg),
          ),
        ),
      _StepState.active => Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: colors.accentDim,
            border: Border.all(color: colors.accent, width: 2),
          ),
          child: Center(
            child: Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: colors.accent,
              ),
            ),
          ),
        ),
      _StepState.pending => Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: colors.border, width: 2),
          ),
        ),
    };
  }
}
