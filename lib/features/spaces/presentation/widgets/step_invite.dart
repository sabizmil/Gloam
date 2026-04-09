import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:matrix/matrix.dart';

import '../../../../app/theme/gloam_color_extension.dart';
import '../../../../app/theme/gloam_theme_ext.dart';
import '../../../../app/theme/spacing.dart';
import '../../../../services/matrix_service.dart';
import '../../../../widgets/gloam_avatar.dart';

/// A user that can be invited.
class _KnownUser {
  final String userId;
  final String? displayName;
  final Uri? avatarUrl;
  const _KnownUser({required this.userId, this.displayName, this.avatarUrl});
}

/// Step 3: Search users, assign roles, build invite list.
class StepInvite extends ConsumerStatefulWidget {
  const StepInvite({
    super.key,
    required this.invites,
    required this.displayNames,
    required this.onInvitesChanged,
  });

  final Map<String, int> invites; // userId -> powerLevel
  final Map<String, String> displayNames; // userId -> displayName
  final void Function(Map<String, int> invites, Map<String, String> names)
      onInvitesChanged;

  @override
  ConsumerState<StepInvite> createState() => _StepInviteState();
}

class _StepInviteState extends ConsumerState<StepInvite> {
  final _searchController = TextEditingController();
  final _focusNode = FocusNode();
  Timer? _debounce;
  List<_KnownUser> _knownUsers = [];
  List<_KnownUser> _searchResults = [];

  @override
  void initState() {
    super.initState();
    _buildKnownUsers();
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _buildKnownUsers() {
    final client = ref.read(matrixServiceProvider).client;
    if (client == null) return;

    final userMap = <String, _KnownUser>{};
    for (final room in client.rooms) {
      final members = room.states[EventTypes.RoomMember] ?? {};
      for (final entry in members.entries) {
        final userId = entry.key;
        if (userId == client.userID) continue;
        final content = entry.value.content;
        if (content['membership'] != 'join') continue;

        userMap.putIfAbsent(
          userId,
          () => _KnownUser(
            userId: userId,
            displayName: content['displayname'] as String?,
            avatarUrl: content['avatar_url'] != null
                ? Uri.tryParse(content['avatar_url'] as String)
                : null,
          ),
        );
      }
    }

    _knownUsers = userMap.values.toList()
      ..sort((a, b) => (a.displayName ?? a.userId)
          .toLowerCase()
          .compareTo((b.displayName ?? b.userId).toLowerCase()));
  }

  void _onSearchChanged() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () async {
      final query = _searchController.text.trim().toLowerCase();
      if (query.isEmpty) {
        setState(() => _searchResults = []);
        return;
      }

      // Filter out already-invited users
      final invitedIds = widget.invites.keys.toSet();

      final localResults = _knownUsers
          .where((u) =>
              !invitedIds.contains(u.userId) &&
              ((u.displayName?.toLowerCase().contains(query) ?? false) ||
                  u.userId.toLowerCase().contains(query)))
          .take(10)
          .toList();

      // Server directory search
      final client = ref.read(matrixServiceProvider).client;
      if (client != null && query.length >= 2) {
        try {
          final serverResults =
              await client.searchUserDirectory(query, limit: 10);
          final localIds = localResults.map((u) => u.userId).toSet();
          for (final user in serverResults.results) {
            if (user.userId == client.userID) continue;
            if (localIds.contains(user.userId)) continue;
            if (invitedIds.contains(user.userId)) continue;
            localResults.add(_KnownUser(
              userId: user.userId,
              displayName: user.displayName,
              avatarUrl: user.avatarUrl,
            ));
          }
        } catch (_) {}
      }

      if (mounted) {
        setState(() => _searchResults = localResults.take(10).toList());
      }
    });
  }

  void _addUser(_KnownUser user) {
    final newInvites = Map<String, int>.from(widget.invites);
    final newNames = Map<String, String>.from(widget.displayNames);
    newInvites[user.userId] = 0; // Default: Member
    newNames[user.userId] = user.displayName ?? user.userId;
    widget.onInvitesChanged(newInvites, newNames);
    _searchController.clear();
    setState(() => _searchResults = []);
    _focusNode.requestFocus();
  }

  void _removeUser(String userId) {
    final newInvites = Map<String, int>.from(widget.invites);
    final newNames = Map<String, String>.from(widget.displayNames);
    newInvites.remove(userId);
    newNames.remove(userId);
    widget.onInvitesChanged(newInvites, newNames);
  }

  void _changeRole(String userId, int powerLevel) {
    final newInvites = Map<String, int>.from(widget.invites);
    newInvites[userId] = powerLevel;
    widget.onInvitesChanged(newInvites, widget.displayNames);
  }

  String _roleLabel(int powerLevel) {
    if (powerLevel >= 100) return 'Admin';
    if (powerLevel >= 50) return 'Mod';
    return 'Member';
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.gloam;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Search bar
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
          child: TextField(
            controller: _searchController,
            focusNode: _focusNode,
            style: GoogleFonts.inter(
              fontSize: 13,
              color: colors.textPrimary,
            ),
            decoration: InputDecoration(
              hintText: 'Search for users to invite...',
              hintStyle: GoogleFonts.inter(
                fontSize: 13,
                color: colors.textTertiary,
              ),
              prefixIcon: Padding(
                padding: const EdgeInsets.only(left: 12, right: 8),
                child: Icon(Icons.search,
                    size: 18, color: colors.textTertiary),
              ),
              prefixIconConstraints:
                  const BoxConstraints(minWidth: 0, minHeight: 0),
              filled: true,
              fillColor: colors.bgElevated,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              border: OutlineInputBorder(
                borderRadius:
                    BorderRadius.circular(GloamSpacing.radiusMd),
                borderSide: BorderSide(color: colors.border),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius:
                    BorderRadius.circular(GloamSpacing.radiusMd),
                borderSide: BorderSide(color: colors.border),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius:
                    BorderRadius.circular(GloamSpacing.radiusMd),
                borderSide: BorderSide(color: colors.accent),
              ),
            ),
          ),
        ),

        // Selected users chips
        if (widget.invites.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '// invited (${widget.invites.length})',
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 10,
                    color: colors.textTertiary,
                    letterSpacing: 1,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: widget.invites.entries.map((entry) {
                    final name = widget.displayNames[entry.key] ?? entry.key;
                    return Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: colors.bgElevated,
                        borderRadius:
                            BorderRadius.circular(GloamSpacing.radiusSm),
                        border: Border.all(color: colors.border),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            name,
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              color: colors.textPrimary,
                            ),
                          ),
                          const SizedBox(width: 6),
                          // Role dropdown
                          PopupMenuButton<int>(
                            onSelected: (v) =>
                                _changeRole(entry.key, v),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(
                                minWidth: 0, minHeight: 0),
                            position: PopupMenuPosition.under,
                            color: colors.bgSurface,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(6),
                              side: BorderSide(color: colors.border),
                            ),
                            itemBuilder: (_) => [
                              _roleMenuItem(colors, 'Member', 0,
                                  entry.value == 0),
                              _roleMenuItem(colors, 'Moderator', 50,
                                  entry.value >= 50 && entry.value < 100),
                              _roleMenuItem(colors, 'Admin', 100,
                                  entry.value >= 100),
                            ],
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: entry.value >= 100
                                    ? colors.accentDim
                                    : entry.value >= 50
                                        ? const Color(0xFF1A2540)
                                        : Colors.transparent,
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(
                                  color: entry.value >= 100
                                      ? colors.accent
                                      : entry.value >= 50
                                          ? colors.info
                                          : colors.border,
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    _roleLabel(entry.value),
                                    style: GoogleFonts.jetBrainsMono(
                                      fontSize: 9,
                                      color: entry.value >= 100
                                          ? colors.accent
                                          : entry.value >= 50
                                              ? colors.info
                                              : colors.textTertiary,
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                                  const SizedBox(width: 2),
                                  Icon(
                                    Icons.expand_more,
                                    size: 10,
                                    color: colors.textTertiary,
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(width: 4),
                          GestureDetector(
                            onTap: () => _removeUser(entry.key),
                            child: Icon(Icons.close,
                                size: 12, color: colors.textTertiary),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
              ],
            ),
          ),

        const SizedBox(height: 12),

        // Search results
        Expanded(
          child: _searchResults.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.person_search_outlined,
                            size: 32, color: colors.textTertiary),
                        const SizedBox(height: 12),
                        Text(
                          'Search for users to invite',
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            color: colors.textTertiary,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'You can always invite people later',
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            color: colors.textTertiary,
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: _searchResults.length,
                  itemBuilder: (context, index) {
                    final user = _searchResults[index];
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 2),
                      child: Material(
                        color: Colors.transparent,
                        borderRadius: BorderRadius.circular(6),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(6),
                          hoverColor:
                              colors.border.withValues(alpha: 0.3),
                          onTap: () => _addUser(user),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 8),
                            child: Row(
                              children: [
                                GloamAvatar(
                                  displayName:
                                      user.displayName ?? user.userId,
                                  mxcUrl: user.avatarUrl,
                                  size: 28,
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        user.displayName ?? user.userId,
                                        style: GoogleFonts.inter(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w500,
                                          color: colors.textPrimary,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      if (user.displayName != null)
                                        Text(
                                          user.userId,
                                          style:
                                              GoogleFonts.jetBrainsMono(
                                            fontSize: 10,
                                            color: colors.textTertiary,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                    ],
                                  ),
                                ),
                                Icon(Icons.add_circle_outline,
                                    size: 18, color: colors.accent),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  PopupMenuItem<int> _roleMenuItem(
    GloamColorExtension colors,
    String label,
    int value,
    bool isSelected,
  ) {
    return PopupMenuItem<int>(
      value: value,
      height: 32,
      child: Row(
        children: [
          if (isSelected)
            Icon(Icons.check, size: 14, color: colors.accent)
          else
            const SizedBox(width: 14),
          const SizedBox(width: 8),
          Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 12,
              color: isSelected ? colors.accent : colors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}
