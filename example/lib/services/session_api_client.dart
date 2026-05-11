import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

/// HTTP client for Huda session lifecycle API calls.
///
/// All calls attach the current Supabase access token as Authorization header.
class SessionApiClient {
  final String baseUrl;

  const SessionApiClient({required this.baseUrl});

  // ---------------------------------------------------------------------------
  // Internal helpers
  // ---------------------------------------------------------------------------

  /// Returns the current Supabase JWT access token, or throws if not logged in.
  String _accessToken() {
    final token = Supabase.instance.client.auth.currentSession?.accessToken;
    if (token == null || token.isEmpty) {
      throw StateError('No active Supabase session – user must be logged in.');
    }
    return token;
  }

  Map<String, String> _authHeaders() => {
        'Authorization': 'Bearer ${_accessToken()}',
        'Content-Type': 'application/json',
      };

  // ---------------------------------------------------------------------------
  // Session endpoints
  // ---------------------------------------------------------------------------

  /// Prepare a new session: generates prompt, stores it, returns session info.
  Future<Map<String, dynamic>> prepareSession({
    String? targetDialectCode,
    String? translationLanguageCode,
  }) async {
    final body = <String, dynamic>{};
    if (targetDialectCode != null) body['target_dialect_code'] = targetDialectCode;
    if (translationLanguageCode != null) {
      body['translation_language_code'] = translationLanguageCode;
    }

    final response = await http.post(
      Uri.parse('$baseUrl/session/prepare'),
      headers: _authHeaders(),
      body: jsonEncode(body),
    );

    if (response.statusCode == 200 || response.statusCode == 201) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    }

    final detail = _errorDetail(response);
    throw Exception('Session prepare failed (${response.statusCode}): $detail');
  }

  /// Mark a session as started (LiveKit connected).
  Future<void> markStarted(String sessionId) async {
    final response = await http.post(
      Uri.parse('$baseUrl/session/$sessionId/started'),
      headers: _authHeaders(),
    );
    if (response.statusCode != 200 && response.statusCode != 201) {
      final detail = _errorDetail(response);
      throw Exception('Mark started failed (${response.statusCode}): $detail');
    }
  }

  /// Mark a session as ended.
  Future<void> markEnded(
    String sessionId, {
    String reason = 'user_ended',
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/session/$sessionId/ended'),
      headers: _authHeaders(),
      body: jsonEncode({'reason': reason}),
    );
    if (response.statusCode != 200 && response.statusCode != 201) {
      final detail = _errorDetail(response);
      throw Exception('Mark ended failed (${response.statusCode}): $detail');
    }
  }

  /// Fetch session events (session_evidence rows) for a session.
  Future<List<Map<String, dynamic>>> getSession(String sessionId) async {
    final response = await http.get(
      Uri.parse('$baseUrl/session/$sessionId'),
      headers: _authHeaders(),
    );
    if (response.statusCode == 200) {
      final list = jsonDecode(response.body) as List<dynamic>;
      return list.cast<Map<String, dynamic>>();
    }
    final detail = _errorDetail(response);
    throw Exception('Get session failed (${response.statusCode}): $detail');
  }

  /// Build the token URL for the LiveKit connection, including session params.
  String buildTokenUrl(String sessionId, String promptId) {
    final uri = Uri.parse('$baseUrl/token').replace(queryParameters: {
      'session_id': sessionId,
      'prompt_id': promptId,
    });
    return uri.toString();
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  String _errorDetail(http.Response resp) {
    try {
      final body = jsonDecode(resp.body) as Map<String, dynamic>;
      return body['detail']?.toString() ?? resp.body;
    } catch (_) {
      return resp.body;
    }
  }
}
