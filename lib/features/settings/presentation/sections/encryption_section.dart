import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../app/theme/color_tokens.dart';
import '../../../../services/matrix_service.dart';
import '../recovery_key_dialog.dart';
import '../widgets/settings_tile.dart';

class EncryptionSection extends ConsumerWidget {
  const EncryptionSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final client = ref.watch(matrixServiceProvider).client;
    final hasEncryption = client?.encryption != null;
    final deviceId = client?.deviceID ?? 'unknown';
    final devices = client?.userDeviceKeys[client.userID]?.deviceKeys.values
            .toList() ??
        [];

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const SettingsSectionHeader('encryption status'),
        SettingsTile(
          icon: hasEncryption ? Icons.lock : Icons.lock_open,
          label: 'end-to-end encryption',
          value: hasEncryption ? 'active' : 'unavailable',
        ),
        SettingsTile(
          icon: Icons.vpn_key_outlined,
          label: 'key backup',
          value: client?.encryption?.keyManager.enabled == true
              ? 'enabled'
              : 'not set up',
        ),

        const SettingsSectionHeader('recovery'),
        SettingsTile(
          icon: Icons.key,
          label: 'enter recovery key',
          onTap: () => showRecoveryKeyDialog(context),
        ),
        SettingsTile(
          icon: Icons.security,
          label: 'verify this device',
          onTap: () {},
        ),

        SettingsSectionHeader('devices — ${devices.length}'),
        ...devices.map((device) {
          final isCurrent = device.deviceId == deviceId;
          return SettingsTile(
            icon: isCurrent ? Icons.computer : Icons.smartphone,
            label: device.deviceDisplayName ?? device.deviceId ?? 'unknown',
            value: isCurrent ? 'this device' : null,
            trailing: device.verified
                ? const Icon(Icons.verified, size: 16, color: GloamColors.accent)
                : const Icon(Icons.warning_amber, size: 16, color: GloamColors.warning),
          );
        }),

        const SettingsSectionHeader('advanced'),
        SettingsTile(
          icon: Icons.delete_outline,
          label: 'reset encryption',
          danger: true,
          onTap: () {},
        ),
      ],
    );
  }
}
