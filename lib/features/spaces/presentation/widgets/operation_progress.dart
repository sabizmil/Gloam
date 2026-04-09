import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../app/theme/gloam_theme_ext.dart';
import '../../providers/space_operation_provider.dart';

/// Shared progress checklist view — used by both create and delete flows.
class OperationProgress extends StatelessWidget {
  const OperationProgress({
    super.key,
    required this.state,
    this.onRetry,
  });

  final SpaceOperationState state;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final colors = context.gloam;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Space name
            if (state.spaceName != null) ...[
              Text(
                state.spaceName!,
                style: GoogleFonts.inter(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: colors.textPrimary,
                ),
              ),
              const SizedBox(height: 24),
            ],

            // Steps checklist
            ...state.steps.map((step) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Row(
                    children: [
                      _StepStatusIcon(status: step.status),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              step.label,
                              style: GoogleFonts.inter(
                                fontSize: 13,
                                color: step.status == StepStatus.failed
                                    ? colors.danger
                                    : step.status == StepStatus.done
                                        ? colors.textPrimary
                                        : colors.textSecondary,
                              ),
                            ),
                            if (step.error != null)
                              Text(
                                step.error!,
                                style: GoogleFonts.jetBrainsMono(
                                  fontSize: 10,
                                  color: colors.danger,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                )),

            // Fatal error
            if (state.fatalError != null) ...[
              const SizedBox(height: 16),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: const Color(0xFF3A1A1A),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                      color: colors.danger.withValues(alpha: 0.4)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.error_outline,
                        size: 16, color: colors.danger),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        state.fatalError!,
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          color: colors.danger,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            // Retry button if any step failed
            if (state.hasFailed && onRetry != null) ...[
              const SizedBox(height: 20),
              GestureDetector(
                onTap: onRetry,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: colors.accent),
                    color: colors.accentDim,
                  ),
                  child: Text(
                    'retry failed steps',
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 12,
                      color: colors.accent,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              ),
            ],

            // Done message
            if (state.isComplete && !state.hasFailed) ...[
              const SizedBox(height: 20),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.check_circle_outline,
                      size: 16, color: colors.accent),
                  const SizedBox(width: 8),
                  Text(
                    state.type == OperationType.create
                        ? 'Space created successfully'
                        : 'Space deleted',
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      color: colors.accent,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _StepStatusIcon extends StatelessWidget {
  const _StepStatusIcon({required this.status});
  final StepStatus status;

  @override
  Widget build(BuildContext context) {
    final colors = context.gloam;
    switch (status) {
      case StepStatus.pending:
        return Container(
          width: 20,
          height: 20,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: colors.border),
          ),
        );
      case StepStatus.running:
        return SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: colors.accent,
          ),
        );
      case StepStatus.done:
        return Container(
          width: 20,
          height: 20,
          decoration: BoxDecoration(
            color: colors.accent,
            shape: BoxShape.circle,
          ),
          child: Icon(Icons.check, size: 12, color: colors.bg),
        );
      case StepStatus.failed:
        return Container(
          width: 20,
          height: 20,
          decoration: BoxDecoration(
            color: colors.danger,
            shape: BoxShape.circle,
          ),
          child: Icon(Icons.close, size: 12, color: colors.bg),
        );
    }
  }
}
