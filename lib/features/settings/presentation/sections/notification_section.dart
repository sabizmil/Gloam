import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../app/theme/color_tokens.dart';
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
              color: GloamColors.textTertiary,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTrailing() {
    return switch (_result) {
      _TestResult.none => const SizedBox.shrink(),
      _TestResult.sending => const SizedBox(
          width: 14,
          height: 14,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: GloamColors.textTertiary,
          ),
        ),
      _TestResult.success => const Icon(
          Icons.check_circle_outline,
          size: 16,
          color: GloamColors.accent,
        ),
      _TestResult.failure => const Icon(
          Icons.error_outline,
          size: 16,
          color: GloamColors.danger,
        ),
    };
  }
}
