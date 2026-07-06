import 'package:flutter/material.dart';

import '../../models/highlight.dart';
import 'safe_note_dialog.dart';

/// Shows the annotation (highlight/underline/strikethrough/squiggly) list
/// in a modal bottom sheet — the "Annotation History" screen (Issue 2).
///
/// Mirrors `bookmarks_sheet.dart`'s structure and calling convention
/// exactly: `showModalBottomSheet` → stateful sheet content holding its own
/// list copy + busy-sets → `DraggableScrollableSheet` → `ListView.separated`.
/// Reusing this shape keeps the two sheets visually and behaviourally
/// consistent, and means no new interaction pattern is introduced.
///
/// Returns the page the user wants to navigate to, or `null` if dismissed
/// without selecting a row.
Future<int?> showHighlightsSheet({
  required BuildContext context,
  required List<Highlight> highlights,
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
    builder: (_) => _HighlightsSheetContent(
      highlights: highlights,
      currentPage: currentPage,
      onDelete: onDelete,
      onEditNote: onEditNote,
    ),
  );
}

// ---------------------------------------------------------------------------
// Type → icon/label metadata (mirrors AnnotationActionBar._types)
// ---------------------------------------------------------------------------

class _TypeMeta {
  const _TypeMeta(this.icon, this.label);
  final IconData icon;
  final String label;
}

const Map<AnnotationType, _TypeMeta> _typeMeta = {
  AnnotationType.highlight: _TypeMeta(Icons.highlight_rounded, 'Highlight'),
  AnnotationType.underline:
      _TypeMeta(Icons.format_underline_rounded, 'Underline'),
  AnnotationType.strikethrough:
      _TypeMeta(Icons.format_strikethrough_rounded, 'Strikethrough'),
  AnnotationType.squiggly: _TypeMeta(Icons.waves_rounded, 'Squiggly'),
};

// ---------------------------------------------------------------------------
// Sheet content
// ---------------------------------------------------------------------------

class _HighlightsSheetContent extends StatefulWidget {
  const _HighlightsSheetContent({
    required this.highlights,
    required this.currentPage,
    required this.onDelete,
    required this.onEditNote,
  });

  final List<Highlight> highlights;
  final int currentPage;
  final Future<void> Function(int id) onDelete;
  final Future<void> Function(int id, String? note) onEditNote;

  @override
  State<_HighlightsSheetContent> createState() =>
      _HighlightsSheetContentState();
}

class _HighlightsSheetContentState extends State<_HighlightsSheetContent> {
  late List<Highlight> _items;
  final Set<int> _deleting = {};
  final Set<int> _editingNote = {};

  @override
  void initState() {
    super.initState();
    _items = List.of(widget.highlights);
  }

  // ---------------------------------------------------------------------------
  // Actions
  // ---------------------------------------------------------------------------

  Future<void> _delete(Highlight h) async {
    if (h.id == null) return;
    setState(() => _deleting.add(h.id!));
    try {
      await widget.onDelete(h.id!);
      if (mounted) setState(() => _items.removeWhere((x) => x.id == h.id));
    } finally {
      if (mounted) setState(() => _deleting.remove(h.id));
    }
  }

  Future<void> _editNote(Highlight h) async {
    if (h.id == null) return;

    // Use SafeNoteDialog (useRootNavigator, owned controller lifecycle)
    // so the TextEditingController is never at risk of being orphaned.
    final result = await showSafeNoteDialog(
      context: context,
      title: 'Note — Page ${h.page + 1}',
      initialText: h.note ?? '',
      allowDelete: h.note != null && h.note!.isNotEmpty,
    );
    if (result == null || !mounted) return; // cancelled

    setState(() => _editingNote.add(h.id!));
    try {
      if (result.deleted) {
        await widget.onEditNote(h.id!, null);
        if (mounted) {
          setState(() {
            final idx = _items.indexWhere((x) => x.id == h.id);
            if (idx != -1) {
              _items[idx] = _items[idx].copyWith(clearNote: true);
            }
          });
        }
      } else {
        final trimmed = result.text.trim().isEmpty ? null : result.text.trim();
        await widget.onEditNote(h.id!, trimmed);
        if (mounted) {
          setState(() {
            final idx = _items.indexWhere((x) => x.id == h.id);
            if (idx != -1) {
              _items[idx] = _items[idx].copyWith(
                note: trimmed,
                clearNote: trimmed == null,
              );
            }
          });
        }
      }
    } finally {
      if (mounted) setState(() => _editingNote.remove(h.id));
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
                Text('Annotations', style: tt.titleMedium),
                const Spacer(),
                Chip(
                  label: Text(
                    '${_items.length}',
                    style:
                        tt.labelSmall?.copyWith(color: cs.onSecondaryContainer),
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
                      final h = _items[i];
                      final isDeleting = _deleting.contains(h.id);
                      final isEditingNote = _editingNote.contains(h.id);
                      final isCurrent = h.page == widget.currentPage;
                      final isBusy = isDeleting || isEditingNote;
                      final hasNote = h.note != null && h.note!.isNotEmpty;
                      final meta = _typeMeta[h.annotationType]!;
                      final dotColor = Color(h.colorValue | 0xFF000000);

                      final preview = h.selectedText.length > 60
                          ? '${h.selectedText.substring(0, 60)}…'
                          : h.selectedText;

                      return ListTile(
                        onTap: isBusy
                            ? null
                            : () => Navigator.of(context).pop(h.page),
                        contentPadding: const EdgeInsets.fromLTRB(16, 4, 8, 4),
                        // ── Leading: colour dot + type icon ─────────────────
                        leading: CircleAvatar(
                          backgroundColor: isCurrent
                              ? cs.primary
                              : dotColor.withAlpha(229), // 90% opacity
                          foregroundColor:
                              isCurrent ? cs.onPrimary : Colors.black87,
                          child: Icon(meta.icon, size: 18),
                        ),
                        // ── Title: type + page ───────────────────────────────
                        title: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Flexible(
                              child: Text(
                                meta.label,
                                style: tt.bodyLarge?.copyWith(
                                  fontWeight: isCurrent
                                      ? FontWeight.bold
                                      : FontWeight.normal,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              '· Page ${h.page + 1}',
                              style: tt.bodySmall
                                  ?.copyWith(color: cs.onSurfaceVariant),
                            ),
                            if (hasNote) ...[
                              const SizedBox(width: 6),
                              Icon(Icons.sticky_note_2_rounded,
                                  size: 14, color: cs.primary),
                            ],
                          ],
                        ),
                        // ── Subtitle: selected-text preview, or the note ─────
                        subtitle: Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            hasNote ? h.note! : '"$preview"',
                            style: tt.bodySmall?.copyWith(
                              color:
                                  hasNote ? cs.onSurface : cs.onSurfaceVariant,
                              fontStyle:
                                  hasNote ? FontStyle.normal : FontStyle.italic,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        // ── Trailing action row ───────────────────────────
                        trailing: isBusy
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  // Edit note
                                  IconButton(
                                    icon: Icon(
                                      hasNote
                                          ? Icons.edit_note_rounded
                                          : Icons.note_add_outlined,
                                      color: cs.primary,
                                    ),
                                    tooltip: hasNote ? 'Edit note' : 'Add note',
                                    onPressed: () => _editNote(h),
                                  ),
                                  // Delete
                                  IconButton(
                                    icon: Icon(Icons.delete_outline,
                                        color: cs.error),
                                    tooltip: 'Remove annotation',
                                    onPressed: () => _delete(h),
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

// _showEditNoteDialog removed — replaced with showSafeNoteDialog in _editNote.

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
          Icon(Icons.format_color_text_rounded,
              size: 64, color: cs.outlineVariant),
          const SizedBox(height: 16),
          Text('No annotations yet',
              style: tt.titleMedium?.copyWith(color: cs.onSurfaceVariant)),
          const SizedBox(height: 8),
          Text(
            'Select text while reading to highlight,\nunderline, or add a note.',
            textAlign: TextAlign.center,
            style: tt.bodySmall?.copyWith(color: cs.outline),
          ),
        ],
      ),
    );
  }
}
