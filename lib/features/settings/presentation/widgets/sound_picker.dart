import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../app/theme/gloam_theme_ext.dart';
import '../../../../app/theme/spacing.dart';
import '../../../../data/notification_sounds.dart';

/// Modal sound picker with preview playback.
///
/// Shows built-in sounds, custom user sounds, an "add custom" button,
/// and a "silent" option. Returns the selected sound ID or null if dismissed.
Future<String?> showSoundPicker(
  BuildContext context, {
  required String currentSound,
  bool showUseDefault = false,
}) async {
  return showDialog<String>(
    context: context,
    builder: (ctx) => _SoundPickerDialog(
      currentSound: currentSound,
      showUseDefault: showUseDefault,
    ),
  );
}

class _SoundPickerDialog extends StatefulWidget {
  const _SoundPickerDialog({
    required this.currentSound,
    this.showUseDefault = false,
  });

  final String currentSound;
  final bool showUseDefault;

  @override
  State<_SoundPickerDialog> createState() => _SoundPickerDialogState();
}

class _SoundPickerDialogState extends State<_SoundPickerDialog> {
  final _player = AudioPlayer();
  List<NotificationSoundEntry> _customSounds = [];
  bool _loadingCustom = true;

  @override
  void initState() {
    super.initState();
    _loadCustomSounds();
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  Future<void> _loadCustomSounds() async {
    final custom = await getCustomSounds();
    if (mounted) setState(() { _customSounds = custom; _loadingCustom = false; });
  }

  Future<void> _preview(NotificationSoundEntry sound) async {
    await _player.stop();
    if (sound.isBuiltIn) {
      await _player.play(AssetSource('sounds/${sound.id}.wav'));
    } else {
      await _player.play(DeviceFileSource(sound.id));
    }
  }

  Future<void> _addCustomSound() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['wav', 'mp3', 'aiff', 'm4a', 'ogg'],
    );
    if (result == null || result.files.isEmpty) return;

    final sourcePath = result.files.first.path;
    if (sourcePath == null) return;

    final sourceFile = File(sourcePath);
    final fileName = sourcePath.split('/').last.split('\\').last;

    // Validate size (< 5MB)
    final size = await sourceFile.length();
    if (size > 5 * 1024 * 1024) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Sound file must be under 5 MB'),
            backgroundColor: context.gloam.danger,
          ),
        );
      }
      return;
    }

    // Copy to app sounds dir
    final dir = await getCustomSoundsDir();
    final destPath = '${dir.path}/$fileName';
    await sourceFile.copy(destPath);

    await _loadCustomSounds();
  }

  Future<void> _deleteCustomSound(NotificationSoundEntry sound) async {
    final file = File(sound.id);
    if (await file.exists()) await file.delete();
    await _loadCustomSounds();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.gloam;
    return Dialog(
      backgroundColor: colors.bgElevated,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(GloamSpacing.radiusMd),
        side: BorderSide(color: colors.border),
      ),
      child: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 12, 16),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'notification sound',
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: 12,
                        color: colors.textSecondary,
                        fontWeight: FontWeight.w500,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: Icon(Icons.close, size: 16, color: colors.textTertiary),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                  ),
                ],
              ),
            ),

            Container(height: 1, color: colors.border),

            // Sound list
            Flexible(
              child: ListView(
                shrinkWrap: true,
                padding: EdgeInsets.zero,
                children: [
                  // Use default option (for per-room picker)
                  if (widget.showUseDefault)
                    _SoundRow(
                      icon: Icons.refresh,
                      label: 'Use default',
                      isSelected: widget.currentSound == 'default',
                      onTap: () => Navigator.pop(context, 'default'),
                    ),

                  // Built-in section header
                  _sectionHeader(colors, 'built-in'),

                  // Built-in sounds
                  for (final sound in builtInSounds)
                    _SoundRow(
                      icon: Icons.play_arrow,
                      label: sound.displayName,
                      isSelected: widget.currentSound == sound.id,
                      onTap: () => Navigator.pop(context, sound.id),
                      onPlay: () => _preview(sound),
                    ),

                  // Custom section
                  if (!_loadingCustom && _customSounds.isNotEmpty) ...[
                    Container(height: 1, color: colors.borderSubtle),
                    _sectionHeader(colors, 'custom'),
                    for (final sound in _customSounds)
                      _SoundRow(
                        icon: Icons.play_arrow,
                        label: sound.displayName,
                        isSelected: widget.currentSound == sound.id,
                        onTap: () => Navigator.pop(context, sound.id),
                        onPlay: () => _preview(sound),
                        onDelete: () => _deleteCustomSound(sound),
                      ),
                  ],

                  // Add custom
                  _SoundRow(
                    icon: Icons.add,
                    label: 'Add custom sound...',
                    isAccent: true,
                    onTap: _addCustomSound,
                  ),

                  // Silent
                  Container(height: 1, color: colors.borderSubtle),
                  _SoundRow(
                    icon: Icons.volume_off,
                    label: 'Silent',
                    isSelected: widget.currentSound == 'silent',
                    onTap: () => Navigator.pop(context, 'silent'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionHeader(dynamic colors, String text) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
      child: Text(
        '// $text',
        style: GoogleFonts.jetBrainsMono(
          fontSize: 10,
          color: colors.textTertiary,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

class _SoundRow extends StatelessWidget {
  const _SoundRow({
    required this.icon,
    required this.label,
    this.isSelected = false,
    this.isAccent = false,
    this.onTap,
    this.onPlay,
    this.onDelete,
  });

  final IconData icon;
  final String label;
  final bool isSelected;
  final bool isAccent;
  final VoidCallback? onTap;
  final VoidCallback? onPlay;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final colors = context.gloam;
    return Material(
      color: isSelected ? colors.accentDim : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        hoverColor: colors.bgSurface,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          child: Row(
            children: [
              if (onPlay != null)
                GestureDetector(
                  onTap: onPlay,
                  child: MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: Icon(icon, size: 14,
                        color: isSelected ? colors.accentBright : colors.textTertiary),
                  ),
                )
              else
                Icon(icon, size: 14,
                    color: isAccent ? colors.accent : colors.textTertiary),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    color: isAccent ? colors.accent : colors.textPrimary,
                  ),
                ),
              ),
              if (onDelete != null)
                GestureDetector(
                  onTap: onDelete,
                  child: MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: Icon(Icons.delete_outline, size: 14,
                        color: colors.textTertiary),
                  ),
                ),
              if (isSelected)
                Icon(Icons.check, size: 14, color: colors.accentBright),
            ],
          ),
        ),
      ),
    );
  }
}
