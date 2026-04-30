import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../theme/gloam_color_extension.dart';
import '../../theme/gloam_theme_ext.dart';
import '../../theme/spacing.dart';
import '../../theme/theme_preferences.dart';
import '../../theme/theme_variants.dart';
import '../../../features/chat/presentation/providers/timeline_provider.dart';
import '../../../features/rooms/presentation/providers/room_list_provider.dart';
import '../../../features/rooms/presentation/providers/space_hierarchy_provider.dart';
import '../../../services/matrix_service.dart';
import '../../../widgets/gloam_avatar.dart';
import 'palette_actions.dart';
import 'palette_search.dart';
import 'palette_usage.dart';

/// Shows the command palette overlay (⌘K / Ctrl+K + top-strip search pill).
///
/// Uses a transparent route barrier and draws its own dim overlay inside the
/// dialog so the theme-preview-on-navigate feature can re-tint the backdrop
/// in real time (a route-level barrierColor is captured once at push and
/// can't react to theme changes).
Future<void> showCommandPalette(BuildContext context, WidgetRef ref) async {
  await showDialog<void>(
    context: context,
    barrierColor: Colors.transparent,
    builder: (_) => const _CommandPaletteDialog(),
  );
}

const int _perSectionCap = 5;

/// Discriminator across all selectable palette items.
enum _Kind { recent, suggested, channel, person, message, member, action, theme, setting, more }

/// Flat list item used for keyboard navigation. Headers are filtered out.
class _Item {
  const _Item({
    required this.kind,
    this.room,
    this.message,
    this.member,
    this.action,
    this.moreSection,
    this.moreCount = 0,
  });

  final _Kind kind;
  final RoomListItem? room;
  final MessageResult? message;
  final MemberResult? member;
  final PaletteAction? action;
  final _Kind? moreSection; // for kind == _Kind.more
  final int moreCount;
}

class _CommandPaletteDialog extends ConsumerStatefulWidget {
  const _CommandPaletteDialog();

  @override
  ConsumerState<_CommandPaletteDialog> createState() =>
      _CommandPaletteDialogState();
}

class _CommandPaletteDialogState
    extends ConsumerState<_CommandPaletteDialog> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  final _scrollController = ScrollController();
  Timer? _msgDebounce;

  int _selectedIndex = 0;
  final Set<_Kind> _expanded = {};

  // Theme preview-on-navigate: snapshot the variant at open time and restore
  // it on close unless the user explicitly committed a theme change.
  late final ThemeVariant _originalVariant;
  bool _themeCommitted = false;

  @override
  void initState() {
    super.initState();
    _focusNode.requestFocus();
    _controller.addListener(_onQueryChanged);
    _originalVariant = ref.read(themePreferencesProvider).variant;
  }

  @override
  void dispose() {
    if (!_themeCommitted) {
      final notifier = ref.read(themePreferencesProvider.notifier);
      if (ref.read(themePreferencesProvider).variant != _originalVariant) {
        notifier.setVariant(_originalVariant);
      }
    }
    _msgDebounce?.cancel();
    _controller.dispose();
    _focusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  // ── Theme preview ──

  ThemeVariant? _variantFromActionId(String id) {
    if (!id.startsWith('theme-')) return null;
    final name = id.substring('theme-'.length);
    for (final v in ThemeVariant.values) {
      if (v.name == name) return v;
    }
    return null;
  }

  /// Apply the focused item's theme as a live preview. If the focused item
  /// isn't a theme, restore the original variant so previews don't linger.
  void _syncPreview(_Item? focused) {
    final notifier = ref.read(themePreferencesProvider.notifier);
    final current = ref.read(themePreferencesProvider).variant;
    if (focused != null && focused.kind == _Kind.theme) {
      final variant = _variantFromActionId(focused.action!.id);
      if (variant != null && variant != current) {
        notifier.setVariant(variant);
      }
    } else if (current != _originalVariant) {
      notifier.setVariant(_originalVariant);
    }
  }

  String get _query => _controller.text.trim();

  void _onQueryChanged() {
    setState(() {
      _selectedIndex = 0;
      _expanded.clear();
    });
    // Debounce the (expensive) message timeline scan; rooms/people/actions
    // re-derive from in-memory state every frame, no debounce needed.
    _msgDebounce?.cancel();
    _msgDebounce = Timer(const Duration(milliseconds: 150), () {
      ref.read(paletteMessageQueryProvider.notifier).state = _query;
    });
    // After rebuild settles, sync preview to whatever ends up at index 0.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final layout = _buildLayout();
      _syncPreview(layout.items.isNotEmpty ? layout.items.first : null);
    });
  }

  List<RoomListItem> _allRooms() {
    final raw = ref.read(roomListProvider).valueOrNull ?? const [];
    return raw.map((r) {
      if (r.displayName != 'Empty chat') return r;
      final name = ref.read(hierarchyRoomNameProvider(r.roomId));
      return name != null ? r.withDisplayName(name) : r;
    }).toList();
  }

  // ── Section builders ──

  List<RoomListItem> _channels(String q) {
    final rooms = _allRooms()
        .where((r) => !r.isDirect && !r.isInvite)
        .toList();
    if (q.isEmpty) return rooms;
    final lower = q.toLowerCase();
    return rooms
        .where((r) => r.displayName.toLowerCase().contains(lower))
        .toList();
  }

  List<RoomListItem> _people(String q) {
    final rooms = _allRooms()
        .where((r) => r.isDirect && !r.isInvite)
        .toList();
    if (q.isEmpty) return rooms;
    final lower = q.toLowerCase();
    return rooms
        .where((r) => r.displayName.toLowerCase().contains(lower))
        .toList();
  }

  List<PaletteAction> _actions(String q) {
    final available = paletteActions.where((a) {
      if (a.section != PaletteActionSection.action) return false;
      if (a.requiresActiveRoom &&
          ref.read(selectedRoomProvider) == null) {
        return false;
      }
      return true;
    });
    if (q.isEmpty) return available.toList();
    final lower = q.toLowerCase();
    return available
        .where((a) => a.label.toLowerCase().contains(lower))
        .toList();
  }

  List<PaletteAction> _themes(String q) {
    final available = paletteActions
        .where((a) => a.section == PaletteActionSection.theme);
    if (q.isEmpty) return const [];
    final lower = q.toLowerCase();
    return available
        .where((a) => a.label.toLowerCase().contains(lower))
        .toList();
  }

  List<PaletteAction> _settings(String q) {
    final available = paletteActions.where(
        (a) => a.section == PaletteActionSection.settings);
    if (q.isEmpty) return const [];
    final lower = q.toLowerCase();
    return available
        .where((a) => a.label.toLowerCase().contains(lower))
        .toList();
  }

  // ── Build flat item list + section structure ──

  ({List<_SectionData> sections, List<_Item> items}) _buildLayout() {
    final q = _query;
    final sections = <_SectionData>[];
    final items = <_Item>[];

    void addSection(_SectionData section) {
      if (section.items.isEmpty) return;
      sections.add(section);
      items.addAll(section.items);
      if (section.hasMore) {
        final moreItem = _Item(
          kind: _Kind.more,
          moreSection: section.kind,
          moreCount: section.totalCount - section.items.length,
        );
        sections.last.items.add(moreItem);
        items.add(moreItem);
      }
    }

    if (q.isEmpty) {
      // Zero-state: recent rooms + suggested actions.
      final usage = ref.read(paletteUsageProvider);
      final allRooms = _allRooms();
      final byId = {for (final r in allRooms) r.roomId: r};
      final recent = usage
          .recentRoomIds(limit: 3)
          .map((id) => byId[id])
          .whereType<RoomListItem>()
          .toList();
      addSection(_buildRoomSection(
        kind: _Kind.recent,
        header: '// recent',
        rooms: recent,
        cap: 3,
      ));

      final allAvailableActions = _actions('');
      final usedIds = usage.topActionIds(limit: 3);
      final ordered = [
        ...usedIds
            .map((id) => allAvailableActions.firstWhere(
                  (a) => a.id == id,
                  orElse: () => paletteActions.first,
                ))
            .where((a) => allAvailableActions.contains(a)),
        ...allAvailableActions.where((a) => !usedIds.contains(a.id)),
      ];
      final suggested = ordered.take(3).toList();
      addSection(_buildActionSection(
        kind: _Kind.suggested,
        header: '// suggested actions',
        actions: suggested,
        cap: 3,
      ));
      return (sections: sections, items: items);
    }

    // Query state.
    addSection(_buildRoomSection(
      kind: _Kind.channel,
      header: '// channels',
      rooms: _channels(q),
    ));
    addSection(_buildRoomSection(
      kind: _Kind.person,
      header: '// people',
      rooms: _people(q),
    ));

    // Messages — async via FutureProvider.
    final msgAsync = ref.watch(paletteMessageResultsProvider);
    final messages = msgAsync.valueOrNull ?? const <MessageResult>[];
    addSection(_buildMessageSection(messages));

    // Members — sync.
    final client = ref.read(matrixServiceProvider).client;
    final members =
        client != null ? searchMembers(client, q) : const <MemberResult>[];
    addSection(_buildMemberSection(members));

    addSection(_buildActionSection(
      kind: _Kind.action,
      header: '// actions',
      actions: _actions(q),
    ));
    addSection(_buildActionSection(
      kind: _Kind.theme,
      header: '// themes',
      actions: _themes(q),
    ));
    addSection(_buildActionSection(
      kind: _Kind.setting,
      header: '// settings',
      actions: _settings(q),
    ));

    return (sections: sections, items: items);
  }

  _SectionData _buildRoomSection({
    required _Kind kind,
    required String header,
    required List<RoomListItem> rooms,
    int? cap,
  }) {
    final c = cap ?? _perSectionCap;
    final visible = _expanded.contains(kind) ? rooms : rooms.take(c).toList();
    return _SectionData(
      kind: kind,
      header: header,
      totalCount: rooms.length,
      items: visible
          .map((r) => _Item(
                kind: kind == _Kind.person ? _Kind.person : _Kind.channel,
                room: r,
              ))
          .toList(),
      hasMore: rooms.length > visible.length,
    );
  }

  _SectionData _buildMessageSection(List<MessageResult> results) {
    final visible = _expanded.contains(_Kind.message)
        ? results
        : results.take(_perSectionCap).toList();
    return _SectionData(
      kind: _Kind.message,
      header: '// messages',
      totalCount: results.length,
      items: visible
          .map((r) => _Item(kind: _Kind.message, message: r))
          .toList(),
      hasMore: results.length > visible.length,
    );
  }

  _SectionData _buildMemberSection(List<MemberResult> results) {
    final visible = _expanded.contains(_Kind.member)
        ? results
        : results.take(_perSectionCap).toList();
    return _SectionData(
      kind: _Kind.member,
      header: '// members',
      totalCount: results.length,
      items: visible
          .map((r) => _Item(kind: _Kind.member, member: r))
          .toList(),
      hasMore: results.length > visible.length,
    );
  }

  _SectionData _buildActionSection({
    required _Kind kind,
    required String header,
    required List<PaletteAction> actions,
    int? cap,
  }) {
    final c = cap ?? _perSectionCap;
    final visible =
        _expanded.contains(kind) ? actions : actions.take(c).toList();
    return _SectionData(
      kind: kind,
      header: header,
      totalCount: actions.length,
      items: visible
          .map((a) => _Item(kind: kind, action: a))
          .toList(),
      hasMore: actions.length > visible.length,
    );
  }

  // ── Invocation ──

  Future<void> _invoke(_Item item) async {
    switch (item.kind) {
      case _Kind.recent:
      case _Kind.channel:
      case _Kind.person:
        final id = item.room!.roomId;
        ref.read(selectedRoomProvider.notifier).state = id;
        ref.read(paletteUsageProvider.notifier).recordRoomVisit(id);
        if (mounted) Navigator.pop(context);
      case _Kind.message:
        final id = item.message!.room.id;
        ref.read(selectedRoomProvider.notifier).state = id;
        ref.read(paletteUsageProvider.notifier).recordRoomVisit(id);
        if (mounted) Navigator.pop(context);
      case _Kind.member:
        openMember(ref, item.member!);
        if (mounted) Navigator.pop(context);
      case _Kind.suggested:
      case _Kind.action:
      case _Kind.theme:
      case _Kind.setting:
        final action = item.action!;
        // Lock in the previewed theme (or any explicit theme cycle) so dispose
        // doesn't snap back to _originalVariant.
        if (item.kind == _Kind.theme || action.id == 'toggle-theme') {
          _themeCommitted = true;
        }
        ref
            .read(paletteUsageProvider.notifier)
            .recordActionInvocation(action.id);
        if (mounted) Navigator.pop(context);
        // Run after pop so the action's UI (dialogs/snackbars) attaches to
        // the surviving navigator/scaffold.
        if (mounted) await action.run(context, ref);
      case _Kind.more:
        setState(() => _expanded.add(item.moreSection!));
    }
  }


  // ── Keyboard ──

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final layout = _buildLayout();
    final items = layout.items;
    if (items.isEmpty) return KeyEventResult.ignored;

    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      setState(() {
        _selectedIndex = (_selectedIndex + 1) % items.length;
      });
      _syncPreview(items[_selectedIndex]);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      setState(() {
        _selectedIndex = (_selectedIndex - 1 + items.length) % items.length;
      });
      _syncPreview(items[_selectedIndex]);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.enter) {
      if (_selectedIndex < items.length) _invoke(items[_selectedIndex]);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      Navigator.pop(context);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  // ── Build ──

  @override
  Widget build(BuildContext context) {
    final colors = context.gloam;
    final layout = _buildLayout();
    final items = layout.items;
    if (items.isNotEmpty && _selectedIndex >= items.length) {
      _selectedIndex = items.length - 1;
    }

    return Stack(
      children: [
        // Theme-reactive barrier — rebuilds with the rest of the dialog so
        // the preview flow can re-tint the backdrop live.
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => Navigator.of(context).maybePop(),
            child: ColoredBox(color: colors.overlay),
          ),
        ),
        Center(
          child: Material(
            color: Colors.transparent,
            child: Container(
              width: 560,
              constraints: const BoxConstraints(maxHeight: 560),
              decoration: BoxDecoration(
                color: colors.bgSurface,
                borderRadius: BorderRadius.circular(GloamSpacing.radiusLg),
                border: Border.all(color: colors.border),
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
                  _buildInput(colors),
                  if (layout.sections.isEmpty)
                    _buildEmpty(colors)
                  else
                    Flexible(child: _buildResults(layout, items)),
                  _buildFooter(colors),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildInput(GloamColorExtension colors) {
    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: colors.border)),
      ),
      child: Row(
        children: [
          Icon(Icons.search, size: 18, color: colors.textTertiary),
          const SizedBox(width: 10),
          Expanded(
            child: Focus(
              onKeyEvent: _onKey,
              child: TextField(
                controller: _controller,
                focusNode: _focusNode,
                style: GoogleFonts.inter(
                  fontSize: 15,
                  color: colors.textPrimary,
                ),
                decoration: InputDecoration(
                  hintText: 'Search or jump to anything…',
                  hintStyle: GoogleFonts.inter(
                    fontSize: 15,
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
          ),
        ],
      ),
    );
  }

  Widget _buildEmpty(GloamColorExtension colors) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Text(
        '// no matches',
        style: GoogleFonts.jetBrainsMono(
          fontSize: 11,
          color: colors.textTertiary,
        ),
      ),
    );
  }

  Widget _buildResults(
      ({List<_SectionData> sections, List<_Item> items}) layout,
      List<_Item> items) {
    final colors = context.gloam;
    return ListView(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(vertical: 8),
      shrinkWrap: true,
      children: [
        for (final section in layout.sections) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Text(
              section.header,
              style: GoogleFonts.jetBrainsMono(
                fontSize: 10,
                color: colors.textTertiary,
                letterSpacing: 1,
              ),
            ),
          ),
          for (final item in section.items)
            _buildRow(item, items.indexOf(item) == _selectedIndex, colors),
        ],
      ],
    );
  }

  Widget _buildRow(
      _Item item, bool selected, GloamColorExtension colors) {
    final bg = selected ? colors.bgElevated : Colors.transparent;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Material(
        color: bg,
        borderRadius: BorderRadius.circular(GloamSpacing.radiusSm),
        child: InkWell(
          onTap: () => _invoke(item),
          borderRadius: BorderRadius.circular(GloamSpacing.radiusSm),
          child: Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: _rowContent(item, selected, colors),
          ),
        ),
      ),
    );
  }

  Widget _rowContent(
      _Item item, bool selected, GloamColorExtension colors) {
    switch (item.kind) {
      case _Kind.recent:
      case _Kind.channel:
        final r = item.room!;
        return Row(
          children: [
            Text('#',
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 16,
                  color:
                      selected ? colors.accent : colors.textTertiary,
                )),
            const SizedBox(width: 10),
            Expanded(child: _label(r.displayName, selected, colors)),
            if (selected) _enterGlyph(colors),
          ],
        );
      case _Kind.person:
        final r = item.room!;
        return Row(
          children: [
            GloamAvatar(displayName: r.displayName, size: 24),
            const SizedBox(width: 10),
            Expanded(child: _label(r.displayName, selected, colors)),
            if (selected) _enterGlyph(colors),
          ],
        );
      case _Kind.message:
        final m = item.message!;
        return Row(
          children: [
            Icon(Icons.chat_bubble_outline,
                size: 14, color: colors.textTertiary),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    m.snippet,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      color: selected
                          ? colors.textPrimary
                          : colors.textSecondary,
                    ),
                  ),
                  Text(
                    '#${m.room.getLocalizedDisplayname()}  ·  ${_relTime(m.event.originServerTs)}',
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 10,
                      color: colors.textTertiary,
                    ),
                  ),
                ],
              ),
            ),
            if (selected) _enterGlyph(colors),
          ],
        );
      case _Kind.member:
        final mem = item.member!;
        return Row(
          children: [
            GloamAvatar(displayName: mem.displayName, size: 24),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _label(mem.displayName, selected, colors),
                  Text(
                    'in ${mem.contextRoom.getLocalizedDisplayname()}',
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 10,
                      color: colors.textTertiary,
                    ),
                  ),
                ],
              ),
            ),
            if (selected) _enterGlyph(colors),
          ],
        );
      case _Kind.suggested:
      case _Kind.action:
      case _Kind.theme:
      case _Kind.setting:
        final a = item.action!;
        return Row(
          children: [
            Icon(a.icon,
                size: 16,
                color:
                    selected ? colors.accent : colors.textTertiary),
            const SizedBox(width: 10),
            Expanded(child: _label(a.label, selected, colors)),
            if (a.shortcut != null)
              _shortcutChip(a.shortcut!, colors),
            if (selected) ...[
              const SizedBox(width: 8),
              _enterGlyph(colors),
            ],
          ],
        );
      case _Kind.more:
        return Row(
          children: [
            const SizedBox(width: 26),
            Text(
              'show ${item.moreCount} more',
              style: GoogleFonts.jetBrainsMono(
                fontSize: 11,
                color: colors.textTertiary,
              ),
            ),
          ],
        );
    }
  }

  Widget _label(
      String text, bool selected, GloamColorExtension colors) {
    return Text(
      text,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: GoogleFonts.inter(
        fontSize: 14,
        fontWeight: selected ? FontWeight.w500 : FontWeight.w400,
        color: selected ? colors.textPrimary : colors.textSecondary,
      ),
    );
  }

  Widget _enterGlyph(GloamColorExtension colors) => Text(
        '↵',
        style: GoogleFonts.jetBrainsMono(
            fontSize: 14, color: colors.textTertiary),
      );

  Widget _shortcutChip(String label, GloamColorExtension colors) =>
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
        decoration: BoxDecoration(
          color: colors.bg,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: colors.borderSubtle),
        ),
        child: Text(
          label,
          style: GoogleFonts.jetBrainsMono(
            fontSize: 10,
            fontWeight: FontWeight.w500,
            color: colors.textTertiary,
            letterSpacing: 0.5,
          ),
        ),
      );

  Widget _buildFooter(GloamColorExtension colors) {
    return Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: colors.border)),
      ),
      child: Row(
        children: [
          _Hint('↑↓', 'navigate'),
          const SizedBox(width: 16),
          _Hint('↵', 'open'),
          const SizedBox(width: 16),
          _Hint('esc', 'close'),
        ],
      ),
    );
  }

  String _relTime(DateTime t) {
    final diff = DateTime.now().difference(t);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inHours < 1) return '${diff.inMinutes}m ago';
    if (diff.inDays < 1) return '${diff.inHours}h ago';
    if (diff.inDays < 30) return '${diff.inDays}d ago';
    return '${(diff.inDays / 30).floor()}mo ago';
  }
}

class _SectionData {
  _SectionData({
    required this.kind,
    required this.header,
    required this.totalCount,
    required this.items,
    required this.hasMore,
  });

  final _Kind kind;
  final String header;
  final int totalCount;
  final List<_Item> items;
  final bool hasMore;
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
              fontSize: 10, color: context.gloam.textTertiary),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: GoogleFonts.jetBrainsMono(
              fontSize: 10, color: context.gloam.textTertiary),
        ),
      ],
    );
  }
}

