import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../theme/gloam_theme_ext.dart';
import '../../../features/auth/presentation/providers/auth_provider.dart';
import '../../../features/settings/presentation/settings_modal.dart';
import '../../../services/matrix_service.dart';
import '../../../widgets/gloam_avatar.dart';

class _OwnProfile {
  const _OwnProfile({required this.displayName, required this.userId, this.avatarUrl});
  final String displayName;
  final String userId;
  final Uri? avatarUrl;
}

/// Loads the current user's profile via the Matrix SDK. Cached for the
/// session; refetching only happens if the provider is invalidated.
final _ownProfileProvider = FutureProvider<_OwnProfile?>((ref) async {
  final client = ref.watch(matrixServiceProvider).client;
  if (client == null || client.userID == null) return null;
  final userId = client.userID!;
  try {
    final profile = await client.getProfileFromUserId(userId);
    return _OwnProfile(
      displayName:
          profile.displayName ?? userId.split(':').first.replaceFirst('@', ''),
      userId: userId,
      avatarUrl: profile.avatarUrl,
    );
  } catch (_) {
    return _OwnProfile(
      displayName: userId.split(':').first.replaceFirst('@', ''),
      userId: userId,
    );
  }
});

/// Mobile `me` tab — profile header + settings + log out.
/// Settings modal carries the full config surface (appearance, notifications,
/// account, encryption, server, about) on its own responsive layout, so the
/// me tab itself stays intentionally shallow.
class MeScreen extends ConsumerWidget {
  const MeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profileAsync = ref.watch(_ownProfileProvider);
    final profile = profileAsync.valueOrNull;

    return Column(
      children: [
        _ProfileHeader(
          displayName: profile?.displayName ?? '',
          userId: profile?.userId ?? '',
          avatarUrl: profile?.avatarUrl,
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.symmetric(vertical: 8),
            children: [
              _MeRow(
                icon: Icons.settings_outlined,
                label: 'Settings',
                sublabel:
                    'appearance, notifications, account, encryption, server',
                onTap: () => showSettingsModal(context),
              ),
              _MeRow(
                icon: Icons.logout,
                label: 'Log out',
                sublabel: null,
                danger: true,
                onTap: () => _confirmLogout(context, ref),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _confirmLogout(BuildContext context, WidgetRef ref) async {
    final colors = context.gloam;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: colors.bgSurface,
        title: Text(
          'log out?',
          style: GoogleFonts.jetBrainsMono(
            fontSize: 14,
            color: colors.textPrimary,
          ),
        ),
        content: Text(
          'you\'ll need to sign in again to see your messages.',
          style: GoogleFonts.inter(
            fontSize: 13,
            color: colors.textSecondary,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: colors.danger),
            child: const Text('log out'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await ref.read(authProvider.notifier).logout();
    }
  }
}

class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader({
    required this.displayName,
    required this.userId,
    required this.avatarUrl,
  });

  final String displayName;
  final String userId;
  final Uri? avatarUrl;

  @override
  Widget build(BuildContext context) {
    final colors = context.gloam;
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: colors.borderSubtle)),
      ),
      child: Row(
        children: [
          GloamAvatar(
            displayName: displayName,
            mxcUrl: avatarUrl,
            size: 56,
            borderRadius: 28,
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  displayName,
                  style: GoogleFonts.inter(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: colors.textPrimary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  userId,
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 11,
                    color: colors.textTertiary,
                    letterSpacing: 0.3,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MeRow extends StatelessWidget {
  const _MeRow({
    required this.icon,
    required this.label,
    required this.sublabel,
    required this.onTap,
    this.danger = false,
  });

  final IconData icon;
  final String label;
  final String? sublabel;
  final VoidCallback onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final colors = context.gloam;
    final fg = danger ? colors.danger : colors.textPrimary;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            SizedBox(
              width: 36,
              child: Icon(icon, size: 20, color: fg),
            ),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: fg,
                    ),
                  ),
                  if (sublabel != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      sublabel!,
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        color: colors.textTertiary,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
            if (!danger)
              Icon(Icons.chevron_right, size: 18, color: colors.textTertiary),
          ],
        ),
      ),
    );
  }
}
