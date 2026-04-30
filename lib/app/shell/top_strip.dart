import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:window_manager/window_manager.dart';

import '../theme/gloam_theme_ext.dart';
import '../theme/spacing.dart';
import 'command_palette/command_palette.dart';

/// Frameless-window top chrome — drag region, centered ⌘K search invoker,
/// and platform window controls (min/max/close on Win/Linux; traffic lights
/// are drawn by the OS over the left side on macOS).
class TopStrip extends StatefulWidget {
  const TopStrip({super.key});

  @override
  State<TopStrip> createState() => _TopStripState();
}

class _TopStripState extends State<TopStrip> with WindowListener {
  bool _focused = true;

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    super.dispose();
  }

  @override
  void onWindowFocus() => setState(() => _focused = true);

  @override
  void onWindowBlur() => setState(() => _focused = false);

  Future<void> _toggleMaximize() async {
    if (await windowManager.isMaximized()) {
      await windowManager.unmaximize();
    } else {
      await windowManager.maximize();
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.gloam;
    final dim = !_focused;
    // macOS traffic-light cluster lives at x≈7–59 / y≈6–22. Reserve the
    // SpaceRail-width column so the search pill never sits behind them.
    const trafficLightInset = GloamSpacing.spaceRailWidth;
    final showWindowButtons = Platform.isWindows || Platform.isLinux;

    return Container(
      height: GloamSpacing.topStripHeight,
      decoration: BoxDecoration(
        color: colors.bg,
        border: Border(bottom: BorderSide(color: colors.borderSubtle)),
      ),
      child: Stack(
        children: [
          // Full-width drag + double-click-to-zoom region.
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onPanStart: (_) => windowManager.startDragging(),
              onDoubleTap: _toggleMaximize,
            ),
          ),
          // Centered ⌘K invoker.
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 150),
                  opacity: dim ? 0.6 : 1.0,
                  child: const _SearchInvoker(),
                ),
              ),
            ),
          ),
          // Right-side controls.
          if (showWindowButtons)
            Positioned(
              top: 0,
              bottom: 0,
              right: 0,
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 150),
                opacity: dim ? 0.6 : 1.0,
                child: const _WindowButtons(),
              ),
            ),
          // Reserve traffic-light area on macOS — purely visual breathing
          // room, lights are drawn by the OS on top of the strip.
          if (Platform.isMacOS)
            const Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              width: trafficLightInset,
              child: SizedBox.shrink(),
            ),
        ],
      ),
    );
  }
}

class _SearchInvoker extends ConsumerStatefulWidget {
  const _SearchInvoker();

  @override
  ConsumerState<_SearchInvoker> createState() => _SearchInvokerState();
}

class _SearchInvokerState extends ConsumerState<_SearchInvoker> {
  bool _hover = false;

  void _open() {
    showCommandPalette(context, ref);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.gloam;
    final shortcut = Platform.isMacOS ? '⌘K' : 'Ctrl+K';
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _open,
        child: Container(
          height: 26,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: _hover ? colors.bgElevated : colors.bgSurface,
            borderRadius: BorderRadius.circular(GloamSpacing.radiusMd),
            border: Border.all(color: colors.borderSubtle),
          ),
          child: Row(
            children: [
              Icon(Icons.search, size: 14, color: colors.textTertiary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Search messages, rooms, people…',
                  style: TextStyle(
                    fontSize: 12,
                    color: colors.textTertiary,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: colors.bg,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: colors.borderSubtle),
                ),
                child: Text(
                  shortcut,
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 10,
                    fontWeight: FontWeight.w500,
                    color: colors.textTertiary,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _WindowButtons extends StatelessWidget {
  const _WindowButtons();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _WindowButton(
          icon: Icons.remove,
          onTap: () => windowManager.minimize(),
          tooltip: 'Minimize',
        ),
        _WindowButton(
          icon: Icons.crop_square,
          iconSize: 12,
          onTap: () async {
            if (await windowManager.isMaximized()) {
              await windowManager.unmaximize();
            } else {
              await windowManager.maximize();
            }
          },
          tooltip: 'Maximize',
        ),
        _WindowButton(
          icon: Icons.close,
          onTap: () => windowManager.close(),
          tooltip: 'Close',
          isClose: true,
        ),
      ],
    );
  }
}

class _WindowButton extends StatefulWidget {
  const _WindowButton({
    required this.icon,
    required this.onTap,
    required this.tooltip,
    this.iconSize = 14,
    this.isClose = false,
  });

  final IconData icon;
  final VoidCallback onTap;
  final String tooltip;
  final double iconSize;
  final bool isClose;

  @override
  State<_WindowButton> createState() => _WindowButtonState();
}

class _WindowButtonState extends State<_WindowButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.gloam;
    final hoverColor =
        widget.isClose ? const Color(0xFFE81123) : colors.bgElevated;
    final iconColor = _hover && widget.isClose
        ? Colors.white
        : colors.textSecondary;
    return Tooltip(
      message: widget.tooltip,
      waitDuration: const Duration(milliseconds: 500),
      child: MouseRegion(
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 100),
            width: 46,
            height: GloamSpacing.topStripHeight,
            color: _hover ? hoverColor : Colors.transparent,
            child: Icon(widget.icon, size: widget.iconSize, color: iconColor),
          ),
        ),
      ),
    );
  }
}
