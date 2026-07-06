import 'dart:io';
import 'dart:isolate';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';

import 'pdf_operation_exception.dart';

// ---------------------------------------------------------------------------
// Isolate payload types
// ---------------------------------------------------------------------------

@immutable
class _MergeRequest {
  const _MergeRequest({required this.inputPaths, required this.outputPath});
  final List<String> inputPaths;
  final String outputPath;
}

@immutable
class _MergeResult {
  const _MergeResult({this.outputPath, this.error, this.stackTrace});
  final String? outputPath;
  final Object? error;
  final StackTrace? stackTrace;
  bool get isSuccess => outputPath != null;
}

// ---------------------------------------------------------------------------
// Public service
// ---------------------------------------------------------------------------

/// Merges two or more PDF files into a single output PDF.
///
/// All heavy PDF work runs in a dedicated [Isolate] so the Flutter UI thread
/// is never blocked, even for large documents.
///
/// ---
/// ### API note — syncfusion_flutter_pdf ^27.1.48
///
/// The Flutter build of `syncfusion_flutter_pdf` does **not** have an
/// `importPage` method on [PdfPageCollection]. That method exists only in
/// Syncfusion's .NET PDF library. Attempting to call it produces:
///
/// > The method 'importPage' isn't defined for the type 'PdfPageCollection'
///
/// The correct approach (confirmed by Syncfusion's own KB article and GitHub
/// support) is the **template pattern**:
///
/// ```dart
/// PdfTemplate template = sourcePage.createTemplate();
/// destPage.graphics.drawPdfTemplate(template, Offset.zero, destPage.getClientSize());
/// ```
///
/// `createTemplate()` wraps the page's content stream into a [PdfTemplate]
/// (a PDF Form XObject). This faithfully reproduces all visible content —
/// text, images, and vector graphics. Interactive elements (live form fields,
/// clickable annotations) are not carried over; flatten them first if needed.
///
/// Pages with different dimensions are handled by creating a new [PdfSection]
/// whenever the page size changes.
/// ---
///
/// ### Basic usage
/// ```dart
/// final path = await PdfMergeService.merge(
///   inputPaths: ['/path/to/a.pdf', '/path/to/b.pdf'],
/// );
/// ```
///
/// ### Error handling
/// ```dart
/// try {
///   final path = await PdfMergeService.merge(inputPaths: [pdf1, pdf2]);
/// } on PdfMergeFileNotFoundException catch (e) {
///   print('Missing: ${e.missingPath}');
/// } on PdfMergeCorruptFileException catch (e) {
///   print('Corrupt: ${e.corruptPath}');
/// } on PdfMergeException catch (e) {
///   print('Failed: ${e.message}');
/// }
/// ```
abstract final class PdfMergeService {
  PdfMergeService._();

  // ---------------------------------------------------------------------------
  // Public API
  // ---------------------------------------------------------------------------

  /// Merges the PDFs at [inputPaths] into a single file.
  ///
  /// [inputPaths] must contain at least two valid, readable PDF paths.
  /// [outputPath] is optional; when omitted a timestamped file is created in
  /// [getTemporaryDirectory]. [outputFileName] is only used when [outputPath]
  /// is `null`.
  ///
  /// Returns the absolute path of the merged PDF.
  ///
  /// Throws:
  /// - [PdfMergeFileNotFoundException] — an input path does not exist.
  /// - [PdfMergeCorruptFileException] — a file cannot be parsed as a PDF.
  /// - [PdfMergeException] — any other failure.
  static Future<String> merge({
    required List<String> inputPaths,
    String? outputPath,
    String? outputFileName,
  }) async {
    if (inputPaths.length < 2) {
      throw const PdfMergeException(
        'At least two input PDFs are required for a merge.',
      );
    }

    for (final path in inputPaths) {
      if (!File(path).existsSync()) throw PdfMergeFileNotFoundException(path);
    }

    final resolvedOutputPath =
        outputPath ?? await _resolveOutputPath(outputFileName);

    final result = await Isolate.run(
      () => _mergeInIsolate(
        _MergeRequest(inputPaths: inputPaths, outputPath: resolvedOutputPath),
      ),
    );

    if (!result.isSuccess) {
      final err = result.error;
      final st = result.stackTrace;
      if (err is PdfMergeException) throw err;
      throw PdfMergeException('Merge failed unexpectedly.',
          cause: err, stackTrace: st);
    }

    return result.outputPath!;
  }

  // ---------------------------------------------------------------------------
  // Isolate entry point
  // ---------------------------------------------------------------------------

  /// Runs entirely inside a spawned [Isolate].
  ///
  /// Implementation uses [PdfPage.createTemplate] + [PdfPageGraphics.drawPdfTemplate]:
  /// the only supported method for copying page content in syncfusion_flutter_pdf.
  ///
  /// A new [PdfSection] is created whenever the page size changes so mixed-size
  /// documents (e.g. portrait + landscape) are handled correctly.
  static _MergeResult _mergeInIsolate(_MergeRequest req) {
    PdfDocument? output;
    try {
      output = PdfDocument();
      PdfSection? currentSection;
      Size? currentSize;

      for (final path in req.inputPaths) {
        PdfDocument? source;
        try {
          source = PdfDocument(inputBytes: File(path).readAsBytesSync());
        } catch (e) {
          output.dispose();
          return _MergeResult(
              error: PdfMergeCorruptFileException(path, cause: e));
        }

        try {
          for (int i = 0; i < source.pages.count; i++) {
            // createTemplate() is the verified Syncfusion Flutter API for
            // capturing a page's full content as a reusable Form XObject.
            final PdfTemplate template = source.pages[i].createTemplate();
            final Size pageSize = template.size;

            // Allocate a new section only when the page size changes so the
            // destination page dimensions always match the source exactly.
            if (currentSection == null || currentSize != pageSize) {
              currentSection = output.sections!.add();
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
        } finally {
          source.dispose();
        }
      }

      // saveSync() is correct for isolate use — avoids async/await across
      // the isolate boundary that Isolate.run does not support.
      final bytes = output.saveSync();
      File(req.outputPath).writeAsBytesSync(bytes);
      return _MergeResult(outputPath: req.outputPath);
    } catch (e, st) {
      return _MergeResult(error: e, stackTrace: st);
    } finally {
      output?.dispose();
    }
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  static Future<String> _resolveOutputPath(String? fileName) async {
    final dir = await getTemporaryDirectory();
    final name =
        fileName ?? 'merged_${DateTime.now().millisecondsSinceEpoch}.pdf';
    return p.join(dir.path, name);
  }
}
