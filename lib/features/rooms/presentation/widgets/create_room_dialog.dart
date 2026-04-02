import 'dart:async';

import 'package:flutter/material.dart' hide Visibility;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:matrix/matrix.dart';

import '../../../../app/theme/gloam_theme_ext.dart';
import '../../../../app/theme/spacing.dart';
import '../../../../services/matrix_service.dart';
import '../../../../widgets/gloam_avatar.dart';

enum _RoomType { channel, private_, dm }

/// A known user collected from joined rooms.
class _KnownUser {
  final String userId;
  final String? displayName;
  final Uri? avatarUrl;

  const _KnownUser({
    required this.userId,
    this.displayName,
    this.avatarUrl,
  });
}

/// Create room dialog with type-adaptive fields and user autocomplete for DMs.
class CreateRoomDialog extends ConsumerStatefulWidget {
  const CreateRoomDialog({super.key, this.parentSpaceId});

  /// If set, the new room will be added to this space after creation.
  final String? parentSpaceId;

  @override
  ConsumerState<CreateRoomDialog> createState() => _CreateRoomDialogState();
}

class _CreateRoomDialogState extends ConsumerState<CreateRoomDialog> {
  _RoomType _type = _RoomType.channel;
  final _nameController = TextEditingController();
  final _topicController = TextEditingController();
  final _userController = TextEditingController();
  bool _encrypted = false;
  bool _creating = false;
  String? _selectedSpaceId;

  // User search state
  List<_KnownUser> _knownUsers = [];
  List<_KnownUser> _searchResults = [];
  _KnownUser? _selectedUser;
  String? _existingDmId;
  Timer? _searchDebounce;

  @override
  void initState() {
    super.initState();
    _selectedSpaceId = widget.parentSpaceId;
    _buildKnownUsers();
    _userController.addListener(_onUserSearchChanged);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _topicController.dispose();
    _userController.dispose();
    _searchDebounce?.cancel();
    super.dispose();
  }

  /// Collect all unique users from joined rooms (excluding self).
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

  void _onUserSearchChanged() {
    _searchDebounce?.cancel();

    // If user was selected but text changed, clear selection
    if (_selectedUser != null) {
      final currentText = _userController.text.trim();
      if (currentText != _selectedUser!.userId &&
          currentText != _selectedUser!.displayName) {
        setState(() {
          _selectedUser = null;
          _existingDmId = null;
        });
      }
    }

    _searchDebounce = Timer(const Duration(milliseconds: 100), () {
      final query = _userController.text.trim().toLowerCase();
      if (query.isEmpty || _selectedUser != null) {
        setState(() => _searchResults = []);
        return;
      }

      final results = _knownUsers
          .where((u) =>
              (u.displayName?.toLowerCase().contains(query) ?? false) ||
              u.userId.toLowerCase().contains(query))
          .take(6)
          .toList();

      setState(() => _searchResults = results);
    });
  }

  void _selectUser(_KnownUser user) {
    final client = ref.read(matrixServiceProvider).client;
    final existingDm = client?.getDirectChatFromUserId(user.userId);

    setState(() {
      _selectedUser = user;
      _existingDmId = existingDm;
      _searchResults = [];
      _userController.text = user.displayName ?? user.userId;
      // Move cursor to end
      _userController.selection = TextSelection.collapsed(
        offset: _userController.text.length,
      );
    });
  }

  void _clearSelection() {
    setState(() {
      _selectedUser = null;
      _existingDmId = null;
      _userController.clear();
    });
  }

  void _setType(_RoomType type) {
    setState(() {
      _type = type;
      switch (type) {
        case _RoomType.channel:
          _encrypted = false;
        case _RoomType.private_:
          _encrypted = true;
        case _RoomType.dm:
          _encrypted = true;
      }
      // Clear DM state when switching away
      if (type != _RoomType.dm) {
        _selectedUser = null;
        _existingDmId = null;
        _searchResults = [];
      }
    });
  }

  String get _actionLabel {
    if (_type != _RoomType.dm) return 'create room';
    if (_existingDmId != null) return 'open chat';
    return 'start chat';
  }

  Future<void> _create() async {
    final client = ref.read(matrixServiceProvider).client;
    if (client == null) return;

    if (_type == _RoomType.dm) {
      // If existing DM, just open it
      if (_existingDmId != null) {
        Navigator.pop(context, _existingDmId);
        return;
      }

      final userId = _selectedUser?.userId ?? _userController.text.trim();
      if (userId.isEmpty) return;
      if (!userId.startsWith('@') || !userId.contains(':')) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content:
                Text('Enter a valid Matrix ID (e.g. @user:server.com)'),
            backgroundColor: context.gloam.danger,
          ),
        );
        return;
      }
    } else {
      if (_nameController.text.trim().isEmpty) return;
    }

    setState(() => _creating = true);

    try {
      String roomId;

      if (_type == _RoomType.dm) {
        final userId = _selectedUser?.userId ?? _userController.text.trim();
        roomId = await client.startDirectChat(
          userId,
          enableEncryption: _encrypted,
        );
      } else {
        final name = _nameController.text.trim();
        final topic = _topicController.text.trim();

        roomId = await client.createRoom(
          name: name,
          topic: topic.isEmpty ? null : topic,
          visibility: _type == _RoomType.channel
              ? Visibility.public
              : Visibility.private,
          preset: _type == _RoomType.channel
              ? CreateRoomPreset.publicChat
              : CreateRoomPreset.privateChat,
          initialState: _encrypted
              ? [
                  StateEvent(
                    type: EventTypes.Encryption,
                    stateKey: '',
                    content: {'algorithm': 'm.megolm.v1.aes-sha2'},
                  ),
                ]
              : null,
        );
      }

      // Add to selected space if specified
      if (_selectedSpaceId != null) {
        final space = client.getRoomById(_selectedSpaceId!);
        if (space != null) {
          await space.setSpaceChild(roomId);
        }
      }

      if (mounted) Navigator.pop(context, roomId);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to create room: $e'),
            backgroundColor: context.gloam.danger,
          ),
        );
        setState(() => _creating = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDm = _type == _RoomType.dm;
    final colors = context.gloam;

    return Dialog(
      backgroundColor: colors.bgSurface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(GloamSpacing.radiusLg),
        side: BorderSide(color: colors.border),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Container(
              height: 56,
              padding: const EdgeInsets.symmetric(horizontal: 24),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: colors.border),
                ),
              ),
              child: Row(
                children: [
                  Text(
                    isDm ? 'start conversation' : 'create room',
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: colors.textPrimary,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const Spacer(),
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Icon(Icons.close,
                        size: 18, color: colors.textTertiary),
                  ),
                ],
              ),
            ),

            // Body
            Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Room type selector
                  Text(
                    '// type',
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 10,
                      color: colors.textTertiary,
                      letterSpacing: 1,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      _TypeCard(
                        icon: Icons.tag,
                        label: 'channel',
                        isSelected: _type == _RoomType.channel,
                        onTap: () => _setType(_RoomType.channel),
                      ),
                      const SizedBox(width: 10),
                      _TypeCard(
                        icon: Icons.lock_outline,
                        label: 'private',
                        isSelected: _type == _RoomType.private_,
                        onTap: () => _setType(_RoomType.private_),
                      ),
                      const SizedBox(width: 10),
                      _TypeCard(
                        icon: Icons.chat_bubble_outline,
                        label: 'DM',
                        isSelected: _type == _RoomType.dm,
                        onTap: () => _setType(_RoomType.dm),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),

                  // DM: user search field with autocomplete
                  if (isDm) ...[
                    Text(
                      '// user',
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: 10,
                        color: colors.textTertiary,
                        letterSpacing: 1,
                      ),
                    ),
                    const SizedBox(height: 8),
                    _buildUserField(colors),
                    if (_searchResults.isNotEmpty)
                      _buildSearchResults(colors),
                    if (_selectedUser != null) ...[
                      const SizedBox(height: 12),
                      _buildSelectedUserChip(colors),
                    ],
                  ],

                  // Space picker (for channel/private, not DM)
                  if (!isDm) ...[
                    Text(
                      '// add to space',
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: 10,
                        color: colors.textTertiary,
                        letterSpacing: 1,
                      ),
                    ),
                    const SizedBox(height: 8),
                    _buildSpacePicker(colors),
                    const SizedBox(height: 16),
                  ],

                  // Channel / Private: name + topic
                  if (!isDm) ...[
                    Text(
                      '// room name',
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: 10,
                        color: colors.textTertiary,
                        letterSpacing: 1,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _nameController,
                      autofocus: true,
                      decoration: InputDecoration(
                        hintText: _type == _RoomType.channel
                            ? 'e.g. design-reviews'
                            : 'e.g. project-alpha',
                        prefixIcon: Padding(
                          padding: const EdgeInsets.only(left: 14, right: 4),
                          child: Text(
                            _type == _RoomType.channel ? '#' : '\u{1f512}',
                            style: GoogleFonts.jetBrainsMono(
                              fontSize: 16,
                              color: colors.textTertiary,
                            ),
                          ),
                        ),
                        prefixIconConstraints:
                            const BoxConstraints(minWidth: 0, minHeight: 0),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      '// topic (optional)',
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: 10,
                        color: colors.textTertiary,
                        letterSpacing: 1,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _topicController,
                      decoration: const InputDecoration(
                        hintText: "what's this room about?",
                      ),
                    ),
                  ],
                  const SizedBox(height: 20),

                  // Encryption toggle
                  Row(
                    children: [
                      Icon(Icons.shield_outlined,
                          size: 16, color: colors.accent),
                      const SizedBox(width: 8),
                      Text(
                        'enable encryption',
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          color: colors.textPrimary,
                        ),
                      ),
                      const Spacer(),
                      Switch(
                        value: _encrypted,
                        onChanged: (v) => setState(() => _encrypted = v),
                        activeThumbColor: colors.accent,
                        activeTrackColor: colors.accentDim,
                        inactiveThumbColor: colors.textTertiary,
                        inactiveTrackColor: colors.bgElevated,
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // Footer
            Container(
              height: 64,
              padding: const EdgeInsets.symmetric(horizontal: 24),
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(color: colors.border),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('cancel'),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton(
                    onPressed: _creating ? null : _create,
                    child: _creating
                        ? SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: colors.bg,
                            ),
                          )
                        : Text(_actionLabel),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSpacePicker(dynamic colors) {
    final client = ref.read(matrixServiceProvider).client;
    final spaces = client?.rooms
            .where((r) => r.isSpace && r.membership == Membership.join)
            .toList() ??
        [];

    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: colors.bgElevated,
        borderRadius: BorderRadius.circular(GloamSpacing.radiusSm),
        border: Border.all(color: colors.border),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String?>(
          value: _selectedSpaceId,
          isExpanded: true,
          dropdownColor: colors.bgSurface,
          icon: Icon(Icons.expand_more, size: 18, color: colors.textTertiary),
          style: GoogleFonts.inter(fontSize: 13, color: colors.textPrimary),
          hint: Text(
            'no space (standalone)',
            style: GoogleFonts.inter(fontSize: 13, color: colors.textTertiary),
          ),
          items: [
            DropdownMenuItem<String?>(
              value: null,
              child: Text('no space (standalone)',
                  style: GoogleFonts.inter(
                      fontSize: 13, color: colors.textSecondary)),
            ),
            ...spaces.map((s) => DropdownMenuItem<String?>(
                  value: s.id,
                  child: Row(
                    children: [
                      Icon(Icons.workspaces,
                          size: 14, color: colors.accent),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          s.getLocalizedDisplayname(),
                          style: GoogleFonts.inter(
                              fontSize: 13, color: colors.textPrimary),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                )),
          ],
          onChanged: (value) => setState(() => _selectedSpaceId = value),
        ),
      ),
    );
  }

  Widget _buildUserField(dynamic colors) {
    return TextField(
      controller: _userController,
      autofocus: true,
      decoration: InputDecoration(
        hintText: 'search by name or @user:server.com',
        prefixIcon: Padding(
          padding: const EdgeInsets.only(left: 14, right: 4),
          child: Icon(Icons.search,
              size: 18, color: colors.textTertiary),
        ),
        prefixIconConstraints:
            const BoxConstraints(minWidth: 0, minHeight: 0),
        suffixIcon: _userController.text.isNotEmpty
            ? GestureDetector(
                onTap: _clearSelection,
                child: Icon(Icons.close,
                    size: 16, color: colors.textTertiary),
              )
            : null,
      ),
    );
  }

  Widget _buildSearchResults(dynamic colors) {
    return Container(
      margin: const EdgeInsets.only(top: 4),
      constraints: const BoxConstraints(maxHeight: 240),
      decoration: BoxDecoration(
        color: colors.bgElevated,
        borderRadius: BorderRadius.circular(GloamSpacing.radiusSm),
        border: Border.all(color: colors.border),
      ),
      child: ListView.builder(
        shrinkWrap: true,
        padding: const EdgeInsets.symmetric(vertical: 4),
        itemCount: _searchResults.length,
        itemBuilder: (context, index) {
          final user = _searchResults[index];
          final client = ref.read(matrixServiceProvider).client;
          final hasDm = client?.getDirectChatFromUserId(user.userId) != null;

          return InkWell(
            onTap: () => _selectUser(user),
            borderRadius: BorderRadius.circular(GloamSpacing.radiusSm),
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  GloamAvatar(
                    displayName: user.displayName ?? user.userId,
                    mxcUrl: user.avatarUrl,
                    size: 28,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
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
                            style: GoogleFonts.jetBrainsMono(
                              fontSize: 10,
                              color: colors.textTertiary,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                      ],
                    ),
                  ),
                  if (hasDm)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: colors.accentDim,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        'existing DM',
                        style: GoogleFonts.jetBrainsMono(
                          fontSize: 9,
                          color: colors.accent,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildSelectedUserChip(dynamic colors) {
    final user = _selectedUser!;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: colors.accentDim,
        borderRadius: BorderRadius.circular(GloamSpacing.radiusSm),
        border: Border.all(color: colors.accent),
      ),
      child: Row(
        children: [
          GloamAvatar(
            displayName: user.displayName ?? user.userId,
            mxcUrl: user.avatarUrl,
            size: 24,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  user.displayName ?? user.userId,
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: colors.textPrimary,
                  ),
                ),
                Text(
                  user.userId,
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 10,
                    color: colors.textTertiary,
                  ),
                ),
              ],
            ),
          ),
          if (_existingDmId != null)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Text(
                'existing conversation',
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 10,
                  color: colors.accent,
                  letterSpacing: 0.5,
                ),
              ),
            ),
          GestureDetector(
            onTap: _clearSelection,
            child: Icon(Icons.close, size: 14, color: colors.textTertiary),
          ),
        ],
      ),
    );
  }
}

class _TypeCard extends StatelessWidget {
  const _TypeCard({
    required this.icon,
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          height: 80,
          decoration: BoxDecoration(
            color: isSelected ? context.gloam.accentDim : Colors.transparent,
            borderRadius: BorderRadius.circular(GloamSpacing.radiusMd),
            border: Border.all(
              color: isSelected ? context.gloam.accent : context.gloam.border,
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 18,
                color: isSelected
                    ? context.gloam.accent
                    : context.gloam.textTertiary,
              ),
              const SizedBox(height: 6),
              Text(
                label,
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 11,
                  color: isSelected
                      ? context.gloam.accent
                      : context.gloam.textSecondary,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Shows the create room dialog and returns the new room ID (if created).
Future<String?> showCreateRoomDialog(
  BuildContext context, {
  String? parentSpaceId,
}) {
  return showDialog<String>(
    context: context,
    barrierColor: context.gloam.overlay,
    builder: (_) => CreateRoomDialog(parentSpaceId: parentSpaceId),
  );
}
