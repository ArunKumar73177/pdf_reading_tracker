/// The user-selectable appearance option for [PdfReadingTrackerViewer].
///
/// Kept intentionally minimal (three values) for v3.x. The system is built
/// so that future modes — OLED Black, Sepia, Paper, Gray — can be added as
/// additional enum values plus a matching [ReaderColors] / [ThemeData]
/// branch in `appearance_data.dart`, without touching any widget.
enum AppearanceMode {
  /// Always use the light reading theme.
  light,

  /// Always use the dark reading theme.
  dark,

  /// Follow the host device's system brightness setting. Automatically
  /// switches when the OS theme changes while the app is running.
  system;

  /// Stable string used for persistence. Deliberately independent of
  /// [name] ordering/casing so storage format never breaks if enum values
  /// are reordered or renamed in the Dart source in the future.
  String get storageValue {
    switch (this) {
      case AppearanceMode.light:
        return 'light';
      case AppearanceMode.dark:
        return 'dark';
      case AppearanceMode.system:
        return 'system';
    }
  }

  static AppearanceMode fromStorageValue(String? value) {
    switch (value) {
      case 'light':
        return AppearanceMode.light;
      case 'dark':
        return AppearanceMode.dark;
      case 'system':
      default:
        return AppearanceMode.system;
    }
  }
}