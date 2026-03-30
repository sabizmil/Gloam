import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'router.dart';
import 'theme/gloam_theme.dart';
import 'theme/theme_preferences.dart';

class GloamApp extends ConsumerWidget {
  const GloamApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prefs = ref.watch(themePreferencesProvider);

    Widget app = MediaQuery(
      data: MediaQuery.of(context).copyWith(
        textScaler: TextScaler.linear(prefs.fontScale),
      ),
      child: MaterialApp.router(
        title: 'Gloam',
        debugShowCheckedModeBanner: false,
        theme: buildGloamTheme(prefs: prefs),
        themeAnimationDuration: const Duration(milliseconds: 300),
        themeAnimationCurve: Curves.easeInOut,
        routerConfig: router,
      ),
    );

    // macOS needs a PlatformMenuBar for standard keyboard shortcuts
    // to work correctly in text fields.
    if (defaultTargetPlatform == TargetPlatform.macOS) {
      app = PlatformMenuBar(
        menus: [
          PlatformMenu(
            label: 'Gloam',
            menus: [
              PlatformProvidedMenuItem(
                type: PlatformProvidedMenuItemType.about,
              ),
              PlatformProvidedMenuItem(
                type: PlatformProvidedMenuItemType.quit,
              ),
            ],
          ),
          PlatformMenu(
            label: 'Edit',
            menus: [
              PlatformMenuItem(
                label: 'Cut',
                shortcut: const SingleActivator(
                  LogicalKeyboardKey.keyX,
                  meta: true,
                ),
                onSelected: null,
              ),
              PlatformMenuItem(
                label: 'Copy',
                shortcut: const SingleActivator(
                  LogicalKeyboardKey.keyC,
                  meta: true,
                ),
                onSelected: null,
              ),
              PlatformMenuItem(
                label: 'Paste',
                shortcut: const SingleActivator(
                  LogicalKeyboardKey.keyV,
                  meta: true,
                ),
                onSelected: null,
              ),
              PlatformMenuItem(
                label: 'Select All',
                shortcut: const SingleActivator(
                  LogicalKeyboardKey.keyA,
                  meta: true,
                ),
                onSelected: null,
              ),
            ],
          ),
          PlatformMenu(
            label: 'View',
            menus: [
              PlatformProvidedMenuItem(
                type: PlatformProvidedMenuItemType.toggleFullScreen,
              ),
            ],
          ),
          PlatformMenu(
            label: 'Window',
            menus: [
              PlatformProvidedMenuItem(
                type: PlatformProvidedMenuItemType.minimizeWindow,
              ),
            ],
          ),
        ],
        child: app,
      );
    }

    return app;
  }
}
