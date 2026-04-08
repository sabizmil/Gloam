import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../app/theme/gloam_color_extension.dart';
import '../../../../app/theme/gloam_theme_ext.dart';
import '../../../../app/theme/spacing.dart';

/// Zero-state shown when a room is joined but has no messages yet
/// (federation bootstrap in progress).
///
/// After [timeoutDuration] with no resolution, switches to an error
/// state indicating the server may be unreachable.
class SyncingZeroState extends StatefulWidget {
  const SyncingZeroState({
    super.key,
    required this.roomName,
    required this.serverName,
    required this.memberCount,
    this.onLeave,
    this.onRetry,
    this.timeoutDuration = const Duration(seconds: 60),
  });

  final String roomName;
  final String serverName;
  final int memberCount;
  final VoidCallback? onLeave;
  final VoidCallback? onRetry;
  final Duration timeoutDuration;

  @override
  State<SyncingZeroState> createState() => _SyncingZeroStateState();
}

class _SyncingZeroStateState extends State<SyncingZeroState> {
  bool _timedOut = false;

  @override
  void initState() {
    super.initState();
    Future.delayed(widget.timeoutDuration, () {
      if (mounted) setState(() => _timedOut = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    return _timedOut
        ? _ServerUnreachable(
            roomName: widget.roomName,
            serverName: widget.serverName,
            onLeave: widget.onLeave,
            onRetry: widget.onRetry,
          )
        : _SyncingProgress(
            roomName: widget.roomName,
            serverName: widget.serverName,
            memberCount: widget.memberCount,
            onLeave: widget.onLeave,
          );
  }
}

// ── Syncing progress (original view) ──

class _SyncingProgress extends StatelessWidget {
  const _SyncingProgress({
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
        Expanded(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(40),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
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
        _SyncFooter(onLeave: onLeave),
      ],
    );
  }
}

// ── Server unreachable (timeout view) ──

class _ServerUnreachable extends StatelessWidget {
  const _ServerUnreachable({
    required this.roomName,
    required this.serverName,
    this.onLeave,
    this.onRetry,
  });

  final String roomName;
  final String serverName;
  final VoidCallback? onLeave;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final colors = context.gloam;
    return Column(
      children: [
        Expanded(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(40),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.cloud_off, size: 48, color: colors.danger),
                  const SizedBox(height: 20),
                  Text(
                    'Unable to reach server',
                    style: GoogleFonts.inter(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: colors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'The homeserver for #$roomName ($serverName) '
                    'appears to be offline or no longer exists.',
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      color: colors.textTertiary,
                      height: 1.5,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 28),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ElevatedButton.icon(
                        onPressed: onLeave,
                        icon: const Icon(Icons.logout, size: 16),
                        label: const Text('Leave Room'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: colors.danger,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      OutlinedButton.icon(
                        onPressed: onRetry,
                        icon: const Icon(Icons.refresh, size: 16),
                        label: const Text('Retry'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: colors.textSecondary,
                          side: BorderSide(color: colors.border),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ── Shared footer ──

class _SyncFooter extends StatelessWidget {
  const _SyncFooter({this.onLeave});
  final VoidCallback? onLeave;

  @override
  Widget build(BuildContext context) {
    final colors = context.gloam;
    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: colors.border)),
      ),
      child: Row(
        children: [
          Icon(Icons.chat_bubble_outline, size: 14, color: colors.textTertiary),
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
                  borderRadius: BorderRadius.circular(GloamSpacing.radiusSm),
                  border: Border.all(color: colors.border),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.logout, size: 12, color: colors.textTertiary),
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
    );
  }
}

// ── Step widget ──

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
        SizedBox(
          width: 24,
          child: Column(
            children: [
              _buildDot(colors),
              if (!isLast)
                Container(
                  width: 2, height: 32,
                  color: state == _StepState.complete ? colors.accent : colors.border,
                ),
            ],
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Padding(
            padding: EdgeInsets.only(bottom: isLast ? 0 : 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 2),
                Text(title, style: GoogleFonts.inter(
                  fontSize: 13, fontWeight: FontWeight.w500,
                  color: switch (state) {
                    _StepState.complete => colors.accent,
                    _StepState.active => colors.textPrimary,
                    _StepState.pending => colors.textTertiary,
                  },
                )),
                const SizedBox(height: 2),
                Text(subtitle, style: GoogleFonts.inter(
                  fontSize: 11, color: colors.textTertiary,
                )),
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
          width: 24, height: 24,
          decoration: BoxDecoration(shape: BoxShape.circle, color: colors.accent),
          child: Center(child: Icon(Icons.check, size: 12, color: colors.bg)),
        ),
      _StepState.active => Container(
          width: 24, height: 24,
          decoration: BoxDecoration(
            shape: BoxShape.circle, color: colors.accentDim,
            border: Border.all(color: colors.accent, width: 2),
          ),
          child: Center(child: Container(
            width: 8, height: 8,
            decoration: BoxDecoration(shape: BoxShape.circle, color: colors.accent),
          )),
        ),
      _StepState.pending => Container(
          width: 24, height: 24,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: colors.border, width: 2),
          ),
        ),
    };
  }
}
