import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:matrix/matrix.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'gloam_native_implementations.dart';

/// Connection state machine for the Matrix client.
enum GloamConnectionState {
  disconnected,
  connecting,
  connected,
  syncing,
  synced,
  error,
}

/// Central service wrapping the matrix_dart_sdk [Client].
///
/// The SDK handles session persistence through its own database.
/// On init(), it restores a previous session automatically if one exists.
class MatrixService {
  Client? _client;
  GloamConnectionState _connectionState = GloamConnectionState.disconnected;

  Client? get client => _client;
  GloamConnectionState get connectionState => _connectionState;
  bool get isLoggedIn => _client?.isLogged() ?? false;

  /// Initialize the SDK. The SDK restores any previous session from its database.
  /// If the client is already logged in (e.g. after loginWithPassword), returns true immediately.
  Future<bool> initialize() async {
    // Already logged in — don't re-init
    if (_client != null && _client!.isLogged()) {
      _connectionState = GloamConnectionState.connected;
      return true;
    }

    _connectionState = GloamConnectionState.connecting;

    await _ensureClient();

    try {
      await _client!.init(waitForFirstSync: false);

      if (_client!.isLogged()) {
        _connectionState = GloamConnectionState.connected;
        return true;
      }
    } catch (e) {
      Logs().e('Session restore failed', e);
      // Reset client so loginWithPassword gets a fresh one
      _client = null;
    }

    _connectionState = GloamConnectionState.disconnected;
    return false;
  }

  /// Ensures the client exists (with a database) but does NOT call init().
  Future<void> _ensureClient() async {
    if (_client != null) return;

    if (Platform.isLinux || Platform.isWindows || Platform.isMacOS) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    }

    final supportDir = await getApplicationSupportDirectory();
    final dbPath = '${supportDir.path}/gloam_matrix.db';

    _client = Client(
      'gloam',
      databaseBuilder: (_) async {
        final db = MatrixSdkDatabase(
          'gloam',
          database: await databaseFactory.openDatabase(dbPath),
        );
        await db.open();
        return db;
      },
      nativeImplementations: const GloamNativeImplementations(),
      supportedLoginTypes: {
        AuthenticationTypes.password,
        AuthenticationTypes.sso,
      },
      importantStateEvents: {
        EventTypes.Encryption,
      },
    );
  }

  /// Login with username/password against a homeserver.
  Future<void> loginWithPassword({
    required String homeserver,
    required String username,
    required String password,
  }) async {
    _connectionState = GloamConnectionState.connecting;

    await _ensureClient();

    final hsUri = _normalizeHomeserver(homeserver);
    Logs().i('Login: checking homeserver $hsUri');
    await _client!.checkHomeserver(hsUri, checkWellKnown: true);
    Logs().i('Login: homeserver set to ${_client!.homeserver}');

    Logs().i('Login: attempting login for $username');
    await _client!.login(
      LoginType.mLoginPassword,
      identifier: AuthenticationUserIdentifier(user: username),
      password: password,
      initialDeviceDisplayName: 'Gloam (macOS)',
    );
    Logs().i('Login: success, userID=${_client!.userID}');

    _connectionState = GloamConnectionState.connected;
  }

  /// Register a new account.
  Future<void> register({
    required String homeserver,
    required String username,
    required String password,
  }) async {
    _connectionState = GloamConnectionState.connecting;

    await _ensureClient();

    await _client!.checkHomeserver(
      _normalizeHomeserver(homeserver),
      checkWellKnown: true,
    );

    await _client!.uiaRequestBackground(
      (auth) => _client!.register(
        username: username,
        password: password,
        auth: auth,
      ),
    );

    _connectionState = GloamConnectionState.connected;
  }

  /// Ensures the homeserver string becomes a valid Uri with scheme and host.
  Uri _normalizeHomeserver(String input) {
    var url = input.trim();
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      url = 'https://$url';
    }
    // Strip trailing slash
    if (url.endsWith('/')) url = url.substring(0, url.length - 1);
    return Uri.parse(url);
  }

  /// Logout and clear local state.
  Future<void> logout() async {
    try {
      await _client?.logout();
    } catch (_) {
      // Best-effort server logout
    }
    _connectionState = GloamConnectionState.disconnected;
  }
}

/// Global MatrixService provider — singleton for the app's lifetime.
final matrixServiceProvider = Provider<MatrixService>((ref) {
  return MatrixService();
});
