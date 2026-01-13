import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'data_providers/firebase_bootstrap.dart';
import 'data_providers/firestore_character_profile_service.dart';
import 'data_providers/firestore_user_profile_service.dart';
import 'data_providers/character_profile_service.dart';
import 'data_providers/user_profile_service.dart';
import 'providers/character_profile_provider.dart';
import 'providers/navigation_provider.dart';
import 'providers/user_profile_provider.dart';
import 'standardpages/app_stack.dart';

// Hardcoded admin flag - set to true to enable admin features
const bool adminLogin = false;
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final firebaseReady = await FirebaseBootstrap.isReady();
  runApp(AppRoot(firebaseReady: firebaseReady));
}

class AppRoot extends StatelessWidget {
  final bool firebaseReady;

  const AppRoot({
    super.key,
    required this.firebaseReady,
  });

  @override
  Widget build(BuildContext context) {
    final UserProfileService userProfileService = firebaseReady
        ? FirestoreUserProfileService()
        : InMemoryUserProfileService();

    final CharacterProfileService characterProfileService = firebaseReady
        ? FirestoreCharacterProfileService()
        : InMemoryCharacterProfileService();

    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => NavigationProvider()),
        ChangeNotifierProvider(
          create: (_) {
            final provider = UserProfileProvider(userProfileService);
            provider.refreshUserIds();
            return provider;
          },
        ),
        ChangeNotifierProvider(
          create: (_) {
            final provider = CharacterProfileProvider(characterProfileService);
            provider.refreshCharacterIds();
            return provider;
          },
        ),
      ],
      child: MaterialApp(
        title: 'Huda',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.green),
          useMaterial3: true,
        ),
        home: const AppStack(),
      ),
    );
  }
}
