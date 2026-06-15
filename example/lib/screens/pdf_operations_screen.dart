import 'dart:io';

import 'package:alh_pdf_view/alh_pdf_view.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pdf_reading_tracker/pdf_reading_tracker.dart';

// ---------------------------------------------------------------------------
// PDF Operations Screen — v2.1.0
//
// Merge tab
//   • User selects 2+ PDFs via FilePicker
//   • Selected files shown in a dismissible list
//   • "Merge" button produces output, opens result in viewer
//
// Split tab
//   • User selects one PDF via FilePicker
//   • User enters pages-per-chunk (validated; default 5)
//   • "Split" button produces parts, listed with individual "Open" buttons
//
// All heavy work is already off the main thread via Isolate.run inside
// PdfMergeService / PdfSplitService.
// ---------------------------------------------------------------------------

class PdfOperationsScreen extends StatefulWidget {
  const PdfOperationsScreen({super.key});

  @override
  State<PdfOperationsScreen> createState() => _PdfOperationsScreenState();
}

class _PdfOperationsScreenState extends State<PdfOperationsScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  // ── Merge state ─────────────────────────────────────────────────────────────
  final List<PlatformFile> _mergeFiles = [];
  bool _merging = false;
  String? _mergedPath;
  String? _mergeError;

  // ── Split state ─────────────────────────────────────────────────────────────
  PlatformFile? _splitFile;
  final _pagesCtrl = TextEditingController(text: '5');
  bool _splitting = false;
  List<String> _splitParts = [];
  String? _splitError;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _pagesCtrl.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // File picking
  // ---------------------------------------------------------------------------

  Future<void> _pickMergeFiles() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
      allowMultiple: true,
    );
    if (result == null || !mounted) return;

    // Deduplicate by path.
    final existingPaths = _mergeFiles.map((f) => f.path).toSet();
    final added = result.files
        .where((f) => f.path != null && !existingPaths.contains(f.path))
        .toList();

    setState(() {
      _mergeFiles.addAll(added);
      _mergedPath = null;
      _mergeError = null;
    });
  }

  Future<void> _pickSplitFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
    );
    if (result == null || !mounted) return;
    setState(() {
      _splitFile = result.files.first;
      _splitParts = [];
      _splitError = null;
    });
  }

  // ---------------------------------------------------------------------------
  // Merge action
  // ---------------------------------------------------------------------------

  Future<void> _runMerge() async {
    if (_mergeFiles.length < 2) {
      setState(() => _mergeError = 'Select at least two PDF files to merge.');
      return;
    }

    final paths = _mergeFiles.map((f) => f.path!).toList();

    setState(() {
      _merging = true;
      _mergedPath = null;
      _mergeError = null;
    });

    try {
      final dir = await getTemporaryDirectory();
      final outPath = p.join(
        dir.path,
        'merged_${DateTime.now().millisecondsSinceEpoch}.pdf',
      );

      final merged = await PdfMergeService.merge(
        inputPaths: paths,
        outputPath: outPath,
      );

      if (mounted) {
        setState(() => _mergedPath = merged);
        _showSnackBar('Merged successfully', isError: false);
      }
    } on PdfMergeFileNotFoundException catch (e) {
      if (mounted) {
        setState(() => _mergeError = 'File not found: ${p.basename(e.missingPath)}');
      }
    } on PdfMergeCorruptFileException catch (e) {
      if (mounted) {
        setState(() =>
        _mergeError = 'Corrupt or password-protected PDF: ${p.basename(e.corruptPath)}');
      }
    } on PdfMergeException catch (e) {
      if (mounted) setState(() => _mergeError = e.message);
    } catch (e) {
      if (mounted) setState(() => _mergeError = e.toString());
    } finally {
      if (mounted) setState(() => _merging = false);
    }
  }

  // ---------------------------------------------------------------------------
  // Split action
  // ---------------------------------------------------------------------------

  Future<void> _runSplit() async {
    if (_splitFile == null || _splitFile!.path == null) {
      setState(() => _splitError = 'Select a PDF to split.');
      return;
    }

    final pagesPerFile = int.tryParse(_pagesCtrl.text.trim());
    if (pagesPerFile == null || pagesPerFile < 1) {
      setState(() => _splitError = 'Enter a valid number of pages per chunk.');
      return;
    }

    setState(() {
      _splitting = true;
      _splitParts = [];
      _splitError = null;
    });

    try {
      final dir = await getTemporaryDirectory();
      final parts = await PdfSplitService.split(
        pdfPath: _splitFile!.path!,
        pagesPerFile: pagesPerFile,
        outputDir: dir.path,
        baseFileName:
        p.basenameWithoutExtension(_splitFile!.name).replaceAll(' ', '_'),
      );

      if (mounted) {
        setState(() => _splitParts = parts);
        _showSnackBar(
          'Split into ${parts.length} file${parts.length == 1 ? '' : 's'}',
          isError: false,
        );
      }
    } on PdfSplitFileNotFoundException catch (e) {
      if (mounted) setState(() => _splitError = 'File not found: $e');
    } on PdfSplitInvalidRangeException catch (e) {
      if (mounted) {
        setState(() => _splitError = 'Invalid range: ${e.message}');
      }
    } on PdfSplitException catch (e) {
      if (mounted) setState(() => _splitError = e.message);
    } catch (e) {
      if (mounted) setState(() => _splitError = e.toString());
    } finally {
      if (mounted) setState(() => _splitting = false);
    }
  }

  // ---------------------------------------------------------------------------
  // Navigation helpers
  // ---------------------------------------------------------------------------

  void _openPdf(String path, String title) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => _PdfFileViewer(filePath: path, title: title),
    ));
  }

  void _showSnackBar(String message, {required bool isError}) {
    if (!mounted) return;
    final cs = Theme.of(context).colorScheme;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message),
      backgroundColor: isError ? cs.error : cs.primary,
    ));
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('PDF Operations'),
        backgroundColor: cs.primaryContainer,
        foregroundColor: cs.onPrimaryContainer,
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(icon: Icon(Icons.merge_type_rounded), text: 'Merge'),
            Tab(icon: Icon(Icons.call_split_rounded), text: 'Split'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildMergeTab(),
          _buildSplitTab(),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Merge tab
  // ---------------------------------------------------------------------------

  Widget _buildMergeTab() {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Info
          _InfoCard(
            icon: Icons.merge_type_rounded,
            title: 'Merge PDFs',
            body: 'Select two or more PDF files from your device. '
                'They will be combined into a single PDF in the order shown.',
          ),
          const SizedBox(height: 20),

          // File list
          if (_mergeFiles.isNotEmpty) ...[
            Text('Selected files (${_mergeFiles.length})',
                style: tt.labelMedium
                    ?.copyWith(color: cs.onSurfaceVariant)),
            const SizedBox(height: 8),
            ..._mergeFiles.asMap().entries.map((entry) {
              final idx = entry.key;
              final file = entry.value;
              return Card(
                elevation: 0,
                margin: const EdgeInsets.only(bottom: 6),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                  side: BorderSide(color: cs.outlineVariant),
                ),
                child: ListTile(
                  dense: true,
                  leading: CircleAvatar(
                    radius: 14,
                    backgroundColor: cs.secondaryContainer,
                    foregroundColor: cs.onSecondaryContainer,
                    child: Text('${idx + 1}',
                        style: const TextStyle(fontSize: 11)),
                  ),
                  title: Text(file.name,
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text(_fileSizeLabel(file.size)),
                  trailing: IconButton(
                    icon: const Icon(Icons.close_rounded, size: 18),
                    tooltip: 'Remove',
                    onPressed: () => setState(() {
                      _mergeFiles.removeAt(idx);
                      _mergedPath = null;
                      _mergeError = null;
                    }),
                  ),
                ),
              );
            }),
            const SizedBox(height: 12),
          ],

          // Add files button
          OutlinedButton.icon(
            onPressed: _merging ? null : _pickMergeFiles,
            icon: const Icon(Icons.add_rounded),
            label: Text(_mergeFiles.isEmpty ? 'Select PDFs' : 'Add more PDFs'),
          ),
          const SizedBox(height: 12),

          // Merge button
          FilledButton.icon(
            onPressed: (_merging || _mergeFiles.length < 2) ? null : _runMerge,
            icon: _merging
                ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
                : const Icon(Icons.merge_type_rounded),
            label: Text(_merging ? 'Merging…' : 'Merge PDFs'),
          ),
          const SizedBox(height: 24),

          // Error / result
          if (_mergeError != null)
            _ErrorBanner(message: _mergeError!)
          else if (_mergedPath != null)
            _ResultCard(
              icon: Icons.picture_as_pdf_rounded,
              title: p.basename(_mergedPath!),
              subtitle: _mergedPath!,
              actionLabel: 'Open merged PDF',
              onAction: () => _openPdf(_mergedPath!, 'Merged PDF'),
            ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Split tab
  // ---------------------------------------------------------------------------

  Widget _buildSplitTab() {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Info
          _InfoCard(
            icon: Icons.call_split_rounded,
            title: 'Split PDF',
            body: 'Select a PDF and enter how many pages each chunk should '
                'contain. The last chunk may be shorter.',
          ),
          const SizedBox(height: 20),

          // Selected file
          if (_splitFile != null)
            Card(
              elevation: 0,
              margin: const EdgeInsets.only(bottom: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
                side: BorderSide(color: cs.outlineVariant),
              ),
              child: ListTile(
                leading: Icon(Icons.picture_as_pdf_rounded,
                    color: cs.primary),
                title: Text(_splitFile!.name,
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text(_fileSizeLabel(_splitFile!.size)),
                trailing: IconButton(
                  icon: const Icon(Icons.close_rounded, size: 18),
                  tooltip: 'Clear',
                  onPressed: () => setState(() {
                    _splitFile = null;
                    _splitParts = [];
                    _splitError = null;
                  }),
                ),
              ),
            ),

          // Pick file
          OutlinedButton.icon(
            onPressed: _splitting ? null : _pickSplitFile,
            icon: const Icon(Icons.upload_file_rounded),
            label: Text(_splitFile == null ? 'Select PDF' : 'Change PDF'),
          ),
          const SizedBox(height: 16),

          // Pages per chunk
          TextField(
            controller: _pagesCtrl,
            enabled: !_splitting,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Pages per chunk',
              hintText: 'e.g. 5',
              border: OutlineInputBorder(),
              suffixText: 'pages',
            ),
            onChanged: (_) => setState(() {
              _splitParts = [];
              _splitError = null;
            }),
          ),
          const SizedBox(height: 16),

          // Split button
          FilledButton.icon(
            onPressed: (_splitting || _splitFile == null) ? null : _runSplit,
            icon: _splitting
                ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
                : const Icon(Icons.call_split_rounded),
            label: Text(_splitting ? 'Splitting…' : 'Split PDF'),
          ),
          const SizedBox(height: 24),

          // Error
          if (_splitError != null) _ErrorBanner(message: _splitError!),

          // Parts list
          if (_splitParts.isNotEmpty) ...[
            Text(
              '${_splitParts.length} part${_splitParts.length == 1 ? '' : 's'} generated',
              style: tt.labelMedium?.copyWith(color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 12),
            ..._splitParts.asMap().entries.map((entry) {
              final name = p.basename(entry.value);
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _ResultCard(
                  icon: Icons.description_outlined,
                  title: name,
                  subtitle: entry.value,
                  actionLabel: 'Open',
                  onAction: () => _openPdf(entry.value, name),
                ),
              );
            }),
          ],
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  static String _fileSizeLabel(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}

// ---------------------------------------------------------------------------
// Shared sub-widgets
// ---------------------------------------------------------------------------

class _InfoCard extends StatelessWidget {
  const _InfoCard({
    required this.icon,
    required this.title,
    required this.body,
  });
  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Card(
      elevation: 0,
      color: cs.secondaryContainer,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: cs.onSecondaryContainer, size: 28),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: tt.titleSmall
                          ?.copyWith(color: cs.onSecondaryContainer)),
                  const SizedBox(height: 8),
                  Text(body,
                      style: tt.bodySmall
                          ?.copyWith(color: cs.onSecondaryContainer)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ResultCard extends StatelessWidget {
  const _ResultCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.actionLabel,
    required this.onAction,
  });
  final IconData icon;
  final String title;
  final String subtitle;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: cs.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            CircleAvatar(
              backgroundColor: cs.primaryContainer,
              foregroundColor: cs.onPrimaryContainer,
              child: Icon(icon),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: tt.bodyLarge
                          ?.copyWith(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style:
                    tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            FilledButton.tonal(
              onPressed: onAction,
              child: Text(actionLabel),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(16),
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: cs.errorContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline_rounded, color: cs.onErrorContainer),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: cs.onErrorContainer),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Inline PDF viewer for generated files
// ---------------------------------------------------------------------------

class _PdfFileViewer extends StatelessWidget {
  const _PdfFileViewer({required this.filePath, required this.title});
  final String filePath;
  final String title;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(title, overflow: TextOverflow.ellipsis),
        backgroundColor: cs.primaryContainer,
        foregroundColor: cs.onPrimaryContainer,
      ),
      body: AlhPdfView(
        filePath: filePath,
        swipeHorizontal: true,
        enableDoubleTap: true,
        backgroundColor: cs.surface,
        onError: (err) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('PDF error: $err'),
            backgroundColor: cs.error,
          ));
        },
      ),
    );
  }
}