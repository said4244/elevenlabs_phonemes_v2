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
}
