import 'package:flutter/material.dart';

import '../../models/note.dart';
import 'safe_note_dialog.dart';

/// Shows the text-anchored Notes Panel in a modal bottom sheet.
///
/// Each row displays:
/// - Page number
/// - Selected text (italic, truncated)
/// - Note body
///
/// Tapping a row navigates to the page (and attempts scroll-to-text if
/// the caller supplies [onScrollToNote]).
///
/// Returns the page the user wants to navigate to, or `null` if dismissed
/// without selecting a row.
Future<int?> showNotesSheet({
  required BuildContext context,
  required List<Note> notes,
  required int currentPage,
  required Future<void> Function(int id) onDelete,
  required Future<void> Function(int id, String text) onEdit,
}) {
  return showModalBottomSheet<int>(
    context:           context,
    isScrollControlled: true,
    useSafeArea:       true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => _NotesSheetContent(
      notes:       notes,
      currentPage: currentPage,
      onDelete:    onDelete,
      onEdit:      onEdit,
    ),
  );
}

class _NotesSheetContent extends StatefulWidget {
  const _NotesSheetContent({
    required this.notes,
    required this.currentPage,
    required this.onDelete,
    required this.onEdit,
  });

  final List<Note> notes;
  final int currentPage;
  final Future<void> Function(int id) onDelete;
  final Future<void> Function(int id, String text) onEdit;

  @override
  State<_NotesSheetContent> createState() => _NotesSheetContentState();
}

class _NotesSheetContentState extends State<_NotesSheetContent> {
  late List<Note> _items;
  final Set<int> _busy = {};

  @override
  void initState() {
    super.initState();
    _items = List.of(widget.notes);
  }

  Future<void> _delete(Note n) async {
    if (n.id == null) return;
    setState(() => _busy.add(n.id!));
    try {
      await widget.onDelete(n.id!);
      if (mounted) setState(() => _items.removeWhere((x) => x.id == n.id));
    } finally {
      if (mounted) setState(() => _busy.remove(n.id));
    }
  }

  Future<void> _edit(Note n) async {
    if (n.id == null) return;
    final result = await showSafeNoteDialog(
      context:     context,
      title:       'Note — Page ${n.page + 1}',
      initialText: n.noteText,
      allowDelete: true,
    );
    if (result == null || !mounted) return;

    setState(() => _busy.add(n.id!));
    try {
      if (result.deleted) {
        await widget.onDelete(n.id!);
        if (mounted) setState(() => _items.removeWhere((x) => x.id == n.id));
      } else {
        await widget.onEdit(n.id!, result.text);
        if (mounted) {
          setState(() {
            final idx = _items.indexWhere((x) => x.id == n.id);
            if (idx != -1) {
              _items[idx] = _items[idx].copyWith(
                noteText:  result.text,
                updatedAt: DateTime.now(),
              );
            }
          });
        }
      }
    } finally {
      if (mounted) setState(() => _busy.remove(n.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return DraggableScrollableSheet(
      expand:          false,
      initialChildSize: 0.55,
      minChildSize:    0.35,
      maxChildSize:    0.92,
      builder: (_, scrollController) => Column(
        children: [
          // ── Handle ─────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Container(
              width:  40,
              height: 4,
              decoration: BoxDecoration(
                color:        cs.outlineVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          // ── Header ─────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            child: Row(
              children: [
                Text('Notes', style: tt.titleMedium),
                const Spacer(),
                Chip(
                  label: Text(
                    '${_items.length}',
                    style: tt.labelSmall
                        ?.copyWith(color: cs.onSecondaryContainer),
                  ),
                  backgroundColor: cs.secondaryContainer,
                  visualDensity:   VisualDensity.compact,
                  padding:         EdgeInsets.zero,
                ),
              ],
            ),
          ),
          const Divider(height: 1),

          // ── List ───────────────────────────────────────────────────────
          Expanded(
            child: _items.isEmpty
                ? _EmptyState(cs: cs, tt: tt)
                : ListView.separated(
              controller:    scrollController,
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount:     _items.length,
              separatorBuilder: (_, __) =>
              const Divider(height: 1, indent: 72),
              itemBuilder: (_, i) {
                final n        = _items[i];
                final isBusy   = _busy.contains(n.id);
                final isCurrent = n.page == widget.currentPage;
                final hasSelection =
                    n.selectedText.isNotEmpty;

                return ListTile(
                  onTap: isBusy
                      ? null
                      : () => Navigator.of(context).pop(n.page),
                  contentPadding:
                  const EdgeInsets.fromLTRB(16, 4, 8, 4),

                  // Leading avatar: page number
                  leading: CircleAvatar(
                    backgroundColor: isCurrent
                        ? cs.primary
                        : cs.secondaryContainer,
                    foregroundColor: isCurrent
                        ? cs.onPrimary
                        : cs.onSecondaryContainer,
                    child: Text(
                      '${n.page + 1}',
                      style: tt.labelSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: isCurrent
                            ? cs.onPrimary
                            : cs.onSecondaryContainer,
                      ),
                    ),
                  ),

                  // Title: note body
                  title: Text(
                    n.noteText,
                    style: tt.bodyMedium?.copyWith(
                      fontWeight: isCurrent
                          ? FontWeight.bold
                          : FontWeight.normal,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),

                  // Subtitle: selected text (italic) or page label
                  subtitle: hasSelection
                      ? Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Row(
                      children: [
                        Icon(
                          Icons.format_quote_rounded,
                          size:  12,
                          color: cs.primary.withAlpha(178), // 70% opacity
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            n.selectedText,
                            style: tt.bodySmall?.copyWith(
                              color: cs.onSurfaceVariant,
                              fontStyle: FontStyle.italic,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  )
                      : Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      'Page ${n.page + 1}',
                      style: tt.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ),

                  // Trailing: edit + delete
                  trailing: isBusy
                      ? const SizedBox(
                    width:  20,
                    height: 20,
                    child: CircularProgressIndicator(
                        strokeWidth: 2),
                  )
                      : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: Icon(
                          Icons.edit_note_rounded,
                          color: cs.primary,
                        ),
                        tooltip:   'Edit note',
                        onPressed: () => _edit(n),
                      ),
                      IconButton(
                        icon: Icon(
                          Icons.delete_outline,
                          color: cs.error,
                        ),
                        tooltip:   'Remove note',
                        onPressed: () => _delete(n),
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
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.cs, required this.tt});
  final ColorScheme cs;
  final TextTheme   tt;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.sticky_note_2_outlined,
              size: 64, color: cs.outlineVariant),
          const SizedBox(height: 16),
          Text('No notes yet',
              style: tt.titleMedium?.copyWith(color: cs.onSurfaceVariant)),
          const SizedBox(height: 8),
          Text(
            'Select text while reading, then tap\n'
                'the note icon to attach a note.',
            textAlign: TextAlign.center,
            style: tt.bodySmall?.copyWith(color: cs.outline),
          ),
        ],
      ),
    );
  }
}