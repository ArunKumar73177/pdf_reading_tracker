import 'package:flutter/material.dart';

/// A compact action bar that appears above the keyboard / at bottom of screen
/// when the user selects text in the PDF viewer.
///
/// Offers one primary action — "Highlight" — plus a dismiss button.
/// Internal to the package; not exported in the public barrel.
class HighlightActionBar extends StatelessWidget {
  const HighlightActionBar({
    super.key,
    required this.selectedText,
    required this.onHighlight,
    required this.onDismiss,
  });

  /// The currently selected text, shown as a truncated preview.
  final String selectedText;

  /// Called when the user taps "Highlight".
  final VoidCallback onHighlight;

  /// Called when the user taps the dismiss (×) button.
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    // Truncate preview to keep the bar compact.
    final preview = selectedText.length > 48
        ? '${selectedText.substring(0, 48)}...'
        : selectedText;

    return Material(
      elevation:    6,
      borderRadius: BorderRadius.circular(28),
      color:        cs.surfaceContainerHigh,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── Text preview ───────────────────────────────────────────
            Flexible(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Text(
                  '"$preview"',
                  maxLines:  1,
                  overflow:  TextOverflow.ellipsis,
                  style: tt.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ),
            ),

            const SizedBox(width: 4),

            // ── Highlight button ───────────────────────────────────────
            FilledButton.icon(
              onPressed: onHighlight,
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFFFEB3B), // yellow
                foregroundColor: Colors.black87,
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 8),
                visualDensity: VisualDensity.compact,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20)),
              ),
              icon:  const Icon(Icons.highlight_rounded, size: 18),
              label: const Text('Highlight'),
            ),

            const SizedBox(width: 4),

            // ── Dismiss ────────────────────────────────────────────────
            IconButton(
              icon:      const Icon(Icons.close_rounded),
              iconSize:  20,
              tooltip:   'Dismiss',
              onPressed: onDismiss,
              color:     cs.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }
}