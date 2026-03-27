# FEAT-008: Server & Room Browser — Join Spaces and Public Rooms

**Requested:** 2026-03-26
**Status:** Proposed
**Priority:** High
**Effort:** Medium (3–5 days)

---

## Description

The (+) button in the space rail currently does nothing. It should open a browser that lets users discover and join public Matrix rooms and spaces — both on their own homeserver and on popular federated servers. This is how Gloam's social surface area grows beyond private DMs and manually-created rooms.

## User Story

As a Gloam user, I want to browse and search for public rooms and spaces on my homeserver and other Matrix servers, so I can discover communities and join conversations without needing a direct invite link.

---

## Current State

| Element | Location | Current Behavior |
|---------|----------|-----------------|
| Space rail (+) button | `lib/app/shell/space_rail.dart:157` | `onTap: () {}` — empty handler |
| Room list (+) button | `lib/app/shell/room_list_panel.dart` header | Opens `showCreateRoomDialog()` — creates new rooms only |
| Quick switcher (Cmd+K) | `lib/app/shell/quick_switcher.dart` | Searches joined rooms only |

## Matrix APIs Available

The Dart `matrix` SDK (v0.40.2) has everything we need built in:

| Method | Purpose |
|--------|---------|
| `client.queryPublicRooms(server, filter, limit, since)` | Search/browse public room directory on any server |
| `client.joinRoom(roomIdOrAlias, via: [server])` | Join a room by ID or alias |
| `client.getSpaceHierarchy(roomId, suggestedOnly, limit, maxDepth)` | Browse a space's children without joining |
| `PublicRoomQueryFilter(genericSearchTerm, roomTypes)` | Filter by name/topic text and room type |

Response includes: `name`, `topic`, `avatarUrl`, `numJoinedMembers`, `canonicalAlias`, `roomType`, `worldReadable`, `joinRule`.

---

## UX Design

### The (+) Button Opens a Modal Browser

Tapping (+) in the space rail opens a full-width modal (same pattern as the settings modal) with three tabs:

```
┌────────────────────────────────────────────────────────────────┐
│  Explore                                                   ✕   │
├───────┬──────────┬───────────────────────────────────────────── │
│ Browse │ Spaces  │ Join by Address                             │
├───────┴──────────┴────────────────────────────────────────────┤
│                                                                │
│  Server: [nerdforge.xyz ▾]      🔍 [search rooms...]          │
│                                                                │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │ 🌐 Matrix HQ                           45,231 members   │  │
│  │    The official Matrix community                [Join]   │  │
│  ├──────────────────────────────────────────────────────────┤  │
│  │ 🔒 Rust                                 12,847 members   │  │
│  │    Pair-programming and discussion          [Joined ✓]   │  │
│  ├──────────────────────────────────────────────────────────┤  │
│  │ # Flutter Dev                            8,203 members   │  │
│  │    Flutter framework discussions            [Join]       │  │
│  └──────────────────────────────────────────────────────────┘  │
│                                                                │
│  [Load more...]                                                │
│                                                                │
└────────────────────────────────────────────────────────────────┘
```

### Tab 1: Browse (Public Rooms)

- **Server selector** dropdown at the top — defaults to user's homeserver, with presets for popular servers (matrix.org, gitter.im, mozilla.org, tchncs.de) plus "Enter server address..." option
- **Search bar** — filters by room name/topic via `queryPublicRooms(filter: PublicRoomQueryFilter(genericSearchTerm: ...))`
- **Room list** — scrollable, paginated (20 per page, load more on scroll)
- Each room card shows: avatar, name (or alias), topic preview, member count, join rule icon (public/knock)
- **Join button** — tapping it calls `client.joinRoom(roomId, via: [server])`, button shows spinner then "Joined ✓"
- Already-joined rooms show "Joined ✓" badge (check against `client.rooms`)
- Rooms with `roomType == "m.space"` show a space icon and are also listed in the Spaces tab

### Tab 2: Spaces

- Same as Browse but filtered to `roomTypes: ["m.space"]`
- Tapping a space shows its hierarchy via `client.getSpaceHierarchy(spaceId)` as an expandable tree
- Each child room in the hierarchy has its own Join button
- Joining a space adds it to the space rail immediately

### Tab 3: Join by Address

- A simple text field for entering a room alias (`#room:server.org`) or room ID (`!abc:server.org`)
- "Join" button calls `client.joinRoom(input, via: [extractedServer])`
- Shows result: success → navigate to room, error → show message
- Supports paste of `matrix.to` links (`https://matrix.to/#/#room:server`) — parse and join

### Server Selector Dropdown

```
┌──────────────────────────────────┐
│ ● nerdforge.xyz          (home)  │  ← user's homeserver, always first
│   matrix.org                     │
│   gitter.im                      │
│   mozilla.org                    │
│   tchncs.de                      │
├──────────────────────────────────┤
│   Enter server address...        │  ← opens text input
└──────────────────────────────────┘
```

When the user selects a different server, the room list reloads with `queryPublicRooms(server: selectedServer)`.

---

## Implementation Plan

### File Layout

```
lib/features/explore/
├── presentation/
│   ├── explore_modal.dart              # Modal shell with tabs
│   ├── browse_tab.dart                 # Public room directory browser
│   ├── spaces_tab.dart                 # Space discovery + hierarchy
│   ├── join_by_address_tab.dart        # Manual room/alias entry
│   └── widgets/
│       ├── server_selector.dart        # Server dropdown with presets
│       ├── public_room_tile.dart       # Room card (name, topic, members, join)
│       └── space_hierarchy_tile.dart   # Space child with indent + join
└── providers/
    └── explore_provider.dart           # Room search state, pagination, join actions
```

### Task 1: Explore Provider (State Management)

**File:** `lib/features/explore/providers/explore_provider.dart`

```dart
@riverpod
class ExploreNotifier extends _$ExploreNotifier {
  // State: server, search query, results, pagination, loading
  // Methods:
  //   searchRooms(server, query) → calls client.queryPublicRooms()
  //   loadMore() → paginate with since token
  //   joinRoom(roomId, server) → calls client.joinRoom(via: [server])
  //   browseSpaceHierarchy(spaceId) → calls client.getSpaceHierarchy()
  //   setServer(server) → switch server, reload results
}
```

State model:
```dart
@freezed
class ExploreState with _$ExploreState {
  const factory ExploreState({
    @Default('') String server,           // current server to browse
    @Default('') String searchQuery,
    @Default([]) List<PublicRoomsChunk> rooms,
    String? nextBatch,                    // pagination token
    @Default(false) bool isLoading,
    @Default({}) Set<String> joinedRoomIds,  // for "Joined ✓" badges
    @Default({}) Set<String> joiningRoomIds, // rooms currently being joined
    String? error,
  }) = _ExploreState;
}
```

### Task 2: Explore Modal Shell

**File:** `lib/features/explore/presentation/explore_modal.dart`

- Full-screen modal matching the settings modal pattern
- Three tabs across the top: Browse, Spaces, Join by Address
- Server selector + search bar in the header area
- Tab content area below
- Called from the space rail (+) button: `showExploreModal(context, ref)`

### Task 3: Browse Tab (Public Room Directory)

**File:** `lib/features/explore/presentation/browse_tab.dart`

- Watches `exploreProvider` for room results
- Renders `PublicRoomTile` for each result
- Infinite scroll pagination (detect scroll near bottom → `loadMore()`)
- Search bar debounced at 300ms
- Empty state: "No public rooms found" / "Search for rooms..."
- Error state: "Failed to load rooms from {server}"

### Task 4: Public Room Tile Widget

**File:** `lib/features/explore/presentation/widgets/public_room_tile.dart`

Each tile shows:
- Avatar (from `avatarUrl` MXC URI, or letter fallback from room name)
- Room name (bold) + canonical alias (mono, secondary)
- Topic (max 2 lines, tertiary)
- Member count (right side, mono)
- Room type icon: 🌐 space, # channel, 🔒 knock-only
- **Join button**: "Join" (accent) → spinner while joining → "Joined ✓" (dim)
- If already joined: show "Open" button that navigates to the room

### Task 5: Server Selector

**File:** `lib/features/explore/presentation/widgets/server_selector.dart`

- PopupMenuButton with preset servers + custom entry
- Presets: user's homeserver (labeled "home"), matrix.org, gitter.im, mozilla.org, tchncs.de
- "Enter server address..." option opens a text field inline
- Changing server triggers `exploreNotifier.setServer(newServer)` → reloads results

### Task 6: Spaces Tab

**File:** `lib/features/explore/presentation/spaces_tab.dart`

- Same as browse but with `roomTypes: ["m.space"]` filter
- Tapping a space row expands it to show `getSpaceHierarchy()` children inline
- Space children rendered with indent and their own join buttons

### Task 7: Join by Address Tab

**File:** `lib/features/explore/presentation/join_by_address_tab.dart`

- Text field with placeholder: "#room:server.org or !roomId:server.org"
- Auto-detects and parses `matrix.to` links
- "Join" button → `client.joinRoom(input, via: [parsedServer])`
- Result feedback: success banner → navigate to room, or error message

### Task 8: Wire Up the (+) Button

**File to modify:** `lib/app/shell/space_rail.dart`

Change the add button's `onTap` from `() {}` to `() => showExploreModal(context, ref)`.

Also wire the room list panel's (+) to open the same modal (or keep it as create-room and add an "Explore" option).

---

## Dependencies

| Dependency | Status | Risk |
|-----------|--------|------|
| `client.queryPublicRooms()` | Available in matrix SDK v0.40.2 | Low |
| `client.joinRoom()` | Available | Low |
| `client.getSpaceHierarchy()` | Available | Low |
| Federated directory browsing | Depends on remote server config | Low — graceful error if server doesn't expose directory |

## Success Criteria

- [ ] (+) button in space rail opens the Explore modal
- [ ] Browse tab shows public rooms from user's homeserver by default
- [ ] Server selector allows switching to matrix.org, gitter.im, etc.
- [ ] Search filters rooms by name/topic in real time (debounced)
- [ ] Scrolling to bottom loads next page of results
- [ ] Join button joins the room and updates to "Joined ✓"
- [ ] Already-joined rooms show "Joined ✓" without re-joining
- [ ] Joining a space adds it to the space rail
- [ ] Spaces tab filters to spaces only with expandable hierarchy
- [ ] Join by Address tab accepts aliases, room IDs, and matrix.to links
- [ ] Error states shown for unreachable servers or failed joins
- [ ] Modal dismisses cleanly, room list updates after joins

---

## Change History

- 2026-03-26: Initial feature request and implementation plan
