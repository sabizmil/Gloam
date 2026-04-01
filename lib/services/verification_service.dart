import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:matrix/encryption/utils/key_verification.dart';
import 'package:matrix/matrix.dart';

import '../app/theme/gloam_theme_ext.dart';
import '../app/theme/spacing.dart';

/// Handles incoming and outgoing device verification flows.
///
/// Shows a single stateful dialog that transitions through phases
/// instead of stacking multiple dialogs.
class VerificationService {
  final Client client;
  StreamSubscription? _sub;
  final GlobalKey<NavigatorState> navigatorKey;

  /// Track the active dialog so we don't stack multiple.
  bool _dialogOpen = false;

  VerificationService({required this.client, required this.navigatorKey});

  void start() {
    _sub = client.onKeyVerificationRequest.stream.listen(_onRequest);
  }

  void dispose() {
    _sub?.cancel();
  }

  /// Initiate verification with a specific device.
  Future<void> verifyDevice(String userId, String deviceId) async {
    final request = await client.userDeviceKeys[userId]
        ?.deviceKeys[deviceId]
        ?.startVerification();
    if (request == null) return;
    _showVerificationDialog(request);
  }

  /// Initiate self-verification (verify this device against another).
  Future<void> verifySelf() async {
    final userId = client.userID;
    if (userId == null) return;

    final request =
        await client.userDeviceKeys[userId]?.startVerification();
    if (request == null) return;
    _showVerificationDialog(request);
  }

  void _onRequest(KeyVerification request) async {
    _showVerificationDialog(request, incoming: true);
  }

  void _showVerificationDialog(
    KeyVerification request, {
    bool incoming = false,
  }) {
    final context = navigatorKey.currentContext;
    if (context == null || _dialogOpen) return;

    _dialogOpen = true;
    showDialog(
      context: context,
      barrierColor: context.gloam.overlay,
      barrierDismissible: false,
      builder: (_) => _VerificationDialog(
        request: request,
        client: client,
        incoming: incoming,
      ),
    ).then((_) {
      _dialogOpen = false;
    });
  }
}

// ─── Single Stateful Verification Dialog ───

class _VerificationDialog extends StatefulWidget {
  const _VerificationDialog({
    required this.request,
    required this.client,
    this.incoming = false,
  });

  final KeyVerification request;
  final Client client;
  final bool incoming;

  @override
  State<_VerificationDialog> createState() => _VerificationDialogState();
}

class _VerificationDialogState extends State<_VerificationDialog> {
  late KeyVerificationState _state;
  final _recoveryKeyController = TextEditingController();
  String? _error;
  bool _restoring = false;

  @override
  void initState() {
    super.initState();
    _state = widget.incoming
        ? KeyVerificationState.askAccept
        : KeyVerificationState.waitingAccept;
    widget.request.onUpdate = _onUpdate;
  }

  @override
  void dispose() {
    _recoveryKeyController.dispose();
    super.dispose();
  }

  void _onUpdate() {
    if (!mounted) return;
    setState(() {
      _state = widget.request.state;
    });

    // After verification completes, restore key backup
    if (_state == KeyVerificationState.done) {
      _restoreKeysAfterVerification();
    }
  }

  Future<void> _restoreKeysAfterVerification() async {
    if (_restoring) return;
    _restoring = true;
    try {
      final encryption = widget.client.encryption;
      if (encryption == null) return;

      // Try to cache SSSS secrets that were shared during verification
      if (encryption.ssss.defaultKeyId != null) {
        try {
          final openSsss = encryption.ssss.open();
          await openSsss.maybeCacheAll();
        } catch (_) {
          // SSSS might not be available yet — that's OK
        }
      }

      // Restore Megolm key backup
      if (encryption.keyManager.enabled) {
        await encryption.keyManager.loadAllKeys();
      }
    } catch (e) {
      debugPrint('[verification] key restore failed: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.gloam;
    return Dialog(
      backgroundColor: colors.bgSurface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(GloamSpacing.radiusLg),
        side: BorderSide(color: colors.border),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: _buildPhase(colors),
        ),
      ),
    );
  }

  Widget _buildPhase(dynamic colors) {
    return switch (_state) {
      KeyVerificationState.askAccept => _buildAcceptPhase(colors),
      KeyVerificationState.waitingAccept => _buildWaitingPhase(colors),
      KeyVerificationState.askChoice => _buildChoicePhase(colors),
      KeyVerificationState.askSSSS => _buildSsssPhase(colors),
      KeyVerificationState.askSas => _buildSasPhase(colors),
      KeyVerificationState.done => _buildDonePhase(colors),
      KeyVerificationState.error => _buildErrorPhase(colors),
      _ => _buildWaitingPhase(colors),
    };
  }

  // ── Accept incoming request ──

  Widget _buildAcceptPhase(dynamic colors) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.security, size: 32, color: colors.accent),
        const SizedBox(height: 16),
        Text(
          'verification request',
          style: GoogleFonts.jetBrainsMono(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: colors.textPrimary,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'another device wants to verify this session',
          style: GoogleFonts.inter(
            fontSize: 13,
            color: colors.textSecondary,
          ),
          textAlign: TextAlign.center,
        ),
        if (widget.request.deviceId != null) ...[
          const SizedBox(height: 4),
          Text(
            widget.request.deviceId!,
            style: GoogleFonts.jetBrainsMono(
              fontSize: 11,
              color: colors.textTertiary,
            ),
          ),
        ],
        const SizedBox(height: 24),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            OutlinedButton(
              onPressed: () {
                widget.request.rejectVerification();
                Navigator.pop(context);
              },
              child: const Text('decline'),
            ),
            const SizedBox(width: 12),
            ElevatedButton(
              onPressed: () {
                widget.request.acceptVerification();
              },
              child: const Text('accept'),
            ),
          ],
        ),
      ],
    );
  }

  // ── Waiting for other device ──

  Widget _buildWaitingPhase(dynamic colors) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 32,
          height: 32,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: colors.accent,
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'waiting for other device',
          style: GoogleFonts.jetBrainsMono(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: colors.textPrimary,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'accept the verification request on your other device',
          style: GoogleFonts.inter(
            fontSize: 13,
            color: colors.textSecondary,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 24),
        OutlinedButton(
          onPressed: () {
            widget.request.rejectVerification();
            Navigator.pop(context);
          },
          child: const Text('cancel'),
        ),
      ],
    );
  }

  // ── Method choice (auto-select SAS) ──

  Widget _buildChoicePhase(dynamic colors) {
    // Auto-start SAS verification
    WidgetsBinding.instance.addPostFrameCallback((_) {
      widget.request.acceptVerification();
    });
    return _buildWaitingPhase(colors);
  }

  // ── Recovery key / passphrase needed ──

  Widget _buildSsssPhase(dynamic colors) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.key, size: 32, color: colors.accent),
        const SizedBox(height: 16),
        Text(
          'recovery key needed',
          style: GoogleFonts.jetBrainsMono(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: colors.textPrimary,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'enter your recovery key or passphrase to complete verification',
          style: GoogleFonts.inter(
            fontSize: 13,
            color: colors.textSecondary,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _recoveryKeyController,
          autofocus: true,
          style: GoogleFonts.jetBrainsMono(
            fontSize: 13,
            color: colors.textPrimary,
          ),
          decoration: InputDecoration(
            hintText: 'recovery key or passphrase',
            hintStyle: GoogleFonts.inter(
              fontSize: 13,
              color: colors.textTertiary,
            ),
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: 8),
          Text(
            _error!,
            style: GoogleFonts.inter(
              fontSize: 12,
              color: colors.danger,
            ),
          ),
        ],
        const SizedBox(height: 24),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            OutlinedButton(
              onPressed: () {
                widget.request.rejectVerification();
                Navigator.pop(context);
              },
              child: const Text('cancel'),
            ),
            const SizedBox(width: 12),
            ElevatedButton(
              onPressed: () async {
                final input = _recoveryKeyController.text.trim();
                if (input.isEmpty) return;

                try {
                  setState(() => _error = null);
                  await widget.request.openSSSS(
                    keyOrPassphrase: input,
                  );
                } catch (e) {
                  setState(() => _error = 'Invalid key or passphrase');
                }
              },
              child: const Text('unlock'),
            ),
          ],
        ),
      ],
    );
  }

  // ── SAS emoji/number comparison ──

  Widget _buildSasPhase(dynamic colors) {
    final emojis = widget.request.sasEmojis;
    final numbers = widget.request.sasNumbers;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'verify device',
          style: GoogleFonts.jetBrainsMono(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: colors.textPrimary,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'confirm these match on your other device',
          style: GoogleFonts.inter(
            fontSize: 13,
            color: colors.textSecondary,
          ),
        ),
        const SizedBox(height: 24),
        if (emojis.isNotEmpty)
          Wrap(
            spacing: 16,
            runSpacing: 16,
            alignment: WrapAlignment.center,
            children: emojis
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
                            color: colors.textTertiary,
                          ),
                        ),
                      ],
                    ))
                .toList(),
          )
        else if (numbers.isNotEmpty)
          Text(
            numbers.join('  '),
            style: GoogleFonts.jetBrainsMono(
              fontSize: 24,
              fontWeight: FontWeight.w500,
              color: colors.textPrimary,
              letterSpacing: 4,
            ),
          ),
        const SizedBox(height: 32),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            OutlinedButton(
              onPressed: () {
                widget.request.rejectSas();
              },
              child: Text(
                'they don\'t match',
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 12,
                  color: colors.danger,
                ),
              ),
            ),
            const SizedBox(width: 12),
            ElevatedButton(
              onPressed: () {
                widget.request.acceptSas();
              },
              child: const Text('they match'),
            ),
          ],
        ),
      ],
    );
  }

  // ── Done ──

  Widget _buildDonePhase(dynamic colors) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.check_circle, size: 48, color: colors.accent),
        const SizedBox(height: 16),
        Text(
          'device verified',
          style: GoogleFonts.jetBrainsMono(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: colors.textPrimary,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'encryption keys have been shared',
          style: GoogleFonts.inter(
            fontSize: 13,
            color: colors.textSecondary,
          ),
        ),
        const SizedBox(height: 24),
        ElevatedButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('done'),
        ),
      ],
    );
  }

  // ── Error ──

  Widget _buildErrorPhase(dynamic colors) {
    final code = widget.request.canceledCode;
    final message = switch (code) {
      'm.user' => 'verification was cancelled',
      'm.timeout' => 'verification timed out',
      'm.key_mismatch' => 'key mismatch — possible security issue',
      'm.unknown_method' => 'unsupported verification method',
      _ => code ?? 'unknown error',
    };

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.error_outline, size: 48, color: colors.danger),
        const SizedBox(height: 16),
        Text(
          'verification failed',
          style: GoogleFonts.jetBrainsMono(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: colors.textPrimary,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          message,
          style: GoogleFonts.inter(
            fontSize: 13,
            color: colors.textSecondary,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 24),
        ElevatedButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('close'),
        ),
      ],
    );
  }
}
