import 'package:flutter/material.dart';

import '../../theme/design_tokens.dart';
import '../dnd/dnd_service.dart';
import '../reading_settings_controller.dart';

/// Opens the Reading Settings picker as a Material 3 modal bottom sheet.
///
/// ### Stability-pass fix — responsive on small screens
///
/// The previous version placed every `SwitchListTile` directly in an
/// unconstrained `Column` inside `showModalBottomSheet`. On short/small
/// devices, or with the OS text-scale factor increased (accessibility),
/// the combined intrinsic height of six rows plus the divider could
/// exceed the available sheet height, causing a bottom overflow (the
/// classic yellow-and-black stripes) and clipped content.
///
/// Fixed by:
/// - Bounding the sheet's max height to a fraction of the screen height
///   via `MediaQuery.sizeOf(context).height`, using `LayoutBuilder`/
///   `ConstrainedBox` rather than a fixed pixel value so it adapts to any
///   device size.
/// - Wrapping the switches in a `SingleChildScrollView` so, if content
///   still exceeds the bounded height (e.g. very large text scale), it
///   scrolls instead of overflowing.
/// - Using `MediaQuery.sizeOf` (not `MediaQuery.of(context).size`) to
///   avoid this widget rebuilding on *every* MediaQuery change (e.g.
///   keyboard insets) — `sizeOf` only depends on the screen size specifically.
Future<void> showReadingSettingsSheet({
  required BuildContext context,
  required ReadingSettingsController controller,
  required DndService dndService,
}) {
  return showModalBottomSheet<void>(
    context: context,
    useSafeArea: true,
    isScrollControlled: true,
    builder: (_) => _ReadingSettingsSheet(
      controller: controller,
      dndService: dndService,
    ),
  );
}

class _ReadingSettingsSheet extends StatelessWidget {
  const _ReadingSettingsSheet({
    required this.controller,
    required this.dndService,
  });

  final ReadingSettingsController controller;
  final DndService dndService;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final screenHeight = MediaQuery.sizeOf(context).height;

    return SafeArea(
      child: ConstrainedBox(
        // Bounded, not fixed: leaves at least ~10% of the screen visible
        // above the sheet on any device, and never forces a taller sheet
        // than its content actually needs (Column below is
        // MainAxisSize.min, so a short-content case doesn't stretch to
        // fill this max).
        constraints: BoxConstraints(maxHeight: screenHeight * 0.9),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.sm,
            AppSpacing.lg,
            AppSpacing.lg,
          ),
          child: ListenableBuilder(
            listenable: controller,
            builder: (context, _) {
              final settings = controller.value;
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Handle ──────────────────────────────────────────
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

                  Text('Reading Settings', style: tt.titleMedium),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    'Distraction-free reading, your way',
                    style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                  ),
                  const SizedBox(height: AppSpacing.md),

                  // ── Scrollable switches ─────────────────────────────
                  // Flexible + SingleChildScrollView: on a normal-size
                  // screen this never needs to scroll (content is shorter
                  // than the bounded max height above), but on a small
                  // device or with large text-scale it scrolls cleanly
                  // instead of overflowing.
                  Flexible(
                    child: SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            title: const Text('Immersive Reading Mode'),
                            subtitle: const Text(
                              'Hide the app bar and controls — tap the '
                              'page to show them again',
                            ),
                            secondary: const Icon(Icons.fullscreen_rounded),
                            value: settings.immersiveModeEnabled,
                            onChanged: (v) => controller.setImmersiveMode(v),
                          ),

                          SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            title: const Text('Auto-hide Controls'),
                            subtitle: Text(
                              settings.immersiveModeEnabled
                                  ? 'Controls fade out automatically while '
                                      'reading'
                                  : 'Only applies while Immersive Mode is on',
                            ),
                            secondary: const Icon(Icons.visibility_off_rounded),
                            value: settings.autoHideControlsEnabled,
                            onChanged: settings.immersiveModeEnabled
                                ? (v) => controller.setAutoHideControls(v)
                                : null,
                          ),

                          SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            title: const Text('Keep Screen Awake'),
                            subtitle: const Text(
                              'Prevent the screen from sleeping while '
                              'reading',
                            ),
                            secondary: const Icon(Icons.light_mode_outlined),
                            value: settings.keepScreenAwakeEnabled,
                            onChanged: (v) => controller.setKeepScreenAwake(v),
                          ),

                          const Divider(height: AppSpacing.xl),

                          SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            title: const Text('Do Not Disturb'),
                            subtitle: Text(dndService.capability.reason),
                            secondary: Icon(
                              Icons.do_not_disturb_on_outlined,
                              color: cs.onSurfaceVariant,
                            ),
                            value: false,
                            onChanged: null, // not usable yet
                          ),
                          Padding(
                            padding:
                                const EdgeInsets.only(left: AppSpacing.xxl + 8),
                            child:
                                _DndBadge(level: dndService.capability.level),
                          ),
                          // Bottom breathing room so the last row/badge
                          // never sits flush against the scroll edge.
                          const SizedBox(height: AppSpacing.sm),
                        ],
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _DndBadge extends StatelessWidget {
  const _DndBadge({required this.level});
  final DndSupportLevel level;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final label = switch (level) {
      DndSupportLevel.comingSoon => 'Coming soon',
      DndSupportLevel.notSupported => 'Not supported on this platform',
      DndSupportLevel.partialSupport => 'Partially supported',
      DndSupportLevel.fullSupport => 'Supported',
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Text(
        label,
        style: tt.labelSmall?.copyWith(color: cs.onSurfaceVariant),
      ),
    );
  }
}
