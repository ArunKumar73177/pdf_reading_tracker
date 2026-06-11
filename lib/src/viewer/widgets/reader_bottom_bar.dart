import 'package:flutter/material.dart';

/// Slim progress bar + page counter shown at the bottom of the reader.
///
/// Internal to the package — not exported.
class ReaderBottomBar extends StatelessWidget {
  const ReaderBottomBar({
    super.key,
    required this.currentPage,
    required this.totalPages,
    required this.progressPct,
    required this.isSaving,
  });

  /// Zero-based current page (displayed as 1-based).
  final int currentPage;
  final int totalPages;

  /// Completion percentage in [0.0, 100.0].
  final double progressPct;

  /// Shows a micro spinner while a DB write is in flight.
  final bool isSaving;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Container(
      decoration: BoxDecoration(
        color: cs.surface,
        boxShadow: [
          BoxShadow(
            color: cs.shadow.withValues(alpha: 0.08),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: totalPages > 0 ? progressPct / 100 : 0,
              backgroundColor: cs.surfaceContainerHighest,
              valueColor: AlwaysStoppedAnimation<Color>(cs.primary),
              minHeight: 5,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                totalPages > 0
                    ? 'Page ${currentPage + 1} of $totalPages'
                    : 'Loading…',
                style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
              ),
              Row(
                children: [
                  if (isSaving) ...[
                    SizedBox(
                      width: 10,
                      height: 10,
                      child: CircularProgressIndicator(
                        strokeWidth: 1.5,
                        color: cs.primary,
                      ),
                    ),
                    const SizedBox(width: 6),
                  ],
                  Text(
                    '${progressPct.toStringAsFixed(1)}%',
                    style: tt.bodySmall?.copyWith(
                      color: cs.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}