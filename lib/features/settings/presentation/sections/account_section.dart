import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../app/theme/gloam_theme_ext.dart';
import '../../../../services/matrix_service.dart';
import '../../../../widgets/gloam_avatar.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../widgets/settings_tile.dart';

class AccountSection extends ConsumerWidget {
  const AccountSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final client = ref.watch(matrixServiceProvider).client;
    final displayName = client?.userID ?? 'Unknown';
    final userId = client?.userID ?? '';
    final deviceId = client?.deviceID ?? '';
    final deviceName = client?.deviceName ?? 'Gloam';

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        // Profile card
        Center(
          child: Column(
            children: [
              GloamAvatar(
                displayName: displayName,
                mxcUrl: client?.ownProfile.then((p) => p.avatarUrl) != null
                    ? null
                    : null, // Avatar loading is async; show letter fallback
                size: 72,
                borderRadius: 20,
              ),
              const SizedBox(height: 12),
              Text(
                displayName,
                style: GoogleFonts.inter(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: context.gloam.textPrimary,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                userId,
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 12,
                  color: context.gloam.textTertiary,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),

        const SettingsSectionHeader('session'),
        SettingsTile(
          icon: Icons.smartphone,
          label: 'device name',
          value: deviceName,
        ),
        SettingsTile(
          icon: Icons.fingerprint,
          label: 'device ID',
          value: deviceId,
        ),

        const SettingsSectionHeader('account'),
        SettingsTile(
          icon: Icons.edit_outlined,
          label: 'edit display name',
          onTap: () {},
        ),
        SettingsTile(
          icon: Icons.image_outlined,
          label: 'change avatar',
          onTap: () {},
        ),

        const SizedBox(height: 32),
        const SettingsSectionHeader('danger zone'),
        SettingsTile(
          icon: Icons.logout,
          label: 'sign out',
          danger: true,
          onTap: () => _confirmLogout(context, ref),
        ),
      ],
    );
  }

  void _confirmLogout(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      barrierColor: context.gloam.overlay,
      builder: (ctx) => AlertDialog(
        backgroundColor: ctx.gloam.bgSurface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: ctx.gloam.border),
        ),
        title: Text(
          'sign out?',
          style: GoogleFonts.jetBrainsMono(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: ctx.gloam.textPrimary,
          ),
        ),
        content: Text(
          'you\'ll need your recovery key to access message history on a new session.',
          style: GoogleFonts.inter(
            fontSize: 13,
            color: ctx.gloam.textSecondary,
            height: 1.5,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('cancel',
                style: GoogleFonts.jetBrainsMono(
                    fontSize: 12, color: ctx.gloam.textSecondary)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: ctx.gloam.danger,
            ),
            onPressed: () async {
              Navigator.pop(ctx); // close dialog
              Navigator.pop(context); // close settings modal
              await ref.read(authProvider.notifier).logout();
              if (context.mounted) context.go('/sign-in');
            },
            child: Text('sign out',
                style: GoogleFonts.jetBrainsMono(
                    fontSize: 12, color: ctx.gloam.textPrimary)),
          ),
        ],
      ),
    );
  }
}
