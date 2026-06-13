import 'dart:io';

import 'package:alh_pdf_view/alh_pdf_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf_reading_tracker/pdf_reading_tracker.dart';

// ---------------------------------------------------------------------------
// PDF Operations Screen
// ---------------------------------------------------------------------------

/// Demonstrates [PdfMergeService] and [PdfSplitService] in the example app.
///
/// ### Merge workflow
///   sample.pdf + sample2.pdf  →  merged.pdf  →  opens in ALH PDF View
///
/// ### Split workflow
///   sample.pdf  →  split every 5 pages  →  lists part_1.pdf … part_N.pdf
///   Tap any part to open it in ALH PDF View
class PdfOperationsScreen extends StatefulWidget {
  const PdfOperationsScreen({super.key});

  @override
  State<PdfOperationsScreen> createState() => _PdfOperationsScreenState();
}

class _PdfOperationsScreenState extends State<PdfOperationsScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  // ── Merge state ─────────────────────────────────────────────────────────────
  bool _merging = false;
  String? _mergedPath;
  String? _mergeError;

  // ── Split state ─────────────────────────────────────────────────────────────
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
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Asset extraction helper
  // ---------------------------------------------------------------------------

  /// Copies a Flutter asset to a writable temp file and returns its path.
  ///
  /// Both [PdfMergeService] and [PdfSplitService] operate on file-system paths;
  /// Flutter assets must be extracted first.
  Future<String> _extractAsset(String assetPath, String fileName) async {
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/$fileName');
    if (!file.existsSync()) {
      final data = await rootBundle.load(assetPath);
      await file.writeAsBytes(
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
      );
    }
    return file.path;
  }

  // ---------------------------------------------------------------------------
  // Merge action
  // ---------------------------------------------------------------------------

  Future<void> _runMerge() async {
    setState(() {
      _merging = true;
      _mergedPath = null;
      _mergeError = null;
    });

    try {
      // Extract both sample assets to disk so the merge service can read them.
      final path1 = await _extractAsset('assets/sample.pdf', 'op_sample1.pdf');
      final path2 =
      await _extractAsset('assets/sample2.pdf', 'op_sample2.pdf');

      final dir = await getTemporaryDirectory();
      final outPath = '${dir.path}/merged.pdf';

      final merged = await PdfMergeService.merge(
        inputPaths: [path1, path2],
        outputPath: outPath,
      );

      if (mounted) {
        setState(() => _mergedPath = merged);
        _showSnackBar('✓ Merged successfully', isError: false);
      }
    } on PdfMergeFileNotFoundException catch (e) {
      if (mounted) setState(() => _mergeError = 'File not found: ${e.missingPath}');
    } on PdfMergeCorruptFileException catch (e) {
      if (mounted) setState(() => _mergeError = 'Corrupt PDF: ${e.corruptPath}');
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
    setState(() {
      _splitting = true;
      _splitParts = [];
      _splitError = null;
    });

    try {
      final sourcePath =
      await _extractAsset('assets/sample.pdf', 'op_sample_split.pdf');

      final parts = await PdfSplitService.split(
        pdfPath: sourcePath,
        pagesPerFile: 5,
        baseFileName: 'sample',
      );

      if (mounted) {
        setState(() => _splitParts = parts);
        _showSnackBar('✓ Split into ${parts.length} file(s)', isError: false);
      }
    } on PdfSplitFileNotFoundException catch (e) {
      if (mounted) setState(() => _splitError = 'File not found: $e');
    } on PdfSplitInvalidRangeException catch (e) {
      if (mounted) setState(() => _splitError = 'Invalid range: ${e.message}');
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

  void _openPdf(BuildContext context, String path, String title) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _PdfFileViewer(filePath: path, title: title),
      ),
    );
  }

  void _showSnackBar(String message, {required bool isError}) {
    if (!mounted) return;
    final cs = Theme.of(context).colorScheme;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? cs.error : cs.primary,
        duration: const Duration(seconds: 3),
      ),
    );
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
          _MergeTab(
            merging: _merging,
            mergedPath: _mergedPath,
            error: _mergeError,
            onMerge: _runMerge,
            onOpen: (path) => _openPdf(context, path, 'merged.pdf'),
          ),
          _SplitTab(
            splitting: _splitting,
            parts: _splitParts,
            error: _splitError,
            onSplit: _runSplit,
            onOpenPart: (path, name) => _openPdf(context, path, name),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Merge tab widget
// ---------------------------------------------------------------------------

class _MergeTab extends StatelessWidget {
  const _MergeTab({
    required this.merging,
    required this.mergedPath,
    required this.error,
    required this.onMerge,
    required this.onOpen,
  });

  final bool merging;
  final String? mergedPath;
  final String? error;
  final VoidCallback onMerge;
  final void Function(String path) onOpen;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Info card ──────────────────────────────────────────────────────
          _InfoCard(
            icon: Icons.merge_type_rounded,
            title: 'Merge two PDFs',
            body:
            'Combines sample.pdf + sample2.pdf into a single merged.pdf '
                'using PdfMergeService.\n\n'
                'Uses createTemplate() + drawPdfTemplate() — the correct '
                'Syncfusion Flutter API for copying page content.',
          ),
          const SizedBox(height: 24),

          // ── Merge button ───────────────────────────────────────────────────
          FilledButton.icon(
            onPressed: merging ? null : onMerge,
            icon: merging
                ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
                : const Icon(Icons.merge_type_rounded),
            label: Text(merging ? 'Merging…' : 'Merge PDFs'),
          ),
          const SizedBox(height: 24),

          // ── Result ─────────────────────────────────────────────────────────
          if (error != null)
            _ErrorBanner(message: error!)
          else if (mergedPath != null)
            _ResultCard(
              icon: Icons.picture_as_pdf_rounded,
              title: 'merged.pdf',
              subtitle: mergedPath!,
              actionLabel: 'Open merged PDF',
              onAction: () => onOpen(mergedPath!),
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Split tab widget
// ---------------------------------------------------------------------------

class _SplitTab extends StatelessWidget {
  const _SplitTab({
    required this.splitting,
    required this.parts,
    required this.error,
    required this.onSplit,
    required this.onOpenPart,
  });

  final bool splitting;
  final List<String> parts;
  final String? error;
  final VoidCallback onSplit;
  final void Function(String path, String name) onOpenPart;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Info card ──────────────────────────────────────────────────────
          _InfoCard(
            icon: Icons.call_split_rounded,
            title: 'Split a PDF',
            body:
            'Splits sample.pdf into chunks of 5 pages each using '
                'PdfSplitService.\n\n'
                'Generates sample_part_1.pdf, sample_part_2.pdf, … '
                'Tap any part to open it.',
          ),
          const SizedBox(height: 24),

          // ── Split button ───────────────────────────────────────────────────
          FilledButton.icon(
            onPressed: splitting ? null : onSplit,
            icon: splitting
                ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
                : const Icon(Icons.call_split_rounded),
            label: Text(splitting ? 'Splitting…' : 'Split PDF (5 pages each)'),
          ),
          const SizedBox(height: 24),

          // ── Error ──────────────────────────────────────────────────────────
          if (error != null) _ErrorBanner(message: error!),

          // ── Parts list ─────────────────────────────────────────────────────
          if (parts.isNotEmpty) ...[
            Text(
              '${parts.length} part(s) generated',
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            ...parts.asMap().entries.map((entry) {
              final idx = entry.key;
              final path = entry.value;
              final name = 'sample_part_${idx + 1}.pdf';
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _ResultCard(
                  icon: Icons.description_outlined,
                  title: name,
                  subtitle: path,
                  actionLabel: 'Open',
                  onAction: () => onOpenPart(path, name),
                ),
              );
            }),
          ],
        ],
      ),
    );
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
                    style: tt.bodySmall
                        ?.copyWith(color: cs.onSurfaceVariant),
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
// Inline PDF viewer for generated files (uses ALH PDF View on a file path)
// ---------------------------------------------------------------------------

/// Opens a file-system PDF directly — used for generated merge/split outputs.
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
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('PDF error: $err'),
              backgroundColor: cs.error,
            ),
          );
        },
      ),
    );
  }
}