import 'package:flutter/foundation.dart';
import '../data_providers/user_profile.dart';
import '../data_providers/user_profile_service.dart';

class UserProfileProvider extends ChangeNotifier {
  final UserProfileService _service;

  UserProfile? _profile;
  bool _isLoading = false;
  List<String> _availableUserIds = const [];
  String? _selectedUserId;

  UserProfileProvider(this._service);

  UserProfile? get profile => _profile;
  bool get isLoading => _isLoading;

  List<String> get availableUserIds => _availableUserIds;
  String? get selectedUserId => _selectedUserId;

  List<String> get favSubjects => _profile?.favSubjects ?? const [];
  String get languageLevel => _profile?.languageLevel ?? 'unknown';
  List<String> get struggles => _profile?.struggles ?? const [];
  List<String> get strengths => _profile?.strengths ?? const [];

  Future<void> load(String userId) async {
    _setLoading(true);
    try {
      _profile = await _service.getProfile(userId) ?? UserProfile(userId: userId);
      _selectedUserId = userId;
    } finally {
      _setLoading(false);
      notifyListeners();
    }
  }

  Future<void> refreshUserIds() async {
    _setLoading(true);
    try {
      _availableUserIds = await _service.listUserIds();
    } finally {
      _setLoading(false);
      notifyListeners();
    }
  }

  Future<void> save(UserProfile profile) async {
    _setLoading(true);
    try {
      await _service.upsertProfile(profile);
      _profile = profile;
      _selectedUserId = profile.userId;
      _availableUserIds = await _service.listUserIds();
    } finally {
      _setLoading(false);
      notifyListeners();
    }
  }

  Future<void> selectUser(String userId) async {
    await load(userId);
  }

  void _setLoading(bool value) {
    _isLoading = value;
    notifyListeners();
  }
}
