# FEAT-010: Sliding Sync (MSC4186)

**Requested:** 2026-03-26
**Status:** Proposed
**Priority:** High
**Effort:** Large (3-4 weeks)

---

## The Problem

Gloam uses traditional `/v3/sync`, which downloads **everything** — every room, every state event, every receipt — on initial sync. This creates three pain points:

1. **Slow initial sync**: Accounts with many rooms take minutes to load. Even a modest account feels sluggish on first launch.
2. **Empty federated rooms**: Newly-joined federated rooms show no messages until the full room state bootstraps. Element shows messages instantly because it uses Sliding Sync to request exactly what it needs.
3. **Bandwidth waste**: Sync delivers data for all rooms even when the user is only looking at one. Receipts, typing indicators, and state events for hundreds of rooms nobody is viewing.

## The Solution

**Simplified Sliding Sync (MSC4186)** — the client tells the server "I'm looking at rooms 0-19, give me their latest message and metadata" and the server responds in <100ms. Room timeline is fetched on-demand when the user opens a room.

- **Native in Synapse 1.114+** — no proxy, no config, just works
- **nerdforge.xyz already supports it** — any modern Synapse does
- **Element X uses it exclusively** — proven in production

## The Challenge

**The Dart `matrix` SDK (v0.40.2) does not support Sliding Sync.** Zero implementation — no classes, no methods, no MSC3575 or MSC4186 support. This means Gloam must build it from scratch: raw HTTP calls to `/_matrix/client/v4/sync`, response parsing, and integration with the SDK's room/timeline models.

This is the largest technical lift in the project. But it transforms Gloam from "works OK on small accounts" to "instant on any account."

---

## How Sliding Sync Works

### Traditional Sync vs Sliding Sync

| Aspect | Traditional `/v3/sync` | Sliding Sync `/v4/sync` |
|--------|----------------------|------------------------|
| Initial load | All rooms, all state | Only visible window (e.g., 20 rooms) |
| Performance | O(N) with room count | O(1) — constant regardless of account size |
| Room list | Server pushes everything | Client requests specific ranges |
| Timeline | Delivered via sync stream | On-demand per room subscription |
| Incremental updates | Everything since last sync | Only rooms the client cares about |
| Time to first render | Seconds to minutes | < 100ms |

### The Request/Response Cycle

**Client sends:**
```json
POST /_matrix/client/v4/sync
{
  "conn_id": "gloam-main",
  "timeout": 30000,
  "lists": {
    "all_rooms": {
      "ranges": [[0, 19]],
      "timeline_limit": 1,
      "required_state": [
        ["m.room.name", ""],
        ["m.room.avatar", ""],
        ["m.room.encryption", ""],
        ["m.room.canonical_alias", ""]
      ],
      "filters": {},
      "include_heroes": true
    }
  },
  "room_subscriptions": {
    "!active_room:server": {
      "timeline_limit": 50,
      "required_state": [["m.room.member", "*"]]
    }
  },
  "extensions": {
    "e2ee": { "enabled": true },
    "to_device": { "enabled": true },
    "account_data": { "enabled": true },
    "typing": { "enabled": true },
    "receipts": { "enabled": true }
  }
}
```

**Server responds:**
```json
{
  "pos": "6",
  "lists": {
    "all_rooms": {
      "count": 347,
      "ops": [{"op": "SYNC", "range": [0, 19], "room_ids": ["!room1", ...]}]
    }
  },
  "rooms": {
    "!room1:server": {
      "name": "General",
      "initial": true,
      "bump_stamp": 1711234567,
      "notification_count": 3,
      "joined_count": 42,
      "timeline": [{"type": "m.room.message", "content": {"body": "hello"}, ...}],
      "required_state": [...]
    }
  },
  "extensions": { ... }
}
```

### Key Concepts

- **Lists**: Named groups of rooms with filters (DMs, spaces, all). Each has a visible range.
- **Ranges**: `[[0, 19]]` = "give me rooms at positions 0-19 in the sorted list." Shift the range as the user scrolls.
- **Room subscriptions**: When a user opens a room, subscribe with `timeline_limit: 50` to get full conversation history. Independent of list visibility.
- **`pos` token**: Opaque pagination token. Each response includes one; send it back in the next request for incremental updates. If the server doesn't recognize it, start over.
- **`bump_stamp`**: Server-provided timestamp of last "interesting" activity. Client sorts rooms locally using this.
- **Sticky params**: Request fields persist across requests. Only send deltas.
- **Extensions**: Opt-in delivery of E2EE keys, to-device messages, typing, receipts, account data.

---

## Architecture

### Two Sync Paths (v3 Fallback)

Gloam should support both sync protocols and detect which the server supports:

```
┌─────────────────────────────────────────┐
│              SyncService                │
│  (abstract — protocol-agnostic)         │
│                                         │
│  Stream<RoomListUpdate> get roomList    │
│  Stream<TimelineUpdate> get timeline    │
│  void setVisibleRange(int start, end)   │
│  void subscribeToRoom(String roomId)    │
│  void unsubscribeFromRoom(String roomId)│
└────────────┬───────────┬────────────────┘
             │           │
    ┌────────┴───┐  ┌────┴────────┐
    │ V3Sync     │  │ V4Sliding   │
    │ Service    │  │ SyncService │
    │ (current)  │  │ (new)       │
    └────────────┘  └─────────────┘
```

Detection: On login, check if the server advertises Sliding Sync support (try `POST /v4/sync` — if 404/unimplemented, fall back to v3).

### File Layout

```
lib/services/sync/
├── sync_service.dart              # Abstract interface
├── v3_sync_service.dart           # Traditional /sync (current behavior, extracted)
├── v4_sliding_sync_service.dart   # Sliding Sync implementation
├── sliding_sync_models.dart       # Request/response models
└── sliding_sync_extensions.dart   # E2EE, to-device, typing, receipts
```

---

## Implementation Plan

### Phase 1: Sliding Sync Core (Week 1-2)

**Goal:** Room list loads instantly via Sliding Sync. Timeline still uses existing SDK.

#### Task 1.1: Sliding Sync HTTP Layer

**File:** `lib/services/sync/v4_sliding_sync_service.dart`

Raw HTTP client for the `/v4/sync` endpoint:

```dart
class SlidingSyncService {
  final Client _client;
  final Dio _dio;
  String? _pos;          // position token
  String _connId;        // connection identifier
  bool _running = false;

  /// Start the sync loop.
  Future<void> start() async {
    _running = true;
    while (_running) {
      final response = await _sendRequest();
      _pos = response.pos;
      _processResponse(response);
    }
  }

  /// Build and send a /v4/sync request.
  Future<SlidingSyncResponse> _sendRequest() async {
    final body = _buildRequestBody();
    final resp = await _dio.post(
      '${_client.homeserver}/_matrix/client/v4/sync',
      data: body,
      options: Options(
        headers: {'Authorization': 'Bearer ${_client.accessToken}'},
        receiveTimeout: Duration(milliseconds: _timeout + 5000),
      ),
    );

    if (resp.statusCode == 400 && resp.data['errcode'] == 'M_UNKNOWN_POS') {
      _pos = null; // Reset — server lost our position
      return _sendRequest(); // Retry without pos
    }

    return SlidingSyncResponse.fromJson(resp.data);
  }
}
```

#### Task 1.2: Request/Response Models

**File:** `lib/services/sync/sliding_sync_models.dart`

Dart models for the Sliding Sync JSON format:

```dart
class SlidingSyncRequest {
  final String? pos;
  final String connId;
  final int timeout;
  final Map<String, SlidingSyncList> lists;
  final Map<String, RoomSubscription> roomSubscriptions;
  final SlidingSyncExtensions extensions;
}

class SlidingSyncList {
  final List<List<int>> ranges;  // e.g., [[0, 19]]
  final int timelineLimit;
  final List<List<String>> requiredState;
  final SlidingSyncFilters? filters;
  final bool includeHeroes;
}

class SlidingSyncResponse {
  final String pos;
  final Map<String, SlidingSyncListResponse> lists;
  final Map<String, SlidingSyncRoom> rooms;
  final SlidingSyncExtensionResponse? extensions;
}

class SlidingSyncRoom {
  final String? name;
  final String? avatar;
  final bool initial;
  final int? notificationCount;
  final int? highlightCount;
  final int? joinedCount;
  final int? invitedCount;
  final int? bumpStamp;
  final List<MatrixEvent>? timeline;
  final List<MatrixEvent>? requiredState;
  final bool? limited;
  final String? prevBatch;
}
```

#### Task 1.3: Room List Integration

Feed Sliding Sync room data into Gloam's existing `RoomListItem` model. The `roomListProvider` currently builds from `client.rooms` — add an alternative path that builds from Sliding Sync responses:

```dart
// When Sliding Sync is active, the room list comes from
// the v4/sync response, not from client.rooms
final slidingSyncRoomListProvider = StreamProvider<List<RoomListItem>>((ref) {
  final syncService = ref.watch(slidingSyncServiceProvider);
  return syncService.roomListStream.map((rooms) {
    return rooms.map((r) => RoomListItem(
      roomId: r.roomId,
      displayName: r.name ?? r.roomId,
      avatarUrl: r.avatar != null ? Uri.parse(r.avatar!) : null,
      lastMessagePreview: r.latestMessage?.body,
      lastMessageTimestamp: r.bumpStamp != null
          ? DateTime.fromMillisecondsSinceEpoch(r.bumpStamp!)
          : null,
      unreadCount: r.notificationCount ?? 0,
      // ... etc
    )).toList();
  });
});
```

#### Task 1.4: Visible Range Tracking

Connect the room list's scroll position to the Sliding Sync range:

```dart
// In RoomListPanel, when the user scrolls:
void _onScroll() {
  final firstVisible = _scrollController.position.pixels ~/ itemHeight;
  final lastVisible = firstVisible + visibleItemCount;
  ref.read(slidingSyncServiceProvider)
    .setVisibleRange(firstVisible, lastVisible + 10); // +10 buffer
}
```

### Phase 2: Room Subscriptions + Timeline (Week 2-3)

**Goal:** Opening a room instantly loads messages via room subscription.

#### Task 2.1: Room Subscription Management

When the user opens a room, add a room subscription:

```dart
void subscribeToRoom(String roomId) {
  _roomSubscriptions[roomId] = RoomSubscription(
    timelineLimit: 50,
    requiredState: [['m.room.member', '*']],
  );
  _sendRequest(); // Trigger immediate sync with new subscription
}

void unsubscribeFromRoom(String roomId) {
  _roomSubscriptions.remove(roomId);
}
```

#### Task 2.2: Timeline from Sliding Sync

When a room subscription response arrives with `timeline` events, feed them into the existing `TimelineNotifier`:

```dart
void _processRoomData(String roomId, SlidingSyncRoom room) {
  if (room.timeline != null && room.timeline!.isNotEmpty) {
    // Inject timeline events into the SDK's room model
    // so existing timeline_provider.dart picks them up
    final sdkRoom = _client.getRoomById(roomId);
    if (sdkRoom != null) {
      // Use the SDK's internal event insertion
      for (final event in room.timeline!) {
        sdkRoom.setState(event); // or inject via fake sync update
      }
    }
  }
}
```

The challenge here is bridging Sliding Sync responses into the SDK's existing `Room` and `Timeline` objects. Options:

**Option A: Fake sync injection** — Construct a `SyncUpdate` object from the Sliding Sync response and feed it through `client.handleSync()`. This is what the conference talk prototype did. Pros: reuses all existing SDK processing (decryption, state resolution). Cons: hacky, may cause side effects.

**Option B: Parallel room model** — Build a separate `SlidingSyncRoom` model that the UI reads directly, bypassing the SDK's `Room` class for rooms discovered via Sliding Sync. Pros: clean separation. Cons: duplicates room state management.

**Recommended: Option A** — fake sync injection is the pragmatic path. The SDK's sync handler already handles all the complexity (decryption, state resolution, database persistence). Constructing a synthetic `SyncUpdate` from Sliding Sync data and feeding it through the existing pipeline is less code and more reliable than reimplementing all of that.

#### Task 2.3: Backfill via `/messages`

When the response has `limited: true`, use the `prev_batch` token with the standard `/messages` endpoint to backfill older messages. This is the same pagination mechanism the timeline provider already uses.

### Phase 3: Extensions + E2EE (Week 3)

**Goal:** E2EE, typing indicators, receipts, and account data work over Sliding Sync.

#### Task 3.1: E2EE Extension

**Critical** — without this, encrypted rooms won't work:

```dart
extensions: {
  'e2ee': {'enabled': true},
  'to_device': {
    'enabled': true,
    'since': _toDeviceSince, // independent token, persisted
  },
}
```

Response delivers:
- `device_lists.changed` / `device_lists.left` — device tracking
- `device_one_time_keys_count` — OTK replenishment
- `device_unused_fallback_key_types` — fallback key management
- To-device events (key shares, verification)

Feed these into the SDK's crypto module via the existing `client.encryption` hooks.

#### Task 3.2: Typing + Receipts Extensions

```dart
extensions: {
  'typing': {'enabled': true},
  'receipts': {'enabled': true},
}
```

Scoped to rooms the server knows the client cares about (list + subscriptions). Much more efficient than v3 sync which delivers these for ALL rooms.

#### Task 3.3: Account Data Extension

```dart
extensions: {
  'account_data': {'enabled': true},
}
```

Delivers `m.direct` (DM mappings), `m.tag` (room tags), `m.push_rules`, and per-room account data. Essential for correct DM detection and notification settings.

### Phase 4: Polish + Migration (Week 4)

#### Task 4.1: Protocol Detection

On login, detect Sliding Sync support:

```dart
Future<bool> serverSupportsSlidingSync() async {
  try {
    final resp = await _dio.post(
      '${client.homeserver}/_matrix/client/v4/sync',
      data: {'lists': {}, 'timeout': 0},
      options: Options(headers: authHeaders),
    );
    return resp.statusCode == 200;
  } catch (_) {
    return false;
  }
}
```

If supported → use Sliding Sync. If not → fall back to v3 sync (current behavior).

#### Task 4.2: Smooth Transition

- Persist the `pos` token across app restarts for instant resume
- Cache room list data locally so the UI renders immediately on cold start
- Background-load rooms beyond the visible window for search/filter

#### Task 4.3: Connection Error Handling

- `M_UNKNOWN_POS` → reset `pos`, restart from scratch
- Network disconnect → retry with exponential backoff
- Server downgrade (returns 404 on v4) → fall back to v3

#### Task 4.4: Remove Zero-State Workaround

Once Sliding Sync is active, the "Joining #room / Syncing room state" zero-state becomes unnecessary — room subscriptions deliver timeline events immediately regardless of federation state. The zero-state can be simplified to a loading spinner.

---

## Dependencies

| Dependency | Status | Risk |
|-----------|--------|------|
| Synapse 1.114+ with MSC4186 | nerdforge.xyz is likely up to date | Low — check version |
| `package:matrix` has no Sliding Sync | Must build custom | High — largest technical lift |
| Dio HTTP client | Already in pubspec | None |
| E2EE integration with custom sync | Needs careful bridge to SDK crypto | Medium |

## Success Criteria

- [ ] Initial room list renders in < 1 second after login (vs current multi-second wait)
- [ ] Opening a newly-joined federated room shows messages immediately (no zero-state)
- [ ] E2EE works correctly (key sharing, decryption, verification)
- [ ] Typing indicators and read receipts work
- [ ] Scroll-based range shifting loads rooms on demand
- [ ] Falls back to v3 sync on servers without Sliding Sync support
- [ ] `pos` token persisted — app resume is instant
- [ ] No regression on existing functionality

## Risk Register

| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|------------|
| SDK integration is harder than expected | High | High | Start with fake sync injection; fall back to parallel model if needed |
| E2EE breaks with custom sync | Medium | Critical | Test encrypted rooms extensively; keep v3 fallback for E2EE-only |
| Server version too old | Low | Medium | Protocol detection with graceful fallback |
| Edge cases in room list diffing | Medium | Medium | Compare against Element X behavior for reference |

## Open Questions

1. **Should we contribute Sliding Sync to the Dart matrix SDK upstream?** If we build this well, Famedly (the SDK maintainers) might accept a PR. This would benefit the entire Dart Matrix ecosystem.

2. **Fake sync injection vs parallel model?** The conference talk used fake sync injection. Element X uses a completely separate Rust-native sync engine. For Gloam, fake sync injection is pragmatic for v1, but a cleaner separation might be better long-term.

3. **When to start?** This is a 3-4 week project that touches the core sync engine. It should be done before or alongside multi-account support, since multi-account with v3 sync would be very slow (two full sync streams).

---

## Change History

- 2026-03-26: Initial comprehensive plan based on MSC4186 research, SDK analysis, and Element X reference implementation study.
