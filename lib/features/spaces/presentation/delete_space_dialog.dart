import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:matrix/matrix.dart';

import '../../../app/shell/space_rail.dart';
import '../../../app/theme/gloam_theme_ext.dart';
import '../../../app/theme/spacing.dart';
import '../../../services/matrix_service.dart';
import '../../chat/presentation/providers/timeline_provider.dart';
import '../providers/space_operation_provider.dart';
import 'widgets/operation_progress.dart';

/// Dialog for deleting a space with room selection and type-to-confirm.
class DeleteSpaceDialog extends ConsumerStatefulWidget {
  const DeleteSpaceDialog({super.key, required this.spaceId});
  final String spaceId;

  @override
  ConsumerState<DeleteSpaceDialog> createState() => _DeleteSpaceDialogState();
}

class _DeleteSpaceDialogState extends ConsumerState<DeleteSpaceDialog> {
  final _confirmController = TextEditingController();
  final _checkedRooms = <String>{};
  List<_ChildRoom> _childRooms = [];
  bool _loading = true;
  bool _deletionStarted = false;

  @override
  void initState() {
    super.initState();
    _loadChildRooms();
    _confirmController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _loadChildRooms() async {
    final client = ref.read(matrixServiceProvider).client;
    final space = client?.getRoomById(widget.spaceId);
    if (space == null || client == null) {
      setState(() => _loading = false);
      return;
    }

    final children = space.spaceChildren;
    final rooms = <_ChildRoom>[];

    for (final child in children) {
      if (child.roomId == null) continue;
      final room = client.getRoomById(child.roomId!);

      // Check if this room is shared with other spaces
      final otherSpaces = client.rooms
          .where((r) =>
              r.isSpace &&
              r.id != widget.spaceId &&
              r.membership == Membership.join &&
              r.spaceChildren.any((c) => c.roomId == child.roomId))
          .map((s) => s.getLocalizedDisplayname())
          .toList();

      rooms.add(_ChildRoom(
        roomId: child.roomId!,
        name: room?.getLocalizedDisplayname() ?? child.roomId!,
        memberCount: room?.summary.mJoinedMemberCount ?? 0,
        sharedWithSpaces: otherSpaces,
      ));
    }

    if (mounted) {
      setState(() {
        _childRooms = rooms;
        _loading = false;
      });
    }
  }

  String get _spaceName {
    final client = ref.read(matrixServiceProvider).client;
    final space = client?.getRoomById(widget.spaceId);
    return space?.getLocalizedDisplayname() ?? '';
  }

  bool get _canDelete =>
      _confirmController.text.trim() == _spaceName;

  void _startDeletion() {
    setState(() => _deletionStarted = true);

    final params = DeleteSpaceParams(
      spaceId: widget.spaceId,
      roomIdsToDelete: _checkedRooms,
    );

    ref.read(spaceOperationProvider.notifier).deleteSpace(params);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.gloam;
    final opState = ref.watch(spaceOperationProvider);

    // Listen for completion — navigate away
    ref.listen(spaceOperationProvider, (prev, next) {
      if (next.isComplete &&
          next.type == OperationType.delete &&
          !next.hasFailed) {
        ref.read(selectedSpaceProvider.notifier).state = null;
        ref.read(selectedRoomProvider.notifier).state = null;
        Navigator.of(context).pop(); // close delete dialog
        Navigator.of(context).pop(); // close space management modal
        Future.microtask(
            () => ref.read(spaceOperationProvider.notifier).reset());
      }
    });

    // Show progress view once deletion has started
    if (_deletionStarted && opState.type == OperationType.delete) {
      return Dialog(
        backgroundColor: colors.bgSurface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(GloamSpacing.radiusLg),
          side: BorderSide(color: colors.border),
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480, maxHeight: 500),
          child: Column(
            children: [
              Container(
                height: 56,
                padding: const EdgeInsets.symmetric(horizontal: 24),
                decoration: BoxDecoration(
                  border: Border(bottom: BorderSide(color: colors.border)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.delete_outline,
                        size: 20, color: colors.danger),
                    const SizedBox(width: 10),
                    Text(
                      'Deleting Space',
                      style: GoogleFonts.inter(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: colors.danger,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: OperationProgress(state: opState),
              ),
            ],
          ),
        ),
      );
    }

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
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Container(
              height: 56,
              padding: const EdgeInsets.symmetric(horizontal: 24),
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: colors.border)),
              ),
              child: Row(
                children: [
                  Icon(Icons.delete_outline,
                      size: 20, color: colors.danger),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Delete $_spaceName',
                      style: GoogleFonts.inter(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: colors.danger,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
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
                  // Warning
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF3A1A1A),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: colors.danger.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.warning_amber,
                            size: 18, color: colors.danger),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'This will permanently remove this space and kick all members. This action cannot be undone.',
                            style: GoogleFonts.inter(
                              fontSize: 13,
                              color: colors.danger,
                              height: 1.4,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Child rooms
                  if (_loading)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      child: Center(
                        child: SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: colors.accent,
                          ),
                        ),
                      ),
                    )
                  else if (_childRooms.isNotEmpty) ...[
                    const SizedBox(height: 20),
                    Text(
                      '// also delete these rooms?',
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: 10,
                        color: colors.textTertiary,
                        letterSpacing: 1,
                      ),
                    ),
                    const SizedBox(height: 8),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 160),
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: _childRooms.length,
                        itemBuilder: (context, index) {
                          final room = _childRooms[index];
                          final isChecked =
                              _checkedRooms.contains(room.roomId);
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 2),
                            child: Material(
                              color: Colors.transparent,
                              child: InkWell(
                                borderRadius: BorderRadius.circular(4),
                                hoverColor: colors.border
                                    .withValues(alpha: 0.3),
                                onTap: () => setState(() {
                                  if (isChecked) {
                                    _checkedRooms.remove(room.roomId);
                                  } else {
                                    _checkedRooms.add(room.roomId);
                                  }
                                }),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                      vertical: 4),
                                  child: Row(
                                    children: [
                                      SizedBox(
                                        width: 24,
                                        height: 24,
                                        child: Checkbox(
                                          value: isChecked,
                                          onChanged: (v) => setState(() {
                                            if (v == true) {
                                              _checkedRooms
                                                  .add(room.roomId);
                                            } else {
                                              _checkedRooms
                                                  .remove(room.roomId);
                                            }
                                          }),
                                          activeColor: colors.danger,
                                          side: BorderSide(
                                              color: colors.border),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        '#',
                                        style:
                                            GoogleFonts.jetBrainsMono(
                                          fontSize: 14,
                                          color: colors.textTertiary,
                                        ),
                                      ),
                                      const SizedBox(width: 4),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              room.name,
                                              style: GoogleFonts.inter(
                                                fontSize: 13,
                                                color:
                                                    colors.textPrimary,
                                              ),
                                            ),
                                            if (room.sharedWithSpaces
                                                .isNotEmpty)
                                              Row(
                                                children: [
                                                  Icon(
                                                    Icons.warning_amber,
                                                    size: 10,
                                                    color:
                                                        colors.warning,
                                                  ),
                                                  const SizedBox(
                                                      width: 4),
                                                  Expanded(
                                                    child: Text(
                                                      'Also in ${room.sharedWithSpaces.join(", ")}',
                                                      style: GoogleFonts
                                                          .inter(
                                                        fontSize: 10,
                                                        color: colors
                                                            .warning,
                                                      ),
                                                      overflow:
                                                          TextOverflow
                                                              .ellipsis,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                          ],
                                        ),
                                      ),
                                      Text(
                                        '${room.memberCount}',
                                        style:
                                            GoogleFonts.jetBrainsMono(
                                          fontSize: 10,
                                          color: colors.textTertiary,
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

                  // Type to confirm
                  const SizedBox(height: 20),
                  Text(
                    '// type "$_spaceName" to confirm',
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 10,
                      color: colors.textTertiary,
                      letterSpacing: 1,
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _confirmController,
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      color: colors.textPrimary,
                    ),
                    decoration: InputDecoration(
                      hintText: _spaceName,
                      hintStyle: GoogleFonts.inter(
                        fontSize: 14,
                        color: colors.textTertiary,
                      ),
                      filled: true,
                      fillColor: colors.bgElevated,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 12),
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
                        borderSide: BorderSide(color: colors.danger),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Footer
            Container(
              height: 64,
              padding: const EdgeInsets.symmetric(horizontal: 24),
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: colors.border)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Container(
                      height: 36,
                      padding:
                          const EdgeInsets.symmetric(horizontal: 16),
                      decoration: BoxDecoration(
                        borderRadius:
                            BorderRadius.circular(GloamSpacing.radiusMd),
                        border: Border.all(color: colors.border),
                      ),
                      child: Center(
                        child: Text(
                          'cancel',
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            color: colors.textSecondary,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  GestureDetector(
                    onTap: _canDelete ? _startDeletion : null,
                    child: Container(
                      height: 36,
                      padding:
                          const EdgeInsets.symmetric(horizontal: 20),
                      decoration: BoxDecoration(
                        color: _canDelete
                            ? colors.danger
                            : colors.bgElevated,
                        borderRadius:
                            BorderRadius.circular(GloamSpacing.radiusMd),
                        border: Border.all(
                          color: _canDelete
                              ? colors.danger
                              : colors.border,
                        ),
                      ),
                      child: Center(
                        child: Text(
                          'delete space',
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: _canDelete
                                ? colors.bg
                                : colors.textTertiary,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChildRoom {
  const _ChildRoom({
    required this.roomId,
    required this.name,
    required this.memberCount,
    required this.sharedWithSpaces,
  });

  final String roomId;
  final String name;
  final int memberCount;
  final List<String> sharedWithSpaces;
}

/// Shows the delete space dialog.
Future<void> showDeleteSpaceDialog(BuildContext context, String spaceId) {
  return showDialog(
    context: context,
    barrierColor: context.gloam.overlay,
    builder: (_) => DeleteSpaceDialog(spaceId: spaceId),
  );
}
