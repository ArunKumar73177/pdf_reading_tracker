import 'dart:io';

import 'package:flutter/material.dart';
import 'package:pdf_reading_tracker/pdf_reading_tracker.dart';

// ---------------------------------------------------------------------------
// RecentPdfsScreen
//
// Shows all PDFs the user has opened, ordered by last-read timestamp.
// Each card shows:
//   • PDF title
//   • Last read: "X minutes ago / yesterday / dd MMM yyyy"
//   • Page X of Y  ·  progress %
//   • "Resume" button (opens viewer directly)
//   • "Delete history" icon (removes DB record)
//   • Greyed out + "File not found" badge when the on-device file is missing
// ---------------------------------------------------------------------------

class RecentPdfsScreen extends StatefulWidget {
  const RecentPdfsScreen({super.key});

  @override
  State<RecentPdfsScreen> createState() => _RecentPdfsScreenState();
}

class _RecentPdfsScreenState extends State<RecentPdfsScreen> {
  List<ReadingProgress> _recents = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final recents = await PdfReadingTracker.getRecentlyRead(limit: 100);
      if (mounted) setState(() { _recents = recents; _loading = false; });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openPdf(ReadingProgress p) async {
    if (p.filePath == null || !File(p.filePath!).existsSync()) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('"${p.title ?? 'PDF'}" could not be found on your device.'),
        backgroundColor: Theme.of(context).colorScheme.error,
      ));
      return;
    }
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => Scaffold(
        body: PdfReadingTrackerViewer(
          pdfId: p.pdfId,
          pdfTitle: p.title ?? 'PDF',
          filePath: p.filePath,
        ),
      ),
    ));
    await _load();
  }

  Future<void> _deleteHistory(ReadingProgress p) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove from history?'),
        content: Text(
          'Reading progress and bookmarks for '
              '"${p.title ?? 'this PDF'}" will be deleted.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    await PdfReadingTracker.deleteProgress(p.pdfId);
    await PdfReadingTracker.clearBookmarks(p.pdfId);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Reading history'),
        backgroundColor: cs.primaryContainer,
        foregroundColor: cs.onPrimaryContainer,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _recents.isEmpty
          ? _EmptyHistory()
          : RefreshIndicator(
        onRefresh: _load,
        child: ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: _recents.length,
          separatorBuilder: (_, __) => const SizedBox(height: 10),
          itemBuilder: (_, i) => _RecentCard(
            progress: _recents[i],
            onResume: () => _openPdf(_recents[i]),
            onDelete: () => _deleteHistory(_recents[i]),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Empty state
// ---------------------------------------------------------------------------

class _EmptyHistory extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.history_rounded,
              size: 64, color: cs.onSurfaceVariant.withAlpha(102)),
          const SizedBox(height: 16),
          Text('No history yet',
              style: tt.titleMedium?.copyWith(color: cs.onSurfaceVariant)),
          const SizedBox(height: 8),
          Text(
            'PDFs you open will appear here.',
            style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Recent card
// ---------------------------------------------------------------------------

class _RecentCard extends StatelessWidget {
  const _RecentCard({
    required this.progress,
    required this.onResume,
    required this.onDelete,
  });

  final ReadingProgress progress;
  final VoidCallback onResume;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final fileExists = progress.filePath == null ||
        File(progress.filePath!).existsSync();
    final title = progress.title ?? 'Unknown PDF';
    final pct = progress.progressPct.toStringAsFixed(1);

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: fileExists ? cs.outlineVariant : cs.errorContainer,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Header row ─────────────────────────────────────────────
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: fileExists
                      ? cs.secondaryContainer
                      : cs.errorContainer,
                  foregroundColor: fileExists
                      ? cs.onSecondaryContainer
                      : cs.onErrorContainer,
                  child: const Icon(Icons.picture_as_pdf_rounded),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: tt.bodyLarge?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: fileExists ? null : cs.onSurfaceVariant,
                        ),
                      ),
                      if (progress.lastReadAt != null)
                        Text(
                          _relativeTime(progress.lastReadAt!),
                          style: tt.bodySmall
                              ?.copyWith(color: cs.onSurfaceVariant),
                        ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline_rounded),
                  tooltip: 'Remove from history',
                  color: cs.onSurfaceVariant,
                  onPressed: onDelete,
                ),
              ],
            ),

            // ── Progress bar ───────────────────────────────────────────
            if (progress.totalPages > 0) ...[
              const SizedBox(height: 14),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: progress.progressPct / 100,
                  backgroundColor: cs.surfaceContainerHighest,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    fileExists ? cs.primary : cs.outline,
                  ),
                  minHeight: 5,
                ),
              ),
              const SizedBox(height: 6),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Page ${progress.currentPage + 1} of ${progress.totalPages}',
                    style: tt.bodySmall
                        ?.copyWith(color: cs.onSurfaceVariant),
                  ),
                  Text(
                    '$pct% read',
                    style: tt.bodySmall?.copyWith(
                      color: fileExists ? cs.primary : cs.outline,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ],

            // ── File-not-found badge ───────────────────────────────────
            if (!fileExists) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  Icon(Icons.warning_amber_rounded,
                      size: 14, color: cs.error),
                  const SizedBox(width: 4),
                  Text(
                    'File not found on device',
                    style: tt.bodySmall?.copyWith(color: cs.error),
                  ),
                ],
              ),
            ],

            // ── Resume button ──────────────────────────────────────────
            if (fileExists) ...[
              const SizedBox(height: 14),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton.tonal(
                  onPressed: onResume,
                  child: const Text('Resume'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// Human-readable relative time string.
  static String _relativeTime(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);

    if (diff.inSeconds < 60) return 'Just now';
    if (diff.inMinutes < 60) {
      final m = diff.inMinutes;
      return '$m ${m == 1 ? 'minute' : 'minutes'} ago';
    }
    if (diff.inHours < 24) {
      final h = diff.inHours;
      return '$h ${h == 1 ? 'hour' : 'hours'} ago';
    }
    if (diff.inDays == 1) return 'Yesterday';
    if (diff.inDays < 7) return '${diff.inDays} days ago';

    // Older: dd Mon yyyy
    const months = [
      '', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return '${dt.day} ${months[dt.month]} ${dt.year}';
  }
}