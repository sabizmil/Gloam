import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../app/theme/gloam_theme_ext.dart';
import '../../../app/theme/spacing.dart';
import '../../../services/search_service.dart';
import '../../../widgets/gloam_avatar.dart';
import '../../chat/presentation/providers/timeline_provider.dart';

/// Full search view — replaces the chat area on desktop, pushed screen on mobile.
class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key, this.onSelectResult});
  final void Function(String roomId, String eventId)? onSelectResult;

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  Timer? _debounce;
  List<SearchResult> _results = [];
  List<String> _history = [];
  bool _searching = false;

  @override
  void initState() {
    super.initState();
    _focusNode.requestFocus();
    _loadHistory();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _loadHistory() async {
    final service = ref.read(searchServiceProvider);
    final history = await service.getHistory();
    if (mounted) setState(() => _history = history);
  }

  void _onQueryChanged(String query) {
    _debounce?.cancel();
    if (query.trim().isEmpty) {
      setState(() {
        _results = [];
        _searching = false;
      });
      return;
    }

    setState(() => _searching = true);
    _debounce = Timer(const Duration(milliseconds: 150), () => _search(query));
  }

  Future<void> _search(String query) async {
    final service = ref.read(searchServiceProvider);

    // Parse filters from query
    String? roomFilter;
    String? senderFilter;
    var searchText = query;

    final fromMatch = RegExp(r'from:(\S+)').firstMatch(query);
    if (fromMatch != null) {
      senderFilter = fromMatch.group(1);
      searchText = searchText.replaceFirst(fromMatch.group(0)!, '').trim();
    }

    final inMatch = RegExp(r'in:(\S+)').firstMatch(query);
    if (inMatch != null) {
      roomFilter = inMatch.group(1);
      searchText = searchText.replaceFirst(inMatch.group(0)!, '').trim();
    }

    if (searchText.isEmpty) {
      setState(() {
        _results = [];
        _searching = false;
      });
      return;
    }

    final results = await service.search(
      searchText,
      roomId: roomFilter,
      sender: senderFilter,
    );

    if (mounted) {
      setState(() {
        _results = results;
        _searching = false;
      });
    }

    await service.saveToHistory(query);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: context.gloam.bg,
      child: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(color: context.gloam.border),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Search input
                Container(
                  height: 44,
                  decoration: BoxDecoration(
                    color: context.gloam.bgSurface,
                    borderRadius: BorderRadius.circular(GloamSpacing.radiusMd),
                    border: Border.all(color: context.gloam.border),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  child: Row(
                    children: [
                      Icon(Icons.search,
                          size: 18, color: context.gloam.textTertiary),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          controller: _controller,
                          focusNode: _focusNode,
                          onChanged: _onQueryChanged,
                          style: GoogleFonts.inter(
                            fontSize: 15,
                            color: context.gloam.textPrimary,
                          ),
                          decoration: InputDecoration(
                            hintText: 'search messages...',
                            hintStyle: GoogleFonts.inter(
                              fontSize: 15,
                              color: context.gloam.textTertiary,
                            ),
                            border: InputBorder.none,
                            contentPadding: EdgeInsets.zero,
                            isDense: true,
                          ),
                        ),
                      ),
                      if (_controller.text.isNotEmpty)
                        GestureDetector(
                          onTap: () {
                            _controller.clear();
                            _onQueryChanged('');
                          },
                          child: Icon(Icons.close,
                              size: 16, color: context.gloam.textTertiary),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),

                // Filter hints
                Row(
                  children: [
                    _FilterChip(label: 'from:', onTap: () {
                      _controller.text = 'from: ${_controller.text}';
                      _controller.selection = TextSelection.collapsed(
                          offset: 'from: '.length);
                      _focusNode.requestFocus();
                    }),
                    const SizedBox(width: 6),
                    _FilterChip(label: 'in:', onTap: () {
                      _controller.text = 'in: ${_controller.text}';
                      _controller.selection = TextSelection.collapsed(
                          offset: 'in: '.length);
                      _focusNode.requestFocus();
                    }),
                    const SizedBox(width: 6),
                    _FilterChip(label: 'has:file', onTap: () {
                      _controller.text = '${_controller.text} has:file';
                      _focusNode.requestFocus();
                    }),
                  ],
                ),
              ],
            ),
          ),

          // Results or history
          Expanded(
            child: _controller.text.isEmpty
                ? _buildHistory()
                : _searching
                    ? Center(
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: context.gloam.accent,
                        ),
                      )
                    : _buildResults(),
          ),
        ],
      ),
    );
  }

  Widget _buildHistory() {
    if (_history.isEmpty) {
      return Center(
        child: Text(
          '// search across all your messages',
          style: GoogleFonts.jetBrainsMono(
            fontSize: 11,
            color: context.gloam.textTertiary,
            letterSpacing: 1,
          ),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          '// recent searches',
          style: GoogleFonts.jetBrainsMono(
            fontSize: 10,
            color: context.gloam.textTertiary,
            letterSpacing: 1,
          ),
        ),
        const SizedBox(height: 8),
        ..._history.map((q) => ListTile(
              dense: true,
              leading: Icon(Icons.history,
                  size: 16, color: context.gloam.textTertiary),
              title: Text(
                q,
                style: GoogleFonts.inter(
                  fontSize: 13,
                  color: context.gloam.textSecondary,
                ),
              ),
              onTap: () {
                _controller.text = q;
                _onQueryChanged(q);
              },
            )),
      ],
    );
  }

  Widget _buildResults() {
    if (_results.isEmpty) {
      return Center(
        child: Text(
          '// no messages found',
          style: GoogleFonts.jetBrainsMono(
            fontSize: 11,
            color: context.gloam.textTertiary,
            letterSpacing: 1,
          ),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: _results.length + 1,
      itemBuilder: (context, index) {
        if (index == 0) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 8, left: 4),
            child: Text(
              '${_results.length} result${_results.length == 1 ? '' : 's'}',
              style: GoogleFonts.jetBrainsMono(
                fontSize: 11,
                color: context.gloam.textTertiary,
                letterSpacing: 0.5,
              ),
            ),
          );
        }

        final result = _results[index - 1];
        return _SearchResultTile(
          result: result,
          query: _controller.text,
          onTap: () {
            ref.read(selectedRoomProvider.notifier).state = result.roomId;
            widget.onSelectResult?.call(result.roomId, result.eventId);
          },
        );
      },
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: context.gloam.border),
        ),
        child: Text(
          label,
          style: GoogleFonts.jetBrainsMono(
            fontSize: 10,
            color: context.gloam.textTertiary,
          ),
        ),
      ),
    );
  }
}

class _SearchResultTile extends StatelessWidget {
  const _SearchResultTile({
    required this.result,
    required this.query,
    required this.onTap,
  });

  final SearchResult result;
  final String query;
  final VoidCallback onTap;

  String _formatTime(DateTime ts) {
    final now = DateTime.now();
    final diff = now.difference(ts);
    if (diff.inDays == 0) {
      final h = ts.hour > 12 ? ts.hour - 12 : (ts.hour == 0 ? 12 : ts.hour);
      final period = ts.hour >= 12 ? 'pm' : 'am';
      return '${h}:${ts.minute.toString().padLeft(2, '0')} $period';
    }
    if (diff.inDays == 1) return 'yesterday';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${ts.month}/${ts.day}';
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(GloamSpacing.radiusMd),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(GloamSpacing.radiusMd),
              border: Border.all(color: context.gloam.borderSubtle),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    GloamAvatar(
                        displayName: result.senderName, size: 24),
                    const SizedBox(width: 8),
                    Text(
                      result.senderName,
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: context.gloam.textPrimary,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'in ${result.roomName}',
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: 10,
                        color: context.gloam.textTertiary,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      _formatTime(result.timestamp),
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: 10,
                        color: context.gloam.textTertiary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  result.body,
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    color: context.gloam.textSecondary,
                    height: 1.4,
                  ),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
