import '../models/huda_avatar_types.dart';

class TimedCharToken {
  final int id;
  final String text;
  final int startMs;
  final int endMs;

  const TimedCharToken({
    required this.id,
    required this.text,
    required this.startMs,
    required this.endMs,
  });
}

class LipSyncFrame {
  final int? highlightedCharId;
  final HudaViseme visemeId;

  const LipSyncFrame({
    required this.highlightedCharId,
    required this.visemeId,
  });

  @override
  bool operator ==(Object other) {
    return other is LipSyncFrame &&
        other.highlightedCharId == highlightedCharId &&
        other.visemeId == visemeId;
  }

  @override
  int get hashCode => Object.hash(highlightedCharId, visemeId);

  @override
  String toString() =>
      'LipSyncFrame(highlightedCharId: $highlightedCharId, visemeId: $visemeId)';
}

class LipSyncEngine {
  final List<TimedCharToken> _tokens = [];
  int _highlightIndex = 0;
  int _visemeIndex = -1;
  int _lastElapsedMs = -1;

  bool get hasTokens => _tokens.isNotEmpty;

  void reset() {
    _tokens.clear();
    _highlightIndex = 0;
    _visemeIndex = -1;
    _lastElapsedMs = -1;
  }

  void addTokens(Iterable<TimedCharToken> tokens) {
    _tokens.addAll(tokens);
  }

  LipSyncFrame update({
    required int elapsedMs,
    required HudaViseme Function(String) mapCharToViseme,
    HudaViseme neutralVisemeId = HudaViseme.ah,
    int silenceThresholdMs = 250,
  }) {
    if (elapsedMs < _lastElapsedMs) {
      _highlightIndex = 0;
      _visemeIndex = -1;
    }
    _lastElapsedMs = elapsedMs;

    if (_tokens.isEmpty) {
      return LipSyncFrame(
        highlightedCharId: null,
        visemeId: neutralVisemeId,
      );
    }

    while (_highlightIndex < _tokens.length &&
        elapsedMs >= _tokens[_highlightIndex].endMs) {
      _highlightIndex++;
    }

    int? highlightId;
    if (_highlightIndex < _tokens.length) {
      final token = _tokens[_highlightIndex];
      if (elapsedMs >= token.startMs && elapsedMs < token.endMs) {
        highlightId = token.id;
      }
    }

    while (_visemeIndex + 1 < _tokens.length &&
        elapsedMs >= _tokens[_visemeIndex + 1].startMs) {
      _visemeIndex++;
    }

    var visemeId = neutralVisemeId;
    if (_visemeIndex >= 0 && _visemeIndex < _tokens.length) {
      final token = _tokens[_visemeIndex];
      final silenceStartedMs = token.endMs;
      if (elapsedMs < silenceStartedMs + silenceThresholdMs) {
        visemeId = mapCharToViseme(token.text);
      }
    }

    return LipSyncFrame(
      highlightedCharId: highlightId,
      visemeId: visemeId,
    );
  }

  int? get lastTokenEndMs => _tokens.isEmpty ? null : _tokens.last.endMs;

  bool isSpeechActiveAt(int elapsedMs, {int silenceThresholdMs = 250}) {
    if (_tokens.isEmpty) return false;

    TimedCharToken? previousToken;
    for (final token in _tokens) {
      if (elapsedMs >= token.startMs && elapsedMs < token.endMs) {
        return true;
      }
      if (elapsedMs < token.startMs) {
        if (previousToken == null) return false;
        return elapsedMs < previousToken.endMs + silenceThresholdMs;
      }
      previousToken = token;
    }

    if (previousToken == null) return false;
    return elapsedMs < previousToken.endMs + silenceThresholdMs;
  }
}
