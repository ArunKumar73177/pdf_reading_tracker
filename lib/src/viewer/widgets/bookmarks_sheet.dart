import 'package:flutter/material.dart';

import '../../models/bookmark.dart';

/// Shows the bookmark list in a modal bottom sheet.
///
/// Returns the page the user wants to navigate to, or `null` if dismissed.
/// Internal to the package — not exported.
Future<int?> showBookmarksSheet({
  required BuildContext context,
  required List<Bookmark> bookmarks,
  required int currentPage,
  required Future<void> Function(int id) onDelete,
}) {
  return showModalBottomSheet<int>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => _BookmarksSheetContent(
      bookmarks: bookmarks,
      currentPage: currentPage,
      onDelete: onDelete,
    ),
  );
}

// ---------------------------------------------------------------------------
// Sheet content (stateful so it can remove items locally while deleting)
// ---------------------------------------------------------------------------

class _BookmarksSheetContent extends StatefulWidget {
  const _BookmarksSheetContent({
    required this.bookmarks,
    required this.currentPage,
    required this.onDelete,
  });

  final List<Bookmark> bookmarks;
  final int currentPage;
  final Future<void> Function(int id) onDelete;

  @override
  State<_BookmarksSheetContent> createState() => _BookmarksSheetContentState();
}

class _BookmarksSheetContentState extends State<_BookmarksSheetContent> {
  late List<Bookmark> _items;
  final Set<int> _deleting = {};

  @override
  void initState() {
    super.initState();
    _items = List.of(widget.bookmarks);
  }

  Future<void> _delete(Bookmark bm) async {
    if (bm.id == null) return;
    setState(() => _deleting.add(bm.id!));
    try {
      await widget.onDelete(bm.id!);
      setState(() => _items.removeWhere((b) => b.id == bm.id));
    } finally {
      if (mounted) setState(() => _deleting.remove(bm.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.55,
      minChildSize: 0.35,
      maxChildSize: 0.92,
      builder: (_, scrollController) => Column(
        children: [
          // ── Handle ─────────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: cs.outlineVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          // ── Header ─────────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            child: Row(
              children: [
                Text('Bookmarks', style: tt.titleMedium),
                const Spacer(),
                Chip(
                  label: Text(
                    '${_items.length}',
                    style: tt.labelSmall
                        ?.copyWith(color: cs.onSecondaryContainer),
                  ),
                  backgroundColor: cs.secondaryContainer,
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          // ── List ───────────────────────────────────────────────────────────
          Expanded(
            child: _items.isEmpty
                ? _EmptyState(cs: cs, tt: tt)
                : ListView.separated(
              controller: scrollController,
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: _items.length,
              separatorBuilder: (_, __) =>
              const Divider(height: 1, indent: 72),
              itemBuilder: (_, i) {
                final bm = _items[i];
                final isDeleting = _deleting.contains(bm.id);
                final isCurrent = bm.page == widget.currentPage;

                return ListTile(
                  onTap: isDeleting
                      ? null
                      : () => Navigator.of(context).pop(bm.page),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 4,
                  ),
                  leading: CircleAvatar(
                    backgroundColor:
                    isCurrent ? cs.primary : cs.secondaryContainer,
                    foregroundColor: isCurrent
                        ? cs.onPrimary
                        : cs.onSecondaryContainer,
                    child: Text(
                      '${bm.page + 1}',
                      style: tt.labelMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: isCurrent
                            ? cs.onPrimary
                            : cs.onSecondaryContainer,
                      ),
                    ),
                  ),
                  title: Text(
                    'Page ${bm.page + 1}',
                    style: tt.bodyLarge?.copyWith(
                      fontWeight: isCurrent
                          ? FontWeight.bold
                          : FontWeight.normal,
                    ),
                  ),
                  subtitle: bm.note != null
                      ? Text(
                    bm.note!,
                    style: tt.bodySmall
                        ?.copyWith(color: cs.onSurfaceVariant),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  )
                      : Text(
                    _formatDate(bm.createdAt),
                    style: tt.bodySmall
                        ?.copyWith(color: cs.outline),
                  ),
                  trailing: isDeleting
                      ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                        strokeWidth: 2),
                  )
                      : IconButton(
                    icon: Icon(Icons.delete_outline,
                        color: cs.error),
                    tooltip: 'Remove bookmark',
                    onPressed: () => _delete(bm),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime dt) =>
      '${dt.day.toString().padLeft(2, '0')}/'
          '${dt.month.toString().padLeft(2, '0')}/'
          '${dt.year}';
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.cs, required this.tt});
  final ColorScheme cs;
  final TextTheme tt;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.bookmark_border_rounded,
              size: 64, color: cs.outlineVariant),
          const SizedBox(height: 16),
          Text('No bookmarks yet',
              style: tt.titleMedium?.copyWith(color: cs.onSurfaceVariant)),
          const SizedBox(height: 8),
          Text(
            'Tap the bookmark button while reading\nto save your favourite pages.',
            textAlign: TextAlign.center,
            style: tt.bodySmall?.copyWith(color: cs.outline),
          ),
        ],
      ),
    );
  }
}