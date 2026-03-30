import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'theme_variants.dart';

/// Persisted user preferences for theming.
class ThemePreferences {
  final ThemeVariant variant;
  final AccentColor accentColor;
  final DensityMode density;
  final double fontScale;

  const ThemePreferences({
    this.variant = ThemeVariant.gloamDark,
    this.accentColor = AccentColor.green,
    this.density = DensityMode.comfortable,
    this.fontScale = 1.0,
  });

  ThemePreferences copyWith({
    ThemeVariant? variant,
    AccentColor? accentColor,
    DensityMode? density,
    double? fontScale,
  }) {
    return ThemePreferences(
      variant: variant ?? this.variant,
      accentColor: accentColor ?? this.accentColor,
      density: density ?? this.density,
      fontScale: fontScale ?? this.fontScale,
    );
  }
}

/// Manages theme preferences with SharedPreferences persistence.
class ThemePreferencesNotifier extends StateNotifier<ThemePreferences> {
  final SharedPreferences _prefs;

  ThemePreferencesNotifier(this._prefs) : super(const ThemePreferences()) {
    _load();
  }

  void _load() {
    final variantIndex = _prefs.getInt('theme_variant') ?? 0;
    final accentIndex = _prefs.getInt('theme_accent') ?? 0;
    final densityIndex = _prefs.getInt('theme_density') ?? 1; // comfortable
    final fontScale = _prefs.getDouble('theme_font_scale') ?? 1.0;

    state = ThemePreferences(
      variant: ThemeVariant.values[variantIndex.clamp(0, ThemeVariant.values.length - 1)],
      accentColor: AccentColor.values[accentIndex.clamp(0, AccentColor.values.length - 1)],
      density: DensityMode.values[densityIndex.clamp(0, DensityMode.values.length - 1)],
      fontScale: fontScale.clamp(0.85, 1.25),
    );
  }

  void setVariant(ThemeVariant variant) {
    state = state.copyWith(variant: variant);
    _prefs.setInt('theme_variant', variant.index);
  }

  void setAccentColor(AccentColor color) {
    state = state.copyWith(accentColor: color);
    _prefs.setInt('theme_accent', color.index);
  }

  void setDensity(DensityMode density) {
    state = state.copyWith(density: density);
    _prefs.setInt('theme_density', density.index);
  }

  void setFontScale(double scale) {
    final clamped = scale.clamp(0.85, 1.25);
    state = state.copyWith(fontScale: clamped);
    _prefs.setDouble('theme_font_scale', clamped);
  }
}

/// Injected in main.dart via ProviderScope.overrides.
final sharedPreferencesProvider = Provider<SharedPreferences>((ref) {
  throw UnimplementedError('Override in main.dart');
});

/// Theme preferences — persisted, drives the entire app's theme.
final themePreferencesProvider =
    StateNotifierProvider<ThemePreferencesNotifier, ThemePreferences>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  return ThemePreferencesNotifier(prefs);
});
