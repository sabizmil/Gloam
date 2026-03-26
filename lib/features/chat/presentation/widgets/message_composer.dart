import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../app/theme/color_tokens.dart';
import 'emoji_picker.dart';
import '../../../../app/theme/spacing.dart';

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

class MessageComposer extends StatefulWidget {
  const MessageComposer({
    super.key,
    required this.roomName,
    required this.onSend,
    this.onReply,
    this.onEdit,
    this.onTyping,
    this.onAttach,
    this.onEditLastMessage,
    this.composerState = const ComposerState(),
    this.onCancelAction,
  });

  final String roomName;
  final void Function(String text) onSend;
  final void Function(String text, String eventId)? onReply;
  final void Function(String text, String eventId)? onEdit;
  final void Function(bool isTyping)? onTyping;
  final VoidCallback? onAttach;
  final VoidCallback? onEditLastMessage;
  final ComposerState composerState;
  final VoidCallback? onCancelAction;

  @override
  State<MessageComposer> createState() => _MessageComposerState();
}

class _MessageComposerState extends State<MessageComposer> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  bool _hasText = false;
  bool _isTyping = false;

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
    return Container(
      decoration: const BoxDecoration(
        border: Border(
          top: BorderSide(color: GloamColors.border),
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

          // Composer row
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: GloamSpacing.xl,
              vertical: 8,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                // Attachment button
                IconButton(
                  onPressed: widget.onAttach,
                  icon: const Icon(Icons.add_circle_outline,
                      size: 22, color: GloamColors.textTertiary),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                      minWidth: 36, minHeight: 36),
                ),
                const SizedBox(width: 8),

                // Text field
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: GloamColors.bgSurface,
                      borderRadius:
                          BorderRadius.circular(GloamSpacing.radiusSm),
                      border: Border.all(color: GloamColors.border),
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
                          color: GloamColors.textPrimary,
                        ),
                        decoration: InputDecoration(
                          hintText: widget.composerState.mode ==
                                  ComposerMode.edit
                              ? 'edit message...'
                              : 'message #${widget.roomName}',
                          hintStyle: GoogleFonts.inter(
                            fontSize: 14,
                            color: GloamColors.textTertiary,
                          ),
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 10,
                          ),
                          suffixIcon: IconButton(
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
                            icon: const Icon(Icons.sentiment_satisfied_outlined,
                                size: 20, color: GloamColors.textTertiary),
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
                  opacity: _hasText ? 1.0 : 0.3,
                  child: IconButton(
                    onPressed: _hasText ? _handleSend : null,
                    icon: Icon(
                      widget.composerState.mode == ComposerMode.edit
                          ? Icons.check
                          : Icons.arrow_upward,
                      size: 20,
                      color: GloamColors.accentBright,
                    ),
                    style: IconButton.styleFrom(
                      backgroundColor: GloamColors.accentDim,
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
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      decoration: const BoxDecoration(
        border: Border(
          bottom: BorderSide(color: GloamColors.borderSubtle),
        ),
      ),
      child: Row(
        children: [
          Icon(
            mode == ComposerMode.reply ? Icons.reply : Icons.edit_outlined,
            size: 16,
            color: GloamColors.accent,
          ),
          const SizedBox(width: 8),
          Text(
            mode == ComposerMode.reply
                ? 'replying to $senderName'
                : 'editing message',
            style: GoogleFonts.jetBrainsMono(
              fontSize: 11,
              color: GloamColors.accent,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              body ?? '',
              style: GoogleFonts.inter(
                fontSize: 12,
                color: GloamColors.textTertiary,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          GestureDetector(
            onTap: onCancel,
            child: const Icon(Icons.close,
                size: 16, color: GloamColors.textTertiary),
          ),
        ],
      ),
    );
  }
}
