import 'dart:io';
import 'dart:isolate';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';

import 'pdf_operation_exception.dart';

// ---------------------------------------------------------------------------
// Value types
// ---------------------------------------------------------------------------

/// Describes a single contiguous page range to extract into one output file.
///
/// Both [startPage] and [endPage] are **1-based** and inclusive.
///
/// ```dart
/// const range = PageRange(startPage: 1, endPage: 5);
/// ```
@immutable
class PageRange {
  const PageRange({required this.startPage, required this.endPage})
      : assert(startPage >= 1, 'startPage must be ≥ 1'),
        assert(endPage >= startPage, 'endPage must be ≥ startPage');

  /// First page to include (1-based).
  final int startPage;

  /// Last page to include (1-based, inclusive).
  final int endPage;

  /// Number of pages in this range.
  int get pageCount => endPage - startPage + 1;

  @override
  String toString() => 'PageRange($startPage–$endPage)';
}

// ---------------------------------------------------------------------------
// Isolate payload types
// ---------------------------------------------------------------------------

@immutable
class _SplitRequest {
  const _SplitRequest({
    required this.pdfPath,
    required this.ranges,
    required this.outputDir,
    required this.baseFileName,
  });
  final String pdfPath;
  final List<PageRange> ranges;
  final String outputDir;
  final String baseFileName;
}

@immutable
class _SplitResult {
  const _SplitResult({this.outputPaths, this.error, this.stackTrace});
  final List<String>? outputPaths;
  final Object? error;
  final StackTrace? stackTrace;
  bool get isSuccess => outputPaths != null;
}

// ---------------------------------------------------------------------------
// Public service
// ---------------------------------------------------------------------------

/// Splits a single PDF into multiple output files.
///
/// Two strategies are supported:
///
/// **By fixed page count** — [split] divides the document evenly.
/// **By explicit ranges** — [splitByRanges] gives full control.
///
/// All heavy PDF work runs in a dedicated [Isolate] so the UI thread is
/// never blocked.
///
/// ---
/// ### API note — syncfusion_flutter_pdf ^27.1.48
///
/// `importPage` does not exist on [PdfPageCollection] in the Flutter package.
/// Page content is copied using the template pattern confirmed by Syncfusion's
/// own support engineers:
///
/// ```dart
/// PdfTemplate template = existingPage.createTemplate();
/// PdfPage newPage = newDocument.pages.add();
/// newPage.graphics.drawPdfTemplate(template, Offset.zero, newPage.getClientSize());
/// ```
/// ---
///
/// ### Even split (5 pages per file)
/// ```dart
/// final parts = await PdfSplitService.split(
///   pdfPath: '/tmp/source.pdf',
///   pagesPerFile: 5,
/// );
/// ```
///
/// ### Explicit ranges
/// ```dart
/// final parts = await PdfSplitService.splitByRanges(
///   pdfPath: '/tmp/source.pdf',
///   ranges: [
///     PageRange(startPage: 1, endPage: 5),
///     PageRange(startPage: 6, endPage: 10),
///   ],
/// );
/// ```
abstract final class PdfSplitService {
  PdfSplitService._();

  // ---------------------------------------------------------------------------
  // Public API — strategy 1: even split
  // ---------------------------------------------------------------------------

  /// Splits [pdfPath] into chunks of [pagesPerFile] pages each.
  ///
  /// The last chunk may contain fewer pages when the document does not divide
  /// evenly. [outputDir] defaults to [getTemporaryDirectory]. [baseFileName]
  /// defaults to the source filename without extension.
  ///
  /// Returns absolute output paths in page order.
  ///
  /// Throws:
  /// - [PdfSplitFileNotFoundException] — [pdfPath] does not exist.
  /// - [PdfSplitInvalidRangeException] — [pagesPerFile] is < 1 or ≥ total pages.
  /// - [PdfSplitException] — any other failure.
  static Future<List<String>> split({
    required String pdfPath,
    required int pagesPerFile,
    String? outputDir,
    String? baseFileName,
  }) async {
    if (!File(pdfPath).existsSync()) throw PdfSplitFileNotFoundException(pdfPath);
    if (pagesPerFile < 1) {
      throw const PdfSplitInvalidRangeException('pagesPerFile must be ≥ 1.');
    }

    final totalPages = await _readPageCount(pdfPath);

    if (pagesPerFile >= totalPages) {
      throw PdfSplitInvalidRangeException(
        'pagesPerFile ($pagesPerFile) must be less than total pages ($totalPages).',
      );
    }

    final ranges = <PageRange>[];
    for (int start = 1; start <= totalPages; start += pagesPerFile) {
      final end = (start + pagesPerFile - 1).clamp(1, totalPages);
      ranges.add(PageRange(startPage: start, endPage: end));
    }

    return _runSplit(
        pdfPath: pdfPath,
        ranges: ranges,
        outputDir: outputDir,
        baseFileName: baseFileName);
  }

  // ---------------------------------------------------------------------------
  // Public API — strategy 2: explicit ranges
  // ---------------------------------------------------------------------------

  /// Splits [pdfPath] according to caller-specified [ranges].
  ///
  /// Each [PageRange] produces exactly one output file. Ranges may overlap.
  /// Returns paths in the same order as [ranges].
  ///
  /// Throws:
  /// - [PdfSplitFileNotFoundException] — [pdfPath] does not exist.
  /// - [PdfSplitInvalidRangeException] — a range exceeds the document.
  /// - [PdfSplitException] — any other failure.
  static Future<List<String>> splitByRanges({
    required String pdfPath,
    required List<PageRange> ranges,
    String? outputDir,
    String? baseFileName,
  }) async {
    if (!File(pdfPath).existsSync()) throw PdfSplitFileNotFoundException(pdfPath);
    if (ranges.isEmpty) {
      throw const PdfSplitInvalidRangeException(
          'At least one PageRange is required.');
    }

    final totalPages = await _readPageCount(pdfPath);
    for (final range in ranges) {
      if (range.endPage > totalPages) {
        throw PdfSplitInvalidRangeException(
            'Range $range exceeds total page count ($totalPages).');
      }
    }

    return _runSplit(
        pdfPath: pdfPath,
        ranges: ranges,
        outputDir: outputDir,
        baseFileName: baseFileName);
  }

  // ---------------------------------------------------------------------------
  // Shared dispatch
  // ---------------------------------------------------------------------------

  static Future<List<String>> _runSplit({
    required String pdfPath,
    required List<PageRange> ranges,
    String? outputDir,
    String? baseFileName,
  }) async {
    final resolvedDir = outputDir ?? (await getTemporaryDirectory()).path;
    final resolvedBase = baseFileName ??
        p.basenameWithoutExtension(pdfPath).replaceAll(RegExp(r'\s+'), '_');

    final result = await Isolate.run(
          () => _splitInIsolate(_SplitRequest(
        pdfPath: pdfPath,
        ranges: ranges,
        outputDir: resolvedDir,
        baseFileName: resolvedBase,
      )),
    );

    if (!result.isSuccess) {
      final err = result.error;
      final st = result.stackTrace;
      if (err is PdfSplitException) throw err;
      throw PdfSplitException('Split failed unexpectedly.',
          cause: err, stackTrace: st);
    }

    return result.outputPaths!;
  }

  // ---------------------------------------------------------------------------
  // Isolate entry point
  // ---------------------------------------------------------------------------

  /// Runs entirely inside a spawned [Isolate].
  ///
  /// The source document is opened once and reused across all ranges.
  /// For each range a fresh [PdfDocument] is created; each page is captured
  /// via [PdfPage.createTemplate] and stamped via [PdfPageGraphics.drawPdfTemplate].
  /// Mixed page sizes within a range are handled via [PdfSection].
  static _SplitResult _splitInIsolate(_SplitRequest req) {
    PdfDocument? source;
    try {
      source = PdfDocument(inputBytes: File(req.pdfPath).readAsBytesSync());
      final outputPaths = <String>[];

      for (int i = 0; i < req.ranges.length; i++) {
        final range = req.ranges[i];
        PdfDocument? chunk;
        try {
          chunk = PdfDocument();
          PdfSection? currentSection;
          Size? currentSize;

          // PageRange is 1-based; page indices in PdfPageCollection are 0-based.
          for (int idx = range.startPage - 1; idx < range.endPage; idx++) {
            // createTemplate() — the correct Syncfusion Flutter API.
            final PdfTemplate template = source.pages[idx].createTemplate();
            final Size pageSize = template.size;

            if (currentSection == null || currentSize != pageSize) {
              currentSection = chunk.sections!.add();
              currentSection.pageSettings.size = pageSize;
              currentSection.pageSettings.margins.all = 0;
              currentSize = pageSize;
            }

            final PdfPage destPage = currentSection.pages.add();
            destPage.graphics.drawPdfTemplate(
              template,
              Offset.zero,
              destPage.getClientSize(),
            );
          }

          final fileName = '${req.baseFileName}_part_${i + 1}.pdf';
          final outPath = p.join(req.outputDir, fileName);
          File(outPath).writeAsBytesSync(chunk.saveSync());
          outputPaths.add(outPath);
        } finally {
          chunk?.dispose();
        }
      }

      return _SplitResult(outputPaths: outputPaths);
    } catch (e, st) {
      return _SplitResult(error: e, stackTrace: st);
    } finally {
      source?.dispose();
    }
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  /// Opens the PDF just long enough to read its page count, then disposes.
  static Future<int> _readPageCount(String path) {
    return Isolate.run(() {
      final doc = PdfDocument(inputBytes: File(path).readAsBytesSync());
      final count = doc.pages.count;
      doc.dispose();
      return count;
    });
  }
}