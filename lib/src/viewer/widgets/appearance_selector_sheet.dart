import 'package:flutter/material.dart';

import '../../theme/appearance_mode.dart';
import '../../theme/design_tokens.dart';

/// Opens the Appearance picker as a Material 3 modal bottom sheet.
///
/// Mirrors the calling convention of the other sheets in this package
/// (`bookmarks_sheet.dart`, `highlights_sheet.dart`, `notes_sheet.dart`):
/// tap an icon → get a bottom sheet → pick → sheet closes. Reusing that
/// interaction language keeps Appearance consistent with the rest of the
/// reader chrome instead of introducing a new pattern (e.g. a cycling
/// icon button, which hides two of the three options at any given time).
///
/// Uses [SegmentedButton] — a Material 3 component purpose-built for a
/// small, mutually-exclusive option set like this.
Future<void> showAppearanceSelectorSheet({
  required BuildContext context,
  required AppearanceMode current,
  required ValueChanged<AppearanceMode> onSelected,
}) {
  return showModalBottomSheet<void>(
    context: context,
    useSafeArea: true,
    builder: (_) => _AppearanceSelectorSheet(
      current: current,
      onSelected: onSelected,
    ),
  );
}

class _AppearanceSelectorSheet extends StatelessWidget {
  const _AppearanceSelectorSheet({
    required this.current,
    required this.onSelected,
  });

  final AppearanceMode current;
  final ValueChanged<AppearanceMode> onSelected;

  static const List<(AppearanceMode, IconData, String)> _options = [
    (AppearanceMode.light, Icons.light_mode_rounded, 'Light'),
    (AppearanceMode.dark, Icons.dark_mode_rounded, 'Dark'),
    (AppearanceMode.system, Icons.brightness_auto_rounded, 'System'),
  ];

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.sm,
          AppSpacing.lg,
          AppSpacing.lg,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Handle ──────────────────────────────────────────────
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: AppSpacing.md),
                decoration: BoxDecoration(
                  color: cs.outlineVariant,
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                ),
              ),
            ),

            Text('Appearance', style: tt.titleMedium),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Choose how the reader looks',
              style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: AppSpacing.lg),

            // ── Options ─────────────────────────────────────────────
            SegmentedButton<AppearanceMode>(
              segments: _options
                  .map((o) => ButtonSegment(
                value: o.$1,
                icon: Icon(o.$2, size: 18),
                label: Text(o.$3),
              ))
                  .toList(growable: false),
              selected: {current},
              showSelectedIcon: false,
              onSelectionChanged: (selection) {
                onSelected(selection.first);
                Navigator.of(context).pop();
              },
            ),
          ],
        ),
      ),
    );
  }
}