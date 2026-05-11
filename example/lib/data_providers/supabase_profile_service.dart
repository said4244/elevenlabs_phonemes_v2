import 'package:supabase_flutter/supabase_flutter.dart';

/// Model that mirrors the columns we care about from `public.user_profile`.
class SupabaseUserProfile {
  final String userId;
  final String targetDialectCode;
  final String translationLanguageCode;
  final int age;
  final bool isNewUser;
  final int currentLevel;
  final Map<String, dynamic> learnerPreferences;
  final Map<String, dynamic> personalityNeeds;
  final DateTime updatedAt;

  const SupabaseUserProfile({
    required this.userId,
    required this.targetDialectCode,
    required this.translationLanguageCode,
    required this.age,
    required this.isNewUser,
    required this.currentLevel,
    required this.learnerPreferences,
    required this.personalityNeeds,
    required this.updatedAt,
  });

  factory SupabaseUserProfile.fromJson(Map<String, dynamic> json) {
    return SupabaseUserProfile(
      userId: json['user_id'] as String,
      targetDialectCode: (json['target_dialect_code'] as String?) ?? 'lev_syrian',
      translationLanguageCode:
          (json['translation_language_code'] as String?) ?? 'en',
      age: (json['age'] as num?)?.toInt() ?? 0,
      isNewUser: (json['is_new_user'] as bool?) ?? true,
      currentLevel: (json['current_level'] as num?)?.toInt() ?? 1,
      learnerPreferences:
          (json['learner_preferences'] as Map<String, dynamic>?) ?? {},
      personalityNeeds:
          (json['personality_needs'] as Map<String, dynamic>?) ?? {},
      updatedAt: json['updated_at'] != null
          ? DateTime.parse(json['updated_at'] as String)
          : DateTime.now(),
    );
  }
}

/// Service for reading and writing the `public.user_profile` table in Supabase.
class SupabaseProfileService {
  static const _table = 'user_profile';

  SupabaseClient get _client => Supabase.instance.client;

  /// Fetch the profile for [userId]. Returns null if no row exists.
  Future<SupabaseUserProfile?> getProfile(String userId) async {
    final response = await _client
        .from(_table)
        .select()
        .eq('user_id', userId)
        .maybeSingle();

    if (response == null) return null;
    return SupabaseUserProfile.fromJson(response);
  }

  /// Upsert a user profile row.
  Future<void> upsertProfile({
    required String userId,
    required String targetDialectCode,
    required String translationLanguageCode,
    required int age,
    required int currentLevel,
    required Map<String, dynamic> learnerPreferences,
    bool isNewUser = false,
  }) async {
    await _client.from(_table).upsert({
      'user_id': userId,
      'target_dialect_code': targetDialectCode,
      'translation_language_code': translationLanguageCode,
      'age': age,
      'is_new_user': isNewUser,
      'current_level': currentLevel,
      'learner_preferences': learnerPreferences,
      'personality_needs': <String, dynamic>{},
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    });
  }
}
