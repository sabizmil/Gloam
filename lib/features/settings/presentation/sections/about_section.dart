import 'dart:io';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../app/theme/gloam_theme_ext.dart';
import '../../../../services/update_service.dart';
import '../widgets/settings_tile.dart';

class AboutSection extends StatefulWidget {
  const AboutSection({super.key});

  @override
  State<AboutSection> createState() => _AboutSectionState();
}

class _AboutSectionState extends State<AboutSection> {
  String _version = '...';
  bool _isBeta = false;

  @override
  void initState() {
    super.initState();
    _loadVersion();
    _loadChannel();
  }

  Future<void> _loadVersion() async {
    final info = await PackageInfo.fromPlatform();
    if (mounted) {
      final v = info.version.split('+').first;
      setState(() => _version = v);
    }
  }

  Future<void> _loadChannel() async {
    final beta = await UpdateService.isBetaChannel();
    if (mounted) setState(() => _isBeta = beta);
  }

  Future<void> _toggleChannel(bool beta) async {
    setState(() => _isBeta = beta);
    await UpdateService.setBetaChannel(beta);
  }

  void _openUrl(String url) {
    launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }

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
        SettingsTile(icon: Icons.tag, label: 'version', value: _version),
        if (Platform.isMacOS || Platform.isWindows) ...[
          SettingsTile(
            icon: Icons.science_outlined,
            label: 'update channel',
            value: _isBeta ? 'beta' : 'stable',
            onTap: () => _toggleChannel(!_isBeta),
          ),
          SettingsTile(
            icon: Icons.system_update,
            label: 'check for updates',
            onTap: () => UpdateService.checkNow(),
          ),
        ],

        const SettingsSectionHeader('links'),
        SettingsTile(
          icon: Icons.code,
          label: 'source code',
          onTap: () => _openUrl('https://github.com/sabizmil/Gloam'),
        ),
        SettingsTile(
          icon: Icons.new_releases_outlined,
          label: 'changelog',
          onTap: () => _openUrl('https://github.com/sabizmil/Gloam/releases'),
        ),
      ],
    );
  }
}
