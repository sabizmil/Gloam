# BUG-004: Emoji picker shows "No Material widget found" error

**Reported:** 2026-03-26
**Status:** Open
**Priority:** P0 (crash)

## Description
Clicking the emoji icon (😊) in the message composer triggers a Flutter error: "No Material widget found."

## Steps to Reproduce
1. Open any room
2. Click the smiley face icon on the right side of the message input
3. Red error screen: "No Material widget found"

## Expected Behavior
The emoji picker overlay should appear with categories, search, and emoji grid.

## Actual Behavior
Flutter throws: `No Material widget found. TextField widgets require a Material widget ancestor.`

## Root Cause Analysis
In `emoji_picker.dart:270`, `showEmojiPicker` uses `showDialog` which wraps content in a `Dialog`. But the emoji picker is placed inside a `Stack` → `Positioned` → `GloamEmojiPicker`. The `GloamEmojiPicker` contains a `TextField` (the search bar) which requires a `Material` ancestor.

The `Stack` inside the dialog builder does not have a `Material` widget wrapping the `GloamEmojiPicker`:

```dart
builder: (ctx) => Stack(
  children: [
    GestureDetector(...),  // dismiss
    Positioned(
      child: GloamEmojiPicker(  // <-- contains TextField, no Material ancestor
```

The `Dialog` widget itself provides Material, but since `GloamEmojiPicker` is in a `Positioned` inside a `Stack` that's the direct child of the builder (not inside the Dialog), it lacks the Material ancestor.

## Implementation Plan
1. Wrap `GloamEmojiPicker` in a `Material(color: Colors.transparent)` widget
2. OR restructure to use `showDialog` properly with the picker as the Dialog child
3. Simplest fix: wrap the `Positioned` child:

```dart
Positioned(
  bottom: 80,
  right: 20,
  child: Material(
    color: Colors.transparent,
    child: GloamEmojiPicker(
      onSelect: (emoji) => Navigator.pop(ctx, emoji),
    ),
  ),
),
```

## Affected Files
- `lib/features/chat/presentation/widgets/emoji_picker.dart`
