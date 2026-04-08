import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:matrix/encryption/utils/bootstrap.dart';
import 'package:matrix/matrix.dart';

import '../../../app/theme/gloam_theme_ext.dart';
import '../../../app/theme/spacing.dart';
import '../../../services/matrix_service.dart';

/// Show the encryption bootstrap dialog.
void showBootstrapDialog(BuildContext context) {
  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (_) => const _BootstrapDialog(),
  );
}

enum _Phase { generating, saveKey, done, error }

class _BootstrapDialog extends ConsumerStatefulWidget {
  const _BootstrapDialog();

  @override
  ConsumerState<_BootstrapDialog> createState() => _BootstrapDialogState();
}

class _BootstrapDialogState extends ConsumerState<_BootstrapDialog> {
  _Phase _phase = _Phase.generating;
  String? _recoveryKey;
  String? _error;
  bool _confirmed = false;
  String _status = 'Creating encryption keys...';

  @override
  void initState() {
    super.initState();
    _runBootstrap();
  }

  Future<void> _runBootstrap() async {
    final client = ref.read(matrixServiceProvider).client;
    if (client?.encryption == null) {
      setState(() {
        _phase = _Phase.error;
        _error = 'Encryption not available';
      });
      return;
    }

    try {
      final bootstrap = client!.encryption!.bootstrap(onUpdate: (b) {
        if (!mounted) return;
        _handleBootstrapState(b);
      });

      // The bootstrap constructor triggers the first state via onUpdate
      // We need to wait for it to be ready, then drive the state machine
    } catch (e) {
      if (mounted) {
        setState(() {
          _phase = _Phase.error;
          _error = e.toString();
        });
      }
    }
  }

  Future<void> _handleBootstrapState(Bootstrap bootstrap) async {
    switch (bootstrap.state) {
      case BootstrapState.loading:
        break;

      case BootstrapState.askNewSsss:
        setState(() => _status = 'Creating secure storage...');
        await bootstrap.newSsss();

      case BootstrapState.askSetupCrossSigning:
        setState(() => _status = 'Setting up cross-signing...');
        await bootstrap.askSetupCrossSigning(
          setupMasterKey: true,
          setupSelfSigningKey: true,
          setupUserSigningKey: true,
        );

      case BootstrapState.askSetupOnlineKeyBackup:
        setState(() => _status = 'Enabling key backup...');
        await bootstrap.askSetupOnlineKeyBackup(true);

      case BootstrapState.done:
        // Extract the recovery key
        final key = bootstrap.newSsssKey;
        if (key != null && mounted) {
          setState(() {
            _recoveryKey = key.recoveryKey;
            _phase = _Phase.saveKey;
          });
        } else if (mounted) {
          setState(() => _phase = _Phase.done);
        }

      case BootstrapState.error:
        if (mounted) {
          setState(() {
            _phase = _Phase.error;
            _error = 'Bootstrap failed. Please try again.';
          });
        }

      // Existing SSSS scenarios — auto-wipe for fresh accounts
      case BootstrapState.askWipeSsss:
        bootstrap.wipeSsss(true);
      case BootstrapState.askWipeCrossSigning:
        await bootstrap.wipeCrossSigning(true);
      case BootstrapState.askWipeOnlineKeyBackup:
        bootstrap.wipeOnlineKeyBackup(true);
      case BootstrapState.askUseExistingSsss:
        bootstrap.useExistingSsss(false);
      case BootstrapState.askBadSsss:
        bootstrap.ignoreBadSecrets(true);
      case BootstrapState.askUnlockSsss:
        bootstrap.unlockedSsss();
      case BootstrapState.openExistingSsss:
        await bootstrap.openExistingSsss();
    }
  }

  void _copyKey() {
    if (_recoveryKey != null) {
      Clipboard.setData(ClipboardData(text: _recoveryKey!));
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Recovery key copied to clipboard'),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _saveKeyToFile() async {
    if (_recoveryKey == null) return;
    final result = await FilePicker.platform.saveFile(
      dialogTitle: 'Save recovery key',
      fileName: 'gloam-recovery-key.txt',
    );
    if (result == null) return;
    final file = File(result);
    await file.writeAsString(
      'Gloam Recovery Key\n'
      '==================\n\n'
      '$_recoveryKey\n\n'
      'Keep this key safe. You will need it to recover\n'
      'your encrypted messages on a new device.\n',
    );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Recovery key saved'),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.gloam;
    return Dialog(
      backgroundColor: colors.bgSurface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(GloamSpacing.radiusMd),
        side: BorderSide(color: colors.border),
      ),
      child: SizedBox(
        width: 440,
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: switch (_phase) {
            _Phase.generating => _buildGenerating(colors),
            _Phase.saveKey => _buildSaveKey(colors),
            _Phase.done => _buildDone(colors),
            _Phase.error => _buildError(colors),
          },
        ),
      ),
    );
  }

  Widget _buildGenerating(dynamic colors) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.lock_outlined, size: 36, color: colors.accent),
        const SizedBox(height: 20),
        Text(
          'Setting up encryption...',
          style: GoogleFonts.inter(
            fontSize: 16, fontWeight: FontWeight.w600, color: colors.textPrimary,
          ),
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: 24, height: 24,
          child: CircularProgressIndicator(
            strokeWidth: 2, color: colors.accent,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          _status,
          style: GoogleFonts.inter(fontSize: 13, color: colors.textTertiary),
        ),
      ],
    );
  }

  Widget _buildSaveKey(dynamic colors) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.key, size: 20, color: colors.accent),
            const SizedBox(width: 10),
            Text(
              'Save your recovery key',
              style: GoogleFonts.inter(
                fontSize: 16, fontWeight: FontWeight.w600, color: colors.textPrimary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),

        // Recovery key display
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: colors.bg,
            borderRadius: BorderRadius.circular(GloamSpacing.radiusSm),
            border: Border.all(color: colors.borderSubtle),
          ),
          child: SelectableText(
            _recoveryKey ?? '',
            style: GoogleFonts.jetBrainsMono(
              fontSize: 13, color: colors.textPrimary, height: 1.6,
            ),
          ),
        ),
        const SizedBox(height: 12),

        // Warning
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: colors.warning.withAlpha(20),
            borderRadius: BorderRadius.circular(GloamSpacing.radiusSm),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.warning_amber, size: 16, color: colors.warning),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'If you lose this key, you will not be able to recover your encrypted messages on a new device.',
                  style: GoogleFonts.inter(
                    fontSize: 12, color: colors.warning, height: 1.5,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Action buttons
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _copyKey,
                icon: const Icon(Icons.copy, size: 14),
                label: const Text('Copy to clipboard'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: colors.textSecondary,
                  side: BorderSide(color: colors.border),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _saveKeyToFile,
                icon: const Icon(Icons.save_outlined, size: 14),
                label: const Text('Save to file'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: colors.textSecondary,
                  side: BorderSide(color: colors.border),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),

        // Confirmation checkbox
        GestureDetector(
          onTap: () => setState(() => _confirmed = !_confirmed),
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            child: Row(
              children: [
                Icon(
                  _confirmed ? Icons.check_box : Icons.check_box_outline_blank,
                  size: 20,
                  color: _confirmed ? colors.accent : colors.textTertiary,
                ),
                const SizedBox(width: 8),
                Text(
                  'I\'ve saved my recovery key',
                  style: GoogleFonts.inter(fontSize: 13, color: colors.textPrimary),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),

        // Continue button
        SizedBox(
          width: double.infinity,
          height: 44,
          child: ElevatedButton(
            onPressed: _confirmed
                ? () => setState(() => _phase = _Phase.done)
                : null,
            child: const Text('Continue'),
          ),
        ),
      ],
    );
  }

  Widget _buildDone(dynamic colors) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.check_circle, size: 48, color: colors.accent),
        const SizedBox(height: 16),
        Text(
          'Encryption set up',
          style: GoogleFonts.inter(
            fontSize: 16, fontWeight: FontWeight.w600, color: colors.textPrimary,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Your messages are now secured with end-to-end encryption. Keep your recovery key safe.',
          style: GoogleFonts.inter(
            fontSize: 13, color: colors.textTertiary, height: 1.5,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 20),
        SizedBox(
          width: double.infinity,
          height: 44,
          child: ElevatedButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Done'),
          ),
        ),
      ],
    );
  }

  Widget _buildError(dynamic colors) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.error_outline, size: 48, color: colors.danger),
        const SizedBox(height: 16),
        Text(
          'Setup failed',
          style: GoogleFonts.inter(
            fontSize: 16, fontWeight: FontWeight.w600, color: colors.textPrimary,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          _error ?? 'An unknown error occurred.',
          style: GoogleFonts.inter(fontSize: 13, color: colors.textTertiary),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 20),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            OutlinedButton(
              onPressed: () => Navigator.pop(context),
              style: OutlinedButton.styleFrom(
                foregroundColor: colors.textSecondary,
                side: BorderSide(color: colors.border),
              ),
              child: const Text('Close'),
            ),
            const SizedBox(width: 10),
            ElevatedButton(
              onPressed: () {
                setState(() {
                  _phase = _Phase.generating;
                  _error = null;
                  _status = 'Creating encryption keys...';
                });
                _runBootstrap();
              },
              child: const Text('Retry'),
            ),
          ],
        ),
      ],
    );
  }
}
