import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:matrix/matrix.dart';
import 'package:path_provider/path_provider.dart';

import '../../../../app/theme/gloam_theme_ext.dart';
import '../../../../services/matrix_service.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../widgets/settings_tile.dart';

Future<void> _confirmClearData(BuildContext context, WidgetRef ref) async {
  final colors = context.gloam;
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: colors.bgSurface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: colors.border),
      ),
      title: Text(
        'Clear all local data?',
        style: GoogleFonts.inter(fontSize: 14, color: colors.textPrimary),
      ),
      content: Text(
        'This will delete all cached messages, room data, and encryption keys from this device. '
        'You will be signed out and can sign into a new server.',
        style: GoogleFonts.inter(fontSize: 13, color: colors.textSecondary, height: 1.5),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: Text('Cancel', style: TextStyle(color: colors.textTertiary)),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: Text('Clear Data & Log Out', style: TextStyle(color: colors.danger)),
        ),
      ],
    ),
  );

  if (confirmed != true || !context.mounted) return;

  // Delete the local database file
  try {
    final supportDir = await getApplicationSupportDirectory();
    final dbFile = File('${supportDir.path}/gloam_matrix.db');
    if (await dbFile.exists()) await dbFile.delete();
  } catch (_) {}

  // Logout via auth provider (resets state)
  try {
    await ref.read(authProvider.notifier).logout();
  } catch (_) {}

  if (context.mounted) {
    Navigator.of(context, rootNavigator: true).pop(); // close settings
    GoRouter.of(context).go('/sign-in');
  }
}

class ServerSection extends ConsumerWidget {
  const ServerSection({super.key});

  /// Extract the homeserver domain from a room ID (e.g., "!abc:server.com" → "server.com").
  static String _serverFromId(String roomId) {
    final idx = roomId.indexOf(':');
    return idx >= 0 ? roomId.substring(idx + 1) : roomId;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final client = ref.watch(matrixServiceProvider).client;
    final homeserver = client?.homeserver?.toString() ?? 'not connected';

    // Build map of server → rooms
    final serverRooms = <String, List<Room>>{};
    if (client != null) {
      for (final room in client.rooms) {
        if (room.membership != Membership.join &&
            room.membership != Membership.invite) continue;
        final server = _serverFromId(room.id);
        serverRooms.putIfAbsent(server, () => []).add(room);
      }
    }

    // Sort: own homeserver first, then alphabetical
    final ownServer = client?.homeserver?.host ?? '';
    final servers = serverRooms.keys.toList()
      ..sort((a, b) {
        if (a == ownServer) return -1;
        if (b == ownServer) return 1;
        return a.compareTo(b);
      });

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
        SettingsTile(
          icon: Icons.info_outline,
          label: 'user ID',
          value: client?.userID ?? 'unknown',
        ),

        // Show clear data option when disconnected / server unreachable
        if (client == null || !client.isLogged()) ...[
          const SettingsSectionHeader('recovery'),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: Text(
              'Your homeserver appears to be unreachable. If the server no longer exists, '
              'you can clear local data and sign into a different server.',
              style: GoogleFonts.inter(
                fontSize: 12,
                color: context.gloam.textTertiary,
                height: 1.5,
              ),
            ),
          ),
          SettingsTile(
            icon: Icons.delete_outline,
            label: 'clear local data and log out',
            danger: true,
            onTap: () => _confirmClearData(context, ref),
          ),
        ],

        const SettingsSectionHeader('federated servers'),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
          child: Text(
            'Servers you have rooms on. Leave all rooms from a server to remove it.',
            style: GoogleFonts.inter(
              fontSize: 12,
              color: context.gloam.textTertiary,
            ),
          ),
        ),

        for (final server in servers)
          _ServerRow(
            server: server,
            rooms: serverRooms[server]!,
            isOwnServer: server == ownServer,
            client: client!,
          ),
      ],
    );
  }
}

class _ServerRow extends StatefulWidget {
  const _ServerRow({
    required this.server,
    required this.rooms,
    required this.isOwnServer,
    required this.client,
  });

  final String server;
  final List<Room> rooms;
  final bool isOwnServer;
  final Client client;

  @override
  State<_ServerRow> createState() => _ServerRowState();
}

class _ServerRowState extends State<_ServerRow> {
  bool _leaving = false;

  Future<void> _leaveAll() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final colors = ctx.gloam;
        return AlertDialog(
          backgroundColor: colors.bgSurface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: colors.border),
          ),
          title: Text(
            'Leave all rooms on ${widget.server}?',
            style: GoogleFonts.inter(fontSize: 14, color: colors.textPrimary),
          ),
          content: Text(
            'This will leave ${widget.rooms.length} room${widget.rooms.length == 1 ? '' : 's'}. '
            'If the server is offline, rooms will be removed locally.',
            style: GoogleFonts.inter(fontSize: 13, color: colors.textSecondary),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text('Cancel', style: TextStyle(color: colors.textTertiary)),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text('Leave All', style: TextStyle(color: colors.danger)),
            ),
          ],
        );
      },
    );

    if (confirmed != true || !mounted) return;

    setState(() => _leaving = true);

    for (final room in widget.rooms) {
      try {
        await room.leave();
      } catch (_) {
        // SDK handles dead-server fallback (local cleanup)
      }
    }

    if (mounted) setState(() => _leaving = false);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.gloam;
    final roomCount = widget.rooms.length;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: colors.bgElevated,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: colors.borderSubtle),
        ),
        child: Row(
          children: [
            Icon(
              widget.isOwnServer ? Icons.home_outlined : Icons.dns_outlined,
              size: 16,
              color: widget.isOwnServer ? colors.accent : colors.textTertiary,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.server,
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 12,
                      color: colors.textPrimary,
                      fontWeight: widget.isOwnServer ? FontWeight.w600 : FontWeight.w400,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '$roomCount room${roomCount == 1 ? '' : 's'}${widget.isOwnServer ? ' · your server' : ''}',
                    style: GoogleFonts.inter(fontSize: 11, color: colors.textTertiary),
                  ),
                ],
              ),
            ),
            if (!widget.isOwnServer)
              _leaving
                  ? SizedBox(
                      width: 16, height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2, color: colors.textTertiary,
                      ),
                    )
                  : MouseRegion(
                      cursor: SystemMouseCursors.click,
                      child: GestureDetector(
                        onTap: _leaveAll,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: colors.border),
                          ),
                          child: Text(
                            'leave all',
                            style: GoogleFonts.inter(
                              fontSize: 11, color: colors.danger,
                            ),
                          ),
                        ),
                      ),
                    ),
          ],
        ),
      ),
    );
  }
}
