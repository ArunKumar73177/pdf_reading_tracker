import 'dart:io';

import 'package:flutter/material.dart';
import 'package:pdf_reading_tracker/pdf_reading_tracker.dart';

import 'pdf_operations_screen.dart';
import 'recent_pdfs_screen.dart';

// ---------------------------------------------------------------------------
// Landing screen — v2.1.0
//
// No static catalogue. All PDFs come from:
//   • The device file picker (FAB → "Open PDF")
//   • The "Recent PDFs" history (SQLite via getRecentlyRead)
//
// Sections:
//   1. Continue Reading  — in-progress (0 < progress < 100 %)
//   2. Recent PDFs       — all opened PDFs, most-recent first
// ---------------------------------------------------------------------------

class PdfSelectionScreen extends StatefulWidget {
  const PdfSelectionScreen({super.key});

  @override
  State<PdfSelectionScreen> createState() => _PdfSelectionScreenState();
}

class _PdfSelectionScreenState extends State<PdfSelectionScreen> {
  List<ReadingProgress> _recentlyRead = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  // ---------------------------------------------------------------------------
  // Data loading
  // ---------------------------------------------------------------------------

  Future<void> _refresh() async {
    setState(() => _loading = true);
    try {
      final recents = await PdfReadingTracker.getRecentlyRead(limit: 30);
      if (!mounted) return;
      setState(() {
        _recentlyRead = recents;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ---------------------------------------------------------------------------
  // Navigation
  // ---------------------------------------------------------------------------

  Future<void> _openRecentProgress(ReadingProgress progress) async {
    if (progress.filePath == null) return; // should not happen in picker-first

    if (!File(progress.filePath!).existsSync()) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
          '"${progress.title ?? 'PDF'}" could not be found. '
              'It may have been moved or deleted.',
        ),
        backgroundColor: Theme.of(context).colorScheme.error,
      ));
      return;
    }

    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => Scaffold(
        body: PdfReadingTrackerViewer(
          pdfId: progress.pdfId,
          pdfTitle: progress.title ?? 'PDF',
          filePath: progress.filePath,
        ),
      ),
    ));
    await _refresh();
  }

  Future<void> _pickAndOpenPdf() async {
    try {
      final picked = await PdfPickerService.pickPdf();
      if (picked == null || !mounted) return;

      await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => Scaffold(
          body: PdfReadingTrackerViewer(
            pdfId: picked.pdfId,
            pdfTitle: picked.title,
            filePath: picked.filePath,
          ),
        ),
      ));
      await _refresh();
    } on PdfPickerException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(e.message),
        backgroundColor: Theme.of(context).colorScheme.error,
      ));
    }
  }

  void _openOperations() => Navigator.of(context).push(
    MaterialPageRoute(builder: (_) => const PdfOperationsScreen()),
  );

  void _openRecentScreen() => Navigator.of(context)
      .push(MaterialPageRoute(builder: (_) => const RecentPdfsScreen()))
      .then((_) => _refresh());

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final continueReading = _recentlyRead
        .where((p) => p.currentPage > 0 && p.progressPct < 100.0)
        .toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('PDF Reading Tracker'),
        centerTitle: true,
        backgroundColor: cs.primaryContainer,
        foregroundColor: cs.onPrimaryContainer,
        actions: [
          IconButton(
            icon: const Icon(Icons.history_rounded),
            tooltip: 'All recent PDFs',
            onPressed: _openRecentScreen,
          ),
          IconButton(
            icon: const Icon(Icons.build_rounded),
            tooltip: 'PDF Operations (merge / split)',
            onPressed: _openOperations,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
        onRefresh: _refresh,
        child: _recentlyRead.isEmpty
            ? _EmptyState(onPick: _pickAndOpenPdf)
            : ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // ── Continue Reading ──────────────────────────────
            if (continueReading.isNotEmpty) ...[
              _SectionHeader(
                icon: Icons.play_circle_outline_rounded,
                label: 'Continue reading',
              ),
              const SizedBox(height: 8),
              ...continueReading.map((p) => _PdfCard(
                progress: p,
                onTap: () => _openRecentProgress(p),
              )),
              const SizedBox(height: 24),
            ],

            // ── Recent PDFs ───────────────────────────────────
            _SectionHeader(
              icon: Icons.history_rounded,
              label: 'Recent PDFs',
            ),
            const SizedBox(height: 8),
            ..._recentlyRead.map((p) => _PdfCard(
              progress: p,
              onTap: () => _openRecentProgress(p),
            )),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _pickAndOpenPdf,
        icon: const Icon(Icons.upload_file_rounded),
        label: const Text('Open PDF'),
        tooltip: 'Pick a PDF from your device',
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Empty state
// ---------------------------------------------------------------------------

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onPick});
  final VoidCallback onPick;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.picture_as_pdf_rounded,
                size: 72, color: cs.onSurfaceVariant.withAlpha(102)),
            const SizedBox(height: 24),
            Text('No PDFs yet',
                style: tt.titleLarge?.copyWith(color: cs.onSurfaceVariant)),
            const SizedBox(height: 10),
            Text(
              'Tap "Open PDF" to pick a PDF from your device.\n'
                  'Your reading progress and bookmarks are saved automatically.',
              textAlign: TextAlign.center,
              style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 32),
            FilledButton.icon(
              onPressed: onPick,
              icon: const Icon(Icons.upload_file_rounded),
              label: const Text('Open PDF'),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Section header
// ---------------------------------------------------------------------------

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Row(
      children: [
        Icon(icon, size: 18, color: cs.primary),
        const SizedBox(width: 8),
        Text(
          label,
          style: tt.titleSmall?.copyWith(
            color: cs.primary,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.5,
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// PDF card  (ReadingProgress-based)
// ---------------------------------------------------------------------------

class _PdfCard extends StatelessWidget {
  const _PdfCard({required this.progress, required this.onTap});
  final ReadingProgress progress;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final fileExists = progress.filePath == null ||
        File(progress.filePath!).existsSync();
    final title = progress.title ?? 'Unknown PDF';
    final pct = progress.progressPct.toStringAsFixed(1);

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: fileExists ? cs.outlineVariant : cs.errorContainer,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: fileExists ? onTap : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              // Icon
              CircleAvatar(
                backgroundColor: fileExists
                    ? cs.secondaryContainer
                    : cs.errorContainer,
                foregroundColor: fileExists
                    ? cs.onSecondaryContainer
                    : cs.onErrorContainer,
                child: const Icon(Icons.upload_file_rounded),
              ),
              const SizedBox(width: 14),
              // Text
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: tt.bodyLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: fileExists ? null : cs.onSurfaceVariant,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    if (progress.totalPages > 0)
                      Text(
                        'Page ${progress.currentPage + 1} of '
                            '${progress.totalPages}  ·  $pct%',
                        style: tt.bodySmall
                            ?.copyWith(color: cs.onSurfaceVariant),
                      ),
                    if (!fileExists)
                      Text(
                        'File not found',
                        style: tt.bodySmall?.copyWith(color: cs.error),
                      ),
                  ],
                ),
              ),
              // Progress ring
              if (progress.totalPages > 0 && fileExists)
                SizedBox(
                  width: 36,
                  height: 36,
                  child: CircularProgressIndicator(
                    value: progress.progressPct / 100,
                    strokeWidth: 3,
                    backgroundColor: cs.surfaceContainerHighest,
                    valueColor:
                    AlwaysStoppedAnimation<Color>(cs.primary),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}