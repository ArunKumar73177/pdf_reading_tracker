import 'package:flutter/material.dart';
import 'package:pdf_reading_tracker/pdf_reading_tracker.dart';

import '../models/pdf_document.dart';

/// Thin wrapper — all reader logic now lives inside [PdfReadingTrackerViewer].
///
/// This screen is kept so the example app can accept a [PdfDocument] from
/// its navigation stack. In real apps consumers would use
/// [PdfReadingTrackerViewer] directly on any route.
class PdfReaderScreen extends StatelessWidget {
  const PdfReaderScreen({super.key, required this.document});

  final PdfDocument document;

  @override
  Widget build(BuildContext context) {
    return PdfReadingTrackerViewer(
      pdfId: document.id,
      pdfTitle: document.title,
      assetPath: document.assetPath,
    );
  }
}