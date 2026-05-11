import 'package:cloud_firestore/cloud_firestore.dart';

import 'character_profile.dart';
import 'character_profile_service.dart';
import 'firebase_bootstrap.dart';

class FirestoreCharacterProfileService implements CharacterProfileService {
  final FirebaseFirestore? _firestore;
  final String collectionPath;

  FirestoreCharacterProfileService({
    FirebaseFirestore? firestore,
    this.collectionPath = 'characters',
  }) : _firestore = firestore;

  Future<CollectionReference<Map<String, dynamic>>> _getCollection() async {
    await FirebaseBootstrap.ensureInitialized();
    return (_firestore ?? FirebaseFirestore.instance).collection(collectionPath);
  }

  int _clamp0to10(dynamic v, {int fallback = 5}) {
    final n = v is num ? v.toInt() : int.tryParse(v?.toString() ?? '');
    if (n == null) return fallback;
    return n.clamp(0, 10);
  }

  @override
  Future<CharacterProfile?> getCharacter(String characterId) async {
    final col = await _getCollection();
    final doc = await col.doc(characterId).get();
    if (!doc.exists) return null;

    final data = doc.data() ?? <String, dynamic>{};

    return CharacterProfile(
      characterId: characterId,
      name: (data['name'] as String?) ?? '',
      roleTitle: (data['role_title'] as String?) ?? '',
      oneLineMission: (data['one_line_mission'] as String?) ?? '',
      targetUser: (data['target_user'] as String?) ?? '',
      domainScope: (data['domain_scope'] as String?) ?? '',
      warmth: _clamp0to10(data['warmth']),
      directness: _clamp0to10(data['directness']),
      humor: _clamp0to10(data['humor']),
      formality: _clamp0to10(data['formality']),
      energy: _clamp0to10(data['energy']),
      creativity: _clamp0to10(data['creativity']),
      // support both spellings
      assertiveness: _clamp0to10(data['assertiveness'] ?? data['aassertiveness']),
      voiceId: (data['voice_id'] as String?) ?? '',
      defaultStrategy: (data['default_strategy'] as String?) ?? '',
      hardBoundaries:
          (data['hard_boundaries'] as List?)?.cast<String>() ?? const [],
      coreValues: (data['core_values'] as List?)?.cast<String>() ?? const [],
      expertiseLevel: (data['expertise_level'] as String?) ?? '',
    );
  }

  @override
  Future<void> upsertCharacter(CharacterProfile profile) async {
    final col = await _getCollection();
    await col.doc(profile.characterId).set({
      'character_id': profile.characterId,
      'name': profile.name,
      'role_title': profile.roleTitle,
      'one_line_mission': profile.oneLineMission,
      'target_user': profile.targetUser,
      'domain_scope': profile.domainScope,
      'warmth': profile.warmth,
      'directness': profile.directness,
      'humor': profile.humor,
      'formality': profile.formality,
      'energy': profile.energy,
      'creativity': profile.creativity,
      'assertiveness': profile.assertiveness,
      'voice_id': profile.voiceId,
      'default_strategy': profile.defaultStrategy,
      'hard_boundaries': profile.hardBoundaries,
      'core_values': profile.coreValues,
      'expertise_level': profile.expertiseLevel,
      'updated_at': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  @override
  Future<void> deleteCharacter(String characterId) async {
    final col = await _getCollection();
    await col.doc(characterId).delete();
  }

  @override
  Future<List<String>> listCharacterIds() async {
    final col = await _getCollection();
    final snap = await col.get();
    final ids = snap.docs.map((d) => d.id).toList()..sort();
    return ids;
  }
}
