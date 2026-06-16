import 'package:flutter/material.dart';

import 'animated_progress_bar.dart';

/// Bottom bar shown while reading a PDF.
///
/// Displays:
/// - Current page / total pages.
/// - Animated gradient progress bar (Improvement 3).
/// - A small saving indicator when [isSaving] is true.
///
/// The bar uses [AnimatedProgressBar] which cross-fades percentage labels
/// and smoothly animates the fill width on every [progressPct] change.
class ReaderBottomBar extends StatelessWidget {
  const ReaderBottomBar({
    super.key,
    required this.currentPage,
    required this.totalPages,
    required this.progressPct,
    this.isSaving = false,
  });

  /// Zero-based index of the currently visible page.
  final int currentPage;
  final int totalPages;

  /// Completion percentage in [0.0, 100.0].
  final double progressPct;

  /// When `true` a small [CircularProgressIndicator] is shown to indicate
  /// that a SQLite write is in progress.
  final bool isSaving;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    final pageLabel = totalPages > 0
        ? 'Page ${currentPage + 1} of $totalPages'
        : 'Loading…';

    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
        decoration: BoxDecoration(
          color: cs.surface,
          border: Border(top: BorderSide(color: cs.outlineVariant, width: 0.5)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Progress bar ─────────────────────────────────────────
            AnimatedProgressBar(
              progressPct: progressPct,
              height: 7,
              showLabel: true,
            ),

            const SizedBox(height: 8),

            // ── Page label + saving indicator ─────────────────────────
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  pageLabel,
                  style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                ),
                if (isSaving)
                  SizedBox(
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(
                      strokeWidth: 1.5,
                      color: cs.primary.withAlpha(160),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}