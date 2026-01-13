import 'package:elevenlabs_phonemes/elevenlabs_phonemes.dart';

class ElevenLabsTtsService {
  final VoiceAssistant _assistant;

  ElevenLabsTtsService({
    required String tokenUrl,
    bool enableLogging = true,
  }) : _assistant = VoiceAssistant(
          config: VoiceAssistantConfig(
            tokenUrl: tokenUrl,
            enableLogging: enableLogging,
          ),
        );

  Stream<dynamic> get statusStream => _assistant.statusStream;
  Stream<Map<String, dynamic>> get eventStream => _assistant.eventStream;
  Stream<Map<String, dynamic>> get transcriptionStream =>
      _assistant.transcriptionStream;

  Future<void> start() => _assistant.start();
  Future<void> stop() => _assistant.stop();

  void dispose() => _assistant.dispose();
}
