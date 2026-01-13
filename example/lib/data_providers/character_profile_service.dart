import 'character_profile.dart';

abstract class CharacterProfileService {
  Future<CharacterProfile?> getCharacter(String characterId);
  Future<void> upsertCharacter(CharacterProfile profile);
  Future<void> deleteCharacter(String characterId);
  Future<List<String>> listCharacterIds();
}

class InMemoryCharacterProfileService implements CharacterProfileService {
  final Map<String, CharacterProfile> _store = {};

  @override
  Future<CharacterProfile?> getCharacter(String characterId) async {
    return _store[characterId];
  }

  @override
  Future<void> upsertCharacter(CharacterProfile profile) async {
    _store[profile.characterId] = profile;
  }

  @override
  Future<void> deleteCharacter(String characterId) async {
    _store.remove(characterId);
  }

  @override
  Future<List<String>> listCharacterIds() async {
    final ids = _store.keys.toList()..sort();
    return ids;
  }
}
