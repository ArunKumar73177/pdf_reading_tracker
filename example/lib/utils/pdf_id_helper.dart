import 'package:path/path.dart' as p;

/// Derives a stable, SQLite-safe [pdfId] from a persistent on-device file path.
///
/// Rules:
/// - Uses the **filename without extension** as the base (e.g. `merged_a_b`).
/// - Lowercases the result.
/// - Replaces every character that is not `[a-z0-9_-]` with `_`.
/// - Prefixes with `file_` so ids never start with a digit.
///
/// This is intentionally path-segment-based (not full-path-hash) so that
/// if the user moves a file and re-picks it, it still gets the same id —
/// matching the behaviour of [PdfPickerService].
///
/// For merged PDFs the output filename already encodes the source files
/// (`merged_1234567890.pdf`), so the id is naturally unique.
/// For split PDFs each part has a unique suffix (`source_part_1.pdf`).
///
/// ### Example
/// ```dart
/// PdfIdHelper.fromFilePath('/docs/merged_report.pdf')
/// // → 'file_merged_report'
///
/// PdfIdHelper.fromFilePath('/docs/Clean Architecture_part_1.pdf')
/// // → 'file_clean_architecture_part_1'
/// ```
abstract final class PdfIdHelper {
  PdfIdHelper._();

  /// Returns a stable, sanitised pdfId for [filePath].
  static String fromFilePath(String filePath) {
    final base = p.basenameWithoutExtension(filePath);
    final sanitised = base
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9_\-]'), '_')
        .replaceAll(RegExp(r'_+'), '_') // collapse runs of underscores
        .replaceAll(RegExp(r'^_+|_+$'), ''); // trim leading/trailing _
    return 'file_${sanitised.isEmpty ? 'pdf' : sanitised}';
  }

  /// Returns a human-readable title from a file path.
  ///
  /// Uses the filename without extension with underscores replaced by spaces.
  static String titleFromFilePath(String filePath) {
    final base = p.basenameWithoutExtension(filePath);
    return base.replaceAll('_', ' ').trim();
  }
}