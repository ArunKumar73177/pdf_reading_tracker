/// Unified exception hierarchy for all PDF operation failures.
///
/// Both [PdfMergeException] and [PdfSplitException] extend this base class
/// so callers can catch either specifically or both with a single `on` clause:
///
/// ```dart
/// try {
///   await PdfMergeService.merge(...);
/// } on PdfOperationException catch (e) {
///   // handles both merge and split errors
/// }
/// ```
sealed class PdfOperationException implements Exception {
  const PdfOperationException(
      this.message, {
        this.cause,
        this.stackTrace,
      });

  /// Human-readable description of what failed.
  final String message;

  /// The underlying error that triggered this exception, if any.
  final Object? cause;

  /// Stack trace captured at the throw site.
  final StackTrace? stackTrace;

  @override
  String toString() {
    final buf = StringBuffer('${runtimeType}: $message');
    if (cause != null) buf.write('\nCause: $cause');
    return buf.toString();
  }
}

// ---------------------------------------------------------------------------
// Merge exceptions
// ---------------------------------------------------------------------------

/// Thrown by [PdfMergeService] when a merge operation cannot be completed.
final class PdfMergeException extends PdfOperationException {
  const PdfMergeException(
      super.message, {
        super.cause,
        super.stackTrace,
      });
}

/// Thrown when one or more input paths do not exist on disk.
final class PdfMergeFileNotFoundException extends PdfMergeException {
  const PdfMergeFileNotFoundException(this.missingPath)
      : super('Input file not found: $missingPath');

  /// The path that could not be found.
  final String missingPath;
}

/// Thrown when a PDF file cannot be opened or is structurally invalid.
final class PdfMergeCorruptFileException extends PdfMergeException {
  const PdfMergeCorruptFileException(this.corruptPath, {super.cause})
      : super(
    'PDF file appears to be corrupted or password-protected: $corruptPath',
  );

  /// The path of the file that could not be parsed.
  final String corruptPath;
}

// ---------------------------------------------------------------------------
// Split exceptions
// ---------------------------------------------------------------------------

/// Thrown by [PdfSplitService] when a split operation cannot be completed.
final class PdfSplitException extends PdfOperationException {
  const PdfSplitException(
      super.message, {
        super.cause,
        super.stackTrace,
      });
}

/// Thrown when the source PDF does not exist on disk.
final class PdfSplitFileNotFoundException extends PdfSplitException {
  const PdfSplitFileNotFoundException(String path)
      : super('Source PDF not found: $path');
}

/// Thrown when the requested page ranges are invalid for the given document.
final class PdfSplitInvalidRangeException extends PdfSplitException {
  const PdfSplitInvalidRangeException(super.message);
}