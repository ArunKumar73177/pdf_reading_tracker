import 'package:flutter/material.dart';

import '../../models/highlight.dart';

// ---------------------------------------------------------------------------
// Callbacks
// ---------------------------------------------------------------------------

class AnnotationCommit {
  const AnnotationCommit({
    required this.type,
    required this.colorValue,
    this.note,
  });
  final AnnotationType type;
  final int            colorValue;
  final String?        note;
}

class NoteCommit {
  const NoteCommit({
    required this.selectedText,
    required this.noteText,
  });
  final String selectedText;
  final String noteText;
}

// ---------------------------------------------------------------------------
// AnnotationActionBar
// ---------------------------------------------------------------------------

/// Compact floating bar shown when the user has selected text in the PDF.
///
/// ### Issue 6 fix — Color API compatibility
///
/// The previous implementation used `cs.onSurface.r.round()`,
/// `cs.onSurface.g.round()`, and `cs.onSurface.b.round()` — double
/// component accessors introduced in Flutter 3.27 (Color API v2). Because
/// this package targets `sdk: ^3.3.0` (Flutter ≥ 3.10), these accessors do
/// not exist in older Flutter versions and cause a runtime crash.
///
/// Fixed by using `.value` bit-shifting, which is available on all Flutter
/// versions:
/// ```dart
/// final r = (cs.onSurface.value >> 16) & 0xFF;
/// final g = (cs.onSurface.value >>  8) & 0xFF;
/// final b =  cs.onSurface.value        & 0xFF;
/// Color.fromARGB(alpha, r, g, b);
/// ```
///
/// All `Color.withOpacity(x)` calls also replaced with [Color.fromARGB]
/// or compile-time hex constants to avoid the Flutter 3.27 deprecation
/// warning on projects that have already migrated to Color API v2.
class AnnotationActionBar extends StatefulWidget {
  const AnnotationActionBar({
    super.key,
    required this.selectedText,
    required this.onCommit,
    required this.onDismiss,
    required this.onAddNote,
    this.currentNote,
  });

  final String                         selectedText;
  final ValueChanged<AnnotationCommit> onCommit;
  final VoidCallback                   onDismiss;
  final VoidCallback                   onAddNote;
  final String?                        currentNote;

  @override
  State<AnnotationActionBar> createState() => AnnotationActionBarState();
}

class AnnotationActionBarState extends State<AnnotationActionBar> {
  AnnotationType _type       = AnnotationType.highlight;
  int            _colorValue = AnnotationColors.yellow;

  static const _types = [
    _TypeMeta(AnnotationType.highlight,
        Icons.highlight_rounded,            'Highlight'),
    _TypeMeta(AnnotationType.underline,
        Icons.format_underline_rounded,     'Underline'),
    _TypeMeta(AnnotationType.strikethrough,
        Icons.format_strikethrough_rounded, 'Strike'),
    _TypeMeta(AnnotationType.squiggly,
        Icons.waves_rounded,                'Squiggly'),
  ];

  static const _colorLabels = <int, String>{
    AnnotationColors.yellow: 'Yellow',
    AnnotationColors.green:  'Green',
    AnnotationColors.blue:   'Blue',
    AnnotationColors.pink:   'Pink',
    AnnotationColors.orange: 'Orange',
    AnnotationColors.purple: 'Purple',
  };

  void _commit() {
    widget.onCommit(AnnotationCommit(
      type:       _type,
      colorValue: _colorValue,
      note:       widget.currentNote,
    ));
  }

  /// Extracts RGB components from a [Color] using `.value` bit-shifting.
  /// Compatible with all Flutter versions (does not use Color API v2
  /// `.r/.g/.b` double accessors which require Flutter ≥ 3.27).
  static Color _shadowColor(Color base, int alpha) {
    final r = (base.value >> 16) & 0xFF;
    final g = (base.value >>  8) & 0xFF;
    final b =  base.value        & 0xFF;
    return Color.fromARGB(alpha, r, g, b);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    final preview = widget.selectedText.length > 40
        ? '${widget.selectedText.substring(0, 40)}…'
        : widget.selectedText;

    return Material(
      elevation:    8,
      borderRadius: BorderRadius.circular(16),
      color:        cs.surfaceContainerHigh,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Column(
          mainAxisSize:       MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Selected text preview + dismiss ────────────────────────
            Row(
              children: [
                Expanded(
                  child: Text(
                    '"$preview"',
                    maxLines:  1,
                    overflow:  TextOverflow.ellipsis,
                    style: tt.bodySmall?.copyWith(
                      color:     cs.onSurfaceVariant,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ),
                IconButton(
                  icon:        const Icon(Icons.close_rounded, size: 18),
                  tooltip:     'Dismiss',
                  onPressed:   widget.onDismiss,
                  color:       cs.onSurfaceVariant,
                  padding:     EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ),

            const SizedBox(height: 8),

            // ── Annotation type chips ───────────────────────────────────
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: _types.map((meta) {
                  final selected = _type == meta.type;
                  return Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: FilterChip(
                      selected:      selected,
                      avatar:        Icon(meta.icon, size: 16),
                      label:         Text(meta.label, style: tt.labelSmall),
                      onSelected:    (_) => setState(() => _type = meta.type),
                      visualDensity: VisualDensity.compact,
                      padding:       EdgeInsets.zero,
                    ),
                  );
                }).toList(growable: false),
              ),
            ),

            const SizedBox(height: 8),

            // ── Color dots + note button + apply ───────────────────────
            Row(
              children: [
                ...AnnotationColors.palette.map((c) {
                  final isSelected   = _colorValue == c;
                  final displayColor = Color(c | 0xFF000000);
                  return Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: Tooltip(
                      message: _colorLabels[c] ?? '',
                      child: GestureDetector(
                        onTap: () => setState(() => _colorValue = c),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          width:  24,
                          height: 24,
                          decoration: BoxDecoration(
                            color:  displayColor,
                            shape:  BoxShape.circle,
                            border: isSelected
                                ? Border.all(
                                color: cs.onSurface, width: 2.5)
                                : null,
                            // Issue 6: use .value bit-shift instead of
                            // .r/.g/.b (Flutter ≥ 3.27 only).
                            boxShadow: isSelected
                                ? [
                              BoxShadow(
                                color:      _shadowColor(cs.onSurface, 77),
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

                // Note button
                Tooltip(
                  message: widget.currentNote == null
                      ? 'Add note'
                      : 'Edit note',
                  child: IconButton(
                    icon: Icon(
                      widget.currentNote == null
                          ? Icons.note_add_outlined
                          : Icons.note_rounded,
                      size:  20,
                      color: widget.currentNote == null
                          ? cs.onSurfaceVariant
                          : cs.primary,
                    ),
                    padding:     EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    onPressed:   widget.onAddNote,
                  ),
                ),

                const SizedBox(width: 8),

                // Apply button
                FilledButton(
                  onPressed: _commit,
                  style: FilledButton.styleFrom(
                    backgroundColor: Color(_colorValue | 0xFF000000),
                    foregroundColor: Colors.black87,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 8),
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
  final IconData       icon;
  final String         label;
}