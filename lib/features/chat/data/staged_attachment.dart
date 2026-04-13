import 'package:matrix/matrix.dart';

/// A file the user has attached to the composer but not yet sent.
/// Holds the already-validated [MatrixFile] (bytes + name + mimeType + info).
/// [id] is used as a stable widget key and removal target — not derived from
/// the file so duplicate attachments stay distinguishable.
class StagedAttachment {
  const StagedAttachment({required this.id, required this.file});
  final String id;
  final MatrixFile file;

  bool get isImage => file is MatrixImageFile;
  bool get isVideo => file is MatrixVideoFile;
}
