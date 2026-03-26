import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'router.dart';
import 'theme/gloam_theme.dart';

class GloamApp extends ConsumerWidget {
  const GloamApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    Widget app = MaterialApp.router(
      title: 'Gloam',
      debugShowCheckedModeBanner: false,
      theme: buildGloamTheme(),
      routerConfig: router,
    );

    // macOS needs a PlatformMenuBar for standard keyboard shortcuts
    // to work correctly in text fields.
    if (Platform.isMacOS) {
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
          // The Edit menu with standard shortcuts is needed for
          // text fields to receive Cmd+C/V/X/A correctly on macOS.
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
