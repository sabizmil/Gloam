# BUG-015: Image message captions not displayed in chat

**Reported:** 2026-03-26
**Status:** Open
**Priority:** P2 (Visual / polish)
**Effort:** S

## Description

When a user sends an image with a caption/comment in a Matrix room, the caption text is silently dropped in the chat UI. Only the image itself is rendered. The Matrix spec places the user's caption in the `body` field of the `m.room.message` event (with `msgtype: m.image`), while the actual filename is in `content.filename`. If no caption is provided, `body` defaults to the filename. Gloam currently treats `body` as the filename in all cases and never renders it below the image.

## Steps to Reproduce

1. Open any room in Gloam
2. From another client (e.g., Element), send an image with a caption/comment attached
3. Observe the message in Gloam

## Expected Behavior

The caption text should appear below the image thumbnail, styled small and italic so it reads as a comment rather than a full message. If the `body` is just the filename (i.e., no real caption was provided), nothing extra should be shown.

## Actual Behavior

Only the image is displayed. The caption/comment text is completely invisible. The `body` field is only shown when the image fails to load (error widget) or in the fullscreen view title bar.

## Root Cause Analysis

Three layers contribute to this bug:

### 1. `TimelineMessage` model lacks a `filename` field

**File:** `lib/features/chat/presentation/providers/timeline_provider.dart`
**Lines:** 9-55 (model definition)

The `TimelineMessage` data class has a `body` field but no `filename` field. Without a separate filename, the UI cannot determine whether `body` contains a user-authored caption or just the default filename.

### 2. `_mapEvent` doesn't extract `content.filename`

**File:** `lib/features/chat/presentation/providers/timeline_provider.dart`
**Lines:** 286-313 (the `_mapEvent` method, specifically the `TimelineMessage` constructor call)

The mapping function populates `body` from `_extractBody(event)` (which returns `event.body`), but never reads `event.content['filename']`. Per the Matrix spec ([MSC2530](https://github.com/matrix-org/matrix-spec-proposals/pull/2530) and the current spec), when a caption is present:
- `body` = the caption text
- `content.filename` = the actual filename

When no caption is present:
- `body` = the filename
- `content.filename` may or may not be present

### 3. `ImageMessage` widget doesn't render body text

**File:** `lib/features/chat/presentation/widgets/image_message.dart`
**Lines:** 90-105 (the `build` method)

The widget renders only the image container. The `body` text is used in exactly two places:
- Line 166: Inside the error widget as a fallback label
- Line 189: Passed as `filename` to the fullscreen view title bar

There is no code path that displays caption text below the image in the normal (non-error) rendering flow.

### 4. `_MessageContent` passes through only the `ImageMessage` widget

**File:** `lib/features/chat/presentation/widgets/message_bubble.dart`
**Line:** 277

```dart
'm.image' => ImageMessage(message: message, roomId: roomId),
```

The `m.image` case returns only the `ImageMessage` widget with no surrounding `Column` or additional text widget for caption display.

## Implementation Plan

### Step 1: Add `filename` field to `TimelineMessage`

In `timeline_provider.dart`, add an optional `String? filename` field to the `TimelineMessage` class. This stores the actual filename from `content.filename` (or `content.body` as fallback), allowing the UI to compare `body` vs `filename` to detect real captions.

### Step 2: Extract `filename` in `_mapEvent`

In the `_mapEvent` method, read `event.content['filename']` for media message types (`m.image`, `m.video`, `m.file`, `m.audio`). If `content.filename` is not present, fall back to `event.body` (which means no caption was provided, body IS the filename).

```dart
// In _mapEvent, before the return statement:
String? filename;
if (type == 'm.image' || type == 'm.video' || type == 'm.file' || type == 'm.audio') {
  filename = event.content.tryGet<String>('filename') ?? event.body;
}
```

### Step 3: Update `ImageMessage` to accept and render caption

In `image_message.dart`, update the `build` method to wrap the image container in a `Column` when a caption is present. The caption should be:
- Displayed only when `message.body != message.filename` (i.e., the body is a real caption, not the default filename)
- Styled small and italic (e.g., `fontSize: 12`, `fontStyle: FontStyle.italic`, `color: GloamColors.textSecondary`)
- Rendered below the image with a small top margin (`4px`)
- Constrained to the same `maxWidth` as the image (400px)

### Step 4: Update fullscreen view to use `filename` field

In `image_message.dart`, line 189, pass `message.filename ?? message.body` as the `filename` parameter to `_FullscreenImageView` so the title bar shows the actual filename, not the caption.

## Affected Files

| File | Change |
|------|--------|
| `lib/features/chat/presentation/providers/timeline_provider.dart` | Add `filename` field to `TimelineMessage`; extract `content.filename` in `_mapEvent` |
| `lib/features/chat/presentation/widgets/image_message.dart` | Render caption text below image when `body != filename`; use `filename` for fullscreen title |
