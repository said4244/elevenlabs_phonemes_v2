import 'package:elevenlabs_phonemes_example/controllers/rive_lipsync_controller.dart';
import 'package:elevenlabs_phonemes_example/models/huda_avatar_types.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:elevenlabs_phonemes_example/utils/lipsync_engine.dart';

HudaViseme _mapCharToViseme(String char) {
  switch (char) {
    case 'a':
      return HudaViseme.ah;
    case 'b':
      return HudaViseme.dtn;
    case 'c':
      return HudaViseme.fv;
  }
  return HudaViseme.ah;
}

void main() {
  test('progression highlights and visemes over time', () {
    final engine = LipSyncEngine()
      ..addTokens(const [
        TimedCharToken(id: 0, text: 'a', startMs: 0, endMs: 100),
        TimedCharToken(id: 1, text: 'b', startMs: 100, endMs: 200),
        TimedCharToken(id: 2, text: 'c', startMs: 200, endMs: 300),
      ]);

    expect(
      engine.update(elapsedMs: 0, mapCharToViseme: _mapCharToViseme),
      const LipSyncFrame(highlightedCharId: 0, visemeId: HudaViseme.ah),
    );
    expect(
      engine.update(elapsedMs: 50, mapCharToViseme: _mapCharToViseme),
      const LipSyncFrame(highlightedCharId: 0, visemeId: HudaViseme.ah),
    );
    expect(
      engine.update(elapsedMs: 100, mapCharToViseme: _mapCharToViseme),
      const LipSyncFrame(highlightedCharId: 1, visemeId: HudaViseme.dtn),
    );
    expect(
      engine.update(elapsedMs: 250, mapCharToViseme: _mapCharToViseme),
      const LipSyncFrame(highlightedCharId: 2, visemeId: HudaViseme.fv),
    );
    expect(
      engine.update(elapsedMs: 350, mapCharToViseme: _mapCharToViseme),
      const LipSyncFrame(highlightedCharId: null, visemeId: HudaViseme.fv),
    );
    expect(
      engine.update(elapsedMs: 600, mapCharToViseme: _mapCharToViseme),
      const LipSyncFrame(highlightedCharId: null, visemeId: HudaViseme.ah),
    );
  });

  test('short gaps keep the previous viseme', () {
    final engine = LipSyncEngine()
      ..addTokens(const [
        TimedCharToken(id: 0, text: 'a', startMs: 0, endMs: 100),
        TimedCharToken(id: 1, text: 'b', startMs: 200, endMs: 300),
      ]);

    expect(
      engine.update(elapsedMs: 50, mapCharToViseme: _mapCharToViseme),
      const LipSyncFrame(highlightedCharId: 0, visemeId: HudaViseme.ah),
    );
    expect(
      engine.update(elapsedMs: 150, mapCharToViseme: _mapCharToViseme),
      const LipSyncFrame(highlightedCharId: null, visemeId: HudaViseme.ah),
    );
    expect(
      engine.update(elapsedMs: 250, mapCharToViseme: _mapCharToViseme),
      const LipSyncFrame(highlightedCharId: 1, visemeId: HudaViseme.dtn),
    );
  });

  test('long gaps reset to neutral viseme', () {
    final engine = LipSyncEngine()
      ..addTokens(const [
        TimedCharToken(id: 0, text: 'b', startMs: 0, endMs: 100),
        TimedCharToken(id: 1, text: 'c', startMs: 500, endMs: 600),
      ]);

    expect(
      engine.update(
        elapsedMs: 150,
        mapCharToViseme: _mapCharToViseme,
        silenceThresholdMs: 250,
      ),
      const LipSyncFrame(highlightedCharId: null, visemeId: HudaViseme.dtn),
    );

    expect(
      engine.update(
        elapsedMs: 360,
        mapCharToViseme: _mapCharToViseme,
        silenceThresholdMs: 250,
      ),
      const LipSyncFrame(highlightedCharId: null, visemeId: HudaViseme.ah),
    );
  });

  test('before first token uses neutral viseme', () {
    final engine = LipSyncEngine()
      ..addTokens(const [
        TimedCharToken(id: 0, text: 'a', startMs: 100, endMs: 200),
      ]);

    expect(
      engine.update(elapsedMs: 0, mapCharToViseme: _mapCharToViseme),
      const LipSyncFrame(highlightedCharId: null, visemeId: HudaViseme.ah),
    );
  });

  test('reset clears tokens and output', () {
    final engine = LipSyncEngine()
      ..addTokens(const [
        TimedCharToken(id: 0, text: 'a', startMs: 0, endMs: 100),
      ]);

    expect(engine.hasTokens, isTrue);
    engine.reset();
    expect(engine.hasTokens, isFalse);

    expect(
      engine.update(elapsedMs: 50, mapCharToViseme: _mapCharToViseme),
      const LipSyncFrame(highlightedCharId: null, visemeId: HudaViseme.ah),
    );
  });

  test('elapsed going backwards re-seeks safely', () {
    final engine = LipSyncEngine()
      ..addTokens(const [
        TimedCharToken(id: 0, text: 'a', startMs: 0, endMs: 100),
        TimedCharToken(id: 1, text: 'b', startMs: 100, endMs: 200),
      ]);

    expect(
      engine.update(elapsedMs: 150, mapCharToViseme: _mapCharToViseme),
      const LipSyncFrame(highlightedCharId: 1, visemeId: HudaViseme.dtn),
    );

    expect(
      engine.update(elapsedMs: 50, mapCharToViseme: _mapCharToViseme),
      const LipSyncFrame(highlightedCharId: 0, visemeId: HudaViseme.ah),
    );
  });

  test('speech activity uses the silence threshold', () {
    final engine = LipSyncEngine()
      ..addTokens(const [
        TimedCharToken(id: 0, text: 'a', startMs: 0, endMs: 100),
        TimedCharToken(id: 1, text: 'b', startMs: 500, endMs: 600),
      ]);

    expect(engine.isSpeechActiveAt(50), isTrue);
    expect(engine.isSpeechActiveAt(150, silenceThresholdMs: 250), isTrue);
    expect(engine.isSpeechActiveAt(360, silenceThresholdMs: 250), isFalse);
    expect(engine.isSpeechActiveAt(520, silenceThresholdMs: 250), isTrue);
    expect(engine.isSpeechActiveAt(900, silenceThresholdMs: 250), isFalse);
  });

  test('character mapper covers key viseme buckets', () {
    final controller =
        RiveLipSyncController(assetPath: 'assets/huda-character.riv');

    expect(controller.mapCharToViseme('و'), HudaViseme.wo);
    expect(controller.mapCharToViseme('ث'), HudaViseme.thi);
    expect(controller.mapCharToViseme('ذ'), HudaViseme.tha);
    expect(controller.mapCharToViseme('ش'), HudaViseme.sh);
    expect(controller.mapCharToViseme('س'), HudaViseme.sie);
    expect(controller.mapCharToViseme('ڭ'), HudaViseme.ng);
    expect(controller.mapCharToViseme('د'), HudaViseme.dtn);
    expect(controller.mapCharToViseme('x'), HudaViseme.ah);
  });
}
