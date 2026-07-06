import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pdf_reading_tracker/pdf_reading_tracker.dart';

import '../utils/pdf_id_helper.dart';

// ---------------------------------------------------------------------------
// PdfOperationsScreen — v2.2.0
//
// Merge and Split PDF operations.
//
// **v2.2.0 changes — Improvement 1 (bookmarks & progress for merged/split)**
//
// After merge/split:
//   1. Output is copied from temp → ApplicationDocumentsDirectory/user_pdfs/
//      (same persistent dir as PdfPickerService) via [_copyToPersistentDir].
//   2. A stable pdfId is derived from the filename via [PdfIdHelper].
//   3. PdfReadingTrackerViewer is opened with filePath + stable pdfId, so
//      progress and bookmarks work exactly like user-picked PDFs.
//
// BuildContext-across-async-gaps: every use of BuildContext after an await
// is guarded by an explicit `if (!context.mounted) return` immediately before
// the context access, satisfying the `use_build_context_synchronously` lint.
// ---------------------------------------------------------------------------

class PdfOperationsScreen extends StatefulWidget {
  const PdfOperationsScreen({super.key});

  @override
  State<PdfOperationsScreen> createState() => _PdfOperationsScreenState();
}

class _PdfOperationsScreenState extends State<PdfOperationsScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('PDF Operations'),
        backgroundColor: cs.primaryContainer,
        foregroundColor: cs.onPrimaryContainer,
        bottom: TabBar(
          controller: _tabs,
          labelColor: cs.onPrimaryContainer,
          unselectedLabelColor: cs.onPrimaryContainer.withAlpha(153),
          indicatorColor: cs.onPrimaryContainer,
          tabs: const [
            Tab(icon: Icon(Icons.merge_type_rounded), text: 'Merge'),
            Tab(icon: Icon(Icons.call_split_rounded), text: 'Split'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: const [
          _MergeTab(),
          _SplitTab(),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Shared helpers
// ---------------------------------------------------------------------------

/// Copies [tempPath] to `ApplicationDocumentsDirectory/user_pdfs/<filename>`.
///
/// Returns the persistent destination path.
Future<String> _copyToPersistentDir(String tempPath) async {
  final docsDir = await getApplicationDocumentsDirectory();
  final destDir = Directory(p.join(docsDir.path, 'user_pdfs'));
  if (!destDir.existsSync()) {
    destDir.createSync(recursive: true);
  }
  final fileName = p.basename(tempPath);
  final destPath = p.join(destDir.path, fileName);
  await File(tempPath).copy(destPath);
  return destPath;
}

// ---------------------------------------------------------------------------
// Merge tab
// ---------------------------------------------------------------------------

class _MergeTab extends StatefulWidget {
  const _MergeTab();

  @override
  State<_MergeTab> createState() => _MergeTabState();
}

class _MergeTabState extends State<_MergeTab> {
  final List<String> _selectedPaths = [];
  bool _busy = false;

  Future<void> _pickPdf() async {
    try {
      final picked = await PdfPickerService.pickPdf();
      if (!mounted) return;
      if (picked == null) return;
      setState(() => _selectedPaths.add(picked.filePath));
    } on PdfPickerException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(e.message),
        backgroundColor: Theme.of(context).colorScheme.error,
      ));
    }
  }

  Future<void> _merge() async {
    if (_selectedPaths.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: const Text('Select at least 2 PDFs to merge.'),
        backgroundColor: Theme.of(context).colorScheme.error,
      ));
      return;
    }

    setState(() => _busy = true);

    String? tempPath;
    String? persistentPath;

    try {
      // 1. Run merge — produces a temp file.
      tempPath = await PdfMergeService.merge(inputPaths: _selectedPaths);

      // 2. Move to persistent storage so the pdfId is stable.
      persistentPath = await _copyToPersistentDir(tempPath);
    } on PdfMergeException catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Merge failed: ${e.message}'),
        backgroundColor: Theme.of(context).colorScheme.error,
      ));
      return;
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Unexpected error: $e'),
        backgroundColor: Theme.of(context).colorScheme.error,
      ));
      return;
    }

    // 3. Clean up temp file (non-fatal if it fails).
    try {
      await File(tempPath).delete();
    } catch (_) {}

    if (!mounted) return;
    setState(() {
      _selectedPaths.clear();
      _busy = false;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('PDFs merged successfully!')),
    );

    // 4. Open the result — context.mounted already verified above.
    if (!mounted) return;
    await _openOutputPdf(context, persistentPath: persistentPath);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Select two or more PDFs to merge into one document.',
            style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 16),
          if (_selectedPaths.isNotEmpty) ...[
            Text('Selected PDFs (${_selectedPaths.length})',
                style: tt.labelMedium?.copyWith(color: cs.primary)),
            const SizedBox(height: 8),
            ..._selectedPaths.asMap().entries.map((e) => _FileChip(
                  index: e.key + 1,
                  path: e.value,
                  onRemove: () =>
                      setState(() => _selectedPaths.removeAt(e.key)),
                )),
            const SizedBox(height: 16),
          ],
          OutlinedButton.icon(
            onPressed: _busy ? null : _pickPdf,
            icon: const Icon(Icons.add_rounded),
            label: const Text('Add PDF'),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: (_busy || _selectedPaths.length < 2) ? null : _merge,
            icon: _busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.merge_type_rounded),
            label: Text(_busy ? 'Merging…' : 'Merge PDFs'),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Split tab
// ---------------------------------------------------------------------------

class _SplitTab extends StatefulWidget {
  const _SplitTab();

  @override
  State<_SplitTab> createState() => _SplitTabState();
}

class _SplitTabState extends State<_SplitTab> {
  String? _selectedPath;
  final _pagesCtrl = TextEditingController(text: '5');
  bool _busy = false;

  @override
  void dispose() {
    _pagesCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickPdf() async {
    try {
      final picked = await PdfPickerService.pickPdf();
      if (!mounted) return;
      if (picked == null) return;
      setState(() => _selectedPath = picked.filePath);
    } on PdfPickerException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(e.message),
        backgroundColor: Theme.of(context).colorScheme.error,
      ));
    }
  }

  Future<void> _split() async {
    final path = _selectedPath;
    if (path == null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: const Text('Please pick a PDF first.'),
        backgroundColor: Theme.of(context).colorScheme.error,
      ));
      return;
    }

    final pagesPerFile = int.tryParse(_pagesCtrl.text.trim());
    if (pagesPerFile == null || pagesPerFile < 1) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: const Text('Enter a valid pages-per-file number.'),
        backgroundColor: Theme.of(context).colorScheme.error,
      ));
      return;
    }

    setState(() => _busy = true);

    List<String> persistentPaths;

    try {
      // 1. Run split — produces temp files.
      final tempPaths = await PdfSplitService.split(
        pdfPath: path,
        pagesPerFile: pagesPerFile,
      );

      // 2. Copy each part to persistent storage, clean up temp.
      persistentPaths = [];
      for (final tp in tempPaths) {
        persistentPaths.add(await _copyToPersistentDir(tp));
        try {
          await File(tp).delete();
        } catch (_) {}
      }
    } on PdfSplitException catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Split failed: ${e.message}'),
        backgroundColor: Theme.of(context).colorScheme.error,
      ));
      return;
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Unexpected error: $e'),
        backgroundColor: Theme.of(context).colorScheme.error,
      ));
      return;
    }

    if (!mounted) return;
    setState(() {
      _selectedPath = null;
      _busy = false;
    });

    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('Split into ${persistentPaths.length} parts!'),
    ));

    // 3. Show sheet — context.mounted already verified above.
    if (!mounted) return;
    await _showSplitResultsSheet(context, persistentPaths);
  }

  Future<void> _showSplitResultsSheet(
    BuildContext context,
    List<String> paths,
  ) async {
    final cs = Theme.of(context).colorScheme;
    await showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetCtx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
              child: Text(
                'Split complete — ${paths.length} parts',
                style: Theme.of(sheetCtx)
                    .textTheme
                    .titleMedium
                    ?.copyWith(color: cs.primary),
              ),
            ),
            ...paths.asMap().entries.map(
                  (e) => ListTile(
                    leading: CircleAvatar(
                      backgroundColor: cs.secondaryContainer,
                      foregroundColor: cs.onSecondaryContainer,
                      child: Text('${e.key + 1}'),
                    ),
                    title: Text(
                      PdfIdHelper.titleFromFilePath(e.value),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: const Icon(Icons.open_in_new_rounded),
                    onTap: () async {
                      // Close the sheet first, then open the PDF using the
                      // original screen's context (captured before the await).
                      Navigator.of(sheetCtx).pop();
                      if (!context.mounted) return;
                      await _openOutputPdf(
                        context,
                        persistentPath: e.value,
                      );
                    },
                  ),
                ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Pick a PDF and choose how many pages per part.',
            style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 16),
          if (_selectedPath != null) ...[
            _FileChip(
              index: 1,
              path: _selectedPath!,
              onRemove: () => setState(() => _selectedPath = null),
            ),
            const SizedBox(height: 12),
          ],
          OutlinedButton.icon(
            onPressed: _busy ? null : _pickPdf,
            icon: const Icon(Icons.upload_file_rounded),
            label: Text(_selectedPath == null ? 'Pick PDF' : 'Change PDF'),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _pagesCtrl,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Pages per part',
              hintText: 'e.g. 5',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.format_list_numbered_rounded),
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: (_busy || _selectedPath == null) ? null : _split,
            icon: _busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.call_split_rounded),
            label: Text(_busy ? 'Splitting…' : 'Split PDF'),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Shared: open an output PDF in the reader
// ---------------------------------------------------------------------------

/// Opens [PdfReadingTrackerViewer] for a file already in persistent storage.
///
/// [context] must be mounted at the call site — callers are responsible for
/// checking `context.mounted` immediately before calling this function.
Future<void> _openOutputPdf(
  BuildContext context, {
  required String persistentPath,
}) async {
  final pdfId = PdfIdHelper.fromFilePath(persistentPath);
  final title = PdfIdHelper.titleFromFilePath(persistentPath);

  await Navigator.of(context).push(MaterialPageRoute(
    builder: (_) => Scaffold(
      body: PdfReadingTrackerViewer(
        pdfId: pdfId,
        pdfTitle: title,
        filePath: persistentPath,
      ),
    ),
  ));
}

// ---------------------------------------------------------------------------
// Shared file chip widget
// ---------------------------------------------------------------------------

class _FileChip extends StatelessWidget {
  const _FileChip({
    required this.index,
    required this.path,
    required this.onRemove,
  });

  final int index;
  final String path;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: cs.secondaryContainer.withAlpha(80),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 14,
            backgroundColor: cs.secondaryContainer,
            foregroundColor: cs.onSecondaryContainer,
            child: Text('$index', style: const TextStyle(fontSize: 12)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              p.basename(path),
              style: tt.bodyMedium,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close_rounded, size: 18),
            onPressed: onRemove,
            color: cs.onSurfaceVariant,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          ),
        ],
      ),
    );
  }
}
