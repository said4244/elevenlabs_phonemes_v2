import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';
import '../services/admin_api_client.dart';
import 'admin_session_detail_page.dart';

/// Lists all sessions for a specific user, grouped from session_evidence rows.
class AdminSessionListPage extends StatefulWidget {
  final String userId;
  final String userEmail;
  final String backendBaseUrl;

  const AdminSessionListPage({
    super.key,
    required this.userId,
    required this.userEmail,
    required this.backendBaseUrl,
  });

  @override
  State<AdminSessionListPage> createState() => _AdminSessionListPageState();
}

class _AdminSessionListPageState extends State<AdminSessionListPage> {
  late final AdminApiClient _api;
  List<Map<String, dynamic>> _sessions = [];
  bool _isLoading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _api = AdminApiClient(baseUrl: widget.backendBaseUrl);
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final token = context.read<AuthProvider>().accessToken;
      if (token == null) throw Exception('Not authenticated');
      _sessions = await _api.getUserSessions(widget.userId, token);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'analyzed':
        return Colors.green;
      case 'ended':
        return Colors.blue;
      case 'started':
        return Colors.orange;
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Sessions: ${widget.userEmail}'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _load,
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) return const Center(child: CircularProgressIndicator());

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_error!, style: const TextStyle(color: Colors.red)),
              const SizedBox(height: 12),
              ElevatedButton(onPressed: _load, child: const Text('Retry')),
            ],
          ),
        ),
      );
    }

    if (_sessions.isEmpty) {
      return const Center(child: Text('No sessions found for this user.'));
    }

    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: _sessions.length,
      separatorBuilder: (_, __) => const Divider(),
      itemBuilder: (_, index) {
        final s = _sessions[index];
        final sessionId = s['session_id'] as String? ?? '';
        final status = s['status'] as String? ?? 'unknown';
        final evidenceCount = s['evidence_count'] as int? ?? 0;
        final preparedAt = s['prepared_at'] as String? ?? '';
        final endedAt = s['ended_at'] as String? ?? '';
        final dialectCode = s['dialect_code'] as String? ?? '';

        return ListTile(
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => AdminSessionDetailPage(
                sessionId: sessionId,
                backendBaseUrl: widget.backendBaseUrl,
              ),
            ),
          ),
          title: Text(
            sessionId.length > 20
                ? '${sessionId.substring(0, 20)}...'
                : sessionId,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
          ),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (preparedAt.isNotEmpty)
                Text('Prepared: $preparedAt', style: const TextStyle(fontSize: 11)),
              if (endedAt.isNotEmpty)
                Text('Ended: $endedAt', style: const TextStyle(fontSize: 11)),
              Text(
                'Dialect: $dialectCode  |  Events: $evidenceCount',
                style: const TextStyle(fontSize: 11),
              ),
            ],
          ),
          isThreeLine: true,
          trailing: Chip(
            label: Text(
              status,
              style: const TextStyle(fontSize: 11, color: Colors.white),
            ),
            backgroundColor: _statusColor(status),
            padding: EdgeInsets.zero,
          ),
        );
      },
    );
  }
}
