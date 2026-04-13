import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../app/theme/gloam_theme_ext.dart';
import '../../../../app/theme/spacing.dart';
import '../../../../services/klipy_service.dart';
import '../providers/draft_attachments_provider.dart';
import 'attachment_chip_strip.dart';
import 'emoji_picker.dart';
import 'gif_picker.dart';
import 'mention_autocomplete.dart';

/// The state of the composer — normal, replying to a message, or editing.
class ComposerState {
  final ComposerMode mode;
  final String? targetEventId;
  final String? targetSenderName;
  final String? targetBody;

  const ComposerState({
    this.mode = ComposerMode.normal,
    this.targetEventId,
    this.targetSenderName,
    this.targetBody,
  });

  static const normal = ComposerState();
}

enum ComposerMode { normal, reply, edit }

class MessageComposer extends ConsumerStatefulWidget {
  const MessageComposer({
    super.key,
    required this.roomName,
    required this.roomId,
    required this.onSend,
    this.onSendWithAttachments,
    this.onReply,
    this.onEdit,
    this.onTyping,
    this.onAttach,
    this.onEditLastMessage,
    this.composerState = const ComposerState(),
    this.onCancelAction,
    this.onGif,
  });

  final String roomName;
  final String roomId;
  final void Function(String text) onSend;

  /// Called when the user submits with staged attachments. The handler is
  /// expected to read the draft provider, send, and clear.
  final void Function(String text)? onSendWithAttachments;

  final void Function(String text, String eventId)? onReply;
  final void Function(String text, String eventId)? onEdit;
  final void Function(bool isTyping)? onTyping;
  final VoidCallback? onAttach;
  final VoidCallback? onEditLastMessage;
  final ComposerState composerState;
  final VoidCallback? onCancelAction;
  final void Function(KlipyItem item)? onGif;

  @override
  MessageComposerState createState() => MessageComposerState();
}

class MessageComposerState extends ConsumerState<MessageComposer> {
  final _controller = MentionTextController();
  final _focusNode = FocusNode();
  final _autocompleteKey = GlobalKey<MentionAutocompleteState>();
  bool _hasText = false;
  bool _isTyping = false;

  /// Focus the composer input.
  void focus() => _focusNode.requestFocus();

  /// Get the current composer text.
  String get text => _controller.text;

  /// Set the composer text (used to undo filename paste after file upload).
  set text(String value) {
    _controller.text = value;
    _controller.selection = TextSelection.collapsed(offset: value.length);
  }

  /// Insert text at the current cursor position (used for manual paste fallback).
  void pasteText(String pasteContent) {
    final sel = _controller.selection;
    final current = _controller.text;
    if (sel.isValid) {
      final newText = current.replaceRange(sel.start, sel.end, pasteContent);
      _controller.text = newText;
      _controller.selection = TextSelection.collapsed(
        offset: sel.start + pasteContent.length,
      );
    } else {
      _controller.text = current + pasteContent;
      _controller.selection = TextSelection.collapsed(
        offset: _controller.text.length,
      );
    }
  }

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onTextChanged);
  }

  @override
  void didUpdateWidget(MessageComposer oldWidget) {
    super.didUpdateWidget(oldWidget);
    // When entering edit mode, populate with original text
    if (widget.composerState.mode == ComposerMode.edit &&
        oldWidget.composerState.mode != ComposerMode.edit) {
      _controller.text = widget.composerState.targetBody ?? '';
      _controller.selection = TextSelection.fromPosition(
        TextPosition(offset: _controller.text.length),
      );
      _focusNode.requestFocus();
    }
    // When entering reply mode, focus the input
    if (widget.composerState.mode == ComposerMode.reply &&
        oldWidget.composerState.mode != ComposerMode.reply) {
      _focusNode.requestFocus();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onTextChanged() {
    final hasText = _controller.text.trim().isNotEmpty;
    if (hasText != _hasText) {
      setState(() => _hasText = hasText);
    }

    // Typing indicator — debounced
    if (hasText && !_isTyping) {
      _isTyping = true;
      widget.onTyping?.call(true);
    } else if (!hasText && _isTyping) {
      _isTyping = false;
      widget.onTyping?.call(false);
    }
  }

  void _handleSend() {
    final text = _controller.text.trim();
    final attachments = ref.read(draftAttachmentsProvider(widget.roomId));

    // Attachments present — route to the combined send path regardless of mode.
    // Edit mode + attachments is explicitly unsupported (see chip strip gating
    // in build), so reply + attachments and normal + attachments fall here.
    if (attachments.isNotEmpty) {
      widget.onSendWithAttachments?.call(text);
      _controller.clear();
      _isTyping = false;
      widget.onTyping?.call(false);
      widget.onCancelAction?.call();
      return;
    }

    if (text.isEmpty) return;

    switch (widget.composerState.mode) {
      case ComposerMode.reply:
        widget.onReply?.call(text, widget.composerState.targetEventId!);
      case ComposerMode.edit:
        widget.onEdit?.call(text, widget.composerState.targetEventId!);
      case ComposerMode.normal:
        widget.onSend(text);
    }

    _controller.clear();
    _isTyping = false;
    widget.onTyping?.call(false);
    widget.onCancelAction?.call();
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }

    // Let the mention autocomplete handle navigation keys first
    if (_autocompleteKey.currentState?.handleKeyEvent(event) == true) {
      return KeyEventResult.handled;
    }

    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    // Enter to send (without shift)
    if (event.logicalKey == LogicalKeyboardKey.enter &&
        !HardwareKeyboard.instance.isShiftPressed) {
      _handleSend();
      return KeyEventResult.handled;
    }

    // Escape to cancel reply/edit
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      if (widget.composerState.mode != ComposerMode.normal) {
        widget.onCancelAction?.call();
        return KeyEventResult.handled;
      }
    }

    // Up Arrow in empty composer → edit last own message
    if (event.logicalKey == LogicalKeyboardKey.arrowUp &&
        _controller.text.isEmpty &&
        widget.composerState.mode == ComposerMode.normal) {
      widget.onEditLastMessage?.call();
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.gloam;
    final attachments = ref.watch(draftAttachmentsProvider(widget.roomId));
    final isEdit = widget.composerState.mode == ComposerMode.edit;
    // Chips disabled in edit mode — you can't edit a message to add attachments.
    final showChips = attachments.isNotEmpty && !isEdit;
    final canSubmit = _hasText || (attachments.isNotEmpty && !isEdit);
    return Container(
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: colors.border),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Reply/edit bar
          if (widget.composerState.mode != ComposerMode.normal)
            _ActionBar(
              mode: widget.composerState.mode,
              senderName: widget.composerState.targetSenderName,
              body: widget.composerState.targetBody,
              onCancel: widget.onCancelAction,
            ),

          // Staged attachments
          if (showChips)
            AttachmentChipStrip(
              attachments: attachments,
              onRemove: (id) => ref
                  .read(draftAttachmentsProvider(widget.roomId).notifier)
                  .remove(id),
            ),

          // Composer row
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: GloamSpacing.xl,
              vertical: 8,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Attachment button
                IconButton(
                  onPressed: widget.onAttach,
                  icon: Icon(Icons.add_circle_outline,
                      size: 22, color: colors.textTertiary),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                      minWidth: 36, minHeight: 36),
                ),
                const SizedBox(width: 8),

                // Text field
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
                      onKeyEvent: _handleKeyEvent,
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
                          hintText: widget.composerState.mode ==
                                  ComposerMode.edit
                              ? 'edit message...'
                              : 'message #${widget.roomName}',
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
                                  if (item != null) {
                                    widget.onGif?.call(item);
                                  }
                                },
                                icon: Icon(Icons.gif_box_outlined,
                                    size: 20, color: colors.textTertiary),
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(
                                    minWidth: 36, minHeight: 36),
                              ),
                              IconButton(
                                onPressed: () async {
                                  final emoji =
                                      await showEmojiPicker(context);
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
                AnimatedOpacity(
                  duration: const Duration(milliseconds: 150),
                  opacity: canSubmit ? 1.0 : 0.3,
                  child: IconButton(
                    onPressed: canSubmit ? _handleSend : null,
                    icon: Icon(
                      widget.composerState.mode == ComposerMode.edit
                          ? Icons.check
                          : Icons.arrow_upward,
                      size: 20,
                      color: colors.accentBright,
                    ),
                    style: IconButton.styleFrom(
                      backgroundColor: colors.accentDim,
                      shape: const CircleBorder(),
                      minimumSize: const Size(36, 36),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionBar extends StatelessWidget {
  const _ActionBar({
    required this.mode,
    this.senderName,
    this.body,
    this.onCancel,
  });

  final ComposerMode mode;
  final String? senderName;
  final String? body;
  final VoidCallback? onCancel;

  @override
  Widget build(BuildContext context) {
    final colors = context.gloam;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: colors.borderSubtle),
        ),
      ),
      child: Row(
        children: [
          Icon(
            mode == ComposerMode.reply ? Icons.reply : Icons.edit_outlined,
            size: 16,
            color: colors.accent,
          ),
          const SizedBox(width: 8),
          Text(
            mode == ComposerMode.reply
                ? 'replying to $senderName'
                : 'editing message',
            style: GoogleFonts.jetBrainsMono(
              fontSize: 11,
              color: colors.accent,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              body ?? '',
              style: GoogleFonts.inter(
                fontSize: 12,
                color: colors.textTertiary,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          GestureDetector(
            onTap: onCancel,
            child: Icon(Icons.close,
                size: 16, color: colors.textTertiary),
          ),
        ],
      ),
    );
  }
}
