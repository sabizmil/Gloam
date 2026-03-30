import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:matrix/encryption/utils/key_verification.dart';
import 'package:matrix/matrix.dart';

import '../app/theme/gloam_theme_ext.dart';
import '../app/theme/spacing.dart';

/// Handles incoming and outgoing device verification flows.
///
/// Uses the SDK's `onUpdate` callback for proper state tracking
/// instead of polling.
class VerificationService {
  final Client client;
  StreamSubscription? _sub;
  final GlobalKey<NavigatorState> navigatorKey;

  VerificationService({required this.client, required this.navigatorKey});

  void start() {
    _sub = client.onKeyVerificationRequest.stream.listen(_onRequest);
  }

  void dispose() {
    _sub?.cancel();
  }

  /// Initiate verification with another device.
  Future<void> verifyDevice(String userId, String deviceId) async {
    final request = await client.userDeviceKeys[userId]
        ?.deviceKeys[deviceId]
        ?.startVerification();
    if (request == null) return;

    request.onUpdate = () => _handleState(request);
  }

  /// Initiate self-verification (verify this device against another).
  Future<void> verifySelf() async {
    final userId = client.userID;
    if (userId == null) return;

    final request = await client.userDeviceKeys[userId]
        ?.startVerification();
    if (request == null) return;

    request.onUpdate = () => _handleState(request);
  }

  void _onRequest(KeyVerification request) async {
    final context = navigatorKey.currentContext;
    if (context == null) return;

    // Show accept/decline dialog
    final accepted = await showDialog<bool>(
      context: context,
      barrierColor: context.gloam.overlay,
      barrierDismissible: false,
      builder: (ctx) => _AcceptVerificationDialog(
        deviceId: request.deviceId,
      ),
    );

    if (accepted != true) {
      await request.rejectVerification();
      return;
    }

    await request.acceptVerification();
    request.onUpdate = () => _handleState(request);
  }

  void _handleState(KeyVerification request) {
    final context = navigatorKey.currentContext;
    if (context == null) return;

    switch (request.state) {
      case KeyVerificationState.askSas:
        _showSasDialog(context, request);
      case KeyVerificationState.done:
        _showDoneDialog(context);
      case KeyVerificationState.error:
        _showErrorDialog(context, request);
      default:
        // waitingAccept, askAccept, askSSSS, etc — no UI needed
        break;
    }
  }

  void _showSasDialog(BuildContext context, KeyVerification request) {
    showDialog<bool>(
      context: context,
      barrierColor: context.gloam.overlay,
      barrierDismissible: false,
      builder: (ctx) => _SasVerificationDialog(
        emojis: request.sasEmojis,
        numbers: request.sasNumbers,
      ),
    ).then((confirmed) async {
      if (confirmed == true) {
        await request.acceptSas();
      } else {
        await request.rejectSas();
      }
    });
  }

  void _showDoneDialog(BuildContext context) {
    showDialog(
      context: context,
      barrierColor: context.gloam.overlay,
      builder: (ctx) => Dialog(
        backgroundColor: context.gloam.bgSurface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(GloamSpacing.radiusLg),
          side: BorderSide(color: context.gloam.border),
        ),
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.check_circle,
                  size: 48, color: context.gloam.accent),
              const SizedBox(height: 16),
              Text(
                'device verified',
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: context.gloam.textPrimary,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'encryption keys have been shared',
                style: GoogleFonts.inter(
                  fontSize: 13,
                  color: context.gloam.textSecondary,
                ),
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('done'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showErrorDialog(BuildContext context, KeyVerification request) {
    showDialog(
      context: context,
      barrierColor: context.gloam.overlay,
      builder: (ctx) => Dialog(
        backgroundColor: context.gloam.bgSurface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(GloamSpacing.radiusLg),
          side: BorderSide(color: context.gloam.border),
        ),
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline,
                  size: 48, color: context.gloam.danger),
              const SizedBox(height: 16),
              Text(
                'verification failed',
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: context.gloam.textPrimary,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                request.canceledCode ?? 'unknown error',
                style: GoogleFonts.inter(
                  fontSize: 13,
                  color: context.gloam.textSecondary,
                ),
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('close'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AcceptVerificationDialog extends StatelessWidget {
  const _AcceptVerificationDialog({this.deviceId});
  final String? deviceId;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: context.gloam.bgSurface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(GloamSpacing.radiusLg),
        side: BorderSide(color: context.gloam.border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.security, size: 32, color: context.gloam.accent),
            const SizedBox(height: 16),
            Text(
              'verification request',
              style: GoogleFonts.jetBrainsMono(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: context.gloam.textPrimary,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'another device wants to verify this session',
              style: GoogleFonts.inter(
                fontSize: 13,
                color: context.gloam.textSecondary,
              ),
              textAlign: TextAlign.center,
            ),
            if (deviceId != null) ...[
              const SizedBox(height: 4),
              Text(
                deviceId!,
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 11,
                  color: context.gloam.textTertiary,
                ),
              ),
            ],
            const SizedBox(height: 24),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                OutlinedButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('decline'),
                ),
                const SizedBox(width: 12),
                ElevatedButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('accept'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SasVerificationDialog extends StatelessWidget {
  const _SasVerificationDialog({this.emojis, this.numbers});

  final List<KeyVerificationEmoji>? emojis;
  final List<int>? numbers;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: context.gloam.bgSurface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(GloamSpacing.radiusLg),
        side: BorderSide(color: context.gloam.border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'verify device',
              style: GoogleFonts.jetBrainsMono(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: context.gloam.textPrimary,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'confirm these match on your other device',
              style: GoogleFonts.inter(
                fontSize: 13,
                color: context.gloam.textSecondary,
              ),
            ),
            const SizedBox(height: 24),

            if (emojis != null)
              Wrap(
                spacing: 16,
                runSpacing: 16,
                alignment: WrapAlignment.center,
                children: emojis!
                    .map((e) => Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(e.emoji,
                                style: const TextStyle(fontSize: 32)),
                            const SizedBox(height: 4),
                            Text(
                              e.name,
                              style: GoogleFonts.jetBrainsMono(
                                fontSize: 10,
                                color: context.gloam.textTertiary,
                              ),
                            ),
                          ],
                        ))
                    .toList(),
              ),

            if (emojis == null && numbers != null)
              Text(
                numbers!.join('  '),
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 24,
                  fontWeight: FontWeight.w500,
                  color: context.gloam.textPrimary,
                  letterSpacing: 4,
                ),
              ),

            const SizedBox(height: 32),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                OutlinedButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: Text(
                    'they don\'t match',
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 12,
                      color: context.gloam.danger,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                ElevatedButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('they match'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
