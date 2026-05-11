import '../controllers/rive_lipsync_controller.dart';

class RiveAvatarCache {
  static Future<RiveLipSyncController>? _talkingInit;
  static RiveLipSyncController? _talking;

  static Future<RiveLipSyncController> getTalkingController() {
    final existing = _talking;
    if (existing != null && existing.isReady) {
      return Future.value(existing);
    }

    final inFlight = _talkingInit;
    if (inFlight != null) return inFlight;

    final controller = RiveLipSyncController(
      assetPath: 'assets/huda-character.riv',
    );

    final initFuture = controller.init().then((_) {
      _talking = controller;
      return controller;
    }).catchError((error) {
      if (identical(_talking, controller)) {
        _talking = null;
      }
      throw error;
    }).whenComplete(() {
      _talkingInit = null;
    });

    _talkingInit = initFuture;
    return initFuture;
  }
}
