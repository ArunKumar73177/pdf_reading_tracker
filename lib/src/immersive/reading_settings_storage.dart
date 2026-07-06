import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'reading_settings.dart';

/// Persists [ReadingSettings] across app restarts.
///
/// Mirrors `AppearanceStorage` (Phase 1) exactly: a single small file under
/// `ApplicationSupportDirectory`, no SQLite table, no schema migration.
/// Kept as its own class (rather than folded into `AppearanceStorage`) so
/// Phase 1's appearance persistence and Phase 3's reading-settings
/// persistence stay independently testable and neither accidentally
/// depends on the other's file format.
class ReadingSettingsStorage {
  ReadingSettingsStorage._();
  static final ReadingSettingsStorage instance = ReadingSettingsStorage._();

  static const String _fileName = 'pdf_reading_tracker_reading_settings.json';

  Future<File> _file() async {
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}/$_fileName');
  }

  /// Returns the previously persisted settings, or `null` if none were
  /// ever saved (first launch) or the read/parse failed.
  Future<ReadingSettings?> load() async {
    try {
      final file = await _file();
      if (!await file.exists()) return null;
      final raw = await file.readAsString();
      if (raw.trim().isEmpty) return null;
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return null;
      return ReadingSettings.fromJson(decoded);
    } catch (e) {
      debugPrint('[ReadingSettingsStorage] load failed (non-fatal): $e');
      return null;
    }
  }

  /// Persists [settings]. Failures are logged and swallowed — reading
  /// preferences are a nice-to-have, never worth surfacing an error to the
  /// reader mid-session.
  Future<void> save(ReadingSettings settings) async {
    try {
      final file = await _file();
      await file.writeAsString(jsonEncode(settings.toJson()), flush: true);
    } catch (e) {
      debugPrint('[ReadingSettingsStorage] save failed (non-fatal): $e');
    }
  }
}
