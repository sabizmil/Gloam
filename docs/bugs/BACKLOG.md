# Gloam Bug Backlog

| Bug | Title | Priority | Status | Effort |
|-----|-------|----------|--------|--------|
| [BUG-001](BUG-001-key-icon-always-visible.md) | Key icon shows even after recovery key entered | P2 | Open | 30 min |
| [BUG-002](BUG-002-link-preview-not-clickable.md) | Link previews not clickable, no hover cursor | P1 | Open | 20 min |
| [BUG-003](BUG-003-attachment-button-noop.md) | Attachment (+) button does nothing | P1 | Open | 2 hours |
| [BUG-004](BUG-004-emoji-picker-no-material-error.md) | Emoji picker shows "No Material widget found" error | P0 | Open | 10 min |
| [BUG-005](BUG-005-images-show-filename-only.md) | Images show filename only, no preview | P1 | Open | 3 hours |
| [BUG-006](BUG-006-macos-notifications-not-showing.md) | macOS notifications not showing for new messages | P1 | Open | 20 min |
| [BUG-007](BUG-007-fullscreen-image-no-esc-dismiss.md) | Fullscreen image viewer does not dismiss on Escape key | P2 | Open | 15 min |
| [BUG-008](BUG-008-self-dm-wrong-avatar-no-title.md) | Wrong avatar for own messages in DMs + self-DM room | P1 | Open | 30 min |

## Priority Legend
- **P0**: Crash / app-breaking
- **P1**: Broken feature
- **P2**: Visual / polish
- **P3**: Nice-to-have

## Recommended Fix Order
1. **BUG-004** (P0, 10 min) — Crash fix, wrap emoji picker in Material widget
2. **BUG-002** (P1, 20 min) — Wrap link preview in GestureDetector + url_launcher
3. **BUG-005** (P1, 3 hours) — Rewrite ImageMessage to use SDK's downloadAndDecryptAttachment for E2EE
4. **BUG-003** (P1, 2 hours) — Implement file picker + upload flow
5. **BUG-006** (P1, 20 min) — Add macOS notification presentation flags + explicit permission request
6. **BUG-001** (P2, 30 min) — Conditional key icon based on SSSS unlock state
7. **BUG-007** (P2, 15 min) — Wrap fullscreen image viewer in CallbackShortcuts to dismiss on Escape
8. **BUG-008** (P1, 30 min) — Fix sender avatar in DM timeline + self-DM room list name/avatar
