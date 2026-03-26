import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../services/matrix_service.dart';
import '../widgets/settings_tile.dart';

class ServerSection extends ConsumerWidget {
  const ServerSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final client = ref.watch(matrixServiceProvider).client;
    final homeserver = client?.homeserver?.toString() ?? 'not connected';

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const SettingsSectionHeader('connection'),
        SettingsTile(
          icon: Icons.dns_outlined,
          label: 'homeserver',
          value: homeserver,
        ),
        SettingsTile(
          icon: Icons.signal_wifi_4_bar,
          label: 'status',
          value: client?.isLogged() == true ? 'connected' : 'disconnected',
        ),

        const SettingsSectionHeader('server info'),
        SettingsTile(
          icon: Icons.info_outline,
          label: 'user ID',
          value: client?.userID ?? 'unknown',
        ),
      ],
    );
  }
}
