import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../app/theme/color_tokens.dart';
import '../../../../app/theme/spacing.dart';

/// Gloam emoji picker — matches the mockup: search bar, category tabs,
/// frequently used section, emoji grid.
class GloamEmojiPicker extends StatefulWidget {
  const GloamEmojiPicker({super.key, required this.onSelect});
  final void Function(String emoji) onSelect;

  @override
  State<GloamEmojiPicker> createState() => _GloamEmojiPickerState();
}

class _GloamEmojiPickerState extends State<GloamEmojiPicker> {
  String _search = '';
  int _selectedCategory = 0;

  static const _categories = [
    ('Frequent', _frequentlyUsed),
    ('Smileys', _smileys),
    ('People', _people),
    ('Nature', _nature),
    ('Food', _food),
    ('Objects', _objects),
    ('Symbols', _symbols),
  ];

  List<String> get _displayedEmoji {
    if (_search.isNotEmpty) {
      // Simple search through all categories
      return _allEmoji
          .where((e) => _emojiNames[e]?.contains(_search.toLowerCase()) ?? false)
          .toList();
    }
    return _categories[_selectedCategory].$2;
  }

  static List<String> get _allEmoji {
    final seen = <String>{};
    final result = <String>[];
    for (final list in [
      _frequentlyUsed, _smileys, _people, _nature, _food, _objects, _symbols,
    ]) {
      for (final e in list) {
        if (seen.add(e)) result.add(e);
      }
    }
    return result;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 352,
      height: 420,
      decoration: BoxDecoration(
        color: GloamColors.bgSurface,
        borderRadius: BorderRadius.circular(GloamSpacing.radiusLg),
        border: Border.all(color: GloamColors.border),
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
          // Search bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            height: 44,
            decoration: const BoxDecoration(
              border: Border(
                bottom: BorderSide(color: GloamColors.border),
              ),
            ),
            child: Row(
              children: [
                const Icon(Icons.search,
                    size: 16, color: GloamColors.textTertiary),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    onChanged: (v) => setState(() => _search = v),
                    style: GoogleFonts.inter(
                        fontSize: 13, color: GloamColors.textPrimary),
                    decoration: InputDecoration(
                      hintText: 'search emoji...',
                      hintStyle: GoogleFonts.inter(
                          fontSize: 13, color: GloamColors.textTertiary),
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      contentPadding: EdgeInsets.zero,
                      isDense: true,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Category tabs
          if (_search.isEmpty)
            Container(
              height: 36,
              decoration: const BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: GloamColors.border),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: List.generate(_categoryIcons.length, (i) {
                  final isActive = i == _selectedCategory;
                  return GestureDetector(
                    onTap: () => setState(() => _selectedCategory = i),
                    child: Opacity(
                      opacity: isActive ? 1.0 : 0.4,
                      child: Text(
                        _categoryIcons[i],
                        style: const TextStyle(fontSize: 16),
                      ),
                    ),
                  );
                }),
              ),
            ),

          // Section header
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                _search.isNotEmpty
                    ? '// results'
                    : '// ${_categories[_selectedCategory].$1.toLowerCase()}',
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 10,
                  color: GloamColors.textTertiary,
                  letterSpacing: 1,
                ),
              ),
            ),
          ),

          // Emoji grid
          Expanded(
            child: GridView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 8,
                mainAxisSpacing: 2,
                crossAxisSpacing: 2,
              ),
              itemCount: _displayedEmoji.length,
              itemBuilder: (context, index) {
                final emoji = _displayedEmoji[index];
                return GestureDetector(
                  onTap: () => widget.onSelect(emoji),
                  child: Center(
                    child: Text(
                      emoji,
                      style: const TextStyle(fontSize: 22),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  static const _categoryIcons = [
    '\u2b50', // star (frequent)
    '\ud83d\ude00', // smiley
    '\ud83d\udc4b', // wave (people)
    '\ud83d\udc3e', // paw (nature)
    '\ud83c\udf55', // pizza (food)
    '\ud83d\udca1', // bulb (objects)
    '\ud83d\udd23', // symbols
  ];

  static const _frequentlyUsed = [
    '\ud83d\udc4d', '\ud83d\udd25', '\ud83d\udc40', '\u2764\ufe0f',
    '\ud83d\ude02', '\ud83c\udf89', '\u2705', '\ud83d\udcaf',
    '\ud83d\ude4f', '\ud83e\udd14', '\ud83d\ude0d', '\ud83d\udc4f',
    '\ud83d\ude80', '\ud83c\udf1f', '\ud83d\udcaa', '\ud83d\ude4c',
  ];

  static const _smileys = [
    '\ud83d\ude00', '\ud83d\ude03', '\ud83d\ude04', '\ud83d\ude01',
    '\ud83d\ude06', '\ud83d\ude05', '\ud83e\udd23', '\ud83d\ude02',
    '\ud83d\ude42', '\ud83d\ude43', '\ud83d\ude09', '\ud83d\ude0a',
    '\ud83d\ude07', '\ud83e\udd70', '\ud83d\ude0d', '\ud83e\udd29',
    '\ud83d\ude18', '\ud83d\ude17', '\ud83d\ude1a', '\ud83d\ude19',
    '\ud83e\udd72', '\ud83d\ude0b', '\ud83d\ude1b', '\ud83d\ude1c',
    '\ud83e\udd2a', '\ud83d\ude1d', '\ud83e\udd11', '\ud83e\udd17',
    '\ud83e\udd2d', '\ud83e\udd2b', '\ud83e\udd14', '\ud83e\udd28',
    '\ud83d\ude10', '\ud83d\ude11', '\ud83d\ude36', '\ud83d\ude44',
    '\ud83d\ude0f', '\ud83d\ude23', '\ud83d\ude25', '\ud83e\udd7a',
  ];

  static const _people = [
    '\ud83d\udc4b', '\ud83e\udd1a', '\ud83d\udd90\ufe0f', '\u270b',
    '\ud83d\udc4c', '\ud83e\udd0c', '\ud83e\udd0f', '\u270c\ufe0f',
    '\ud83e\udd1e', '\ud83e\udd1f', '\ud83e\udd18', '\ud83d\udc4d',
    '\ud83d\udc4e', '\u270a', '\ud83d\udc4a', '\ud83e\udd1b',
  ];

  static const _nature = [
    '\ud83d\udc36', '\ud83d\udc31', '\ud83d\udc2d', '\ud83d\udc39',
    '\ud83d\udc30', '\ud83e\udd8a', '\ud83d\udc3b', '\ud83d\udc3c',
    '\ud83d\udc28', '\ud83d\udc2f', '\ud83e\udd81', '\ud83d\udc2e',
    '\ud83d\udc37', '\ud83d\udc38', '\ud83d\udc35', '\ud83d\udc12',
  ];

  static const _food = [
    '\ud83c\udf4e', '\ud83c\udf4a', '\ud83c\udf4b', '\ud83c\udf4c',
    '\ud83c\udf49', '\ud83c\udf47', '\ud83c\udf53', '\ud83e\uded0',
    '\ud83c\udf51', '\ud83c\udf52', '\ud83c\udf55', '\ud83c\udf54',
    '\ud83c\udf2e', '\ud83c\udf2f', '\ud83e\udd59', '\ud83c\udf5e',
  ];

  static const _objects = [
    '\ud83d\udcbb', '\ud83d\udcf1', '\u2328\ufe0f', '\ud83d\udda5\ufe0f',
    '\ud83d\udcf7', '\ud83d\udcf8', '\ud83c\udfa5', '\ud83d\udcfd\ufe0f',
    '\ud83d\udcde', '\ud83d\udce1', '\ud83d\udcfa', '\ud83d\udcfb',
    '\ud83d\udd0a', '\ud83d\udd14', '\ud83c\udfb5', '\ud83c\udfb6',
  ];

  static const _symbols = [
    '\u2764\ufe0f', '\ud83e\udde1', '\ud83d\udc9b', '\ud83d\udc9a',
    '\ud83d\udc99', '\ud83d\udc9c', '\ud83e\udd0e', '\ud83d\udda4',
    '\u2b50', '\ud83c\udf1f', '\u2728', '\ud83d\udcab',
    '\u2705', '\u274c', '\u2753', '\u2757',
  ];

  static const _emojiNames = <String, String>{
    '\ud83d\udc4d': 'thumbsup thumbs up like yes',
    '\ud83d\udd25': 'fire hot flame',
    '\ud83d\udc40': 'eyes look see watching',
    '\u2764\ufe0f': 'heart love red',
    '\ud83d\ude02': 'joy laugh crying tears',
    '\ud83c\udf89': 'tada party celebrate',
    '\u2705': 'check done complete',
    '\ud83d\udcaf': 'hundred perfect',
    '\ud83d\ude4f': 'pray thanks please',
    '\ud83e\udd14': 'thinking hmm',
    '\ud83d\ude0d': 'heart eyes love',
    '\ud83d\udc4f': 'clap applause',
    '\ud83d\ude80': 'rocket launch ship',
    '\ud83d\ude00': 'grinning happy smile',
    '\ud83d\ude42': 'slight smile',
    '\ud83d\ude09': 'wink',
    '\ud83d\ude0a': 'blush smile',
  };
}

/// Shows the emoji picker as a dialog/overlay.
Future<String?> showEmojiPicker(BuildContext context) {
  return showDialog<String>(
    context: context,
    barrierColor: Colors.transparent,
    builder: (ctx) => Stack(
      children: [
        // Dismiss on tap outside
        GestureDetector(
          onTap: () => Navigator.pop(ctx),
          child: Container(color: Colors.transparent),
        ),
        Positioned(
          bottom: 80,
          right: 20,
          child: GloamEmojiPicker(
            onSelect: (emoji) => Navigator.pop(ctx, emoji),
          ),
        ),
      ],
    ),
  );
}
