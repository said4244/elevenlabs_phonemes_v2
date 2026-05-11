import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../data_providers/supabase_profile_service.dart';
import '../main.dart' show kBackendBaseUrl;
import '../providers/auth_provider.dart';
import '../providers/navigation_provider.dart';
import '../providers/session_provider.dart';
import '../standardpages/admin_dashboard_page.dart';
import '../standardpages/auth_gate.dart';
import '../standardpages/onboarding_page.dart';

// Keep in sync with auth_gate.dart
const Set<String> _kAdminEmails = kAdminEmails;

class ProfilePageContent extends StatefulWidget {
  const ProfilePageContent({super.key});

  @override
  State<ProfilePageContent> createState() => _ProfilePageContentState();
}

class _ProfilePageContentState extends State<ProfilePageContent> {
  final SupabaseProfileService _profileService = SupabaseProfileService();

  SupabaseUserProfile? _profile;
  bool _isLoading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    final userId = context.read<AuthProvider>().currentUser?.id;
    if (userId == null) return;

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final p = await _profileService.getProfile(userId);
      if (mounted) setState(() => _profile = p);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _logout() async {
    // End any active session gracefully before signing out
    final sessionProv = context.read<SessionProvider>();
    if (sessionProv.hasSession) {
      await sessionProv.markEnded(reason: 'logout');
      sessionProv.clearSession();
    }

    await context.read<AuthProvider>().signOut();
    // AuthGate listens to onAuthStateChange and will rebuild to LoginPage.
    // Also push-replace in case we are inside a Navigator stack.
    if (mounted) {
      Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
        MaterialPageRoute<void>(builder: (_) => const AuthGate()),
        (_) => false,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final user = auth.currentUser;
    final mediaPadding = MediaQuery.paddingOf(context);

    return Material(
      type: MaterialType.transparency,
      child: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFFDD18E), Color(0xFF4B4B4B), Colors.black],
            stops: [0.0, 0.5, 1.0],
          ),
        ),
        child: Padding(
          padding: EdgeInsets.only(
            top: mediaPadding.top + 56 + 10,
            bottom: mediaPadding.bottom + 56 + 12,
          ),
          child: user == null
              ? _buildLoggedOutFallback()
              : _buildProfileBody(user),
        ),
      ),
    );
  }

  Widget _buildLoggedOutFallback() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'You are not logged in.',
            style: TextStyle(color: Colors.white, fontSize: 16),
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: _logout,
            child: const Text('Go to Login'),
          ),
        ],
      ),
    );
  }

  Widget _buildProfileBody(User user) {
    final profile = _profile;
    final prefs = profile?.learnerPreferences ?? {};

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      children: [
        // Header
        Row(
          children: [
            const CircleAvatar(
              radius: 28,
              backgroundColor: Color(0xFFFDD18E),
              child: Icon(Icons.person, size: 30, color: Colors.black87),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    (prefs['name'] as String?)?.isNotEmpty == true
                        ? prefs['name'] as String
                        : 'Huda Learner',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    user.email ?? '',
                    style: const TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                ],
              ),
            ),
          ],
        ),

        const SizedBox(height: 24),

        // Loading / Error / Missing states
        if (_isLoading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(child: CircularProgressIndicator(color: Colors.white)),
          )
        else if (_error != null)
          _InfoCard(title: 'Error loading profile', content: _error!, isError: true)
        else if (profile == null)
          const _InfoCard(
            title: 'Profile not found',
            content: 'Onboarding may not be complete.',
          )
        else ...[
          _SectionHeader('Account'),
          _ProfileRow('User ID', user.id),
          _ProfileRow('Email', user.email ?? '—'),

          const SizedBox(height: 8),
          _SectionHeader('Learning Profile'),
          _ProfileRow('Current Level', '${profile.currentLevel} / 5'),
          _ProfileRow('Target Dialect', profile.targetDialectCode),
          _ProfileRow('Translation Language', profile.translationLanguageCode),
          _ProfileRow('Age', profile.age > 0 ? '${profile.age}' : '—'),

          const SizedBox(height: 8),
          _SectionHeader('Preferences'),
          _ProfileRow(
            'Learning Goal',
            (prefs['learning_goal'] as String?)?.isNotEmpty == true
                ? prefs['learning_goal'] as String
                : '—',
          ),
          _ProfileRow('Interests', _formatList(prefs['interests'])),
          _ProfileRow('Preferred Style', (prefs['preferred_style'] as String?) ?? '—'),
          _ProfileRow(
            'Challenge Preference',
            (prefs['challenge_preference'] as String?) ?? '—',
          ),
        ],

        const SizedBox(height: 20),

        // Action buttons
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('Refresh'),
                style: OutlinedButton.styleFrom(foregroundColor: Colors.white),
                onPressed: _isLoading ? null : _loadProfile,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: OutlinedButton.icon(
                icon: const Icon(Icons.edit, size: 18),
                label: const Text('Edit Profile'),
                style: OutlinedButton.styleFrom(foregroundColor: Colors.white),
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => const OnboardingPage()),
                ),
              ),
            ),
          ],
        ),

        const SizedBox(height: 12),

        // Logout
        ElevatedButton.icon(
          icon: const Icon(Icons.logout),
          label: const Text('Logout'),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.redAccent,
            foregroundColor: Colors.white,
            minimumSize: const Size.fromHeight(48),
          ),
          onPressed: _logout,
        ),

        const SizedBox(height: 24),

        // Admin section
        _AdminSection(),
      ],
    );
  }

  String _formatList(dynamic value) {
    if (value == null) return '—';
    if (value is List) return value.isEmpty ? '—' : value.join(', ');
    return value.toString();
  }
}

// ---------------------------------------------------------------------------
// Helper widgets
// ---------------------------------------------------------------------------

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader(this.title);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 4),
      child: Text(
        title.toUpperCase(),
        style: const TextStyle(
          color: Color(0xFFFDD18E),
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.2,
        ),
      ),
    );
  }
}

class _ProfileRow extends StatelessWidget {
  final String label;
  final String value;
  const _ProfileRow(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 160,
            child: Text(label, style: const TextStyle(color: Colors.white54, fontSize: 13)),
          ),
          Expanded(
            child: Text(value, style: const TextStyle(color: Colors.white, fontSize: 13)),
          ),
        ],
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  final String title;
  final String content;
  final bool isError;

  const _InfoCard({required this.title, required this.content, this.isError = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isError ? Colors.redAccent.withAlpha(40) : Colors.white.withAlpha(20),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: isError ? Colors.redAccent : Colors.white24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              color: isError ? Colors.redAccent : Colors.white70,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 6),
          Text(content, style: const TextStyle(color: Colors.white70)),
        ],
      ),
    );
  }
}

/// Conditionally renders the admin dashboard button for admin users.
class _AdminSection extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final email = context.read<AuthProvider>().currentUser?.email ?? '';
    if (!_kAdminEmails.contains(email)) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Divider(color: Colors.white24),
        const Text('🛡 Admin', style: TextStyle(color: Colors.white54, fontSize: 12)),
        const SizedBox(height: 8),
        ElevatedButton.icon(
          icon: const Icon(Icons.admin_panel_settings),
          label: const Text('Open Admin Dashboard'),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.deepOrange,
            foregroundColor: Colors.white,
          ),
          onPressed: () {
            Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const AdminDashboardPage(
                  backendBaseUrl: kBackendBaseUrl,
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}
