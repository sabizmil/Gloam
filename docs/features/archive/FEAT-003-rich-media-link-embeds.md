# FEAT-003: Rich Media Link Embeds

**Requested:** 2026-03-26
**Status:** Proposed
**Priority:** P2

---

## Description

When a message contains a URL pointing to a media resource (GIF, image, video) or a known media platform (YouTube, Vimeo, Giphy, Tenor, etc.), the link preview should render the actual media inline rather than showing a text-only URL card. The current `LinkPreview` widget displays every URL identically -- a domain label, truncated URL, and an "open" icon. This is adequate for articles but actively bad for media links where the whole point is visual content.

The feature encompasses three tiers of inline media:

1. **Direct media URLs** (`.gif`, `.jpg`, `.png`, `.webp`, `.mp4`, `.webm`): Render the image/GIF/video directly inside a link preview wrapper. GIFs autoplay. Videos show a thumbnail with a play button; tapping plays inline.

2. **Known platform embeds** (YouTube, Vimeo, Giphy, Tenor, Imgur, Twitter/X): Extract the thumbnail/preview via oEmbed or platform-specific URL patterns. Show the thumbnail with platform branding and a play/open overlay. Clicking the play button on YouTube/Vimeo plays the video inline (via webview or native player). Clicking elsewhere on the card opens the URL externally.

3. **OG-enriched previews** (everything else with og:image): Show the og:image as a thumbnail alongside the title and description. This is an upgrade to the existing link preview, not a new category.

### UX Principles

- **The link preview wrapper persists.** Every embed retains a subtle card frame with the source domain, a small external-link icon in the corner, and a tap-to-open affordance. The media is *inside* the preview, not replacing it. This keeps the URL accessible and avoids the "where did the link go?" problem.
- **Two tap targets.** For videos: tapping the play button plays inline; tapping the domain/external-link area opens in browser. For images/GIFs: the image is the primary content, but the domain bar at the bottom is still tappable to open externally.
- **Autoplay is limited.** GIFs autoplay but are paused when scrolled off-screen. Videos never autoplay -- always require a tap.
- **Size constraints.** Embeds are capped at the same `maxWidth: 400` used by `ImageMessage` to maintain consistent bubble widths. Aspect ratios are preserved.
- **Graceful degradation.** If media fails to load (CORS, 404, network), fall back to the existing text-only link preview. No broken image icons in the timeline.
- **Data consciousness.** On mobile, a user preference could gate autoloading of external media (load on tap vs auto-load). This is a stretch goal, not MVP.

## User Story

As a Gloam user, I want URLs to images, GIFs, and videos to render the actual media content inline in the chat so that I can see visual content without leaving the conversation, while still having access to the original link.

---

## Implementation Approaches

### Approach 1: Extend Existing LinkPreview with Media Type Detection

**Summary:** Add URL pattern matching and media type detection to the current `LinkPreview` widget, rendering different content based on the detected type.

**Technical approach:**
- Add a `_MediaType` enum (`directImage`, `directGif`, `directVideo`, `youtube`, `giphy`, `tenor`, `ogRich`, `plain`) to `link_preview.dart`.
- Parse the URL to detect media type: file extension check for direct media, regex patterns for YouTube/Giphy/etc., and fall back to OG metadata from the homeserver's `/preview_url`.
- Branch the `build()` method to render different widgets per type: `Image.network` for images/GIFs, a thumbnail+play overlay for videos, an oEmbed thumbnail for platform links.
- Keep everything in one widget file with private helper classes.

**Pros:**
- Minimal file changes -- single widget modification
- No new dependencies for basic image/GIF support
- Leverages existing URL regex and homeserver preview endpoint

**Cons:**
- `LinkPreview` becomes a god widget with too many responsibilities
- Hard to test individual media types in isolation
- Video playback requires a player dependency regardless
- Mixing direct-fetch and homeserver-proxy logic in one place is messy

**Effort:** Medium (2-3 days)
**Dependencies:** Video player package for video embeds (media_kit or video_player)

---

### Approach 2: Media Embed Strategy Pattern (Widget Per Type)

**Summary:** Create a `MediaEmbedResolver` service that classifies URLs, and a family of embed widgets (`GifEmbed`, `ImageEmbed`, `VideoEmbed`, `PlatformEmbed`) rendered inside a shared `EmbedCard` wrapper.

**Technical approach:**
- New `media_embed_resolver.dart` service: takes a URL, returns a `MediaEmbedInfo` (type, thumbnailUrl, mediaUrl, platform, title, etc.). Uses a chain-of-responsibility pattern: DirectMediaResolver -> PlatformResolver -> OgMetadataResolver -> FallbackResolver.
- New `embed_card.dart`: the shared wrapper with domain label, external-link icon, and tap-to-open. Accepts a `child` widget for the media content.
- Individual embed widgets: `GifEmbed` (Image.network with autoplay awareness), `ImageEmbed` (cached image with tap-to-fullscreen), `VideoEmbed` (thumbnail + inline player), `PlatformEmbed` (YouTube/Vimeo/Giphy thumbnail + branding).
- `LinkPreview` becomes a thin orchestrator: resolve URL -> pick embed widget -> wrap in `EmbedCard`.
- Riverpod provider for `MediaEmbedResolver` with caching.

**Pros:**
- Clean separation of concerns; each embed type is independently testable
- Easy to add new platform support (just add a new resolver and widget)
- Shared `EmbedCard` wrapper enforces consistent UX
- Resolver results can be cached in Riverpod state
- Follows the project's existing pattern of small, focused widgets

**Cons:**
- More files to create upfront
- Slightly more architecture than strictly necessary for v1
- Still needs a video player dependency for inline video

**Effort:** Medium-High (3-4 days)
**Dependencies:** `cached_network_image` (already in pubspec), video player package for video embeds

---

### Approach 3: WebView-Based Embeds

**Summary:** Use platform webviews to render embeds, especially for video platforms that provide iframe embed codes.

**Technical approach:**
- Add `webview_flutter` dependency.
- For YouTube/Vimeo, construct the iframe embed URL and render in a sized WebView.
- For direct media, still use native Flutter widgets.
- WebView handles all the platform-specific player chrome, DRM, etc.

**Pros:**
- Perfect fidelity for platform embeds -- YouTube player looks exactly like YouTube
- Handles edge cases like age-restricted videos, playlists, etc.
- No need for a native video player package for platform videos

**Cons:**
- WebView is heavyweight: memory, startup time, platform inconsistencies
- Poor performance in a scrolling list with multiple embeds
- WebView on macOS/Linux desktop is still rough in Flutter
- Breaks the native feel -- WebView content won't match Gloam's dark theme
- Security concerns: loading arbitrary web content inside the app
- Not available on all platforms equally (desktop support varies)

**Effort:** Medium (2-3 days for basic, but ongoing maintenance)
**Dependencies:** `webview_flutter` (+ platform-specific packages)

---

### Approach 4: OEmbed API + Thumbnail-Only (No Inline Playback)

**Summary:** Use the oEmbed protocol to fetch rich metadata (title, thumbnail, provider) for URLs and display an enriched preview card. Video playback always opens externally.

**Technical approach:**
- New `oembed_service.dart` that queries oEmbed endpoints (YouTube, Vimeo, etc.) or uses a generic oEmbed discovery mechanism.
- Render enriched cards: large thumbnail, title, description, provider logo.
- All "play" actions open the URL in the external browser/app.
- Direct image/GIF URLs still render inline (no oEmbed needed).

**Pros:**
- No video player dependency needed
- Much simpler implementation -- just HTTP requests and image rendering
- oEmbed is a well-defined standard
- Lower memory and performance impact

**Cons:**
- No inline video playback -- users always leave the app to watch videos
- oEmbed endpoints aren't always reliable or fast
- Many platforms don't support oEmbed or have rate limits
- Feels like a half-measure -- users expect inline playback for YouTube in 2026
- Giphy/Tenor GIFs would work but YouTube/Vimeo would feel broken

**Effort:** Low-Medium (1-2 days)
**Dependencies:** None beyond existing `dio`

---

### Approach 5: Hybrid Approach (Native Media + Platform Thumbnails + Deferred Player)

**Summary:** Direct media (images, GIFs, short videos) renders natively inline. Platform links (YouTube, Vimeo) show rich thumbnails immediately, with inline playback added as a fast-follow via `media_kit`. Video playback is architecturally supported from day one but the player integration ships separately.

**Technical approach:**
- Phase A (this feature): Build the resolver + embed widget architecture from Approach 2. Ship with direct image/GIF inline rendering, platform thumbnail extraction (YouTube thumbnail URL patterns, Giphy direct URLs), and enhanced OG previews. Videos show thumbnail + play icon that opens externally.
- Phase B (fast-follow): Integrate `media_kit` for inline video playback. The `VideoEmbed` widget already exists with the right interface; Phase B replaces the "open externally" behavior with an inline player.
- URL-to-thumbnail mapping for YouTube (`https://img.youtube.com/vi/{id}/hqdefault.jpg`), Vimeo (via oEmbed), Giphy (URL already is the media).

**Pros:**
- Ships useful functionality fast (images/GIFs inline is the 80% case)
- Architecture supports future inline video without rework
- No new heavy dependencies for Phase A
- Thumbnail extraction for YouTube/Vimeo is deterministic (no API calls needed for YouTube)
- Clean separation: Phase A is pure Flutter widgets, Phase B adds native player
- Matches what Discord/Slack do: GIFs inline, YouTube thumbnail + click-to-play

**Cons:**
- YouTube/Vimeo don't play inline in Phase A (but this matches user expectations for v1)
- Two-phase delivery means video playback is deferred
- Still need to handle the YouTube thumbnail resolution variants (default, hq, maxres)

**Effort:** Phase A: Medium (2-3 days), Phase B: Medium (2-3 days additional)
**Dependencies:** Phase A: none new. Phase B: `media_kit` + platform libs

---

## Recommendation

**Approach 5: Hybrid (Native Media + Platform Thumbnails + Deferred Player)** is the best fit for Gloam.

**Rationale:**

1. **Pragmatic scoping.** The user's core request is "GIFs and images should show inline, YouTube should look right." Approach 5 delivers this in Phase A without any new dependencies. Inline video playback is architecturally ready but ships when the video player integration is solid.

2. **Matches the codebase patterns.** The existing widget structure (`ImageMessage`, `VideoMessage`, `FileMessage`, `LinkPreview`) already follows the "small widget per content type" pattern. The embed widget family (`GifEmbed`, `ImageEmbed`, `VideoEmbed`, `PlatformEmbed`) mirrors this exactly. The resolver service fits naturally as a Riverpod provider alongside `matrixServiceProvider`.

3. **No new dependencies for Phase A.** `cached_network_image` is already in pubspec. YouTube thumbnail URLs are deterministic (no API key needed). Giphy/Tenor URLs are the direct media. The homeserver's `/preview_url` provides OG metadata for everything else.

4. **Cross-platform safe.** Pure Flutter widgets work identically on iOS, Android, macOS, Windows, Linux. No WebView fragmentation. No platform-specific player code until Phase B.

5. **UX hierarchy is clear.** The `EmbedCard` wrapper enforces the "two tap targets" pattern -- media content in the center, domain/external-link at the bottom. This is consistent whether the content is a GIF, a YouTube thumbnail, or an OG-enriched article preview.

6. **Avoids the WebView trap.** Approach 3 would create ongoing maintenance burden and platform-specific bugs. The thumbnail-to-external-play pattern is what Discord uses and users understand it.

---

## Implementation Plan

### Phase A: Rich Media Embeds (This Feature)

#### Step 1: Media Embed Resolver Service

**File:** `lib/features/chat/data/media_embed_resolver.dart` (new)

- Define `MediaEmbedType` enum: `directImage`, `directGif`, `directVideo`, `youtube`, `vimeo`, `giphy`, `tenor`, `imgur`, `ogRich`, `plain`.
- Define `MediaEmbedInfo` data class: `type`, `originalUrl`, `mediaUrl` (direct media or thumbnail), `title`, `description`, `providerName`, `providerIconUrl`, `width`, `height`.
- Implement URL classification:
  - **Direct media:** Check file extension (`.gif`, `.jpg`, `.jpeg`, `.png`, `.webp`, `.svg`, `.mp4`, `.webm`, `.mov`). Also check `Content-Type` header via HEAD request as fallback.
  - **YouTube:** Match `youtube.com/watch?v=`, `youtu.be/`, `youtube.com/shorts/`. Extract video ID. Build thumbnail URL: `https://img.youtube.com/vi/{id}/hqdefault.jpg`.
  - **Vimeo:** Match `vimeo.com/{id}`. Use oEmbed endpoint for thumbnail.
  - **Giphy:** Match `giphy.com/gifs/`, `media.giphy.com/media/`. The URL often IS the direct GIF.
  - **Tenor:** Match `tenor.com/view/`. Extract media URL from Tenor's URL structure.
  - **Imgur:** Match `imgur.com/`, `i.imgur.com/`. Direct image URL extraction.
  - **Fallback:** Use homeserver `/preview_url` for OG metadata (title, description, og:image).
- Expose as a Riverpod provider with an in-memory LRU cache (URL -> `MediaEmbedInfo`).

#### Step 2: Embed Card Wrapper

**File:** `lib/features/chat/presentation/widgets/embed_card.dart` (new)

- Shared wrapper for all embed types.
- Layout:
  - Top: Media content area (child widget, constrained to `maxWidth: 400`).
  - Bottom: Domain bar -- small row with provider favicon/icon, domain name (JetBrains Mono, 10px, `textTertiary`), external-link icon. Entire bar tappable to `launchUrl`.
- Styling: `bgElevated` background, `borderSubtle` border, `radiusMd` corners. Matches existing `ImageMessage` and `LinkPreview` container patterns.
- The `accentDim` left-bar from the current `LinkPreview` is removed for media embeds (it's a text-link affordance, not appropriate for visual content).
- Tap behavior on the media area is delegated to the child (play video, open fullscreen image, etc.).

#### Step 3: Individual Embed Widgets

**File:** `lib/features/chat/presentation/widgets/media_embeds/gif_embed.dart` (new)
- Renders GIF via `Image.network` or `cached_network_image`.
- Autoplay by default. Consider `VisibilityDetector` to pause when off-screen (stretch goal).
- Tap opens fullscreen viewer (reuse `_FullscreenImageView` from `image_message.dart`).
- Size constrained: `maxWidth: 400`, `maxHeight: 300`, aspect ratio preserved.

**File:** `lib/features/chat/presentation/widgets/media_embeds/image_embed.dart` (new)
- Renders static images via `CachedNetworkImage`.
- Tap opens fullscreen viewer.
- Loading placeholder: subtle shimmer or the existing `CircularProgressIndicator` pattern.

**File:** `lib/features/chat/presentation/widgets/media_embeds/video_embed.dart` (new)
- Phase A: Renders thumbnail image with play button overlay (matching existing `VideoMessage` pattern).
- Play button tap: opens URL externally (Phase A) or plays inline (Phase B).
- Shows duration badge if available from OG/oEmbed metadata.
- Platform branding: small YouTube/Vimeo icon in the corner for recognized platforms.

**File:** `lib/features/chat/presentation/widgets/media_embeds/og_embed.dart` (new)
- Enhanced link preview with og:image thumbnail on the left or top, title, and description.
- Layout: if og:image exists, show it as a thumbnail (120px wide, left-aligned). Title in Inter 13px semibold, description in Inter 12px secondary. Domain bar at bottom.
- If no og:image, fall back to the existing text-only style.

#### Step 4: Refactor LinkPreview

**File:** `lib/features/chat/presentation/widgets/link_preview.dart` (modify)

- Replace the monolithic `_LinkPreviewState` with an orchestrator:
  1. Extract URL from body (existing regex).
  2. Call `MediaEmbedResolver` to classify the URL.
  3. Based on `MediaEmbedType`, instantiate the appropriate embed widget inside an `EmbedCard`.
- Maintain backward compatibility: the widget signature (`LinkPreview({required this.body})`) stays the same. `MessageBubble` needs no changes.

#### Step 5: Fullscreen Viewer Extraction

**File:** `lib/features/chat/presentation/widgets/fullscreen_media_viewer.dart` (new, extracted)

- Extract `_FullscreenImageView` from `image_message.dart` into a shared widget.
- Both `ImageMessage` and the new embed widgets can reuse it.
- Add support for network URLs (not just MXC-resolved images).

### State Management

- `MediaEmbedResolver` is a Riverpod provider (simple Provider, not StateNotifier -- it's a service with an internal cache).
- Each embed widget is a `ConsumerStatefulWidget` that reads the resolver and manages its own loading state.
- The resolver's LRU cache prevents redundant network requests when scrolling.

### New Dependencies

- **Phase A:** None. `cached_network_image` already in pubspec. `dio` already available for HTTP HEAD requests.
- **Phase B (future):** `media_kit` + `media_kit_libs_*` for inline video playback.

### Edge Cases

- **CORS on direct media URLs.** Some servers block direct image loading. Fall back to text-only preview. The homeserver proxy via `/preview_url` may help here.
- **Animated WebP.** Treat like GIF (autoplay).
- **Very large GIFs.** Cap download at ~10MB. Show thumbnail with a "tap to load" overlay for larger files.
- **YouTube age-restricted / private videos.** Thumbnail URL returns a placeholder image. Detect and show generic "Video" preview instead.
- **Multiple URLs in one message.** Only preview the first URL (matching current behavior). Can expand to multiple previews later.
- **URL inside markdown link.** If the URL is wrapped in `[text](url)` markdown syntax, the link preview should still detect and render it. The existing regex handles this.
- **Tenor/Giphy via Matrix sticker packs.** Some Matrix clients send Giphy content as `m.image` events, not as URLs in text. Those are already handled by `ImageMessage`. This feature only covers URLs in text messages.
- **Rate limits on oEmbed endpoints.** Cache aggressively. Vimeo oEmbed is rate-limited; cache results in the LRU for the session.

---

## Acceptance Criteria

- [ ] Direct image URLs (`.jpg`, `.png`, `.webp`) render the image inline inside a link preview card
- [ ] Direct GIF URLs (`.gif`, animated `.webp`) render and autoplay inline
- [ ] YouTube URLs show the video thumbnail with a play button overlay and YouTube branding
- [ ] Vimeo URLs show the video thumbnail with a play button overlay
- [ ] Giphy/Tenor URLs render the GIF inline (autoplay)
- [ ] Imgur direct image URLs render the image inline
- [ ] All embeds show a domain bar at the bottom with external-link icon
- [ ] Tapping the domain bar opens the URL in the external browser
- [ ] Tapping the play button on video embeds opens the video externally (Phase A)
- [ ] Tapping an image/GIF embed opens a fullscreen viewer
- [ ] Embeds are constrained to max 400px wide and preserve aspect ratio
- [ ] Failed media loads gracefully fall back to the existing text-only link preview
- [ ] URLs without recognized media patterns still show the existing link preview style
- [ ] Embeds render correctly on macOS, iOS, and Android
- [ ] No new dependencies added in Phase A
- [ ] Embed resolution results are cached to avoid redundant network requests

---

## Related

- **Current implementation:** `lib/features/chat/presentation/widgets/link_preview.dart` -- the widget being enhanced
- **Image rendering patterns:** `lib/features/chat/presentation/widgets/image_message.dart` -- reusable fullscreen viewer, image loading patterns
- **Video rendering:** `lib/features/chat/presentation/widgets/file_message.dart` (`VideoMessage`) -- thumbnail + play overlay pattern to mirror
- **Design system:** `docs/plan/09-design-system.md` -- color tokens, typography, spacing
- **Phase 1 plan:** `docs/plan/02-phase1-core-messaging.md` -- media rendering requirements
- **FEAT-002:** File attachments -- related media handling infrastructure
- **Competitive analysis:** `COMPETITIVE_ANALYSIS.md` -- Discord/Slack embed behavior as reference
