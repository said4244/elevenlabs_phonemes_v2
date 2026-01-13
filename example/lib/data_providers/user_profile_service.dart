import 'user_profile.dart';

abstract class UserProfileService {
  Future<UserProfile?> getProfile(String userId);
  Future<void> upsertProfile(UserProfile profile);
  Future<void> deleteProfile(String userId);
  Future<List<String>> listUserIds();
}

class InMemoryUserProfileService implements UserProfileService {
  final Map<String, UserProfile> _store = {};

  @override
  Future<UserProfile?> getProfile(String userId) async {
    return _store[userId];
  }

  @override
  Future<void> upsertProfile(UserProfile profile) async {
    _store[profile.userId] = profile;
  }

  @override
  Future<void> deleteProfile(String userId) async {
    _store.remove(userId);
  }

  @override
  Future<List<String>> listUserIds() async {
    final ids = _store.keys.toList()..sort();
    return ids;
  }
}
