class CharacterProfile {
  final String characterId;
  final String name;
  final String roleTitle;
  final String oneLineMission;
  final String targetUser;
  final String domainScope;

  final int warmth;
  final int directness;
  final int humor;
  final int formality;
  final int energy;
  final int creativity;
  final int assertiveness;

  final String voiceId;
  final String defaultStrategy;

  final List<String> hardBoundaries;
  final List<String> coreValues;
  final String expertiseLevel;

  const CharacterProfile({
    required this.characterId,
    this.name = '',
    this.roleTitle = '',
    this.oneLineMission = '',
    this.targetUser = '',
    this.domainScope = '',
    this.warmth = 5,
    this.directness = 5,
    this.humor = 5,
    this.formality = 5,
    this.energy = 5,
    this.creativity = 5,
    this.assertiveness = 5,
    this.voiceId = '',
    this.defaultStrategy = '',
    this.hardBoundaries = const [],
    this.coreValues = const [],
    this.expertiseLevel = '',
  });

  CharacterProfile copyWith({
    String? name,
    String? roleTitle,
    String? oneLineMission,
    String? targetUser,
    String? domainScope,
    int? warmth,
    int? directness,
    int? humor,
    int? formality,
    int? energy,
    int? creativity,
    int? assertiveness,
    String? voiceId,
    String? defaultStrategy,
    List<String>? hardBoundaries,
    List<String>? coreValues,
    String? expertiseLevel,
  }) {
    return CharacterProfile(
      characterId: characterId,
      name: name ?? this.name,
      roleTitle: roleTitle ?? this.roleTitle,
      oneLineMission: oneLineMission ?? this.oneLineMission,
      targetUser: targetUser ?? this.targetUser,
      domainScope: domainScope ?? this.domainScope,
      warmth: warmth ?? this.warmth,
      directness: directness ?? this.directness,
      humor: humor ?? this.humor,
      formality: formality ?? this.formality,
      energy: energy ?? this.energy,
      creativity: creativity ?? this.creativity,
      assertiveness: assertiveness ?? this.assertiveness,
      voiceId: voiceId ?? this.voiceId,
      defaultStrategy: defaultStrategy ?? this.defaultStrategy,
      hardBoundaries: hardBoundaries ?? this.hardBoundaries,
      coreValues: coreValues ?? this.coreValues,
      expertiseLevel: expertiseLevel ?? this.expertiseLevel,
    );
  }
}
