import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../app/theme/gloam_theme_ext.dart';
import '../../../../app/theme/spacing.dart';
import '../../../../data/emoji_data.dart';
import '../../../../data/emoji_frequency.dart';

/// Search-first emoji picker (Prototype C design).
/// Used in both the hover toolbar (reactions) and the message composer.
class GloamEmojiPicker extends StatefulWidget {
  const GloamEmojiPicker({
    super.key,
    required this.onSelect,
    this.width = 352,
  });

  final void Function(String emoji) onSelect;
  final double width;

  @override
  State<GloamEmojiPicker> createState() => _GloamEmojiPickerState();
}

class _GloamEmojiPickerState extends State<GloamEmojiPicker> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  String _query = '';

  @override
  void initState() {
    super.initState();
    _focusNode.requestFocus();
    EmojiFrequency.load();
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _selectEmoji(String emoji) {
    EmojiFrequency.record(emoji);
    widget.onSelect(emoji);
  }

  // ── Search ──

  List<EmojiEntry> _search(String query) {
    final q = query.toLowerCase().trim();
    if (q.isEmpty) return [];

    final scored = <(EmojiEntry, double)>[];
    for (final entry in allEmoji) {
      final s = _score(entry, q);
      if (s > 0) scored.add((entry, s));
    }
    scored.sort((a, b) => b.$2.compareTo(a.$2));
    return scored.take(40).map((e) => e.$1).toList();
  }

  double _score(EmojiEntry entry, String q) {
    final name = entry.name.toLowerCase();

    // Exact name match
    if (name == q) return 100;
    // Name starts with query
    if (name.startsWith(q)) return 80;
    // A word in the name starts with query
    final words = name.split(RegExp(r'[\s_:-]+'));
    if (words.any((w) => w.startsWith(q))) return 60;
    // Name contains query as substring
    if (name.contains(q)) return 40;
    // Any keyword starts with query
    for (final k in entry.keywords) {
      if (k.toLowerCase().startsWith(q)) return 30;
    }
    // Any keyword contains query
    for (final k in entry.keywords) {
      if (k.toLowerCase().contains(q)) return 20;
    }
    return 0;
  }

  // ── Build ──

  @override
  Widget build(BuildContext context) {
    final colors = context.gloam;
    final isSearching = _query.isNotEmpty;
    final searchResults = isSearching ? _search(_query) : <EmojiEntry>[];
    final frequent = EmojiFrequency.topN(8);

    return Container(
      width: widget.width,
      height: 420,
      decoration: BoxDecoration(
        color: colors.bgSurface,
        borderRadius: BorderRadius.circular(GloamSpacing.radiusLg),
        border: Border.all(color: colors.border),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0A1A0E).withValues(alpha: 0.5),
            blurRadius: 40,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          // ── Search field ──
          _buildSearchField(colors),

          Divider(height: 1, color: colors.border),

          // ── Grid area ──
          Expanded(
            child: isSearching
                ? _buildSearchResults(searchResults, colors)
                : _buildBrowseGrid(colors),
          ),

          // ── Recently used footer ──
          if (!isSearching) ...[
            Divider(height: 1, color: colors.border),
            _buildFrequentFooter(frequent, colors),
          ],
        ],
      ),
    );
  }

  Widget _buildSearchField(dynamic colors) {
    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          Icon(Icons.search, size: 16, color: colors.textTertiary),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: _controller,
              focusNode: _focusNode,
              onChanged: (v) => setState(() => _query = v),
              style: GoogleFonts.inter(
                fontSize: 13,
                color: colors.textPrimary,
              ),
              decoration: InputDecoration(
                hintText: 'search emoji...',
                hintStyle: GoogleFonts.inter(
                  fontSize: 13,
                  color: colors.textTertiary,
                ),
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                contentPadding: EdgeInsets.zero,
                isDense: true,
              ),
            ),
          ),
          if (_query.isNotEmpty)
            GestureDetector(
              onTap: () {
                _controller.clear();
                setState(() => _query = '');
              },
              child: Icon(Icons.close,
                  size: 14, color: colors.textTertiary),
            ),
        ],
      ),
    );
  }

  Widget _buildSearchResults(List<EmojiEntry> results, dynamic colors) {
    if (results.isEmpty) {
      return Center(
        child: Text(
          '// no matches',
          style: GoogleFonts.jetBrainsMono(
            fontSize: 11,
            color: colors.textTertiary,
          ),
        ),
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 8,
        mainAxisSpacing: 2,
        crossAxisSpacing: 2,
      ),
      itemCount: results.length,
      itemBuilder: (context, index) =>
          _emojiCell(results[index].emoji, colors),
    );
  }

  Widget _buildBrowseGrid(dynamic colors) {
    // Build a flat list of widgets: category headers + emoji cells
    final items = <_GridItem>[];
    int? lastCategory;

    for (final entry in allEmoji) {
      if (entry.categoryIndex != lastCategory) {
        lastCategory = entry.categoryIndex;
        items.add(_GridItem.header(emojiCategories[entry.categoryIndex]));
      }
      items.add(_GridItem.emoji(entry.emoji));
    }

    return CustomScrollView(
      slivers: _buildSlivers(items, colors),
    );
  }

  List<Widget> _buildSlivers(List<_GridItem> items, dynamic colors) {
    final slivers = <Widget>[];
    var emojiBuffer = <String>[];

    void flushEmoji() {
      if (emojiBuffer.isEmpty) return;
      final emojis = List<String>.from(emojiBuffer);
      slivers.add(
        SliverGrid(
          delegate: SliverChildBuilderDelegate(
            (ctx, i) => _emojiCell(emojis[i], colors),
            childCount: emojis.length,
          ),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 8,
            mainAxisSpacing: 2,
            crossAxisSpacing: 2,
          ),
        ),
      );
      emojiBuffer = [];
    }

    for (final item in items) {
      if (item.isHeader) {
        flushEmoji();
        slivers.add(SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
            child: Text(
              '// ${item.label!.toLowerCase()}',
              style: GoogleFonts.jetBrainsMono(
                fontSize: 10,
                color: colors.textTertiary,
                letterSpacing: 1,
              ),
            ),
          ),
        ));
      } else {
        emojiBuffer.add(item.emoji!);
      }
    }
    flushEmoji();
    return slivers;
  }

  Widget _buildFrequentFooter(List<String> frequent, dynamic colors) {
    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          Text(
            '//',
            style: GoogleFonts.jetBrainsMono(
              fontSize: 10,
              color: colors.textTertiary,
            ),
          ),
          const SizedBox(width: 6),
          ...frequent.map((e) => GestureDetector(
                onTap: () => _selectEmoji(e),
                child: MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    child: Text(e, style: const TextStyle(fontSize: 18)),
                  ),
                ),
              )),
        ],
      ),
    );
  }

  Widget _emojiCell(String emoji, dynamic colors) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(6),
      child: InkWell(
        onTap: () => _selectEmoji(emoji),
        mouseCursor: SystemMouseCursors.click,
        hoverColor: colors.border.withValues(alpha: 0.8),
        borderRadius: BorderRadius.circular(6),
        child: Center(
          child: Text(emoji, style: const TextStyle(fontSize: 22)),
        ),
      ),
    );
  }
}

/// Internal helper for building the mixed header+emoji list.
class _GridItem {
  final String? label;
  final String? emoji;
  bool get isHeader => label != null;

  _GridItem.header(this.label) : emoji = null;
  _GridItem.emoji(this.emoji) : label = null;
}

/// Shows the emoji picker as a positioned popup.
/// [anchor] controls where the picker appears relative to the screen.
Future<String?> showEmojiPicker(BuildContext context) {
  return showDialog<String>(
    context: context,
    barrierColor: Colors.transparent,
    builder: (ctx) => Stack(
      children: [
        GestureDetector(
          onTap: () => Navigator.pop(ctx),
          child: Container(color: Colors.transparent),
        ),
        Positioned(
          bottom: 80,
          right: 20,
          child: Material(
            color: Colors.transparent,
            child: GloamEmojiPicker(
              onSelect: (emoji) => Navigator.pop(ctx, emoji),
            ),
          ),
        ),
      ],
    ),
  );
}

/// Shows the emoji picker anchored to a specific position.
Future<String?> showEmojiPickerAt(
  BuildContext context, {
  double? top,
  double? bottom,
  double? left,
  double? right,
  double width = 352,
}) {
  return showDialog<String>(
    context: context,
    barrierColor: Colors.transparent,
    builder: (ctx) => Stack(
      children: [
        GestureDetector(
          onTap: () => Navigator.pop(ctx),
          child: Container(color: Colors.transparent),
        ),
        Positioned(
          top: top,
          bottom: bottom,
          left: left,
          right: right,
          child: Material(
            color: Colors.transparent,
            child: GloamEmojiPicker(
              width: width,
              onSelect: (emoji) => Navigator.pop(ctx, emoji),
            ),
          ),
        ),
      ],
    ),
  );
}
