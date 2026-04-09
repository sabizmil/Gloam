import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../app/theme/gloam_color_extension.dart';
import '../../../app/theme/gloam_theme_ext.dart';
import '../../../app/theme/spacing.dart';
import '../../../services/matrix_service.dart';
import '../../chat/presentation/providers/timeline_provider.dart';
import '../../spaces/presentation/create_space_wizard.dart';
import '../../spaces/providers/space_operation_provider.dart';
import '../providers/explore_provider.dart';
import 'widgets/public_room_tile.dart';
import 'widgets/server_selector.dart';

/// Opens the Explore modal for browsing and joining public rooms.
void showExploreModal(BuildContext context) {
  showDialog(
    context: context,
    barrierColor: Colors.black54,
    builder: (_) => const _ExploreModal(),
  );
}

class _ExploreModal extends ConsumerStatefulWidget {
  const _ExploreModal();

  @override
  ConsumerState<_ExploreModal> createState() => _ExploreModalState();
}

class _ExploreModalState extends ConsumerState<_ExploreModal>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _searchController = TextEditingController();
  final _addressController = TextEditingController();
  final _scrollController = ScrollController();
  String? _joinByAddressError;
  String? _joinByAddressSuccess;
  bool _showCreateWizard = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        final notifier = ref.read(exploreProvider.notifier);
        notifier.setSpacesOnly(_tabController.index == 1);
      }
    });
    _scrollController.addListener(_onScroll);

    // Trigger initial load
    Future.microtask(() {
      ref.read(exploreProvider.notifier).initialLoad();
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    _addressController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.hasClients &&
        _scrollController.position.pixels >=
            _scrollController.position.maxScrollExtent - 200) {
      ref.read(exploreProvider.notifier).loadMore();
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(exploreProvider);
    final homeServer =
        ref.read(matrixServiceProvider).client?.homeserver?.host ?? '';

    return Dialog(
      backgroundColor: context.gloam.bg,
      insetPadding: const EdgeInsets.all(40),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(GloamSpacing.radiusLg),
        side: BorderSide(color: context.gloam.border),
      ),
      child: SizedBox(
        width: 900,
        height: 700,
        child: Column(
          children: [
            // Header
            Container(
              height: 56,
              padding: const EdgeInsets.symmetric(horizontal: 24),
              decoration: BoxDecoration(
                border: Border(
                    bottom: BorderSide(color: context.gloam.border)),
              ),
              child: Row(
                children: [
                  Icon(Icons.explore_outlined,
                      size: 20, color: context.gloam.accent),
                  const SizedBox(width: 10),
                  Text(
                    'Explore',
                    style: GoogleFonts.inter(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: context.gloam.textPrimary,
                    ),
                  ),
                  const Spacer(),
                  GestureDetector(
                    onTap: () => Navigator.of(context).pop(),
                    child: Icon(Icons.close,
                        size: 20, color: context.gloam.textTertiary),
                  ),
                ],
              ),
            ),

            // Tab bar
            Container(
              decoration: BoxDecoration(
                border: Border(
                    bottom: BorderSide(color: context.gloam.border)),
              ),
              child: TabBar(
                controller: _tabController,
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                padding: const EdgeInsets.only(left: 24),
                labelColor: context.gloam.accent,
                unselectedLabelColor: context.gloam.textSecondary,
                labelStyle: GoogleFonts.inter(
                    fontSize: 13, fontWeight: FontWeight.w500),
                unselectedLabelStyle: GoogleFonts.inter(fontSize: 13),
                indicatorColor: context.gloam.accent,
                indicatorSize: TabBarIndicatorSize.label,
                dividerHeight: 0,
                tabs: const [
                  Tab(text: 'Browse'),
                  Tab(text: 'Spaces'),
                  Tab(text: 'Join by Address'),
                ],
              ),
            ),

            // Tab content
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _BrowseTab(
                    state: state,
                    homeServer: homeServer,
                    searchController: _searchController,
                    scrollController: _scrollController,
                    onServerChanged: (s) =>
                        ref.read(exploreProvider.notifier).setServer(s),
                    onSearchChanged: (q) =>
                        ref.read(exploreProvider.notifier).setSearchQuery(q),
                    onJoin: (roomId) =>
                        ref.read(exploreProvider.notifier).joinRoom(roomId),
                    onOpen: _openRoom,
                  ),
                  _showCreateWizard
                      ? CreateSpaceWizard(
                          onBack: () =>
                              setState(() => _showCreateWizard = false),
                        )
                      : _SpacesTab(
                          state: state,
                          homeServer: homeServer,
                          searchController: _searchController,
                          scrollController: _scrollController,
                          onServerChanged: (s) =>
                              ref.read(exploreProvider.notifier).setServer(s),
                          onSearchChanged: (q) => ref
                              .read(exploreProvider.notifier)
                              .setSearchQuery(q),
                          onJoin: (roomId) =>
                              ref.read(exploreProvider.notifier).joinRoom(roomId),
                          onOpen: _openRoom,
                          onCreateSpace: () =>
                              setState(() => _showCreateWizard = true),
                        ),
                  _JoinByAddressTab(
                    controller: _addressController,
                    error: _joinByAddressError,
                    success: _joinByAddressSuccess,
                    onJoin: _joinByAddress,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _openRoom(String roomId) {
    ref.read(selectedRoomProvider.notifier).state = roomId;
    Navigator.of(context).pop();
  }

  Future<void> _joinByAddress() async {
    final address = _addressController.text.trim();
    if (address.isEmpty) return;

    setState(() {
      _joinByAddressError = null;
      _joinByAddressSuccess = null;
    });

    try {
      final roomId =
          await ref.read(exploreProvider.notifier).joinByAddress(address);
      if (mounted && roomId != null) {
        setState(() => _joinByAddressSuccess = 'Joined successfully');
        // Navigate to the room after a brief delay
        Future.delayed(const Duration(milliseconds: 500), () {
          if (mounted) _openRoom(roomId);
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _joinByAddressError = '$e');
      }
    }
  }
}

// =============================================================================
// Browse tab (shared for Browse and Spaces — controlled by spacesOnly flag)
// =============================================================================

class _BrowseTab extends StatelessWidget {
  const _BrowseTab({
    required this.state,
    required this.homeServer,
    required this.searchController,
    required this.scrollController,
    required this.onServerChanged,
    required this.onSearchChanged,
    required this.onJoin,
    required this.onOpen,
  });

  final ExploreState state;
  final String homeServer;
  final TextEditingController searchController;
  final ScrollController scrollController;
  final ValueChanged<String> onServerChanged;
  final ValueChanged<String> onSearchChanged;
  final ValueChanged<String> onJoin;
  final ValueChanged<String> onOpen;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Server selector + search bar
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          child: Row(
            children: [
              ServerSelector(
                currentServer: state.server,
                homeServer: homeServer,
                onSelected: onServerChanged,
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Container(
                  height: 36,
                  decoration: BoxDecoration(
                    color: context.gloam.bgSurface,
                    borderRadius:
                        BorderRadius.circular(GloamSpacing.radiusMd),
                    border: Border.all(color: context.gloam.border),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Row(
                    children: [
                      Icon(Icons.search,
                          size: 14, color: context.gloam.textTertiary),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: searchController,
                          onChanged: onSearchChanged,
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            color: context.gloam.textPrimary,
                          ),
                          decoration: InputDecoration(
                            hintText: state.spacesOnly
                                ? 'search spaces...'
                                : 'search rooms and spaces...',
                            hintStyle: GoogleFonts.inter(
                              fontSize: 13,
                              color: context.gloam.textTertiary,
                            ),
                            border: InputBorder.none,
                            contentPadding: EdgeInsets.zero,
                            isDense: true,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),

        // Results
        Expanded(
          child: _buildContent(context),
        ),
      ],
    );
  }

  Widget _buildContent(BuildContext context) {
    if (state.error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
            state.error!,
            style: GoogleFonts.jetBrainsMono(
              fontSize: 12,
              color: context.gloam.danger,
            ),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    if (state.isLoading && state.rooms.isEmpty) {
      return Center(
        child: CircularProgressIndicator(
          color: context.gloam.accent,
          strokeWidth: 2,
        ),
      );
    }

    if (state.rooms.isEmpty) {
      return Center(
        child: Text(
          state.searchQuery.isNotEmpty
              ? '// no matching rooms'
              : '// no public rooms found',
          style: GoogleFonts.jetBrainsMono(
            fontSize: 11,
            color: context.gloam.textTertiary,
            letterSpacing: 1,
          ),
        ),
      );
    }

    // +1 for footer, +1 for error banner if present
    final hasError = state.error != null;
    final extraItems = 1 + (hasError ? 1 : 0);

    return ListView.builder(
      controller: scrollController,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      itemCount: state.rooms.length + extraItems,
      itemBuilder: (context, index) {
        // Error banner at top
        if (hasError && index == 0) {
          return Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFF3A1A1A),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: context.gloam.danger.withAlpha(80)),
            ),
            child: Row(
              children: [
                Icon(Icons.error_outline,
                    size: 16, color: context.gloam.danger),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    state.error!,
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      color: context.gloam.danger,
                    ),
                  ),
                ),
              ],
            ),
          );
        }

        final roomIndex = hasError ? index - 1 : index;
        if (roomIndex >= state.rooms.length) {
          return _buildFooter(context);
        }

        final room = state.rooms[roomIndex];
        return PublicRoomTile(
          room: room,
          isJoined: state.joinedRoomIds.contains(room.roomId),
          isJoining: state.joiningRoomIds.contains(room.roomId),
          onJoin: () => onJoin(room.roomId),
          onOpen: () => onOpen(room.roomId),
        );
      },
    );
  }

  Widget _buildFooter(BuildContext context) {
    if (state.isLoading) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              color: context.gloam.accent,
              strokeWidth: 2,
            ),
          ),
        ),
      );
    }

    final total = state.totalEstimate;
    final shown = state.rooms.length;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Center(
        child: Text(
          total != null
              ? 'showing $shown of ${_formatCount(total)} rooms'
              : '$shown rooms loaded',
          style: GoogleFonts.jetBrainsMono(
            fontSize: 11,
            color: context.gloam.textTertiary,
            letterSpacing: 0.5,
          ),
        ),
      ),
    );
  }

  String _formatCount(int count) {
    if (count >= 1000) {
      return '${(count / 1000).toStringAsFixed(count >= 10000 ? 0 : 1)}k';
    }
    return '$count';
  }
}

// =============================================================================
// Spaces tab — wraps BrowseTab with Create Space CTA and progress banner
// =============================================================================

class _SpacesTab extends ConsumerWidget {
  const _SpacesTab({
    required this.state,
    required this.homeServer,
    required this.searchController,
    required this.scrollController,
    required this.onServerChanged,
    required this.onSearchChanged,
    required this.onJoin,
    required this.onOpen,
    required this.onCreateSpace,
  });

  final ExploreState state;
  final String homeServer;
  final TextEditingController searchController;
  final ScrollController scrollController;
  final ValueChanged<String> onServerChanged;
  final ValueChanged<String> onSearchChanged;
  final ValueChanged<String> onJoin;
  final ValueChanged<String> onOpen;
  final VoidCallback onCreateSpace;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.gloam;
    final opState = ref.watch(spaceOperationProvider);
    final showProgressBanner = opState.type == OperationType.create &&
        !opState.isComplete &&
        opState.spaceId != null;

    // If no results and not loading, show empty state with prominent CTA
    if (!state.isLoading &&
        state.rooms.isEmpty &&
        state.searchQuery.isEmpty &&
        state.error == null) {
      return Column(
        children: [
          if (showProgressBanner) _buildProgressBanner(colors, opState),
          Expanded(
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      color: colors.bgElevated,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Center(
                      child: Icon(Icons.workspaces_outlined,
                          size: 28, color: colors.accent),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'No spaces yet',
                    style: GoogleFonts.inter(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: colors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Create a space to organize your rooms and people',
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      color: colors.textTertiary,
                    ),
                  ),
                  const SizedBox(height: 24),
                  GestureDetector(
                    onTap: onCreateSpace,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 10),
                      decoration: BoxDecoration(
                        color: colors.accentDim,
                        borderRadius:
                            BorderRadius.circular(GloamSpacing.radiusMd),
                        border: Border.all(color: colors.accent),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.add, size: 16, color: colors.accent),
                          const SizedBox(width: 8),
                          Text(
                            'Create Space',
                            style: GoogleFonts.inter(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              color: colors.accent,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      );
    }

    // Normal browse with CTA at top
    return Column(
      children: [
        if (showProgressBanner) _buildProgressBanner(colors, opState),
        // Create Space CTA row
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
          child: GestureDetector(
            onTap: onCreateSpace,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: colors.bgElevated,
                borderRadius:
                    BorderRadius.circular(GloamSpacing.radiusMd),
                border: Border.all(color: colors.border),
              ),
              child: Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: colors.accentDim,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Center(
                      child: Icon(Icons.add,
                          size: 16, color: colors.accent),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Create a space',
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: colors.textPrimary,
                          ),
                        ),
                        Text(
                          'Organize rooms and people',
                          style: GoogleFonts.inter(
                            fontSize: 11,
                            color: colors.textTertiary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(Icons.chevron_right,
                      size: 18, color: colors.textTertiary),
                ],
              ),
            ),
          ),
        ),
        // Server selector + search + results
        Expanded(
          child: _BrowseTab(
            state: state,
            homeServer: homeServer,
            searchController: searchController,
            scrollController: scrollController,
            onServerChanged: onServerChanged,
            onSearchChanged: onSearchChanged,
            onJoin: onJoin,
            onOpen: onOpen,
          ),
        ),
      ],
    );
  }

  Widget _buildProgressBanner(
      GloamColorExtension colors, SpaceOperationState opState) {
    final currentStep = opState.steps
        .where((s) => s.status == StepStatus.running)
        .firstOrNull;
    return Container(
      margin: const EdgeInsets.fromLTRB(24, 12, 24, 0),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: colors.accentDim,
        borderRadius: BorderRadius.circular(GloamSpacing.radiusMd),
        border: Border.all(color: colors.accent.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: colors.accent,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              currentStep != null
                  ? 'Creating ${opState.spaceName}: ${currentStep.label}...'
                  : 'Creating ${opState.spaceName}...',
              style: GoogleFonts.inter(
                fontSize: 12,
                color: colors.accent,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// Join by Address tab
// =============================================================================

class _JoinByAddressTab extends StatelessWidget {
  const _JoinByAddressTab({
    required this.controller,
    required this.onJoin,
    this.error,
    this.success,
  });

  final TextEditingController controller;
  final VoidCallback onJoin;
  final String? error;
  final String? success;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Icon
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: context.gloam.bgElevated,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Center(
                child: Icon(Icons.alternate_email,
                    size: 28, color: context.gloam.accent),
              ),
            ),
            const SizedBox(height: 24),

            Text(
              'Join a room by address',
              style: GoogleFonts.inter(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: context.gloam.textPrimary,
              ),
            ),
            const SizedBox(height: 8),

            Text(
              'Enter a room alias, room ID, or paste a matrix.to link',
              style: GoogleFonts.inter(
                fontSize: 13,
                color: context.gloam.textTertiary,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),

            // Input
            SizedBox(
              width: 480,
              height: 44,
              child: TextField(
                controller: controller,
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 14,
                  color: context.gloam.textPrimary,
                ),
                decoration: InputDecoration(
                  hintText: '#room:server.org',
                  hintStyle: GoogleFonts.jetBrainsMono(
                    fontSize: 14,
                    color: context.gloam.textTertiary,
                  ),
                  prefixIcon: Padding(
                    padding: const EdgeInsets.only(left: 16, right: 8),
                    child: Text(
                      '#',
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: 18,
                        color: context.gloam.accent,
                      ),
                    ),
                  ),
                  prefixIconConstraints:
                      const BoxConstraints(minWidth: 0, minHeight: 0),
                  filled: true,
                  fillColor: context.gloam.bgSurface,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  border: OutlineInputBorder(
                    borderRadius:
                        BorderRadius.circular(GloamSpacing.radiusMd),
                    borderSide: BorderSide(color: context.gloam.border),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius:
                        BorderRadius.circular(GloamSpacing.radiusMd),
                    borderSide: BorderSide(color: context.gloam.border),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius:
                        BorderRadius.circular(GloamSpacing.radiusMd),
                    borderSide: BorderSide(color: context.gloam.accent),
                  ),
                ),
                onSubmitted: (_) => onJoin(),
              ),
            ),
            const SizedBox(height: 16),

            // Join button
            GestureDetector(
              onTap: onJoin,
              child: Container(
                height: 40,
                padding: const EdgeInsets.symmetric(horizontal: 24),
                decoration: BoxDecoration(
                  color: context.gloam.accentDim,
                  borderRadius: BorderRadius.circular(GloamSpacing.radiusMd),
                  border: Border.all(color: context.gloam.accent),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.login, size: 16, color: context.gloam.accent),
                    const SizedBox(width: 8),
                    Text(
                      'Join Room',
                      style: GoogleFonts.inter(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: context.gloam.accent,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Error / success feedback
            if (error != null)
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: Text(
                  error!,
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 12,
                    color: context.gloam.danger,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            if (success != null)
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.check_circle_outline,
                        size: 14, color: context.gloam.accent),
                    const SizedBox(width: 6),
                    Text(
                      success!,
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        color: context.gloam.accent,
                      ),
                    ),
                  ],
                ),
              ),

            const SizedBox(height: 32),

            // Examples
            Text(
              '// examples',
              style: GoogleFonts.jetBrainsMono(
                fontSize: 10,
                color: context.gloam.textTertiary,
                letterSpacing: 1,
              ),
            ),
            const SizedBox(height: 8),
            for (final example in const [
              '#matrix:matrix.org',
              '!abc123:server.org',
              'https://matrix.to/#/#room:server',
            ])
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: GestureDetector(
                  onTap: () => controller.text = example,
                  child: Text(
                    example,
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 12,
                      color: context.gloam.textSecondary,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
