import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart' as md;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../app/theme/gloam_color_extension.dart';
import '../../../../app/theme/gloam_theme_ext.dart';
import '../../../../app/theme/spacing.dart';
import '../../../../app/theme/theme_preferences.dart';
import '../../../../data/syntax_themes.dart';
import '../../../../services/download_service.dart';
import '../../../../services/matrix_service.dart';
import '../providers/timeline_provider.dart';
import 'markdown_body.dart';
import 'selectable_highlight.dart';

/// The render mode for a file preview.
enum _PreviewMode { markdown, code, plainText, unsupported }

/// Determine how to preview a file based on its extension.
_PreviewMode _modeForFilename(String filename) {
  final ext = filename.split('.').last.toLowerCase();
  switch (ext) {
    case 'md':
    case 'markdown':
      return _PreviewMode.markdown;
    case 'py':
    case 'js':
    case 'ts':
    case 'tsx':
    case 'jsx':
    case 'dart':
    case 'sh':
    case 'bash':
    case 'zsh':
    case 'css':
    case 'scss':
    case 'html':
    case 'xml':
    case 'yaml':
    case 'yml':
    case 'json':
    case 'toml':
    case 'rs':
    case 'go':
    case 'c':
    case 'cpp':
    case 'h':
    case 'hpp':
    case 'java':
    case 'kt':
    case 'swift':
    case 'rb':
    case 'sql':
    case 'r':
    case 'php':
    case 'lua':
    case 'vim':
    case 'dockerfile':
    case 'makefile':
    case 'cmake':
    case 'gradle':
    case 'tf':
    case 'proto':
      return _PreviewMode.code;
    case 'txt':
    case 'log':
    case 'csv':
    case 'tsv':
    case 'env':
    case 'gitignore':
    case 'editorconfig':
    case 'conf':
    case 'ini':
    case 'cfg':
    case 'properties':
      return _PreviewMode.plainText;
    default:
      return _PreviewMode.unsupported;
  }
}

/// Get the highlight.js language name from a file extension.
String _languageForFilename(String filename) {
  final ext = filename.split('.').last.toLowerCase();
  const map = {
    'py': 'python', 'js': 'javascript', 'ts': 'typescript',
    'tsx': 'typescript', 'jsx': 'javascript', 'dart': 'dart',
    'sh': 'bash', 'bash': 'bash', 'zsh': 'bash',
    'css': 'css', 'scss': 'scss', 'html': 'html', 'xml': 'xml',
    'yaml': 'yaml', 'yml': 'yaml', 'json': 'json', 'toml': 'ini',
    'rs': 'rust', 'go': 'go', 'c': 'c', 'cpp': 'cpp',
    'h': 'c', 'hpp': 'cpp', 'java': 'java', 'kt': 'kotlin',
    'swift': 'swift', 'rb': 'ruby', 'sql': 'sql', 'r': 'r',
    'php': 'php', 'lua': 'lua', 'dockerfile': 'dockerfile',
    'makefile': 'makefile', 'tf': 'hcl', 'proto': 'protobuf',
    'gradle': 'gradle', 'cmake': 'cmake',
  };
  return map[ext] ?? 'plaintext';
}

/// Show a file preview modal for a file attachment.
void showFilePreview(
  BuildContext context,
  WidgetRef ref, {
  required TimelineMessage message,
  required String roomId,
}) {
  showDialog(
    context: context,
    builder: (_) => _FilePreviewDialog(
      message: message,
      roomId: roomId,
    ),
  );
}

class _FilePreviewDialog extends ConsumerStatefulWidget {
  const _FilePreviewDialog({
    required this.message,
    required this.roomId,
  });

  final TimelineMessage message;
  final String roomId;

  @override
  ConsumerState<_FilePreviewDialog> createState() => _FilePreviewDialogState();
}

class _FilePreviewDialogState extends ConsumerState<_FilePreviewDialog> {
  String? _content;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadFile();
  }

  String get _filename => widget.message.body;
  _PreviewMode get _mode => _modeForFilename(_filename);

  String _formatBytes(int? bytes) {
    if (bytes == null) return '';
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  Future<void> _loadFile() async {
    if (_mode == _PreviewMode.unsupported) {
      setState(() => _loading = false);
      return;
    }

    try {
      final client = ref.read(matrixServiceProvider).client;
      if (client == null) throw Exception('Not connected');

      final matrixFile = await DownloadService.downloadAttachment(
        client,
        widget.roomId,
        widget.message.eventId,
      );

      // Check size limit
      final maxSize = 1024 * 1024; // 1MB default
      if (matrixFile.bytes.length > maxSize) {
        setState(() {
          _loading = false;
          _error = 'too_large';
        });
        return;
      }

      final text = utf8.decode(matrixFile.bytes, allowMalformed: true);
      if (mounted) setState(() { _content = text; _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    }
  }

  Future<void> _download() async {
    try {
      final client = ref.read(matrixServiceProvider).client;
      if (client == null) return;

      final matrixFile = await DownloadService.downloadAttachment(
        client,
        widget.roomId,
        widget.message.eventId,
      );

      await DownloadService.saveFile(
        bytes: matrixFile.bytes,
        filename: matrixFile.name,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Download failed: $e'),
            backgroundColor: context.gloam.danger,
          ),
        );
      }
    }
  }

  void _copyAll() {
    if (_content != null) {
      Clipboard.setData(ClipboardData(text: _content!));
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Copied to clipboard'),
          duration: Duration(seconds: 1),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.gloam;
    final size = MediaQuery.of(context).size;

    return KeyboardListener(
      focusNode: FocusNode()..requestFocus(),
      onKeyEvent: (event) {
        if (event is! KeyDownEvent) return;
        // Cmd+S → download
        if (event.logicalKey == LogicalKeyboardKey.keyS &&
            HardwareKeyboard.instance.isMetaPressed) {
          _download();
        }
        // Cmd+Shift+C → copy all
        if (event.logicalKey == LogicalKeyboardKey.keyC &&
            HardwareKeyboard.instance.isMetaPressed &&
            HardwareKeyboard.instance.isShiftPressed) {
          _copyAll();
        }
      },
      child: Dialog(
        backgroundColor: colors.bgSurface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(GloamSpacing.radiusMd),
          side: BorderSide(color: colors.border),
        ),
        child: SizedBox(
          width: size.width * 0.8,
          height: size.height * 0.85,
          child: Column(
            children: [
              _buildHeader(colors),
              Container(height: 1, color: colors.border),
              Expanded(child: _buildBody(colors)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(GloamColorExtension colors) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 12, 14),
      child: Row(
        children: [
          Icon(Icons.description_outlined, size: 16, color: colors.accent),
          const SizedBox(width: 10),
          Expanded(
            child: Text.rich(
              TextSpan(children: [
                TextSpan(
                  text: _filename,
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 13, fontWeight: FontWeight.w600,
                    color: colors.textPrimary,
                  ),
                ),
                if (widget.message.mediaSizeBytes != null) ...[
                  TextSpan(
                    text: '  ·  ${_formatBytes(widget.message.mediaSizeBytes)}',
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 11, color: colors.textTertiary,
                    ),
                  ),
                ],
                TextSpan(
                  text: '  ·  ${widget.message.senderName}',
                  style: GoogleFonts.inter(
                    fontSize: 12, color: colors.textTertiary,
                  ),
                ),
              ]),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          Tooltip(
            message: 'Download (⌘S)',
            child: IconButton(
              onPressed: _download,
              icon: Icon(Icons.download_outlined, size: 18, color: colors.textSecondary),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            ),
          ),
          if (_content != null)
            Tooltip(
              message: 'Copy all (⌘⇧C)',
              child: IconButton(
                onPressed: _copyAll,
                icon: Icon(Icons.copy_outlined, size: 16, color: colors.textSecondary),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              ),
            ),
          Tooltip(
            message: 'Close (Esc)',
            child: IconButton(
              onPressed: () => Navigator.pop(context),
              icon: Icon(Icons.close, size: 18, color: colors.textTertiary),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody(GloamColorExtension colors) {
    if (_loading) {
      return Center(
        child: CircularProgressIndicator(color: colors.accent, strokeWidth: 2),
      );
    }

    if (_error == 'too_large') {
      return _buildMetadataCard(colors, 'File too large to preview');
    }

    if (_error != null) {
      return _buildMetadataCard(colors, 'Failed to load file');
    }

    if (_mode == _PreviewMode.unsupported) {
      return _buildMetadataCard(colors, 'Preview not available for this file type');
    }

    final content = _content!;
    final themePrefs = ref.watch(themePreferencesProvider);

    // Wrap all previewable content in SelectionArea for cross-widget
    // click-and-drag text selection with Cmd+C support.
    return SelectionArea(
      child: switch (_mode) {
        _PreviewMode.markdown => SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: MarkdownBody(
              text: content,
              syntaxThemeId: themePrefs.syntaxThemeId,
              selectable: false, // SelectionArea handles selection
            ),
          ),

        _PreviewMode.code => SingleChildScrollView(
            child: SelectableHighlightView(
              content,
              language: _languageForFilename(_filename),
              theme: getSyntaxTheme(themePrefs.syntaxThemeId),
              padding: const EdgeInsets.all(20),
              textStyle: GoogleFonts.jetBrainsMono(fontSize: 13, height: 1.6),
            ),
          ),

        _PreviewMode.plainText => SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Text(
              content,
              style: GoogleFonts.jetBrainsMono(
                fontSize: 13, color: colors.textPrimary, height: 1.6,
              ),
            ),
          ),

        _PreviewMode.unsupported => _buildMetadataCard(colors, 'Preview not available'),
      },
    );
  }

  Widget _buildMetadataCard(GloamColorExtension colors, String message) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.insert_drive_file_outlined, size: 48, color: colors.textTertiary),
          const SizedBox(height: 16),
          Text(
            _filename,
            style: GoogleFonts.jetBrainsMono(
              fontSize: 14, fontWeight: FontWeight.w600, color: colors.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '${_formatBytes(widget.message.mediaSizeBytes)}  ·  ${widget.message.senderName}',
            style: GoogleFonts.inter(fontSize: 12, color: colors.textTertiary),
          ),
          const SizedBox(height: 8),
          Text(
            message,
            style: GoogleFonts.inter(fontSize: 13, color: colors.textSecondary),
          ),
          const SizedBox(height: 20),
          ElevatedButton.icon(
            onPressed: _download,
            icon: const Icon(Icons.download_outlined, size: 16),
            label: const Text('Download'),
            style: ElevatedButton.styleFrom(
              backgroundColor: colors.accentDim,
              foregroundColor: colors.accentBright,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
