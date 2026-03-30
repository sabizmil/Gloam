import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../app/theme/gloam_theme_ext.dart';
import '../../../../app/theme/spacing.dart';

/// Dropdown for selecting which Matrix server to browse.
///
/// Shows the user's homeserver (labeled "home"), popular servers,
/// and an option to enter a custom server address.
class ServerSelector extends StatefulWidget {
  const ServerSelector({
    super.key,
    required this.currentServer,
    required this.homeServer,
    required this.onSelected,
  });

  final String currentServer;
  final String homeServer;
  final ValueChanged<String> onSelected;

  @override
  State<ServerSelector> createState() => _ServerSelectorState();
}

class _ServerSelectorState extends State<ServerSelector> {
  bool _showCustomInput = false;
  final _customController = TextEditingController();

  static const _presetServers = [
    'matrix.org',
    'gitter.im',
    'mozilla.org',
    'tchncs.de',
  ];

  @override
  void dispose() {
    _customController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_showCustomInput) {
      return SizedBox(
        width: 220,
        height: 36,
        child: TextField(
          controller: _customController,
          autofocus: true,
          style: GoogleFonts.jetBrainsMono(
            fontSize: 12,
            color: context.gloam.textPrimary,
          ),
          decoration: InputDecoration(
            hintText: 'server.example.com',
            hintStyle: GoogleFonts.jetBrainsMono(
              fontSize: 12,
              color: context.gloam.textTertiary,
            ),
            filled: true,
            fillColor: context.gloam.bgSurface,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(GloamSpacing.radiusMd),
              borderSide: BorderSide(color: context.gloam.border),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(GloamSpacing.radiusMd),
              borderSide: BorderSide(color: context.gloam.border),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(GloamSpacing.radiusMd),
              borderSide: BorderSide(color: context.gloam.accent),
            ),
            suffixIcon: IconButton(
              icon: Icon(Icons.check, size: 16, color: context.gloam.accent),
              onPressed: () {
                final server = _customController.text.trim();
                if (server.isNotEmpty) {
                  widget.onSelected(server);
                  setState(() => _showCustomInput = false);
                }
              },
            ),
          ),
          onSubmitted: (value) {
            if (value.trim().isNotEmpty) {
              widget.onSelected(value.trim());
              setState(() => _showCustomInput = false);
            }
          },
        ),
      );
    }

    return PopupMenuButton<String>(
      onSelected: (value) {
        if (value == '_custom') {
          setState(() => _showCustomInput = true);
        } else {
          widget.onSelected(value);
        }
      },
      color: context.gloam.bgElevated,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: context.gloam.border),
      ),
      offset: const Offset(0, 36),
      itemBuilder: (_) {
        final items = <PopupMenuEntry<String>>[];

        // Home server first
        items.add(_buildItem(
          widget.homeServer,
          isSelected: widget.currentServer == widget.homeServer,
          suffix: '(home)',
        ));

        // Preset servers (skip if same as homeserver)
        for (final server in _presetServers) {
          if (server == widget.homeServer) continue;
          items.add(_buildItem(
            server,
            isSelected: widget.currentServer == server,
          ));
        }

        items.add(const PopupMenuDivider(height: 1));

        // Custom entry
        items.add(PopupMenuItem<String>(
          value: '_custom',
          height: 36,
          child: Row(
            children: [
              Icon(Icons.add, size: 14, color: context.gloam.textTertiary),
              const SizedBox(width: 8),
              Text(
                'Enter server address...',
                style: GoogleFonts.inter(
                  fontSize: 13,
                  color: context.gloam.textSecondary,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
          ),
        ));

        return items;
      },
      child: Container(
        height: 36,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: context.gloam.bgSurface,
          borderRadius: BorderRadius.circular(GloamSpacing.radiusMd),
          border: Border.all(color: context.gloam.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              widget.currentServer,
              style: GoogleFonts.jetBrainsMono(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: context.gloam.textPrimary,
              ),
            ),
            if (widget.currentServer == widget.homeServer) ...[
              const SizedBox(width: 6),
              Text(
                '(home)',
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 10,
                  color: context.gloam.textTertiary,
                ),
              ),
            ],
            const SizedBox(width: 6),
            Icon(Icons.keyboard_arrow_down,
                size: 14, color: context.gloam.textTertiary),
          ],
        ),
      ),
    );
  }

  PopupMenuItem<String> _buildItem(
    String server, {
    bool isSelected = false,
    String? suffix,
  }) {
    return PopupMenuItem<String>(
      value: server,
      height: 36,
      child: Row(
        children: [
          if (isSelected)
            Icon(Icons.check, size: 14, color: context.gloam.accent)
          else
            const SizedBox(width: 14),
          const SizedBox(width: 8),
          Text(
            server,
            style: GoogleFonts.jetBrainsMono(
              fontSize: 12,
              color:
                  isSelected ? context.gloam.accent : context.gloam.textPrimary,
            ),
          ),
          if (suffix != null) ...[
            const SizedBox(width: 6),
            Text(
              suffix,
              style: GoogleFonts.jetBrainsMono(
                fontSize: 10,
                color: context.gloam.textTertiary,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
