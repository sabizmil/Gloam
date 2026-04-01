import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:matrix/matrix.dart';

import '../../../../app/theme/gloam_color_extension.dart';
import '../../../../app/theme/gloam_theme_ext.dart';
import '../../../../app/theme/spacing.dart';
import '../../../../services/matrix_service.dart';

enum _MediaFilter { all, images, files, links }

/// Grid view of all media shared in a room.
class MediaGallery extends ConsumerStatefulWidget {
  const MediaGallery({super.key, required this.roomId, required this.onClose});
  final String roomId;
  final VoidCallback onClose;

  @override
  ConsumerState<MediaGallery> createState() => _MediaGalleryState();
}

class _MediaGalleryState extends ConsumerState<MediaGallery> {
  _MediaFilter _filter = _MediaFilter.all;
  List<Event> _mediaEvents = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadMedia();
  }

  Future<void> _loadMedia() async {
    final client = ref.read(matrixServiceProvider).client;
    if (client == null) return;
    final room = client.getRoomById(widget.roomId);
    if (room == null) return;

    final timeline = await room.getTimeline();
    final events = timeline.events
        .where((e) =>
            e.type == EventTypes.Message &&
            (e.messageType == MessageTypes.Image ||
                e.messageType == MessageTypes.File ||
                e.messageType == MessageTypes.Video ||
                e.messageType == MessageTypes.Audio))
        .toList();

    timeline.cancelSubscriptions();

    if (mounted) {
      setState(() {
        _mediaEvents = events;
        _loading = false;
      });
    }
  }

  List<Event> get _filteredEvents {
    switch (_filter) {
      case _MediaFilter.all:
        return _mediaEvents;
      case _MediaFilter.images:
        return _mediaEvents
            .where((e) => e.messageType == MessageTypes.Image)
            .toList();
      case _MediaFilter.files:
        return _mediaEvents
            .where((e) =>
                e.messageType == MessageTypes.File ||
                e.messageType == MessageTypes.Audio)
            .toList();
      case _MediaFilter.links:
        return []; // Links aren't media events — would need separate extraction
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.gloam;
    return Container(
      width: GloamSpacing.rightPanelWidth,
      decoration: BoxDecoration(
        color: colors.bgSurface,
        border: Border(left: BorderSide(color: colors.border)),
      ),
      child: Column(
        children: [
          // Header
          Container(
            height: GloamSpacing.headerHeight,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            decoration: BoxDecoration(
              border:
                  Border(bottom: BorderSide(color: colors.border)),
            ),
            child: Row(
              children: [
                Text(
                  'media',
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: colors.textPrimary,
                    letterSpacing: 0.5,
                  ),
                ),
                const Spacer(),
                IconButton(
                  onPressed: widget.onClose,
                  icon: Icon(Icons.close,
                      size: 16, color: colors.textTertiary),
                  hoverColor: colors.border.withValues(alpha: 0.5),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                ),
              ],
            ),
          ),

          // Filter tabs
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: _MediaFilter.values.map((f) {
                final active = f == _filter;
                return Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: GestureDetector(
                    onTap: () => setState(() => _filter = f),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: active ? colors.accentDim : null,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: active
                              ? colors.accent
                              : colors.border,
                        ),
                      ),
                      child: Text(
                        f.name,
                        style: GoogleFonts.jetBrainsMono(
                          fontSize: 10,
                          color: active
                              ? colors.accent
                              : colors.textTertiary,
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),

          // Grid
          Expanded(
            child: _loading
                ? Center(
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: colors.accent,
                    ),
                  )
                : _filteredEvents.isEmpty
                    ? Center(
                        child: Text(
                          '// no media',
                          style: GoogleFonts.jetBrainsMono(
                            fontSize: 11,
                            color: colors.textTertiary,
                            letterSpacing: 1,
                          ),
                        ),
                      )
                    : GridView.builder(
                        padding: const EdgeInsets.all(12),
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 3,
                          mainAxisSpacing: 4,
                          crossAxisSpacing: 4,
                        ),
                        itemCount: _filteredEvents.length,
                        itemBuilder: (context, index) {
                          final event = _filteredEvents[index];
                          return _MediaTile(event: event);
                        },
                      ),
          ),

          // Count
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: colors.border)),
            ),
            child: Text(
              '${_filteredEvents.length} item${_filteredEvents.length == 1 ? '' : 's'}',
              style: GoogleFonts.jetBrainsMono(
                fontSize: 10,
                color: colors.textTertiary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MediaTile extends ConsumerWidget {
  const _MediaTile({required this.event});
  final Event event;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.gloam;
    final isImage = event.messageType == MessageTypes.Image;

    return Container(
      decoration: BoxDecoration(
        color: colors.bgElevated,
        borderRadius: BorderRadius.circular(GloamSpacing.radiusSm),
        border: Border.all(color: colors.borderSubtle),
      ),
      clipBehavior: Clip.antiAlias,
      child: isImage
          ? FutureBuilder<Uri>(
              future: event.attachmentMxcUrl?.getDownloadUri(
                  ref.read(matrixServiceProvider).client!),
              builder: (context, snap) {
                if (snap.hasData) {
                  return Image.network(
                    snap.data.toString(),
                    fit: BoxFit.cover,
                    width: double.infinity,
                    height: double.infinity,
                    errorBuilder: (_, __, ___) => _filePlaceholder(colors),
                  );
                }
                return _filePlaceholder(colors);
              },
            )
          : _filePlaceholder(colors),
    );
  }

  Widget _filePlaceholder(GloamColorExtension colors) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.insert_drive_file_outlined,
              size: 20, color: colors.textTertiary),
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              event.body,
              style: GoogleFonts.inter(
                fontSize: 9,
                color: colors.textTertiary,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }
}
