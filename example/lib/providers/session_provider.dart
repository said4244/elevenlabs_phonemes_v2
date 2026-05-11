import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/session_api_client.dart';

/// Holds the state of the current learning session and coordinates lifecycle calls.
///
/// Lifecycle:
///   1. [prepareSession] – call before showing CallPage; stores session_id + prompt_id.
///   2. [markStarted]   – call once LiveKit is connected.
///   3. [markEnded]     – call when the user ends the call.
///   4. [clearSession]  – call on logout or after navigating away from call flow.
class SessionProvider extends ChangeNotifier {
  final SessionApiClient _api;

  SessionProvider({required SessionApiClient api}) : _api = api;

  // ---------------------------------------------------------------------------
  // State
  // ---------------------------------------------------------------------------

  String? _sessionId;
  String? _promptId;
  String? _roomName;
  bool _isPreparing = false;
  String? _lastError;

  String? get currentSessionId => _sessionId;
  String? get currentPromptId => _promptId;
  String? get roomName => _roomName;
  bool get isPreparing => _isPreparing;
  String? get lastError => _lastError;
  bool get hasSession => _sessionId != null;

  // ---------------------------------------------------------------------------
  // Actions
  // ---------------------------------------------------------------------------

  /// Prepare a new session via [POST /session/prepare].
  ///
  /// Stores [sessionId], [promptId], and [roomName] on success.
  /// Returns `true` on success, `false` on failure (check [lastError]).
  Future<bool> prepareSession() async {
    _isPreparing = true;
    _lastError = null;
    notifyListeners();

    try {
      final data = await _api.prepareSession();
      _sessionId = data['session_id']?.toString();
      _promptId = data['prompt_id']?.toString();
      _roomName = data['room_name']?.toString();
      _lastError = null;
      return true;
    } catch (e) {
      _lastError = e.toString();
      debugPrint('[SessionProvider] prepareSession error: $e');
      return false;
    } finally {
      _isPreparing = false;
      notifyListeners();
    }
  }

  /// Mark the session as started (LiveKit connected).
  Future<void> markStarted() async {
    final id = _sessionId;
    if (id == null) return;
    try {
      await _api.markStarted(id);
    } catch (e) {
      debugPrint('[SessionProvider] markStarted error: $e');
    }
  }

  /// Mark the session as ended.
  Future<void> markEnded({String reason = 'user_ended'}) async {
    final id = _sessionId;
    if (id == null) return;
    try {
      await _api.markEnded(id, reason: reason);
    } catch (e) {
      debugPrint('[SessionProvider] markEnded error: $e');
    }
  }

  /// Build the full authenticated token URL for the LiveKit connection.
  ///
  /// Requires [prepareSession] to have succeeded first.
  /// Returns `null` if session is not prepared.
  String? buildTokenUrl() {
    final id = _sessionId;
    final pid = _promptId;
    if (id == null || pid == null) return null;
    return _api.buildTokenUrl(id, pid);
  }

  /// Returns Authorization headers for the token server HTTP call.
  Map<String, String> authHeaders() {
    final token = Supabase.instance.client.auth.currentSession?.accessToken ?? '';
    return {'Authorization': 'Bearer $token'};
  }

  /// Clear session state (call on logout or post-call cleanup).
  void clearSession() {
    _sessionId = null;
    _promptId = null;
    _roomName = null;
    _isPreparing = false;
    _lastError = null;
    notifyListeners();
  }
}
