import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Wraps Supabase auth and exposes reactive state via ChangeNotifier.
class AuthProvider extends ChangeNotifier {
  bool _isLoading = false;

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

  /// The current Supabase session, or null if not signed in.
  Session? get currentSession => Supabase.instance.client.auth.currentSession;

  bool get isLoggedIn => currentUser != null;

  /// True while an auth operation (sign-in, sign-up, sign-out) is in progress.
  bool get isLoading => _isLoading;

  // ---------------------------------------------------------------------------
  // Actions
  // ---------------------------------------------------------------------------

  /// Register a new user with [email] and [password].
  /// Returns the [AuthResponse]; throws [AuthException] on failure.
  Future<AuthResponse> signUp(String email, String password) async {
    _isLoading = true;
    notifyListeners();
    try {
      final response = await Supabase.instance.client.auth.signUp(
        email: email,
        password: password,
      );
      return response;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Sign in an existing user with [email] and [password].
  Future<AuthResponse> signIn(String email, String password) async {
    _isLoading = true;
    notifyListeners();
    try {
      final response = await Supabase.instance.client.auth.signInWithPassword(
        email: email,
        password: password,
      );
      return response;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Sign out the current user and clear any cached session state.
  Future<void> signOut() async {
    _isLoading = true;
    notifyListeners();
    try {
      await Supabase.instance.client.auth.signOut();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
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

