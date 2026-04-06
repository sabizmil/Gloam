import 'dart:io';
import 'dart:typed_data';

import 'package:matrix/matrix.dart';
import 'package:mime/mime.dart';

/// Shared upload pipeline — converts raw file bytes into the appropriate
/// Matrix file type (image, video, audio, generic) with metadata.
class UploadService {
  /// Maximum upload size (50MB default, overridden by homeserver config).
  static const maxFileSizeBytes = 50 * 1024 * 1024;

  /// Create the appropriate MatrixFile subtype based on MIME type.
  static MatrixFile createMatrixFile({
    required Uint8List bytes,
    required String name,
  }) {
    // Prioritise extension-based detection. The mime package's header-byte
    // detector shares magic bytes for Matroska containers (WebM / WebA) and
    // returns audio/weba for video-only .webm files. Fall back to header
    // bytes only when the extension is unrecognised.
    final mimeType = lookupMimeType(name) ??
        lookupMimeType(name, headerBytes: bytes) ??
        'application/octet-stream';

    if (mimeType.startsWith('image/')) {
      return MatrixImageFile(
        bytes: bytes,
        name: name,
        mimeType: mimeType,
      );
    }

    if (mimeType.startsWith('video/')) {
      return MatrixVideoFile(
        bytes: bytes,
        name: name,
        mimeType: mimeType,
      );
    }

    if (mimeType.startsWith('audio/')) {
      return MatrixAudioFile(
        bytes: bytes,
        name: name,
        mimeType: mimeType,
      );
    }

    return MatrixFile(
      bytes: bytes,
      name: name,
      mimeType: mimeType,
    );
  }

  /// Validate file size. Returns null if OK, or an error message.
  static String? validateFileSize(int bytes) {
    if (bytes > maxFileSizeBytes) {
      final sizeMb = (bytes / (1024 * 1024)).toStringAsFixed(1);
      return 'file too large ($sizeMb MB). maximum is ${maxFileSizeBytes ~/ (1024 * 1024)} MB.';
    }
    return null;
  }

  /// Read a file from disk and create the appropriate MatrixFile.
  static Future<MatrixFile> fromPath(String path) async {
    final file = File(path);
    final bytes = await file.readAsBytes();
    final name = path.split('/').last.split('\\').last;
    return createMatrixFile(bytes: bytes, name: name);
  }
}
