# BUG-002: Link previews not clickable, no hover cursor

**Reported:** 2026-03-26
**Status:** Open
**Priority:** P1 (broken feature)

## Description
Link preview cards display correctly in the chat, but clicking them does nothing. There's no cursor change on hover to indicate they're interactive.

## Steps to Reproduce
1. Send or receive a message containing a URL (e.g. https://example.com)
2. Wait for the link preview card to render below the message
3. Hover over the preview card — no cursor change
4. Click the preview card — nothing happens

## Expected Behavior
- Hover: cursor changes to pointer
- Click: opens the URL in the system default browser
- The open_in_new icon on the right suggests it should be clickable

## Actual Behavior
The preview card is a static `Container` with no interactivity. No `GestureDetector`, `InkWell`, or `MouseRegion` wrapping it.

## Root Cause Analysis
In `link_preview.dart:66`, the preview card is a plain `Container` → `Row`. There is no tap handler or `url_launcher` call. The `open_in_new` icon is decorative only.

```dart
return Container(
  margin: const EdgeInsets.only(top: 6),
  // ... no GestureDetector wrapping this
```

## Implementation Plan
1. Wrap the preview `Container` in a `MouseRegion` (for cursor) + `GestureDetector` (for tap)
2. On tap, call `launchUrl(Uri.parse(_url!))` from the `url_launcher` package (already in pubspec)
3. Add `cursor: SystemMouseCursors.click` via `MouseRegion`
4. Add a subtle hover state (lighten border or background)

## Affected Files
- `lib/features/chat/presentation/widgets/link_preview.dart`
