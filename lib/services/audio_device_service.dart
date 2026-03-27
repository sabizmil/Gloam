import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

/// Protocol-independent audio device management.
///
/// Handles input/output device enumeration, selection, and volume.
/// All voice protocol adapters share this service rather than each
/// reimplementing device management.
class AudioDeviceService {
  String? _selectedInputId;
  String? _selectedOutputId;
  double _inputVolume = 0.8;
  double _outputVolume = 0.9;

  bool echoCancellation = true;
  bool noiseSuppression = true;
  bool autoGainControl = true;

  String? get selectedInputId => _selectedInputId;
  String? get selectedOutputId => _selectedOutputId;
  double get inputVolume => _inputVolume;
  double get outputVolume => _outputVolume;

  /// Get all available audio input devices (microphones).
  Future<List<MediaDeviceInfo>> getInputDevices() async {
    final devices = await navigator.mediaDevices.enumerateDevices();
    return devices
        .where((d) => d.kind == 'audioinput')
        .toList();
  }

  /// Get all available audio output devices (speakers/headphones).
  Future<List<MediaDeviceInfo>> getOutputDevices() async {
    final devices = await navigator.mediaDevices.enumerateDevices();
    return devices
        .where((d) => d.kind == 'audiooutput')
        .toList();
  }

  /// Select an audio input device.
  void setInputDevice(String deviceId) {
    _selectedInputId = deviceId;
  }

  /// Select an audio output device.
  void setOutputDevice(String deviceId) {
    _selectedOutputId = deviceId;
  }

  /// Set input (microphone) volume. Range: 0.0 – 1.0.
  void setInputVolume(double volume) {
    _inputVolume = volume.clamp(0.0, 1.0);
  }

  /// Set output (speaker) volume. Range: 0.0 – 1.0.
  void setOutputVolume(double volume) {
    _outputVolume = volume.clamp(0.0, 1.0);
  }

  /// WebRTC media constraints for audio capture, incorporating
  /// the current device selection and processing settings.
  Map<String, dynamic> get audioConstraints => {
        'audio': {
          if (_selectedInputId != null) 'deviceId': _selectedInputId,
          'echoCancellation': echoCancellation,
          'noiseSuppression': noiseSuppression,
          'autoGainControl': autoGainControl,
        },
      };
}

/// Global AudioDeviceService provider.
final audioDeviceServiceProvider = Provider<AudioDeviceService>((ref) {
  return AudioDeviceService();
});
