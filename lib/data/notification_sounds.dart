import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// A notification sound entry.
class NotificationSoundEntry {
  final String id;
  final String displayName;
  final bool isBuiltIn;

  const NotificationSoundEntry({
    required this.id,
    required this.displayName,
    this.isBuiltIn = true,
  });

  /// Asset path for preview playback via audioplayers.
  String get previewAsset => isBuiltIn
      ? 'assets/sounds/$id.wav'
      : id; // custom sounds use full path

  /// macOS bundle sound filename (without extension — the system adds it).
  String get macOsSound => '$id.aiff';
}

/// Built-in notification sounds.
const builtInSounds = <NotificationSoundEntry>[
  NotificationSoundEntry(id: 'soft_tap', displayName: 'Soft Tap'),
  NotificationSoundEntry(id: 'gentle_ping', displayName: 'Gentle Ping'),
  NotificationSoundEntry(id: 'low_tone', displayName: 'Low Tone'),
  NotificationSoundEntry(id: 'chime', displayName: 'Chime'),
  NotificationSoundEntry(id: 'click', displayName: 'Click'),
  NotificationSoundEntry(id: 'pulse', displayName: 'Pulse'),
  NotificationSoundEntry(id: 'drop', displayName: 'Drop'),
];

/// Get the directory for user-added custom sounds.
Future<Directory> getCustomSoundsDir() async {
  final appDir = await getApplicationSupportDirectory();
  final soundsDir = Directory('${appDir.path}/sounds');
  if (!soundsDir.existsSync()) soundsDir.createSync(recursive: true);
  return soundsDir;
}

/// Scan for user-added custom sound files.
Future<List<NotificationSoundEntry>> getCustomSounds() async {
  final dir = await getCustomSoundsDir();
  final entries = <NotificationSoundEntry>[];
  for (final file in dir.listSync()) {
    if (file is! File) continue;
    final name = file.path.split('/').last.split('\\').last;
    final ext = name.split('.').last.toLowerCase();
    if (!{'wav', 'mp3', 'aiff', 'm4a', 'ogg'}.contains(ext)) continue;
    entries.add(NotificationSoundEntry(
      id: file.path,
      displayName: name,
      isBuiltIn: false,
    ));
  }
  return entries;
}

/// Get all available sounds (built-in + custom).
Future<List<NotificationSoundEntry>> getAllSounds() async {
  final custom = await getCustomSounds();
  return [...builtInSounds, ...custom];
}

/// Find a sound entry by ID. Returns null if not found.
Future<NotificationSoundEntry?> findSound(String id) async {
  for (final s in builtInSounds) {
    if (s.id == id) return s;
  }
  // Check custom
  final custom = await getCustomSounds();
  for (final s in custom) {
    if (s.id == id) return s;
  }
  return null;
}
