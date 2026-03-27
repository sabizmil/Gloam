import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:matrix/matrix.dart';

import '../../../app/theme/color_tokens.dart';
import '../../../app/theme/spacing.dart';
import '../../../services/matrix_service.dart';
import '../../chat/presentation/providers/timeline_provider.dart';

/// Dialog to enter recovery key / passphrase to unlock key backup
/// and decrypt historical messages.
class RecoveryKeyDialog extends ConsumerStatefulWidget {
  const RecoveryKeyDialog({super.key});

  @override
  ConsumerState<RecoveryKeyDialog> createState() => _RecoveryKeyDialogState();
}

class _RecoveryKeyDialogState extends ConsumerState<RecoveryKeyDialog> {
  final _controller = TextEditingController();
  bool _loading = false;
  String? _error;
  String? _status;
  bool _success = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _unlock() async {
    final input = _controller.text.trim();
    if (input.isEmpty) return;

    setState(() {
      _loading = true;
      _error = null;
      _status = 'unlocking secrets...';
    });

    try {
      final client = ref.read(matrixServiceProvider).client;
      if (client?.encryption == null) {
        setState(() {
          _error = 'encryption not initialized';
          _loading = false;
        });
        return;
      }

      final ssss = client!.encryption!.ssss;
      if (ssss.defaultKeyId == null) {
        setState(() {
          _error = 'no key backup found on server';
          _loading = false;
        });
        return;
      }

      // Step 1: Unlock SSSS (caches secrets including backup decryption key)
      final keyInfo = ssss.open();
      await keyInfo.unlock(keyOrPassphrase: input);

      if (!mounted) return;
      setState(() => _status = 'downloading keys from backup...');

      // Step 2: Check key backup status and cache state
      final keyManager = client.encryption!.keyManager;
      final isCached = await keyManager.isCached();

      if (!isCached) {
        // Manually cache the megolm backup key from SSSS
        await keyInfo.maybeCacheAll();
      }

      // Step 3: Download and import keys from backup
      try {
        await keyManager.loadAllKeys();
      } catch (_) {
        // Best-effort — continue even if backup import fails
      }

      // Step 4: Re-decrypt still-encrypted events in all encrypted rooms
      if (!mounted) return;
      setState(() => _status = 'decrypting messages...');

      var totalDecrypted = 0;
      var totalFailed = 0;
      for (final room in client.rooms) {
        if (!room.encrypted) continue;
        final timeline = await room.getTimeline();
        for (var i = 0; i < timeline.events.length; i++) {
          if (timeline.events[i].type == EventTypes.Encrypted) {
            try {
              final decrypted = await client.encryption!.decryptRoomEvent(
                timeline.events[i],
                store: true,
                updateType: EventUpdateType.history,
              );
              if (decrypted.type != EventTypes.Encrypted) {
                timeline.events[i] = decrypted;
                totalDecrypted++;
              } else {
                totalFailed++;
              }
            } catch (e) {
              totalFailed++;
            }
          }
        }
        if (totalDecrypted > 0) {
          timeline.onUpdate?.call();
        }
      }
      // Continue to key requests if some events are still encrypted

      // Step 5: For sessions still missing, request keys from other devices
      if (totalFailed > 0) {
        if (!mounted) return;
        setState(() => _status = 'requesting missing keys from other devices...');

        final missingSessionIds = <String>{};
        for (final room in client.rooms) {
          if (!room.encrypted) continue;
          final timeline = await room.getTimeline();
          for (final event in timeline.events) {
            if (event.type == EventTypes.Encrypted) {
              final sid = event.content.tryGet<String>('session_id');
              final senderKey = event.content.tryGet<String>('sender_key');
              if (sid != null && senderKey != null && missingSessionIds.add(sid)) {
                client.encryption!.keyManager.maybeAutoRequest(
                  room.id,
                  sid,
                  senderKey,
                  tryOnlineBackup: false,
                  onlineKeyBackupOnly: false,
                );
              }
            }
          }
        }
      }

      // Invalidate all active timeline providers so they reload from DB
      for (final room in client.rooms) {
        ref.invalidate(timelineProvider(room.id));
      }

      if (!mounted) return;
      setState(() {
        _success = true;
        _loading = false;
        _status = null;
      });

      await Future.delayed(const Duration(seconds: 2));
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      setState(() {
        _error = e.toString().contains('Inalid')
            ? 'invalid recovery key or passphrase'
            : e.toString();
        _loading = false;
        _status = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: GloamColors.bgSurface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(GloamSpacing.radiusLg),
        side: const BorderSide(color: GloamColors.border),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'unlock message history',
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: GloamColors.textPrimary,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'enter your recovery key or passphrase to decrypt older messages',
                style: GoogleFonts.inter(
                  fontSize: 13,
                  color: GloamColors.textSecondary,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 20),

              Text(
                '// recovery key or passphrase',
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 10,
                  color: GloamColors.textTertiary,
                  letterSpacing: 1,
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _controller,
                maxLines: 3,
                minLines: 1,
                enabled: !_loading && !_success,
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 13,
                  color: GloamColors.textPrimary,
                ),
                decoration: const InputDecoration(
                  hintText: 'EsTV b9hM...',
                ),
                onSubmitted: (_) => _unlock(),
              ),

              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(
                  _error!,
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    color: GloamColors.danger,
                  ),
                ),
              ],

              if (_status != null && !_success) ...[
                const SizedBox(height: 12),
                Row(
                  children: [
                    const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 1.5,
                        color: GloamColors.accentDim,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _status!,
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: 11,
                        color: GloamColors.textTertiary,
                      ),
                    ),
                  ],
                ),
              ],

              if (_success) ...[
                const SizedBox(height: 12),
                Row(
                  children: [
                    const Icon(Icons.check_circle,
                        size: 16, color: GloamColors.accent),
                    const SizedBox(width: 8),
                    Text(
                      'keys restored — messages decrypting...',
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: 11,
                        color: GloamColors.accent,
                      ),
                    ),
                  ],
                ),
              ],

              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  OutlinedButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('cancel'),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton(
                    onPressed: _loading || _success ? null : _unlock,
                    child: _loading
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: GloamColors.bg,
                            ),
                          )
                        : const Text('unlock'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Future<bool?> showRecoveryKeyDialog(BuildContext context) {
  return showDialog<bool>(
    context: context,
    barrierColor: GloamColors.overlay,
    builder: (_) => const RecoveryKeyDialog(),
  );
}
