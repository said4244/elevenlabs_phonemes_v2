import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'dart:math' as math;

import '../main.dart' show adminLogin;
import '../data_providers/character_profile.dart';
import '../providers/character_profile_provider.dart';

class CharactersPageContent extends StatefulWidget {
  const CharactersPageContent({super.key});

  @override
  State<CharactersPageContent> createState() => _CharactersPageContentState();
}

class _CharactersPageContentState extends State<CharactersPageContent> {
  final _characterIdController = TextEditingController();
  final _nameController = TextEditingController();
  final _roleTitleController = TextEditingController();
  final _oneLineMissionController = TextEditingController();
  final _targetUserController = TextEditingController();
  final _domainScopeController = TextEditingController();
  final _voiceIdController = TextEditingController();
  final _defaultStrategyController = TextEditingController();
  final _hardBoundariesController = TextEditingController();
  final _coreValuesController = TextEditingController();
  final _expertiseLevelController = TextEditingController();

  bool _showAvatars = false;
  bool _showAdminPanel = false;

  int _warmth = 5;
  int _directness = 5;
  int _humor = 5;
  int _formality = 5;
  int _energy = 5;
  int _creativity = 5;
  int _assertiveness = 5;

  List<String> _parseCsv(String input) {
    return input
        .split(',')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
  }

  void _applyProfileToForm(CharacterProfile profile) {
    _characterIdController.text = profile.characterId;
    _nameController.text = profile.name;
    _roleTitleController.text = profile.roleTitle;
    _oneLineMissionController.text = profile.oneLineMission;
    _targetUserController.text = profile.targetUser;
    _domainScopeController.text = profile.domainScope;
    _voiceIdController.text = profile.voiceId;
    _defaultStrategyController.text = profile.defaultStrategy;
    _hardBoundariesController.text = profile.hardBoundaries.join(', ');
    _coreValuesController.text = profile.coreValues.join(', ');
    _expertiseLevelController.text = profile.expertiseLevel;

    setState(() {
      _warmth = profile.warmth;
      _directness = profile.directness;
      _humor = profile.humor;
      _formality = profile.formality;
      _energy = profile.energy;
      _creativity = profile.creativity;
      _assertiveness = profile.assertiveness;
    });
  }

  Future<void> _save() async {
    final id = _characterIdController.text.trim();
    if (id.isEmpty) return;

    final profile = CharacterProfile(
      characterId: id,
      name: _nameController.text.trim(),
      roleTitle: _roleTitleController.text.trim(),
      oneLineMission: _oneLineMissionController.text.trim(),
      targetUser: _targetUserController.text.trim(),
      domainScope: _domainScopeController.text.trim(),
      warmth: _warmth,
      directness: _directness,
      humor: _humor,
      formality: _formality,
      energy: _energy,
      creativity: _creativity,
      assertiveness: _assertiveness,
      voiceId: _voiceIdController.text.trim(),
      defaultStrategy: _defaultStrategyController.text.trim(),
      hardBoundaries: _parseCsv(_hardBoundariesController.text),
      coreValues: _parseCsv(_coreValuesController.text),
      expertiseLevel: _expertiseLevelController.text.trim(),
    );

    await context.read<CharacterProfileProvider>().save(profile);
  }

  @override
  void dispose() {
    _characterIdController.dispose();
    _nameController.dispose();
    _roleTitleController.dispose();
    _oneLineMissionController.dispose();
    _targetUserController.dispose();
    _domainScopeController.dispose();
    _voiceIdController.dispose();
    _defaultStrategyController.dispose();
    _hardBoundariesController.dispose();
    _coreValuesController.dispose();
    _expertiseLevelController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final characterProvider = context.watch<CharacterProfileProvider>();

    final ids = characterProvider.availableCharacterIds;
    final selected = characterProvider.selected;

    if (selected != null && _characterIdController.text.trim().isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _applyProfileToForm(selected);
      });
    }

    // Show admin panel only if admin is logged in and clicked the + button
    if (adminLogin && _showAdminPanel) {
      return _buildAdminPanel(context, characterProvider, ids);
    }

    // Show frontend view
    return _buildFrontendView(context);
  }

  Widget _buildFrontendView(BuildContext context) {
    final mediaPadding = MediaQuery.paddingOf(context);
    final screenHeight = MediaQuery.sizeOf(context).height;
    final topSpacing = mediaPadding.top + 56 + 10;

    // Calculate the height of the top section (hamza profile + spacing)
    const hamzaProfileHeight = 225.0;
    const topSectionPadding = 8.0;
    final topSectionHeight =
        topSpacing + topSectionPadding + hamzaProfileHeight + topSpacing;

    // Minimum height for the dark section to fill remaining screen space (to bottom of screen)
    final minDarkSectionHeight = screenHeight - topSectionHeight;

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
          child: SingleChildScrollView(
            padding: EdgeInsets.only(
              top: topSpacing,
            ),
            child: Column(
              children: [
                const SizedBox(height: 8),
                LayoutBuilder(
                  builder: (context, constraints) {
                    // 25% smaller than main_page (300 * 0.75 = 225)
                    final target = 225.0;
                    final width = math.min(target, constraints.maxWidth);
                    return SvgPicture.asset(
                      'assets/images/hamza_profile.svg',
                      width: width,
                    );
                  },
                ),
                // Space equal to the space between hamza_profile and top app bar
                SizedBox(height: topSpacing),
                // Dark section with character profiles
                Container(
                  width: double.infinity,
                  constraints: BoxConstraints(
                    minHeight: minDarkSectionHeight,
                  ),
                  color: const Color(0xFF232323),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 24,
                  ),
                  child: Column(
                    children: [
                      // Row 1: ali_profile, 2x common_profile
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          _buildProfileAvatar('assets/images/ali_profile.svg'),
                          _buildProfileAvatar('assets/images/common_profile.svg'),
                          _buildProfileAvatar('assets/images/common_profile.svg'),
                        ],
                      ),
                      const SizedBox(height: 16),
                      // Row 2: 3x rare_profile
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          _buildProfileAvatar('assets/images/rare_profile.svg'),
                          _buildProfileAvatar('assets/images/rare_profile.svg'),
                          _buildProfileAvatar('assets/images/rare_profile.svg'),
                        ],
                      ),
                      const SizedBox(height: 16),
                      // Row 3: 3x legend_profile
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          _buildProfileAvatar('assets/images/legend_profile.svg'),
                          _buildProfileAvatar('assets/images/legend_profile.svg'),
                          _buildProfileAvatar('assets/images/legend_profile.svg'),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
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

  Widget _buildProfileAvatar(String assetPath) {
    return SvgPicture.asset(
      assetPath,
      width: 112,
      height: 112,
    );
  }

  Widget _buildAdminPanel(
    BuildContext context,
    CharacterProfileProvider characterProvider,
    List<String> ids,
  ) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Admin Panel'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => setState(() => _showAdminPanel = false),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: ListView(
          children: [
            Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: () {
                      setState(() => _showAvatars = !_showAvatars);
                      if (!_showAvatars) return;
                      context
                          .read<CharacterProfileProvider>()
                          .refreshCharacterIds();
                    },
                    child: Text(_showAvatars ? 'Hide avatars' : 'Show avatars'),
                  ),
                ),
              ],
            ),
            if (_showAvatars) ...[
              const SizedBox(height: 12),
              if (characterProvider.isLoading)
                const Center(child: CircularProgressIndicator()),
              if (!characterProvider.isLoading && ids.isEmpty)
                const Text('No characters found in global collection.'),
              if (ids.isNotEmpty)
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final id in ids)
                      OutlinedButton(
                        onPressed: () async {
                          final provider = context.read<CharacterProfileProvider>();
                          await provider.load(id);
                          if (!mounted) return;
                          final loaded = provider.selected;
                          if (loaded != null) _applyProfileToForm(loaded);
                        },
                        child: Text(id),
                      ),
                  ],
                ),
            ],
            const SizedBox(height: 16),
            const Text('Character editor (global collection)'),
            const SizedBox(height: 12),
            TextField(
              controller: _characterIdController,
              decoration: const InputDecoration(
                labelText: 'characterId (doc id)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: 'name',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _roleTitleController,
              decoration: const InputDecoration(
                labelText: 'role_title',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _oneLineMissionController,
              decoration: const InputDecoration(
                labelText: 'one_line_mission',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _targetUserController,
              decoration: const InputDecoration(
                labelText: 'target_user',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _domainScopeController,
              decoration: const InputDecoration(
                labelText: 'domain_scope',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            _buildSlider('warmth', _warmth, (v) => setState(() => _warmth = v)),
            _buildSlider(
              'directness',
              _directness,
              (v) => setState(() => _directness = v),
            ),
            _buildSlider('humor', _humor, (v) => setState(() => _humor = v)),
            _buildSlider(
              'formality',
              _formality,
              (v) => setState(() => _formality = v),
            ),
            _buildSlider('energy', _energy, (v) => setState(() => _energy = v)),
            _buildSlider(
              'creativity',
              _creativity,
              (v) => setState(() => _creativity = v),
            ),
            _buildSlider(
              'assertiveness',
              _assertiveness,
              (v) => setState(() => _assertiveness = v),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _voiceIdController,
              decoration: const InputDecoration(
                labelText: 'voice_id',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _defaultStrategyController,
              decoration: const InputDecoration(
                labelText: 'default_strategy',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _hardBoundariesController,
              decoration: const InputDecoration(
                labelText: 'hard_boundaries (comma separated)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _coreValuesController,
              decoration: const InputDecoration(
                labelText: 'core_values (comma separated)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _expertiseLevelController,
              decoration: const InputDecoration(
                labelText: 'expertise_level',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: characterProvider.isLoading ? null : _save,
              child: Text(characterProvider.isLoading ? 'Saving...' : 'Save'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSlider(String label, int value, ValueChanged<int> onChanged) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('$label: $value'),
        Slider(
          value: value.toDouble(),
          min: 0,
          max: 10,
          divisions: 10,
          label: value.toString(),
          onChanged: (v) => onChanged(v.round()),
        ),
        const SizedBox(height: 8),
      ],
    );
  }
}
