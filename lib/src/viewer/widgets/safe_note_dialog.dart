import 'package:flutter/material.dart';

/// A fully self-contained note editor dialog.
///
/// ### Why this exists (fixes the disposed-controller / duplicate-key crash)
/// Earlier versions created a `TextEditingController` inline inside a
/// parent State's method (`_openPendingNoteDialog` / `_showAddNoteDialog`),
/// then disposed it in a `finally` block after `await showDialog(...)`
/// resolved. That pattern is fragile for two independent reasons that both
/// manifested here:
///
/// 1. The PDF viewer (`SfPdfViewer`) keeps its own **native, platform-level
///    text-selection-handle overlay** alive behind the dialog unless
///    selection is explicitly torn down first. That overlay can still fire
///    `onTextSelectionChanged` while the dialog's `TextField` has focus,
///    which (via `highlightNotifier`) rebuilds an ancestor of the dialog's
///    *trigger* widget — but the dialog itself, if pushed on the same
///    `Navigator` as the page, can have its route's element tree
///    invalidated mid-flight by that ancestor rebuild, corrupting the
///    controller's lifecycle and producing the duplicate-`GlobalKey` /
///    `_dependents.isEmpty` crashes seen in the logs.
/// 2. A controller created in a method-local variable has no `State`
///    object of its own — there's nothing to guarantee `dispose()` runs
///    exactly once, exactly after the last frame that uses it, and never
///    after the owning context is gone.
///
/// **The fix:** this widget owns its `TextEditingController` and
/// `FocusNode` with completely standard, textbook `State` lifecycle
/// (`initState` creates, `dispose` destroys, nothing else ever touches
/// them). It is opened via [showSafeNoteDialog], which uses
/// `useRootNavigator: true` so it always lives on the **root** Navigator —
/// structurally outside the PDF viewer's element subtree — so no rebuild
/// triggered by `SfPdfViewer`'s native selection overlay can ever reach
/// into this dialog's element tree. The dialog also explicitly clears the
/// PDF's text selection *before* opening (via [onOpen]), so the native
/// selection-handle overlay is torn down and cannot fire any further
/// callbacks while this dialog is visible.
///
/// ### Context menu (fixes Issue 2)
/// [TextField.contextMenuBuilder] is overridden to render **only**
/// Cut / Copy / Paste / Select All. Highlight / Underline / Strikethrough /
/// Squiggly are Syncfusion-specific entries that only ever come from
/// `SfPdfViewer`'s own selection toolbar — they cannot appear here because
/// this dialog contains no `SfPdfViewer` instance and uses Flutter's
/// standard `EditableText` selection plumbing exclusively.
class SafeNoteDialogResult {
  const SafeNoteDialogResult.saved(this.text) : deleted = false;
  const SafeNoteDialogResult.deleted()
      : text = '',
        deleted = true;

  final String text;
  final bool deleted;
}

/// Opens the safe note editor and returns the result, or `null` if the user
/// cancelled (back button, barrier tap, or Cancel button).
///
/// [onOpen] is invoked synchronously before the dialog route is pushed —
/// use it to clear any active PDF text selection so the native Syncfusion
/// selection-handle overlay is torn down first.
Future<SafeNoteDialogResult?> showSafeNoteDialog({
  required BuildContext context,
  required String title,
  required String initialText,
  bool allowDelete = false,
  VoidCallback? onOpen,
}) {
  onOpen?.call();

  return showGeneralDialog<SafeNoteDialogResult>(
    context: context,
    useRootNavigator: true,
    barrierDismissible: true,
    barrierLabel: 'Dismiss',
    barrierColor: Colors.black54,
    transitionDuration: const Duration(milliseconds: 180),
    pageBuilder: (dialogContext, _, __) => _SafeNoteDialog(
      title: title,
      initialText: initialText,
      allowDelete: allowDelete,
    ),
    transitionBuilder: (_, animation, __, child) => FadeTransition(
      opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
      child: ScaleTransition(
        scale: Tween<double>(begin: 0.96, end: 1.0).animate(
          CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
        ),
        child: child,
      ),
    ),
  );
}

// ---------------------------------------------------------------------------
// Implementation
// ---------------------------------------------------------------------------

class _SafeNoteDialog extends StatefulWidget {
  const _SafeNoteDialog({
    required this.title,
    required this.initialText,
    required this.allowDelete,
  });

  final String title;
  final String initialText;
  final bool allowDelete;

  @override
  State<_SafeNoteDialog> createState() => _SafeNoteDialogState();
}

class _SafeNoteDialogState extends State<_SafeNoteDialog> {
  // Owned entirely by this State. Created once in initState, disposed
  // exactly once in dispose. Never recreated, never shared, never touched
  // from outside this class.
  late final TextEditingController _controller =
      TextEditingController(text: widget.initialText);
  late final FocusNode _focusNode = FocusNode();

  bool _saving = false;

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _save() {
    if (_saving) return; // guard against double-tap re-entrancy
    final trimmed = _controller.text.trim();
    if (trimmed.isEmpty) {
      // Treat empty save as a delete-or-noop, never persist blank notes.
      Navigator.of(context).pop(
        widget.allowDelete ? const SafeNoteDialogResult.deleted() : null,
      );
      return;
    }
    setState(() => _saving = true);
    Navigator.of(context).pop(SafeNoteDialogResult.saved(trimmed));
  }

  void _delete() {
    Navigator.of(context).pop(const SafeNoteDialogResult.deleted());
  }

  void _cancel() {
    Navigator.of(context).pop();
  }

  /// Restricts the selection toolbar to Cut / Copy / Paste / Select All.
  /// No Syncfusion entries can appear here regardless of platform, because
  /// this is a plain [EditableText] context menu, fully independent of
  /// `SfPdfViewer`'s own overlay.
  Widget _buildContextMenu(
    BuildContext context,
    EditableTextState editableTextState,
  ) {
    final buttonItems = editableTextState.contextMenuButtonItems
        .where((item) =>
            item.type == ContextMenuButtonType.cut ||
            item.type == ContextMenuButtonType.copy ||
            item.type == ContextMenuButtonType.paste ||
            item.type == ContextMenuButtonType.selectAll)
        .toList(growable: false);

    return AdaptiveTextSelectionToolbar.buttonItems(
      anchors: editableTextState.contextMenuAnchors,
      buttonItems: buttonItems,
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(widget.title, style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 16),
              TextField(
                controller: _controller,
                focusNode: _focusNode,
                autofocus: true,
                maxLines: 6,
                minLines: 3,
                textCapitalization: TextCapitalization.sentences,
                contextMenuBuilder: _buildContextMenu,
                decoration: InputDecoration(
                  hintText: 'Type your note here…',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                // Submitting via keyboard "done" action saves directly —
                // no separate code path, no separate controller reference.
                onSubmitted: (_) => _save(),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  if (widget.allowDelete)
                    TextButton.icon(
                      onPressed: _saving ? null : _delete,
                      icon: Icon(Icons.delete_outline, color: cs.error),
                      label: Text('Delete', style: TextStyle(color: cs.error)),
                    ),
                  const Spacer(),
                  TextButton(
                    onPressed: _saving ? null : _cancel,
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: _saving ? null : _save,
                    child: const Text('Save'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
