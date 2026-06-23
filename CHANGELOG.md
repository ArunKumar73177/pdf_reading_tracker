# Changelog

## 3.0.0

### 🚀 Major Release

This release introduces a complete migration to Syncfusion PDF Viewer and significantly expands the package from a reading-progress tracker into a full-featured PDF reader and annotation solution.

---

### 🔥 Major Architecture Changes

* Replaced ALH PDF View with Syncfusion PDF Viewer.
* Reworked PDF rendering architecture.
* Improved rendering reliability and maintainability.
* Simplified dependency management by removing JitPack requirements.
* Improved overall package structure for long-term scalability.

---

### ✨ Added

#### PDF Reading

* Reading Progress Tracking
* Continue Reading
* Recent PDFs Dashboard
* Jump To Page Navigation
* Multi-PDF Support
* Persistent Reading Position

#### User PDF Management

* Import PDFs from device storage
* Persistent PDF Library
* Stable PDF ID generation
* Automatic PDF restoration after app restart

#### Search

* Built-in PDF Text Search
* Search Navigation
* Search Result Highlighting

#### Bookmarks

* Bookmark Creation
* Bookmark Removal
* Bookmark Notes
* Persistent Bookmark Storage

#### Annotations

* Highlight Annotations
* Underline Annotations
* Strikethrough Annotations
* Squiggly Annotations
* Annotation Persistence
* Annotation Restoration

#### Notes

* Text-linked Notes
* Edit Notes
* Delete Notes
* Jump To Note
* Persistent Note Storage

#### PDF Operations

* PDF Merge
* PDF Split
* Typed Exception Handling

---

### ⚡ Improvements

* Improved Reading Progress Tracking
* Improved Continue Reading Experience
* Improved Recent PDFs Workflow
* Improved PDF Loading Performance
* Improved Bookmark Management
* Improved Annotation Restoration
* Improved Database Structure
* Improved Storage Efficiency
* Improved Offline Persistence
* Improved User PDF Workflow

---

### 🛠 Fixed

* Fixed File Not Found issues caused by temporary file picker paths.
* Fixed reading progress persistence issues.
* Fixed bookmark restoration issues.
* Fixed PDF reopening issues.
* Fixed annotation restoration race conditions.
* Fixed dialog lifecycle issues.
* Fixed TextEditingController disposal issues.
* Fixed duplicate PDF cache storage.
* Fixed multiple persistence edge cases.

---

### 💾 Storage Optimizations

* Automatic cleanup of temporary imported PDFs.
* Reduced duplicate file storage.
* Lightweight SQLite schema.
* Efficient annotation storage.
* Efficient note storage.

---

### 🏗 Internal

* Added Highlight APIs.
* Added Note APIs.
* Added Search Controller.
* Added Annotation Infrastructure.
* Extended SQLite Schema.
* Improved Service Architecture.
* Improved Persistence Layer.

---

### Known Limitations

* Reading progress currently relies on Syncfusion page-change events.
* Dominant page detection is planned for a future release.
* Advanced search customization may be expanded in future versions.
