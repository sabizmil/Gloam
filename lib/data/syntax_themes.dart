import 'package:flutter/painting.dart';
import 'package:flutter_highlight/themes/atom-one-dark.dart';
import 'package:flutter_highlight/themes/dracula.dart';
import 'package:flutter_highlight/themes/github.dart';
import 'package:flutter_highlight/themes/gruvbox-dark.dart';
import 'package:flutter_highlight/themes/monokai.dart';
import 'package:flutter_highlight/themes/nord.dart';
import 'package:flutter_highlight/themes/solarized-dark.dart';
import 'package:flutter_highlight/themes/solarized-light.dart';
import 'package:flutter_highlight/themes/vs2015.dart';

/// A curated syntax highlighting theme.
class SyntaxThemeEntry {
  final String id;
  final String displayName;
  final bool isDark;
  final Map<String, TextStyle> theme;

  const SyntaxThemeEntry({
    required this.id,
    required this.displayName,
    required this.isDark,
    required this.theme,
  });
}

/// Curated syntax themes — a selection of popular dark and light themes.
final syntaxThemes = <SyntaxThemeEntry>[
  SyntaxThemeEntry(id: 'atom-one-dark', displayName: 'One Dark', isDark: true, theme: atomOneDarkTheme),
  SyntaxThemeEntry(id: 'dracula', displayName: 'Dracula', isDark: true, theme: draculaTheme),
  SyntaxThemeEntry(id: 'monokai', displayName: 'Monokai', isDark: true, theme: monokaiTheme),
  SyntaxThemeEntry(id: 'gruvbox-dark', displayName: 'Gruvbox Dark', isDark: true, theme: gruvboxDarkTheme),
  SyntaxThemeEntry(id: 'vs2015', displayName: 'VS Dark', isDark: true, theme: vs2015Theme),
  SyntaxThemeEntry(id: 'nord', displayName: 'Nord', isDark: true, theme: nordTheme),
  SyntaxThemeEntry(id: 'solarized-dark', displayName: 'Solarized Dark', isDark: true, theme: solarizedDarkTheme),
  SyntaxThemeEntry(id: 'github', displayName: 'GitHub Light', isDark: false, theme: githubTheme),
  SyntaxThemeEntry(id: 'solarized-light', displayName: 'Solarized Light', isDark: false, theme: solarizedLightTheme),
];

/// Default syntax theme ID.
const defaultSyntaxTheme = 'atom-one-dark';

/// Look up a theme by ID. Falls back to the default.
Map<String, TextStyle> getSyntaxTheme(String id) {
  for (final t in syntaxThemes) {
    if (t.id == id) return t.theme;
  }
  return atomOneDarkTheme;
}
