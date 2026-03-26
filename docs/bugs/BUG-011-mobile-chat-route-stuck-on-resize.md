# BUG-011: Mobile chat route persists when window resized to desktop width

- **Reported**: 2026-03-26
- **Status**: Open
- **Priority**: P1 (broken feature)

## Description

When the app is resized down to mobile width (<600px) and the user taps into a chat, the pushed mobile chat route stays on the Navigator stack even after the window is resized back to desktop/tablet width. The user gets stuck in a full-screen chat view with no sidebar and no way to navigate back to the room list — the desktop two-pane layout never reappears.

## Steps to Reproduce

1. Launch the app at desktop width (>1024px) — sidebar + chat pane visible
2. Resize the window below 600px to trigger mobile layout (MobileTabs)
3. Tap on any room in the room list
4. A full-screen `_MobileChatScreen` route is pushed via `Navigator.of(context).push()`
5. Resize the window back above 1024px
6. **Result**: The pushed route still covers the entire screen; no sidebar is visible

## Expected Behavior

When the window is resized back to desktop or tablet width, the app should display the standard two-pane layout (sidebar + chat area). The mobile chat route should be automatically dismissed so the user is returned to the responsive split view.

## Actual Behavior

The `MaterialPageRoute` pushed in `_selectRoom()` remains on top of the Navigator stack, occluding the entire `AdaptiveShell` layout beneath it. The user is stuck in the full-screen chat with no back button or sidebar.

## Root Cause Analysis

The issue spans two files:

### 1. `lib/app/shell/room_list_panel.dart` — lines 28-44

```dart
void _selectRoom(String roomId) {
  ref.read(selectedRoomProvider.notifier).state = roomId;

  // On mobile, push chat screen
  final width = MediaQuery.sizeOf(context).width;
  if (width < GloamSpacing.breakpointTablet) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => Scaffold(
          backgroundColor: GloamColors.bg,
          body: SafeArea(
            child: _MobileChatScreen(roomId: roomId),
          ),
        ),
      ),
    );
  }
}
```

When the viewport is narrow, `_selectRoom` pushes a full-screen `MaterialPageRoute` onto the root Navigator. This route sits on top of the `HomeScreen` → `AdaptiveShell` widget tree.

### 2. `lib/app/shell/adaptive_shell.dart` — lines 20-31

```dart
Widget build(BuildContext context, WidgetRef ref) {
  return LayoutBuilder(
    builder: (context, constraints) {
      if (constraints.maxWidth >= GloamSpacing.breakpointTablet) {
        return const _DesktopShell();
      } else if (constraints.maxWidth >= GloamSpacing.breakpointPhone) {
        return const _TabletShell();
      } else {
        return const MobileTabs();
      }
    },
  );
}
```

The `LayoutBuilder` correctly switches the *underlying* shell when the viewport changes. But because the mobile chat route was pushed **on top** of this widget via the root Navigator, the `AdaptiveShell` rebuilds under the opaque route — the user never sees it. There is no code that pops the mobile route when the window crosses back above the breakpoint.

### Core problem

Imperative navigation (`Navigator.push`) creates a route that is decoupled from the declarative layout logic (`LayoutBuilder` breakpoints). There is no listener or mechanism that pops the mobile chat route when the viewport widens past the mobile breakpoint.

## Implementation Plan

### Approach: Pop mobile route on viewport width change

The simplest fix is to detect when the viewport transitions from mobile to tablet/desktop width while a mobile chat route is active, and automatically pop it. The `selectedRoomProvider` already holds the selected room, so the desktop/tablet shells will immediately display the correct chat.

**Option A (recommended) — LayoutBuilder-aware route management in AdaptiveShell:**

Add a `ConsumerStatefulWidget` wrapper (or convert `AdaptiveShell`) that tracks whether a mobile chat route has been pushed and pops it when the layout crosses back above the mobile breakpoint.

Changes to `lib/app/shell/adaptive_shell.dart`:
1. Convert `AdaptiveShell` from `ConsumerWidget` to `ConsumerStatefulWidget`
2. Track a boolean `_mobileChatRoutePushed` (or use a Riverpod provider for cross-widget access)
3. In the `LayoutBuilder`, when `constraints.maxWidth >= breakpointPhone` and a mobile route is active, call `Navigator.of(context).pop()` via a post-frame callback
4. Reset the tracking flag after popping

Changes to `lib/app/shell/room_list_panel.dart`:
1. When pushing the mobile chat route, set the tracking state (e.g., a provider) to `true`
2. When the route is popped (via back button or automatic pop), set it to `false`
3. Use the `.then()` callback on `Navigator.push` to reset the state

**Alternatively (Option B) — Use a provider to track mobile navigation state:**

Create a `mobileChatRouteActiveProvider` (StateProvider<bool>) that:
- Gets set to `true` when `_selectRoom` pushes the mobile route
- Gets set to `false` when the route completes (via `.then()` on `Navigator.push`)
- Is watched by `AdaptiveShell`; when the shell switches to desktop/tablet mode and the provider is `true`, it pops the route and resets the provider

**Option B is cleaner** because it avoids stashing Navigator state in a StatefulWidget and makes the state accessible across the widget tree.

### Concrete steps (Option B):

1. **Add provider** in `lib/features/chat/presentation/providers/timeline_provider.dart` (or a new navigation_state file):
   ```dart
   final mobileChatRouteActiveProvider = StateProvider<bool>((ref) => false);
   ```

2. **Update `_selectRoom`** in `lib/app/shell/room_list_panel.dart`:
   ```dart
   void _selectRoom(String roomId) {
     ref.read(selectedRoomProvider.notifier).state = roomId;
     final width = MediaQuery.sizeOf(context).width;
     if (width < GloamSpacing.breakpointTablet) {
       ref.read(mobileChatRouteActiveProvider.notifier).state = true;
       Navigator.of(context).push(
         MaterialPageRoute(
           builder: (_) => Scaffold(
             backgroundColor: GloamColors.bg,
             body: SafeArea(child: _MobileChatScreen(roomId: roomId)),
           ),
         ),
       ).then((_) {
         ref.read(mobileChatRouteActiveProvider.notifier).state = false;
       });
     }
   }
   ```

3. **Update `AdaptiveShell`** in `lib/app/shell/adaptive_shell.dart`:
   Convert to `ConsumerStatefulWidget` or add logic in the `LayoutBuilder` builder. When the layout is tablet or desktop and `mobileChatRouteActiveProvider` is `true`, schedule a pop:
   ```dart
   Widget build(BuildContext context, WidgetRef ref) {
     final mobileRouteActive = ref.watch(mobileChatRouteActiveProvider);
     return LayoutBuilder(
       builder: (context, constraints) {
         final isDesktopOrTablet = constraints.maxWidth >= GloamSpacing.breakpointPhone;
         if (isDesktopOrTablet && mobileRouteActive) {
           WidgetsBinding.instance.addPostFrameCallback((_) {
             if (Navigator.of(context).canPop()) {
               Navigator.of(context).pop();
             }
             ref.read(mobileChatRouteActiveProvider.notifier).state = false;
           });
         }
         if (constraints.maxWidth >= GloamSpacing.breakpointTablet) {
           return const _DesktopShell();
         } else if (constraints.maxWidth >= GloamSpacing.breakpointPhone) {
           return const _TabletShell();
         } else {
           return const MobileTabs();
         }
       },
     );
   }
   ```

## Affected Files

- `lib/app/shell/adaptive_shell.dart` — add viewport-change route popping logic
- `lib/app/shell/room_list_panel.dart` — track mobile route lifecycle via provider
- `lib/features/chat/presentation/providers/timeline_provider.dart` (or new file) — add `mobileChatRouteActiveProvider`
