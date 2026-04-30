import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:window_manager/window_manager.dart';

import '../../../app/theme/gloam_theme_ext.dart';
import '../../../app/theme/spacing.dart';
import 'sections/account_section.dart';
import 'sections/appearance_section.dart';
import 'sections/encryption_section.dart';
import 'sections/server_section.dart';
import 'sections/about_section.dart';
import 'sections/notification_section.dart';
import '../../calls/presentation/screens/voice_settings_screen.dart';

enum SettingsSection {
  account('account', Icons.person_outline),
  appearance('appearance', Icons.palette_outlined),
  voiceAudio('voice & audio', Icons.headphones_outlined),
  notifications('notifications', Icons.notifications_outlined),
  encryption('security & keys', Icons.shield_outlined),
  server('server', Icons.dns_outlined),
  about('about gloam', Icons.info_outline);

  const SettingsSection(this.label, this.icon);
  final String label;
  final IconData icon;
}

/// Full-screen settings modal overlay.
class SettingsModal extends ConsumerStatefulWidget {
  const SettingsModal({super.key, this.initialSection});

  final SettingsSection? initialSection;

  @override
  ConsumerState<SettingsModal> createState() => _SettingsModalState();
}

class _SettingsModalState extends ConsumerState<SettingsModal> {
  late SettingsSection _selected =
      widget.initialSection ?? SettingsSection.account;

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.sizeOf(context).width > 700;

    return Scaffold(
      backgroundColor: context.gloam.bg,
      body: SafeArea(
        child: Column(
          children: [
            // Top strip — draggable, leaves room for the macOS traffic
            // lights on the left; close button on the right.
            SizedBox(
              height: GloamSpacing.topStripHeight,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: GestureDetector(
                      behavior: HitTestBehavior.translucent,
                      onPanStart: (_) => windowManager.startDragging(),
                      onDoubleTap: () async {
                        if (await windowManager.isMaximized()) {
                          await windowManager.unmaximize();
                        } else {
                          await windowManager.maximize();
                        }
                      },
                    ),
                  ),
                  Positioned(
                    top: 0,
                    bottom: 0,
                    right: 4,
                    child: IconButton(
                      onPressed: () => Navigator.pop(context),
                      iconSize: 18,
                      padding: EdgeInsets.zero,
                      visualDensity: VisualDensity.compact,
                      tooltip: 'close',
                      icon: Icon(Icons.close,
                          color: context.gloam.textTertiary),
                    ),
                  ),
                ],
              ),
            ),
            Divider(color: context.gloam.border, height: 1),

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
                        VerticalDivider(
                            color: context.gloam.border, width: 1),
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
                            children: SettingsSection.values.map((s) {
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
                                          ? context.gloam.accentDim
                                          : null,
                                      borderRadius:
                                          BorderRadius.circular(16),
                                      border: Border.all(
                                        color: active
                                            ? context.gloam.accent
                                            : context.gloam.border,
                                      ),
                                    ),
                                    child: Text(
                                      s.label,
                                      style: GoogleFonts.jetBrainsMono(
                                        fontSize: 11,
                                        color: active
                                            ? context.gloam.accent
                                            : context.gloam.textSecondary,
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            }).toList(),
                          ),
                        ),
                        Divider(
                            color: context.gloam.border, height: 1),
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
        children: SettingsSection.values.map((s) {
          final active = s == _selected;
          return Padding(
            padding: const EdgeInsets.only(bottom: 2),
            child: Material(
              color: active ? context.gloam.bgElevated : Colors.transparent,
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
                              ? context.gloam.accent
                              : context.gloam.textTertiary),
                      const SizedBox(width: 10),
                      Text(
                        s.label,
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          fontWeight:
                              active ? FontWeight.w500 : FontWeight.w400,
                          color: active
                              ? context.gloam.textPrimary
                              : context.gloam.textSecondary,
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
      SettingsSection.account => const AccountSection(),
      SettingsSection.appearance => const AppearanceSection(),
      SettingsSection.voiceAudio => const VoiceSettingsScreen(),
      SettingsSection.notifications => const NotificationSection(),
      SettingsSection.encryption => const EncryptionSection(),
      SettingsSection.server => const ServerSection(),
      SettingsSection.about => const AboutSection(),
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
          color: context.gloam.textTertiary,
          letterSpacing: 1,
        ),
      ),
    );
  }
}

/// Shows the settings modal as a full-screen overlay.
/// Pass [initialSection] to deep-link directly to a section (used by ⌘K).
void showSettingsModal(
  BuildContext context, {
  SettingsSection? initialSection,
}) {
  Navigator.of(context).push(
    PageRouteBuilder(
      pageBuilder: (_, __, ___) => SettingsModal(initialSection: initialSection),
      transitionsBuilder: (_, animation, __, child) =>
          FadeTransition(opacity: animation, child: child),
      transitionDuration: const Duration(milliseconds: 200),
    ),
  );
}
