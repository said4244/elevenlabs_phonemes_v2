/// main.dart
///
/// Demo app with streaming TTS and synchronized highlighting.

import 'package:flutter/material.dart';
import 'package:elevenlabs_phonemes/elevenlabs_phonemes.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Voice Assistant Demo',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.green),
        useMaterial3: true,
      ),
      home: const VoiceAssistantDemo(),
    );
  }
}

class VoiceAssistantDemo extends StatefulWidget {
  const VoiceAssistantDemo({super.key});

  @override
  State<VoiceAssistantDemo> createState() => _VoiceAssistantDemoState();
}

class _VoiceAssistantDemoState extends State<VoiceAssistantDemo> {
  late final VoiceAssistant assistant;
  bool isActive = false;
  String transcription = '';
  final List<Map<String, dynamic>> _charBuffer = [];
  int? _highlightedIndex;
  DateTime? _audioStartTime; // Track when audio playback started

  @override
  void initState() {
    super.initState();

    // That's it! Just configure and create the assistant
    assistant = VoiceAssistant(
      config: VoiceAssistantConfig(
        tokenUrl:
            'http://localhost:8080/token', // Replace with your token server
        enableLogging: true, // See all the logs in console
      ),
    );

    // Listen to status updates (optional)
    assistant.statusStream.listen((status) {
      debugPrint('Status: $status');
    });

    // Listen to character-level transcriptions from agent TTS
    assistant.transcriptionStream.listen((data) {
      final char = data['text'] as String?;
      final startTime = data['start_time'] as num?;
      final endTime = data['end_time'] as num?;

      if (char != null) {
        // First character marks when audio playback started
        if (_charBuffer.isEmpty) {
          _audioStartTime = DateTime.now();
          debugPrint('🎵 Audio playback started at ${_audioStartTime}');
        }

        setState(() {
          _charBuffer.add({
            'text': char,
            'start_time': startTime,
            'end_time': endTime,
            'received_at': DateTime.now(),
          });
          transcription = _charBuffer.map((c) => c['text']).join();
          debugPrint('Received char: "$char" [${startTime}s -> ${endTime}s]');
        });

        // Schedule highlighting based on timing
        if (startTime != null && endTime != null) {
          _scheduleHighlight(
              _charBuffer.length - 1, startTime.toDouble(), endTime.toDouble());
        }
      }
    });
  }

  @override
  void dispose() {
    assistant.dispose();
    super.dispose();
  }

  void _scheduleHighlight(int index, double startTime, double endTime) {
    if (_audioStartTime == null) return;

    final now = DateTime.now();
    final audioElapsedMs = now.difference(_audioStartTime!).inMilliseconds;

    // Calculate when this character should be highlighted relative to audio start
    final charStartMs = (startTime * 1000).toInt();
    final charEndMs = (endTime * 1000).toInt();
    final charDurationMs = charEndMs - charStartMs;

    // How much time until we should highlight this character
    final delayUntilHighlight = charStartMs - audioElapsedMs;

    debugPrint('📍 Char[$index] "${_charBuffer[index]['text']}" | '
        'audioElapsed: ${audioElapsedMs}ms, charStart: ${charStartMs}ms, '
        'delay: ${delayUntilHighlight}ms, duration: ${charDurationMs}ms');

    if (delayUntilHighlight > 0) {
      // Schedule highlight in the future
      Future.delayed(Duration(milliseconds: delayUntilHighlight), () {
        if (mounted) {
          setState(() => _highlightedIndex = index);
        }
      });

      // Schedule un-highlight
      Future.delayed(
          Duration(milliseconds: delayUntilHighlight + charDurationMs), () {
        if (mounted && _highlightedIndex == index) {
          setState(() => _highlightedIndex = null);
        }
      });
    } else if (audioElapsedMs < charEndMs) {
      // We're late but character is still being spoken - highlight now
      setState(() => _highlightedIndex = index);

      final remainingMs = charEndMs - audioElapsedMs;
      Future.delayed(Duration(milliseconds: remainingMs), () {
        if (mounted && _highlightedIndex == index) {
          setState(() => _highlightedIndex = null);
        }
      });
    }
    // else: character already finished speaking, skip highlighting
  }

  void _toggleAssistant() async {
    if (!isActive) {
      // Clear previous transcription
      setState(() {
        transcription = '';
        _charBuffer.clear();
        _audioStartTime = null;
        _highlightedIndex = null;
      });
      await assistant.start();
    } else {
      await assistant.stop();
    }

    setState(() {
      isActive = !isActive;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          // Transcription display at top
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            color: Colors.black87,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Agent TTS (Character-by-Character):',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                _charBuffer.isEmpty
                    ? const Text(
                        'Waiting for the agent response...',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          height: 1.5,
                        ),
                      )
                    : Wrap(
                        children: List.generate(_charBuffer.length, (index) {
                          final isHighlighted = _highlightedIndex == index;
                          final char = _charBuffer[index]['text'] as String;
                          return Text(
                            char,
                            style: TextStyle(
                              color:
                                  isHighlighted ? Colors.yellow : Colors.white,
                              fontSize: 18,
                              height: 1.5,
                              fontWeight: isHighlighted
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                              backgroundColor: isHighlighted
                                  ? Colors.orange.withOpacity(0.3)
                                  : null,
                            ),
                          );
                        }),
                      ),
                const SizedBox(height: 8),
                Text(
                  'Characters received: ${_charBuffer.length}',
                  style: const TextStyle(
                    color: Colors.white54,
                    fontSize: 10,
                  ),
                ),
              ],
            ),
          ),

          // Microphone button in center
          Expanded(
            child: Center(
              child: GestureDetector(
                onTap: _toggleAssistant,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  width: 200,
                  height: 200,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isActive ? Colors.red : Colors.green,
                    boxShadow: [
                      BoxShadow(
                        color: (isActive ? Colors.red : Colors.green)
                            .withOpacity(0.5),
                        blurRadius: isActive ? 30 : 10,
                        spreadRadius: isActive ? 10 : 5,
                      ),
                    ],
                  ),
                  child: Icon(
                    isActive ? Icons.stop : Icons.mic,
                    size: 80,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
