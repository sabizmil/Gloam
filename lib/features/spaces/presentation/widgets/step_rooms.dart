import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../app/theme/gloam_theme_ext.dart';
import '../../../../app/theme/spacing.dart';

/// Step 2: Template picker + editable room list.
class StepRooms extends StatefulWidget {
  const StepRooms({
    super.key,
    required this.roomNames,
    required this.onRoomNamesChanged,
  });

  final List<String> roomNames;
  final ValueChanged<List<String>> onRoomNamesChanged;

  @override
  State<StepRooms> createState() => _StepRoomsState();
}

class _StepRoomsState extends State<StepRooms> {
  String? _selectedTemplate = 'community';
  late List<TextEditingController> _controllers;

  static const _templates = <String, List<String>>{
    'community': ['General', 'Introductions', 'Off-topic'],
    'team': ['General', 'Announcements', 'Random'],
    'project': ['General', 'Tasks', 'Updates'],
    'scratch': [],
  };

  static const _templateLabels = <String, String>{
    'community': 'Community',
    'team': 'Team',
    'project': 'Project',
    'scratch': 'Start from scratch',
  };

  static const _templateIcons = <String, IconData>{
    'community': Icons.groups_outlined,
    'team': Icons.business_outlined,
    'project': Icons.folder_outlined,
    'scratch': Icons.edit_outlined,
  };

  @override
  void initState() {
    super.initState();
    _controllers = widget.roomNames
        .map((n) => TextEditingController(text: n))
        .toList();
  }

  @override
  void dispose() {
    for (final c in _controllers) {
      c.dispose();
    }
    super.dispose();
  }

  void _selectTemplate(String key) {
    setState(() {
      _selectedTemplate = key;
      // Dispose old controllers
      for (final c in _controllers) {
        c.dispose();
      }
      final rooms = List<String>.from(_templates[key]!);
      _controllers = rooms.map((n) => TextEditingController(text: n)).toList();
    });
    widget.onRoomNamesChanged(
        _controllers.map((c) => c.text).toList());
  }

  void _addRoom() {
    setState(() {
      _controllers.add(TextEditingController());
      _selectedTemplate = null; // Deselect template on manual edit
    });
    widget.onRoomNamesChanged(
        _controllers.map((c) => c.text).toList());
  }

  void _removeRoom(int index) {
    setState(() {
      _controllers[index].dispose();
      _controllers.removeAt(index);
      _selectedTemplate = null;
    });
    widget.onRoomNamesChanged(
        _controllers.map((c) => c.text).toList());
  }

  void _onRoomNameChanged(int index, String value) {
    _selectedTemplate = null;
    widget.onRoomNamesChanged(
        _controllers.map((c) => c.text).toList());
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.gloam;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '// template',
            style: GoogleFonts.jetBrainsMono(
              fontSize: 10,
              color: colors.textTertiary,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 10),

          // Template pills
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _templates.keys.map((key) {
              final isSelected = _selectedTemplate == key;
              return GestureDetector(
                onTap: () => _selectTemplate(key),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: isSelected ? colors.accentDim : Colors.transparent,
                    borderRadius:
                        BorderRadius.circular(GloamSpacing.radiusMd),
                    border: Border.all(
                      color: isSelected ? colors.accent : colors.border,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _templateIcons[key],
                        size: 14,
                        color:
                            isSelected ? colors.accent : colors.textTertiary,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        _templateLabels[key]!,
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          fontWeight:
                              isSelected ? FontWeight.w500 : FontWeight.w400,
                          color: isSelected
                              ? colors.accent
                              : colors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),

          const SizedBox(height: 24),

          Text(
            '// rooms',
            style: GoogleFonts.jetBrainsMono(
              fontSize: 10,
              color: colors.textTertiary,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 10),

          // Room list
          if (_controllers.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Text(
                'No rooms yet — add some below or pick a template',
                style: GoogleFonts.inter(
                  fontSize: 13,
                  color: colors.textTertiary,
                ),
              ),
            ),

          ...List.generate(_controllers.length, (index) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Text(
                    '#',
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 16,
                      color: colors.textTertiary,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _controllers[index],
                      onChanged: (v) => _onRoomNameChanged(index, v),
                      style: GoogleFonts.inter(
                        fontSize: 14,
                        color: colors.textPrimary,
                      ),
                      decoration: InputDecoration(
                        hintText: 'room-name',
                        hintStyle: GoogleFonts.inter(
                          fontSize: 14,
                          color: colors.textTertiary,
                        ),
                        filled: true,
                        fillColor: colors.bgElevated,
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 10),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(
                              GloamSpacing.radiusSm),
                          borderSide: BorderSide(color: colors.border),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(
                              GloamSpacing.radiusSm),
                          borderSide: BorderSide(color: colors.border),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(
                              GloamSpacing.radiusSm),
                          borderSide: BorderSide(color: colors.accent),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: () => _removeRoom(index),
                    child: Icon(Icons.close,
                        size: 16, color: colors.textTertiary),
                  ),
                ],
              ),
            );
          }),

          const SizedBox(height: 4),

          // Add room button
          GestureDetector(
            onTap: _addRoom,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                borderRadius:
                    BorderRadius.circular(GloamSpacing.radiusSm),
                border: Border.all(
                  color: colors.border,
                  style: BorderStyle.solid,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.add, size: 14, color: colors.accent),
                  const SizedBox(width: 6),
                  Text(
                    'add room',
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 12,
                      color: colors.accent,
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          Text(
            'You can always add more rooms later',
            style: GoogleFonts.inter(
              fontSize: 12,
              color: colors.textTertiary,
            ),
          ),
        ],
      ),
    );
  }
}
