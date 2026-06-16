import 'dart:io';

import 'package:flutter/material.dart';
import 'package:pdf_reading_tracker/pdf_reading_tracker.dart';

import 'pdf_operations_screen.dart';
import 'recent_pdfs_screen.dart';

// ---------------------------------------------------------------------------
// PdfSelectionScreen — v2.2.0
//
// **v2.2.0 changes — Improvement 5 (Continue Reading dashboard)**
//
// The "Continue Reading" section now shows the top 3 in-progress PDFs in
// dedicated _ContinueCard widgets that feature:
//   • A large (56 px) circular progress ring as the visual anchor.
//   • Title (bold) + "X of Y pages · Z%" metadata line.
//   • A prominent "Continue" action button.
//   • A "See all" link that pushes RecentPdfsScreen.
//
// The Recent PDFs section retains its existing flat-card design with the
// enhanced _PdfCard used for all other entries.
//
// **v2.1.1 changes (preserved)**
// - `continueReading` filter changed from `currentPage > 0` to
//   `progressPct > 0.0` so PDFs opened at page 1 (index 0) are included.
// - File-existence check uses the persistent ApplicationDocuments path.
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

  Future<void> _openRecentProgress(ReadingProgress progress) async {
    if (progress.filePath == null) return;
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

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    // In-progress PDFs (0 < pct < 100, totalPages known), sorted newest first
    // (already ordered by lastReadAt DESC from getRecentlyRead).
    final continueReading = _recentlyRead
        .where((p) =>
    p.totalPages > 0 && p.progressPct > 0.0 && p.progressPct < 100.0)
        .toList();

    // Top 3 for the dashboard strip.
    final topContinue = continueReading.take(3).toList();

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
            // ── Continue Reading dashboard ──────────────────
            if (topContinue.isNotEmpty) ...[
              _DashboardHeader(
                icon: Icons.play_circle_outline_rounded,
                label: 'Continue reading',
                showSeeAll: continueReading.length > 3,
                onSeeAll: _openRecentScreen,
              ),
              const SizedBox(height: 12),
              ...topContinue.map((p) => _ContinueCard(
                progress: p,
                onTap: () => _openRecentProgress(p),
              )),
              const SizedBox(height: 28),
            ],

            // ── Recent PDFs list ────────────────────────────
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
// Continue Reading dashboard card — Improvement 5
// ---------------------------------------------------------------------------

class _ContinueCard extends StatelessWidget {
  const _ContinueCard({required this.progress, required this.onTap});

  final ReadingProgress progress;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final pct = progress.progressPct;

    return Card(
      elevation: 0,
      color: cs.surfaceContainerLow,
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: cs.outlineVariant, width: 0.8),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              // ── Circular progress ring ─────────────────────────────────
              SizedBox(
                width: 56,
                height: 56,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    CircularProgressIndicator(
                      value: pct / 100.0,
                      strokeWidth: 4.5,
                      backgroundColor: cs.surfaceContainerHighest,
                      valueColor: AlwaysStoppedAnimation<Color>(cs.primary),
                      strokeCap: StrokeCap.round,
                    ),
                    Center(
                      child: Text(
                        '${pct.toStringAsFixed(0)}%',
                        style: tt.labelSmall?.copyWith(
                          color: cs.primary,
                          fontWeight: FontWeight.w700,
                          fontSize: 10,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(width: 14),

              // ── Text block ─────────────────────────────────────────────
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      progress.title ?? 'Unknown PDF',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: tt.bodyLarge
                          ?.copyWith(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'Page ${progress.currentPage + 1} of '
                          '${progress.totalPages}',
                      style: tt.bodySmall
                          ?.copyWith(color: cs.onSurfaceVariant),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _relativeTime(progress.lastReadAt),
                      style: tt.bodySmall?.copyWith(
                          color: cs.onSurfaceVariant.withAlpha(180),
                          fontSize: 11),
                    ),
                  ],
                ),
              ),

              const SizedBox(width: 8),

              // ── Continue button ────────────────────────────────────────
              FilledButton.tonal(
                onPressed: onTap,
                style: FilledButton.styleFrom(
                  padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 0),
                  minimumSize: const Size(0, 34),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.play_arrow_rounded, size: 16),
                    SizedBox(width: 4),
                    Text('Continue', style: TextStyle(fontSize: 13)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _relativeTime(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inSeconds < 60) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays == 1) return 'Yesterday';
    if (diff.inDays < 7) return '${diff.inDays} days ago';
    const months = [
      '', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${dt.day} ${months[dt.month]}';
  }
}

// ---------------------------------------------------------------------------
// Dashboard header (section title + optional "See all" link)
// ---------------------------------------------------------------------------

class _DashboardHeader extends StatelessWidget {
  const _DashboardHeader({
    required this.icon,
    required this.label,
    this.showSeeAll = false,
    this.onSeeAll,
  });

  final IconData icon;
  final String label;
  final bool showSeeAll;
  final VoidCallback? onSeeAll;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Row(
      children: [
        Icon(icon, size: 18, color: cs.primary),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            label,
            style: tt.titleSmall?.copyWith(
              color: cs.primary,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.4,
            ),
          ),
        ),
        if (showSeeAll)
          TextButton(
            onPressed: onSeeAll,
            style: TextButton.styleFrom(
              padding:
              const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
              minimumSize: const Size(0, 28),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: const Text('See all'),
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Plain section header (no "see all")
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
// PDF card (Recent PDFs section — unchanged design, v2.1.1 logic)
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
              CircleAvatar(
                backgroundColor:
                fileExists ? cs.secondaryContainer : cs.errorContainer,
                foregroundColor: fileExists
                    ? cs.onSecondaryContainer
                    : cs.onErrorContainer,
                child: const Icon(Icons.upload_file_rounded),
              ),
              const SizedBox(width: 14),
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
                      Text('File not found',
                          style: tt.bodySmall?.copyWith(color: cs.error)),
                  ],
                ),
              ),
              if (progress.totalPages > 0 && fileExists)
                SizedBox(
                  width: 36,
                  height: 36,
                  child: CircularProgressIndicator(
                    value: progress.progressPct / 100,
                    strokeWidth: 3,
                    backgroundColor: cs.surfaceContainerHighest,
                    valueColor: AlwaysStoppedAnimation<Color>(cs.primary),
                  ),
                ),
            ],
          ),
        ),
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
                size: 72, color: cs.onSurfaceVariant.withAlpha(100)),
            const SizedBox(height: 24),
            Text('No PDFs yet',
                style:
                tt.titleLarge?.copyWith(color: cs.onSurfaceVariant)),
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