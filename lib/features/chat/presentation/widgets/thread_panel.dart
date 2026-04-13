import 'dart:io' show HttpClient;
import 'dart:typed_data';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:matrix/matrix.dart' show MatrixFile;

import '../../../../app/theme/gloam_theme_ext.dart';
import '../../../../app/theme/spacing.dart';
import '../../../../services/clipboard_paste_service.dart';
import '../../../../services/klipy_service.dart';
import '../../../../services/matrix_service.dart';
import '../../../../services/upload_service.dart';
import '../../../../widgets/gloam_avatar.dart';
import '../../../profile/presentation/user_profile_modal.dart';
import '../../data/staged_attachment.dart';
import '../providers/draft_attachments_provider.dart';
import '../providers/timeline_provider.dart';
import 'attachment_chip_strip.dart';
import 'drop_overlay.dart';
import 'emoji_picker.dart';
import 'gif_picker.dart';
import 'mention_autocomplete.dart';
import 'message_bubble.dart';

Future<Uint8List> _downloadBytes(String url) async {
  final client = HttpClient();
  final request = await client.getUrl(Uri.parse(url));
  final response = await request.close();
  final builder = BytesBuilder();
  await response.forEach(builder.add);
  client.close();
  return builder.toBytes();
}

/// Right panel for viewing a message thread.
class ThreadPanel extends ConsumerStatefulWidget {
  const ThreadPanel({
    super.key,
    required this.roomId,
    required this.rootMessage,
    required this.onClose,
  });

  final String roomId;
  final TimelineMessage rootMessage;
  final VoidCallback onClose;

  @override
  ConsumerState<ThreadPanel> createState() => _ThreadPanelState();
}

class _ThreadPanelState extends ConsumerState<ThreadPanel> {
  final _controller = MentionTextController();
  final _scrollController = ScrollController();
  final _focusNode = FocusNode();
  final _autocompleteKey = GlobalKey<MentionAutocompleteState>();
  TimelineMessage? _replyTo;
  String _prePasteText = '';

  @override
  void initState() {
    super.initState();
    // Focus after the first frame so the widget tree is ready
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
    });
  }

  @override
  void didUpdateWidget(covariant ThreadPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Re-focus when switching to a different thread
    if (oldWidget.rootMessage.eventId != widget.rootMessage.eventId) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _focusNode.requestFocus();
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _setReplyTo(TimelineMessage msg) {
    setState(() => _replyTo = msg);
    _focusNode.requestFocus();
  }

  void _clearReplyTo() {
    setState(() => _replyTo = null);
  }

  /// Thread drafts are scoped by `roomId#rootEventId` so staged files in
  /// one thread don't leak into the main room or sibling threads.
  String get _draftKey => '${widget.roomId}#${widget.rootMessage.eventId}';

  int _attachmentCounter = 0;
  String _attachmentId() =>
      '${DateTime.now().microsecondsSinceEpoch}-${_attachmentCounter++}';

  void _stageAttachments(List<MatrixFile> files) {
    if (files.isEmpty) return;
    final staged = files
        .map((f) => StagedAttachment(id: _attachmentId(), file: f))
        .toList();
    final accepted = ref
        .read(draftAttachmentsProvider(_draftKey).notifier)
        .add(staged);
    if (accepted < staged.length && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Attachments limited to ${DraftAttachmentsNotifier.maxPerDraft} per message',
          ),
          backgroundColor: context.gloam.danger,
        ),
      );
    }
  }

  void _send() async {
    final text = _controller.text.trim();
    final staged = ref.read(draftAttachmentsProvider(_draftKey));

    if (staged.isNotEmpty) {
      ref.read(draftAttachmentsProvider(_draftKey).notifier).clear();
      _controller.clear();
      _clearReplyTo();
      try {
        await ref
            .read(timelineProvider(widget.roomId).notifier)
            .sendWithAttachments(
              files: staged.map((a) => a.file).toList(),
              text: text,
              threadRootEventId: widget.rootMessage.eventId,
            );
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('send failed: $e'),
              backgroundColor: context.gloam.danger,
            ),
          );
        }
      }
      return;
    }

    if (text.isEmpty) return;
    ref.read(timelineProvider(widget.roomId).notifier).sendThreadReply(
          text,
          widget.rootMessage.eventId,
          inReplyToEventId: _replyTo?.eventId,
        );
    _controller.clear();
    _clearReplyTo();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.gloam;
    final allMessages = ref.watch(timelineProvider(widget.roomId));

    // Filter thread replies — m.thread relation OR legacy m.in_reply_to
    final threadReplies = allMessages
        .where((m) =>
            m.threadRootEventId == widget.rootMessage.eventId ||
            (!m.isThreadReply &&
                m.replyToEventId == widget.rootMessage.eventId))
        .toList();

    // Extract unique participants
    final participants = <String, ({String name, Uri? avatarUrl})>{};
    for (final reply in threadReplies) {
      participants.putIfAbsent(
        reply.senderId,
        () => (name: reply.senderName, avatarUrl: reply.senderAvatarUrl),
      );
    }

    return FileDropZone(
      onFilesDropped: _handleDroppedFiles,
      child: Container(
      decoration: BoxDecoration(
        color: colors.bgSurface,
        border: Border(
          left: BorderSide(color: colors.border),
        ),
      ),
      child: Column(
        children: [
          // ── Header ──
          _buildHeader(),

          // ── Scrollable thread: root message + metadata + replies ──
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
              itemCount: threadReplies.length + 2, // +1 root, +1 metadata
              itemBuilder: (context, index) {
                final myUserId = ref.read(matrixServiceProvider).client?.userID;
                final notifier = ref.read(timelineProvider(widget.roomId).notifier);

                // First item: root message
                if (index == 0) {
                  return _buildMessageBubble(
                    widget.rootMessage, false, myUserId, notifier,
                  );
                }

                // Second item: metadata
                if (index == 1) {
                  return _buildMetadata(threadReplies, participants);
                }

                // Replies (offset by 2)
                final replyIndex = index - 2;
                final msg = threadReplies[replyIndex];
                final prevMsg =
                    replyIndex > 0 ? threadReplies[replyIndex - 1] : null;
                final isGrouped = prevMsg != null &&
                    prevMsg.senderId == msg.senderId &&
                    msg.timestamp.difference(prevMsg.timestamp).inMinutes <
                        3;

                return _buildMessageBubble(msg, isGrouped, myUserId, notifier);
              },
            ),
          ),

          // ── Composer ──
          _buildComposer(),
        ],
      ),
      ),
    );
  }

  Widget _buildHeader() {
    final colors = context.gloam;
    return Container(
      height: GloamSpacing.headerHeight,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: colors.border),
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.chat_bubble_outline,
              size: 16, color: colors.accent),
          const SizedBox(width: 8),
          Text(
            'Thread',
            style: GoogleFonts.inter(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: colors.textPrimary,
            ),
          ),
          const Spacer(),
          IconButton(
            onPressed: widget.onClose,
            icon: Icon(Icons.close,
                size: 16, color: colors.textTertiary),
            hoverColor: colors.border.withValues(alpha: 0.5),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageBubble(
    TimelineMessage msg,
    bool isGrouped,
    String? myUserId,
    TimelineNotifier notifier,
  ) {
    final isOwn = msg.senderId == myUserId;
    return MessageBubble(
      message: msg,
      isGrouped: isGrouped,
      roomId: widget.roomId,
      isOwnMessage: isOwn,
      selfUserId: myUserId,
      onAvatarTap: () => showUserProfile(
        context, ref,
        userId: msg.senderId,
        roomId: widget.roomId,
      ),
      onMentionTap: (userId) => showUserProfile(
        context, ref,
        userId: userId,
        roomId: widget.roomId,
      ),
      onReact: (emoji) => notifier.react(msg.eventId, emoji),
      onReply: () => _setReplyTo(msg),
      onEdit: isOwn
          ? () async {
              // Simple inline edit — prompt with current text
              _controller.text = msg.body;
              _focusNode.requestFocus();
            }
          : null,
      onDelete: isOwn
          ? () async {
              final confirmed = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('Delete message?'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: const Text('cancel'),
                    ),
                    TextButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      child: const Text('delete'),
                    ),
                  ],
                ),
              );
              if (confirmed == true) {
                notifier.redactMessage(msg.eventId);
              }
            }
          : null,
      onCopy: () {
        Clipboard.setData(ClipboardData(text: msg.body));
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('copied to clipboard'),
            duration: Duration(seconds: 1),
          ),
        );
      },
    );
  }

  Widget _buildMetadata(
    List<TimelineMessage> replies,
    Map<String, ({String name, Uri? avatarUrl})> participants,
  ) {
    if (replies.isEmpty) return const SizedBox.shrink();

    final colors = context.gloam;
    final replyWord = replies.length == 1 ? 'reply' : 'replies';
    final partWord =
        participants.length == 1 ? 'participant' : 'participants';

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 2),
      child: Row(
        children: [
          // Reply count · participant count
          Expanded(
            child: Row(
              children: [
                Text(
                  '${replies.length} $replyWord',
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 10,
                    color: colors.textTertiary,
                    letterSpacing: 1,
                  ),
                ),
                Container(
                  width: 3,
                  height: 3,
                  margin: const EdgeInsets.symmetric(horizontal: 8),
                  decoration: BoxDecoration(
                    color: colors.textTertiary,
                    shape: BoxShape.circle,
                  ),
                ),
                Text(
                  '${participants.length} $partWord',
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 10,
                    color: colors.textTertiary,
                    letterSpacing: 1,
                  ),
                ),
              ],
            ),
          ),

          // Overlapping participant avatars
          SizedBox(
            height: 22,
            child: _buildParticipantAvatars(participants),
          ),
        ],
      ),
    );
  }

  Widget _buildParticipantAvatars(
    Map<String, ({String name, Uri? avatarUrl})> participants,
  ) {
    final colors = context.gloam;
    final entries = participants.values.take(5).toList();
    const size = 22.0;
    const overlap = 6.0;
    final totalWidth = size + (entries.length - 1) * (size - overlap);

    return SizedBox(
      width: totalWidth,
      child: Stack(
        children: [
          for (var i = 0; i < entries.length; i++)
            Positioned(
              left: i * (size - overlap),
              child: Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: colors.bgSurface,
                    width: 2,
                  ),
                ),
                child: GloamAvatar(
                  displayName: entries[i].name,
                  mxcUrl: entries[i].avatarUrl,
                  size: size - 4, // account for border
                ),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _handleDroppedFiles(List<DropDoneDetails> detailsList) async {
    final collected = <MatrixFile>[];
    for (final details in detailsList) {
      for (final xFile in details.files) {
        try {
          final bytes = await xFile.readAsBytes();

          final sizeError = UploadService.validateFileSize(bytes.length);
          if (sizeError != null && mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(sizeError), backgroundColor: context.gloam.danger),
            );
            continue;
          }

          collected.add(UploadService.createMatrixFile(
            bytes: bytes,
            name: xFile.name,
          ));
        } catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Upload failed: $e'), backgroundColor: context.gloam.danger),
            );
          }
        }
      }
    }
    _stageAttachments(collected);
  }

  Future<void> _pickAndUploadFile() async {
    try {
      final result = await FilePicker.platform.pickFiles();
      if (result == null || result.files.isEmpty) return;
      final picked = result.files.first;
      if (picked.path == null) return;

      final sizeError = UploadService.validateFileSize(picked.size);
      if (sizeError != null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(sizeError), backgroundColor: context.gloam.danger),
        );
        return;
      }

      final matrixFile = await UploadService.fromPath(picked.path!);
      _stageAttachments([matrixFile]);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Upload failed: $e'), backgroundColor: context.gloam.danger),
        );
      }
    }
  }

  void _sendGif(KlipyItem item) {
    final rootEventId = widget.rootMessage.eventId;
    final notifier = ref.read(timelineProvider(widget.roomId).notifier);
    final url = item.fullUrl;
    final w = item.fullWidth;
    final h = item.fullHeight;

    () async {
      try {
        final bytes = await compute(_downloadBytes, url);
        final uri = Uri.parse(url);
        final name = uri.pathSegments.isNotEmpty ? uri.pathSegments.last : 'gif.webp';
        await notifier.sendThreadGif(bytes, name, rootEventId, width: w, height: h);
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to send: $e'), backgroundColor: context.gloam.danger),
          );
        }
      }
    }();
  }

  Future<void> _handlePaste() async {
    try {
      final files = await ClipboardPasteService.getClipboardFiles();
      if (files.isNotEmpty) {
        _controller.text = _prePasteText;
        _stageAttachments(files);
        return;
      }

      final imageFile = await ClipboardPasteService.getClipboardImage();
      if (imageFile != null) {
        final sizeError = UploadService.validateFileSize(imageFile.bytes.length);
        if (sizeError != null && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(sizeError), backgroundColor: context.gloam.danger),
          );
          return;
        }
        _controller.text = _prePasteText;
        _stageAttachments([imageFile]);
        return;
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Paste failed: $e'), backgroundColor: context.gloam.danger),
        );
      }
    }
  }

  Widget _buildComposer() {
    final colors = context.gloam;
    final staged = ref.watch(draftAttachmentsProvider(_draftKey));
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Staged attachments
        if (staged.isNotEmpty)
          AttachmentChipStrip(
            attachments: staged,
            onRemove: (id) => ref
                .read(draftAttachmentsProvider(_draftKey).notifier)
                .remove(id),
          ),

        // Reply bar
        if (_replyTo != null)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            decoration: BoxDecoration(
              border: Border(
                top: BorderSide(color: colors.border),
              ),
            ),
            child: Row(
              children: [
                Icon(Icons.reply, size: 16, color: colors.accent),
                const SizedBox(width: 8),
                Text(
                  'replying to ${_replyTo!.senderName}',
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 11,
                    color: colors.accent,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _replyTo!.body,
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      color: colors.textTertiary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                GestureDetector(
                  onTap: _clearReplyTo,
                  child: Icon(Icons.close,
                      size: 16, color: colors.textTertiary),
                ),
              ],
            ),
          ),

        // Composer row
        Container(
      padding: const EdgeInsets.symmetric(
        horizontal: GloamSpacing.xl,
        vertical: 8,
      ),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: colors.border),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Attachment button
          IconButton(
            onPressed: _pickAndUploadFile,
            icon: Icon(Icons.add_circle_outline,
                size: 22, color: colors.textTertiary),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
          ),
          const SizedBox(width: 8),

          // Text field with GIF + emoji suffix
          Expanded(
            child: MentionAutocomplete(
              key: _autocompleteKey,
              roomId: widget.roomId,
              controller: _controller,
              focusNode: _focusNode,
              child: Container(
              decoration: BoxDecoration(
                color: colors.bgSurface,
                borderRadius:
                    BorderRadius.circular(GloamSpacing.radiusSm),
                border: Border.all(color: colors.border),
              ),
              child: Focus(
                onKeyEvent: (node, event) {
                  if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
                    return KeyEventResult.ignored;
                  }
                  // Let mention autocomplete handle keys first
                  if (_autocompleteKey.currentState?.handleKeyEvent(event) == true) {
                    return KeyEventResult.handled;
                  }
                  if (event is! KeyDownEvent) return KeyEventResult.ignored;
                  // Enter to send
                  if (event.logicalKey == LogicalKeyboardKey.enter &&
                      !HardwareKeyboard.instance.isShiftPressed) {
                    _send();
                    return KeyEventResult.handled;
                  }
                  // Cmd/Ctrl+V paste handling
                  final isPaste = event.logicalKey == LogicalKeyboardKey.keyV &&
                      (HardwareKeyboard.instance.isMetaPressed ||
                          HardwareKeyboard.instance.isControlPressed);
                  if (isPaste) {
                    _handlePaste();
                  } else {
                    _prePasteText = _controller.text;
                  }
                  return KeyEventResult.ignored;
                },
                child: TextField(
                  controller: _controller,
                  focusNode: _focusNode,
                  maxLines: 6,
                  minLines: 1,
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    color: colors.textPrimary,
                  ),
                  decoration: InputDecoration(
                    hintText: 'Reply in thread...',
                    hintMaxLines: 1,
                    hintStyle: GoogleFonts.inter(
                      fontSize: 14,
                      color: colors.textTertiary,
                    ),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    suffixIcon: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          onPressed: () async {
                            final item = await showGifPicker(context);
                            if (item != null) _sendGif(item);
                          },
                          icon: Icon(Icons.gif_box_outlined,
                              size: 20, color: colors.textTertiary),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(
                              minWidth: 36, minHeight: 36),
                        ),
                        IconButton(
                          onPressed: () async {
                            final emoji = await showEmojiPicker(context);
                            if (emoji != null) {
                              final pos = _controller.selection;
                              final text = _controller.text;
                              final newText =
                                  text.substring(0, pos.baseOffset) +
                                      emoji +
                                      text.substring(pos.extentOffset);
                              _controller.text = newText;
                              _controller.selection =
                                  TextSelection.collapsed(
                                offset: pos.baseOffset + emoji.length,
                              );
                            }
                          },
                          icon: Icon(Icons.sentiment_satisfied_outlined,
                              size: 20, color: colors.textTertiary),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(
                              minWidth: 36, minHeight: 36),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            ),
          ),
          const SizedBox(width: 8),

          // Send button
          IconButton(
            onPressed: _send,
            icon: Icon(
              Icons.arrow_upward,
              size: 20,
              color: colors.accentBright,
            ),
            style: IconButton.styleFrom(
              backgroundColor: colors.accentDim,
              shape: const CircleBorder(),
              minimumSize: const Size(36, 36),
            ),
          ),
        ],
      ),
    ),
      ],
    );
  }

  String _formatTime(DateTime ts) {
    final h = ts.hour;
    final m = ts.minute.toString().padLeft(2, '0');
    final period = h >= 12 ? 'pm' : 'am';
    final hour = h > 12 ? h - 12 : (h == 0 ? 12 : h);
    return '$hour:$m $period';
  }
}
