/// Describes a single PDF document the example app can open.
///
/// This is the single source of truth for every string that identifies a
/// document. No layer may use a raw string literal as a pdfId — always use
/// [PdfDocument.id].
class PdfDocument {
  const PdfDocument({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.assetPath,
  });

  /// Stable SQLite primary key.
  ///
  /// ⚠️  NEVER rename this after shipping.  All reading_progress and
  /// bookmark rows are keyed on this value.  A rename is a data-loss event.
  final String id;

  /// Shown in the AppBar and on the selection card.
  final String title;

  /// Second line on the selection card.
  final String subtitle;

  /// Flutter asset path declared in pubspec.yaml.
  final String assetPath;

  @override
  String toString() =>
      'PdfDocument(id: $id, title: $title, assetPath: $assetPath)';
}

// ---------------------------------------------------------------------------
// Catalogue — the single place where PDFs are registered
// ---------------------------------------------------------------------------
//
// IMPORTANT — id values below are intentionally kept as 'sample_pdf_v1' and
// 'sample2_pdf_v1' so that any bookmarks or progress already saved by the
// previous version of the app (which used kSamplePdfId = 'sample_pdf_v1')
// are automatically found on first launch of the refactored app.
// Do NOT change these strings.

const List<PdfDocument> kPdfCatalogue = [
  PdfDocument(
    id: 'sample_pdf_v1', // ← matches old kSamplePdfId exactly
    title: 'Clean Architecture',
    subtitle: 'Robert C. Martin — Software craftsmanship',
    assetPath: 'assets/sample.pdf',
  ),
  PdfDocument(
    id: 'sample2_pdf_v1',
    title: 'Flutter System Design',
    subtitle: 'Patterns and architecture for production Flutter apps',
    assetPath: 'assets/sample2.pdf',
  ),
];
