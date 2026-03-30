import 'dart:ffi';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app/app.dart';
import 'app/theme/theme_preferences.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Pre-load libolm from the app bundle before the Matrix SDK tries.
  //
  // The olm Dart package calls DynamicLibrary.open('libolm.3.dylib') with a
  // bare filename. The dynamic linker only searches system paths — NOT the
  // app bundle's Contents/MacOS directory. So on machines without Homebrew
  // (i.e., every release build recipient), olm.init() fails silently and
  // encryption is disabled.
  //
  // By loading the library with its full path here, it's registered in the
  // process's library cache. When the olm package later calls
  // DynamicLibrary.open('libolm.3.dylib'), the linker finds it already
  // loaded and returns the cached handle.
  if (Platform.isMacOS) {
    try {
      final executable = Platform.resolvedExecutable;
      final bundleDir = File(executable).parent.path;
      DynamicLibrary.open('$bundleDir/libolm.3.dylib');
    } catch (e) {
      debugPrint('[main] Failed to pre-load libolm: $e');
    }
  }

  if (Platform.isWindows) {
    try {
      final executable = Platform.resolvedExecutable;
      final bundleDir = File(executable).parent.path;
      // Try both common names on Windows
      try {
        DynamicLibrary.open('$bundleDir/olm.dll');
      } catch (_) {
        DynamicLibrary.open('$bundleDir/libolm.dll');
      }
    } catch (e) {
      debugPrint('[main] Failed to pre-load libolm: $e');
    }
  }

  // Initialize SharedPreferences before runApp so theme
  // preferences are available synchronously.
  final sharedPrefs = await SharedPreferences.getInstance();

  runApp(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(sharedPrefs),
      ],
      child: const GloamApp(),
    ),
  );
}
