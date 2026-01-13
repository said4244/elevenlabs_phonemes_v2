import 'package:firebase_core/firebase_core.dart';
import '../firebase_options.dart';

class FirebaseBootstrap {
  static Future<FirebaseApp?> ensureInitialized() async {
    try {
      return await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
    } catch (_) {
      return null;
    }
  }

  static Future<bool> isReady() async {
    final app = await ensureInitialized();
    return app != null;
  }
}
