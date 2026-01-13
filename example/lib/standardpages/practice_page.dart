import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/user_profile_provider.dart';

class PracticePage extends StatefulWidget {
  const PracticePage({super.key});

  @override
  State<PracticePage> createState() => _PracticePageState();
}

class _PracticePageState extends State<PracticePage> {
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
      appBar: AppBar(title: const Text('Practice')),
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
