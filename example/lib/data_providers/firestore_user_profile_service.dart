import 'package:cloud_firestore/cloud_firestore.dart';

import 'user_profile.dart';
import 'user_profile_service.dart';
import 'firebase_bootstrap.dart';

class FirestoreUserProfileService implements UserProfileService {
  final FirebaseFirestore? _firestore;
  final String collectionPath;

  FirestoreUserProfileService({
    FirebaseFirestore? firestore,
    this.collectionPath = 'user_profiles',
  }) : _firestore = firestore;

  Future<CollectionReference<Map<String, dynamic>>> _getCollection() async {
    await FirebaseBootstrap.ensureInitialized();
    return (_firestore ?? FirebaseFirestore.instance).collection(collectionPath);
  }

  @override
  Future<UserProfile?> getProfile(String userId) async {
    final col = await _getCollection();
    final doc = await col.doc(userId).get();
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
    final col = await _getCollection();
    await col.doc(profile.userId).set({
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
    final col = await _getCollection();
    await col.doc(userId).delete();
  }

  @override
  Future<List<String>> listUserIds() async {
    final col = await _getCollection();
    final snap = await col.get();
    final ids = snap.docs.map((d) => d.id).toList()..sort();
    return ids;
  }
}
