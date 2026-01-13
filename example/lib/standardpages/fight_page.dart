import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/user_profile_provider.dart';

class FightPage extends StatefulWidget {
  const FightPage({super.key});

  @override
  State<FightPage> createState() => _FightPageState();
}

class _FightPageState extends State<FightPage> {
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

    return Scaffold(
      appBar: AppBar(title: const Text('Fight')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: ListView(
          children: [
            const Text('Available userIds:'),
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
            Text('Selected: ${provider.selectedUserId ?? '(none)'}'),
            const SizedBox(height: 12),
            if (profile != null) ...[
              Text('favSubjects: ${profile.favSubjects.join(', ')}'),
              Text('languageLevel: ${profile.languageLevel}'),
              Text('struggles: ${profile.struggles.join(', ')}'),
              Text('strengths: ${profile.strengths.join(', ')}'),
            ] else
              const Text('No profile loaded.'),
          ],
        ),
      ),
    );
  }
}
