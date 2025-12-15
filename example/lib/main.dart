/// main.dart
///
/// Demo app with streaming TTS and synchronized highlighting.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:elevenlabs_phonemes/elevenlabs_phonemes.dart';
import 'package:rive/rive.dart';

// Intents for keyboard shortcuts (arrow key handling for Rive viseme control)
class IncrementIntent extends Intent {}

class DecrementIntent extends Intent {}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
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

    // Rive state machine variables
    RiveWidgetController? _riveController;
    StateMachine? _smController;
    NumberInput? _visemeInput;
    int _visemeValue = 1; // current Viseme value (1-17)
    final TextEditingController _numberController =
      TextEditingController(text: '1');

  @override
  void initState() {
    super.initState();

    // Initialize Rive animation
    _initializeRive();

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
          debugPrint('🎵 Audio playback started at $_audioStartTime');
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
    _numberController.dispose();
    _riveController?.dispose();
    _smController?.dispose();
    super.dispose();
  }

  // Initialize Rive animation file
  Future<void> _initializeRive() async {
    try {
      // Load the Rive file using File.asset
      final file = await File.asset(
        'assets/charachter.riv',
        riveFactory: Factory.rive,
      );
      
      if (file == null) {
        debugPrint('⚠️ Failed to load Rive file');
        return;
      }

      // Create a controller that manages artboard + state machine
      final controller = RiveWidgetController(
        file,
        stateMachineSelector: const StateMachineNamed('TalkingSM'),
      );

      final stateMachine = controller.stateMachine;

      // Find the 'Viseme' number input
      final visemeInput = stateMachine.number('Viseme');
      if (visemeInput != null) {
        visemeInput.value = _visemeValue.toDouble(); // set initial value to 1
        debugPrint('✅ Viseme input found and set to $_visemeValue');
      } else {
        debugPrint('⚠️ Viseme input not found in state machine');
      }

      setState(() {
        _riveController = controller;
        _smController = stateMachine;
        _visemeInput = visemeInput;
      });

      debugPrint('✅ Rive initialization complete');
    } catch (e) {
      debugPrint('⚠️ Error loading Rive file: $e');
      debugPrint('');
      debugPrint('Common issues:');
      debugPrint('1. Make sure charachter.riv exists in example/assets/');
      debugPrint('2. If using advanced Rive features (like Feather effect), try exporting with simpler settings');
      debugPrint('3. Some Rive features may not be compatible with Flutter Web - test on mobile/desktop');
      debugPrint('4. Verify the state machine is named "TalkingSM" and has a "Viseme" number input');
      // Don't set error state, just leave artboard as null so it shows loading indicator
    }
  }

  // Helper methods to change the viseme value safely
  void _incrementViseme() {
    if (_visemeValue < 17) {
      setState(() {
        _visemeValue += 1;
        _numberController.text = _visemeValue.toString();
        _visemeInput?.value = _visemeValue.toDouble();
        debugPrint('👄 Viseme set to $_visemeValue');
      });
    }
  }

  void _decrementViseme() {
    if (_visemeValue > 1) {
      setState(() {
        _visemeValue -= 1;
        _numberController.text = _visemeValue.toString();
        _visemeInput?.value = _visemeValue.toDouble();
        debugPrint('👄 Viseme set to $_visemeValue');
      });
    }
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
    // Keyboard shortcuts: map arrow keys to increment/decrement intents
    return Focus(
      // A Focus widget to capture key events
      autofocus: true,
      child: Shortcuts(
        shortcuts: {
          LogicalKeySet(LogicalKeyboardKey.arrowUp): IncrementIntent(),
          LogicalKeySet(LogicalKeyboardKey.arrowDown): DecrementIntent(),
        },
        child: Actions(
          actions: {
            IncrementIntent: CallbackAction<IncrementIntent>(
              onInvoke: (IncrementIntent _) {
                _incrementViseme();
                return null;
              },
            ),
            DecrementIntent: CallbackAction<DecrementIntent>(
              onInvoke: (DecrementIntent _) {
                _decrementViseme();
                return null;
              },
            ),
          },
          child: Scaffold(
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
                              children:
                                  List.generate(_charBuffer.length, (index) {
                                final isHighlighted =
                                    _highlightedIndex == index;
                                final char =
                                    _charBuffer[index]['text'] as String;
                                return Text(
                                  char,
                                  style: TextStyle(
                                    color: isHighlighted
                                        ? Colors.yellow
                                        : Colors.white,
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

                // Main content area - split into two columns
                Expanded(
                  child: Row(
                    children: [
                      // Left side: Rive animation with viseme controls
                      Expanded(
                        child: Container(
                          color: Colors.grey[900],
                          child: Column(
                            children: [
                              const Padding(
                                padding: EdgeInsets.all(8.0),
                                child: Text(
                                  'Rive Viseme Test',
                                  style: TextStyle(
                                    color: Colors.white70,
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              // Rive animation view
                              Expanded(
                                child: Center(
                                  child: _riveController == null
                                      ? const CircularProgressIndicator()
                                      : RiveWidget(
                                          controller: _riveController!,
                                          fit: Fit.contain,
                                        ),
                                ),
                              ),
                              // Numeric input with up/down controls
                              Padding(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 12),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    const Text(
                                      'Viseme: ',
                                      style: TextStyle(color: Colors.white70),
                                    ),
                                    // The number TextField
                                    SizedBox(
                                      width: 60,
                                      child: TextField(
                                        controller: _numberController,
                                        textAlign: TextAlign.center,
                                        keyboardType: TextInputType.number,
                                        style: const TextStyle(
                                            color: Colors.white),
                                        inputFormatters: [
                                          FilteringTextInputFormatter.digitsOnly
                                        ],
                                        decoration: const InputDecoration(
                                          border: OutlineInputBorder(),
                                          contentPadding: EdgeInsets.all(8),
                                          fillColor: Colors.black26,
                                          filled: true,
                                        ),
                                        onChanged: (value) {
                                          if (value.isEmpty) return;
                                          final int? numVal =
                                              int.tryParse(value);
                                          if (numVal == null) return;
                                          // Clamp the value between 1 and 17
                                          int newVal = numVal.clamp(1, 17);
                                          if (newVal != _visemeValue) {
                                            setState(() {
                                              _visemeValue = newVal;
                                              _visemeInput?.value =
                                                  _visemeValue.toDouble();
                                            });
                                          }
                                          // If the parsed number was outside range, update text to the clamped value
                                          if (newVal.toString() != value) {
                                            _numberController.text =
                                                newVal.toString();
                                            // Move cursor to end (in case the user is editing)
                                            _numberController.selection =
                                                TextSelection.collapsed(
                                                    offset: _numberController
                                                        .text.length);
                                          }
                                        },
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    // Up/Down arrow buttons
                                    Column(
                                      children: [
                                        IconButton(
                                          icon: const Icon(Icons.arrow_drop_up,
                                              color: Colors.white70),
                                          onPressed: _incrementViseme,
                                        ),
                                        IconButton(
                                          icon: const Icon(
                                              Icons.arrow_drop_down,
                                              color: Colors.white70),
                                          onPressed: _decrementViseme,
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                              const Padding(
                                padding: EdgeInsets.only(bottom: 8.0),
                                child: Text(
                                  'Use ↑/↓ arrow keys or buttons (1-17)',
                                  style: TextStyle(
                                      color: Colors.white54, fontSize: 11),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),

                      // Divider
                      Container(
                        width: 2,
                        color: Colors.white24,
                      ),

                      // Right side: Microphone button (existing functionality)
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
                                    color:
                                        (isActive ? Colors.red : Colors.green)
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
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
