import 'dnd_service.dart';

/// No-op [DndService] implementation for platforms with no usable Do Not
/// Disturb integration: does nothing, and is honest about why via
/// [capability].
///
/// Used by [DndServiceProvider.create] for iOS and every non-Android
/// platform; Android resolves to `AndroidDndService` instead (see
/// `dnd_service.dart`).
///
/// **Bug fix (final Reader-integration pass):** [checkPermission]
/// previously threw `UnimplementedError()`. It happened to never be
/// called in practice because every caller already short-circuits on
/// `capability.isUsable == false` first — but that made it a latent
/// crash risk for any future or third-party call site, and directly
/// contradicts this class's own "no-op, never usable" contract. It now
/// simply returns `false`, consistent with [capability] always reporting
/// [DndSupportLevel.notSupported] wherever this class is used.
class UnsupportedDndService implements DndService {
  const UnsupportedDndService(this.capability);

  @override
  final DndCapability capability;

  @override
  Future<bool> requestAccess() async => false;

  @override
  Future<bool> checkPermission() async => false;

  @override
  Future<int?> getCurrentInterruptionFilter() async => null;

  @override
  Future<void> enable() async {}

  @override
  Future<void> disable({int? restoreFilter}) async {}

  @override
  void dispose() {}
}
