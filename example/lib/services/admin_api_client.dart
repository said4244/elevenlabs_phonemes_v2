import 'dart:convert';
import 'package:http/http.dart' as http;

/// Calls the backend admin API endpoints.
/// All requests require a valid Supabase JWT (Bearer token).
class AdminApiClient {
  /// Base URL of the FastAPI backend, e.g. http://localhost:8080
  final String baseUrl;

  const AdminApiClient({required this.baseUrl});

  // ---------------------------------------------------------------------------
  // GET /admin/users
  // ---------------------------------------------------------------------------

  /// Returns a list of all users with their profile data.
  /// Each element has: id, email, created_at, profile (nullable).
  Future<List<Map<String, dynamic>>> listUsers(String accessToken) async {
    final uri = Uri.parse('$baseUrl/admin/users');
    final response = await http.get(
      uri,
      headers: {
        'Authorization': 'Bearer $accessToken',
        'Content-Type': 'application/json',
      },
    );

    if (response.statusCode != 200) {
      throw Exception(
        'GET /admin/users failed: ${response.statusCode} ${response.body}',
      );
    }

    final List<dynamic> data = jsonDecode(response.body) as List<dynamic>;
    return data.cast<Map<String, dynamic>>();
  }

  // ---------------------------------------------------------------------------
  // DELETE /admin/users/{user_id}
  // ---------------------------------------------------------------------------

  /// Deletes all data for [userId] (test-only – destructive and irreversible).
  Future<void> deleteUser(String userId, String accessToken) async {
    final uri = Uri.parse('$baseUrl/admin/users/$userId');
    final response = await http.delete(
      uri,
      headers: {
        'Authorization': 'Bearer $accessToken',
        'Content-Type': 'application/json',
      },
    );

    if (response.statusCode != 200 && response.statusCode != 204) {
      throw Exception(
        'DELETE /admin/users/$userId failed: '
        '${response.statusCode} ${response.body}',
      );
    }
  }

  // ---------------------------------------------------------------------------
  // GET /admin/users/{user_id}/sessions
  // ---------------------------------------------------------------------------

  Future<List<Map<String, dynamic>>> getUserSessions(
    String userId,
    String accessToken,
  ) async {
    final response = await http.get(
      Uri.parse('$baseUrl/admin/users/$userId/sessions'),
      headers: {'Authorization': 'Bearer $accessToken'},
    );
    if (response.statusCode != 200) {
      throw Exception(
        'GET /admin/users/$userId/sessions failed: ${response.statusCode} ${response.body}',
      );
    }
    return (jsonDecode(response.body) as List<dynamic>).cast<Map<String, dynamic>>();
  }

  // ---------------------------------------------------------------------------
  // GET /admin/sessions/{session_id}
  // ---------------------------------------------------------------------------

  Future<Map<String, dynamic>> getSessionDetail(
    String sessionId,
    String accessToken,
  ) async {
    final response = await http.get(
      Uri.parse('$baseUrl/admin/sessions/$sessionId'),
      headers: {'Authorization': 'Bearer $accessToken'},
    );
    if (response.statusCode != 200) {
      throw Exception(
        'GET /admin/sessions/$sessionId failed: ${response.statusCode} ${response.body}',
      );
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  // ---------------------------------------------------------------------------
  // GET /admin/prompts/{prompt_id}
  // ---------------------------------------------------------------------------

  Future<Map<String, dynamic>> getPrompt(
    String promptId,
    String accessToken,
  ) async {
    final response = await http.get(
      Uri.parse('$baseUrl/admin/prompts/$promptId'),
      headers: {'Authorization': 'Bearer $accessToken'},
    );
    if (response.statusCode != 200) {
      throw Exception(
        'GET /admin/prompts/$promptId failed: ${response.statusCode} ${response.body}',
      );
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  // ---------------------------------------------------------------------------
  // GET /admin/users/{user_id}/learning-state
  // ---------------------------------------------------------------------------

  Future<Map<String, dynamic>> getLearningState(
    String userId,
    String accessToken,
  ) async {
    final response = await http.get(
      Uri.parse('$baseUrl/admin/users/$userId/learning-state'),
      headers: {'Authorization': 'Bearer $accessToken'},
    );
    if (response.statusCode != 200) {
      throw Exception(
        'GET /admin/users/$userId/learning-state failed: ${response.statusCode} ${response.body}',
      );
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  // ---------------------------------------------------------------------------
  // POST /admin/sessions/{session_id}/analyze
  // ---------------------------------------------------------------------------

  Future<Map<String, dynamic>> analyzeSession(
    String sessionId,
    String accessToken,
  ) async {
    final response = await http.post(
      Uri.parse('$baseUrl/admin/sessions/$sessionId/analyze'),
      headers: {'Authorization': 'Bearer $accessToken'},
    );
    if (response.statusCode != 200 && response.statusCode != 201) {
      throw Exception(
        'POST /admin/sessions/$sessionId/analyze failed: ${response.statusCode} ${response.body}',
      );
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  // ---------------------------------------------------------------------------
  // DELETE /admin/users/{user_id}/learning-progress
  // ---------------------------------------------------------------------------

  /// Resets all learning progress for a user without deleting their account.
  Future<void> resetLearningProgress(
    String userId,
    String accessToken,
  ) async {
    final response = await http.delete(
      Uri.parse('$baseUrl/admin/users/$userId/learning-progress'),
      headers: {'Authorization': 'Bearer $accessToken'},
    );
    if (response.statusCode != 200 && response.statusCode != 204) {
      throw Exception(
        'DELETE /admin/users/$userId/learning-progress failed: ${response.statusCode} ${response.body}',
      );
    }
  }
}
