import 'dart:io';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../app/theme/gloam_theme_ext.dart';
import '../../../../services/update_service.dart';
import '../widgets/settings_tile.dart';

class AboutSection extends StatelessWidget {
  const AboutSection({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        // Gloam branding
        Center(
          child: Column(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: context.gloam.accentDim,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Center(
                  child: Text(
                    'G',
                    style: GoogleFonts.spectral(
                      fontSize: 28,
                      fontWeight: FontWeight.w300,
                      fontStyle: FontStyle.italic,
                      color: context.gloam.accentBright,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'gloam',
                style: GoogleFonts.spectral(
                  fontSize: 24,
                  fontWeight: FontWeight.w300,
                  fontStyle: FontStyle.italic,
                  color: context.gloam.accent,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'tune in to the conversation',
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 10,
                  color: context.gloam.textTertiary,
                  letterSpacing: 1,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),

        const SettingsSectionHeader('app info'),
        const SettingsTile(icon: Icons.tag, label: 'version', value: '0.2.7'),
        if (Platform.isMacOS || Platform.isWindows)
          SettingsTile(
            icon: Icons.system_update,
            label: 'check for updates',
            onTap: () => UpdateService.checkNow(),
          ),
        const SettingsTile(icon: Icons.flutter_dash, label: 'framework', value: 'Flutter'),
        const SettingsTile(icon: Icons.code, label: 'matrix SDK', value: 'matrix_dart_sdk'),

        const SettingsSectionHeader('links'),
        SettingsTile(icon: Icons.language, label: 'gloam.chat', onTap: () {}),
        SettingsTile(icon: Icons.code, label: 'source code', onTap: () {}),
        SettingsTile(icon: Icons.description_outlined, label: 'licenses', onTap: () {}),
      ],
    );
  }
}
