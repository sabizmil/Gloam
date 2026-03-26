import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../app/theme/color_tokens.dart';
import '../../../app/theme/spacing.dart';
import '../../../app/router.dart';
import '../../../app/shell/adaptive_shell.dart';
import '../../../app/shell/quick_switcher.dart';
import '../../../services/matrix_service.dart';
import '../../../services/notification_service.dart';
import '../../../services/search_service.dart';
import '../../../services/verification_service.dart';
import '../../auth/presentation/providers/auth_provider.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  @override
  void initState() {
    super.initState();
    Future.microtask(
      () => ref.read(authProvider.notifier).restoreSession(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authProvider);

    return switch (authState) {
      AuthState.loading => const _LoadingScreen(),
      AuthState.unauthenticated || AuthState.error => const _UnauthenticatedRedirect(),
      AuthState.authenticated => const _AuthenticatedHome(),
    };
  }
}

class _LoadingScreen extends StatelessWidget {
  const _LoadingScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: GloamColors.bg,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: GloamColors.accentDim,
                borderRadius: BorderRadius.circular(GloamSpacing.radiusLg),
              ),
              child: Center(
                child: Text(
                  'G',
                  style: GoogleFonts.spectral(
                    fontSize: 32,
                    fontWeight: FontWeight.w300,
                    fontStyle: FontStyle.italic,
                    color: GloamColors.accentBright,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'gloam',
              style: GoogleFonts.spectral(
                fontSize: 28,
                fontWeight: FontWeight.w300,
                fontStyle: FontStyle.italic,
                color: GloamColors.accent,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '// connecting...',
              style: GoogleFonts.jetBrainsMono(
                fontSize: 11,
                color: GloamColors.textTertiary,
                letterSpacing: 1,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _UnauthenticatedRedirect extends ConsumerWidget {
  const _UnauthenticatedRedirect();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (context.mounted) {
        context.go('/sign-in');
      }
    });
    return const _LoadingScreen();
  }
}

/// Wraps AdaptiveShell with global keyboard shortcuts and verification listener.
class _AuthenticatedHome extends ConsumerStatefulWidget {
  const _AuthenticatedHome();

  @override
  ConsumerState<_AuthenticatedHome> createState() =>
      _AuthenticatedHomeState();
}

class _AuthenticatedHomeState extends ConsumerState<_AuthenticatedHome> {
  VerificationService? _verificationService;
  NotificationService? _notificationService;

  @override
  void initState() {
    super.initState();
    final client = ref.read(matrixServiceProvider).client;
    if (client != null) {
      _verificationService = VerificationService(
        client: client,
        navigatorKey: rootNavigatorKey,
      );
      _verificationService!.start();

      _notificationService = NotificationService(client);
      _notificationService!.initialize().then((_) {
        _notificationService!.start();
      });

      // Initialize search indexing
      final searchService = ref.read(searchServiceProvider);
      searchService.initialize().then((_) {
        searchService.startLiveIndexing();
      });
    }
  }

  @override
  void dispose() {
    _verificationService?.dispose();
    _notificationService?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: GloamColors.bg,
      body: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.keyK, meta: true):
              () => showQuickSwitcher(context, ref),
          const SingleActivator(LogicalKeyboardKey.keyK, control: true):
              () => showQuickSwitcher(context, ref),
        },
        child: const Focus(
          autofocus: true,
          child: AdaptiveShell(),
        ),
      ),
    );
  }
}
