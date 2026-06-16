# Changelog

## 2.1.0

### New Features

* Added user PDF upload support using File Picker.
* Added Continue Reading dashboard.
* Added Recent PDFs screen.
* Added persistent storage of user-selected PDFs.
* Added stable PDF ID generation for user, merged, and split PDFs.
* Added automatic resume-from-last-page support for uploaded PDFs.
* Added jump-to-page navigation.
* Added improved progress tracking across all PDF types.
* Added support for bookmarks on uploaded PDFs.
* Added support for bookmarks on merged PDFs.
* Added support for bookmarks on split PDFs.

### Improvements

* Improved PDF loading workflow.
* Improved reading progress calculation accuracy.
* Improved persistence of user-selected PDFs across app restarts.
* Improved Continue Reading and Recent PDFs experience.
* Improved SQLite data handling and PDF identification.
* Enhanced example application with multi-PDF workflow.

### Fixes

* Fixed File Not Found issues caused by temporary File Picker cache paths.
* Fixed reading progress never reaching 100% on the final page.
* Fixed page 1 showing 0% progress.
* Fixed Continue Reading not displaying newly opened PDFs.
* Fixed Recent PDFs filtering issues.
* Fixed progress tracking inconsistencies for merged and split PDFs.
* Fixed bookmark persistence issues for generated PDFs.
* Reduced lag during page jump navigation.
* Improved PDF reopening and restoration behavior.

### Internal

* Added PdfPickerService.
* Added PdfIdHelper.
* Extended database schema to support user-selected PDFs.
* Optimized controller initialization and persistence workflow.
* Improved package architecture for future features such as:

    * Text Search
    * Text Highlighting
    * PDF Annotation
    * Page Extraction
    * Page Rotation
    * Password Protected PDFs
    * Thumbnail Navigation
