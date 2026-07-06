import 'dart:io';

import 'package:flutter/material.dart';
import 'package:pdf_reading_tracker/pdf_reading_tracker.dart';

// ---------------------------------------------------------------------------
// RecentPdfsScreen — v2.2.0
//
// **v2.2.0 changes — Improvement 4 (enhanced card UI)**
//
// Each card now features:
//   • A colour-coded PDF icon avatar whose background shifts with progress
//     tier (< 33 % → amber, 33–66 % → teal, > 66 % → green, 100 % → primary).
//   • Stronger visual hierarchy — title in bodyLarge/semibold, metadata in
//     bodySmall/muted.
//   • A compact two-column metadata row (page fraction left, % right).
//   • A gradient-filled AnimatedProgressBar (same component as the reader).
//   • A "Continue" FilledButton.tonal and a delete icon aligned in a row so
//     both actions are always visible without nested columns.
//   • A "File not found" chip replacing the previous plain text badge.
//
// Older change notes preserved below:
//   - Removed null-guard on `progress.lastReadAt` (field is non-nullable).
//   - Cards for PDFs where totalPages == 0 show "Opening…".
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
      if (mounted) {
        setState(() {
          _recents = recents;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openPdf(ReadingProgress progress) async {
    if (progress.filePath == null || !File(progress.filePath!).existsSync()) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content:
            Text('"${progress.title ?? 'PDF'}" could not be found on device.'),
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
    await _load();
  }

  Future<void> _deleteHistory(ReadingProgress progress) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove from history?'),
        content: Text(
          'Reading progress and bookmarks for '
          '"${progress.title ?? 'this PDF'}" will be deleted.',
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
    if (confirmed != true || !mounted) return;
    await PdfReadingTracker.deleteProgress(progress.pdfId);
    await PdfReadingTracker.clearBookmarks(progress.pdfId);
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
              ? const _EmptyHistory()
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
  const _EmptyHistory();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.history_rounded,
              size: 64, color: cs.onSurfaceVariant.withAlpha(100)),
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
// Enhanced recent card — Improvement 4
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

    final fileExists =
        progress.filePath == null || File(progress.filePath!).existsSync();
    final title = progress.title ?? 'Unknown PDF';
    final pct = progress.progressPct;
    final hasPages = progress.totalPages > 0;

    // Colour-code the icon avatar by progress tier.
    final avatarBg = _avatarBackground(pct, fileExists, cs);
    final avatarFg = _avatarForeground(pct, fileExists, cs);

    return Card(
      elevation: 0,
      color: cs.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: fileExists ? cs.outlineVariant : cs.errorContainer,
          width: 0.8,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Header row: icon + title + delete ──────────────────────
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Colour-coded PDF icon
                CircleAvatar(
                  radius: 22,
                  backgroundColor: avatarBg,
                  foregroundColor: avatarFg,
                  child: const Icon(Icons.picture_as_pdf_rounded, size: 22),
                ),
                const SizedBox(width: 12),

                // Title + timestamp
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: tt.bodyLarge?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: fileExists ? null : cs.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        _relativeTime(progress.lastReadAt),
                        style:
                            tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),

                // Delete icon
                IconButton(
                  icon: const Icon(Icons.delete_outline_rounded, size: 20),
                  tooltip: 'Remove from history',
                  color: cs.onSurfaceVariant,
                  padding: EdgeInsets.zero,
                  constraints:
                      const BoxConstraints(minWidth: 36, minHeight: 36),
                  onPressed: onDelete,
                ),
              ],
            ),

            // ── File-not-found chip ─────────────────────────────────────
            if (!fileExists) ...[
              const SizedBox(height: 10),
              _StatusChip(
                icon: Icons.warning_amber_rounded,
                label: 'File not found on device',
                color: cs.error,
                backgroundColor: cs.errorContainer,
              ),
            ],

            // ── Progress section ────────────────────────────────────────
            if (hasPages) ...[
              const SizedBox(height: 14),
              // Gradient animated progress bar (Improvement 3 component)
              _GradientProgressBar(
                progressPct: pct,
                fileExists: fileExists,
              ),
              const SizedBox(height: 8),

              // Metadata row: page counter (left) + percentage (right)
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Page ${progress.currentPage + 1} of ${progress.totalPages}',
                    style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                  ),
                  Text(
                    '${pct.toStringAsFixed(1)}% read',
                    style: tt.bodySmall?.copyWith(
                      color: fileExists ? _progressColor(pct, cs) : cs.outline,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ] else ...[
              const SizedBox(height: 10),
              Text(
                'Opening…',
                style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
              ),
            ],

            // ── Action row ──────────────────────────────────────────────
            if (fileExists) ...[
              const SizedBox(height: 14),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton.tonal(
                  onPressed: onResume,
                  style: FilledButton.styleFrom(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 20, vertical: 0),
                    minimumSize: const Size(0, 36),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        pct >= 100.0
                            ? Icons.replay_rounded
                            : Icons.play_arrow_rounded,
                        size: 18,
                      ),
                      const SizedBox(width: 6),
                      Text(pct >= 100.0 ? 'Read again' : 'Continue'),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Colour helpers
  // ---------------------------------------------------------------------------

  Color _avatarBackground(double pct, bool fileExists, ColorScheme cs) {
    if (!fileExists) return cs.errorContainer;
    if (pct >= 100.0) return cs.primaryContainer;
    if (pct > 66.0) return Colors.green.shade100;
    if (pct > 33.0) return Colors.teal.shade50;
    return Colors.amber.shade100;
  }

  Color _avatarForeground(double pct, bool fileExists, ColorScheme cs) {
    if (!fileExists) return cs.onErrorContainer;
    if (pct >= 100.0) return cs.onPrimaryContainer;
    if (pct > 66.0) return Colors.green.shade800;
    if (pct > 33.0) return Colors.teal.shade700;
    return Colors.amber.shade800;
  }

  Color _progressColor(double pct, ColorScheme cs) {
    if (pct >= 100.0) return cs.primary;
    if (pct > 66.0) return Colors.green.shade600;
    if (pct > 33.0) return Colors.teal.shade600;
    return Colors.amber.shade700;
  }

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
    const months = [
      '',
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${dt.day} ${months[dt.month]} ${dt.year}';
  }
}

// ---------------------------------------------------------------------------
// Inline gradient progress bar (self-contained, no extra import needed)
// ---------------------------------------------------------------------------

class _GradientProgressBar extends StatelessWidget {
  const _GradientProgressBar({
    required this.progressPct,
    required this.fileExists,
  });

  final double progressPct;
  final bool fileExists;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final fillColor = fileExists ? cs.primary : cs.outline;
    final endColor = fileExists
        ? (Color.lerp(cs.primary, cs.tertiary, 0.5) ?? cs.primary)
        : cs.outline;

    return LayoutBuilder(
      builder: (context, constraints) {
        final totalWidth = constraints.maxWidth;
        final fillWidth = (progressPct / 100.0) * totalWidth;
        return Stack(
          children: [
            Container(
              width: totalWidth,
              height: 6,
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
            AnimatedContainer(
              duration: const Duration(milliseconds: 450),
              curve: Curves.easeOutCubic,
              width: fillWidth.clamp(0.0, totalWidth),
              height: 6,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(3),
                gradient: LinearGradient(
                  colors: [fillColor, endColor],
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Status chip
// ---------------------------------------------------------------------------

class _StatusChip extends StatelessWidget {
  const _StatusChip({
    required this.icon,
    required this.label,
    required this.color,
    required this.backgroundColor,
  });

  final IconData icon;
  final String label;
  final Color color;
  final Color backgroundColor;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 5),
          Text(label,
              style: tt.labelSmall
                  ?.copyWith(color: color, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}
