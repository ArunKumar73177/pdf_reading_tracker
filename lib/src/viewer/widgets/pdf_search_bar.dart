import 'package:flutter/material.dart';

import '../pdf_search_controller.dart';

/// An in-app search bar for PDF text search.
///
/// Renders below the [AppBar] when the user taps the search icon.  Exposes:
/// - A text field for entering the query.
/// - A result count chip ("3 / 12").
/// - Previous / next navigation buttons.
/// - A clear button.
///
/// All state is driven by [PdfSearchController] via [ListenableBuilder] so
/// this widget only repaints when search state changes, not on every page
/// swipe.
class PdfSearchBar extends StatefulWidget {
  const PdfSearchBar({
    super.key,
    required this.searchController,
  });

  final PdfSearchController searchController;

  @override
  State<PdfSearchBar> createState() => _PdfSearchBarState();
}

class _PdfSearchBarState extends State<PdfSearchBar> {
  late final TextEditingController _textCtrl;
  late final FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _textCtrl  = TextEditingController(text: widget.searchController.query);
    _focusNode = FocusNode();
    // Auto-focus when the search bar first appears.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _textCtrl.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onSubmitted(String value) {
    // search() is synchronous in Syncfusion 27.x — no await needed.
    widget.searchController.search(value);
  }

  void _onClear() {
    _textCtrl.clear();
    widget.searchController.clearSearch();
    _focusNode.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Container(
      height: 56,
      color:  cs.surfaceContainerLow,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: Row(
        children: [
          // ── Search field ─────────────────────────────────────────────
          Expanded(
            child: TextField(
              controller:  _textCtrl,
              focusNode:   _focusNode,
              textInputAction: TextInputAction.search,
              onSubmitted: _onSubmitted,
              style: tt.bodyMedium,
              decoration: InputDecoration(
                hintText:     'Search in document…',
                hintStyle:    tt.bodyMedium
                    ?.copyWith(color: cs.onSurfaceVariant),
                filled:        true,
                fillColor:     cs.surfaceContainerHigh,
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 0),
                isDense:       true,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide:   BorderSide.none,
                ),
                prefixIcon: Icon(Icons.search_rounded,
                    size: 20, color: cs.onSurfaceVariant),
                suffixIcon: ListenableBuilder(
                  listenable: widget.searchController.notifier,
                  builder: (_, __) {
                    if (widget.searchController.query.isEmpty) {
                      return const SizedBox.shrink();
                    }
                    return IconButton(
                      icon:    const Icon(Icons.close_rounded, size: 18),
                      tooltip: 'Clear search',
                      onPressed: _onClear,
                    );
                  },
                ),
              ),
            ),
          ),

          const SizedBox(width: 4),

          // ── Result count + navigation (only when a search is active) ──
          ListenableBuilder(
            listenable: widget.searchController.notifier,
            builder: (_, __) {
              final sc = widget.searchController;

              if (sc.isSearching) {
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: SizedBox(
                    width:  18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: cs.primary,
                    ),
                  ),
                );
              }

              if (!sc.hasActiveSearch) return const SizedBox.shrink();

              return _SearchResultControls(
                current:    sc.currentIndex,
                total:      sc.totalCount,
                onPrevious: sc.previousResult,
                onNext:     sc.nextResult,
                cs:         cs,
                tt:         tt,
              );
            },
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Result controls — count chip + prev/next buttons
// ---------------------------------------------------------------------------

class _SearchResultControls extends StatelessWidget {
  const _SearchResultControls({
    required this.current,
    required this.total,
    required this.onPrevious,
    required this.onNext,
    required this.cs,
    required this.tt,
  });

  final int          current;
  final int          total;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final ColorScheme  cs;
  final TextTheme    tt;

  @override
  Widget build(BuildContext context) {
    final hasResults = total > 0;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Count chip
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color:        hasResults
                ? cs.primaryContainer
                : cs.errorContainer,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            hasResults ? '$current / $total' : 'No results',
            style: tt.labelSmall?.copyWith(
              color: hasResults
                  ? cs.onPrimaryContainer
                  : cs.onErrorContainer,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),

        if (hasResults) ...[
          // Previous
          IconButton(
            icon:     const Icon(Icons.keyboard_arrow_up_rounded),
            iconSize: 22,
            tooltip:  'Previous result',
            onPressed: total > 0 ? onPrevious : null,
          ),
          // Next
          IconButton(
            icon:     const Icon(Icons.keyboard_arrow_down_rounded),
            iconSize: 22,
            tooltip:  'Next result',
            onPressed: total > 0 ? onNext : null,
          ),
        ],
      ],
    );
  }
}