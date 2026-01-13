// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:html' as html;

class MicPermissionService {
  static Future<bool> requestMicrophone() async {
    try {
      final stream = await html.window.navigator.mediaDevices
          ?.getUserMedia({'audio': true});
      if (stream == null) return false;

      for (final track in stream.getTracks()) {
        track.stop();
      }

      return true;
    } catch (_) {
      return false;
    }
  }
}
