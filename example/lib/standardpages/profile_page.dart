import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';
import '../providers/user_profile_provider.dart';
import '../standardpages/admin_dashboard_page.dart';
import '../standardpages/auth_gate.dart';

// TODO: replace with real backend URL from config/env.
const String _kBackendBaseUrl = 'http://localhost:8080';

class ProfilePageContent extends StatefulWidget {
  const ProfilePageContent({super.key});

  @override
  State<ProfilePageContent> createState() => _ProfilePageContentState();
}

class _ProfilePageContentState extends State<ProfilePageContent> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<UserProfileProvider>().refreshUserIds();
    });
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<UserProfileProvider>();
    final profile = provider.profile;
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
            colors: [
              Color(0xFFFDD18E),
              Color(0xFF4B4B4B),
              Colors.black,
            ],
            stops: [0.0, 0.5, 1.0],
          ),
        ),
        child: Padding(
          padding: EdgeInsets.only(
            top: mediaPadding.top + 56 + 10,
            bottom: mediaPadding.bottom + 56 + 12,
          ),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const Text(
                'Available userIds:',
                style: TextStyle(color: Colors.white),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: provider.availableUserIds
                    .map(
                      (id) => ElevatedButton(
                        onPressed: () => provider.selectUser(id),
                        child: Text(id),
                      ),
                    )
                    .toList(),
              ),
              const SizedBox(height: 16),
              if (provider.isLoading) const LinearProgressIndicator(),
              const SizedBox(height: 16),
              Text(
                'Selected: ${provider.selectedUserId ?? '(none)'}',
                style: const TextStyle(color: Colors.white),
              ),
              const SizedBox(height: 12),
              if (profile != null) ...[
                Text(
                  'favSubjects: ${profile.favSubjects.join(', ')}',
                  style: const TextStyle(color: Colors.white),
                ),
                Text(
                  'languageLevel: ${profile.languageLevel}',
                  style: const TextStyle(color: Colors.white),
                ),
                Text(
                  'struggles: ${profile.struggles.join(', ')}',
                  style: const TextStyle(color: Colors.white),
                ),
                Text(
                  'strengths: ${profile.strengths.join(', ')}',
                  style: const TextStyle(color: Colors.white),
                ),
              ] else
                const Text(
                  'No profile loaded.',
                  style: TextStyle(color: Colors.white),
                ),
              const SizedBox(height: 24),
              // Admin button – only visible to emails in kAdminEmails.
              _AdminSection(),
            ],
          ),
        ),
      ),
    );
  }
}

/// Conditionally renders the admin dashboard button for admin users.
class _AdminSection extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final email = context.read<AuthProvider>().currentUser?.email ?? '';
    if (!kAdminEmails.contains(email)) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Divider(color: Colors.white24),
        const Text(
          '🛡 Admin',
          style: TextStyle(color: Colors.white54, fontSize: 12),
        ),
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
                  backendBaseUrl: _kBackendBaseUrl,
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}
