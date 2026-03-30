import 'dart:io';

import 'package:matrix/matrix.dart';
import 'package:pasteboard/pasteboard.dart';

import 'upload_service.dart';

/// Reads image or file data from the system clipboard and converts
/// it into Matrix file types ready for upload.
///
/// Desktop-only (macOS, Windows, Linux). Returns null on mobile.
class ClipboardPasteService {
  /// Read image bytes from the clipboard.
  /// Returns a [MatrixFile] (typically [MatrixImageFile]) if found.
  static Future<MatrixFile?> getClipboardImage() async {
    if (!(Platform.isMacOS || Platform.isWindows || Platform.isLinux)) {
      return null;
    }

    final imageBytes = await Pasteboard.image;
    if (imageBytes == null || imageBytes.isEmpty) return null;

    final timestamp = DateTime.now()
        .toIso8601String()
        .replaceAll(':', '-')
        .split('.')
        .first;
    final filename = 'clipboard-$timestamp.png';

    // Clipboard images are always PNG on macOS/Linux.
    // Create MatrixImageFile directly to ensure it's sent as m.image.
    return MatrixImageFile(
      bytes: imageBytes,
      name: filename,
      mimeType: 'image/png',
    );
  }

  /// Read file paths from the clipboard (e.g. files copied in Finder/Explorer).
  /// Returns a list of [MatrixFile]s, empty if none found.
  static Future<List<MatrixFile>> getClipboardFiles() async {
    if (!(Platform.isMacOS || Platform.isWindows || Platform.isLinux)) {
      return [];
    }

    final paths = await Pasteboard.files();
    if (paths.isEmpty) return [];

    final files = <MatrixFile>[];
    for (final path in paths) {
      try {
        final bytes = await File(path).readAsBytes();
        final sizeError = UploadService.validateFileSize(bytes.length);
        if (sizeError != null) continue;
        files.add(UploadService.createMatrixFile(
          bytes: bytes,
          name: path.split('/').last.split('\\').last,
        ));
      } catch (_) {
        // Skip files that can't be read
      }
    }
    return files;
  }
}
