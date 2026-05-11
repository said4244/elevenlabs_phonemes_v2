import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../data_providers/supabase_profile_service.dart';
import '../providers/auth_provider.dart';
import 'app_stack.dart';

/// Collects learner details on first sign-up and saves them to Supabase.
/// After a successful save, navigates to AppStack.
class OnboardingPage extends StatefulWidget {
  const OnboardingPage({super.key});

  @override
  State<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends State<OnboardingPage> {
  final _formKey = GlobalKey<FormState>();
  final _profileService = SupabaseProfileService();

  // Form field controllers.
  final _nameCtrl = TextEditingController();
  final _ageCtrl = TextEditingController();
  final _interestsCtrl = TextEditingController();
  final _goalCtrl = TextEditingController();

  String _dialectCode = 'lev_syrian';
  String _translationLanguageCode = 'en';
  int _currentLevel = 1;
  String _preferredStyle = 'warm';
  String _challengePreference = 'medium';

  bool _isLoading = false;
  String? _errorMessage;

  // ---------------------------------------------------------------------------
  // Options
  // ---------------------------------------------------------------------------

  static const _dialects = [
    ('lev_syrian', 'Levantine – Syrian'),
    ('lev_lebanese', 'Levantine – Lebanese'),
    ('gulf', 'Gulf'),
    ('egyptian', 'Egyptian'),
    ('moroccan', 'Moroccan'),
  ];

  static const _languages = [
    ('en', 'English'),
    ('fr', 'French'),
    ('tr', 'Turkish'),
    ('de', 'German'),
    ('es', 'Spanish'),
  ];

  static const _tutorStyles = [
    ('warm', 'Warm'),
    ('playful', 'Playful'),
    ('direct', 'Direct'),
    ('patient', 'Patient'),
  ];

  static const _challengeOptions = [
    ('easy', 'Easy'),
    ('medium', 'Medium'),
    ('hard', 'Hard'),
  ];

  @override
  void dispose() {
    _nameCtrl.dispose();
    _ageCtrl.dispose();
    _interestsCtrl.dispose();
    _goalCtrl.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Submit
  // ---------------------------------------------------------------------------

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final user = context.read<AuthProvider>().currentUser;
      if (user == null) throw Exception('Not authenticated.');

      final age = int.tryParse(_ageCtrl.text.trim()) ?? 0;

      await _profileService.upsertProfile(
        userId: user.id,
        targetDialectCode: _dialectCode,
        translationLanguageCode: _translationLanguageCode,
        age: age,
        currentLevel: _currentLevel,
        learnerPreferences: {
          'name': _nameCtrl.text.trim(),
          'learning_goal': _goalCtrl.text.trim(),
          'interests': _interestsCtrl.text.trim(),
          'preferred_style': _preferredStyle,
          'challenge_preference': _challengePreference,
        },
        isNewUser: false,
      );

      if (mounted) {
        // Navigate to the main app; AuthGate would also pick this up on
        // next rebuild, but pushing directly is faster.
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute<void>(builder: (_) => const AppStack()),
          (_) => false,
        );
      }
    } on PostgrestException catch (e) {
      if (mounted) setState(() => _errorMessage = e.message);
    } catch (e) {
      if (mounted) setState(() => _errorMessage = e.toString());
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: const Text(
          'Tell us about yourself',
          style: TextStyle(color: Colors.white),
        ),
        actions: [
          TextButton(
            onPressed: () async {
              await context.read<AuthProvider>().signOut();
              // AuthGate stream will redirect to LoginPage.
            },
            child: const Text('Sign out', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              _sectionLabel('Name'),
              _textField(
                controller: _nameCtrl,
                hint: 'Your first name',
                validator: _required,
              ),
              const SizedBox(height: 16),

              _sectionLabel('Age'),
              _textField(
                controller: _ageCtrl,
                hint: 'e.g. 25',
                keyboardType: TextInputType.number,
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return 'Enter your age';
                  final n = int.tryParse(v.trim());
                  if (n == null || n < 5 || n > 120) return 'Enter a valid age';
                  return null;
                },
              ),
              const SizedBox(height: 16),

              _sectionLabel('Target Arabic Dialect'),
              _dropdownField<String>(
                value: _dialectCode,
                items: _dialects,
                onChanged: (v) => setState(() => _dialectCode = v!),
              ),
              const SizedBox(height: 16),

              _sectionLabel('Translation Language'),
              _dropdownField<String>(
                value: _translationLanguageCode,
                items: _languages,
                onChanged: (v) =>
                    setState(() => _translationLanguageCode = v!),
              ),
              const SizedBox(height: 16),

              _sectionLabel('Current Arabic Level (1 = Beginner, 5 = Advanced)'),
              Slider(
                value: _currentLevel.toDouble(),
                min: 1,
                max: 5,
                divisions: 4,
                label: _currentLevel.toString(),
                activeColor: const Color(0xFF4CAF50),
                onChanged: (v) => setState(() => _currentLevel = v.round()),
              ),
              const SizedBox(height: 8),

              _sectionLabel('Main Learning Goal'),
              _textField(
                controller: _goalCtrl,
                hint: 'e.g. Travel to Syria, talk with family…',
                validator: _required,
              ),
              const SizedBox(height: 16),

              _sectionLabel('Interests (comma-separated)'),
              _textField(
                controller: _interestsCtrl,
                hint: 'e.g. cooking, music, travel',
                validator: _required,
              ),
              const SizedBox(height: 16),

              _sectionLabel('Preferred Tutor Style'),
              _dropdownField<String>(
                value: _preferredStyle,
                items: _tutorStyles,
                onChanged: (v) => setState(() => _preferredStyle = v!),
              ),
              const SizedBox(height: 16),

              _sectionLabel('Challenge Preference'),
              _dropdownField<String>(
                value: _challengePreference,
                items: _challengeOptions,
                onChanged: (v) => setState(() => _challengePreference = v!),
              ),
              const SizedBox(height: 32),

              // Error
              if (_errorMessage != null) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.red.shade900,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    _errorMessage!,
                    style: const TextStyle(color: Colors.white),
                  ),
                ),
                const SizedBox(height: 16),
              ],

              // Submit
              ElevatedButton(
                onPressed: _isLoading ? null : _submit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF4CAF50),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: _isLoading
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text('Get Started'),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  String? _required(String? v) =>
      (v == null || v.trim().isEmpty) ? 'This field is required' : null;

  Widget _sectionLabel(String label) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(label, style: const TextStyle(color: Colors.white70)),
    );
  }

  Widget _textField({
    required TextEditingController controller,
    required String hint,
    TextInputType keyboardType = TextInputType.text,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: Colors.white38),
        filled: true,
        fillColor: const Color(0xFF1E1E1E),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFF4CAF50)),
        ),
      ),
      validator: validator,
    );
  }

  Widget _dropdownField<T>({
    required T value,
    required List<(T, String)> items,
    required void Function(T?) onChanged,
  }) {
    return DropdownButtonFormField<T>(
      value: value,
      dropdownColor: const Color(0xFF1E1E1E),
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        filled: true,
        fillColor: const Color(0xFF1E1E1E),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFF4CAF50)),
        ),
      ),
      items: items
          .map(
            (e) => DropdownMenuItem<T>(
              value: e.$1,
              child: Text(e.$2),
            ),
          )
          .toList(),
      onChanged: onChanged,
    );
  }
}
