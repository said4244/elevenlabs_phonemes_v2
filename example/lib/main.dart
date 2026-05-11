import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'config/supabase_config.dart';
import 'data_providers/firebase_bootstrap.dart';
import 'data_providers/firestore_character_profile_service.dart';
import 'data_providers/firestore_user_profile_service.dart';
import 'providers/auth_provider.dart';
import 'providers/character_profile_provider.dart';
import 'providers/navigation_provider.dart';
import 'providers/user_profile_provider.dart';
import 'standardpages/auth_gate.dart';

// Legacy admin flag used by CallPage / CharactersPage / CallSuccessPage.
// The new admin dashboard (AdminDashboardPage) supersedes this for user mgmt.
// Set to true only during local development to enable the old admin panels.
const bool adminLogin = false;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Supabase (auth + database for this MVP).
  await Supabase.initialize(
    url: SupabaseConfig.url,
    anonKey: SupabaseConfig.anonKey,
  );

  // Firebase still initialized for character profiles (not removed yet).
  await _initializeFirebase();

  runApp(const AppRoot());
}

Future<void> _initializeFirebase() async {
  try {
    await FirebaseBootstrap.ensureInitialized();
  } catch (error, stackTrace) {
    FlutterError.reportError(
      FlutterErrorDetails(
        exception: error,
        stack: stackTrace,
        library: 'firebase_bootstrap',
        context: ErrorDescription('while initializing Firebase'),
      ),
    );
  }
}

class AppRoot extends StatelessWidget {
  const AppRoot({super.key});

  @override
  Widget build(BuildContext context) {
    final userProfileService = FirestoreUserProfileService();
    final characterProfileService = FirestoreCharacterProfileService();

    return MultiProvider(
      providers: [
        // Supabase auth state.
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        // Existing providers kept intact.
        ChangeNotifierProvider(create: (_) => NavigationProvider()),
        ChangeNotifierProvider(
          create: (_) => UserProfileProvider(userProfileService),
        ),
        ChangeNotifierProvider(
          create: (_) => CharacterProfileProvider(characterProfileService),
        ),
      ],
      child: MaterialApp(
        title: 'Huda',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.green),
          useMaterial3: true,
        ),
        // AuthGate replaces direct AppStack as the entry point.
        home: const AuthGate(),
      ),
    );
  }
}
