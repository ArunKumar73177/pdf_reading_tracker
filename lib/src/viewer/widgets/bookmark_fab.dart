import 'package:flutter/material.dart';

/// FAB that toggles between "add bookmark" and "already bookmarked" states.
///
/// Internal to the package — not exported.
class BookmarkFab extends StatelessWidget {
  const BookmarkFab({
    super.key,
    required this.isBookmarked,
    required this.onPressed,
  });

  final bool isBookmarked;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return FloatingActionButton.small(
      heroTag: 'pdf_tracker_bookmark_fab',
      tooltip: isBookmarked ? 'Page already bookmarked' : 'Bookmark this page',
      backgroundColor:
      isBookmarked ? cs.primaryContainer : cs.secondaryContainer,
      foregroundColor:
      isBookmarked ? cs.onPrimaryContainer : cs.onSecondaryContainer,
      onPressed: isBookmarked ? null : onPressed,
      child: Icon(
        isBookmarked ? Icons.bookmark_rounded : Icons.bookmark_add_outlined,
      ),
    );
  }
}