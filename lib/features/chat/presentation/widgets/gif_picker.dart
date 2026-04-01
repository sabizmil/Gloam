import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../app/theme/gloam_theme_ext.dart';
import '../../../../app/theme/spacing.dart';
import '../../../../services/klipy_service.dart';

/// GIF & Sticker picker powered by Klipy.
class GifPicker extends ConsumerStatefulWidget {
  const GifPicker({
    super.key,
    required this.onSelect,
    this.width = 380,
  });

  final void Function(KlipyItem item) onSelect;
  final double width;

  @override
  ConsumerState<GifPicker> createState() => _GifPickerState();
}

class _GifPickerState extends ConsumerState<GifPicker> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  final _scrollController = ScrollController();
  Timer? _debounce;

  String _type = 'gifs'; // gifs or stickers
  String _query = '';
  List<KlipyItem> _items = [];
  bool _loading = true;
  int _page = 1;
  bool _hasMore = true;

  @override
  void initState() {
    super.initState();
    _focusNode.requestFocus();
    _scrollController.addListener(_onScroll);
    _loadTrending();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    _focusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_hasMore || _loading) return;
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      _loadMore();
    }
  }

  Future<void> _loadTrending() async {
    setState(() {
      _loading = true;
      _page = 1;
    });
    final service = ref.read(klipyServiceProvider);
    final items = await service.trending(type: _type);
    if (mounted) {
      setState(() {
        _items = items;
        _loading = false;
        _hasMore = items.length >= 24;
      });
    }
  }

  Future<void> _searchItems(String query) async {
    setState(() {
      _loading = true;
      _page = 1;
    });
    final service = ref.read(klipyServiceProvider);
    final items = await service.search(query, type: _type);
    if (mounted) {
      setState(() {
        _items = items;
        _loading = false;
        _hasMore = items.length >= 24;
      });
    }
  }

  Future<void> _loadMore() async {
    if (_loading) return;
    setState(() => _loading = true);
    _page++;
    final service = ref.read(klipyServiceProvider);
    final items = _query.isEmpty
        ? await service.trending(type: _type, page: _page)
        : await service.search(_query, type: _type, page: _page);
    if (mounted) {
      setState(() {
        _items.addAll(items);
        _loading = false;
        _hasMore = items.length >= 24;
      });
    }
  }

  void _onQueryChanged(String query) {
    _debounce?.cancel();
    _query = query;
    if (query.trim().isEmpty) {
      _loadTrending();
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 300), () {
      _searchItems(query);
    });
  }

  void _switchType(String type) {
    if (_type == type) return;
    _type = type;
    _controller.clear();
    _query = '';
    _loadTrending();
  }

  void _selectItem(KlipyItem item) {
    ref.read(klipyServiceProvider).share(item.slug, type: _type);
    widget.onSelect(item);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.gloam;

    return Container(
      width: widget.width,
      height: 500,
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
          // ── Tab bar ──
          _buildTabs(colors),

          // ── Search field ──
          _buildSearchField(colors),

          Divider(height: 1, color: colors.border),

          // ── Grid area ──
          Expanded(
            child: _loading && _items.isEmpty
                ? Center(
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: colors.accent,
                      ),
                    ),
                  )
                : _items.isEmpty
                    ? Center(
                        child: Text(
                          '// no results',
                          style: GoogleFonts.jetBrainsMono(
                            fontSize: 11,
                            color: colors.textTertiary,
                          ),
                        ),
                      )
                    : _buildGrid(colors),
          ),

          // ── Footer ──
          Divider(height: 1, color: colors.border),
          Container(
            height: 28,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            alignment: Alignment.centerRight,
            child: Text(
              'powered by KLIPY',
              style: GoogleFonts.jetBrainsMono(
                fontSize: 9,
                color: colors.textTertiary,
                letterSpacing: 0.5,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabs(dynamic colors) {
    return Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          _TabButton(
            label: 'GIFs',
            isActive: _type == 'gifs',
            onTap: () => _switchType('gifs'),
          ),
          const SizedBox(width: 4),
          _TabButton(
            label: 'stickers',
            isActive: _type == 'stickers',
            onTap: () => _switchType('stickers'),
          ),
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
              onChanged: _onQueryChanged,
              style: GoogleFonts.inter(
                fontSize: 13,
                color: colors.textPrimary,
              ),
              decoration: InputDecoration(
                hintText: 'Search KLIPY',
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
                _onQueryChanged('');
              },
              child: Icon(Icons.close,
                  size: 14, color: colors.textTertiary),
            ),
        ],
      ),
    );
  }

  Widget _buildGrid(dynamic colors) {
    // Masonry-style: split items into 2 columns
    final col1 = <KlipyItem>[];
    final col2 = <KlipyItem>[];
    double h1 = 0, h2 = 0;

    for (final item in _items) {
      final aspect = item.previewWidth > 0
          ? item.previewHeight / item.previewWidth
          : 1.0;
      if (h1 <= h2) {
        col1.add(item);
        h1 += aspect;
      } else {
        col2.add(item);
        h2 += aspect;
      }
    }

    return SingleChildScrollView(
      controller: _scrollController,
      padding: const EdgeInsets.all(6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: _buildColumn(col1, colors)),
          const SizedBox(width: 6),
          Expanded(child: _buildColumn(col2, colors)),
        ],
      ),
    );
  }

  Widget _buildColumn(List<KlipyItem> items, dynamic colors) {
    return Column(
      children: items.map((item) {
        final aspect = item.previewWidth > 0
            ? item.previewHeight / item.previewWidth
            : 1.0;
        return Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(6),
            child: InkWell(
              onTap: () => _selectItem(item),
              mouseCursor: SystemMouseCursors.click,
              hoverColor: colors.border.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(6),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: AspectRatio(
                  aspectRatio: 1 / aspect,
                  child: Image.network(
                    item.previewUrl,
                    fit: BoxFit.cover,
                    loadingBuilder: (_, child, progress) {
                      if (progress == null) return child;
                      return Container(color: colors.bgElevated);
                    },
                    errorBuilder: (_, __, ___) => Container(
                      color: colors.bgElevated,
                      child: Center(
                        child: Icon(Icons.broken_image_outlined,
                            size: 16, color: colors.textTertiary),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

class _TabButton extends StatelessWidget {
  const _TabButton({
    required this.label,
    required this.isActive,
    required this.onTap,
  });

  final String label;
  final bool isActive;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.gloam;
    return GestureDetector(
      onTap: onTap,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
            color: isActive ? colors.bgElevated : null,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            label,
            style: GoogleFonts.jetBrainsMono(
              fontSize: 11,
              fontWeight: isActive ? FontWeight.w500 : FontWeight.normal,
              color: isActive ? colors.accent : colors.textTertiary,
              letterSpacing: 0.5,
            ),
          ),
        ),
      ),
    );
  }
}

/// Shows the GIF picker as a positioned popup.
Future<KlipyItem?> showGifPicker(BuildContext context) {
  return showDialog<KlipyItem>(
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
            child: GifPicker(
              onSelect: (item) => Navigator.pop(ctx, item),
            ),
          ),
        ),
      ],
    ),
  );
}
