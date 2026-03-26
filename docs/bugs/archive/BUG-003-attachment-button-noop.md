# BUG-003: Attachment (+) button does nothing

**Reported:** 2026-03-26
**Status:** Open
**Priority:** P1 (broken feature)

## Description
The + button next to the message composer for attaching files/images does nothing when clicked.

## Steps to Reproduce
1. Open any room
2. Click the + (add_circle_outline) icon to the left of the message input
3. Nothing happens — no file picker, no menu, no feedback

## Expected Behavior
Clicking should open a file picker or a bottom sheet/menu with options:
- Photo/Video (system photo picker)
- File (system file picker)
- Camera (mobile only)

## Actual Behavior
The `onPressed` callback is an empty function: `onPressed: () {}`.

## Root Cause Analysis
In `message_composer.dart:172`, the attachment button has a no-op handler:

```dart
IconButton(
  onPressed: () {},  // <-- empty
  icon: const Icon(Icons.add_circle_outline, ...),
```

File picking was stubbed during Phase 1 and never implemented.

## Implementation Plan
1. Add `file_picker` package to pubspec.yaml (or use `image_picker` for photos)
2. On tap, show a popup menu or bottom sheet with options: "File", "Photo"
3. Use `FilePicker.platform.pickFiles()` for general files
4. For the picked file, call `room.sendFileEvent()` from matrix_dart_sdk
5. Handle encrypted rooms: the SDK auto-encrypts attachments when E2EE is enabled
6. Show upload progress indicator on the message while uploading

## Affected Files
- `pubspec.yaml` (add `file_picker` dependency)
- `lib/features/chat/presentation/widgets/message_composer.dart`
- `lib/features/chat/presentation/providers/timeline_provider.dart` (add `sendFileMessage` method)
