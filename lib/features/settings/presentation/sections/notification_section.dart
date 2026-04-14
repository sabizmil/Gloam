import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../app/theme/gloam_theme_ext.dart';
import '../../../../data/notification_sounds.dart';
import '../../../../services/connection_status_provider.dart';
import '../../../../services/notification_diagnostic.dart';
import '../../../../services/notification_service.dart';
import '../../../../services/notification_sound_preferences.dart';
import '../widgets/settings_tile.dart';
import '../widgets/sound_picker.dart';

class NotificationSection extends ConsumerStatefulWidget {
  const NotificationSection({super.key});

  @override
  ConsumerState<NotificationSection> createState() =>
      _NotificationSectionState();
}

enum _TestResult { none, sending, success, failure }

class _NotificationSectionState extends ConsumerState<NotificationSection> {
  _TestResult _result = _TestResult.none;
  Timer? _resetTimer;

  @override
  void dispose() {
    _resetTimer?.cancel();
    super.dispose();
  }

  Future<void> _sendTest() async {
    if (_result == _TestResult.sending) return;
    setState(() => _result = _TestResult.sending);

    final prefs = ref.read(notificationSoundPrefsProvider);
    final soundName = prefs.enabled ? prefs.globalSound : null;
    final ok = await NotificationService.sendTestNotification(soundName: soundName);

    if (!mounted) return;
    setState(() => _result = ok ? _TestResult.success : _TestResult.failure);

    _resetTimer?.cancel();
    _resetTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _result = _TestResult.none);
    });
  }

  String _soundDisplayName(String soundId) {
    for (final s in builtInSounds) {
      if (s.id == soundId) return s.displayName;
    }
    if (soundId == 'silent') return 'Silent';
    // Custom sound — show filename
    final name = soundId.split('/').last.split('\\').last;
    return name;
  }

  @override
  Widget build(BuildContext context) {
    final soundPrefs = ref.watch(notificationSoundPrefsProvider);
    final soundNotifier =
        ref.read(notificationSoundPrefsProvider.notifier);

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        // ── Sounds ──
        const SettingsSectionHeader('sounds'),
        SettingsTile(
          icon: Icons.volume_up_outlined,
          label: 'notification sounds',
          trailing: Switch(
            value: soundPrefs.enabled,
            onChanged: (v) => soundNotifier.setEnabled(v),
            activeColor: context.gloam.accentBright,
            activeTrackColor: context.gloam.accentDim,
            inactiveTrackColor: context.gloam.bgSurface,
            inactiveThumbColor: context.gloam.textTertiary,
          ),
        ),
        if (soundPrefs.enabled) ...[
          SettingsTile(
            icon: Icons.music_note_outlined,
            label: 'sound',
            value: _soundDisplayName(soundPrefs.globalSound),
            onTap: () async {
              final picked = await showSoundPicker(
                context,
                currentSound: soundPrefs.globalSound,
              );
              if (picked != null) {
                soundNotifier.setGlobalSound(picked);
              }
            },
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(42, 0, 12, 0),
            child: Text(
              'Per-room sounds can be configured in each room\'s info panel.',
              style: GoogleFonts.inter(
                fontSize: 12,
                color: context.gloam.textTertiary,
              ),
            ),
          ),
        ],

        // ── Permissions (Darwin only) ──
        if (Platform.isIOS || Platform.isMacOS) ...[
          const SettingsSectionHeader('permissions'),
          SettingsTile(
            icon: Icons.notifications_outlined,
            label: 'request notification permission',
            onTap: () async {
              final granted =
                  await NotificationService.requestPermissionsStatic();
              if (!context.mounted) return;
              final msg = switch (granted) {
                true => 'Permission granted.',
                false =>
                  'Permission denied. Open ${Platform.isIOS ? "Settings" : "System Settings"} > Notifications > Gloam to change.',
                null => 'No response from system. Already determined?',
              };
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(msg)),
              );
            },
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(42, 0, 12, 0),
            child: Text(
              Platform.isIOS
                  ? 'iOS only shows the system prompt the first time. After that, change the grant in Settings > Notifications > Gloam.'
                  : 'macOS only shows the system prompt the first time. After that, change the grant in System Settings > Notifications > Gloam.',
              style: GoogleFonts.inter(
                fontSize: 12,
                color: context.gloam.textTertiary,
              ),
            ),
          ),
          const SizedBox(height: 12),
        ],

        // ── Test ──
        const SettingsSectionHeader('test'),
        SettingsTile(
          icon: Icons.notifications_active_outlined,
          label: 'send test notification',
          trailing: _buildTrailing(),
          onTap: _result == _TestResult.sending ? null : _sendTest,
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(42, 0, 12, 0),
          child: Text(
            'Fires a local notification to verify your system is configured correctly.',
            style: GoogleFonts.inter(
              fontSize: 12,
              color: context.gloam.textTertiary,
            ),
          ),
        ),
        const SizedBox(height: 12),
        SettingsTile(
          icon: Icons.bug_report_outlined,
          label: 'run notification diagnostic',
          onTap: () async {
            final result = await NotificationDiagnostic.run();
            if (!context.mounted) return;
            showDialog(
              context: context,
              builder: (ctx) => AlertDialog(
                backgroundColor: ctx.gloam.bgSurface,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(color: ctx.gloam.border),
                ),
                title: Text('diagnostic results',
                    style: GoogleFonts.jetBrainsMono(
                        fontSize: 13, color: ctx.gloam.textPrimary)),
                content: SizedBox(
                  width: 500,
                  child: SingleChildScrollView(
                    child: SelectableText(
                      result,
                      style: GoogleFonts.jetBrainsMono(
                          fontSize: 11,
                          color: ctx.gloam.textSecondary,
                          height: 1.6),
                    ),
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('close'),
                  ),
                ],
              ),
            );
          },
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(42, 0, 12, 0),
          child: Text(
            'Runs a step-by-step diagnostic and logs results to the console. Run this via flutter run to see output.',
            style: GoogleFonts.inter(
              fontSize: 12,
              color: context.gloam.textTertiary,
            ),
          ),
        ),

        // Debug-only connection status simulator
        if (kDebugMode) ...[
          const SettingsSectionHeader('debug — connection status'),
          SettingsTile(
            icon: Icons.wifi,
            label: 'simulate: online',
            onTap: () => ref
                .read(connectionStatusProvider.notifier)
                .debugOverride(ConnectionStatus.online),
          ),
          SettingsTile(
            icon: Icons.wifi_find,
            label: 'simulate: connecting',
            onTap: () => ref
                .read(connectionStatusProvider.notifier)
                .debugOverride(ConnectionStatus.connecting),
          ),
          SettingsTile(
            icon: Icons.sync_problem,
            label: 'simulate: reconnecting',
            onTap: () => ref
                .read(connectionStatusProvider.notifier)
                .debugOverride(ConnectionStatus.reconnecting),
          ),
          SettingsTile(
            icon: Icons.wifi_off,
            label: 'simulate: disconnected',
            onTap: () => ref
                .read(connectionStatusProvider.notifier)
                .debugOverride(ConnectionStatus.disconnected),
          ),
          SettingsTile(
            icon: Icons.restore,
            label: 'clear override (use real status)',
            onTap: () => ref
                .read(connectionStatusProvider.notifier)
                .debugClearOverride(),
          ),
        ],
      ],
    );
  }

  Widget _buildTrailing() {
    return switch (_result) {
      _TestResult.none => const SizedBox.shrink(),
      _TestResult.sending => SizedBox(
          width: 14,
          height: 14,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: context.gloam.textTertiary,
          ),
        ),
      _TestResult.success => Icon(
          Icons.check_circle_outline,
          size: 16,
          color: context.gloam.accent,
        ),
      _TestResult.failure => Icon(
          Icons.error_outline,
          size: 16,
          color: context.gloam.danger,
        ),
    };
  }
}
