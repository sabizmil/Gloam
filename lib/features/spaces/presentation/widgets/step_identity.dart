import 'dart:async';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:matrix/matrix.dart';

import '../../../../app/theme/gloam_theme_ext.dart';
import '../../../../app/theme/spacing.dart';
import '../../../../services/matrix_service.dart';

/// Step 1: Space name, avatar, topic, visibility, alias.
class StepIdentity extends ConsumerStatefulWidget {
  const StepIdentity({
    super.key,
    required this.name,
    required this.topic,
    required this.avatar,
    required this.isPublic,
    required this.alias,
    required this.aliasError,
    required this.onNameChanged,
    required this.onTopicChanged,
    required this.onAvatarChanged,
    required this.onVisibilityChanged,
    required this.onAliasChanged,
    required this.onAliasError,
  });

  final String name;
  final String? topic;
  final Uint8List? avatar;
  final bool isPublic;
  final String? alias;
  final String? aliasError;
  final ValueChanged<String> onNameChanged;
  final ValueChanged<String?> onTopicChanged;
  final ValueChanged<Uint8List?> onAvatarChanged;
  final ValueChanged<bool> onVisibilityChanged;
  final ValueChanged<String?> onAliasChanged;
  final ValueChanged<String?> onAliasError;

  @override
  ConsumerState<StepIdentity> createState() => _StepIdentityState();
}

class _StepIdentityState extends ConsumerState<StepIdentity> {
  late TextEditingController _nameController;
  late TextEditingController _topicController;
  late TextEditingController _aliasController;
  Timer? _aliasDebounce;
  bool _aliasChecking = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.name);
    _topicController = TextEditingController(text: widget.topic ?? '');
    _aliasController = TextEditingController(text: widget.alias ?? '');
  }

  @override
  void dispose() {
    _nameController.dispose();
    _topicController.dispose();
    _aliasController.dispose();
    _aliasDebounce?.cancel();
    super.dispose();
  }

  Future<void> _pickAvatar() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowMultiple: false,
      withData: true,
    );
    if (result != null && result.files.single.bytes != null) {
      widget.onAvatarChanged(result.files.single.bytes!);
    }
  }

  void _onAliasChanged(String value) {
    widget.onAliasChanged(value);
    widget.onAliasError(null);
    _aliasDebounce?.cancel();

    if (value.trim().isEmpty) return;

    _aliasDebounce = Timer(const Duration(milliseconds: 500), () {
      _validateAlias(value.trim());
    });
  }

  Future<void> _validateAlias(String alias) async {
    final client = ref.read(matrixServiceProvider).client;
    if (client == null) return;

    setState(() => _aliasChecking = true);

    try {
      final host = client.homeserver?.host ?? '';
      await client.getRoomIdByAlias('#$alias:$host');
      // If we get here, alias is taken
      widget.onAliasError('This address is already in use');
    } on MatrixException catch (e) {
      if (e.error == MatrixError.M_NOT_FOUND) {
        widget.onAliasError(null); // Available
      } else {
        widget.onAliasError(e.errorMessage);
      }
    } catch (_) {
      widget.onAliasError(null); // Assume available on network error
    } finally {
      if (mounted) setState(() => _aliasChecking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.gloam;
    final client = ref.read(matrixServiceProvider).client;
    final host = client?.homeserver?.host ?? 'server';

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Avatar + Name row
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Avatar upload
              GestureDetector(
                onTap: _pickAvatar,
                child: Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: colors.bgElevated,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: colors.border),
                    image: widget.avatar != null
                        ? DecorationImage(
                            image: MemoryImage(widget.avatar!),
                            fit: BoxFit.cover,
                          )
                        : null,
                  ),
                  child: widget.avatar == null
                      ? Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.add_a_photo_outlined,
                                size: 18, color: colors.textTertiary),
                            const SizedBox(height: 2),
                            Text(
                              'icon',
                              style: GoogleFonts.jetBrainsMono(
                                fontSize: 8,
                                color: colors.textTertiary,
                              ),
                            ),
                          ],
                        )
                      : null,
                ),
              ),
              const SizedBox(width: 16),
              // Name + Topic fields
              Expanded(
                child: Column(
                  children: [
                    TextField(
                      controller: _nameController,
                      autofocus: true,
                      onChanged: widget.onNameChanged,
                      style: GoogleFonts.inter(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                        color: colors.textPrimary,
                      ),
                      decoration: InputDecoration(
                        hintText: 'Space name',
                        hintStyle: GoogleFonts.inter(
                          fontSize: 16,
                          color: colors.textTertiary,
                        ),
                        filled: true,
                        fillColor: colors.bgElevated,
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 12),
                        border: OutlineInputBorder(
                          borderRadius:
                              BorderRadius.circular(GloamSpacing.radiusMd),
                          borderSide: BorderSide(color: colors.border),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius:
                              BorderRadius.circular(GloamSpacing.radiusMd),
                          borderSide: BorderSide(color: colors.border),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius:
                              BorderRadius.circular(GloamSpacing.radiusMd),
                          borderSide: BorderSide(color: colors.accent),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _topicController,
                      onChanged: widget.onTopicChanged,
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        color: colors.textPrimary,
                      ),
                      decoration: InputDecoration(
                        hintText: "What's this space about?",
                        hintStyle: GoogleFonts.inter(
                          fontSize: 13,
                          color: colors.textTertiary,
                        ),
                        filled: true,
                        fillColor: colors.bgElevated,
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 10),
                        border: OutlineInputBorder(
                          borderRadius:
                              BorderRadius.circular(GloamSpacing.radiusMd),
                          borderSide: BorderSide(color: colors.border),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius:
                              BorderRadius.circular(GloamSpacing.radiusMd),
                          borderSide: BorderSide(color: colors.border),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius:
                              BorderRadius.circular(GloamSpacing.radiusMd),
                          borderSide: BorderSide(color: colors.accent),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 28),

          // Visibility label
          Text(
            '// visibility',
            style: GoogleFonts.jetBrainsMono(
              fontSize: 10,
              color: colors.textTertiary,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 10),

          // Visibility cards
          Row(
            children: [
              _VisibilityCard(
                icon: Icons.public,
                label: 'Public',
                description: 'Anyone can find and join',
                isSelected: widget.isPublic,
                onTap: () => widget.onVisibilityChanged(true),
              ),
              const SizedBox(width: 12),
              _VisibilityCard(
                icon: Icons.lock_outline,
                label: 'Private',
                description: 'Invite only',
                isSelected: !widget.isPublic,
                onTap: () => widget.onVisibilityChanged(false),
              ),
            ],
          ),

          // Public alias field
          if (widget.isPublic) ...[
            const SizedBox(height: 20),
            Text(
              '// space address',
              style: GoogleFonts.jetBrainsMono(
                fontSize: 10,
                color: colors.textTertiary,
                letterSpacing: 1,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _aliasController,
              onChanged: _onAliasChanged,
              style: GoogleFonts.jetBrainsMono(
                fontSize: 13,
                color: colors.textPrimary,
              ),
              decoration: InputDecoration(
                hintText: 'my-space',
                hintStyle: GoogleFonts.jetBrainsMono(
                  fontSize: 13,
                  color: colors.textTertiary,
                ),
                prefixIcon: Padding(
                  padding: const EdgeInsets.only(left: 14, right: 2),
                  child: Text(
                    '#',
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 16,
                      color: colors.accent,
                    ),
                  ),
                ),
                prefixIconConstraints:
                    const BoxConstraints(minWidth: 0, minHeight: 0),
                suffixIcon: _aliasChecking
                    ? Padding(
                        padding: const EdgeInsets.all(12),
                        child: SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: colors.accent,
                          ),
                        ),
                      )
                    : Padding(
                        padding: const EdgeInsets.only(right: 14),
                        child: Text(
                          ':$host',
                          style: GoogleFonts.jetBrainsMono(
                            fontSize: 12,
                            color: colors.textTertiary,
                          ),
                        ),
                      ),
                suffixIconConstraints:
                    const BoxConstraints(minWidth: 0, minHeight: 0),
                filled: true,
                fillColor: colors.bgElevated,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                border: OutlineInputBorder(
                  borderRadius:
                      BorderRadius.circular(GloamSpacing.radiusMd),
                  borderSide: BorderSide(
                    color: widget.aliasError != null
                        ? colors.danger
                        : colors.border,
                  ),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius:
                      BorderRadius.circular(GloamSpacing.radiusMd),
                  borderSide: BorderSide(
                    color: widget.aliasError != null
                        ? colors.danger
                        : colors.border,
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius:
                      BorderRadius.circular(GloamSpacing.radiusMd),
                  borderSide: BorderSide(
                    color: widget.aliasError != null
                        ? colors.danger
                        : colors.accent,
                  ),
                ),
              ),
            ),
            if (widget.aliasError != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  widget.aliasError!,
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    color: colors.danger,
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _VisibilityCard extends StatelessWidget {
  const _VisibilityCard({
    required this.icon,
    required this.label,
    required this.description,
    required this.isSelected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String description;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.gloam;
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: isSelected ? colors.accentDim : Colors.transparent,
            borderRadius: BorderRadius.circular(GloamSpacing.radiusMd),
            border: Border.all(
              color: isSelected ? colors.accent : colors.border,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                icon,
                size: 20,
                color: isSelected ? colors.accent : colors.textTertiary,
              ),
              const SizedBox(height: 8),
              Text(
                label,
                style: GoogleFonts.inter(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: isSelected
                      ? colors.textPrimary
                      : colors.textSecondary,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                description,
                style: GoogleFonts.inter(
                  fontSize: 11,
                  color: colors.textTertiary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
