import 'package:flutter/material.dart';

import '../../models/highlight.dart';

// ---------------------------------------------------------------------------
// Callbacks
// ---------------------------------------------------------------------------

/// Returned by [AnnotationActionBar] when the user taps "Apply".
class AnnotationCommit {
  const AnnotationCommit({
    required this.type,
    required this.colorValue,
    this.note,
  });
  final AnnotationType type;
  final int colorValue;
  final String? note;
}

// ---------------------------------------------------------------------------
// AnnotationActionBar
// ---------------------------------------------------------------------------

/// Compact floating bar shown when the user has selected text in the PDF.
///
/// Allows the user to choose annotation type, colour, and optionally
/// trigger a note dialog owned entirely by the parent.
///
/// ### Ownership (fixes the v2.5.2/v2.5.3 disposal crash for good)
/// This widget is **stateless with respect to anything that owns a
/// lifecycle resource**. It holds only the transient `_type` /
/// `_colorValue` selection as local `State` — no `TextEditingController`,
/// no dialog, no `FocusNode`. Tapping the note button only invokes
/// [onAddNote]; the actual editor is [SafeNoteDialog], opened and owned
/// entirely by [PdfReadingTrackerViewer]'s state on the **root**
/// `Navigator`, structurally isolated from this bar's element subtree.
/// This bar can be hidden, rebuilt, faded, or removed at any time with no
/// risk to any dialog — it has no reference to one.
class AnnotationActionBar extends StatefulWidget {
  const AnnotationActionBar({
    super.key,
    required this.selectedText,
    required this.onCommit,
    required this.onDismiss,
    required this.onAddNote,
    this.currentNote,
  });

  final String selectedText;
  final ValueChanged<AnnotationCommit> onCommit;
  final VoidCallback onDismiss;

  /// Called when the user taps the note button. The parent owns the actual
  /// dialog UI via [SafeNoteDialog] and updates [currentNote] on the next
  /// rebuild once the dialog resolves.
  final VoidCallback onAddNote;

  /// The note currently staged for this not-yet-committed annotation, if
  /// any. Display-only.
  final String? currentNote;

  @override
  State<AnnotationActionBar> createState() => AnnotationActionBarState();
}

class AnnotationActionBarState extends State<AnnotationActionBar> {
  AnnotationType _type = AnnotationType.highlight;
  int _colorValue = AnnotationColors.yellow;

  static const _types = [
    _TypeMeta(AnnotationType.highlight, Icons.highlight_rounded, 'Highlight'),
    _TypeMeta(AnnotationType.underline, Icons.format_underline_rounded, 'Underline'),
    _TypeMeta(AnnotationType.strikethrough, Icons.format_strikethrough_rounded, 'Strike'),
    _TypeMeta(AnnotationType.squiggly, Icons.waves_rounded, 'Squiggly'),
  ];

  static const _colorLabels = <int, String>{
    AnnotationColors.yellow: 'Yellow',
    AnnotationColors.green: 'Green',
    AnnotationColors.blue: 'Blue',
    AnnotationColors.pink: 'Pink',
    AnnotationColors.orange: 'Orange',
    AnnotationColors.purple: 'Purple',
  };

  void _commit() {
    widget.onCommit(AnnotationCommit(
      type: _type,
      colorValue: _colorValue,
      note: widget.currentNote,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    final preview = widget.selectedText.length > 40
        ? '${widget.selectedText.substring(0, 40)}…'
        : widget.selectedText;

    return Material(
      elevation: 8,
      borderRadius: BorderRadius.circular(16),
      color: cs.surfaceContainerHigh,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '"$preview"',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: tt.bodySmall?.copyWith(
                      color: cs.onSurfaceVariant,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded, size: 18),
                  tooltip: 'Dismiss',
                  onPressed: widget.onDismiss,
                  color: cs.onSurfaceVariant,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: _types.map((meta) {
                  final selected = _type == meta.type;
                  return Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: FilterChip(
                      selected: selected,
                      avatar: Icon(meta.icon, size: 16),
                      label: Text(meta.label, style: tt.labelSmall),
                      onSelected: (_) => setState(() => _type = meta.type),
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                    ),
                  );
                }).toList(growable: false),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                ...AnnotationColors.palette.map((c) {
                  final isSelected = _colorValue == c;
                  final displayColor = Color(c | 0xFF000000);
                  return Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: Tooltip(
                      message: _colorLabels[c] ?? '',
                      child: GestureDetector(
                        onTap: () => setState(() => _colorValue = c),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          width: 24,
                          height: 24,
                          decoration: BoxDecoration(
                            color: displayColor,
                            shape: BoxShape.circle,
                            border: isSelected
                                ? Border.all(color: cs.onSurface, width: 2.5)
                                : null,
                            boxShadow: isSelected
                                ? [
                              BoxShadow(
                                color: cs.onSurface.withOpacity(0.3),
                                blurRadius: 4,
                              ),
                            ]
                                : null,
                          ),
                        ),
                      ),
                    ),
                  );
                }),
                const Spacer(),
                Tooltip(
                  message: (widget.currentNote == null) ? 'Add note' : 'Edit note',
                  child: IconButton(
                    icon: Icon(
                      widget.currentNote == null
                          ? Icons.note_add_outlined
                          : Icons.note_rounded,
                      size: 20,
                      color: widget.currentNote == null
                          ? cs.onSurfaceVariant
                          : cs.primary,
                    ),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    onPressed: widget.onAddNote,
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: _commit,
                  style: FilledButton.styleFrom(
                    backgroundColor: Color(_colorValue | 0xFF000000),
                    foregroundColor: Colors.black87,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    visualDensity: VisualDensity.compact,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                  ),
                  child: const Text('Apply'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _TypeMeta {
  const _TypeMeta(this.type, this.icon, this.label);
  final AnnotationType type;
  final IconData icon;
  final String label;
}