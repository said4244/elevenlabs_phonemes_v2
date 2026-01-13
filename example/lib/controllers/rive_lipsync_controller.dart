// ignore_for_file: deprecated_member_use
import 'package:flutter/foundation.dart' show ChangeNotifier;
import 'package:rive/rive.dart';

class RiveLipSyncController extends ChangeNotifier {
  final String assetPath;
  final String stateMachineName;

  RiveWidgetController? _controller;
  StateMachine? _stateMachine;
  NumberInput? _visemeInput;

  bool _isReady = false;
  int _visemeValue = 1;

  RiveLipSyncController({
    required this.assetPath,
    required this.stateMachineName,
  });

  bool get isReady => _isReady;
  RiveWidgetController? get controller => _controller;
  int get visemeValue => _visemeValue;

  Future<void> init() async {
    final file = await File.asset(
      assetPath,
      riveFactory: Factory.rive,
    );

    if (file == null) {
      _isReady = false;
      notifyListeners();
      return;
    }

    final controller = RiveWidgetController(
      file,
      stateMachineSelector: StateMachineNamed(stateMachineName),
    );

    final stateMachine = controller.stateMachine;
    final visemeInput = stateMachine.number('Viseme');

    if (visemeInput != null) {
      visemeInput.value = _visemeValue.toDouble();
    }

    _controller = controller;
    _stateMachine = stateMachine;
    _visemeInput = visemeInput;
    _isReady = true;
    notifyListeners();
  }

  void applyViseme(int visemeId) {
    if (!_isReady) return;
    _visemeValue = visemeId;
    _visemeInput?.value = visemeId.toDouble();
    notifyListeners();
  }

  void scheduleViseme({
    required int visemeId,
    required DateTime audioStartTime,
    required double startTimeSeconds,
    String? char,
  }) {
    if (!_isReady) return;

    final audioElapsedMs =
        DateTime.now().difference(audioStartTime).inMilliseconds;
    final targetMs = (startTimeSeconds * 1000).toInt();
    final delayMs = targetMs - audioElapsedMs;

    void run() => applyViseme(visemeId);

    if (delayMs > 0) {
      Future.delayed(Duration(milliseconds: delayMs), run);
    } else {
      run();
    }
  }

  int mapCharToViseme(String char) {
    final lower = char.toLowerCase();

    const bmpLetters = {'b', 'm', 'p'};
    const bmpArabic = {'ب', 'م'};
    if (bmpLetters.contains(lower) || bmpArabic.contains(char)) return 3;

    const dtnLetters = {'d', 't', 'n'};
    const dtnArabic = {'ت', 'د', 'ن', 'ط', 'ض'};
    if (dtnLetters.contains(lower) || dtnArabic.contains(char)) return 5;

    const eyLetters = {'e', 'y'};
    const eyArabic = {'ي', 'ى', 'ئ', 'إ'};
    if (eyLetters.contains(lower) || eyArabic.contains(char)) return 6;

    const fvLetters = {'f', 'v'};
    const fvArabic = {'ف', 'ڤ'};
    if (fvLetters.contains(lower) || fvArabic.contains(char)) return 7;

    const kLetters = {'k', 'g', 'c', 'q'};
    const kArabic = {'ك', 'ق', 'ا', 'أ', 'آ', 'ٱ'};
    if (kLetters.contains(lower) || kArabic.contains(char)) return 8;

    const hLetters = {'h'};
    const hArabic = {'ه', 'ح', 'خ', 'ع', 'غ'};
    if (hLetters.contains(lower) || hArabic.contains(char)) return 9;

    const rLetters = {'r'};
    const rArabic = {'ر'};
    if (rLetters.contains(lower) || rArabic.contains(char)) return 10;

    const lLetters = {'l'};
    const lArabic = {'ل'};
    if (lLetters.contains(lower) || lArabic.contains(char)) return 11;

    const ngLetters = {'ڭ'};
    if (ngLetters.contains(char)) return 12;

    const szLetters = {'s', 'z'};
    const szArabic = {'س', 'ص', 'ز'};
    if (szLetters.contains(lower) || szArabic.contains(char)) return 13;

    const shLetters = {'j'};
    const shArabic = {'ش', 'ج', 'چ'};
    if (shLetters.contains(lower) || shArabic.contains(char)) return 14;

    const thArabic = {'ث'};
    if (thArabic.contains(char)) return 15;

    const dhArabic = {'ذ', 'ظ'};
    if (dhArabic.contains(char)) return 16;

    const wLetters = {'w', 'o', 'u'};
    const wArabic = {'و', 'ؤ', 'ء', 'ة'};
    if (wLetters.contains(lower) || wArabic.contains(char)) return 17;

    return 1;
  }

  @override
  void dispose() {
    _controller?.dispose();
    _stateMachine?.dispose();
    super.dispose();
  }
}
