# Gloam — Design System Specification

**Document:** 09-design-system.md
**Date:** 2026-03-25
**Status:** Planning

---

## 1. Brand Identity

### Name & Domain

- **Name:** Gloam
- **Domain:** gloam.chat
- **Tagline:** *tune in to the conversation*

### Aesthetic Direction

Gloam lives in the twilight — the liminal hour between day and night. The visual language draws from the [Liminal Studio](https://simonabizmil.com) DNA: dark, atmospheric, green-on-black. Think paranormal surveillance terminals, classified document interfaces, EVP signal displays. The aesthetic is not "dark mode" as an afterthought — darkness is the native state. Light emerges from it.

**Key qualities:**
- **Atmospheric, not decorative.** Every visual choice serves mood and readability. No ornamentation for its own sake.
- **Dense, not cramped.** Information density respects the user's time. Generous line spacing and deliberate whitespace prevent fatigue without wasting screen real estate.
- **Subtle, not flat.** Depth comes from value shifts between surface layers, not drop shadows or gradients. Borders are barely-there lines that separate without shouting.
- **Green-tinted neutrals.** The entire dark palette is shifted toward green. Not saturated — desaturated olive and sage tones that feel organic rather than synthetic.
- **Monospace accents.** Section headers and metadata use monospace type as a deliberate design element — a nod to terminal interfaces and data readouts.

### Personality

Gloam is calm, confident, and slightly mysterious. It doesn't try to be fun (not Discord) or corporate (not Slack) or institutional (not Element). It's the chat app for people who care about their tools.

---

## 2. Color System

### Dark Mode (Default)

18 semantic color tokens. All neutrals are green-tinted.

#### Backgrounds

| Token | Hex | Usage |
|-------|-----|-------|
| `bg` | `#080f0a` | App background, deepest layer |
| `bg-surface` | `#0d1610` | Cards, panels, room list background |
| `bg-elevated` | `#121e16` | Modals, dropdowns, popovers, floating UI |

#### Borders

| Token | Hex | Usage |
|-------|-----|-------|
| `border` | `#1a2b1e` | Primary dividers, panel edges, input outlines |
| `border-subtle` | `#132019` | Subtle separators, inactive states, hairlines |

#### Text

| Token | Hex | Usage |
|-------|-----|-------|
| `text-primary` | `#c8dccb` | Body text, message content, room names |
| `text-secondary` | `#6b8a70` | Timestamps, metadata, secondary labels |
| `text-tertiary` | `#3d5c42` | Placeholders, disabled text, section headers (monospace) |

#### Accent

| Token | Hex | Usage |
|-------|-----|-------|
| `accent` | `#7db88a` | Primary interactive elements, links, active states, unread indicators |
| `accent-bright` | `#a3d4ab` | Hover states, focus rings, high-emphasis elements |
| `accent-dim` | `#3d7a4a` | Pressed states, subtle emphasis, selected backgrounds |

#### Semantic

| Token | Hex | Usage |
|-------|-----|-------|
| `danger` | `#c45c5c` | Destructive actions, errors, failed message indicators |
| `warning` | `#c4a35c` | Caution states, unverified badges, rate limit notices |
| `info` | `#5c8ac4` | Informational banners, help text, link previews |
| `online` | `#7db88a` | Presence: online (matches accent — intentional) |

#### Special

| Token | Hex | Usage |
|-------|-----|-------|
| `message-self-bg` | `#0f1f14` | Background tint for the current user's messages |
| `hover` | `#ffffff0a` | Transparent white overlay for hover states (~4% opacity) |
| `focus-ring` | `#7db88a40` | Focus ring with 25% opacity accent |

### Note on Green-Tinted Neutrals

Every "grey" in the palette has a green channel bias. This creates visual cohesion — the backgrounds, text, and borders all belong to the same color family as the accent. Compare:

- Pure neutral grey: `#6b6b6b`
- Gloam neutral (text-secondary): `#6b8a70` — shifted +31 green, +5 blue

This is subtle but immediately noticeable when placed next to a pure-neutral dark theme. It gives Gloam its distinctive "twilight" warmth.

### Light Mode Mapping

Light mode inverts the value scale while preserving the green tinting:

| Token | Dark | Light |
|-------|------|-------|
| `bg` | `#080f0a` | `#f2f6f3` |
| `bg-surface` | `#0d1610` | `#e8ede9` |
| `bg-elevated` | `#121e16` | `#ffffff` |
| `border` | `#1a2b1e` | `#c8d4ca` |
| `border-subtle` | `#132019` | `#dce4dd` |
| `text-primary` | `#c8dccb` | `#1a2b1e` |
| `text-secondary` | `#6b8a70` | `#5a7a5f` |
| `text-tertiary` | `#3d5c42` | `#8fa894` |
| `accent` | `#7db88a` | `#2d7a3e` |
| `accent-bright` | `#a3d4ab` | `#1d6030` |
| `accent-dim` | `#3d7a4a` | `#b8d4bc` |
| `message-self-bg` | `#0f1f14` | `#e4f0e6` |

Light mode is a fully supported alternative, not a neglected afterthought. But dark is the default and the brand.

### Accent Color Alternatives

Users can swap the accent color in Settings. Six options:

| Name | Hex | Vibe |
|------|-----|------|
| **Gloam Green** (default) | `#7db88a` | The brand color. Twilight moss. |
| **Signal Blue** | `#5c8ac4` | Cool, trustworthy. Borrowed from the `info` token. |
| **Ember** | `#c4785c` | Warm, copper-toned. Campfire energy. |
| **Orchid** | `#a87db8` | Purple-violet. Mysterious, slightly luxurious. |
| **Gold** | `#c4a35c` | Warm yellow-amber. Matches `warning` token. |
| **Rose** | `#c45c7d` | Muted pink-red. Warm without being aggressive. |

When the accent changes, `accent`, `accent-bright`, `accent-dim`, `online`, and `focus-ring` all derive from the new base. The green-tinted neutrals stay the same — the accent is an overlay on the base palette, not a replacement.

---

## 3. Typography

### Font Stack

| Role | Family | Weight Range | Fallback |
|------|--------|-------------|----------|
| **Display** | Spectral | 400, 500, 600 | Georgia, serif |
| **Body** | Inter | 400, 500, 600 | system-ui, -apple-system, sans-serif |
| **Code/Labels** | JetBrains Mono | 400, 500 | 'SF Mono', 'Fira Code', monospace |

**Spectral** is a serif with italic variants that feels literary and intentional. Used for display headings, onboarding text, empty states — anywhere the app speaks with a voice.

**Inter** is the body workhorse. Optimized for screen readability at small sizes. Used for message text, room names, UI labels, buttons — anything the user reads at volume.

**JetBrains Mono** serves double duty: code blocks (obvious) and section headers/metadata labels as a design element. The monospace-as-header pattern is a Gloam signature.

### Type Scale

| Token | Family | Size | Weight | Line Height | Letter Spacing | Usage |
|-------|--------|------|--------|-------------|----------------|-------|
| `display-lg` | Spectral | 28px | 500 | 1.3 | -0.02em | Onboarding headings |
| `display-md` | Spectral | 22px | 500 | 1.3 | -0.01em | Modal titles, empty states |
| `display-sm` | Spectral | 18px | 500 | 1.3 | 0 | Section titles |
| `heading-lg` | Inter | 16px | 600 | 1.4 | -0.01em | Room names in header |
| `heading-md` | Inter | 14px | 600 | 1.4 | 0 | Setting group titles |
| `heading-sm` | Inter | 13px | 600 | 1.4 | 0 | Sub-section titles |
| `body-lg` | Inter | 15px | 400 | 1.5 | 0 | Message text (default) |
| `body-md` | Inter | 14px | 400 | 1.5 | 0 | UI labels, descriptions |
| `body-sm` | Inter | 13px | 400 | 1.5 | 0 | Secondary text, metadata |
| `caption` | Inter | 12px | 400 | 1.4 | 0.01em | Timestamps, minor labels |
| `code-block` | JetBrains Mono | 14px | 400 | 1.6 | 0 | Code blocks in messages |
| `code-inline` | JetBrains Mono | 13px | 400 | inherit | 0 | Inline code in messages |
| `label` | JetBrains Mono | 11px | 500 | 1.2 | 0.08em | Section headers, metadata badges |
| `label-sm` | JetBrains Mono | 10px | 400 | 1.2 | 0.06em | Tiny labels, counters |

### Section Header Pattern

A signature Gloam element. Section headers use the monospace `label` token with specific formatting:

```
// ROOMS                    ← JetBrains Mono, 11px, weight 500
                              color: text-tertiary (#3d5c42)
                              letterSpacing: 0.08em
                              transform: uppercase
                              prefix: "// " (literal, part of the text)
```

This is used throughout the app: sidebar section headers ("// ROOMS", "// DIRECT MESSAGES"), settings categories ("// APPEARANCE", "// SECURITY"), profile sections ("// DEVICES"), search filter headers. The `//` prefix is a deliberate code-comment aesthetic — information is annotated, not shouted.

---

## 4. Spacing System

### Base Unit

**4px** base unit. All spacing values are multiples of 4.

### Scale

| Token | Value | Usage |
|-------|-------|-------|
| `space-0` | 0px | No spacing |
| `space-1` | 4px | Tight gaps (icon-to-text, badge inset) |
| `space-2` | 8px | Default inline gap, compact padding |
| `space-3` | 12px | Standard padding inside components |
| `space-4` | 16px | Section gaps, card padding |
| `space-5` | 20px | Panel padding (room list, settings) |
| `space-6` | 24px | Major section breaks |
| `space-8` | 32px | Screen padding (mobile), major gaps |
| `space-10` | 40px | Large spacing (between content blocks) |
| `space-12` | 48px | Extra-large spacing |
| `space-16` | 64px | Maximum spacing (above fold content) |

### Component Padding Values

| Component | Padding | Extracted from |
|-----------|---------|----------------|
| Space rail | 8px vertical between icons | Mockup |
| Room list item | 12px horizontal, 10px vertical | Mockup |
| Message bubble | 12px all sides | Mockup |
| Message composer | 12px horizontal, 8px vertical (inner), 12px outer | Mockup |
| Modal/dialog | 24px all sides | Mockup |
| Settings section | 20px horizontal, 16px top, 8px bottom | Mockup |
| Tab bar | 0px (icons centered in 56px hit target) | Mockup |
| Button (standard) | 12px horizontal, 8px vertical | Mockup |
| Input field | 12px horizontal, 10px vertical | Mockup |
| Quick switcher | 16px horizontal, 12px vertical | Mockup |
| Emoji picker | 8px grid gap, 12px container padding | Mockup |

### Gap Values

| Context | Gap | Note |
|---------|-----|------|
| Between messages (same sender) | 2px | Grouped — no timestamp repeat |
| Between messages (different sender) | 12px | Visual break, shows new sender |
| Between messages (>5 min gap) | 20px + date separator | Time-based grouping |
| Room list items | 0px (divider line) | Items touch, separated by `border-subtle` line |
| Space rail icons | 8px | Compact vertical spacing |
| Settings toggle rows | 0px (divider line) | Like iOS settings |

---

## 5. Component Specifications

### Space Rail

The leftmost vertical bar. Always visible on desktop/tablet. Hidden on phone (becomes part of bottom nav or drawer).

| Property | Value |
|----------|-------|
| Width | 56px |
| Background | `bg` (#080f0a) |
| Right border | 1px `border-subtle` |
| Icon size | 36px (space avatars) or 22px (utility icons) |
| Icon shape | Rounded rectangle, 10px border radius |
| Icon spacing | 8px vertical gap |
| Selected indicator | 3px wide, 20px tall pill on left edge, `accent` color |
| Unread dot | 8px circle, `accent`, overlapping bottom-right of icon |
| Mention badge | 16px min-width pill, `danger` background, white text, `caption` font |
| Sections | DMs (top), Spaces (middle), utility icons (bottom: Settings, Add) |
| Tooltip | On hover (desktop), 400ms delay, `bg-elevated` background |

### Room List Item

A single row in the room list panel.

| Property | Value |
|----------|-------|
| Height | 56px (comfortable) / 44px (compact mode) |
| Padding | 12px horizontal, 10px vertical |
| Avatar | 36px circle (comfortable) / 28px circle (compact) |
| Avatar-to-text gap | 12px |
| Room name | `heading-sm` (Inter 13px/600), `text-primary`, single line, ellipsis |
| Last message preview | `body-sm` (Inter 13px/400), `text-secondary`, single line, ellipsis |
| Timestamp | `caption` (Inter 12px/400), `text-tertiary`, right-aligned |
| Unread count badge | 18px pill, min-width 18px, `accent` background, `bg` text, `label-sm` font |
| Mention badge | Same as unread but `danger` background |
| Muted indicator | `text-tertiary` for all text, no badge (count shown as text-tertiary number) |
| Typing indicator | Replaces last message preview: "Alice is typing..." in `text-secondary`, italic |
| Hover background | `hover` (#ffffff0a) |
| Selected background | `accent-dim` at 15% opacity |
| Encrypted icon | 12px lock icon, `text-tertiary`, left of room name (only if E2EE) |
| Border bottom | 1px `border-subtle` |

### Message Bubble

Messages use a flat layout (not speech-bubble shapes). The sender's messages have a subtle background tint.

| Property | Value |
|----------|-------|
| Max width | 65% of timeline width (desktop), 85% (mobile) |
| Padding | 12px all sides |
| Border radius | 8px |
| Self background | `message-self-bg` (#0f1f14) |
| Others background | transparent (no background) |
| Sender name | `body-sm` (Inter 13px/600), `accent`, shown on first message in a group |
| Message text | `body-lg` (Inter 15px/400), `text-primary`, line-height 1.5 |
| Timestamp | `caption` (Inter 12px/400), `text-tertiary`, right of last line or below |
| Delivery indicator | 14px icon right of timestamp: clock (sending), single check (sent), double check (delivered), filled double check (read) |
| Failed indicator | `danger` colored retry icon, "Failed to send — tap to retry" in `caption`/`danger` |
| Reply preview | 3px left border in `accent`, sender name in `body-sm`/`accent`, quoted text in `body-sm`/`text-secondary`, 8px vertical padding |
| Edit indicator | "(edited)" in `caption`/`text-tertiary` after timestamp |
| Reactions row | Below message, 4px gap. Each reaction: 24px pill, 6px padding, emoji 16px + count in `label-sm`, `border-subtle` border, `bg-surface` background. Own reaction has `accent-dim` border. |
| Image | max-width 400px, max-height 300px, 8px border-radius, blurhash placeholder |
| File attachment | 48px row: file icon (22px, `text-secondary`) + filename (`body-sm`) + size (`caption`/`text-tertiary`), `bg-surface` background, 8px border-radius, 12px padding |
| Link preview | Below message text. Card: `bg-surface`, 1px `border-subtle`, 8px radius. Image (if available) 120x80px left or full-width top. Title `heading-sm`, description `body-sm`/`text-secondary`, domain `caption`/`text-tertiary`. |
| Code block | `code-block` font, `bg-surface` background, 8px border-radius, 12px padding, optional language label in `label-sm`/`text-tertiary` |
| Hover actions | Floating toolbar appears on hover (desktop): Reply, React, Thread, More. `bg-elevated` background, 6px radius, 24px icon buttons. |

### Message Composer

The input area at the bottom of the chat timeline.

| Property | Value |
|----------|-------|
| Background | `bg-surface` |
| Top border | 1px `border` |
| Outer padding | 12px horizontal, 8px vertical |
| Input field | Multi-line, min-height 40px, max-height 200px (then scroll) |
| Input background | `bg` |
| Input border | 1px `border`, focus: 1px `accent` |
| Input border radius | 8px |
| Input padding | 12px horizontal, 10px vertical |
| Input text | `body-lg`, `text-primary` |
| Placeholder | `body-lg`, `text-tertiary`, "Message #room-name" |
| Send button | 32px circle, `accent` background, white arrow icon 18px. Disabled: `border` background, `text-tertiary` icon. |
| Attachment button | 22px icon, `text-secondary`, left of input |
| Emoji button | 22px icon, `text-secondary`, right side of input |
| Formatting toolbar | Appears on text selection (mobile) or toggle (desktop). `bg-elevated`, icons: Bold, Italic, Strike, Code, Link, List, Quote. 22px icons, `text-secondary`, active: `accent`. |
| Reply preview | Above input: 3px left border `accent`, "Replying to [name]" in `body-sm`/`accent`, close X button. `bg-surface` background. |
| Edit preview | Above input: "Editing message" in `body-sm`/`warning`, close X button. |
| Typing indicator | Above composer: "[Name] is typing..." in `caption`/`text-secondary` with animated dots. |

### Modal / Dialog

Centered overlay for confirmations, settings, verification flows.

| Property | Value |
|----------|-------|
| Backdrop | `#000000` at 60% opacity |
| Container | `bg-elevated`, 12px border-radius, `border` 1px border |
| Max width | 440px (default), 600px (wide variant) |
| Padding | 24px all sides |
| Title | `display-sm` (Spectral 18px/500) |
| Body | `body-md` (Inter 14px/400), `text-secondary` |
| Action buttons | Right-aligned, 8px gap. Primary: `accent` background, `bg` text. Secondary: transparent, `text-primary` text, `border` border. Destructive: `danger` background, white text. |
| Close button | 22px X icon, top-right, `text-tertiary`, hover: `text-secondary` |
| Animation | Fade in 150ms + scale from 0.95 to 1.0, ease-out |

### Tab Bar (Mobile)

Bottom navigation on phone layout.

| Property | Value |
|----------|-------|
| Height | 56px + safe area inset |
| Background | `bg-surface` |
| Top border | 1px `border-subtle` |
| Items | 4: Chats, Spaces, Calls, Settings |
| Icon size | 22px |
| Label | `label-sm` (JetBrains Mono 10px), 4px below icon |
| Inactive color | `text-tertiary` |
| Active color | `accent` |
| Badge | 8px dot or count pill on icon, `danger` background for mentions |

### Avatar

| Property | Value |
|----------|-------|
| Sizes | 24px (tiny), 28px (compact), 36px (standard), 44px (large), 64px (profile) |
| Shape | Circle for users, rounded rectangle (6px radius) for rooms/spaces |
| Fallback | First letter of display name, centered, `accent-dim` background, `text-primary` text |
| Fallback font | Inter, weight 600, size = avatar diameter * 0.45 |
| Online indicator | 10px circle, `online` color, 2px `bg` border, bottom-right position |
| Idle indicator | Same position, `warning` color, hollow circle (2px stroke) |

### Badge

| Property | Value |
|----------|-------|
| Unread | min-width 18px, height 18px, `accent` background, `bg` text, `label-sm` font, 9px border-radius (pill) |
| Mention | Same dimensions, `danger` background |
| Dot | 8px circle, `accent` fill, no text |
| Position | Overlapping parent element by 4px (absolute positioned) |

### Toggle

| Property | Value |
|----------|-------|
| Track size | 40px wide, 22px tall, 11px border-radius |
| Track off | `border` background |
| Track on | `accent` background |
| Thumb | 18px circle, 2px inset, `text-primary` (off), `bg` (on) |
| Animation | 150ms ease-in-out slide |
| Label | `body-md`, `text-primary`, left of toggle |
| Description | `body-sm`, `text-secondary`, below label |

### Input Field

| Property | Value |
|----------|-------|
| Height | 40px (single-line) |
| Background | `bg` |
| Border | 1px `border`, focus: 1px `accent` |
| Border radius | 8px |
| Padding | 12px horizontal, 10px vertical |
| Text | `body-md`, `text-primary` |
| Placeholder | `body-md`, `text-tertiary` |
| Label (above) | `body-sm` (Inter 13px/500), `text-secondary`, 4px gap below |
| Error state | Border `danger`, helper text below in `caption`/`danger` |
| Disabled | `bg-surface` background, `text-tertiary` text |
| Leading icon | 18px, `text-secondary`, 8px right margin |

### Button Variants

| Variant | Background | Text | Border | Hover |
|---------|-----------|------|--------|-------|
| **Primary** | `accent` | `bg` | none | `accent-bright` background |
| **Secondary** | transparent | `text-primary` | 1px `border` | `hover` overlay |
| **Ghost** | transparent | `text-secondary` | none | `hover` overlay |
| **Danger** | `danger` | `#ffffff` | none | lighten 10% |
| **Icon** | transparent | `text-secondary` | none | `hover` overlay, `text-primary` |

All buttons: 8px border-radius, `body-md` font weight 500, 12px horizontal padding, 8px vertical padding. Min height 36px. Disabled: 40% opacity.

### Quick Switcher

Cmd/Ctrl+K overlay for fast navigation.

| Property | Value |
|----------|-------|
| Position | Centered, top third of screen |
| Width | 560px (desktop), full-width minus 32px (mobile) |
| Background | `bg-elevated` |
| Border | 1px `border` |
| Border radius | 12px |
| Shadow | 0 8px 32px rgba(0,0,0,0.5) |
| Search input | Full width, no border, 48px height, `body-lg`, autofocus |
| Input icon | 18px search icon, `text-tertiary` |
| Result item height | 44px |
| Result item | Avatar (24px) + name (`body-md`) + description (`body-sm`/`text-secondary`), 12px horizontal padding |
| Selected result | `accent-dim` at 15% opacity background |
| Keyboard hint | `label-sm`, `text-tertiary`, right-aligned in result row ("Enter to open") |
| Section headers | `label` token (JetBrains Mono 11px), `text-tertiary`, "// ROOMS", "// PEOPLE" |
| Max visible results | 8 (then scroll) |
| Animation | Fade in 100ms + slide down 8px |

### Emoji Picker

Appears from composer emoji button or long-press on message.

| Property | Value |
|----------|-------|
| Width | 320px (desktop), full-width (mobile bottom sheet) |
| Height | 360px (desktop), 50vh (mobile) |
| Background | `bg-elevated` |
| Border | 1px `border` |
| Border radius | 12px (desktop), 12px top (mobile sheet) |
| Search input | 36px height, `body-sm`, full width, 12px horizontal padding |
| Emoji grid | 8 columns, 36px cells, 4px gap |
| Emoji size | 24px |
| Category tabs | 22px icons, `text-tertiary`, active: `accent`, bottom border indicator |
| Frequently used | Top section, "// FREQUENTLY USED" label header |
| Hover | `hover` overlay on cell |
| Skin tone selector | Long-press popup, 6 options in horizontal row |

### Profile Card

User profile popover (hover on avatar or click on username).

| Property | Value |
|----------|-------|
| Width | 280px |
| Background | `bg-elevated` |
| Border | 1px `border` |
| Border radius | 12px |
| Shadow | 0 4px 16px rgba(0,0,0,0.4) |
| Avatar | 64px, centered at top, 16px top padding |
| Display name | `heading-lg` (Inter 16px/600), `text-primary`, centered, 8px below avatar |
| User ID | `caption` (Inter 12px/400), `text-tertiary`, centered, 4px below name |
| Presence | `body-sm`, `online`/`warning`/`text-tertiary` color dot + text, 8px below ID |
| Actions | Row of icon buttons: Message, Call, More. 36px circle, `bg-surface`, `text-secondary` icons 18px. 12px gap. |
| Divider | 1px `border-subtle`, 16px horizontal margin |
| Metadata | Bio/note field, `body-sm`/`text-secondary`, 16px horizontal padding |

### Settings Layout

| Property | Value |
|----------|-------|
| Navigation | Left sidebar (desktop) or push navigation (mobile) |
| Sidebar width | 220px |
| Sidebar item | 40px height, 12px horizontal padding, `body-md`, `text-secondary`, active: `accent` text + `accent-dim` at 10% background |
| Content max-width | 600px, centered in remaining space |
| Content padding | 20px horizontal, 16px top |
| Section header | `label` token: "// SECTION NAME" pattern |
| Setting row | `body-md` label, `body-sm`/`text-secondary` description, right-aligned control (toggle, dropdown, button). 48px min height. Bottom border 1px `border-subtle`. |
| Group container | `bg-surface` background, 8px border-radius, 1px `border-subtle`, grouped rows inside |

---

## 6. Iconography

### Icon Library

**Lucide Icons** — consistent 24px grid, 1.5px stroke weight, rounded joins. Open source, actively maintained, 1400+ icons.

### Size Conventions

| Context | Size | Stroke |
|---------|------|--------|
| Tab bar, navigation | 22px | 1.5px |
| Inline with body text | 16px | 1.5px |
| Buttons, actions | 18px | 1.5px |
| Message actions (hover toolbar) | 18px | 1.5px |
| Small indicators (lock, pin) | 14px | 1.5px |
| Large decorative (empty states) | 48px | 1.5px |

### Color States

| State | Color |
|-------|-------|
| Default | `text-secondary` (#6b8a70) |
| Active / Selected | `accent` (#7db88a) |
| Hover | `text-primary` (#c8dccb) |
| Disabled | `text-tertiary` (#3d5c42) |
| Destructive | `danger` (#c45c5c) |

### Key Icons

| Usage | Lucide Icon Name |
|-------|-----------------|
| Send | `arrow-up` (in circle) |
| Attach | `paperclip` |
| Emoji | `smile` |
| Reply | `reply` |
| Thread | `message-square` |
| Edit | `pencil` |
| Delete | `trash-2` |
| Search | `search` |
| Settings | `settings` |
| More | `more-horizontal` |
| Lock (E2EE) | `lock` |
| Pin | `pin` |
| Mute | `bell-off` |
| Call (voice) | `phone` |
| Call (video) | `video` |
| Close | `x` |
| Back | `chevron-left` |
| Expand | `chevron-right` |
| Add | `plus` |
| Check | `check` |
| Double check | `check-check` |

---

## 7. Animation & Motion

### Principles

- **Subtle, not flashy.** Animations serve orientation and feedback, not entertainment.
- **Fast.** Most transitions are 100-200ms. Nothing exceeds 300ms.
- **Respect `reduceMotion`.** When the platform's `reduceMotion` accessibility setting is on, replace all motion with instant cuts. No exceptions.

### Transition Durations

| Context | Duration | Easing |
|---------|----------|--------|
| Hover state changes | 100ms | ease-out |
| Button press/release | 80ms | ease-in-out |
| Modal appear/dismiss | 150ms | ease-out / ease-in |
| Panel slide (thread, details) | 200ms | ease-out |
| Page transition (mobile) | 250ms | ease-in-out (with spring physics on iOS) |
| Toast/snackbar appear | 150ms | ease-out |
| Toast auto-dismiss | 200ms | ease-in |
| Message send (local echo) | 0ms (instant), delivery indicator crossfade 200ms | — |
| Reaction appear | 150ms | spring (slight overshoot) |
| Quick switcher appear | 100ms | ease-out |

### Specific Animations

| Element | Animation |
|---------|-----------|
| **Message delivery** | Clock icon → check icon: crossfade 200ms |
| **Reaction added** | Scale from 0.8 to 1.0, 150ms spring |
| **Typing indicator** | Three dots pulsing sequentially, 1.2s cycle |
| **Unread badge count change** | Scale pop 0.9→1.1→1.0, 200ms |
| **Room list reorder** | Slide to new position, 200ms ease-out |
| **Image load** | Blurhash → thumbnail: crossfade 200ms |
| **Modal backdrop** | Fade 0→60% opacity, 150ms |
| **Space rail selection** | Pill indicator slides vertically, 150ms ease-out |
| **Composer expand** | Height lerp, 100ms ease-out |

### reduceMotion Behavior

```dart
final reduceMotion = MediaQuery.of(context).disableAnimations;
final duration = reduceMotion ? Duration.zero : const Duration(milliseconds: 200);
```

When `reduceMotion` is true:
- All durations become `Duration.zero`
- Spring animations become instant
- Page transitions use instant cuts
- Typing indicator shows static "..." text instead of animated dots
- Only exception: loading spinners still spin (accessibility guidelines permit this)

---

## 8. Responsive Breakpoints

### Breakpoint Definitions

| Name | Range | Layout |
|------|-------|--------|
| **Phone** | < 600px | Single column, bottom tab bar, push navigation |
| **Tablet** | 600px - 1024px | Two columns (room list + content), collapsible space rail |
| **Desktop** | > 1024px | Three columns (space rail + room list + content), optional right panel |

### Phone (< 600px)

```
┌──────────────────────┐
│  ┌────────────────┐  │
│  │   Room List     │  │
│  │   (full width)  │  │
│  │                 │  │
│  │                 │  │
│  │                 │  │
│  │                 │  │
│  └────────────────┘  │
│  ┌────────────────┐  │
│  │ Chats|Spaces|...│  │  ← Bottom tab bar
│  └────────────────┘  │
└──────────────────────┘
```

- Space rail → part of Spaces tab or top header selector
- Room list → tap pushes to chat screen (standard mobile navigation)
- Thread/details → pushed as new screen
- Back gesture to return
- Composer uses platform keyboard avoidance
- Quick switcher is full-width, slides down from top

### Tablet (600px - 1024px)

```
┌────────────────────────────────────────┐
│ ┌──────────┐ ┌──────────────────────┐  │
│ │           │ │                      │  │
│ │  Room     │ │   Message Timeline   │  │
│ │  List     │ │                      │  │
│ │  280px    │ │                      │  │
│ │           │ │                      │  │
│ │           │ │  ┌────────────────┐  │  │
│ │           │ │  │   Composer     │  │  │
│ │           │ │  └────────────────┘  │  │
│ └──────────┘ └──────────────────────┘  │
└────────────────────────────────────────┘
```

- Space rail → collapsed into a top bar dropdown or hamburger menu
- Room list → persistent left panel (280px)
- Chat content → fills remaining width
- Thread/details → overlay or slides in from right (replacing some content width)
- Split view on iPads (supports multitasking)

### Desktop (> 1024px)

```
┌────────────────────────────────────────────────────────┐
│ ┌────┐ ┌──────────┐ ┌────────────────────┐ ┌────────┐ │
│ │    │ │          │ │                    │ │        │ │
│ │ S  │ │  Room    │ │  Message Timeline  │ │ Right  │ │
│ │ p  │ │  List    │ │                    │ │ Panel  │ │
│ │ a  │ │  280px   │ │                    │ │ (opt)  │ │
│ │ c  │ │          │ │                    │ │ 320px  │ │
│ │ e  │ │          │ │  ┌──────────────┐  │ │        │ │
│ │    │ │          │ │  │  Composer    │  │ │        │ │
│ │ 56 │ │          │ │  └──────────────┘  │ │        │ │
│ └────┘ └──────────┘ └────────────────────┘ └────────┘ │
└────────────────────────────────────────────────────────┘
```

- Space rail → persistent left, 56px wide
- Room list → persistent, 280px (resizable 220-360px with drag handle)
- Message timeline → flex width
- Right panel → contextual: thread view, room details, member list, search results. 320px. Slides in/out. Does not replace main content.
- Window min size: 800x500px
- Keyboard shortcuts for all navigation (Cmd+K, Cmd+[, Cmd+], etc.)
- Right-click context menus on messages, rooms, users
- macOS: native title bar with traffic lights, PlatformMenuBar
- Windows/Linux: custom title bar with minimize/maximize/close

### Layout Adaptations Summary

| Feature | Phone | Tablet | Desktop |
|---------|-------|--------|---------|
| Space rail | Hidden (tab/selector) | Collapsed (dropdown) | Visible (56px) |
| Room list | Full screen | 280px panel | 280px panel (resizable) |
| Chat timeline | Full screen (pushed) | Flex width | Flex width |
| Right panel | Full screen (pushed) | Overlay / slide | Inline 320px |
| Thread view | Full screen | Overlay | Right panel |
| Composer | Docked bottom | Docked bottom | Docked bottom |
| Quick switcher | Full-width sheet | Centered overlay | Centered overlay |
| Settings | Full screen (pushed) | Modal or full screen | Left sidebar + content |
| Context menu | Long-press sheet | Long-press sheet | Right-click menu |
| Keyboard shortcuts | None | Partial | Full set |
| Drag-to-resize | No | No | Room list, right panel |
| System tray | N/A | N/A | Yes (desktop) |

---

*This design system is the source of truth for all visual implementation in Gloam. Every widget, screen, and interaction should reference these tokens and specifications. Deviations should be intentional and documented.*
