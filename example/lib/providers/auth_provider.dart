import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Wraps Supabase auth and exposes reactive state via ChangeNotifier.
class AuthProvider extends ChangeNotifier {
  AuthProvider() {
    // Listen to Supabase auth state changes and propagate them.
    Supabase.instance.client.auth.onAuthStateChange.listen((data) {
      notifyListeners();
    });
  }

  // ---------------------------------------------------------------------------
  // State
  // ---------------------------------------------------------------------------

  /// The currently authenticated Supabase user, or null if not signed in.
  User? get currentUser => Supabase.instance.client.auth.currentUser;

  bool get isLoggedIn => currentUser != null;

  // ---------------------------------------------------------------------------
  // Actions
  // ---------------------------------------------------------------------------

  /// Register a new user with [email] and [password].
  /// Returns the [AuthResponse]; throws [AuthException] on failure.
  Future<AuthResponse> signUp(String email, String password) async {
    final response = await Supabase.instance.client.auth.signUp(
      email: email,
      password: password,
    );
    notifyListeners();
    return response;
  }

  /// Sign in an existing user with [email] and [password].
  Future<AuthResponse> signIn(String email, String password) async {
    final response = await Supabase.instance.client.auth.signInWithPassword(
      email: email,
      password: password,
    );
    notifyListeners();
    return response;
  }

  /// Sign out the current user.
  Future<void> signOut() async {
    await Supabase.instance.client.auth.signOut();
    notifyListeners();
  }

  /// Refresh the current session (e.g. after app resume).
  Future<void> refreshSession() async {
    final session = Supabase.instance.client.auth.currentSession;
    if (session != null) {
      await Supabase.instance.client.auth.refreshSession();
      notifyListeners();
    }
  }

  /// Returns the current Supabase JWT access token, or null.
  String? get accessToken =>
      Supabase.instance.client.auth.currentSession?.accessToken;
}
