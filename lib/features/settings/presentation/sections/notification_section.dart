import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../app/theme/gloam_theme_ext.dart';
import '../../../../services/notification_diagnostic.dart';
import '../../../../services/notification_service.dart';
import '../widgets/settings_tile.dart';

class NotificationSection extends StatefulWidget {
  const NotificationSection({super.key});

  @override
  State<NotificationSection> createState() => _NotificationSectionState();
}

enum _TestResult { none, sending, success, failure }

class _NotificationSectionState extends State<NotificationSection> {
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

    final ok = await NotificationService.sendTestNotification();

    if (!mounted) return;
    setState(() => _result = ok ? _TestResult.success : _TestResult.failure);

    _resetTimer?.cancel();
    _resetTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _result = _TestResult.none);
    });
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
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
