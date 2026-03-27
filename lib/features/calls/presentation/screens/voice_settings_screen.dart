import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../app/theme/color_tokens.dart';
import '../../../../app/theme/spacing.dart';
import '../../../../services/audio_device_service.dart';
import '../../../settings/presentation/widgets/settings_tile.dart';

/// Voice & Audio settings section.
///
/// Embedded inside the settings modal — no Scaffold, no header.
/// Renders as a ListView matching other settings sections.
class VoiceSettingsScreen extends ConsumerStatefulWidget {
  const VoiceSettingsScreen({super.key});

  @override
  ConsumerState<VoiceSettingsScreen> createState() =>
      _VoiceSettingsScreenState();
}

class _VoiceSettingsScreenState extends ConsumerState<VoiceSettingsScreen> {
  bool _isVoiceActivity = true;
  double _sensitivity = 0.35;
  double _pttReleaseDelay = 200;

  // Device lists loaded asynchronously
  List<MediaDeviceInfo> _inputDevices = [];
  List<MediaDeviceInfo> _outputDevices = [];
  bool _devicesLoaded = false;

  // Mic test state
  bool _isTesting = false;
  String _testStatus = '';
  MediaStream? _testStream;
  Timer? _testTimer;
  int _testCountdown = 0;

  @override
  void initState() {
    super.initState();
    _loadDevices();
  }

  @override
  void dispose() {
    _testTimer?.cancel();
    _testStream?.dispose();
    super.dispose();
  }

  Future<void> _loadDevices() async {
    final audioService = ref.read(audioDeviceServiceProvider);
    try {
      final inputs = await audioService.getInputDevices();
      final outputs = await audioService.getOutputDevices();
      if (mounted) {
        setState(() {
          _inputDevices = inputs;
          _outputDevices = outputs;
          _devicesLoaded = true;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _devicesLoaded = true;
          _testStatus = 'Device enumeration failed: $e';
        });
      }
    }
  }

  Future<void> _testMicrophone() async {
    if (_isTesting) return;

    final audioService = ref.read(audioDeviceServiceProvider);
    setState(() {
      _isTesting = true;
      _testStatus = 'Recording...';
      _testCountdown = 3;
    });

    try {
      // Capture audio from mic
      _testStream = await navigator.mediaDevices.getUserMedia({
        'audio': {
          if (audioService.selectedInputId != null)
            'deviceId': audioService.selectedInputId,
          'echoCancellation': audioService.echoCancellation,
          'noiseSuppression': audioService.noiseSuppression,
          'autoGainControl': audioService.autoGainControl,
        },
        'video': false,
      });

      // Countdown 3 seconds
      _testTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (!mounted) {
          timer.cancel();
          return;
        }
        setState(() {
          _testCountdown--;
          if (_testCountdown > 0) {
            _testStatus = 'Recording... $_testCountdown';
          } else {
            _testStatus = 'Playing back...';
          }
        });

        if (_testCountdown <= 0) {
          timer.cancel();
          // Stop recording — in a real implementation we'd play back the audio.
          // For now, just show that the mic was successfully accessed.
          _testStream?.dispose();
          _testStream = null;
          Future.delayed(const Duration(seconds: 1), () {
            if (mounted) {
              setState(() {
                _isTesting = false;
                _testStatus = 'Microphone is working';
              });
              // Clear status after 3 seconds
              Future.delayed(const Duration(seconds: 3), () {
                if (mounted) setState(() => _testStatus = '');
              });
            }
          });
        }
      });
    } catch (e) {
      _testStream?.dispose();
      _testStream = null;
      if (mounted) {
        setState(() {
          _isTesting = false;
          _testStatus = 'Mic access failed: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final audioService = ref.read(audioDeviceServiceProvider);

    // Resolve display names for selected devices
    final selectedInputName = _resolveDeviceName(
      _inputDevices,
      audioService.selectedInputId,
      'Default Microphone',
    );
    final selectedOutputName = _resolveDeviceName(
      _outputDevices,
      audioService.selectedOutputId,
      'Default Speaker',
    );

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        // ── INPUT ──────────────────────────────────────────
        const SettingsSectionHeader('input'),

        // Device selector
        SettingsTile(
          icon: Icons.mic_rounded,
          label: 'Input Device',
          value: _devicesLoaded ? null : 'loading...',
          trailing: _devicesLoaded
              ? _DevicePopupButton(
                  currentName: selectedInputName,
                  devices: _inputDevices,
                  selectedId: audioService.selectedInputId,
                  onSelected: (id) {
                    audioService.setInputDevice(id);
                    setState(() {});
                  },
                )
              : null,
        ),

        // Volume slider
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: _LabeledSlider(
            label: 'Input Volume',
            value: audioService.inputVolume,
            onChanged: (v) {
              audioService.setInputVolume(v);
              setState(() {});
            },
          ),
        ),

        // Test mic button
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          child: Row(
            children: [
              _ActionChip(
                icon: _isTesting ? Icons.stop_rounded : Icons.mic_rounded,
                label: _isTesting ? 'Recording... $_testCountdown' : 'Test Microphone',
                onTap: _testMicrophone,
                isActive: _isTesting,
              ),
              if (_testStatus.isNotEmpty && !_isTesting) ...[
                const SizedBox(width: 12),
                Icon(
                  _testStatus.contains('working')
                      ? Icons.check_circle_outline
                      : Icons.error_outline,
                  size: 14,
                  color: _testStatus.contains('working')
                      ? GloamColors.accent
                      : GloamColors.warning,
                ),
                const SizedBox(width: 6),
                Text(
                  _testStatus,
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 11,
                    color: _testStatus.contains('working')
                        ? GloamColors.accent
                        : GloamColors.warning,
                  ),
                ),
              ],
            ],
          ),
        ),

        // ── OUTPUT ─────────────────────────────────────────
        const SettingsSectionHeader('output'),

        SettingsTile(
          icon: Icons.headphones_rounded,
          label: 'Output Device',
          trailing: _devicesLoaded
              ? _DevicePopupButton(
                  currentName: selectedOutputName,
                  devices: _outputDevices,
                  selectedId: audioService.selectedOutputId,
                  onSelected: (id) {
                    audioService.setOutputDevice(id);
                    setState(() {});
                  },
                )
              : null,
        ),

        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: _LabeledSlider(
            label: 'Output Volume',
            value: audioService.outputVolume,
            onChanged: (v) {
              audioService.setOutputVolume(v);
              setState(() {});
            },
          ),
        ),

        // ── INPUT MODE ─────────────────────────────────────
        const SettingsSectionHeader('input mode'),

        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              Expanded(
                child: _ModeCard(
                  label: 'Voice Activity',
                  isSelected: _isVoiceActivity,
                  onTap: () => setState(() => _isVoiceActivity = true),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _ModeCard(
                  label: 'Push to Talk',
                  isSelected: !_isVoiceActivity,
                  onTap: () => setState(() => _isVoiceActivity = false),
                ),
              ),
            ],
          ),
        ),

        if (_isVoiceActivity)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: _LabeledSlider(
              label: 'Sensitivity',
              value: _sensitivity,
              onChanged: (v) => setState(() => _sensitivity = v),
            ),
          )
        else ...[
          SettingsTile(
            icon: Icons.keyboard_rounded,
            label: 'Keybind',
            trailing: GestureDetector(
              onTap: () {
                // TODO: key capture dialog
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: GloamColors.bgSurface,
                  borderRadius: BorderRadius.circular(GloamSpacing.radiusSm),
                  border: Border.all(color: GloamColors.border),
                ),
                child: Text(
                  'Click to set',
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 11,
                    color: GloamColors.textTertiary,
                  ),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: _LabeledSlider(
              label: 'Release Delay',
              value: _pttReleaseDelay / 500,
              onChanged: (v) => setState(() => _pttReleaseDelay = v * 500),
              suffix: '${_pttReleaseDelay.round()}ms',
            ),
          ),
        ],

        // ── VOICE PROCESSING ───────────────────────────────
        const SettingsSectionHeader('voice processing'),

        _ToggleTile(
          label: 'Echo Cancellation',
          subtitle: 'Prevents feedback when using speakers',
          value: audioService.echoCancellation,
          onChanged: (v) {
            audioService.echoCancellation = v;
            setState(() {});
          },
        ),
        _ToggleTile(
          label: 'Noise Reduction',
          subtitle: 'Reduces background noise',
          value: audioService.noiseSuppression,
          onChanged: (v) {
            audioService.noiseSuppression = v;
            setState(() {});
          },
        ),
        _ToggleTile(
          label: 'Auto Gain Control',
          subtitle: 'Normalizes microphone volume automatically',
          value: audioService.autoGainControl,
          onChanged: (v) {
            audioService.autoGainControl = v;
            setState(() {});
          },
        ),
      ],
    );
  }

  String _resolveDeviceName(
    List<MediaDeviceInfo> devices,
    String? selectedId,
    String fallback,
  ) {
    if (selectedId == null) return fallback;
    final device = devices.where((d) => d.deviceId == selectedId).firstOrNull;
    return device?.label ?? fallback;
  }
}

// =============================================================================
// Reusable widgets
// =============================================================================

/// A popup button that shows available audio devices.
class _DevicePopupButton extends StatelessWidget {
  const _DevicePopupButton({
    required this.currentName,
    required this.devices,
    required this.selectedId,
    required this.onSelected,
  });

  final String currentName;
  final List<MediaDeviceInfo> devices;
  final String? selectedId;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      onSelected: onSelected,
      color: GloamColors.bgElevated,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: const BorderSide(color: GloamColors.border),
      ),
      offset: const Offset(0, 36),
      itemBuilder: (_) => devices.map((d) {
        final isSelected = d.deviceId == selectedId;
        return PopupMenuItem<String>(
          value: d.deviceId,
          height: 36,
          child: Row(
            children: [
              if (isSelected)
                const Icon(Icons.check, size: 14, color: GloamColors.accent)
              else
                const SizedBox(width: 14),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  d.label.isNotEmpty ? d.label : d.deviceId,
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    color: isSelected
                        ? GloamColors.accent
                        : GloamColors.textPrimary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        );
      }).toList(),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 220),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: GloamColors.bgSurface,
          borderRadius: BorderRadius.circular(GloamSpacing.radiusSm),
          border: Border.all(color: GloamColors.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                currentName,
                style: GoogleFonts.inter(
                  fontSize: 12,
                  color: GloamColors.textPrimary,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 6),
            const Icon(Icons.keyboard_arrow_down,
                size: 14, color: GloamColors.textTertiary),
          ],
        ),
      ),
    );
  }
}

class _LabeledSlider extends StatelessWidget {
  const _LabeledSlider({
    required this.label,
    required this.value,
    required this.onChanged,
    this.suffix,
  });

  final String label;
  final double value;
  final ValueChanged<double> onChanged;
  final String? suffix;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: GoogleFonts.inter(
                fontSize: 13,
                color: GloamColors.textSecondary,
              ),
            ),
          ),
          Expanded(
            child: SliderTheme(
              data: SliderThemeData(
                activeTrackColor: GloamColors.accent,
                inactiveTrackColor: GloamColors.border,
                thumbColor: GloamColors.accent,
                overlayColor: GloamColors.accent.withAlpha(30),
                trackHeight: 4,
                thumbShape:
                    const RoundSliderThumbShape(enabledThumbRadius: 7),
              ),
              child: Slider(value: value, onChanged: onChanged),
            ),
          ),
          SizedBox(
            width: 44,
            child: Text(
              suffix ?? '${(value * 100).round()}%',
              style: GoogleFonts.jetBrainsMono(
                fontSize: 11,
                color: GloamColors.textSecondary,
              ),
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }
}

class _ModeCard extends StatelessWidget {
  const _ModeCard({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 44,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: isSelected ? GloamColors.accentDim : GloamColors.bgSurface,
          borderRadius: BorderRadius.circular(GloamSpacing.radiusMd),
          border: Border.all(
            color: isSelected ? GloamColors.accent : GloamColors.border,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 14,
              height: 14,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: isSelected
                      ? GloamColors.accent
                      : GloamColors.textTertiary,
                  width: 2,
                ),
              ),
              child: isSelected
                  ? Center(
                      child: Container(
                        width: 8,
                        height: 8,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: GloamColors.accent,
                        ),
                      ),
                    )
                  : null,
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: GoogleFonts.inter(
                fontSize: 13,
                fontWeight: isSelected ? FontWeight.w500 : FontWeight.w400,
                color: isSelected
                    ? GloamColors.textPrimary
                    : GloamColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ToggleTile extends StatelessWidget {
  const _ToggleTile({
    required this.label,
    this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    color: GloamColors.textPrimary,
                  ),
                ),
                if (subtitle != null)
                  Text(
                    subtitle!,
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      color: GloamColors.textTertiary,
                    ),
                  ),
              ],
            ),
          ),
          GestureDetector(
            onTap: () => onChanged(!value),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 40,
              height: 22,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(11),
                color: value ? GloamColors.accent : GloamColors.border,
              ),
              child: AnimatedAlign(
                duration: const Duration(milliseconds: 200),
                alignment:
                    value ? Alignment.centerRight : Alignment.centerLeft,
                child: Padding(
                  padding: const EdgeInsets.all(2),
                  child: Container(
                    width: 18,
                    height: 18,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: value ? Colors.white : GloamColors.textSecondary,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionChip extends StatelessWidget {
  const _ActionChip({
    required this.icon,
    required this.label,
    required this.onTap,
    this.isActive = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool isActive;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: isActive ? GloamColors.accentDim : GloamColors.bgSurface,
      borderRadius: BorderRadius.circular(GloamSpacing.radiusMd),
      child: InkWell(
        onTap: isActive ? null : onTap,
        borderRadius: BorderRadius.circular(GloamSpacing.radiusMd),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(GloamSpacing.radiusMd),
            border: Border.all(
              color: isActive ? GloamColors.accent : GloamColors.border,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon,
                  size: 14,
                  color: isActive ? GloamColors.accent : GloamColors.accent),
              const SizedBox(width: 8),
              Text(
                label,
                style: GoogleFonts.inter(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: isActive
                      ? GloamColors.accent
                      : GloamColors.textPrimary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
