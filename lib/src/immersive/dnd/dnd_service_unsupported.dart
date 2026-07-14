import 'dnd_service.dart';

/// No-op [DndService] implementation for platforms with no usable Do Not
/// Disturb integration: does nothing, and is honest about why via
/// [capability].
///
/// Unchanged from Phase 3A. Used by [DndServiceProvider.create] for iOS
/// and every non-Android platform; Android now resolves to
/// `AndroidDndService` instead (see `dnd_service.dart`).
class UnsupportedDndService implements DndService {
  const UnsupportedDndService(this.capability);

  @override
  final DndCapability capability;

  @override
  Future<bool> requestAccess() async => false;

  @override
  Future<void> enable() async {}

  @override
  Future<void> disable() async {}

  @override
  void dispose() {}

  @override
  Future<bool> checkPermission() {
    // TODO: implement checkPermission
    throw UnimplementedError();
  }
}
