import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import '../firebase_options.dart';

class FirebaseBootstrap {
  static Future<FirebaseApp>? _initialization;

  static Future<FirebaseApp> ensureInitialized() {
    if (Firebase.apps.isNotEmpty) {
      return Future.value(Firebase.apps.first);
    }

    final existing = _initialization;
    if (existing != null) {
      return existing;
    }

    final future = _initializeApp();
    _initialization = future;
    return future;
  }

  static Future<bool> isReady() async {
    try {
      await ensureInitialized();
      return true;
    } catch (_) {
      return false;
    }
  }

  static Future<FirebaseApp> _initializeApp() async {
    try {
      return await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
    } catch (_) {
      _initialization = null;
      rethrow;
    }
  }
}
