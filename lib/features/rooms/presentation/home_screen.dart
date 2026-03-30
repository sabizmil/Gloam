import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../app/theme/gloam_theme_ext.dart';
import '../../../app/theme/spacing.dart';
import '../../../app/router.dart';
import '../../../app/shell/adaptive_shell.dart';
import '../../../app/shell/quick_switcher.dart';
import '../../../app/shell/right_panel.dart';
import '../../../app/shell/shortcut_help_overlay.dart';
import '../../../app/shortcuts.dart';
import '../../../features/settings/presentation/settings_modal.dart';
import '../../../services/debug_server.dart';
import '../../../services/matrix_service.dart';
import '../../../services/update_service.dart';
import '../../../services/notification_service.dart';
import '../../../services/search_service.dart';
import '../../../services/verification_service.dart';
import '../../../services/voice_service.dart';
import '../../auth/presentation/providers/auth_provider.dart';
import '../../calls/presentation/widgets/persistent_voice_bar.dart';
import '../../chat/presentation/providers/timeline_provider.dart';
import '../../explore/presentation/explore_modal.dart';
import '../../rooms/presentation/widgets/create_room_dialog.dart';

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
      backgroundColor: context.gloam.bg,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: context.gloam.accentDim,
                borderRadius: BorderRadius.circular(GloamSpacing.radiusLg),
              ),
              child: Center(
                child: Text(
                  'G',
                  style: GoogleFonts.spectral(
                    fontSize: 32,
                    fontWeight: FontWeight.w300,
                    fontStyle: FontStyle.italic,
                    color: context.gloam.accentBright,
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
                color: context.gloam.accent,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '// connecting...',
              style: GoogleFonts.jetBrainsMono(
                fontSize: 11,
                color: context.gloam.textTertiary,
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
  DebugServer? _debugServer;

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

      // Debug server (localhost:9999, debug mode only)
      _debugServer = DebugServer(client: client);
      _debugServer!.start();

      // Auto-update check (release mode only, desktop)
      UpdateService.init();
    }
  }

  @override
  void dispose() {
    _verificationService?.dispose();
    _notificationService?.dispose();
    _debugServer?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final voiceState = ref.watch(voiceServiceProvider);

    return Scaffold(
      backgroundColor: context.gloam.bg,
      body: Shortcuts(
        shortcuts: gloamShortcuts,
        child: Actions(
          actions: {
            QuickSwitcherIntent: CallbackAction<QuickSwitcherIntent>(
              onInvoke: (_) => showQuickSwitcher(context, ref),
            ),
            NewRoomIntent: CallbackAction<NewRoomIntent>(
              onInvoke: (_) async {
                final roomId = await showCreateRoomDialog(context);
                if (roomId != null) {
                  ref.read(selectedRoomProvider.notifier).state = roomId;
                }
                return null;
              },
            ),
            SearchIntent: CallbackAction<SearchIntent>(
              onInvoke: (_) {
                ref.read(rightPanelProvider.notifier).state =
                    const RightPanelState(view: RightPanelView.search);
                return null;
              },
            ),
            GlobalSearchIntent: CallbackAction<GlobalSearchIntent>(
              onInvoke: (_) {
                ref.read(rightPanelProvider.notifier).state =
                    const RightPanelState(view: RightPanelView.search);
                return null;
              },
            ),
            ClosePanelIntent: CallbackAction<ClosePanelIntent>(
              onInvoke: (_) {
                ref.read(rightPanelProvider.notifier).state =
                    RightPanelState.closed;
                return null;
              },
            ),
            ShortcutHelpIntent: CallbackAction<ShortcutHelpIntent>(
              onInvoke: (_) => showShortcutHelp(context),
            ),
            PreferencesIntent: CallbackAction<PreferencesIntent>(
              onInvoke: (_) {
                showSettingsModal(context);
                return null;
              },
            ),
            ToggleMuteIntent: CallbackAction<ToggleMuteIntent>(
              onInvoke: (_) {
                ref.read(voiceServiceProvider.notifier).toggleMute();
                return null;
              },
            ),
            ToggleDeafenIntent: CallbackAction<ToggleDeafenIntent>(
              onInvoke: (_) {
                ref.read(voiceServiceProvider.notifier).toggleDeafen();
                return null;
              },
            ),
            DisconnectVoiceIntent: CallbackAction<DisconnectVoiceIntent>(
              onInvoke: (_) {
                ref.read(voiceServiceProvider.notifier).disconnect();
                return null;
              },
            ),
            MarkReadIntent: CallbackAction<MarkReadIntent>(
              onInvoke: (_) {
                final roomId = ref.read(selectedRoomProvider);
                if (roomId != null) {
                  final client = ref.read(matrixServiceProvider).client;
                  final room = client?.getRoomById(roomId);
                  final lastEvent = room?.lastEvent;
                  if (room != null && lastEvent != null) {
                    room.setReadMarker(lastEvent.eventId);
                  }
                }
                return null;
              },
            ),
            ExploreIntent: CallbackAction<ExploreIntent>(
              onInvoke: (_) {
                showExploreModal(context);
                return null;
              },
            ),
          },
          child: Focus(
            autofocus: true,
            child: Column(
              children: [
                const Expanded(child: AdaptiveShell()),
                if (voiceState is VoiceStateConnected)
                  PersistentVoiceBar(state: voiceState),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
