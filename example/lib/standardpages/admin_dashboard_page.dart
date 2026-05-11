import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';
import '../services/admin_api_client.dart';

/// Admin dashboard for viewing all users and deleting test accounts.
///
/// ⚠️  TEST-ONLY: The delete operation is intentionally destructive and
/// permanently removes all data for a user from the database.
/// This page is only reachable for emails listed in kAdminEmails.
class AdminDashboardPage extends StatefulWidget {
  /// Base URL of the FastAPI backend.
  final String backendBaseUrl;

  const AdminDashboardPage({
    super.key,
    required this.backendBaseUrl,
  });

  @override
  State<AdminDashboardPage> createState() => _AdminDashboardPageState();
}

class _AdminDashboardPageState extends State<AdminDashboardPage> {
  late final AdminApiClient _api;

  List<Map<String, dynamic>> _users = [];
  bool _isLoading = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _api = AdminApiClient(baseUrl: widget.backendBaseUrl);
    _loadUsers();
  }

  // ---------------------------------------------------------------------------
  // Data loading
  // ---------------------------------------------------------------------------

  Future<void> _loadUsers() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final token = context.read<AuthProvider>().accessToken;
      if (token == null) throw Exception('Not authenticated');
      _users = await _api.listUsers(token);
    } catch (e) {
      if (mounted) setState(() => _errorMessage = e.toString());
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ---------------------------------------------------------------------------
  // Delete
  // ---------------------------------------------------------------------------

  Future<void> _deleteUser(String userId, String email) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete user?'),
        content: Text(
          '⚠️  TEST-ONLY: This will permanently delete all data for\n'
          '$email\n\n'
          'This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() => _isLoading = true);
    try {
      final token = context.read<AuthProvider>().accessToken;
      if (token == null) throw Exception('Not authenticated');
      await _api.deleteUser(userId, token);
      await _loadUsers();
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Admin Dashboard'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadUsers,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: Builder(builder: (context) {
        if (_isLoading) {
          return const Center(child: CircularProgressIndicator());
        }

        if (_errorMessage != null) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _errorMessage!,
                    style: const TextStyle(color: Colors.red),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: _loadUsers,
                    child: const Text('Retry'),
                  ),
                ],
              ),
            ),
          );
        }

        if (_users.isEmpty) {
          return const Center(child: Text('No users found.'));
        }

        return ListView.separated(
          padding: const EdgeInsets.all(12),
          itemCount: _users.length,
          separatorBuilder: (_, __) => const Divider(),
          itemBuilder: (_, index) {
            final user = _users[index];
            final userId = user['id'] as String? ?? '';
            final email = user['email'] as String? ?? '(unknown)';
            final createdAt = user['created_at'] as String? ?? '';
            final profile = user['profile'] as Map<String, dynamic>?;
            final onboarded = profile != null &&
                (profile['is_new_user'] as bool?) == false;

            return ListTile(
              title: Text(email),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('ID: $userId', style: const TextStyle(fontSize: 11)),
                  Text(
                    'Created: $createdAt',
                    style: const TextStyle(fontSize: 11),
                  ),
                  Text(
                    'Onboarded: ${onboarded ? 'Yes' : 'No'}',
                    style: TextStyle(
                      fontSize: 11,
                      color: onboarded ? Colors.green : Colors.orange,
                    ),
                  ),
                ],
              ),
              isThreeLine: true,
              trailing: IconButton(
                icon: const Icon(Icons.delete_forever, color: Colors.red),
                tooltip: 'Delete all data (TEST ONLY)',
                onPressed: () => _deleteUser(userId, email),
              ),
            );
          },
        );
      }),
    );
  }
}
