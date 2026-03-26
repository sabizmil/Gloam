import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../app/theme/color_tokens.dart';
import '../../../app/theme/spacing.dart';
import 'sections/account_section.dart';
import 'sections/appearance_section.dart';
import 'sections/encryption_section.dart';
import 'sections/server_section.dart';
import 'sections/about_section.dart';
import 'sections/notification_section.dart';

enum _SettingsSection {
  account('account', Icons.person_outline),
  appearance('appearance', Icons.palette_outlined),
  notifications('notifications', Icons.notifications_outlined),
  encryption('security & keys', Icons.shield_outlined),
  server('server', Icons.dns_outlined),
  about('about gloam', Icons.info_outline);

  const _SettingsSection(this.label, this.icon);
  final String label;
  final IconData icon;
}

/// Full-screen settings modal overlay.
class SettingsModal extends ConsumerStatefulWidget {
  const SettingsModal({super.key});

  @override
  ConsumerState<SettingsModal> createState() => _SettingsModalState();
}

class _SettingsModalState extends ConsumerState<SettingsModal> {
  _SettingsSection _selected = _SettingsSection.account;

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.sizeOf(context).width > 700;

    return Scaffold(
      backgroundColor: GloamColors.bg,
      body: SafeArea(
        child: Column(
          children: [
            // Top bar
            Container(
              height: 56,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  Text(
                    'settings',
                    style: GoogleFonts.spectral(
                      fontSize: 22,
                      fontWeight: FontWeight.w300,
                      fontStyle: FontStyle.italic,
                      color: GloamColors.accent,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close,
                        size: 20, color: GloamColors.textTertiary),
                  ),
                ],
              ),
            ),
            const Divider(color: GloamColors.border, height: 1),

            // Body
            Expanded(
              child: isWide
                  ? Row(
                      children: [
                        // Sidebar nav
                        SizedBox(
                          width: 240,
                          child: _buildNav(),
                        ),
                        const VerticalDivider(
                            color: GloamColors.border, width: 1),
                        // Content
                        Expanded(child: _buildContent()),
                      ],
                    )
                  : Column(
                      children: [
                        // Horizontal nav on narrow screens
                        SizedBox(
                          height: 48,
                          child: ListView(
                            scrollDirection: Axis.horizontal,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 8),
                            children: _SettingsSection.values.map((s) {
                              final active = s == _selected;
                              return Padding(
                                padding: const EdgeInsets.only(right: 6),
                                child: GestureDetector(
                                  onTap: () =>
                                      setState(() => _selected = s),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 12, vertical: 6),
                                    decoration: BoxDecoration(
                                      color: active
                                          ? GloamColors.accentDim
                                          : null,
                                      borderRadius:
                                          BorderRadius.circular(16),
                                      border: Border.all(
                                        color: active
                                            ? GloamColors.accent
                                            : GloamColors.border,
                                      ),
                                    ),
                                    child: Text(
                                      s.label,
                                      style: GoogleFonts.jetBrainsMono(
                                        fontSize: 11,
                                        color: active
                                            ? GloamColors.accent
                                            : GloamColors.textSecondary,
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            }).toList(),
                          ),
                        ),
                        const Divider(
                            color: GloamColors.border, height: 1),
                        Expanded(child: _buildContent()),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNav() {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        children: _SettingsSection.values.map((s) {
          final active = s == _selected;
          return Padding(
            padding: const EdgeInsets.only(bottom: 2),
            child: Material(
              color: active ? GloamColors.bgElevated : Colors.transparent,
              borderRadius: BorderRadius.circular(GloamSpacing.radiusSm),
              child: InkWell(
                onTap: () => setState(() => _selected = s),
                borderRadius:
                    BorderRadius.circular(GloamSpacing.radiusSm),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 8),
                  child: Row(
                    children: [
                      Icon(s.icon,
                          size: 16,
                          color: active
                              ? GloamColors.accent
                              : GloamColors.textTertiary),
                      const SizedBox(width: 10),
                      Text(
                        s.label,
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          fontWeight:
                              active ? FontWeight.w500 : FontWeight.w400,
                          color: active
                              ? GloamColors.textPrimary
                              : GloamColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildContent() {
    return switch (_selected) {
      _SettingsSection.account => const AccountSection(),
      _SettingsSection.appearance => const AppearanceSection(),
      _SettingsSection.notifications => const NotificationSection(),
      _SettingsSection.encryption => const EncryptionSection(),
      _SettingsSection.server => const ServerSection(),
      _SettingsSection.about => const AboutSection(),
    };
  }
}

class _PlaceholderSection extends StatelessWidget {
  const _PlaceholderSection(this.name);
  final String name;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        '// $name — coming soon',
        style: GoogleFonts.jetBrainsMono(
          fontSize: 11,
          color: GloamColors.textTertiary,
          letterSpacing: 1,
        ),
      ),
    );
  }
}

/// Shows the settings modal as a full-screen overlay.
void showSettingsModal(BuildContext context) {
  Navigator.of(context).push(
    PageRouteBuilder(
      pageBuilder: (_, __, ___) => const SettingsModal(),
      transitionsBuilder: (_, animation, __, child) =>
          FadeTransition(opacity: animation, child: child),
      transitionDuration: const Duration(milliseconds: 200),
    ),
  );
}
