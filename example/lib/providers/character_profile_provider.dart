import 'package:flutter/foundation.dart';

import '../data_providers/character_profile.dart';
import '../data_providers/character_profile_service.dart';

class CharacterProfileProvider extends ChangeNotifier {
  final CharacterProfileService _service;

  bool _isLoading = false;
  List<String> _availableCharacterIds = const [];
  String? _selectedCharacterId;
  CharacterProfile? _selected;

  CharacterProfileProvider(this._service);

  bool get isLoading => _isLoading;
  List<String> get availableCharacterIds => _availableCharacterIds;
  String? get selectedCharacterId => _selectedCharacterId;
  CharacterProfile? get selected => _selected;

  Future<void> refreshCharacterIds() async {
    _setLoading(true);
    try {
      _availableCharacterIds = await _service.listCharacterIds();
    } finally {
      _setLoading(false);
    }
  }

  Future<void> load(String characterId) async {
    _setLoading(true);
    try {
      _selected = await _service.getCharacter(characterId) ??
          CharacterProfile(characterId: characterId);
      _selectedCharacterId = characterId;
    } finally {
      _setLoading(false);
    }
  }

  Future<void> save(CharacterProfile profile) async {
    _setLoading(true);
    try {
      await _service.upsertCharacter(profile);
      _selected = profile;
      _selectedCharacterId = profile.characterId;
      _availableCharacterIds = await _service.listCharacterIds();
    } finally {
      _setLoading(false);
    }
  }

  void _setLoading(bool v) {
    _isLoading = v;
    notifyListeners();
  }
}
