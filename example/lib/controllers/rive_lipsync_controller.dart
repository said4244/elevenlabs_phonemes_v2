// ignore_for_file: deprecated_member_use
import 'package:flutter/foundation.dart' show ChangeNotifier;
import 'package:rive/rive.dart';

import '../models/huda_avatar_types.dart';

class RiveLipSyncController extends ChangeNotifier {
  final String assetPath;
  final String? stateMachineName;

  RiveWidgetController? _controller;
  ViewModelInstance? _viewModelInstance;
  ViewModelInstanceEnum? _visemeInput;
  ViewModelInstanceEnum? _poseInput;

  bool _isReady = false;
  HudaViseme _visemeValue = HudaViseme.ah;
  HudaPose _poseValue = HudaPose.idle;

  RiveLipSyncController({
    required this.assetPath,
    this.stateMachineName,
  });

  bool get isReady => _isReady;
  RiveWidgetController? get controller => _controller;
  HudaViseme get visemeValue => _visemeValue;
  HudaPose get poseValue => _poseValue;

  Future<void> init() async {
    RiveWidgetController? controller;
    ViewModelInstance? viewModelInstance;

    try {
      final file = await File.asset(
        assetPath,
        riveFactory: Factory.rive,
      );

      if (file == null) {
        _isReady = false;
        notifyListeners();
        return;
      }

      controller = RiveWidgetController(
        file,
        stateMachineSelector: stateMachineName == null
            ? const StateMachineDefault()
            : StateMachineNamed(stateMachineName!),
      );

      viewModelInstance = controller.dataBind(DataBind.auto());
      final resolvedViewModelInstance = viewModelInstance;
      final visemeInput = resolvedViewModelInstance.enumerator('visemesEnum');
      final poseInput = resolvedViewModelInstance.enumerator('posesEnum');

      if (visemeInput == null) {
        throw StateError(
          'Rive view model enum "visemesEnum" was not found in $assetPath.',
        );
      }

      if (poseInput == null) {
        throw StateError(
          'Rive view model enum "posesEnum" was not found in $assetPath.',
        );
      }

      _controller = controller;
      _viewModelInstance = viewModelInstance;
      _visemeInput = visemeInput;
      _poseInput = poseInput;
      _visemeInput!.value = _visemeValue.riveValue;
      _poseInput!.value = _poseValue.riveValue;
      _isReady = true;
      notifyListeners();
    } catch (_) {
      _isReady = false;
      viewModelInstance?.dispose();
      controller?.dispose();
      _controller = null;
      _viewModelInstance = null;
      _visemeInput = null;
      _poseInput = null;
      notifyListeners();
      rethrow;
    }
  }

  void applyViseme(HudaViseme visemeId) {
    if (!_isReady) return;
    if (_visemeValue == visemeId) return;
    _visemeValue = visemeId;
    _visemeInput?.value = visemeId.riveValue;
    notifyListeners();
  }

  void applyPose(HudaPose pose) {
    if (!_isReady) return;
    if (_poseValue == pose) return;
    _poseValue = pose;
    _poseInput?.value = pose.riveValue;
    notifyListeners();
  }

  void scheduleViseme({
    required HudaViseme visemeId,
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

  HudaViseme mapCharToViseme(String char) {
    final lower = char.toLowerCase();

    const bmpLetters = {'b', 'm', 'p'};
    const bmpArabic = {'ب', 'م'};
    if (bmpLetters.contains(lower) || bmpArabic.contains(char)) {
      return HudaViseme.ah;
    }

    const openVowelLetters = {'a'};
    const openVowelArabic = {'ا', 'أ', 'آ', 'ٱ', 'إ'};
    if (openVowelLetters.contains(lower) || openVowelArabic.contains(char)) {
      return HudaViseme.ah;
    }

    const dtnLetters = {'d', 't', 'n'};
    const dtnArabic = {'ت', 'د', 'ن', 'ط', 'ض'};
    if (dtnLetters.contains(lower) || dtnArabic.contains(char)) {
      return HudaViseme.dtn;
    }

    const eyLetters = {'e', 'y'};
    const eyArabic = {'ي', 'ى', 'ئ', 'إ'};
    if (eyLetters.contains(lower) || eyArabic.contains(char)) {
      return HudaViseme.ey;
    }

    const fvLetters = {'f', 'v'};
    const fvArabic = {'ف', 'ڤ'};
    if (fvLetters.contains(lower) || fvArabic.contains(char)) {
      return HudaViseme.fv;
    }

    const kLetters = {'k', 'g', 'c', 'q'};
    const kArabic = {'ك', 'ق'};
    if (kLetters.contains(lower) || kArabic.contains(char)) {
      return HudaViseme.k;
    }

    const hLetters = {'h'};
    const hArabic = {'ه', 'ح', 'خ', 'ع', 'غ'};
    if (hLetters.contains(lower) || hArabic.contains(char)) {
      return HudaViseme.h;
    }

    const rLetters = {'r'};
    const rArabic = {'ر'};
    if (rLetters.contains(lower) || rArabic.contains(char)) {
      return HudaViseme.r;
    }

    const lLetters = {'l'};
    const lArabic = {'ل'};
    if (lLetters.contains(lower) || lArabic.contains(char)) {
      return HudaViseme.l;
    }

    const ngLetters = {'ڭ'};
    if (ngLetters.contains(char)) return HudaViseme.ng;

    const szLetters = {'s', 'z'};
    const szArabic = {'س', 'ص', 'ز'};
    if (szLetters.contains(lower) || szArabic.contains(char)) {
      return HudaViseme.sie;
    }

    const shLetters = {'j'};
    const shArabic = {'ش', 'ج', 'چ'};
    if (shLetters.contains(lower) || shArabic.contains(char)) {
      return HudaViseme.sh;
    }

    const thArabic = {'ث'};
    if (thArabic.contains(char)) return HudaViseme.thi;

    const dhArabic = {'ذ', 'ظ'};
    if (dhArabic.contains(char)) return HudaViseme.tha;

    const wLetters = {'w', 'o', 'u'};
    const wArabic = {'و', 'ؤ'};
    if (wLetters.contains(lower) || wArabic.contains(char)) {
      return HudaViseme.wo;
    }

    return HudaViseme.ah;
  }

  @override
  void dispose() {
    _viewModelInstance?.dispose();
    _controller?.dispose();
    super.dispose();
  }
}
