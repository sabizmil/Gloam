import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme/color_tokens.dart';
import '../theme/spacing.dart';
import '../../features/rooms/presentation/providers/room_list_provider.dart';
import '../../features/chat/presentation/providers/timeline_provider.dart';
import '../../widgets/gloam_avatar.dart';

/// Shows the quick switcher overlay (Cmd/Ctrl+K).
Future<void> showQuickSwitcher(BuildContext context, WidgetRef ref) async {
  final result = await showDialog<String>(
    context: context,
    barrierColor: GloamColors.overlay,
    builder: (_) => const _QuickSwitcherDialog(),
  );

  if (result != null) {
    ref.read(selectedRoomProvider.notifier).state = result;
  }
}

class _QuickSwitcherDialog extends ConsumerStatefulWidget {
  const _QuickSwitcherDialog();

  @override
  ConsumerState<_QuickSwitcherDialog> createState() =>
      _QuickSwitcherDialogState();
}

class _QuickSwitcherDialogState extends ConsumerState<_QuickSwitcherDialog> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  int _selectedIndex = 0;

  @override
  void initState() {
    super.initState();
    _focusNode.requestFocus();
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  List<RoomListItem> _getFilteredRooms(List<RoomListItem> rooms) {
    final query = _controller.text.toLowerCase();
    if (query.isEmpty) return rooms.take(10).toList();
    return rooms
        .where((r) => r.displayName.toLowerCase().contains(query))
        .take(10)
        .toList();
  }

  void _select(String roomId) {
    Navigator.pop(context, roomId);
  }

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      setState(() => _selectedIndex++);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      setState(() {
        if (_selectedIndex > 0) _selectedIndex--;
      });
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.enter) {
      final roomsAsync = ref.read(roomListProvider);
      roomsAsync.whenData((rooms) {
        final filtered = _getFilteredRooms(rooms);
        if (_selectedIndex < filtered.length) {
          _select(filtered[_selectedIndex].roomId);
        }
      });
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      Navigator.pop(context);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final roomsAsync = ref.watch(roomListProvider);

    return Center(
      child: Material(
        color: Colors.transparent,
        child: Container(
          width: 560,
          constraints: const BoxConstraints(maxHeight: 440),
          decoration: BoxDecoration(
            color: GloamColors.bgSurface,
            borderRadius: BorderRadius.circular(GloamSpacing.radiusLg),
            border: Border.all(color: GloamColors.border),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF0A1A0E).withValues(alpha: 0.5),
                blurRadius: 80,
                offset: const Offset(0, 16),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Search input
              Container(
                height: 52,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                decoration: const BoxDecoration(
                  border: Border(
                    bottom: BorderSide(color: GloamColors.border),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.search,
                        size: 18, color: GloamColors.textTertiary),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Focus(
                        onKeyEvent: _handleKey,
                        child: TextField(
                          controller: _controller,
                          focusNode: _focusNode,
                          onChanged: (_) =>
                              setState(() => _selectedIndex = 0),
                          style: GoogleFonts.inter(
                            fontSize: 15,
                            color: GloamColors.textPrimary,
                          ),
                          decoration: InputDecoration(
                            hintText: 'search rooms and people...',
                            hintStyle: GoogleFonts.inter(
                              fontSize: 15,
                              color: GloamColors.textTertiary,
                            ),
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                            contentPadding: EdgeInsets.zero,
                            isDense: true,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // Results
              roomsAsync.when(
                loading: () => const SizedBox(height: 60),
                error: (e, s) => const SizedBox(height: 60),
                data: (rooms) {
                  final filtered = _getFilteredRooms(rooms);
                  if (filtered.isEmpty) {
                    return Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        '// no matches',
                        style: GoogleFonts.jetBrainsMono(
                          fontSize: 11,
                          color: GloamColors.textTertiary,
                        ),
                      ),
                    );
                  }

                  // Clamp selected index
                  if (_selectedIndex >= filtered.length) {
                    _selectedIndex = filtered.length - 1;
                  }

                  // Split into channels and DMs
                  final channels =
                      filtered.where((r) => !r.isDirect).toList();
                  final dms = filtered.where((r) => r.isDirect).toList();

                  return Flexible(
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: ListView(
                        shrinkWrap: true,
                        children: [
                          if (channels.isNotEmpty) ...[
                            Padding(
                              padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
                              child: Text(
                                '// channels',
                                style: GoogleFonts.jetBrainsMono(
                                  fontSize: 10,
                                  color: GloamColors.textTertiary,
                                  letterSpacing: 1,
                                ),
                              ),
                            ),
                            ...channels.map((r) {
                              final idx = filtered.indexOf(r);
                              return _ResultTile(
                                room: r,
                                isSelected: idx == _selectedIndex,
                                onTap: () => _select(r.roomId),
                              );
                            }),
                          ],
                          if (dms.isNotEmpty) ...[
                            Padding(
                              padding: const EdgeInsets.fromLTRB(
                                  8, 8, 8, 4),
                              child: Text(
                                '// people',
                                style: GoogleFonts.jetBrainsMono(
                                  fontSize: 10,
                                  color: GloamColors.textTertiary,
                                  letterSpacing: 1,
                                ),
                              ),
                            ),
                            ...dms.map((r) {
                              final idx = filtered.indexOf(r);
                              return _ResultTile(
                                room: r,
                                isSelected: idx == _selectedIndex,
                                onTap: () => _select(r.roomId),
                              );
                            }),
                          ],
                        ],
                      ),
                    ),
                  );
                },
              ),

              // Footer hints
              Container(
                height: 36,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                decoration: const BoxDecoration(
                  border: Border(
                    top: BorderSide(color: GloamColors.border),
                  ),
                ),
                child: Row(
                  children: [
                    _Hint('\u2191\u2193', 'navigate'),
                    const SizedBox(width: 16),
                    _Hint('\u21b5', 'open'),
                    const SizedBox(width: 16),
                    _Hint('esc', 'close'),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ResultTile extends StatelessWidget {
  const _ResultTile({
    required this.room,
    required this.isSelected,
    required this.onTap,
  });

  final RoomListItem room;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: isSelected ? GloamColors.bgElevated : Colors.transparent,
      borderRadius: BorderRadius.circular(GloamSpacing.radiusSm),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(GloamSpacing.radiusSm),
        child: Padding(
          padding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              if (room.isDirect)
                GloamAvatar(displayName: room.displayName, size: 28)
              else
                Text(
                  '#',
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 16,
                    color: isSelected
                        ? GloamColors.accent
                        : GloamColors.textTertiary,
                  ),
                ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  room.displayName,
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    fontWeight:
                        isSelected ? FontWeight.w500 : FontWeight.w400,
                    color: isSelected
                        ? GloamColors.textPrimary
                        : GloamColors.textSecondary,
                  ),
                ),
              ),
              if (isSelected)
                Text(
                  '\u21b5',
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 14,
                    color: GloamColors.textTertiary,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Hint extends StatelessWidget {
  const _Hint(this.key_, this.label);
  final String key_;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          key_,
          style: GoogleFonts.jetBrainsMono(
              fontSize: 10, color: GloamColors.textTertiary),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: GoogleFonts.jetBrainsMono(
              fontSize: 10, color: GloamColors.textTertiary),
        ),
      ],
    );
  }
}
