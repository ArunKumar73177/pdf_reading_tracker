import 'package:flutter/material.dart';

import 'design_tokens.dart';
import 'theme_extensions.dart';

/// Builds the [ThemeData] used inside [PdfReadingTrackerViewer] for a
/// resolved [Brightness].
///
/// This is the **only** place a seed colour / Material 3 scheme is defined
/// for the reader. Widgets never construct colours themselves — they read
/// `Theme.of(context).colorScheme`, `.textTheme`, or
/// `Theme.of(context).extension<ReaderColors>()`.
///
/// A calm, desaturated blue seed is used rather than a saturated brand
/// colour — closer to Apple Books / Google Play Books, which keep chrome
/// neutral so the page content stays the visual focus.
abstract final class AppearanceThemeBuilder {
  static const Color _seed = Color(0xFF3A6EA5);

  /// Builds a complete [ThemeData] for [brightness], with [ReaderColors]
  /// attached via [ThemeData.extensions] so downstream widgets can look it
  /// up without any additional wiring.
  static ThemeData build(Brightness brightness) {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: _seed,
      brightness: brightness,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: colorScheme.surface,
      appBarTheme: AppBarTheme(
        backgroundColor: colorScheme.primaryContainer,
        foregroundColor: colorScheme.onPrimaryContainer,
        elevation: 0,
        scrolledUnderElevation: 1,
      ),
      // Subtle, flat surfaces — no heavy shadows, per UX requirements.
      cardTheme: const CardThemeData(elevation: AppElevation.none),
      dialogTheme: DialogThemeData(
        backgroundColor: colorScheme.surfaceContainerHigh,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: colorScheme.surface,
        modalBackgroundColor: colorScheme.surface,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(AppRadius.lg),
          ),
        ),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: SegmentedButton.styleFrom(
          visualDensity: VisualDensity.compact,
        ),
      ),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: FadeUpwardsPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        },
      ),
      extensions: [ReaderColors.forBrightness(brightness)],
    );
  }
}