import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../app/shell/space_rail.dart';
import '../../../app/theme/gloam_color_extension.dart';
import '../../../app/theme/gloam_theme_ext.dart';
import '../../../app/theme/spacing.dart';
import '../../chat/presentation/providers/timeline_provider.dart';
import '../providers/space_operation_provider.dart';
import 'widgets/operation_progress.dart';
import 'widgets/step_identity.dart';
import 'widgets/step_invite.dart';
import 'widgets/step_rooms.dart';

/// Callback to navigate back to the Spaces browse tab.
typedef OnBack = VoidCallback;

/// 3-step wizard for creating a new space.
class CreateSpaceWizard extends ConsumerStatefulWidget {
  const CreateSpaceWizard({super.key, required this.onBack});

  final OnBack onBack;

  @override
  ConsumerState<CreateSpaceWizard> createState() => _CreateSpaceWizardState();
}

class _CreateSpaceWizardState extends ConsumerState<CreateSpaceWizard> {
  int _currentStep = 0;
  bool _creationStarted = false;
  late PageController _pageController;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  // Step 1 state
  String _name = '';
  String? _topic;
  Uint8List? _avatar;
  bool _isPublic = false;
  String? _alias;
  String? _aliasError;

  // Step 2 state
  List<String> _roomNames = ['General', 'Introductions', 'Off-topic'];

  // Step 3 state
  Map<String, int> _invites = {}; // userId -> powerLevel
  Map<String, String> _inviteDisplayNames = {}; // userId -> displayName

  bool get _canAdvance {
    switch (_currentStep) {
      case 0:
        return _name.trim().isNotEmpty && _aliasError == null;
      case 1:
        return true; // zero rooms is fine
      case 2:
        return true; // zero invites is fine
      default:
        return false;
    }
  }

  void _next() {
    if (_currentStep < 2) {
      setState(() => _currentStep++);
      _pageController.animateToPage(
        _currentStep,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeInOut,
      );
    } else {
      _startCreation();
    }
  }

  void _back() {
    if (_currentStep > 0) {
      setState(() => _currentStep--);
      _pageController.animateToPage(
        _currentStep,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeInOut,
      );
    } else {
      widget.onBack();
    }
  }

  void _startCreation() {
    setState(() => _creationStarted = true);

    final params = CreateSpaceParams(
      name: _name.trim(),
      topic: _topic?.trim().isNotEmpty == true ? _topic!.trim() : null,
      avatar: _avatar,
      isPublic: _isPublic,
      alias: _isPublic && (_alias?.trim().isNotEmpty == true)
          ? _alias!.trim()
          : null,
      roomNames: _roomNames.where((n) => n.trim().isNotEmpty).toList(),
      invites: _invites,
    );

    ref.read(spaceOperationProvider.notifier).createSpace(params);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.gloam;
    final opState = ref.watch(spaceOperationProvider);

    // Listen for completion — navigate to new space
    ref.listen(spaceOperationProvider, (prev, next) {
      if (next.isComplete && next.spaceId != null && next.fatalError == null) {
        // Select the new space in the rail
        ref.read(selectedSpaceProvider.notifier).state = next.spaceId!;
        // Navigate to first room if one was created
        if (next.firstRoomId != null) {
          ref.read(selectedRoomProvider.notifier).state = next.firstRoomId;
        }
        // Close the modal
        Navigator.of(context).pop();
        // Reset for next use
        Future.microtask(
            () => ref.read(spaceOperationProvider.notifier).reset());
      }
    });

    // Show progress view once creation has started
    if (_creationStarted && opState.type == OperationType.create) {
      return _buildProgressView(colors, opState);
    }

    return Column(
      children: [
        // Header
        Container(
          height: 56,
          padding: const EdgeInsets.symmetric(horizontal: 24),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: colors.border)),
          ),
          child: Row(
            children: [
              GestureDetector(
                onTap: _back,
                child: Icon(Icons.arrow_back,
                    size: 18, color: colors.textSecondary),
              ),
              const SizedBox(width: 12),
              Text(
                'Create a Space',
                style: GoogleFonts.inter(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: colors.textPrimary,
                ),
              ),
              const Spacer(),
              // Step indicator
              Text(
                '${_currentStep + 1} / 3',
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 12,
                  color: colors.textTertiary,
                  letterSpacing: 1,
                ),
              ),
              const SizedBox(width: 16),
              GestureDetector(
                onTap: () => Navigator.of(context).pop(),
                child:
                    Icon(Icons.close, size: 20, color: colors.textTertiary),
              ),
            ],
          ),
        ),

        // Step indicator bar
        _StepIndicator(
          currentStep: _currentStep,
          labels: const ['Details', 'Rooms', 'Invite'],
        ),

        // Step content — PageView for swipe support, works on both mobile and desktop
        Expanded(
          child: PageView(
            controller: _pageController,
            physics: const NeverScrollableScrollPhysics(), // controlled by buttons
            children: [
              StepIdentity(
                name: _name,
                topic: _topic,
                avatar: _avatar,
                isPublic: _isPublic,
                alias: _alias,
                aliasError: _aliasError,
                onNameChanged: (v) => setState(() => _name = v),
                onTopicChanged: (v) => setState(() => _topic = v),
                onAvatarChanged: (v) => setState(() => _avatar = v),
                onVisibilityChanged: (v) => setState(() => _isPublic = v),
                onAliasChanged: (v) => setState(() => _alias = v),
                onAliasError: (v) => setState(() => _aliasError = v),
              ),
              StepRooms(
                roomNames: _roomNames,
                onRoomNamesChanged: (v) => setState(() => _roomNames = v),
              ),
              StepInvite(
                invites: _invites,
                displayNames: _inviteDisplayNames,
                onInvitesChanged: (invites, names) => setState(() {
                  _invites = invites;
                  _inviteDisplayNames = names;
                }),
              ),
            ],
          ),
        ),

        // Footer
        Container(
          height: 64,
          padding: const EdgeInsets.symmetric(horizontal: 24),
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: colors.border)),
          ),
          child: Row(
            children: [
              // Back / Cancel
              GestureDetector(
                onTap: _back,
                child: Container(
                  height: 36,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  decoration: BoxDecoration(
                    borderRadius:
                        BorderRadius.circular(GloamSpacing.radiusMd),
                    border: Border.all(color: colors.border),
                  ),
                  child: Center(
                    child: Text(
                      _currentStep == 0 ? 'cancel' : 'back',
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        color: colors.textSecondary,
                      ),
                    ),
                  ),
                ),
              ),
              const Spacer(),
              // Skip (on step 2 and 3)
              if (_currentStep > 0) ...[
                GestureDetector(
                  onTap: _next,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Text(
                      'skip',
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        color: colors.textTertiary,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
              ],
              // Next / Create
              GestureDetector(
                onTap: _canAdvance ? _next : null,
                child: Container(
                  height: 36,
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  decoration: BoxDecoration(
                    color:
                        _canAdvance ? colors.accentDim : colors.bgElevated,
                    borderRadius:
                        BorderRadius.circular(GloamSpacing.radiusMd),
                    border: Border.all(
                      color: _canAdvance ? colors.accent : colors.border,
                    ),
                  ),
                  child: Center(
                    child: Text(
                      _currentStep < 2 ? 'next' : 'create space',
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: _canAdvance
                            ? colors.accent
                            : colors.textTertiary,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildProgressView(
      GloamColorExtension colors, SpaceOperationState opState) {
    return Column(
      children: [
        // Header
        Container(
          height: 56,
          padding: const EdgeInsets.symmetric(horizontal: 24),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: colors.border)),
          ),
          child: Row(
            children: [
              Icon(Icons.workspaces_outlined,
                  size: 20, color: colors.accent),
              const SizedBox(width: 12),
              Text(
                'Creating Space',
                style: GoogleFonts.inter(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: colors.textPrimary,
                ),
              ),
              const Spacer(),
              GestureDetector(
                onTap: () => Navigator.of(context).pop(),
                child:
                    Icon(Icons.close, size: 20, color: colors.textTertiary),
              ),
            ],
          ),
        ),
        Expanded(
          child: OperationProgress(
            state: opState,
            onRetry: () {
              // Re-run with same params for failed steps
              if (_createParams != null) {
                ref
                    .read(spaceOperationProvider.notifier)
                    .createSpace(_createParams!);
              }
            },
          ),
        ),
      ],
    );
  }

  CreateSpaceParams? get _createParams {
    return CreateSpaceParams(
      name: _name.trim(),
      topic: _topic?.trim().isNotEmpty == true ? _topic!.trim() : null,
      avatar: _avatar,
      isPublic: _isPublic,
      alias: _isPublic && (_alias?.trim().isNotEmpty == true)
          ? _alias!.trim()
          : null,
      roomNames: _roomNames.where((n) => n.trim().isNotEmpty).toList(),
      invites: _invites,
    );
  }
}

// ── Step Indicator ──

class _StepIndicator extends StatelessWidget {
  const _StepIndicator({
    required this.currentStep,
    required this.labels,
  });

  final int currentStep;
  final List<String> labels;

  @override
  Widget build(BuildContext context) {
    final colors = context.gloam;
    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      decoration: BoxDecoration(
        color: colors.bgSurface,
        border: Border(bottom: BorderSide(color: colors.border)),
      ),
      child: Row(
        children: [
          for (var i = 0; i < labels.length; i++) ...[
            if (i > 0)
              Expanded(
                child: Container(
                  height: 1,
                  margin: const EdgeInsets.symmetric(horizontal: 8),
                  color: i <= currentStep
                      ? colors.accent
                      : colors.border,
                ),
              ),
            _StepDot(
              index: i,
              label: labels[i],
              isActive: i == currentStep,
              isComplete: i < currentStep,
            ),
          ],
        ],
      ),
    );
  }
}

class _StepDot extends StatelessWidget {
  const _StepDot({
    required this.index,
    required this.label,
    required this.isActive,
    required this.isComplete,
  });

  final int index;
  final String label;
  final bool isActive;
  final bool isComplete;

  @override
  Widget build(BuildContext context) {
    final colors = context.gloam;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 20,
          height: 20,
          decoration: BoxDecoration(
            color: isActive || isComplete
                ? colors.accent
                : Colors.transparent,
            shape: BoxShape.circle,
            border: Border.all(
              color: isActive || isComplete
                  ? colors.accent
                  : colors.border,
            ),
          ),
          child: Center(
            child: isComplete
                ? Icon(Icons.check, size: 12, color: colors.bg)
                : Text(
                    '${index + 1}',
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: isActive
                          ? colors.bg
                          : colors.textTertiary,
                    ),
                  ),
          ),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: GoogleFonts.inter(
            fontSize: 12,
            fontWeight: isActive ? FontWeight.w500 : FontWeight.w400,
            color: isActive
                ? colors.textPrimary
                : colors.textTertiary,
          ),
        ),
      ],
    );
  }
}
