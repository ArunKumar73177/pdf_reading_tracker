import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'appearance_mode.dart';

/// Persists the selected [AppearanceMode] across app restarts.
///
/// Deliberately **not** stored in SQLite: the "DO NOT touch database code"
/// constraint rules out adding a settings table or migrating the schema,
/// and a single enum value does not warrant a database round trip. Instead
/// this writes one tiny text file via `path_provider`, which is already a
/// package dependency — no new package added.
///
/// The file lives at
/// `<ApplicationSupportDirectory>/pdf_reading_tracker_appearance.txt` and
/// contains only the mode's [AppearanceMode.storageValue] (e.g. `"dark"`).
class AppearanceStorage {
  AppearanceStorage._();
  static final AppearanceStorage instance = AppearanceStorage._();

  static const String _fileName = 'pdf_reading_tracker_appearance.txt';

  Future<File> _file() async {
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}/$_fileName');
  }

  /// Returns the previously persisted mode, or `null` if none was ever
  /// saved (first launch) or the read failed.
  Future<AppearanceMode?> load() async {
    try {
      final file = await _file();
      if (!await file.exists()) return null;
      final raw = (await file.readAsString()).trim();
      if (raw.isEmpty) return null;
      return AppearanceMode.fromStorageValue(raw);
    } catch (e) {
      debugPrint('[AppearanceStorage] load failed (non-fatal): $e');
      return null;
    }
  }

  /// Persists [mode]. Failures are logged and swallowed — appearance
  /// preference is a nice-to-have, never worth surfacing an error to the
  /// reader.
  Future<void> save(AppearanceMode mode) async {
    try {
      final file = await _file();
      await file.writeAsString(mode.storageValue, flush: true);
    } catch (e) {
      debugPrint('[AppearanceStorage] save failed (non-fatal): $e');
    }
  }
}
