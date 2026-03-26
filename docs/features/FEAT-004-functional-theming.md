# FEAT-004: Functional Theming — Wire Up Appearance Settings

**Requested:** 2026-03-26
**Status:** Proposed
**Priority:** High

---

## Description

The settings panel already contains a well-designed Appearance section (`lib/features/settings/presentation/sections/appearance_section.dart`) with UI for four theming controls:

1. **Theme variant** — Three cards: "gloam dark" (default), "midnight" (blue-tinted dark), "dawn" (light mode). Currently hardcoded `isSelected: true` on "gloam dark".
2. **Density** — Three chips: "compact", "comfortable" (default), "spacious". Currently hardcoded `isSelected: true` on "comfortable".
3. **Accent color** — Six color dots (green, blue, pink, gold, purple, teal). Currently hardcoded `isSelected: true` on green.
4. **Font size** — A slider with small/large A labels. Currently `value: 0.5`, `onChanged: (_) {}` (no-op).

None of these controls are wired to state. The app's theme is built by `buildGloamTheme()` in `lib/app/theme/gloam_theme.dart`, which directly references the static `GloamColors` constants — there is no indirection layer that would allow runtime switching. The `GloamColors` class is an `abstract final class` of static `const` values, and `GloamTypography` follows the same pattern. The `GloamApp` widget passes `buildGloamTheme()` directly to `MaterialApp.router`'s `theme` parameter with no dark/light mode awareness.

This feature request is about making those existing UI controls functional: selecting a theme, density, accent color, or font size should immediately update the app's appearance across all screens.

## User Story

As a Gloam user, I want to change the app's theme, accent color, density, and font size from the appearance settings so that I can personalize the app to my preferences and have those choices persist across sessions.

---

## Implementation Approaches

### Approach 1: Riverpod StateNotifier + Rebuilt Color Tokens

**Summary:** Create a `ThemeNotifier` (Riverpod) that holds theme preferences and generates a new `ThemeData` on every change. Replace static `GloamColors` references with dynamic lookups.

**Technical approach:**
- Define a `ThemePreferences` model: `{themeVariant, accentColor, density, fontScale}`
- Create `themePreferencesProvider` as a `StateNotifierProvider<ThemeNotifier, ThemePreferences>`
- `ThemeNotifier` loads/saves preferences to drift (existing DB) or `SharedPreferences`
- `buildGloamTheme()` becomes `buildGloamTheme(ThemePreferences prefs)` — parameterized
- Create a `GloamColorSet` class (non-static, instantiated per variant) replacing the static `GloamColors`
- `GloamApp` watches `themePreferencesProvider` and passes the resulting `ThemeData` to `MaterialApp.router`
- All widgets that reference `GloamColors.xyz` directly continue to work via `Theme.of(context).colorScheme` or a custom `InheritedWidget`

**Pros:**
- Clean separation of preferences from rendering
- Fits the existing Riverpod pattern used throughout the app
- `ThemeData` propagates automatically via `MaterialApp` — all standard widgets respond
- Font scale can use `MediaQuery` text scale factor override
- Density maps to `VisualDensity` in `ThemeData`

**Cons:**
- ~40 files reference `GloamColors.xyz` directly — all need migration to either `Theme.of(context)` or a context extension
- Large changeset: touching every widget that uses color tokens
- Risk of regressions across the UI during migration
- `SharedPreferences` is a new dependency (drift is overkill for 4 preferences)

**Effort:** High (5-7 days) — most time is the migration, not the provider

**Dependencies:** `shared_preferences` package (new)

---

### Approach 2: InheritedWidget Color Provider + Minimal Migration

**Summary:** Wrap the app in a custom `GloamTheme` InheritedWidget that provides a resolved `GloamColorSet` based on preferences. Keep `GloamColors` as the fallback but add `GloamTheme.of(context)` as the primary access pattern. Migrate incrementally.

**Technical approach:**
- Create `GloamColorSet` — a non-static class with the same fields as `GloamColors`, instantiated per theme variant
- Create three presets: `GloamColorSet.dark()`, `GloamColorSet.midnight()`, `GloamColorSet.dawn()`
- Create `GloamThemeData` that bundles `GloamColorSet` + density + font scale
- Create `GloamThemeProvider` InheritedWidget (placed above `MaterialApp` in the tree)
- Preferences stored via `SharedPreferences`; loaded on startup, updated in settings
- `GloamTheme.of(context).colors.accent` replaces `GloamColors.accent`
- Phase 1: Wire up settings controls + `GloamThemeProvider`. Theme variant works via `MaterialApp.theme`/`darkTheme` switching
- Phase 2: Incrementally migrate `GloamColors.xyz` references to `GloamTheme.of(context)` (can be done file-by-file)

**Pros:**
- Incremental migration — doesn't require touching all 40 files at once
- `GloamColors` continues to work as a fallback (static = dark theme defaults)
- InheritedWidget is zero-dependency, pure Flutter
- Accent color and density can work immediately via `ThemeData` without migrating individual widgets
- Familiar pattern (matches how `Theme.of(context)` already works)

**Cons:**
- Two color access patterns coexist during migration (`GloamColors.x` and `GloamTheme.of(context).colors.x`) — confusing for contributors
- InheritedWidget doesn't persist state — still needs a Riverpod provider or similar to manage the actual preferences
- Custom InheritedWidget is redundant with Flutter's built-in `Theme` / `ColorScheme`

**Effort:** Medium (3-5 days for Phase 1, then ongoing migration)

**Dependencies:** `shared_preferences` package (new)

---

### Approach 3: Extend Flutter ColorScheme + ThemeExtension

**Summary:** Use Flutter's built-in `ThemeExtension` API to attach Gloam's custom tokens to `ThemeData`. All widgets access colors via `Theme.of(context).extension<GloamColorExtension>()`. Theme variant switching is just swapping `ThemeData`.

**Technical approach:**
- Create `GloamColorExtension extends ThemeExtension<GloamColorExtension>` with all Gloam tokens
- Define `lerp` for animated theme transitions
- Create three `ThemeData` presets (dark, midnight, dawn), each with a `GloamColorExtension`
- `themePreferencesProvider` (Riverpod) holds the active variant + accent + density + scale
- `GloamApp` watches the provider, passes the resolved `ThemeData`
- Access pattern: `Theme.of(context).extension<GloamColorExtension>()!.accent`
- Create a convenience extension: `context.gloam.accent` for brevity
- Font scale: override `MediaQuery.textScaleFactor` in the widget tree
- Density: set `ThemeData.visualDensity`

**Pros:**
- Uses Flutter's official mechanism for custom theme tokens
- `ThemeExtension.lerp` enables smooth animated transitions between themes
- No custom InheritedWidget — everything goes through `Theme.of(context)`
- `ColorScheme` maps automatically for standard Material widgets
- Clean, idiomatic Flutter — any Flutter developer understands the pattern

**Cons:**
- Still requires migrating ~40 files from `GloamColors.xyz` to `context.gloam.xyz`
- `ThemeExtension` access is verbose without the convenience extension method
- `lerp` implementation for 15+ color tokens is boilerplate-heavy
- Theme transitions (if animated) could cause frame drops on lower-end devices

**Effort:** Medium-High (4-6 days)

**Dependencies:** None new (ThemeExtension is built into Flutter)

---

### Approach 4: Dynamic GloamColors via Top-Level Mutable State

**Summary:** Make `GloamColors` fields non-const and mutable (or use a global singleton). When the user changes theme, overwrite the values and call `setState` at the app root to rebuild.

**Technical approach:**
- Change `GloamColors` from `abstract final class` with `static const` to a class with `static` (mutable) fields
- On theme change, update the static fields and trigger a root rebuild via a `ValueNotifier` or Riverpod provider that `GloamApp` watches
- All existing `GloamColors.accent` references work without any migration
- Persist preferences to `SharedPreferences`

**Pros:**
- Zero migration cost — every existing `GloamColors.xyz` reference automatically picks up the new values on rebuild
- Fastest to implement by far
- No new patterns to learn or maintain

**Cons:**
- Global mutable state is an anti-pattern — leads to subtle bugs (stale captures in closures, animation controllers holding old values)
- No animated transitions possible (values snap, widgets rebuild from scratch)
- `const` constructors throughout the codebase will need removal (many widgets use `const` that depend on `GloamColors` — changing to non-const could hurt performance)
- Testability suffers — can't easily test different themes in isolation
- Goes against Flutter's reactive/declarative model
- `GloamTypography` has the same problem (static references to `GloamColors`)

**Effort:** Low (1-2 days)

**Dependencies:** `shared_preferences` package (new)

---

### Approach 5: Riverpod + ColorScheme Mapping (Minimal Custom Tokens)

**Summary:** Map all Gloam tokens into Flutter's standard `ColorScheme` roles. Theme switching is just swapping `ColorScheme`. Minimal custom token surface.

**Technical approach:**
- Map Gloam tokens to `ColorScheme` fields: `surface` = bg, `onSurface` = textPrimary, `primary` = accent, `secondary` = accentDim, `outline` = border, etc.
- Already partially done in `buildGloamTheme()` — extend to cover all tokens
- For tokens that don't map to `ColorScheme` (e.g., `textTertiary`, `bgElevated`, `accentBright`), use 2-3 `ThemeExtension` fields
- Three `ColorScheme` presets: dark, midnight, dawn
- Accent color variants: generate derived `ColorScheme` using `ColorScheme.fromSeed` with the selected accent hue
- `themePreferencesProvider` drives the active scheme
- Migrate widgets from `GloamColors.xyz` to `Theme.of(context).colorScheme.xyz` (standard Flutter access)

**Pros:**
- Leverages Flutter's built-in theming to the maximum — Material widgets just work
- Smallest custom code surface (only 3-5 extension tokens instead of 15+)
- `ColorScheme.fromSeed` can generate consistent accent variants automatically
- Standard pattern means AI tools, linters, and Flutter DevTools understand the theme
- Easiest for other contributors to reason about

**Cons:**
- `ColorScheme` has limited named roles — some Gloam tokens require creative mapping or extension
- `ColorScheme.fromSeed` generates Material 3 dynamic colors that may clash with Gloam's hand-crafted palette
- Loses the explicitness of named tokens like `bgElevated`, `textTertiary` — replaced by generic Material names
- Gloam's green-tinted neutral system doesn't survive `fromSeed` — would need manual overrides
- Still requires migrating ~40 files

**Effort:** Medium (3-4 days)

**Dependencies:** None new

---

## Recommendation

**Approach 3: Extend Flutter ColorScheme + ThemeExtension** is the best fit.

**Rationale:**

1. **It's the official Flutter pattern.** `ThemeExtension` was specifically designed for custom design systems that need more tokens than `ColorScheme` provides. Gloam's 15+ tokens (green-tinted neutrals, three accent variants, three text tiers, three background tiers) don't map cleanly into `ColorScheme`'s generic roles — they need their own type-safe extension.

2. **Animated theme transitions come free.** The `lerp` implementation on `ThemeExtension` means switching from "gloam dark" to "dawn" can smoothly crossfade every color in the app. This is a meaningful UX win that reinforces Gloam's atmospheric identity.

3. **No new dependencies.** `ThemeExtension` is built into Flutter. Preferences persistence can use drift (already in the project) via a simple key-value table, avoiding the `shared_preferences` dependency. Alternatively, `shared_preferences` is lightweight and well-established — either works, but drift keeps the dependency list tight.

4. **Plays well with Riverpod.** A `themePreferencesProvider` Notifier drives the active `ThemeData`. `GloamApp` watches it. This is identical to the pattern used by `authProvider` and `roomListProvider` — no architectural novelty.

5. **Preserves Gloam's named tokens.** Unlike Approach 5, the custom extension keeps `accent`, `accentBright`, `accentDim`, `bgSurface`, `bgElevated`, `textTertiary` as first-class, type-safe properties. The design system document at `docs/plan/09-design-system.md` defines these explicitly — they should be addressable by name, not mapped to `surfaceContainerHighest`.

6. **Migration is mechanical.** The `GloamColors.xyz` to `context.gloam.xyz` migration is a find-and-replace operation across ~40 files. It's tedious but low-risk and can be done incrementally — the static `GloamColors` continues to serve as the dark-theme default during transition.

**Why not Approach 4 (mutable globals)?** Despite the zero-migration appeal, mutable global state breaks `const` constructors throughout the codebase, prevents animated transitions, and makes testing painful. The short-term convenience isn't worth the long-term cost.

**Why not Approach 2 (InheritedWidget)?** It's essentially a hand-rolled version of what `ThemeExtension` already provides. No reason to build custom infrastructure when Flutter has a built-in solution.

---

## Implementation Plan

### Step 1: Create ThemePreferences Model and Provider

**Files to create:**
- `lib/app/theme/theme_preferences.dart` — Freezed model: `ThemeVariant` enum (gloamDark, midnight, dawn), `AccentColor` enum (green, blue, pink, gold, purple, teal), `Density` enum (compact, comfortable, spacious), `double fontScale` (0.85–1.25)
- `lib/app/theme/theme_preferences_provider.dart` — `themePreferencesProvider` (StateNotifier or Notifier), loads from / saves to `SharedPreferences` or drift key-value store

**State management approach:**
- `ThemePreferencesNotifier extends StateNotifier<ThemePreferences>`
- Methods: `setVariant()`, `setAccentColor()`, `setDensity()`, `setFontScale()`
- Each setter persists the change and updates state
- On startup, loads persisted preferences (defaulting to gloam dark / green / comfortable / 1.0)

### Step 2: Create GloamColorExtension

**Files to create:**
- `lib/app/theme/gloam_color_extension.dart` — `GloamColorExtension extends ThemeExtension<GloamColorExtension>` with all 15 color tokens from `GloamColors`
- Three factory constructors: `.dark()`, `.midnight()`, `.dawn()` matching the design system spec

**Color definitions:**

| Token | Gloam Dark | Midnight | Dawn |
|-------|-----------|----------|------|
| bg | #080F0A | #0A0F14 | #F5F5F0 |
| bgSurface | #0D1610 | #0F1520 | #E8EDE9 |
| bgElevated | #121E16 | #152030 | #FFFFFF |
| border | #1A2B1E | #1A2540 | #C8D4CA |
| borderSubtle | #132019 | #121D35 | #DCE4DD |
| textPrimary | #C8DCCB | #C8D4E0 | #1A2B1E |
| textSecondary | #6B8A70 | #6B7D9A | #5A7A5F |
| textTertiary | #3D5C42 | #3D4F6A | #8FA894 |
| accent | (per accent color selection) | (per accent color selection) | (per accent color selection) |
| accentBright | (derived) | (derived) | (derived) |
| accentDim | (derived) | (derived) | (derived) |
| danger | #C45C5C | #C45C5C | #C45C5C |
| warning | #C4A35C | #C4A35C | #C4A35C |
| info | #5C8AC4 | #5C8AC4 | #5C8AC4 |
| overlay | #CC0D1610 | #CC0F1520 | #CCE8EDE9 |

**Accent color derivation:**
Each accent base color gets bright (+40 lightness) and dim (-30 lightness) variants. The `online` token always matches `accent`.

**Include `lerp` implementation** for smooth animated transitions between variants.

### Step 3: Create GloamDensity Extension

**File to modify:** `lib/app/theme/spacing.dart`

Add density-aware spacing helpers:
- `GloamSpacing.roomListItemHeight(Density d)` — compact: 44, comfortable: 56, spacious: 68
- `GloamSpacing.messagePadding(Density d)` — compact: 8, comfortable: 12, spacious: 16
- `GloamSpacing.avatarSize(Density d)` — compact: 28, comfortable: 36, spacious: 44

Density also maps to Flutter's `VisualDensity` in `ThemeData`.

### Step 4: Parameterize Theme Builder

**File to modify:** `lib/app/theme/gloam_theme.dart`

- `buildGloamTheme()` becomes `buildGloamTheme(ThemePreferences prefs)`
- Resolves `GloamColorExtension` from variant + accent
- Resolves `VisualDensity` from density
- Applies `textTheme` with `fontScale` multiplier
- Attaches `GloamColorExtension` via `ThemeData.extensions`

### Step 5: Wire GloamApp to Provider

**File to modify:** `lib/app/app.dart`

- `GloamApp` already extends `ConsumerWidget` — add `ref.watch(themePreferencesProvider)`
- Pass resolved `ThemeData` to `MaterialApp.router(theme: ...)`
- Wrap with `MediaQuery` override for font scale if not using `textScaleFactor`

### Step 6: Create Context Extension for Convenience

**File to create:** `lib/app/theme/gloam_theme_context.dart`

```dart
extension GloamThemeContext on BuildContext {
  GloamColorExtension get gloam =>
      Theme.of(this).extension<GloamColorExtension>()!;
}
```

This enables `context.gloam.accent` throughout the codebase.

### Step 7: Wire Up AppearanceSection Controls

**File to modify:** `lib/features/settings/presentation/sections/appearance_section.dart`

- Convert from `StatelessWidget` to `ConsumerWidget`
- Theme cards: `onTap` calls `ref.read(themePreferencesProvider.notifier).setVariant(variant)`
- Density chips: `onTap` calls `ref.read(themePreferencesProvider.notifier).setDensity(density)`
- Accent dots: `onTap` calls `ref.read(themePreferencesProvider.notifier).setAccentColor(color)`
- Font slider: `onChanged` calls `ref.read(themePreferencesProvider.notifier).setFontScale(value)`
- All `isSelected` properties derive from `ref.watch(themePreferencesProvider)`
- The settings modal itself reactively updates as theme changes (immediate visual feedback)

### Step 8: Migrate Color References (Incremental)

**Files to modify:** ~40 files under `lib/`

- Replace `GloamColors.xyz` with `context.gloam.xyz`
- Replace `GloamTypography.xyz` calls to reference the extension colors (or create a parallel `GloamTypographyExtension`)
- This can be done incrementally — `GloamColors` static fields remain as dark-theme defaults
- Priority order: (1) settings modal, (2) chat screen & message bubble, (3) room list, (4) space rail & shell, (5) remaining widgets

### Step 9: Persistence

**Option A (preferred): Drift key-value table**
- Add a `preferences` table to the existing drift database: `key TEXT PRIMARY KEY, value TEXT`
- Store theme preferences as JSON
- No new dependency

**Option B: SharedPreferences**
- Add `shared_preferences` to pubspec.yaml
- Simpler API but adds a dependency

### Step 10: System Theme Integration

**File to modify:** `lib/app/app.dart`

- Add an "auto" option to theme variant that follows `MediaQuery.platformBrightnessOf(context)`
- When "auto": dark variants at night, dawn during day (or follow system setting)
- This is a UX enhancement, not blocking for v1

### New Dependencies Needed

- None strictly required (drift is already available for persistence)
- Optional: `shared_preferences` if drift key-value feels heavy

### Edge Cases

- **Theme change during animation:** Ensure in-flight animations don't hold stale color references. `ThemeExtension.lerp` handles this for theme-driven properties.
- **Font scale extremes:** Clamp to 0.85–1.25. Below 0.85 makes text illegible; above 1.25 breaks layouts.
- **Dawn (light) theme contrast:** Verify all text/background combinations meet WCAG AA (4.5:1) contrast ratios. The design system spec defines light mode mappings but they haven't been tested in practice.
- **Midnight theme definition:** The design system doc defines dark and light modes, but "midnight" is new. Needs a careful blue-tinted neutral palette that maintains the same contrast ratios as gloam dark.
- **Density + large font scale:** Compact density at 1.25x font scale will clip text. Need to test all combinations and potentially force comfortable density at high font scales.
- **Settings modal self-theming:** The modal must reactively update as the user changes settings — they should see the result immediately.
- **Keyboard shortcut overlay, quick switcher, dialogs:** These use `GloamColors` directly and won't respond to theme changes until migrated. Prioritize visible surfaces.
- **Cached/stale ThemeData:** Ensure `GoRouter` routes rebuild when theme changes. `MaterialApp.router` rebuilds its subtree when `theme` changes, so this should be automatic.
- **Platform dark/light mode toggle:** On macOS/iOS, the system can toggle dark/light while the app is running. The "auto" variant needs to respond to `platformBrightness` changes.

---

## Acceptance Criteria

- [ ] Tapping a theme card (gloam dark / midnight / dawn) immediately changes the app's color palette across all screens
- [ ] Tapping an accent color dot updates the accent, accentBright, and accentDim tokens throughout the app
- [ ] Tapping a density chip adjusts spacing, avatar sizes, and visual density
- [ ] Dragging the font size slider scales text across the app in real time
- [ ] Theme preferences persist across app restarts
- [ ] Theme transitions are smooth (animated crossfade, not a hard snap)
- [ ] The settings modal itself reflects changes as they're made (live preview)
- [ ] Dawn (light) theme passes WCAG AA contrast for all text/background pairs
- [ ] Midnight theme has a cohesive blue-tinted neutral palette
- [ ] Compact density does not clip text at default font scale
- [ ] Font scale is clamped between 0.85 and 1.25
- [ ] All five platforms render theme changes correctly (macOS, iOS, Android, Windows, Linux)
- [ ] No regressions in existing UI — all screens look correct in the default gloam dark theme

---

## Related

- [FEAT-001: Global Settings Panel](FEAT-001-global-settings-panel.md) — parent feature; this wires up the Appearance section created there
- `lib/features/settings/presentation/sections/appearance_section.dart` — existing UI to wire up
- `lib/app/theme/color_tokens.dart` — current static color definitions (to be supplemented by ThemeExtension)
- `lib/app/theme/gloam_theme.dart` — current theme builder (to be parameterized)
- `lib/app/theme/typography.dart` — typography definitions referencing GloamColors (need migration)
- `lib/app/theme/spacing.dart` — spacing constants (density-aware helpers to add)
- `lib/app/app.dart` — MaterialApp.router where theme is applied
- `docs/plan/09-design-system.md` — canonical design system spec with light mode mappings and accent alternatives
