import 'package:flutter/material.dart';

/// Centralized colour tokens for the small set of reader-chrome widgets
/// that intentionally do **not** follow the ambient [ColorScheme] 1:1 —
/// e.g. the floating progress pill, which is designed to float above the
/// PDF page itself (which is not part of the Flutter theme) and therefore
/// needs its own considered contrast rather than `cs.surface`.
///
/// Every other widget in the package (dialogs, sheets, app bar, buttons)
/// already reads `Theme.of(context).colorScheme` / `.textTheme`, so once
/// the ambient [ThemeData] is swapped by [AppearanceController] those
/// widgets adapt automatically — no widget-level changes were needed for
/// them.
///
/// **Future-ready:** adding a mode such as Sepia or OLED Black means adding
/// one more [ReaderColors] factory (e.g. `ReaderColors.sepia()`) and one
/// more branch in `appearance_data.dart`. No widget touches this class's
/// fields directly by literal value — they always go through
/// `Theme.of(context).extension<ReaderColors>()`.
@immutable
class ReaderColors extends ThemeExtension<ReaderColors> {
  const ReaderColors({
    required this.overlayBackground,
    required this.overlayTrack,
    required this.overlayFill,
    required this.overlayLabel,
    required this.overlayLabelSecondary,
    required this.overlaySavingIndicator,
    required this.noteBadge,
  });

  /// Background of the floating page/progress pill.
  final Color overlayBackground;

  /// Unfilled portion of the mini progress bar inside the pill.
  final Color overlayTrack;

  /// Filled portion of the mini progress bar inside the pill.
  final Color overlayFill;

  /// "Page X / Y" label colour.
  final Color overlayLabel;

  /// Percentage label colour (deliberately lower emphasis than
  /// [overlayLabel]).
  final Color overlayLabelSecondary;

  /// Colour of the small "saving…" spinner shown briefly after a page turn.
  final Color overlaySavingIndicator;

  /// Colour of the sticky-note badge icon shown when the current page has
  /// one or more notes.
  final Color noteBadge;

  /// Calm, low-contrast pill — reads clearly over both light and dark PDF
  /// page content without competing for attention with the text.
  factory ReaderColors.light() => const ReaderColors(
        overlayBackground: Color(0x99000000), // black 60%
        overlayTrack: Color(0x33FFFFFF), // white 20%
        overlayFill: Colors.white,
        overlayLabel: Colors.white,
        overlayLabelSecondary: Color(0x99FFFFFF), // white 60%
        overlaySavingIndicator: Color(0xB3FFFFFF), // white 70%
        noteBadge: Color(0xFF80DEEA), // teal 200
      );

  /// Slightly lighter / lower-opacity pill for dark mode, since the page
  /// backdrop is already dark and a heavy black pill would lose contrast
  /// against it.
  factory ReaderColors.dark() => const ReaderColors(
        overlayBackground: Color(0xCC1C1C1E), // near-black 80%
        overlayTrack: Color(0x40FFFFFF), // white 25%
        overlayFill: Color(0xFFE8EAED),
        overlayLabel: Color(0xFFE8EAED),
        overlayLabelSecondary: Color(0x99E8EAED),
        overlaySavingIndicator: Color(0xB3E8EAED),
        noteBadge: Color(0xFF4DD0E1), // teal 300 — a touch brighter on dark
      );

  /// Resolves the correct built-in variant for a given [Brightness].
  /// New future modes (Sepia, OLED Black…) get their own factory here.
  factory ReaderColors.forBrightness(Brightness brightness) =>
      brightness == Brightness.dark
          ? ReaderColors.dark()
          : ReaderColors.light();

  @override
  ReaderColors copyWith({
    Color? overlayBackground,
    Color? overlayTrack,
    Color? overlayFill,
    Color? overlayLabel,
    Color? overlayLabelSecondary,
    Color? overlaySavingIndicator,
    Color? noteBadge,
  }) {
    return ReaderColors(
      overlayBackground: overlayBackground ?? this.overlayBackground,
      overlayTrack: overlayTrack ?? this.overlayTrack,
      overlayFill: overlayFill ?? this.overlayFill,
      overlayLabel: overlayLabel ?? this.overlayLabel,
      overlayLabelSecondary:
          overlayLabelSecondary ?? this.overlayLabelSecondary,
      overlaySavingIndicator:
          overlaySavingIndicator ?? this.overlaySavingIndicator,
      noteBadge: noteBadge ?? this.noteBadge,
    );
  }

  @override
  ReaderColors lerp(ThemeExtension<ReaderColors>? other, double t) {
    if (other is! ReaderColors) return this;
    return ReaderColors(
      overlayBackground:
          Color.lerp(overlayBackground, other.overlayBackground, t)!,
      overlayTrack: Color.lerp(overlayTrack, other.overlayTrack, t)!,
      overlayFill: Color.lerp(overlayFill, other.overlayFill, t)!,
      overlayLabel: Color.lerp(overlayLabel, other.overlayLabel, t)!,
      overlayLabelSecondary:
          Color.lerp(overlayLabelSecondary, other.overlayLabelSecondary, t)!,
      overlaySavingIndicator:
          Color.lerp(overlaySavingIndicator, other.overlaySavingIndicator, t)!,
      noteBadge: Color.lerp(noteBadge, other.noteBadge, t)!,
    );
  }
}
