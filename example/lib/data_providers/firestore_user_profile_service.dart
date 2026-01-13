import 'package:cloud_firestore/cloud_firestore.dart';

import 'user_profile.dart';
import 'user_profile_service.dart';

class FirestoreUserProfileService implements UserProfileService {
  final FirebaseFirestore _db;
  final String collectionPath;

  FirestoreUserProfileService({
    FirebaseFirestore? firestore,
    this.collectionPath = 'user_profiles',
  }) : _db = firestore ?? FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get _col =>
      _db.collection(collectionPath);

  @override
  Future<UserProfile?> getProfile(String userId) async {
    final doc = await _col.doc(userId).get();
    if (!doc.exists) return null;

    final data = doc.data() ?? <String, dynamic>{};

    return UserProfile(
      userId: userId,
      favSubjects: (data['fav_subjects'] as List?)?.cast<String>() ?? const [],
      languageLevel: (data['language_level'] as String?) ?? 'unknown',
      struggles: (data['struggles'] as List?)?.cast<String>() ?? const [],
      strengths: (data['strengths'] as List?)?.cast<String>() ?? const [],
      characterIds:
          (data['character_ids'] as List?)?.cast<String>() ?? const [],
    );
  }

  @override
  Future<void> upsertProfile(UserProfile profile) async {
    await _col.doc(profile.userId).set({
      'fav_subjects': profile.favSubjects,
      'language_level': profile.languageLevel,
      'struggles': profile.struggles,
      'strengths': profile.strengths,
      'character_ids': profile.characterIds,
      'updated_at': FieldValue.serverTimestamp(),
      'user_id': profile.userId,
    }, SetOptions(merge: true));
  }

  @override
  Future<void> deleteProfile(String userId) async {
    await _col.doc(userId).delete();
  }

  @override
  Future<List<String>> listUserIds() async {
    final snap = await _col.get();
    final ids = snap.docs.map((d) => d.id).toList()..sort();
    return ids;
  }
}
