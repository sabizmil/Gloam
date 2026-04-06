import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:matrix/matrix.dart';

import '../../../../app/theme/gloam_color_extension.dart';
import '../../../../app/theme/gloam_theme_ext.dart';
import '../../../../app/theme/spacing.dart';
import '../../../../data/emoji_data.dart';
import '../../../../data/slash_commands.dart';
import '../../../../services/matrix_service.dart';
import '../../../../widgets/gloam_avatar.dart';

/// A TextEditingController that highlights @mention patterns with accent color.
class MentionTextController extends TextEditingController {
  MentionTextController({this.mentionColor});

  final Color? mentionColor;

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final color = mentionColor ?? context.gloam.accentBright;
    final mentionRegex = RegExp(r'(@(?:\[[^\]]+\]|\w+))');
    final spans = <InlineSpan>[];
    var lastEnd = 0;

    for (final match in mentionRegex.allMatches(text)) {
      if (match.start > lastEnd) {
        spans.add(TextSpan(text: text.substring(lastEnd, match.start)));
      }
      spans.add(TextSpan(
        text: match.group(1),
        style: TextStyle(color: color, fontWeight: FontWeight.w500),
      ));
      lastEnd = match.end;
    }

    if (lastEnd < text.length) {
      spans.add(TextSpan(text: text.substring(lastEnd)));
    }

    return TextSpan(style: style, children: spans);
  }
}

// ── Suggestion types ──

enum _AutocompleteMode { none, mention, emoji, command }

class MentionSuggestion {
  final String userId;
  final String displayName;
  final Uri? avatarUrl;
  final bool isRoom;

  const MentionSuggestion({
    required this.userId,
    required this.displayName,
    this.avatarUrl,
    this.isRoom = false,
  });
}

class _EmojiSuggestion {
  final String emoji;
  final String shortcode; // without colons
  final String query; // the matched query (for highlighting)

  const _EmojiSuggestion({
    required this.emoji,
    required this.shortcode,
    required this.query,
  });
}

// ── Unified suggestion wrapper ──

class _Suggestion {
  final MentionSuggestion? mention;
  final _EmojiSuggestion? emojiSuggestion;
  final SlashCommand? command;

  const _Suggestion.fromMention(this.mention)
      : emojiSuggestion = null,
        command = null;
  const _Suggestion.fromEmoji(this.emojiSuggestion)
      : mention = null,
        command = null;
  const _Suggestion.fromCommand(this.command)
      : mention = null,
        emojiSuggestion = null;

  bool get isMention => mention != null;
  bool get isEmoji => emojiSuggestion != null;
  bool get isCommand => command != null;
}

// ── Shortcode helpers ──

String _nameToShortcode(String name) {
  return name
      .toLowerCase()
      .replaceAll(RegExp(r'[\s-]+'), '_')
      .replaceAll(RegExp(r'[^\w]'), '');
}

/// Floating autocomplete overlay for @mentions and :emoji: shortcodes.
///
/// Monitors a [TextEditingController] for `@` and `:` triggers and shows
/// a filtered suggestion list. Selecting inserts the appropriate text.
class MentionAutocomplete extends ConsumerStatefulWidget {
  const MentionAutocomplete({
    super.key,
    required this.roomId,
    required this.controller,
    required this.focusNode,
    required this.child,
  });

  final String roomId;
  final TextEditingController controller;
  final FocusNode focusNode;
  final Widget child;

  @override
  ConsumerState<MentionAutocomplete> createState() =>
      MentionAutocompleteState();
}

class MentionAutocompleteState extends ConsumerState<MentionAutocomplete> {
  final _layerLink = LayerLink();
  final _overlayController = OverlayPortalController();
  List<_Suggestion> _suggestions = [];
  int _selectedIndex = 0;
  int _triggerOffset = -1;
  _AutocompleteMode _mode = _AutocompleteMode.none;
  bool _inserting = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onTextChanged);
  }

  @override
  void didUpdateWidget(covariant MentionAutocomplete oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onTextChanged);
      widget.controller.addListener(_onTextChanged);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onTextChanged);
    super.dispose();
  }

  bool get isVisible => _overlayController.isShowing;

  /// Handle a key event — returns true if consumed.
  bool handleKeyEvent(KeyEvent event) {
    if (!_overlayController.isShowing || _suggestions.isEmpty) return false;
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) return false;

    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      setState(() {
        _selectedIndex =
            (_selectedIndex - 1).clamp(0, _suggestions.length - 1);
      });
      return true;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      setState(() {
        _selectedIndex =
            (_selectedIndex + 1).clamp(0, _suggestions.length - 1);
      });
      return true;
    }
    if (event.logicalKey == LogicalKeyboardKey.tab ||
        event.logicalKey == LogicalKeyboardKey.enter) {
      _insertSuggestion(_suggestions[_selectedIndex]);
      return true;
    }
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      _dismiss();
      return true;
    }
    return false;
  }

  // ── Trigger detection ──

  void _onTextChanged() {
    if (_inserting) return;
    final text = widget.controller.text;
    final selection = widget.controller.selection;
    if (!selection.isValid || !selection.isCollapsed) {
      _dismiss();
      return;
    }

    final cursor = selection.baseOffset;

    // Try slash command trigger first (`/` at position 0)
    if (_tryCommandTrigger(text, cursor)) return;

    // Try emoji trigger (`:` + 2+ alphanumeric chars)
    if (_tryEmojiTrigger(text, cursor)) return;

    // Then try mention trigger (`@`)
    if (_tryMentionTrigger(text, cursor)) return;

    _dismiss();
  }

  bool _tryEmojiTrigger(String text, int cursor) {
    // Scan backwards from cursor for an unmatched `:` trigger
    int colonPos = -1;
    for (var i = cursor - 1; i >= 0; i--) {
      if (text[i] == ':') {
        // Must be at start or after whitespace
        if (i == 0 || RegExp(r'\s').hasMatch(text[i - 1])) {
          colonPos = i;
        }
        break;
      }
      // Only allow word chars and underscores in the query
      if (!RegExp(r'[\w]').hasMatch(text[i])) break;
    }

    if (colonPos < 0) return false;

    final query = text.substring(colonPos + 1, cursor).toLowerCase();
    // Need at least 2 chars to avoid triggering on `:)` etc.
    if (query.length < 2) return false;

    _triggerOffset = colonPos;
    _mode = _AutocompleteMode.emoji;
    _updateEmojiSuggestions(query);
    return _suggestions.isNotEmpty;
  }

  bool _tryMentionTrigger(String text, int cursor) {
    int atPos = -1;
    for (var i = cursor - 1; i >= 0; i--) {
      if (text[i] == '@') {
        if (i == 0 || RegExp(r'\s').hasMatch(text[i - 1])) {
          atPos = i;
        }
        break;
      }
      if (RegExp(r'\s').hasMatch(text[i])) break;
    }

    if (atPos < 0) return false;

    final query = text.substring(atPos + 1, cursor).toLowerCase();
    _triggerOffset = atPos;
    _mode = _AutocompleteMode.mention;
    _updateMentionSuggestions(query);
    return _suggestions.isNotEmpty;
  }

  bool _tryCommandTrigger(String text, int cursor) {
    // Only trigger when `/` is at position 0
    if (text.isEmpty || text[0] != '/') return false;
    // Double-slash `//` is regular text (SDK convention)
    if (text.length > 1 && text[1] == '/') return false;
    // Only while still typing the command name (no space yet)
    if (text.contains(' ')) return false;

    final query = text.substring(1, cursor).toLowerCase();
    _triggerOffset = 0;
    _mode = _AutocompleteMode.command;
    _updateCommandSuggestions(query);
    return _suggestions.isNotEmpty;
  }

  // ── Command suggestions ──

  void _updateCommandSuggestions(String query) {
    final results = <_Suggestion>[];
    for (final cmd in slashCommands) {
      if (query.isEmpty || cmd.name.startsWith(query) || cmd.name.contains(query)) {
        results.add(_Suggestion.fromCommand(cmd));
      }
    }
    // Sort: prefix matches first
    if (query.isNotEmpty) {
      results.sort((a, b) {
        final aPrefix = a.command!.name.startsWith(query) ? 0 : 1;
        final bPrefix = b.command!.name.startsWith(query) ? 0 : 1;
        if (aPrefix != bPrefix) return aPrefix.compareTo(bPrefix);
        return 0; // preserve registry order within same tier
      });
    }
    _applySuggestions(results.take(10).toList());
  }

  // ── Mention suggestions ──

  void _updateMentionSuggestions(String query) {
    final client = ref.read(matrixServiceProvider).client;
    if (client == null) {
      _dismiss();
      return;
    }
    final room = client.getRoomById(widget.roomId);
    if (room == null) {
      _dismiss();
      return;
    }

    final members = room.getParticipants();
    final myUserId = client.userID;

    final scored = <(_Suggestion, int)>[];
    for (final member in members) {
      if (member.membership != Membership.join) continue;
      final name = member.calcDisplayname();
      final id = member.id;
      if (id == myUserId) continue;

      final nameLower = name.toLowerCase();
      final idLower = id.toLowerCase();

      int score = -1;
      if (query.isEmpty) {
        score = 0;
      } else if (nameLower.startsWith(query)) {
        score = 2;
      } else if (nameLower.contains(query)) {
        score = 1;
      } else if (idLower.contains(query)) {
        score = 0;
      }

      if (score >= 0) {
        scored.add((
          _Suggestion.fromMention(MentionSuggestion(
            userId: id,
            displayName: name,
            avatarUrl: member.avatarUrl,
          )),
          score,
        ));
      }
    }

    scored.sort((a, b) {
      final s = b.$2.compareTo(a.$2);
      if (s != 0) return s;
      return a.$1.mention!.displayName.compareTo(b.$1.mention!.displayName);
    });

    // Add @room if permitted
    if (!room.isDirectChat) {
      final canPing = room.canSendEvent('m.room.message') &&
          room.ownPowerLevel >=
              (room.powerForChangingStateEvent('m.room.power_levels'));
      if (canPing && (query.isEmpty || 'room'.startsWith(query))) {
        scored.insert(
          0,
          (
            _Suggestion.fromMention(const MentionSuggestion(
              userId: '@room',
              displayName: '@room',
              isRoom: true,
            )),
            3,
          ),
        );
      }
    }

    _applySuggestions(scored.take(8).map((e) => e.$1).toList());
  }

  // ── Emoji suggestions ──

  void _updateEmojiSuggestions(String query) {
    final scored = <(_Suggestion, double)>[];

    for (final entry in allEmoji) {
      final shortcode = _nameToShortcode(entry.name);
      double score = 0;

      // Check keywords first (gemoji aliases like "thumbsup")
      for (final k in entry.keywords) {
        final kLower = k.toLowerCase();
        if (kLower == query) {
          score = 100;
          break;
        }
        if (kLower.startsWith(query) && score < 80) {
          score = 80;
        } else if (kLower.contains(query) && score < 40) {
          score = 40;
        }
      }

      // Check derived shortcode
      if (score < 60 && shortcode.startsWith(query)) {
        score = 60;
      } else if (score < 20 && shortcode.contains(query)) {
        score = score < 20 ? 20 : score;
      }

      if (score > 0) {
        // Use the keyword that best matches as the display shortcode
        String displayShortcode = shortcode;
        for (final k in entry.keywords) {
          final kLower = k.toLowerCase();
          if (kLower.startsWith(query) || kLower == query) {
            displayShortcode = kLower;
            break;
          }
        }
        // If the derived shortcode is a better prefix match, use that
        if (shortcode.startsWith(query) &&
            !displayShortcode.startsWith(query)) {
          displayShortcode = shortcode;
        }

        scored.add((
          _Suggestion.fromEmoji(_EmojiSuggestion(
            emoji: entry.emoji,
            shortcode: displayShortcode,
            query: query,
          )),
          score,
        ));
      }
    }

    scored.sort((a, b) {
      final s = b.$2.compareTo(a.$2);
      if (s != 0) return s;
      return a.$1.emojiSuggestion!.shortcode
          .compareTo(b.$1.emojiSuggestion!.shortcode);
    });

    _applySuggestions(scored.take(8).map((e) => e.$1).toList());
  }

  // ── Shared ──

  void _applySuggestions(List<_Suggestion> results) {
    if (results.isEmpty) {
      _dismiss();
      return;
    }

    setState(() {
      _suggestions = results;
      _selectedIndex = _selectedIndex.clamp(0, results.length - 1);
    });

    if (!_overlayController.isShowing) {
      _overlayController.show();
    }
  }

  void _insertSuggestion(_Suggestion suggestion) {
    if (suggestion.isMention) {
      _insertMention(suggestion.mention!);
    } else if (suggestion.isEmoji) {
      _insertEmoji(suggestion.emojiSuggestion!);
    } else if (suggestion.isCommand) {
      _insertCommand(suggestion.command!);
    }
  }

  /// Atomically replace text + selection to avoid native text input desync.
  void _replaceText(String newText, int cursorOffset) {
    _inserting = true;
    widget.controller.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: cursorOffset),
    );
    _inserting = false;
    _dismiss();
    widget.focusNode.requestFocus();
  }

  void _insertMention(MentionSuggestion suggestion) {
    final text = widget.controller.text;
    final cursor = widget.controller.selection.baseOffset;

    String mentionText;
    if (suggestion.isRoom) {
      mentionText = '@room';
    } else {
      final name = suggestion.displayName;
      if (RegExp(r'^\w+$').hasMatch(name)) {
        mentionText = '@$name';
      } else {
        mentionText = '@[$name]';
      }
    }

    final before = text.substring(0, _triggerOffset);
    final after = text.substring(cursor);
    final newText = '$before$mentionText $after';
    _replaceText(newText, _triggerOffset + mentionText.length + 1);
  }

  void _insertEmoji(_EmojiSuggestion suggestion) {
    final text = widget.controller.text;
    final cursor = widget.controller.selection.baseOffset;

    final before = text.substring(0, _triggerOffset);
    final after = text.substring(cursor);
    final emoji = suggestion.emoji;
    final newText = '$before$emoji$after';
    _replaceText(newText, _triggerOffset + emoji.length);
  }

  void _insertCommand(SlashCommand command) {
    final cmdText = command.hasArgs ? '/${command.name} ' : '/${command.name}';
    _replaceText(cmdText, cmdText.length);
  }

  void _dismiss() {
    if (_overlayController.isShowing) {
      _overlayController.hide();
    }
    _triggerOffset = -1;
    _suggestions = [];
    _selectedIndex = 0;
    _mode = _AutocompleteMode.none;
  }

  // ── Build ──

  @override
  Widget build(BuildContext context) {
    return CompositedTransformTarget(
      link: _layerLink,
      child: OverlayPortal(
        controller: _overlayController,
        overlayChildBuilder: (_) => _buildOverlay(context),
        child: widget.child,
      ),
    );
  }

  Widget _buildOverlay(BuildContext context) {
    final colors = context.gloam;
    return CompositedTransformFollower(
      link: _layerLink,
      targetAnchor: Alignment.topLeft,
      followerAnchor: Alignment.bottomLeft,
      offset: const Offset(0, -4),
      child: Align(
        alignment: Alignment.bottomLeft,
        child: Material(
          color: colors.bgElevated,
          borderRadius: BorderRadius.circular(GloamSpacing.radiusMd),
          elevation: 8,
          shadowColor: Colors.black54,
          child: Container(
            constraints: const BoxConstraints(maxWidth: 380),
            decoration: BoxDecoration(
              border: Border.all(color: colors.border),
              borderRadius: BorderRadius.circular(GloamSpacing.radiusMd),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(GloamSpacing.radiusMd),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var i = 0; i < _suggestions.length; i++)
                    _buildRow(context, _suggestions[i], i),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRow(BuildContext context, _Suggestion suggestion, int index) {
    if (suggestion.isMention) {
      return _MentionRow(
        suggestion: suggestion.mention!,
        isSelected: index == _selectedIndex,
        onTap: () => _insertSuggestion(suggestion),
        onHover: () => setState(() => _selectedIndex = index),
      );
    } else if (suggestion.isCommand) {
      return _CommandRow(
        command: suggestion.command!,
        isSelected: index == _selectedIndex,
        onTap: () => _insertSuggestion(suggestion),
        onHover: () => setState(() => _selectedIndex = index),
      );
    } else {
      return _EmojiRow(
        suggestion: suggestion.emojiSuggestion!,
        isSelected: index == _selectedIndex,
        isFirst: index == _selectedIndex && index == 0,
        onTap: () => _insertSuggestion(suggestion),
        onHover: () => setState(() => _selectedIndex = index),
      );
    }
  }
}

// ── Mention row ──

class _MentionRow extends ConsumerWidget {
  const _MentionRow({
    required this.suggestion,
    required this.isSelected,
    required this.onTap,
    required this.onHover,
  });

  final MentionSuggestion suggestion;
  final bool isSelected;
  final VoidCallback onTap;
  final VoidCallback onHover;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.gloam;
    return MouseRegion(
      onEnter: (_) => onHover(),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          color: isSelected ? colors.accentDim : Colors.transparent,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              if (suggestion.isRoom)
                Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    color: colors.accent.withAlpha(30),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.campaign, size: 14, color: colors.accent),
                )
              else
                GloamAvatar(
                  displayName: suggestion.displayName,
                  mxcUrl: suggestion.avatarUrl,
                  size: 24,
                ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  suggestion.displayName,
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: colors.textPrimary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (!suggestion.isRoom) ...[
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    suggestion.userId,
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 11,
                      color: colors.textTertiary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ── Emoji row ──

class _EmojiRow extends StatelessWidget {
  const _EmojiRow({
    required this.suggestion,
    required this.isSelected,
    required this.isFirst,
    required this.onTap,
    required this.onHover,
  });

  final _EmojiSuggestion suggestion;
  final bool isSelected;
  final bool isFirst;
  final VoidCallback onTap;
  final VoidCallback onHover;

  @override
  Widget build(BuildContext context) {
    final colors = context.gloam;
    return MouseRegion(
      onEnter: (_) => onHover(),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          color: isSelected ? colors.accentDim : Colors.transparent,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              SizedBox(
                width: 32,
                child: Text(
                  suggestion.emoji,
                  style: const TextStyle(fontSize: 22),
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _buildHighlightedShortcode(colors),
              ),
              if (isFirst)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: colors.bgSurface,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: colors.border),
                  ),
                  child: Text(
                    'Enter',
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 10,
                      color: colors.textTertiary,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHighlightedShortcode(GloamColorExtension colors) {
    final shortcode = suggestion.shortcode;
    final query = suggestion.query;
    final idx = shortcode.indexOf(query);

    if (idx < 0) {
      // No substring match — just show the shortcode
      return Text(
        ':$shortcode:',
        style: GoogleFonts.jetBrainsMono(
          fontSize: 13,
          color: colors.textPrimary,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      );
    }

    return Text.rich(
      TextSpan(
        style: GoogleFonts.jetBrainsMono(
          fontSize: 13,
          color: colors.textPrimary,
        ),
        children: [
          TextSpan(text: ':${shortcode.substring(0, idx)}'),
          TextSpan(
            text: shortcode.substring(idx, idx + query.length),
            style: TextStyle(
              color: colors.accentBright,
              fontWeight: FontWeight.w700,
            ),
          ),
          TextSpan(text: '${shortcode.substring(idx + query.length)}:'),
        ],
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }
}

// ── Command row ──

class _CommandRow extends StatelessWidget {
  const _CommandRow({
    required this.command,
    required this.isSelected,
    required this.onTap,
    required this.onHover,
  });

  final SlashCommand command;
  final bool isSelected;
  final VoidCallback onTap;
  final VoidCallback onHover;

  @override
  Widget build(BuildContext context) {
    final colors = context.gloam;
    return MouseRegion(
      onEnter: (_) => onHover(),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          color: isSelected ? colors.accentDim : Colors.transparent,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              Text(
                '/${command.name}',
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: colors.accentBright,
                ),
              ),
              if (command.args != null) ...[
                const SizedBox(width: 6),
                Text(
                  command.args!,
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 12,
                    color: colors.textTertiary,
                  ),
                ),
              ],
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  command.description,
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    color: colors.textSecondary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
