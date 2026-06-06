import 'package:flutter/material.dart';
import 'package:pdf_reading_tracker/pdf_reading_tracker.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const PdfTrackerExampleApp());
}

class PdfTrackerExampleApp extends StatelessWidget {
  const PdfTrackerExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PDF Reading Tracker Demo',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: Colors.indigo,
        useMaterial3: true,
      ),
      home: const TrackerDemoPage(),
    );
  }
}

// ---------------------------------------------------------------------------
// Demo page
// ---------------------------------------------------------------------------

class TrackerDemoPage extends StatefulWidget {
  const TrackerDemoPage({super.key});

  @override
  State<TrackerDemoPage> createState() => _TrackerDemoPageState();
}

class _TrackerDemoPageState extends State<TrackerDemoPage> {
  static const _pdfId = 'demo_document_001';

  final List<String> _log = [];
  bool _loading = false;

  ReadingProgress? _currentProgress;
  List<Bookmark> _bookmarks = [];

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  void _addLog(String message) {
    setState(() => _log.insert(0, '${_timestamp()} $message'));
  }

  String _timestamp() {
    final t = DateTime.now();
    return '[${t.hour.toString().padLeft(2, '0')}:'
        '${t.minute.toString().padLeft(2, '0')}:'
        '${t.second.toString().padLeft(2, '0')}]';
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_loading) return;
    setState(() => _loading = true);
    try {
      await action();
    } catch (e) {
      _addLog('ERROR: $e');
    } finally {
      setState(() => _loading = false);
    }
  }

  // ---------------------------------------------------------------------------
  // Package operations
  // ---------------------------------------------------------------------------

  Future<void> _saveProgress() => _run(() async {
    final progress = ReadingProgress.create(
      pdfId: _pdfId,
      currentPage: 42,
      totalPages: 200,
      title: 'Clean Architecture by Robert Martin',
    );
    final id = await PdfReadingTracker.saveProgress(progress);
    _addLog('✅ Progress saved (rowId=$id) — page 42 / 200');
    await _refreshProgress();
  });

  Future<void> _getProgress() => _run(() async {
    final progress = await PdfReadingTracker.getProgress(_pdfId);
    if (progress == null) {
      _addLog('ℹ️ No progress found for "$_pdfId"');
    } else {
      _addLog(
        '📖 Progress: page ${progress.currentPage}/${progress.totalPages} '
            '(${progress.progressPct.toStringAsFixed(1)}%)',
      );
    }
    await _refreshProgress();
  });

  Future<void> _addBookmark() => _run(() async {
    final notes = ['Key concept here', 'Review this later', 'Important!'];
    final page = 10 + (_bookmarks.length * 7);
    final bookmark = Bookmark.create(
      pdfId: _pdfId,
      page: page,
      note: notes[_bookmarks.length % notes.length],
    );
    final id = await PdfReadingTracker.addBookmark(bookmark);
    _addLog('🔖 Bookmark added (rowId=$id) — page $page');
    await _refreshBookmarks();
  });

  Future<void> _getBookmarks() => _run(() async {
    final bookmarks = await PdfReadingTracker.getBookmarks(_pdfId);
    if (bookmarks.isEmpty) {
      _addLog('ℹ️ No bookmarks found for "$_pdfId"');
    } else {
      _addLog('🔖 Found ${bookmarks.length} bookmark(s)');
    }
    await _refreshBookmarks();
  });

  Future<void> _deleteBookmark(int id) => _run(() async {
    final deleted = await PdfReadingTracker.removeBookmark(id);
    _addLog(deleted
        ? '🗑️ Bookmark #$id removed'
        : 'ℹ️ Bookmark #$id not found');
    await _refreshBookmarks();
  });

  Future<void> _clearAll() => _run(() async {
    await PdfReadingTracker.clearAllProgress();
    _addLog('🧹 All progress and bookmarks cleared');
    await _refreshProgress();
    await _refreshBookmarks();
  });

  // ---------------------------------------------------------------------------
  // State refresh
  // ---------------------------------------------------------------------------

  Future<void> _refreshProgress() async {
    final p = await PdfReadingTracker.getProgress(_pdfId);
    setState(() => _currentProgress = p);
  }

  Future<void> _refreshBookmarks() async {
    final b = await PdfReadingTracker.getBookmarks(_pdfId);
    setState(() => _bookmarks = b);
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('PDF Reading Tracker'),
        centerTitle: true,
        backgroundColor: cs.primaryContainer,
        foregroundColor: cs.onPrimaryContainer,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ---- Status card ------------------------------------------
          _StatusCard(progress: _currentProgress),
          const SizedBox(height: 16),

          // ---- Action buttons ----------------------------------------
          Text('Actions', style: tt.titleMedium),
          const SizedBox(height: 8),
          _ActionGrid(
            onSaveProgress: _saveProgress,
            onGetProgress: _getProgress,
            onAddBookmark: _addBookmark,
            onGetBookmarks: _getBookmarks,
            onClearAll: _clearAll,
          ),
          const SizedBox(height: 16),

          // ---- Bookmarks list ----------------------------------------
          if (_bookmarks.isNotEmpty) ...[
            Text('Bookmarks (${_bookmarks.length})',
                style: tt.titleMedium),
            const SizedBox(height: 8),
            ..._bookmarks.map(
                  (b) => _BookmarkTile(
                bookmark: b,
                onDelete: () => _deleteBookmark(b.id!),
              ),
            ),
            const SizedBox(height: 16),
          ],

          // ---- Log ---------------------------------------------------
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Log', style: tt.titleMedium),
              if (_log.isNotEmpty)
                TextButton.icon(
                  onPressed: () => setState(() => _log.clear()),
                  icon: const Icon(Icons.delete_sweep, size: 18),
                  label: const Text('Clear'),
                ),
            ],
          ),
          const SizedBox(height: 8),
          _LogPanel(entries: _log),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Sub-widgets
// ---------------------------------------------------------------------------

class _StatusCard extends StatelessWidget {
  const _StatusCard({this.progress});

  final ReadingProgress? progress;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Card(
      color: cs.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: progress == null
            ? Row(
          children: [
            Icon(Icons.info_outline, color: cs.onSecondaryContainer),
            const SizedBox(width: 12),
            Text(
              'No progress saved yet',
              style: TextStyle(color: cs.onSecondaryContainer),
            ),
          ],
        )
            : Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              progress!.title ?? progress!.pdfId,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                color: cs.onSecondaryContainer,
                fontWeight: FontWeight.bold,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 8),
            LinearProgressIndicator(
              value: progress!.progressPct / 100,
              backgroundColor: cs.surface,
              color: cs.secondary,
              minHeight: 6,
              borderRadius: BorderRadius.circular(4),
            ),
            const SizedBox(height: 6),
            Text(
              'Page ${progress!.currentPage} of ${progress!.totalPages} '
                  '— ${progress!.progressPct.toStringAsFixed(1)}%',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: cs.onSecondaryContainer,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ActionGrid extends StatelessWidget {
  const _ActionGrid({
    required this.onSaveProgress,
    required this.onGetProgress,
    required this.onAddBookmark,
    required this.onGetBookmarks,
    required this.onClearAll,
  });

  final VoidCallback onSaveProgress;
  final VoidCallback onGetProgress;
  final VoidCallback onAddBookmark;
  final VoidCallback onGetBookmarks;
  final VoidCallback onClearAll;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _ActionButton(
          icon: Icons.save_rounded,
          label: 'Save Progress',
          onTap: onSaveProgress,
        ),
        _ActionButton(
          icon: Icons.menu_book_rounded,
          label: 'Get Progress',
          onTap: onGetProgress,
        ),
        _ActionButton(
          icon: Icons.bookmark_add_rounded,
          label: 'Add Bookmark',
          onTap: onAddBookmark,
        ),
        _ActionButton(
          icon: Icons.bookmarks_rounded,
          label: 'Get Bookmarks',
          onTap: onGetBookmarks,
        ),
        _ActionButton(
          icon: Icons.delete_forever_rounded,
          label: 'Clear All',
          onTap: onClearAll,
          destructive: true,
        ),
      ],
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.destructive = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return FilledButton.tonalIcon(
      style: destructive
          ? FilledButton.styleFrom(
        backgroundColor: cs.errorContainer,
        foregroundColor: cs.onErrorContainer,
      )
          : null,
      onPressed: onTap,
      icon: Icon(icon, size: 18),
      label: Text(label),
    );
  }
}

class _BookmarkTile extends StatelessWidget {
  const _BookmarkTile({required this.bookmark, required this.onDelete});

  final Bookmark bookmark;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: const Icon(Icons.bookmark_rounded),
        title: Text('Page ${bookmark.page}'),
        subtitle: bookmark.note != null ? Text(bookmark.note!) : null,
        trailing: IconButton(
          icon: const Icon(Icons.delete_outline),
          tooltip: 'Remove bookmark',
          onPressed: onDelete,
        ),
      ),
    );
  }
}

class _LogPanel extends StatelessWidget {
  const _LogPanel({required this.entries});

  final List<String> entries;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    if (entries.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          'No activity yet — tap a button above.',
          style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
        ),
      );
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: entries
            .map(
              (e) => Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Text(
              e,
              style: tt.bodySmall?.copyWith(
                color: cs.onSurfaceVariant,
                fontFamily: 'monospace',
              ),
            ),
          ),
        )
            .toList(),
      ),
    );
  }
}