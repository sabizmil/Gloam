import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:matrix/matrix.dart';

import '../../../../app/theme/gloam_theme_ext.dart';
import '../../../../app/theme/spacing.dart';
import '../../../../services/matrix_service.dart';
import '../../../../widgets/gloam_avatar.dart';

/// Known user from joined rooms for autocomplete.
class _KnownUser {
  final String userId;
  final String? displayName;
  final Uri? avatarUrl;
  const _KnownUser({required this.userId, this.displayName, this.avatarUrl});
}

/// Dialog to invite users to a room.
/// Searches across all known users from joined rooms.
class InviteDialog extends ConsumerStatefulWidget {
  const InviteDialog({super.key, required this.roomId});
  final String roomId;

  @override
  ConsumerState<InviteDialog> createState() => _InviteDialogState();
}

class _InviteDialogState extends ConsumerState<InviteDialog> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  Timer? _debounce;
  List<_KnownUser> _knownUsers = [];
  List<_KnownUser> _results = [];
  final _invitedIds = <String>{};
  final _pendingIds = <String>{};

  @override
  void initState() {
    super.initState();
    _focusNode.requestFocus();
    _buildKnownUsers();
    _controller.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _buildKnownUsers() {
    final client = ref.read(matrixServiceProvider).client;
    if (client == null) return;

    final room = client.getRoomById(widget.roomId);
    final currentMembers = room?.getParticipants().map((m) => m.id).toSet() ?? {};

    final userMap = <String, _KnownUser>{};
    for (final r in client.rooms) {
      final members = r.states[EventTypes.RoomMember] ?? {};
      for (final entry in members.entries) {
        final userId = entry.key;
        if (userId == client.userID) continue;
        if (currentMembers.contains(userId)) continue; // Already in the room
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

    // Show suggestions initially
    setState(() => _results = _knownUsers.take(20).toList());
  }

  void _onSearchChanged() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 100), () {
      final query = _controller.text.trim().toLowerCase();
      if (query.isEmpty) {
        setState(() => _results = _knownUsers.take(20).toList());
        return;
      }
      setState(() {
        _results = _knownUsers
            .where((u) =>
                (u.displayName?.toLowerCase().contains(query) ?? false) ||
                u.userId.toLowerCase().contains(query))
            .take(20)
            .toList();
      });
    });
  }

  Future<void> _invite(String userId) async {
    final client = ref.read(matrixServiceProvider).client;
    final room = client?.getRoomById(widget.roomId);
    if (room == null) return;

    setState(() => _pendingIds.add(userId));
    try {
      await room.invite(userId);
      if (mounted) {
        setState(() {
          _pendingIds.remove(userId);
          _invitedIds.add(userId);
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _pendingIds.remove(userId));
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to invite: $e'),
            backgroundColor: context.gloam.danger,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.gloam;
    return Dialog(
      backgroundColor: colors.bgSurface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(GloamSpacing.radiusLg),
        side: BorderSide(color: colors.border),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420, maxHeight: 520),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Container(
              height: 48,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: colors.border),
                ),
              ),
              child: Row(
                children: [
                  Icon(Icons.person_add, size: 18, color: colors.accent),
                  const SizedBox(width: 8),
                  Text(
                    'invite to channel',
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: colors.textPrimary,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: Icon(Icons.close, size: 16, color: colors.textTertiary),
                    hoverColor: colors.border.withValues(alpha: 0.5),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                  ),
                ],
              ),
            ),

            // Search
            Container(
              height: 44,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Icon(Icons.search, size: 16, color: colors.textTertiary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      focusNode: _focusNode,
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        color: colors.textPrimary,
                      ),
                      decoration: InputDecoration(
                        hintText: 'search by name or @user:server',
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
                ],
              ),
            ),
            Divider(height: 1, color: colors.border),

            // Label
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  _controller.text.isEmpty ? '// suggested' : '// results',
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 10,
                    color: colors.textTertiary,
                    letterSpacing: 1,
                  ),
                ),
              ),
            ),

            // User list
            Expanded(
              child: _results.isEmpty
                  ? Center(
                      child: Text(
                        '// no users found',
                        style: GoogleFonts.jetBrainsMono(
                          fontSize: 11,
                          color: colors.textTertiary,
                        ),
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      itemCount: _results.length,
                      itemBuilder: (context, index) {
                        final user = _results[index];
                        final isInvited = _invitedIds.contains(user.userId);
                        final isPending = _pendingIds.contains(user.userId);

                        return Padding(
                          padding: const EdgeInsets.only(bottom: 2),
                          child: Material(
                            color: Colors.transparent,
                            borderRadius: BorderRadius.circular(6),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(6),
                              hoverColor: colors.border.withValues(alpha: 0.3),
                              onTap: isInvited || isPending
                                  ? null
                                  : () => _invite(user.userId),
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
                                    const SizedBox(width: 8),
                                    if (isPending)
                                      SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: colors.accent,
                                        ),
                                      )
                                    else
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 12, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: isInvited
                                              ? null
                                              : colors.accentDim,
                                          borderRadius:
                                              BorderRadius.circular(6),
                                          border: Border.all(
                                            color: isInvited
                                                ? colors.border
                                                : colors.accent,
                                          ),
                                        ),
                                        child: Text(
                                          isInvited ? 'invited' : 'invite',
                                          style: GoogleFonts.jetBrainsMono(
                                            fontSize: 11,
                                            color: isInvited
                                                ? colors.textTertiary
                                                : colors.accent,
                                            letterSpacing: 0.5,
                                          ),
                                        ),
                                      ),
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
        ),
      ),
    );
  }
}

/// Shows the invite dialog for a room.
Future<void> showInviteDialog(BuildContext context, String roomId) {
  return showDialog(
    context: context,
    barrierColor: context.gloam.overlay,
    builder: (_) => InviteDialog(roomId: roomId),
  );
}
