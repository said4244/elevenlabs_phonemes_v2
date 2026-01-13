import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:rive/rive.dart';

import '../main.dart' show adminLogin;
import '../providers/navigation_provider.dart';
import '../providers/user_profile_provider.dart';
import '../data_providers/user_profile.dart';

class CallSuccessPage extends StatefulWidget {
  const CallSuccessPage({super.key});

  @override
  State<CallSuccessPage> createState() => _CallSuccessPageState();
}

class _CallSuccessPageState extends State<CallSuccessPage> {
  final _userIdController = TextEditingController();
  final _favSubjectsController = TextEditingController();
  final _languageLevelController = TextEditingController();
  final _strugglesController = TextEditingController();
  final _strengthsController = TextEditingController();

  bool _showAdminPanel = false;

  // Rive controller
  RiveWidgetController? _riveController;

  List<String> _parseCsv(String input) {
    return input
        .split(',')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
  }

  Future<void> _save() async {
    final userId = _userIdController.text.trim();
    if (userId.isEmpty) return;

    final profile = UserProfile(
      userId: userId,
      favSubjects: _parseCsv(_favSubjectsController.text),
      languageLevel: _languageLevelController.text.trim().isEmpty
          ? 'unknown'
          : _languageLevelController.text.trim(),
      struggles: _parseCsv(_strugglesController.text),
      strengths: _parseCsv(_strengthsController.text),
    );

    await context.read<UserProfileProvider>().save(profile);
  }

  Future<void> _onRiveInit() async {
    final file = await File.asset(
      'assets/callsuccess.riv',
      riveFactory: Factory.rive,
    );

    if (file == null) return;

    final controller = RiveWidgetController(
      file,
      stateMachineSelector: const StateMachineNamed('CallSuccessSM'),
    );

    setState(() {
      _riveController = controller;
    });
  }

  void _onRiveButtonTapped() {
    // Navigate to practice page
    context.read<NavigationProvider>().goTo(AppPage.practice);
  }

  @override
  void initState() {
    super.initState();
    _onRiveInit();
  }

  @override
  void dispose() {
    _userIdController.dispose();
    _favSubjectsController.dispose();
    _languageLevelController.dispose();
    _strugglesController.dispose();
    _strengthsController.dispose();
    _riveController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final userProvider = context.watch<UserProfileProvider>();

    // Show admin panel only if admin is logged in and clicked the + button
    if (adminLogin && _showAdminPanel) {
      return _buildAdminPanel(context, userProvider);
    }

    // Show frontend view
    return _buildFrontendView(context);
  }

  Widget _buildFrontendView(BuildContext context) {
    final mediaPadding = MediaQuery.paddingOf(context);
    final screenSize = MediaQuery.sizeOf(context);

    // Design dimensions
    const designWidth = 430.0;
    const designHeight = 932.0;

    // Calculate scale to fit screen while maintaining aspect ratio
    final scaleX = screenSize.width / designWidth;
    final scaleY = screenSize.height / designHeight;
    final scale = scaleX < scaleY ? scaleX : scaleY;

    return Stack(
      children: [
        Container(
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
          child: Center(
            child: Transform.scale(
              scale: scale,
              child: SizedBox(
                width: designWidth,
                height: designHeight,
                child: _riveController != null
                    ? GestureDetector(
                        onTapUp: (details) {
                          // Detect if tap is on the button area
                          // You may need to adjust these coordinates based on button position
                          _onRiveButtonTapped();
                        },
                        child: RiveWidget(
                          controller: _riveController!,
                          fit: Fit.contain,
                        ),
                      )
                    : const Center(child: CircularProgressIndicator()),
              ),
            ),
          ),
        ),
        if (adminLogin)
          Positioned(
            right: 16,
            bottom: mediaPadding.bottom + 56 + 16,
            child: FloatingActionButton(
              mini: true,
              backgroundColor: const Color(0xFF0CC0DF),
              onPressed: () => setState(() => _showAdminPanel = true),
              child: const Icon(Icons.add, color: Colors.white),
            ),
          ),
      ],
    );
  }

  Widget _buildAdminPanel(BuildContext context, UserProfileProvider userProvider) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Admin Panel - User Profile'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => setState(() => _showAdminPanel = false),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: ListView(
          children: [
            const Text('Save profile to verify Firebase'),
            const SizedBox(height: 12),
            TextField(
              controller: _userIdController,
              decoration: const InputDecoration(
                labelText: 'userId',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _favSubjectsController,
              decoration: const InputDecoration(
                labelText: 'favSubjects (comma separated)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _languageLevelController,
              decoration: const InputDecoration(
                labelText: 'languageLevel',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _strugglesController,
              decoration: const InputDecoration(
                labelText: 'struggles (comma separated)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _strengthsController,
              decoration: const InputDecoration(
                labelText: 'strengths (comma separated)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: userProvider.isLoading ? null : _save,
              child: Text(userProvider.isLoading ? 'Saving...' : 'Save'),
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                ElevatedButton(
                  onPressed: () {
                    context.read<NavigationProvider>().goTo(AppPage.practice);
                  },
                  child: const Text('Practice'),
                ),
                ElevatedButton(
                  onPressed: () {
                    context.read<NavigationProvider>().goTo(AppPage.fight);
                  },
                  child: const Text('Fight'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
