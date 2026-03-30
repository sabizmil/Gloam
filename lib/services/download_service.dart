import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:matrix/matrix.dart';
import 'package:url_launcher/url_launcher.dart';

/// Downloads and saves Matrix file attachments.
/// Mirrors [UploadService] for architectural symmetry.
class DownloadService {
  /// Download (and decrypt if needed) a file attachment from the homeserver.
  /// Returns a [MatrixFile] with the bytes and filename.
  static Future<MatrixFile> downloadAttachment(
    Client client,
    String roomId,
    String eventId,
  ) async {
    final room = client.getRoomById(roomId);
    if (room == null) throw Exception('Room not found');

    final event = await room.getEventById(eventId);
    if (event == null) throw Exception('Event not found');

    // downloadAndDecryptAttachment handles both encrypted and unencrypted
    return await event.downloadAndDecryptAttachment();
  }

  /// Save file bytes to disk using a platform-appropriate method.
  /// Desktop: native save dialog via FilePicker.
  /// Returns the saved path, or null if the user cancelled.
  static Future<String?> saveFile({
    required List<int> bytes,
    required String filename,
  }) async {
    if (Platform.isMacOS || Platform.isWindows || Platform.isLinux) {
      return _saveDesktop(bytes: bytes, filename: filename);
    }
    // Mobile: save to temp and return path (share_plus can be added later)
    return _saveMobile(bytes: bytes, filename: filename);
  }

  static Future<String?> _saveDesktop({
    required List<int> bytes,
    required String filename,
  }) async {
    final result = await FilePicker.platform.saveFile(
      dialogTitle: 'Save file',
      fileName: filename,
    );
    if (result == null) return null; // User cancelled

    final file = File(result);
    await file.writeAsBytes(bytes);
    return result;
  }

  static Future<String?> _saveMobile({
    required List<int> bytes,
    required String filename,
  }) async {
    // Write to a temp directory for now
    final dir = Directory.systemTemp;
    final path = '${dir.path}/$filename';
    await File(path).writeAsBytes(bytes);
    return path;
  }

  /// Open a saved file with the system default application.
  static Future<void> openFile(String path) async {
    await launchUrl(Uri.file(path));
  }
}
