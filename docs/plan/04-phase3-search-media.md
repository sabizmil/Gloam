# Phase 3: Search & Media

**Weeks 15-18 | Depends on: Phase 2 (Navigation & Organization)**

---

## Objectives

Make Gloam's content findable and its media experience rich. Client-side encrypted search is the headline feature — no other Matrix client ships this well. Voice messages, link previews, progressive image loading, and a media gallery round out the media story. By the end, users should never feel like encrypted rooms are second-class citizens.

## Success Criteria

- Full-text search returns results from encrypted rooms within 500ms for a local index of 100K+ messages
- Search filters (from:/in:/has:/date:) work correctly and are discoverable via autocomplete
- Server-side search supplements client-side results for unencrypted rooms with merged, deduplicated results
- Link previews render inline for Open Graph URLs; rich embeds for YouTube, Twitter/X, and GitHub
- Voice messages record, encode to Opus, encrypt, upload, and play back with waveform visualization and scrubbing
- Media gallery shows all media in a room in a grid, filterable by type, with smooth pagination
- Images load progressively: blurhash placeholder visible in <50ms, thumbnail in <500ms, full resolution on demand
- Search index size stays under 10% of the total message database size
- No perceptible UI jank during background indexing

---

## Task Breakdown

### 1. Client-Side Encrypted Search

**Priority: High | Estimate: 10-12 days**

The single most impactful feature in this phase. Every Matrix client either has no encrypted search or does it poorly. This is a differentiator.

#### Architecture

```
Message decrypted (live sync or backfill)
  --> Extract plaintext body, sender, room_id, event_id, timestamp, event type
  --> Tokenization pipeline:
      1. Strip HTML/Markdown formatting
      2. Unicode normalization (NFC)
      3. Lowercase
      4. Split on whitespace + punctuation
      5. Remove stop words (configurable per locale)
      6. Optional: stemming (Porter stemmer for English)
  --> Insert into SQLite FTS5 virtual table
  --> Index stored in SQLCipher-encrypted database file

User searches
  --> Parse query (extract filters, remaining text)
  --> FTS5 MATCH query with BM25 ranking
  --> Apply recency boost: final_score = bm25_score + (recency_weight / days_since_message)
  --> Return event_ids with snippet context
  --> UI fetches full events from timeline cache for display
```

#### Database Schema

```sql
-- FTS5 virtual table (inside SQLCipher database)
CREATE VIRTUAL TABLE message_index USING fts5(
  body,                    -- message plaintext content
  sender,                  -- @user:server.tld
  room_id,                 -- !roomid:server.tld
  content='',              -- contentless table (saves space, events stored elsewhere)
  content_rowid='rowid',
  tokenize='unicode61 remove_diacritics 2'
);

-- Metadata table for index management
CREATE TABLE index_meta (
  room_id TEXT PRIMARY KEY,
  last_indexed_event_id TEXT,
  last_indexed_timestamp INTEGER,
  event_count INTEGER DEFAULT 0
);

-- Frecency data for search history
CREATE TABLE search_history (
  query TEXT PRIMARY KEY,
  use_count INTEGER DEFAULT 1,
  last_used_at INTEGER
);
```

#### Encryption at Rest

- Entire search index database encrypted via SQLCipher (AES-256-CBC)
- Key derived from user's recovery key or a random key stored in platform keychain
- SQLCipher via `sqflite_sqlcipher` or `drift` with SQLCipher driver
- Key never written to disk unencrypted

#### Incremental Indexing

- **Live indexing:** Every decrypted message is indexed immediately after decryption (in background isolate)
- **Backfill indexing:** When a room is opened for the first time, backfill messages and index them in batches of 100
- **Idle indexing:** When app is idle (no user interaction for 30s), index unindexed rooms in background
- **Progress tracking:** `index_meta` table tracks last indexed event per room to avoid re-indexing
- **Isolate architecture:** Indexing runs in a separate Dart isolate to avoid blocking UI thread

#### Index Size Management

- **Contentless FTS5:** Store only the index, not the full message text (events already in timeline cache)
- **Target:** Index size < 10% of message database size
- **Pruning:** Optional — user can configure max index age (e.g., 1 year). Default: no pruning.
- **Compression:** SQLCipher pages compress well; no additional compression needed
- **Monitoring:** Track index size in settings, show "Search index: 45MB covering 150K messages"

#### Ranking: BM25 + Recency

```dart
double rankResult(double bm25Score, DateTime messageTimestamp) {
  final daysSince = DateTime.now().difference(messageTimestamp).inDays;
  final recencyBoost = 10.0 / (1.0 + daysSince.toDouble());
  return bm25Score + recencyBoost;
}
```

- BM25 is FTS5's built-in ranking function (handles term frequency, inverse document frequency, field length normalization)
- Recency boost ensures recent messages surface above old matches with similar relevance
- Weight is tunable — start with recency_weight=10.0, adjust based on user testing

#### Subtasks

- [ ] Set up SQLCipher-encrypted database for search index (separate from main app database)
- [ ] Create FTS5 virtual table with unicode61 tokenizer
- [ ] Build tokenization pipeline (strip formatting, normalize, lowercase, split)
- [ ] Implement indexing service: intercept decrypted messages, insert into FTS5
- [ ] Implement incremental backfill indexing with batch processing
- [ ] Background isolate for indexing operations (no UI thread blocking)
- [ ] Build search query parser (extract filter tokens, pass remaining text to FTS5)
- [ ] Implement BM25 + recency ranking
- [ ] Index metadata tracking (last indexed event per room)
- [ ] Index size monitoring and optional pruning
- [ ] Search history storage with frecency ranking
- [ ] Performance benchmarks: 100K messages, <500ms query time

#### Key Decision: SQLCipher vs Custom Encryption

**Chosen approach:** SQLCipher for full-database encryption of the search index.

**Why not encrypt individual FTS entries?** FTS5 needs to read the entire index structure for ranking. Encrypting individual entries would require decrypting the entire index on every query, negating the point of using FTS5. SQLCipher encrypts at the page level, transparent to SQLite — FTS5 works unmodified.

**Why not use the main app database?** Isolating the search index lets us use a separate isolate for all indexing operations without contending for the main database lock. It also allows nuking the index without affecting app state.

---

### 2. Server-Side Search Supplement

**Priority: Low | Estimate: 2-3 days | Depends on: Client-Side Search, Search UI**

For unencrypted rooms, the homeserver can search messages the client hasn't seen yet (e.g., history before the client was installed).

#### Implementation

- Use Matrix client-server API: `POST /_matrix/client/v3/search` with `search_categories.room_events`
- Only for rooms where `encryption` state event is absent (unencrypted rooms)
- Fire server-side search in parallel with client-side search
- Merge results: deduplicate by `event_id`, prefer client-side result if both exist (it has the decrypted content)
- Clearly indicate in UI which results come from server vs local index (subtle label, not prominent)

#### Result Merging

```
Client-side results: [A, B, C, D]
Server-side results: [B, E, F, G]  (B is duplicate)

Merged: [A, B, C, D, E, F, G]
  - Dedupe by event_id
  - Re-rank merged set by combined score
  - Client-side results get a small boost (user is more likely looking for encrypted content)
```

#### Subtasks

- [ ] Implement homeserver search API call via matrix_dart_sdk
- [ ] Detect encrypted vs unencrypted rooms to decide which search path to use
- [ ] Merge and deduplicate results from both sources
- [ ] Display source indicator on results (local vs server)
- [ ] Handle homeservers that don't support search (graceful degradation)

---

### 3. Search UI

**Priority: Medium | Estimate: 5-6 days | Depends on: Client-Side Search**

A dedicated search view that makes finding messages fast and intuitive.

#### Implementation

**Layout:** Full-width view (replaces chat area on desktop, pushed screen on mobile).

**Search bar:**
- Large text input at top, auto-focused on entry
- Placeholder: "Search messages..."
- Clear button (X) on right
- As user types, results appear below in real-time (debounce 150ms)

**Filter pills:**
- Below the search bar, horizontal scrollable row of active filters
- Each pill shows the filter and its value, with an X to remove
- Tapping a filter pill makes it editable

**Filter syntax (typed in search bar):**

| Filter | Syntax | Behavior |
|--------|--------|----------|
| Sender | `from:@alice:matrix.org` or `from:alice` | Filter by message sender |
| Room | `in:#room:matrix.org` or `in:Room Name` | Filter by room |
| Has attachment | `has:file`, `has:image`, `has:link`, `has:video` | Filter by content type |
| Date range | `date:2026-01-01..2026-03-01` or `date:last-week` | Filter by timestamp |

**Autocomplete:**
- Typing `from:` triggers autocomplete dropdown with known senders
- Typing `in:` triggers autocomplete with room names
- Typing `has:` shows available content type options
- Autocomplete uses frecency (recently searched senders/rooms rank higher)

**Result display:**
- Each result shows: sender avatar, sender name, room name, timestamp, message snippet with highlighted match terms
- Click/tap a result → navigate to that message in the room timeline, highlighted
- "Show in context" button loads surrounding messages

**Result navigation:**
- Arrow up/down moves between results
- Enter navigates to selected result
- Cmd/Ctrl+Enter opens result in new window (desktop only, future)

**Search history:**
- Below search bar when empty, show recent searches (last 10)
- Each history item shows the query and how many results it returned
- Click to re-run search
- Clear all history option

**Empty states:**
- No query: show recent searches or "Search across all your messages"
- No results: "No messages found" with suggestions (check spelling, try different filters)
- Index building: "Search index is still building... X% complete. Results may be incomplete."

#### Subtasks

- [ ] Build search view layout (full-width, search bar, filter pills, results list)
- [ ] Implement filter parser (extract from:/in:/has:/date: tokens from query string)
- [ ] Autocomplete dropdowns for filter values (senders, rooms, content types)
- [ ] Real-time result rendering with debounced search (150ms)
- [ ] Result item widget (avatar, sender, room, timestamp, highlighted snippet)
- [ ] Navigate to message in room on result tap (deep link to event_id)
- [ ] Search history storage and display
- [ ] Empty states and index-building progress indicator
- [ ] Keyboard navigation (arrows + Enter)
- [ ] Mobile: pushed screen with back navigation. Desktop: replaces chat area.

---

### 4. Link Preview Unfurling

**Priority: Medium | Estimate: 4-5 days | Depends on: Phase 1 message rendering**

Inline previews for URLs shared in messages. Makes link-heavy conversations much more scannable.

#### Implementation

**Open Graph extraction:**
- When a message contains a URL, fetch the page's Open Graph metadata (`og:title`, `og:description`, `og:image`, `og:site_name`)
- Use the homeserver's URL preview API (`GET /_matrix/media/v3/preview_url`) when available
- Fallback: client-side fetch with a HEAD request to check content type, then GET for HTML parsing
- Respect robots.txt / `X-Robots-Tag: noindex` — don't preview if site opts out

**Preview card layout:**
```
┌──────────────────────────────────┐
│ ┌──────┐  Site Name              │
│ │      │  Title of Page          │
│ │ img  │  Description text that  │
│ │      │  can wrap to 2-3 lines  │
│ └──────┘  domain.com             │
└──────────────────────────────────┘
```
- Thumbnail on left (80x80), text on right
- If no image, full-width text layout
- Domain name shown in muted text at bottom
- Click preview card → open URL in system browser

**Rich embeds for specific sites:**

| Site | Enhancement |
|------|-------------|
| YouTube | Video thumbnail (large), title, channel name, duration badge. Tap → open in YouTube app or in-app player (future) |
| Twitter/X | Tweet content rendered inline (text, author, timestamp). Profile pic. Embedded images if present. |
| GitHub | Repo: stars, description, language. PR/Issue: title, status, labels. |
| Spotify | Album art, track/album/playlist name, artist |

**Caching:**
- Cache preview metadata in local SQLite: `url_hash`, `title`, `description`, `image_url`, `fetched_at`
- TTL: 7 days, then re-fetch on next view
- Cache preview images in the standard media cache (LRU)

**Security:**
- Never auto-load previews for URLs from unverified senders in encrypted rooms (configurable)
- Sanitize all HTML in descriptions (strip scripts, only allow basic formatting)
- Rate-limit preview fetches (max 5 concurrent, max 20/minute)
- Respect content-type — don't try to preview non-HTML URLs (PDFs, binaries)
- URL preview can leak IP to third-party servers — document this in privacy settings, allow disabling

#### Subtasks

- [ ] Implement URL detection in message content (regex for http/https URLs)
- [ ] Homeserver URL preview API integration (`/_matrix/media/v3/preview_url`)
- [ ] Client-side Open Graph fallback parser
- [ ] Preview card widget (thumbnail, title, description, domain)
- [ ] Rich embed implementations for YouTube, Twitter/X, GitHub
- [ ] Preview metadata caching in SQLite with TTL
- [ ] Preview image caching in media cache
- [ ] Security: sanitization, rate limiting, privacy toggle in settings
- [ ] Loading state (shimmer placeholder while fetching preview)

---

### 5. Voice Messages

**Priority: Medium | Estimate: 5-6 days | Depends on: Phase 1 message composer, E2EE media upload**

Record, send, and play back voice messages with waveform visualization.

#### Implementation

**Recording:**
- Long-press mic button in composer to start recording (or tap to toggle on mobile)
- Waveform visualization renders in real-time as audio is captured
- Timer showing recording duration
- Slide left to cancel (mobile), press Escape or click X (desktop)
- Release / tap stop to finish recording
- Preview before sending: play back with waveform, re-record or send

**Audio encoding:**
- Record via `record` package (cross-platform audio recording)
- Encode to Opus in OGG container (Matrix standard for voice messages)
- Target bitrate: 24kbps (good quality for speech, small file size)
- Max duration: 5 minutes (configurable)
- Generate waveform data (amplitude samples) during recording for visualization

**Upload (E2EE):**
- Encrypt audio file client-side using Matrix's encrypted attachment protocol (AES-CTR + SHA-256)
- Upload encrypted blob to homeserver media repo
- Send `m.audio` event with `m.voice` metadata (MSC3245):
  - `duration` in milliseconds
  - `waveform` array (amplitude samples, 0-1024 range, ~100 samples)
  - `mimetype: audio/ogg; codecs=opus`
  - Encrypted file keys in event content

**Playback:**
- Download encrypted audio → decrypt → play via `just_audio` or `audioplayers`
- Waveform visualization (from event metadata) with playback progress indicator
- Scrubbing: tap/drag on waveform to seek
- Playback speed control: 1x, 1.5x, 2x
- Continue playback when navigating away from room (audio session management)
- Show playback state on the message bubble: play/pause button, progress bar, duration

**Waveform rendering:**
- Custom painter (`CustomPaint`) drawing amplitude bars
- During recording: live amplitude samples from microphone
- During playback: bars from event metadata, progress fill color
- 60fps animation during playback progress

#### Subtasks

- [ ] Microphone permission handling (iOS, Android, macOS, Linux — Windows auto-grants)
- [ ] Audio recording with `record` package, real-time amplitude capture
- [ ] Opus encoding in OGG container
- [ ] Waveform `CustomPaint` widget (recording + playback modes)
- [ ] Recording UI in composer (long-press/tap, timer, cancel gesture, preview)
- [ ] E2EE audio upload (encrypt → upload → send `m.audio` + `m.voice` event)
- [ ] E2EE audio download and decryption
- [ ] Playback with scrubbing and speed control via `just_audio`
- [ ] Audio session management (background playback, interruption handling)
- [ ] Playback state on message bubble (play/pause, progress, duration)

---

### 6. Media Gallery View

**Priority: Medium | Estimate: 4-5 days | Depends on: Phase 1 media display, progressive image loading**

A grid view of all media shared in a room. Essential for rooms with heavy image/file sharing.

#### Implementation

**Access:** Button in room header ("Media") or from room info panel.

**Layout:**
- Grid view with responsive column count (3 columns phone, 4-5 tablet, 6+ desktop)
- Square thumbnails with aspect-fill cropping
- Video thumbnails show a play button overlay and duration badge
- File items show file icon + name + size

**Type filters (horizontal tab bar at top):**

| Filter | Shows |
|--------|-------|
| All | Everything |
| Images | `m.image` events |
| Videos | `m.video` events |
| Files | `m.file` events |
| Links | Messages containing URLs |
| Audio | `m.audio` events including voice messages |

**Full-screen viewer:**
- Tap image → full-screen viewer with pinch-to-zoom
- Swipe left/right to navigate between media in the gallery
- Share button, download button, "Go to message" button
- Double-tap to zoom to 2x
- Video: inline playback with controls

**Pagination:**
- Load media in pages of 50 items
- Use Matrix's `/messages` API with filter for media events
- Infinite scroll — load more when user reaches bottom
- Show loading indicator during pagination
- Cache loaded media metadata locally for instant re-display

**Encrypted media:**
- Same decrypt pipeline as inline message media
- Thumbnails may be unencrypted (Matrix spec allows unencrypted thumbnails for encrypted media)
- Full-resolution images always decrypted on demand

#### Subtasks

- [ ] Build media gallery grid widget with responsive column count
- [ ] Fetch media events from room timeline (paginated, filtered by event type)
- [ ] Type filter tab bar
- [ ] Square thumbnail rendering with aspect-fill crop
- [ ] Full-screen image viewer with pinch-to-zoom and swipe navigation
- [ ] Video playback in viewer
- [ ] "Go to message" navigation from gallery item to timeline
- [ ] Share and download actions
- [ ] Pagination with infinite scroll
- [ ] Loading and empty states

---

### 7. Progressive Image Loading

**Priority: Medium | Estimate: 4-5 days | Depends on: Phase 1 media display**

Images should never pop in from nothing. The progression: solid color → blurhash → thumbnail → full resolution. This is what makes a chat app feel polished.

#### Implementation

**Loading progression:**

```
1. Instant (0ms):     Solid color placeholder (dominant color from blurhash if available)
2. Immediate (<50ms): Blurhash decode → blurred placeholder (20x20 decoded, scaled up)
3. Fast (<500ms):     Thumbnail from homeserver (max 320x240)
4. On demand:         Full resolution (when user scrolls to image or taps to enlarge)
```

**Blurhash:**
- Matrix events include `info.blurhash` field (if sender's client supports it)
- Decode blurhash string to small pixel grid using `blurhash_dart`
- Scale up with bilinear interpolation via `CustomPaint` or `Image` widget
- If no blurhash in event, use a grey placeholder with shimmer animation

**Thumbnail fetching:**
- Request thumbnail from homeserver: `GET /_matrix/media/v3/thumbnail/{serverName}/{mediaId}?width=320&height=240&method=scale`
- Use authenticated media endpoint (Matrix v1.11+)
- For encrypted media: thumbnails may be separately encrypted or unencrypted (depends on sender client)
- If thumbnail unavailable, skip to full resolution

**Full resolution loading:**
- Triggered when image is in viewport AND thumbnail has loaded
- Or triggered explicitly by user tap (tap thumbnail → load full res)
- For very large images (>2MB), only load full res on explicit tap
- Download → decrypt (if E2EE) → decode → display with fade-in transition (200ms)

**Encrypted media pipeline:**

```
Encrypted image in event
  --> Extract file URL, key, IV, hash from event content
  --> Download encrypted blob from homeserver (authenticated media endpoint)
  --> Decrypt using AES-CTR with the key/IV from the event
  --> Verify SHA-256 hash
  --> Decode image bytes (JPEG/PNG/WebP)
  --> Cache decrypted image in memory (LRU) and encrypted blob on disk
```

**Caching strategy:**

| Cache layer | Storage | Eviction | Contents |
|-------------|---------|----------|----------|
| Memory (L1) | RAM, `ImageCache` | LRU, max 100MB | Decoded image pixels (ready to render) |
| Disk (L2) | App cache directory | LRU, max 500MB | Encrypted blobs (re-decryptable) or plain thumbnails |
| Thumbnail (L3) | Disk, separate dir | LRU, max 100MB | Thumbnails only (smaller, kept longer) |

**LRU cache implementation:**
- Use `CacheManager` (from `flutter_cache_manager`) for disk cache with custom max size
- Memory cache via Flutter's built-in `ImageCache` with increased size limit
- Cache key: `mxc_uri + size_variant` (thumbnail vs full)
- Encrypted media: cache the encrypted blob on disk (saves re-download), decrypt on read into memory cache

**Lazy loading:**
- Only fetch images within the viewport + 2 screens of buffer (above and below)
- Use `VisibilityDetector` or scroll position listener to determine which images are near-visible
- Cancel in-flight image requests when user scrolls past rapidly
- Priority queue: visible images load first, buffered images load after

#### Subtasks

- [ ] Blurhash decoding and rendering widget (`blurhash_dart` integration)
- [ ] Thumbnail fetch via authenticated media API
- [ ] Full resolution fetch with E2EE decryption pipeline
- [ ] Three-stage loading widget (blurhash → thumbnail → full) with crossfade transitions
- [ ] Encrypted media download/decrypt/verify pipeline
- [ ] LRU memory cache configuration (increase `ImageCache` limits)
- [ ] LRU disk cache with `flutter_cache_manager` (separate thumbnail and full-res caches)
- [ ] Lazy loading: viewport-aware image fetching with request cancellation
- [ ] Handle missing blurhash gracefully (shimmer placeholder)
- [ ] Cache size monitoring in settings ("Media cache: 234MB — Clear cache")

---

## Dependencies

```
Client-Side Encrypted Search
  ├── Phase 1: E2EE (messages must be decryptable to index)
  ├── Phase 2: Room List (search scoped to rooms/spaces)
  └── SQLCipher setup (new dependency)

Server-Side Search Supplement
  ├── Client-Side Search (merge logic)
  └── Search UI (display layer)

Search UI
  ├── Client-Side Search (query engine)
  ├── Phase 2: Navigation (integrates into layout shell)
  └── go_router (deep link to search results)

Link Preview Unfurling
  ├── Phase 1: Message rendering (embedded in message bubbles)
  └── Homeserver media API (URL preview endpoint)

Voice Messages
  ├── Phase 1: Message composer (recording trigger)
  ├── Phase 1: E2EE media upload (encrypted audio)
  └── New packages: record, just_audio

Media Gallery
  ├── Progressive Image Loading (thumbnail/full-res pipeline)
  ├── Phase 1: Media display (reuse viewer components)
  └── Phase 2: Room info panel (gallery access point)

Progressive Image Loading
  ├── Phase 1: Message rendering (inline images)
  ├── Authenticated media API
  └── New package: blurhash_dart
```

## New Dependencies Introduced

| Package | Purpose | Notes |
|---------|---------|-------|
| `sqflite_sqlcipher` or SQLCipher driver for `drift` | Encrypted search index database | Check Flutter compatibility on all 5 platforms |
| `blurhash_dart` | Decode blurhash strings to placeholder images | Lightweight, pure Dart |
| `record` | Cross-platform audio recording | Supports iOS, Android, macOS, Windows, Linux |
| `just_audio` | Audio playback with seeking and speed control | Well-maintained, cross-platform |
| `flutter_cache_manager` | LRU disk cache for media | If not already added in Phase 1 |

## Key Decisions Summary

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Search database | Separate SQLCipher database, not main app DB | Isolate indexing to background isolate without lock contention |
| FTS engine | SQLite FTS5 with unicode61 tokenizer | Built into SQLite, proven, supports BM25 ranking natively |
| Encryption at rest | SQLCipher (full-database AES-256) | Transparent to FTS5, no per-entry encryption overhead |
| Indexing isolation | Dart isolate for all indexing operations | UI thread never blocked by index writes |
| Ranking algorithm | BM25 (FTS5 native) + recency boost | BM25 handles relevance; recency boost surfaces recent results |
| Audio codec | Opus in OGG container | Matrix standard (MSC3245), excellent compression for speech |
| Image loading | Blurhash --> thumbnail --> full resolution | Three-stage progression prevents blank spaces and pop-in |
| Media cache | LRU with separate thumbnail and full-res tiers | Thumbnails have longer retention; full-res evicted sooner |
| URL preview source | Homeserver API primary, client-side fallback | Homeserver API avoids leaking user IP to third-party sites |

## Definition of Done

Phase 3 is complete when:

1. **Encrypted search works.** A user can search across all their encrypted rooms and get relevant results in <500ms. The index builds incrementally in the background without affecting UI performance.
2. **Search filters work.** `from:`, `in:`, `has:`, and `date:` filters narrow results correctly. Autocomplete helps users discover filters.
3. **Server-side search supplements.** Unencrypted rooms return results from server history the client hasn't seen. Results are merged and deduplicated.
4. **Link previews are inline.** URLs in messages show Open Graph preview cards. YouTube, Twitter/X, and GitHub get rich embeds. Previews are cached and respect privacy settings.
5. **Voice messages record and play.** Users can record, preview, send, and receive voice messages with waveform visualization. Audio is encrypted end-to-end. Playback supports scrubbing and speed control.
6. **Media gallery is browsable.** Users can view all media in a room as a grid, filtered by type. Full-screen viewer supports zoom and swipe navigation.
7. **Images load progressively.** No blank image spaces. Blurhash appears instantly, thumbnail within 500ms, full resolution on demand. Encrypted media decrypts transparently.
8. **Performance holds.** No regressions from Phase 1/2 targets. Background indexing doesn't cause dropped frames. Media cache size is bounded and user-configurable.
9. **Encrypted rooms are first-class citizens.** There is no feature gap between encrypted and unencrypted rooms from the user's perspective (search works, media loads, voice messages play).
