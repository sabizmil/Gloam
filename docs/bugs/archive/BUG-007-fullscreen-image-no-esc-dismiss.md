# BUG-007: Fullscreen image viewer does not dismiss on Escape key

- **Reported**: 2026-03-26
- **Status**: Open
- **Priority**: P2 (visual/polish)
- **Effort**: 15 min

## Description

When viewing a media item (image) in fullscreen, the only way to close it is by clicking the "X" button in the top-left corner. Pressing the Escape key on the keyboard does nothing. On a desktop app, Escape is the universally expected dismiss gesture for fullscreen/modal overlays.

## Steps to Reproduce

1. Open a chat room containing an image message
2. Click on the image to open the fullscreen viewer
3. Press the Escape key on the keyboard
4. Observe that nothing happens — the fullscreen viewer stays open

## Expected Behavior

Pressing Escape should dismiss the fullscreen image viewer and return to the chat, identical to clicking the "X" close button.

## Actual Behavior

Escape key is ignored. The user must click the "X" icon button to close the viewer.

## Root Cause Analysis

The fullscreen image viewer is implemented as `_FullscreenImageView` in `/Users/sabizmil/Developer/matrix-chat/lib/features/chat/presentation/widgets/image_message.dart` (lines 198-230).

The widget is a plain `StatelessWidget` containing a `Scaffold` with an `AppBar`. It has no keyboard event handling — no `KeyboardListener`, `Focus` node, or `CallbackShortcuts` widget wrapping the view.

The app does have a global `ClosePanelIntent` mapped to `Escape` in `lib/app/shortcuts.dart` (line 74), but the fullscreen viewer is pushed as a new route via `Navigator.of(context).push()` (line 181). This route sits above the `Shortcuts` widget in the widget tree, so the global Escape binding is not active while the viewer is visible.

The `Scaffold` widget does not automatically handle Escape to pop the route on desktop platforms — Flutter requires explicit keyboard handling for this.

## Implementation Plan

Wrap the `_FullscreenImageView` body in a `CallbackShortcuts` + `Focus` widget that listens for the Escape key and calls `Navigator.pop(context)`. This follows the existing keyboard shortcut pattern used elsewhere in the app.

Specific changes to `_FullscreenImageView.build()` in `image_message.dart`:

1. Convert `_FullscreenImageView` from `StatelessWidget` to `StatefulWidget` (needed for a `FocusNode` with `autofocus`)
2. Wrap the `Scaffold` in `CallbackShortcuts` with `SingleActivator(LogicalKeyboardKey.escape)` mapped to `Navigator.pop(context)`
3. Wrap that in a `Focus` widget with `autofocus: true` so the view captures keyboard events immediately on open
4. Dispose the `FocusNode` in the state's `dispose()` method

Alternative (simpler): Keep it as a `StatelessWidget` and just wrap the Scaffold with `KeyboardListener` using a `FocusNode(autofocus: true)` — but `CallbackShortcuts` is the cleaner pattern already established in this codebase.

## Affected Files

- `lib/features/chat/presentation/widgets/image_message.dart` — `_FullscreenImageView` class (lines 198-230)
