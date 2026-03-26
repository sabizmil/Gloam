import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../services/matrix_service.dart';

/// Auth state — tracks whether the user is authenticated.
enum AuthState {
  loading,
  unauthenticated,
  authenticated,
  error,
}

class AuthNotifier extends StateNotifier<AuthState> {
  final MatrixService _matrixService;

  AuthNotifier(this._matrixService) : super(AuthState.loading);

  /// Attempt to restore a previous session on app startup.
  Future<void> restoreSession() async {
    state = AuthState.loading;
    try {
      final restored = await _matrixService.initialize();
      state = restored ? AuthState.authenticated : AuthState.unauthenticated;
    } catch (_) {
      state = AuthState.unauthenticated;
    }
  }

  /// Login with username/password.
  Future<void> login({
    required String homeserver,
    required String username,
    required String password,
  }) async {
    state = AuthState.loading;
    try {
      await _matrixService.loginWithPassword(
        homeserver: homeserver,
        username: username,
        password: password,
      );
      state = AuthState.authenticated;
    } catch (_) {
      state = AuthState.error;
      rethrow;
    }
  }

  /// Logout.
  Future<void> logout() async {
    await _matrixService.logout();
    state = AuthState.unauthenticated;
  }
}

final authProvider = StateNotifierProvider<AuthNotifier, AuthState>((ref) {
  final matrixService = ref.watch(matrixServiceProvider);
  return AuthNotifier(matrixService);
});
