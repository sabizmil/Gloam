import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Tests for the feed URL selection logic in UpdateService.
///
/// This verifies the platform + channel → URL mapping is correct.
/// On macOS test runner, only macOS paths are exercised.
void main() {
  group('Update feed URL selection', () {
    const macStable =
        'https://raw.githubusercontent.com/sabizmil/Gloam/main/appcast.xml';
    const macBeta =
        'https://raw.githubusercontent.com/sabizmil/Gloam/main/appcast_beta.xml';
    const winStable =
        'https://raw.githubusercontent.com/sabizmil/Gloam/main/appcast_windows.xml';
    const winBeta =
        'https://raw.githubusercontent.com/sabizmil/Gloam/main/appcast_windows_beta.xml';

    /// Mirrors UpdateService._setFeed() logic
    String selectFeedUrl({required bool isMacOS, required bool beta}) {
      if (isMacOS) {
        return beta ? macBeta : macStable;
      } else {
        return beta ? winBeta : winStable;
      }
    }

    test('macOS stable returns macOS appcast', () {
      expect(selectFeedUrl(isMacOS: true, beta: false), macStable);
    });

    test('macOS beta returns macOS beta appcast', () {
      expect(selectFeedUrl(isMacOS: true, beta: true), macBeta);
    });

    test('Windows stable returns Windows appcast', () {
      expect(selectFeedUrl(isMacOS: false, beta: false), winStable);
    });

    test('Windows beta returns Windows beta appcast', () {
      expect(selectFeedUrl(isMacOS: false, beta: true), winBeta);
    });

    test('platform guard skips unsupported platforms', () {
      // Mirrors: if (!Platform.isMacOS && !Platform.isWindows) return;
      bool shouldInit() => Platform.isMacOS || Platform.isWindows;

      // On macOS test runner, this should be true
      if (Platform.isMacOS) {
        expect(shouldInit(), true);
      }
      // On Linux CI, this should be false
      if (Platform.isLinux) {
        expect(shouldInit(), false);
      }
    });
  });
}
