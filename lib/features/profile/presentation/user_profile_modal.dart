import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:matrix/matrix.dart';

import '../../../app/theme/gloam_theme_ext.dart';
import '../../../app/theme/spacing.dart';
import '../../../services/matrix_service.dart';
import '../../../widgets/gloam_avatar.dart';
import '../../calls/presentation/providers/call_provider.dart';
import '../../chat/presentation/providers/timeline_provider.dart';
import '../providers/user_profile_provider.dart';

/// Opens the user profile overlay modal.
void showUserProfile(
  BuildContext context,
  WidgetRef ref, {
  required String userId,
  String? roomId,
}) {
  final client = ref.read(matrixServiceProvider).client;
  final isSelf = client?.userID == userId;

  showDialog(
    context: context,
    barrierColor: Colors.black54,
    builder: (_) => ProviderScope(
      parent: ProviderScope.containerOf(context),
      child: isSelf
          ? const _SelfProfileModal()
          : _UserProfileModal(userId: userId, roomId: roomId),
    ),
  );
}

class _UserProfileModal extends ConsumerWidget {
  const _UserProfileModal({required this.userId, this.roomId});

  final String userId;
  final String? roomId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profileKey = '$userId|${roomId ?? ''}';
    final profileAsync = ref.watch(userProfileProvider(profileKey));

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(40),
      child: profileAsync.when(
        data: (profile) => _ProfileCard(profile: profile),
        loading: () => _LoadingCard(),
        error: (e, _) => _ErrorCard(error: '$e', userId: userId),
      ),
    );
  }
}

class _ProfileCard extends ConsumerWidget {
  const _ProfileCard({required this.profile});

  final UserProfileData profile;

  // Deterministic banner gradient from userId hash
  static const _bannerColors = [
    [Color(0xFF1a3a2a), Color(0xFF2a4a3a), Color(0xFF1a2b2e)],
    [Color(0xFF2a1a3a), Color(0xFF3a2a4a), Color(0xFF1a1a2e)],
    [Color(0xFF3a2a1a), Color(0xFF4a3a2a), Color(0xFF2e2a1a)],
    [Color(0xFF1a2a3a), Color(0xFF2a3a4a), Color(0xFF1a2e2a)],
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorIdx = profile.userId.hashCode.abs() % _bannerColors.length;
    final colors = _bannerColors[colorIdx];

    return Container(
      width: 500,
      decoration: BoxDecoration(
        color: context.gloam.bgElevated,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.gloam.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(100),
            blurRadius: 40,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Banner
          Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                width: double.infinity,
                height: 120,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: colors,
                  ),
                ),
              ),
              // Close button
              Positioned(
                right: 10,
                top: 10,
                child: GestureDetector(
                  onTap: () => Navigator.of(context).pop(),
                  child: Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: Colors.black38,
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: Icon(Icons.close,
                          size: 14, color: context.gloam.textSecondary),
                    ),
                  ),
                ),
              ),
            ],
          ),

          // Avatar area (overlaps banner)
          Stack(
            clipBehavior: Clip.none,
            children: [
              const SizedBox(width: double.infinity, height: 56),
              Positioned(
                left: 24,
                top: -44,
                child: Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                        color: context.gloam.bgElevated, width: 5),
                  ),
                  child: GloamAvatar(
                    displayName: profile.displayName,
                    mxcUrl: profile.avatarUrl,
                    size: 88,
                  ),
                ),
              ),
              // Online dot
              if (profile.presence == 'online')
                Positioned(
                  left: 96,
                  top: 26,
                  child: Container(
                    width: 18,
                    height: 18,
                    decoration: BoxDecoration(
                      color: context.gloam.online,
                      shape: BoxShape.circle,
                      border: Border.all(
                          color: context.gloam.bgElevated, width: 4),
                    ),
                  ),
                ),
            ],
          ),

          // Body
          Padding(
            padding: const EdgeInsets.fromLTRB(28, 0, 28, 28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Name row + actions
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            profile.displayName,
                            style: GoogleFonts.inter(
                              fontSize: 22,
                              fontWeight: FontWeight.w600,
                              color: context.gloam.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            profile.userId,
                            style: GoogleFonts.jetBrainsMono(
                              fontSize: 12,
                              color: context.gloam.textTertiary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Actions
                    Row(
                      children: [
                        _ActionButton(
                          icon: Icons.chat_bubble_outline,
                          label: 'Message',
                          isPrimary: true,
                          onTap: () => _onMessage(context, ref),
                        ),
                        const SizedBox(width: 8),
                        _IconAction(
                          icon: Icons.call_outlined,
                          onTap: () => _onCall(context, ref),
                        ),
                        const SizedBox(width: 8),
                        Builder(
                          builder: (btnContext) => _IconAction(
                            icon: Icons.more_horiz,
                            onTap: () => _onMore(btnContext),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),

                const SizedBox(height: 20),
                Container(height: 1, color: context.gloam.border),
                const SizedBox(height: 20),

                // Details grid
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _DetailField(
                            label: 'server',
                            value: profile.homeserver,
                          ),
                          const SizedBox(height: 12),
                          if (profile.roleLabel != null)
                            _DetailField(
                              label: 'role',
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.shield_outlined,
                                    size: 13,
                                    color: profile.powerLevel == 100
                                        ? context.gloam.accent
                                        : context.gloam.textSecondary,
                                  ),
                                  const SizedBox(width: 5),
                                  Text(
                                    '${profile.roleLabel} (PL ${profile.powerLevel})',
                                    style: GoogleFonts.inter(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w500,
                                      color: profile.powerLevel == 100
                                          ? context.gloam.accent
                                          : context.gloam.textPrimary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _DetailField(
                            label: 'status',
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  width: 8,
                                  height: 8,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: profile.presence == 'online'
                                        ? context.gloam.online
                                        : context.gloam.textTertiary,
                                  ),
                                ),
                                const SizedBox(width: 5),
                                Text(
                                  profile.presence == 'online'
                                      ? 'Online'
                                      : 'Offline',
                                  style: GoogleFonts.inter(
                                    fontSize: 13,
                                    color: context.gloam.textPrimary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),

                // Mutual rooms
                if (profile.mutualRooms.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  Container(height: 1, color: context.gloam.border),
                  const SizedBox(height: 20),
                  Text(
                    '// ${profile.mutualRooms.length} mutual rooms',
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 10,
                      color: context.gloam.textTertiary,
                      letterSpacing: 1,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      ...profile.mutualRooms.take(5).map((r) =>
                          _RoomChip(
                            name: r.name,
                            onTap: () {
                              ref.read(selectedRoomProvider.notifier).state =
                                  r.id;
                              Navigator.of(context).pop();
                            },
                          )),
                      if (profile.mutualRooms.length > 5)
                        _RoomChip(
                          name: '+${profile.mutualRooms.length - 5}',
                          onTap: null,
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _onMessage(BuildContext context, WidgetRef ref) async {
    final client = ref.read(matrixServiceProvider).client;
    if (client == null) return;

    String? roomId = profile.existingDmId;
    if (roomId == null) {
      roomId = await client.startDirectChat(profile.userId);
    }

    if (context.mounted) {
      ref.read(selectedRoomProvider.notifier).state = roomId;
      Navigator.of(context).pop();
    }
  }

  void _onCall(BuildContext context, WidgetRef ref) async {
    final client = ref.read(matrixServiceProvider).client;
    if (client == null) return;

    String? roomId = profile.existingDmId;
    if (roomId == null) {
      roomId = await client.startDirectChat(profile.userId);
    }

    if (context.mounted) {
      ref.read(callServiceProvider.notifier).startCall(
            roomId: roomId!,
            isVideo: false,
          );
      Navigator.of(context).pop();
    }
  }

  void _onMore(BuildContext context) {
    final button = context.findRenderObject() as RenderBox;
    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox;
    final position = RelativeRect.fromRect(
      Rect.fromPoints(
        button.localToGlobal(Offset(0, button.size.height), ancestor: overlay),
        button.localToGlobal(button.size.bottomRight(Offset.zero),
            ancestor: overlay),
      ),
      Offset.zero & overlay.size,
    );

    showMenu(
      context: context,
      position: position,
      color: context.gloam.bgElevated,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: context.gloam.border),
      ),
      items: [
        PopupMenuItem(
          height: 36,
          onTap: () {
            Clipboard.setData(ClipboardData(text: profile.userId));
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Matrix ID copied'),
                duration: Duration(seconds: 2),
              ),
            );
          },
          child: Row(
            children: [
              Icon(Icons.copy, size: 14, color: context.gloam.textSecondary),
              const SizedBox(width: 8),
              Text('Copy Matrix ID',
                  style: GoogleFonts.inter(
                      fontSize: 13, color: context.gloam.textPrimary)),
            ],
          ),
        ),
      ],
    );
  }
}

// =============================================================================
// Sub-widgets
// =============================================================================

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.isPrimary = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool isPrimary;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: Material(
        color: isPrimary ? context.gloam.accentDim : context.gloam.bgSurface,
        borderRadius: BorderRadius.circular(GloamSpacing.radiusMd),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(GloamSpacing.radiusMd),
          hoverColor: isPrimary
              ? context.gloam.accent.withAlpha(30)
              : context.gloam.bgElevated,
          child: Container(
            height: 36,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(GloamSpacing.radiusMd),
              border: isPrimary
                  ? null
                  : Border.all(color: context.gloam.border),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon,
                    size: 16,
                    color: isPrimary
                        ? context.gloam.accent
                        : context.gloam.textSecondary),
                const SizedBox(width: 8),
                Text(
                  label,
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: isPrimary
                        ? context.gloam.accent
                        : context.gloam.textPrimary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _IconAction extends StatelessWidget {
  const _IconAction({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: Material(
        color: context.gloam.bgSurface,
        borderRadius: BorderRadius.circular(GloamSpacing.radiusMd),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(GloamSpacing.radiusMd),
          hoverColor: context.gloam.bgElevated,
          child: Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(GloamSpacing.radiusMd),
              border: Border.all(color: context.gloam.border),
            ),
            child: Center(
              child: Icon(icon, size: 16, color: context.gloam.textSecondary),
            ),
          ),
        ),
      ),
    );
  }
}

class _DetailField extends StatelessWidget {
  const _DetailField({required this.label, this.value, this.child});

  final String label;
  final String? value;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '// $label',
          style: GoogleFonts.jetBrainsMono(
            fontSize: 9,
            color: context.gloam.textTertiary,
            letterSpacing: 1,
          ),
        ),
        const SizedBox(height: 3),
        child ??
            Text(
              value ?? '—',
              style: GoogleFonts.jetBrainsMono(
                fontSize: 13,
                color: context.gloam.textPrimary,
              ),
            ),
      ],
    );
  }
}

class _RoomChip extends StatelessWidget {
  const _RoomChip({required this.name, this.onTap});

  final String name;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 28,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: context.gloam.bgSurface,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: context.gloam.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!name.startsWith('+'))
              Text('#  ',
                  style: GoogleFonts.jetBrainsMono(
                      fontSize: 12, color: context.gloam.textTertiary)),
            Text(
              name,
              style: GoogleFonts.inter(
                fontSize: 12,
                color: context.gloam.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LoadingCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 500,
      height: 300,
      decoration: BoxDecoration(
        color: context.gloam.bgElevated,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.gloam.border),
      ),
      child: Center(
        child: SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: context.gloam.accent,
          ),
        ),
      ),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.error, required this.userId});
  final String error;
  final String userId;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 500,
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: context.gloam.bgElevated,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.gloam.border),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(userId,
              style: GoogleFonts.jetBrainsMono(
                  fontSize: 13, color: context.gloam.textSecondary)),
          const SizedBox(height: 12),
          Text('Failed to load profile',
              style: GoogleFonts.inter(
                  fontSize: 14, color: context.gloam.textTertiary)),
        ],
      ),
    );
  }
}

// =============================================================================
// Self Profile Modal — View + Edit
// =============================================================================

class _SelfProfileModal extends ConsumerStatefulWidget {
  const _SelfProfileModal();

  @override
  ConsumerState<_SelfProfileModal> createState() => _SelfProfileModalState();
}

class _SelfProfileModalState extends ConsumerState<_SelfProfileModal> {
  bool _editing = false;
  bool _saving = false;
  late TextEditingController _nameController;
  String? _displayName;
  Uri? _avatarUrl;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController();
    _loadProfile();
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _loadProfile() async {
    final client = ref.read(matrixServiceProvider).client;
    if (client == null) return;

    try {
      final profile = await client.getProfileFromUserId(client.userID!);
      if (mounted) {
        setState(() {
          _displayName = profile.displayName ?? client.userID!.split(':').first.substring(1);
          _avatarUrl = profile.avatarUrl;
          _nameController.text = _displayName!;
          _loaded = true;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _displayName = client.userID!.split(':').first.substring(1);
          _nameController.text = _displayName!;
          _loaded = true;
        });
      }
    }
  }

  Future<void> _uploadAvatar() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowMultiple: false,
    );
    if (result == null || result.files.isEmpty) return;

    final file = result.files.first;
    final bytes = file.path != null
        ? await File(file.path!).readAsBytes()
        : file.bytes;
    if (bytes == null) return;

    setState(() => _saving = true);

    try {
      final client = ref.read(matrixServiceProvider).client!;
      final mxcUri = await client.uploadContent(bytes, filename: file.name);
      await client.setAvatarUrl(client.userID!, mxcUri);
      if (mounted) {
        setState(() {
          _avatarUrl = mxcUri;
          _saving = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to upload avatar: $e'),
              backgroundColor: context.gloam.danger),
        );
      }
    }
  }

  Future<void> _removeAvatar() async {
    setState(() => _saving = true);
    try {
      final client = ref.read(matrixServiceProvider).client!;
      await client.setAvatarUrl(client.userID!, Uri.parse(''));
      if (mounted) {
        setState(() {
          _avatarUrl = null;
          _saving = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _saveChanges() async {
    final newName = _nameController.text.trim();
    if (newName.isEmpty) return;

    setState(() => _saving = true);

    try {
      final client = ref.read(matrixServiceProvider).client!;
      if (newName != _displayName) {
        await client.setDisplayName(client.userID!, newName);
      }
      if (mounted) {
        setState(() {
          _displayName = newName;
          _saving = false;
          _editing = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save: $e'),
              backgroundColor: context.gloam.danger),
        );
      }
    }
  }

  static const _bannerColors = [
    Color(0xFF1a3a2a), Color(0xFF2a4a3a), Color(0xFF1a2b2e),
  ];

  @override
  Widget build(BuildContext context) {
    final client = ref.read(matrixServiceProvider).client;
    final userId = client?.userID ?? '';
    final homeserver = userId.contains(':') ? userId.split(':').last : '';

    if (!_loaded) {
      return Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          width: 500, height: 300,
          decoration: BoxDecoration(
            color: context.gloam.bgElevated,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: context.gloam.border),
          ),
          child: Center(
            child: SizedBox(width: 24, height: 24,
              child: CircularProgressIndicator(strokeWidth: 2, color: context.gloam.accent)),
          ),
        ),
      );
    }

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(40),
      child: Container(
        width: 500,
        decoration: BoxDecoration(
          color: context.gloam.bgElevated,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: context.gloam.border),
          boxShadow: [
            BoxShadow(color: Colors.black.withAlpha(100), blurRadius: 40,
                offset: const Offset(0, 12)),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Banner
            Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  width: double.infinity, height: 120,
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft, end: Alignment.bottomRight,
                      colors: _bannerColors,
                    ),
                  ),
                ),
                Positioned(
                  right: 10, top: 10,
                  child: GestureDetector(
                    onTap: () => Navigator.of(context).pop(),
                    child: Container(
                      width: 28, height: 28,
                      decoration: const BoxDecoration(
                        color: Colors.black38, shape: BoxShape.circle),
                      child: Center(
                        child: Icon(Icons.close, size: 14,
                            color: context.gloam.textSecondary)),
                    ),
                  ),
                ),
              ],
            ),

            // Avatar area
            Stack(
              clipBehavior: Clip.none,
              children: [
                const SizedBox(width: double.infinity, height: 56),
                Positioned(
                  left: 24, top: -44,
                  child: MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: GestureDetector(
                      onTap: _editing ? _uploadAvatar : () => setState(() => _editing = true),
                      child: Container(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: _editing ? context.gloam.accent : context.gloam.bgElevated,
                            width: 5),
                        ),
                        child: Stack(
                          children: [
                            GloamAvatar(
                              displayName: _displayName ?? '',
                              mxcUrl: _avatarUrl,
                              size: 88,
                            ),
                            // Camera overlay (always visible as badge in view, full overlay in edit)
                            if (_editing)
                              Container(
                                width: 88, height: 88,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: Colors.black.withAlpha(150),
                                ),
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    const Icon(Icons.camera_alt, size: 24,
                                        color: Colors.white70),
                                    Text('Upload', style: GoogleFonts.inter(
                                      fontSize: 10, fontWeight: FontWeight.w500,
                                      color: Colors.white60)),
                                  ],
                                ),
                              )
                            else
                              Positioned(
                                right: 0, bottom: 0,
                                child: Container(
                                  width: 28, height: 28,
                                  decoration: BoxDecoration(
                                    color: context.gloam.bgSurface,
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                        color: context.gloam.bgElevated, width: 3),
                                  ),
                                  child: Center(
                                    child: Icon(Icons.camera_alt, size: 13,
                                        color: context.gloam.textSecondary)),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),

            // Body
            Padding(
              padding: const EdgeInsets.fromLTRB(28, 0, 28, 28),
              child: _editing ? _buildEditMode(userId, homeserver) : _buildViewMode(userId, homeserver),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildViewMode(String userId, String homeserver) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Name + edit button
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_displayName ?? '', style: GoogleFonts.inter(
                    fontSize: 22, fontWeight: FontWeight.w600,
                    color: context.gloam.textPrimary)),
                  const SizedBox(height: 3),
                  Text(userId, style: GoogleFonts.jetBrainsMono(
                    fontSize: 12, color: context.gloam.textTertiary)),
                ],
              ),
            ),
            MouseRegion(
              cursor: SystemMouseCursors.click,
              child: Material(
                color: context.gloam.accentDim,
                borderRadius: BorderRadius.circular(GloamSpacing.radiusMd),
                child: InkWell(
                  onTap: () => setState(() => _editing = true),
                  borderRadius: BorderRadius.circular(GloamSpacing.radiusMd),
                  hoverColor: context.gloam.accent.withAlpha(30),
                  child: Container(
                    height: 36,
                    padding: const EdgeInsets.symmetric(horizontal: 18),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.edit, size: 14, color: context.gloam.accent),
                        const SizedBox(width: 8),
                        Text('Edit Profile', style: GoogleFonts.inter(
                          fontSize: 13, fontWeight: FontWeight.w500,
                          color: context.gloam.accent)),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),

        const SizedBox(height: 20),
        Container(height: 1, color: context.gloam.border),
        const SizedBox(height: 20),

        // Details
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _DetailField(label: 'display name', value: _displayName),
                const SizedBox(height: 12),
                _DetailField(label: 'matrix id', value: userId),
              ],
            )),
            Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _DetailField(label: 'homeserver', value: homeserver),
                const SizedBox(height: 12),
                _DetailField(label: 'device', value: 'Gloam (macOS)'),
              ],
            )),
          ],
        ),

        const SizedBox(height: 20),
        Container(height: 1, color: context.gloam.border),
        const SizedBox(height: 16),

        // Hint
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: context.gloam.bgSurface,
            borderRadius: BorderRadius.circular(GloamSpacing.radiusMd),
          ),
          child: Row(
            children: [
              Icon(Icons.info_outline, size: 13, color: context.gloam.textTertiary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Click your avatar or "Edit Profile" to upload a photo and update your display name',
                  style: GoogleFonts.inter(fontSize: 12, color: context.gloam.textTertiary),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildEditMode(String userId, String homeserver) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('// edit profile', style: GoogleFonts.jetBrainsMono(
          fontSize: 10, color: context.gloam.textTertiary, letterSpacing: 1)),
        const SizedBox(height: 20),

        // Display name
        Text('Display Name', style: GoogleFonts.inter(
          fontSize: 13, fontWeight: FontWeight.w500, color: context.gloam.textSecondary)),
        const SizedBox(height: 6),
        TextField(
          controller: _nameController,
          style: GoogleFonts.inter(fontSize: 14, color: context.gloam.textPrimary),
          decoration: InputDecoration(
            filled: true,
            fillColor: context.gloam.bgSurface,
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(GloamSpacing.radiusMd),
              borderSide: BorderSide(color: context.gloam.accent)),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(GloamSpacing.radiusMd),
              borderSide: BorderSide(color: context.gloam.accent)),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(GloamSpacing.radiusMd),
              borderSide: BorderSide(color: context.gloam.accent, width: 1.5)),
            suffixIcon: Icon(Icons.edit, size: 14, color: context.gloam.textTertiary),
          ),
        ),

        const SizedBox(height: 20),

        // Matrix ID (read-only)
        Text('Matrix ID', style: GoogleFonts.inter(
          fontSize: 13, fontWeight: FontWeight.w500, color: context.gloam.textSecondary)),
        const SizedBox(height: 6),
        Container(
          width: double.infinity, height: 40,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: context.gloam.bg,
            borderRadius: BorderRadius.circular(GloamSpacing.radiusMd),
            border: Border.all(color: context.gloam.border),
          ),
          alignment: Alignment.centerLeft,
          child: Row(
            children: [
              Expanded(
                child: Text(userId, style: GoogleFonts.jetBrainsMono(
                  fontSize: 13, color: context.gloam.textTertiary)),
              ),
              Icon(Icons.lock, size: 12, color: context.gloam.textTertiary),
            ],
          ),
        ),
        const SizedBox(height: 4),
        Text('Matrix ID cannot be changed', style: GoogleFonts.inter(
          fontSize: 11, fontStyle: FontStyle.italic, color: context.gloam.textTertiary)),

        const SizedBox(height: 20),

        // Profile picture actions
        Text('Profile Picture', style: GoogleFonts.inter(
          fontSize: 13, fontWeight: FontWeight.w500, color: context.gloam.textSecondary)),
        const SizedBox(height: 6),
        Row(
          children: [
            _EditActionButton(
              icon: Icons.upload, label: 'Upload Image',
              onTap: _uploadAvatar),
            const SizedBox(width: 8),
            if (_avatarUrl != null)
              _EditActionButton(
                icon: Icons.delete_outline, label: 'Remove',
                onTap: _removeAvatar, isDanger: true),
          ],
        ),

        const SizedBox(height: 20),
        Container(height: 1, color: context.gloam.border),
        const SizedBox(height: 20),

        // Save / Cancel
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            MouseRegion(
              cursor: SystemMouseCursors.click,
              child: Material(
                color: context.gloam.bgSurface,
                borderRadius: BorderRadius.circular(GloamSpacing.radiusMd),
                child: InkWell(
                  onTap: () => setState(() => _editing = false),
                  borderRadius: BorderRadius.circular(GloamSpacing.radiusMd),
                  hoverColor: context.gloam.bgElevated,
                  child: Container(
                    height: 36,
                    padding: const EdgeInsets.symmetric(horizontal: 18),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(GloamSpacing.radiusMd),
                      border: Border.all(color: context.gloam.border)),
                    child: Center(
                      child: Text('Cancel', style: GoogleFonts.inter(
                        fontSize: 13, color: context.gloam.textSecondary)),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            MouseRegion(
              cursor: SystemMouseCursors.click,
              child: Material(
                color: context.gloam.accentDim,
                borderRadius: BorderRadius.circular(GloamSpacing.radiusMd),
                child: InkWell(
                  onTap: _saving ? null : _saveChanges,
                  borderRadius: BorderRadius.circular(GloamSpacing.radiusMd),
                  hoverColor: context.gloam.accent.withAlpha(30),
                  child: Container(
                    height: 36,
                    padding: const EdgeInsets.symmetric(horizontal: 18),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (_saving)
                          SizedBox(width: 14, height: 14,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: context.gloam.accent))
                        else
                          Icon(Icons.check, size: 14, color: context.gloam.accent),
                        const SizedBox(width: 8),
                        Text('Save Changes', style: GoogleFonts.inter(
                          fontSize: 13, fontWeight: FontWeight.w500,
                          color: context.gloam.accent)),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _EditActionButton extends StatelessWidget {
  const _EditActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.isDanger = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool isDanger;

  @override
  Widget build(BuildContext context) {
    final color = isDanger ? context.gloam.danger : context.gloam.textSecondary;
    final textColor = isDanger ? context.gloam.danger : context.gloam.textPrimary;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: Material(
        color: context.gloam.bgSurface,
        borderRadius: BorderRadius.circular(GloamSpacing.radiusMd),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(GloamSpacing.radiusMd),
          hoverColor: context.gloam.bgElevated,
          child: Container(
            height: 36,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(GloamSpacing.radiusMd),
              border: Border.all(color: context.gloam.border)),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 14, color: color),
                const SizedBox(width: 6),
                Text(label, style: GoogleFonts.inter(
                    fontSize: 13, color: textColor)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
