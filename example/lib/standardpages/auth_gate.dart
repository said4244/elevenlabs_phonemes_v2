import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../data_providers/supabase_profile_service.dart';
import 'app_stack.dart';
import 'login_page.dart';
import 'onboarding_page.dart';

// ---------------------------------------------------------------------------
// Admin email set – add email addresses that should see the Admin button.
// ---------------------------------------------------------------------------
const Set<String> kAdminEmails = {
  'said444b@gmail.com',
  // Add more admin emails here during development.
};

/// Decides which top-level page to show based on Supabase auth and profile.
class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  final SupabaseProfileService _profileService = SupabaseProfileService();

  @override
  Widget build(BuildContext context) {
    // Listen to Supabase auth stream for real-time auth changes.
    return StreamBuilder<AuthState>(
      stream: Supabase.instance.client.auth.onAuthStateChange,
      builder: (context, snapshot) {
        // While waiting for the first auth event, show a splash.
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const _LoadingScreen();
        }

        final session = Supabase.instance.client.auth.currentSession;

        // No session → go to login.
        if (session == null) {
          return const LoginPage();
        }

        // Session exists → check if onboarding is complete.
        return FutureBuilder<SupabaseUserProfile?>(
          future: _profileService.getProfile(session.user.id),
          builder: (context, profileSnap) {
            if (profileSnap.connectionState == ConnectionState.waiting) {
              return const _LoadingScreen();
            }

            final profile = profileSnap.data;

            // No profile, or profile still marked as new → onboard.
            if (profile == null || profile.isNewUser) {
              return const OnboardingPage();
            }

            // Profile complete → show the app.
            return const AppStack();
          },
        );
      },
    );
  }
}

class _LoadingScreen extends StatelessWidget {
  const _LoadingScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: CircularProgressIndicator(color: Colors.white),
      ),
    );
  }
}
