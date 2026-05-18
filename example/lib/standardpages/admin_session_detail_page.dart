import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';
import '../services/admin_api_client.dart';

/// Full session detail view for admin: evidence, prompt, transcript, analysis, plan.
class AdminSessionDetailPage extends StatefulWidget {
  final String sessionId;
  final String backendBaseUrl;

  const AdminSessionDetailPage({
    super.key,
    required this.sessionId,
    required this.backendBaseUrl,
  });

  @override
  State<AdminSessionDetailPage> createState() => _AdminSessionDetailPageState();
}

class _AdminSessionDetailPageState extends State<AdminSessionDetailPage> {
  late final AdminApiClient _api;
  Map<String, dynamic>? _detail;
  bool _isLoading = false;
  bool _isAnalyzing = false;
  String? _error;
  bool _promptExpanded = false;

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
      _detail = await _api.getSessionDetail(widget.sessionId, token);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _runAnalysis() async {
    setState(() => _isAnalyzing = true);
    try {
      final token = context.read<AuthProvider>().accessToken;
      if (token == null) throw Exception('Not authenticated');
      await _api.analyzeSession(widget.sessionId, token);
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Analysis failed: $e'), backgroundColor: Colors.red),
        );
        setState(() => _isAnalyzing = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Session: ${widget.sessionId.length > 16 ? widget.sessionId.substring(0, 16) : widget.sessionId}...',
        ),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
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

    if (_detail == null) return const SizedBox.shrink();

    final d = _detail!;
    final evidence = (d['evidence'] as List<dynamic>?)?.cast<Map<String, dynamic>>() ?? [];
    final transcript = d['transcript'] as Map<String, dynamic>?;
    final analysis = d['analysis'] as Map<String, dynamic>?;
    final prompt = d['prompt'] as Map<String, dynamic>?;
    final planItems = (d['learning_plan_items'] as List<dynamic>?)?.cast<Map<String, dynamic>>() ?? [];
    final user = d['user'] as Map<String, dynamic>? ?? {};
    final hasTranscript = transcript != null;
    final hasAnalysis = analysis != null;
    final messages = transcript != null
        ? ((transcript['messages'] as List<dynamic>?)
                ?.cast<Map<String, dynamic>>() ??
            [])
        : <Map<String, dynamic>>[];

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        // User info
        _sectionHeader('User'),
        Text('Email: ${user['email'] ?? 'unknown'}'),
        Text('ID: ${user['id'] ?? ''}', style: const TextStyle(fontSize: 11)),
        const SizedBox(height: 12),

        // Analyze button
        if (hasTranscript && !hasAnalysis) ...[
          ElevatedButton.icon(
            icon: _isAnalyzing
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.psychology),
            label: Text(_isAnalyzing ? 'Analyzing...' : 'Run AI Analysis'),
            onPressed: _isAnalyzing ? null : _runAnalysis,
          ),
          const SizedBox(height: 12),
        ],

        // Evidence timeline
        _sectionHeader('Evidence Timeline (${evidence.length} events)'),
        ...evidence.map((e) {
          final et = e['evidence_type'] as String? ?? '';
          final ts = e['created_at'] as String? ?? '';
          final excerpt = e['transcript_excerpt'] as String? ?? '';
          return Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.circle, size: 8),
                const SizedBox(width: 6),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(et, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                      Text(ts, style: const TextStyle(fontSize: 10, color: Colors.grey)),
                      if (excerpt.isNotEmpty)
                        Text(excerpt, style: const TextStyle(fontSize: 11)),
                    ],
                  ),
                ),
              ],
            ),
          );
        }),
        const SizedBox(height: 12),

        // Prompt
        if (prompt != null) ...[
          _sectionHeader('System Prompt'),
          Row(
            children: [
              Text(
                'Generated by: ${prompt['generated_by'] ?? 'unknown'}  '
                'v${prompt['prompt_version'] ?? '?'}',
                style: const TextStyle(fontSize: 12),
              ),
              const Spacer(),
              TextButton(
                onPressed: () => setState(() => _promptExpanded = !_promptExpanded),
                child: Text(_promptExpanded ? 'Collapse' : 'Expand'),
              ),
            ],
          ),
          if (_promptExpanded)
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                prompt['prompt_text'] as String? ?? '',
                style: const TextStyle(fontSize: 11, fontFamily: 'monospace'),
              ),
            )
          else
            Text(
              ((prompt['prompt_text'] as String?) ?? '').substring(
                0,
                ((prompt['prompt_text'] as String?) ?? '').length.clamp(0, 200),
              ) + (((prompt['prompt_text'] as String?) ?? '').length > 200 ? '...' : ''),
              style: const TextStyle(fontSize: 11, color: Colors.grey),
            ),
          const SizedBox(height: 12),
        ],

        // Transcript
        _sectionHeader('Transcript'),
        if (!hasTranscript)
          const Text('No transcript saved.', style: TextStyle(color: Colors.grey))
        else ...[
          ...messages.map((m) {
            final role = m['role'] as String? ?? 'unknown';
            final text = m['text'] as String? ?? '';
            final ts = m['timestamp'] as String? ?? '';
            final isAssistant = role == 'assistant';
            return Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 70,
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                    decoration: BoxDecoration(
                      color: isAssistant ? Colors.blue.shade100 : Colors.green.shade100,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      role,
                      style: TextStyle(
                        fontSize: 10,
                        color: isAssistant ? Colors.blue.shade800 : Colors.green.shade800,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(text, style: const TextStyle(fontSize: 13)),
                        if (ts.isNotEmpty)
                          Text(ts, style: const TextStyle(fontSize: 9, color: Colors.grey)),
                      ],
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
        const SizedBox(height: 12),

        // Analysis
        _sectionHeader('AI Analysis'),
        if (!hasAnalysis)
          const Text('No analysis available.', style: TextStyle(color: Colors.grey))
        else ...[
          _analysisRow('Level Score', analysis!['overall_level_score']?.toString() ?? 'N/A'),
          _analysisRow('Confidence', analysis['confidence']?.toString() ?? 'N/A'),
          _analysisRow('Summary', analysis['summary']?.toString() ?? ''),
          _analysisRow('Strengths', (analysis['strengths'] as List<dynamic>?)?.join(', ') ?? ''),
          _analysisRow('Struggles', (analysis['struggles'] as List<dynamic>?)?.join(', ') ?? ''),
          _analysisRow('Next Focus', analysis['suggested_next_focus']?.toString() ?? ''),
          _analysisRow('Level Recommendation', analysis['level_recommendation']?.toString() ?? 'N/A'),
        ],
        const SizedBox(height: 12),

        // Plan items
        if (planItems.isNotEmpty) ...[
          _sectionHeader('Learning Plan Items (${planItems.length})'),
          ...planItems.map((item) {
            final msa = item['msa'] as String? ?? '';
            final en = item['en'] as String? ?? '';
            final bucket = item['material_bucket'] as String? ?? '';
            return Padding(
              padding: const EdgeInsets.only(bottom: 3),
              child: Text(
                '• [$bucket] $msa — $en',
                style: const TextStyle(fontSize: 12),
              ),
            );
          }),
        ],
      ],
    );
  }

  Widget _sectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        title,
        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
      ),
    );
  }

  Widget _analysisRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 140,
            child: Text(label, style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 12)),
          ),
          Expanded(child: Text(value, style: const TextStyle(fontSize: 12))),
        ],
      ),
    );
  }
}
