import 'package:flutter/material.dart';
import 'package:pdf_reading_tracker/pdf_reading_tracker.dart';

import '../models/pdf_document.dart';
import 'pdf_operations_screen.dart';
import 'pdf_reader_screen.dart';

/// Landing screen — presents the PDF catalogue plus a button to the
/// PDF Operations screen (merge & split demo).
class PdfSelectionScreen extends StatefulWidget {
  const PdfSelectionScreen({super.key});

  @override
  State<PdfSelectionScreen> createState() => _PdfSelectionScreenState();
}

class _PdfSelectionScreenState extends State<PdfSelectionScreen> {
  final Map<String, ReadingProgress?> _progressMap = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadAllProgress();
  }

  Future<void> _loadAllProgress() async {
    final results = await Future.wait(
      kPdfCatalogue.map((doc) async {
        final progress = await PdfReadingTracker.getProgress(doc.id);
        return MapEntry(doc.id, progress);
      }),
    );
    if (!mounted) return;
    setState(() {
      _progressMap
        ..clear()
        ..addEntries(results);
      _loading = false;
    });
  }

  Future<void> _openDocument(PdfDocument document) async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => PdfReaderScreen(document: document)),
    );
    await _loadAllProgress();
  }

  void _openOperations() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const PdfOperationsScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('PDF Reading Tracker'),
        centerTitle: true,
        backgroundColor: cs.primaryContainer,
        foregroundColor: cs.onPrimaryContainer,
        actions: [
          IconButton(
            icon: const Icon(Icons.build_rounded),
            tooltip: 'PDF Operations (Merge & Split)',
            onPressed: _openOperations,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: kPdfCatalogue.length + 1, // +1 for operations card
        itemBuilder: (context, index) {
          // ── Operations card (first item) ──────────────────────────
          if (index == 0) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: _OperationsCard(onTap: _openOperations),
            );
          }
          final doc = kPdfCatalogue[index - 1];
          final progress = _progressMap[doc.id];
          return _PdfDocumentCard(
            document: doc,
            progress: progress,
            onTap: () => _openDocument(doc),
          );
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Operations promo card
// ---------------------------------------------------------------------------

class _OperationsCard extends StatelessWidget {
  const _OperationsCard({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Card(
      elevation: 0,
      color: cs.tertiaryContainer,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              CircleAvatar(
                backgroundColor: cs.tertiary,
                foregroundColor: cs.onTertiary,
                child: const Icon(Icons.build_rounded),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('PDF Operations',
                        style: tt.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: cs.onTertiaryContainer)),
                    const SizedBox(height: 4),
                    Text('Merge & Split PDFs',
                        style: tt.bodySmall
                            ?.copyWith(color: cs.onTertiaryContainer)),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded,
                  color: cs.onTertiaryContainer),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Document card (unchanged from original)
// ---------------------------------------------------------------------------

class _PdfDocumentCard extends StatelessWidget {
  const _PdfDocumentCard({
    required this.document,
    required this.progress,
    required this.onTap,
  });

  final PdfDocument document;
  final ReadingProgress? progress;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final hasProgress = progress != null && progress!.totalPages > 0;
    final pct =
    hasProgress ? (progress!.progressPct).toStringAsFixed(1) : null;

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: cs.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    backgroundColor: cs.secondaryContainer,
                    foregroundColor: cs.onSecondaryContainer,
                    child: const Icon(Icons.picture_as_pdf_rounded),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(document.title,
                            style: tt.titleMedium
                                ?.copyWith(fontWeight: FontWeight.bold)),
                        const SizedBox(height: 2),
                        Text(document.subtitle,
                            style: tt.bodySmall
                                ?.copyWith(color: cs.onSurfaceVariant),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis),
                      ],
                    ),
                  ),
                  Icon(Icons.chevron_right_rounded,
                      color: cs.onSurfaceVariant),
                ],
              ),
              if (hasProgress) ...[
                const SizedBox(height: 16),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: progress!.progressPct / 100,
                    backgroundColor: cs.surfaceContainerHighest,
                    valueColor: AlwaysStoppedAnimation<Color>(cs.primary),
                    minHeight: 5,
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                        'Page ${progress!.currentPage + 1} of ${progress!.totalPages}',
                        style: tt.bodySmall
                            ?.copyWith(color: cs.onSurfaceVariant)),
                    Text('$pct% read',
                        style: tt.bodySmall?.copyWith(
                            color: cs.primary,
                            fontWeight: FontWeight.w600)),
                  ],
                ),
              ] else ...[
                const SizedBox(height: 12),
                Text('Not started',
                    style: tt.bodySmall?.copyWith(color: cs.outline)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}