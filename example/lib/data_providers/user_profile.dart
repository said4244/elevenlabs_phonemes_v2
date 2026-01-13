class UserProfile {
  final String userId;
  final List<String> favSubjects;
  final String languageLevel;
  final List<String> struggles;
  final List<String> strengths;
  final List<String> characterIds;

  const UserProfile({
    required this.userId,
    this.favSubjects = const [],
    this.languageLevel = 'unknown',
    this.struggles = const [],
    this.strengths = const [],
    this.characterIds = const [],
  });

  UserProfile copyWith({
    List<String>? favSubjects,
    String? languageLevel,
    List<String>? struggles,
    List<String>? strengths,
    List<String>? characterIds,
  }) {
    return UserProfile(
      userId: userId,
      favSubjects: favSubjects ?? this.favSubjects,
      languageLevel: languageLevel ?? this.languageLevel,
      struggles: struggles ?? this.struggles,
      strengths: strengths ?? this.strengths,
      characterIds: characterIds ?? this.characterIds,
    );
  }
}
