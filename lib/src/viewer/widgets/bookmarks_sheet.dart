import 'package:flutter/material.dart';

import '../../models/bookmark.dart';

/// Shows the bookmark list in a modal bottom sheet.
///
/// Returns the page the user wants to navigate to, or `null` if dismissed.
Future<int?> showBookmarksSheet({
  required BuildContext context,
  required List<Bookmark> bookmarks,
  required int currentPage,
  required Future<void> Function(int id) onDelete,
  required Future<void> Function(int id, String? note) onEditNote,
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
      onEditNote: onEditNote,
    ),
  );
}

// ---------------------------------------------------------------------------
// Sheet content
// ---------------------------------------------------------------------------

class _BookmarksSheetContent extends StatefulWidget {
  const _BookmarksSheetContent({
    required this.bookmarks,
    required this.currentPage,
    required this.onDelete,
    required this.onEditNote,
  });

  final List<Bookmark> bookmarks;
  final int currentPage;
  final Future<void> Function(int id) onDelete;
  final Future<void> Function(int id, String? note) onEditNote;

  @override
  State<_BookmarksSheetContent> createState() => _BookmarksSheetContentState();
}

class _BookmarksSheetContentState extends State<_BookmarksSheetContent> {
  late List<Bookmark> _items;
  final Set<int> _deleting = {};
  final Set<int> _editingNote = {};

  @override
  void initState() {
    super.initState();
    _items = List.of(widget.bookmarks);
  }

  // ---------------------------------------------------------------------------
  // Actions
  // ---------------------------------------------------------------------------

  Future<void> _delete(Bookmark bm) async {
    if (bm.id == null) return;
    setState(() => _deleting.add(bm.id!));
    try {
      await widget.onDelete(bm.id!);
      if (mounted) setState(() => _items.removeWhere((b) => b.id == bm.id));
    } finally {
      if (mounted) setState(() => _deleting.remove(bm.id));
    }
  }

  Future<void> _editNote(Bookmark bm) async {
    if (bm.id == null) return;

    final newNote = await _showEditNoteDialog(context, bm);
    if (newNote == null || !mounted) return; // cancelled

    setState(() => _editingNote.add(bm.id!));
    try {
      final trimmed = newNote.trim().isEmpty ? null : newNote.trim();
      await widget.onEditNote(bm.id!, trimmed);
      if (mounted) {
        setState(() {
          final idx = _items.indexWhere((b) => b.id == bm.id);
          if (idx != -1) _items[idx] = bm.copyWith(note: trimmed);
        });
      }
    } finally {
      if (mounted) setState(() => _editingNote.remove(bm.id));
    }
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

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
                final isEditingNote = _editingNote.contains(bm.id);
                final isCurrent = bm.page == widget.currentPage;
                final isBusy = isDeleting || isEditingNote;

                return ListTile(
                  onTap: isBusy
                      ? null
                      : () => Navigator.of(context).pop(bm.page),
                  contentPadding: const EdgeInsets.fromLTRB(16, 4, 8, 4),
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
                  subtitle: bm.note != null && bm.note!.isNotEmpty
                      ? Text(
                    bm.note!,
                    style: tt.bodySmall
                        ?.copyWith(color: cs.onSurfaceVariant),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  )
                      : Text(
                    _formatDate(bm.createdAt),
                    style:
                    tt.bodySmall?.copyWith(color: cs.outline),
                  ),
                  // ── Trailing action row ───────────────────────────
                  trailing: isBusy
                      ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                        strokeWidth: 2),
                  )
                      : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Edit note
                      IconButton(
                        icon: Icon(
                          bm.note != null && bm.note!.isNotEmpty
                              ? Icons.edit_note_rounded
                              : Icons.note_add_outlined,
                          color: cs.primary,
                        ),
                        tooltip: bm.note != null &&
                            bm.note!.isNotEmpty
                            ? 'Edit note'
                            : 'Add note',
                        onPressed: () => _editNote(bm),
                      ),
                      // Delete
                      IconButton(
                        icon: Icon(Icons.delete_outline,
                            color: cs.error),
                        tooltip: 'Remove bookmark',
                        onPressed: () => _delete(bm),
                      ),
                    ],
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

// ---------------------------------------------------------------------------
// Edit-note dialog
// ---------------------------------------------------------------------------

Future<String?> _showEditNoteDialog(
    BuildContext context,
    Bookmark bookmark,
    ) async {
  final ctrl = TextEditingController(text: bookmark.note ?? '');
  final pageLabel = 'Page ${bookmark.page + 1}';

  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text('Note for $pageLabel'),
      content: TextField(
        controller: ctrl,
        decoration: const InputDecoration(
          hintText: 'Write a note… (leave empty to clear)',
          border: OutlineInputBorder(),
        ),
        maxLines: 4,
        autofocus: true,
        textCapitalization: TextCapitalization.sentences,
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(), // null = cancelled
          child: const Text('Cancel'),
        ),
        if (bookmark.note != null && bookmark.note!.isNotEmpty)
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(''), // empty = clear note
            child: const Text('Clear note'),
          ),
        FilledButton(
          onPressed: () => Navigator.of(ctx).pop(ctrl.text),
          child: const Text('Save'),
        ),
      ],
    ),
  );
}

// ---------------------------------------------------------------------------
// Empty state
// ---------------------------------------------------------------------------

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