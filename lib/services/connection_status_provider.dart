import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:matrix/matrix.dart';

import 'matrix_service.dart';

enum ConnectionStatus {
  online,
  connecting,
  reconnecting,
  disconnected,
}

class ConnectionStatusNotifier extends StateNotifier<ConnectionStatus> {
  final Client _client;
  StreamSubscription? _sub;
  DateTime? _firstErrorAt;
  bool _overridden = false;

  static const _disconnectedThreshold = Duration(seconds: 15);

  ConnectionStatusNotifier(this._client)
      : super(ConnectionStatus.connecting) {
    _sub = _client.onSyncStatus.stream.listen(_onSyncStatus);
  }

  void _onSyncStatus(SyncStatusUpdate update) {
    if (_overridden) return;

    switch (update.status) {
      case SyncStatus.finished:
        _firstErrorAt = null;
        state = ConnectionStatus.online;
      case SyncStatus.error:
        _firstErrorAt ??= DateTime.now();
        final elapsed = DateTime.now().difference(_firstErrorAt!);
        state = elapsed > _disconnectedThreshold
            ? ConnectionStatus.disconnected
            : ConnectionStatus.reconnecting;
      case SyncStatus.waitingForResponse:
      case SyncStatus.processing:
      case SyncStatus.cleaningUp:
        break;
    }
  }

  /// Force a connection state for testing. Debug builds only.
  void debugOverride(ConnectionStatus status) {
    _overridden = true;
    state = status;
  }

  /// Clear the override and resume listening to real sync status.
  void debugClearOverride() {
    _overridden = false;
    _firstErrorAt = null;
    state = ConnectionStatus.online;
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}

final connectionStatusProvider =
    StateNotifierProvider<ConnectionStatusNotifier, ConnectionStatus>((ref) {
  final client = ref.watch(matrixServiceProvider).client;
  if (client == null) {
    return ConnectionStatusNotifier(Client('fallback'));
  }
  return ConnectionStatusNotifier(client);
});
