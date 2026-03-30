import 'package:flutter/material.dart' hide Visibility;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:matrix/matrix.dart';

import '../../../../app/theme/gloam_theme_ext.dart';
import '../../../../app/theme/spacing.dart';
import '../../../../services/matrix_service.dart';

enum _RoomType { channel, private_, dm }

/// Create room dialog matching the Pencil mockup:
/// type selector, name, topic, encryption toggle, invite field.
class CreateRoomDialog extends ConsumerStatefulWidget {
  const CreateRoomDialog({super.key});

  @override
  ConsumerState<CreateRoomDialog> createState() => _CreateRoomDialogState();
}

class _CreateRoomDialogState extends ConsumerState<CreateRoomDialog> {
  _RoomType _type = _RoomType.channel;
  final _nameController = TextEditingController();
  final _topicController = TextEditingController();
  bool _encrypted = true;
  bool _creating = false;

  @override
  void dispose() {
    _nameController.dispose();
    _topicController.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) return;

    setState(() => _creating = true);

    final client = ref.read(matrixServiceProvider).client;
    if (client == null) return;

    try {
      final roomId = await client.createRoom(
        name: name,
        topic: _topicController.text.trim().isEmpty
            ? null
            : _topicController.text.trim(),
        visibility: _type == _RoomType.channel
            ? Visibility.public
            : Visibility.private,
        preset: _type == _RoomType.channel
            ? CreateRoomPreset.publicChat
            : CreateRoomPreset.privateChat,
        initialState: _encrypted
            ? [
                StateEvent(
                  type: EventTypes.Encryption,
                  stateKey: '',
                  content: {'algorithm': 'm.megolm.v1.aes-sha2'},
                ),
              ]
            : null,
        isDirect: _type == _RoomType.dm,
      );

      if (mounted) Navigator.pop(context, roomId);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to create room: $e'),
            backgroundColor: context.gloam.danger,
          ),
        );
        setState(() => _creating = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: context.gloam.bgSurface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(GloamSpacing.radiusLg),
        side: BorderSide(color: context.gloam.border),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Container(
              height: 56,
              padding: const EdgeInsets.symmetric(horizontal: 24),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: context.gloam.border),
                ),
              ),
              child: Row(
                children: [
                  Text(
                    'create room',
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: context.gloam.textPrimary,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const Spacer(),
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Icon(Icons.close,
                        size: 18, color: context.gloam.textTertiary),
                  ),
                ],
              ),
            ),

            // Body
            Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Room type selector
                  Text(
                    '// room type',
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 10,
                      color: context.gloam.textTertiary,
                      letterSpacing: 1,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      _TypeCard(
                        icon: Icons.tag,
                        label: 'channel',
                        isSelected: _type == _RoomType.channel,
                        onTap: () =>
                            setState(() => _type = _RoomType.channel),
                      ),
                      const SizedBox(width: 10),
                      _TypeCard(
                        icon: Icons.lock_outline,
                        label: 'private',
                        isSelected: _type == _RoomType.private_,
                        onTap: () =>
                            setState(() => _type = _RoomType.private_),
                      ),
                      const SizedBox(width: 10),
                      _TypeCard(
                        icon: Icons.chat_bubble_outline,
                        label: 'DM',
                        isSelected: _type == _RoomType.dm,
                        onTap: () => setState(() => _type = _RoomType.dm),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),

                  // Name
                  Text(
                    '// room name',
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 10,
                      color: context.gloam.textTertiary,
                      letterSpacing: 1,
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _nameController,
                    decoration: InputDecoration(
                      hintText: 'e.g. design-reviews',
                      prefixIcon: Padding(
                        padding: const EdgeInsets.only(left: 14, right: 4),
                        child: Text(
                          '#',
                          style: GoogleFonts.jetBrainsMono(
                            fontSize: 16,
                            color: context.gloam.textTertiary,
                          ),
                        ),
                      ),
                      prefixIconConstraints:
                          const BoxConstraints(minWidth: 0, minHeight: 0),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Topic
                  Text(
                    '// topic (optional)',
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 10,
                      color: context.gloam.textTertiary,
                      letterSpacing: 1,
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _topicController,
                    decoration: const InputDecoration(
                      hintText: "what's this room about?",
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Encryption toggle
                  Row(
                    children: [
                      Icon(Icons.shield_outlined,
                          size: 16, color: context.gloam.accent),
                      const SizedBox(width: 8),
                      Text(
                        'enable encryption',
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          color: context.gloam.textPrimary,
                        ),
                      ),
                      const Spacer(),
                      Switch(
                        value: _encrypted,
                        onChanged: (v) => setState(() => _encrypted = v),
                        activeThumbColor: context.gloam.accent,
                        activeTrackColor: context.gloam.accentDim,
                        inactiveThumbColor: context.gloam.textTertiary,
                        inactiveTrackColor: context.gloam.bgElevated,
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // Footer
            Container(
              height: 64,
              padding: const EdgeInsets.symmetric(horizontal: 24),
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(color: context.gloam.border),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('cancel'),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton(
                    onPressed: _creating ? null : _create,
                    child: _creating
                        ? SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: context.gloam.bg,
                            ),
                          )
                        : const Text('create room'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TypeCard extends StatelessWidget {
  const _TypeCard({
    required this.icon,
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          height: 80,
          decoration: BoxDecoration(
            color: isSelected ? context.gloam.accentDim : Colors.transparent,
            borderRadius: BorderRadius.circular(GloamSpacing.radiusMd),
            border: Border.all(
              color: isSelected ? context.gloam.accent : context.gloam.border,
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 18,
                color: isSelected
                    ? context.gloam.accent
                    : context.gloam.textTertiary,
              ),
              const SizedBox(height: 6),
              Text(
                label,
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 11,
                  color: isSelected
                      ? context.gloam.accent
                      : context.gloam.textSecondary,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Shows the create room dialog and returns the new room ID (if created).
Future<String?> showCreateRoomDialog(BuildContext context) {
  return showDialog<String>(
    context: context,
    barrierColor: context.gloam.overlay,
    builder: (_) => const CreateRoomDialog(),
  );
}
