import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:provider/provider.dart';
import 'package:rive/rive.dart';

import '../controllers/rive_lipsync_controller.dart';
import '../providers/navigation_provider.dart';
import '../services/elevenlabs_tts_service.dart';
import '../services/rive_avatar_cache.dart';
import '../main.dart' show adminLogin;

class CallPage extends StatefulWidget {
  const CallPage({super.key});

  @override
  State<CallPage> createState() => _CallPageState();
}

class _CharToken {
  final int id;
  final String text;
  final double? startTimeSeconds;
  final double? endTimeSeconds;

  const _CharToken({
    required this.id,
    required this.text,
    required this.startTimeSeconds,
    required this.endTimeSeconds,
  });
}

class _WordToken {
  final int startCharId;
  final int endCharIdExclusive;
  final String text;

  const _WordToken({
    required this.startCharId,
    required this.endCharIdExclusive,
    required this.text,
  });
}

class _TranscriptionHighlightPainter extends CustomPainter {
  final String text;
  final TextStyle style;
  final TextDirection textDirection;
  final int? highlightStart;
  final int? highlightLength;
  final Color highlightColor;

  const _TranscriptionHighlightPainter({
    required this.text,
    required this.style,
    required this.textDirection,
    required this.highlightStart,
    required this.highlightLength,
    required this.highlightColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final start = highlightStart;
    final len = highlightLength;
    if (start == null || len == null || len <= 0) return;
    if (start < 0 || start >= text.length) return;

    final end = (start + len).clamp(0, text.length);

    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: textDirection,
      maxLines: null,
    )..layout(maxWidth: size.width);

    final boxes = painter.getBoxesForSelection(
      TextSelection(baseOffset: start, extentOffset: end),
    );
    if (boxes.isEmpty) return;

    final paint = Paint()..color = highlightColor;
    for (final box in boxes) {
      canvas.drawRect(box.toRect(), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _TranscriptionHighlightPainter oldDelegate) {
    return oldDelegate.text != text ||
        oldDelegate.style != style ||
        oldDelegate.textDirection != textDirection ||
        oldDelegate.highlightStart != highlightStart ||
        oldDelegate.highlightLength != highlightLength ||
        oldDelegate.highlightColor != highlightColor;
  }
}

class _CallPageState extends State<CallPage> {
  late final ElevenLabsTtsService _tts;
  RiveLipSyncController? _rive;
  Future<RiveLipSyncController>? _riveLoad;

  StreamSubscription? _statusSub;
  StreamSubscription<Map<String, dynamic>>? _transcriptionSub;

  bool _isActive = false;
  final List<_CharToken> _charBuffer = [];
  int _nextCharId = 0;
  int? _highlightedCharId;
  int _wordWindowStart = 0;
  DateTime? _audioStartTime;

  static const int _wordWindowSize = 10;

  @override
  void initState() {
    super.initState();

    _tts = ElevenLabsTtsService(
      tokenUrl: 'http://localhost:8080/token',
      enableLogging: true,
    );

    _riveLoad = RiveAvatarCache.getTalkingController();
    _riveLoad!.then((controller) async {
      if (!mounted) return;
      setState(() => _rive = controller);
      await _initAfterRiveIsReady();
    });
  }

  Future<void> _initAfterRiveIsReady() async {
    final rive = _rive;
    if (rive == null || !rive.isReady) return;

    _statusSub = _tts.statusStream.listen((status) {
      debugPrint('Status: $status');
    });

    _transcriptionSub = _tts.transcriptionStream.listen((data) {
      final text = data['text'] as String?;
      final startTime = data['start_time'] as num?;
      final endTime = data['end_time'] as num?;

      if (text == null || text.isEmpty) return;

      final prevStartTime =
          _charBuffer.isNotEmpty ? _charBuffer.last.startTimeSeconds : null;
      final isNewUtterance = _charBuffer.isEmpty ||
          (startTime != null &&
              prevStartTime != null &&
              startTime.toDouble() < prevStartTime);

      if (isNewUtterance) {
        final now = DateTime.now();
        setState(() {
          _audioStartTime = now;
          _charBuffer.clear();
          _nextCharId = 0;
          _highlightedCharId = null;
          _wordWindowStart = 0;
        });
      } else {
        _audioStartTime ??= DateTime.now();
      }

      final pieces = text.runes.map(String.fromCharCode);
      for (final piece in pieces) {
        final charId = _nextCharId++;
        final token = _CharToken(
          id: charId,
          text: piece,
          startTimeSeconds: startTime?.toDouble(),
          endTimeSeconds: endTime?.toDouble(),
        );

        if (mounted) {
          setState(() {
            _charBuffer.add(token);
          });
        }

        if (token.startTimeSeconds != null &&
            token.endTimeSeconds != null &&
            _audioStartTime != null) {
          _scheduleHighlight(
            charId: charId,
            startTimeSeconds: token.startTimeSeconds!,
            endTimeSeconds: token.endTimeSeconds!,
          );

          final visemeId = rive.mapCharToViseme(piece);
          rive.scheduleViseme(
            visemeId: visemeId,
            audioStartTime: _audioStartTime!,
            startTimeSeconds: token.startTimeSeconds!,
            char: piece,
          );
        }
      }
    });

    if (!mounted) return;

    setState(() => _isActive = true);
    await _tts.start();
  }

  void _scheduleHighlight({
    required int charId,
    required double startTimeSeconds,
    required double endTimeSeconds,
  }) {
    final audioStartTime = _audioStartTime;
    if (audioStartTime == null) return;

    final audioElapsedMs =
        DateTime.now().difference(audioStartTime).inMilliseconds;

    final charStartMs = (startTimeSeconds * 1000).toInt();
    final charEndMs = (endTimeSeconds * 1000).toInt();
    final charDurationMs = charEndMs - charStartMs;

    final delayUntilHighlight = charStartMs - audioElapsedMs;

    if (delayUntilHighlight > 0) {
      Future.delayed(Duration(milliseconds: delayUntilHighlight), () {
        if (!mounted) return;
        setState(() {
          _highlightedCharId = charId;
          _maybeAdvanceWordWindow(charId);
        });
      });

      Future.delayed(
        Duration(milliseconds: delayUntilHighlight + charDurationMs),
        () {
          if (!mounted) return;
          if (_highlightedCharId == charId) {
            setState(() => _highlightedCharId = null);
          }
        },
      );

      return;
    }

    if (audioElapsedMs < charEndMs) {
      setState(() {
        _highlightedCharId = charId;
        _maybeAdvanceWordWindow(charId);
      });

      final remainingMs = charEndMs - audioElapsedMs;
      Future.delayed(Duration(milliseconds: remainingMs), () {
        if (!mounted) return;
        if (_highlightedCharId == charId) {
          setState(() => _highlightedCharId = null);
        }
      });
    }
  }

  bool _isWhitespace(String ch) => RegExp(r'\s').hasMatch(ch);

  bool _isWordChar(String ch) {
    return RegExp(r'[A-Za-z0-9\u0600-\u06FF\u0750-\u077F\u08A0-\u08FF]')
        .hasMatch(ch);
  }

  bool _isPunctuation(String ch) {
    if (_isWhitespace(ch)) return false;
    if (_isWordChar(ch)) return false;

    const extra = {
      '،',
      '؛',
      '؟',
      '…',
      '—',
      '–',
      '“',
      '”',
      '‘',
      '’',
    };
    if (extra.contains(ch)) return true;

    if (ch.runes.length != 1) return false;
    final cp = ch.runes.single;

    // ASCII punctuation ranges.
    // 0x21-0x2F:  !"#$%&'()*+,-./
    // 0x3A-0x40:  :;<=>?@
    // 0x5B-0x60:  [\]^_`
    // 0x7B-0x7E:  {|}~
    return (cp >= 0x21 && cp <= 0x2F) ||
        (cp >= 0x3A && cp <= 0x40) ||
        (cp >= 0x5B && cp <= 0x60) ||
        (cp >= 0x7B && cp <= 0x7E);
  }

  bool _containsAnyWordChar(String s) {
    return RegExp(r'[A-Za-z0-9\u0600-\u06FF\u0750-\u077F\u08A0-\u08FF]')
        .hasMatch(s);
  }

  _CharToken? _charById(int id) {
    if (id < 0 || id >= _charBuffer.length) return null;
    final token = _charBuffer[id];
    if (token.id != id) return null;
    return token;
  }

  int _wordIndexForCharId(List<_WordToken> words, int charId) {
    for (var i = 0; i < words.length; i++) {
      final w = words[i];
      if (charId >= w.startCharId && charId < w.endCharIdExclusive) return i;
    }
    return -1;
  }

  void _maybeAdvanceWordWindow(int highlightedCharId) {
    final words = _computeWordTokens(_charBuffer);
    if (words.isEmpty) {
      _wordWindowStart = 0;
      return;
    }

    final wordIndex = _wordIndexForCharId(words, highlightedCharId);
    if (wordIndex == -1) return;

    final desiredStart = (wordIndex ~/ _wordWindowSize) * _wordWindowSize;
    if (desiredStart != _wordWindowStart) {
      _wordWindowStart = desiredStart;
    }
  }

  List<_WordToken> _computeWordTokens(List<_CharToken> chars) {
    final tokens = <_WordToken>[];

    int? currentStartId;
    int? currentLastId;
    final current = StringBuffer();

    void finalizeCurrent() {
      if (currentStartId == null || currentLastId == null) return;
      final text = current.toString();
      if (text.isNotEmpty && _containsAnyWordChar(text)) {
        tokens.add(
          _WordToken(
            startCharId: currentStartId!,
            endCharIdExclusive: currentLastId! + 1,
            text: text,
          ),
        );
      }
      current.clear();
      currentStartId = null;
      currentLastId = null;
    }

    for (final c in chars) {
      final ch = c.text;

      if (_isWhitespace(ch)) {
        finalizeCurrent();
        continue;
      }

      if (_isPunctuation(ch)) {
        if (currentStartId != null) {
          current.write(ch);
          currentLastId = c.id;
        } else if (tokens.isNotEmpty) {
          final last = tokens.removeLast();
          tokens.add(
            _WordToken(
              startCharId: last.startCharId,
              endCharIdExclusive: c.id + 1,
              text: '${last.text}$ch',
            ),
          );
        }
        continue;
      }

      // Word character
      currentStartId ??= c.id;
      current.write(ch);
      currentLastId = c.id;
    }

    finalizeCurrent();
    return tokens;
  }

  Future<void> _endCall() async {
    if (_isActive) {
      setState(() => _isActive = false);
      await _tts.stop();
    }

    if (!mounted) return;
    context.read<NavigationProvider>().goTo(AppPage.callSuccess);
  }

  void _showRewardOverlay() {
    final nav = context.read<NavigationProvider>();
    nav.showRewardOverlay();
    Future.delayed(const Duration(seconds: 1), () {
      nav.hideRewardOverlay();
    });
  }

  @override
  void dispose() {
    _statusSub?.cancel();
    _transcriptionSub?.cancel();
    _tts.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final allWords = _computeWordTokens(_charBuffer);

    var start = _wordWindowStart;
    if (start < 0) start = 0;
    if (allWords.isNotEmpty && start >= allWords.length) {
      start = ((allWords.length - 1) ~/ _wordWindowSize) * _wordWindowSize;
    }
    final end = (start + _wordWindowSize).clamp(0, allWords.length);
    final words = allWords.sublist(start, end);

    final displayText = StringBuffer();
    final charIdToOffset = <int, int>{};
    final charIdToLen = <int, int>{};

    for (var i = 0; i < words.length; i++) {
      final w = words[i];
      if (i != 0) displayText.write(' ');

      for (var id = w.startCharId; id < w.endCharIdExclusive; id++) {
        final c = _charById(id);
        if (c == null) continue;
        charIdToOffset[id] = displayText.length;
        charIdToLen[id] = c.text.length;
        displayText.write(c.text);
      }
    }

    final highlightId = _highlightedCharId;
    final highlightStart =
        highlightId != null ? charIdToOffset[highlightId] : null;
    final highlightLen = highlightId != null ? charIdToLen[highlightId] : null;

    final textDirection = Directionality.of(context);
    const baseStyle = TextStyle(color: Colors.white, fontSize: 24);
    const highlightColor = Color(0x4D0CC0DF);

    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFFFDD18E),
              Color(0xFF4B4B4B),
              Colors.black,
            ],
            stops: [0.0, 0.5, 1.0],
          ),
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final screenH = constraints.maxHeight;
            final screenW = constraints.maxWidth;

            final topSpace = screenH * 0.10;
            final avatarBoxH = screenH * 0.60;
            final avatarBoxW = screenW * 0.85;

            return Column(
              children: [
                SizedBox(height: topSpace),
                Center(
                  child: ClipRRect(
                    borderRadius: const BorderRadius.all(Radius.circular(20)),
                    child: SizedBox(
                      width: avatarBoxW,
                      height: avatarBoxH,
                      child: DecoratedBox(
                        decoration: const BoxDecoration(
                          color: Color(0xFF17375A),
                          borderRadius:
                              BorderRadius.all(Radius.circular(20)),
                        ),
                        child: Center(
                          child: _rive == null
                              ? const CircularProgressIndicator()
                              : AnimatedBuilder(
                                  animation: _rive!,
                                  builder: (context, _) {
                                    final rive = _rive;
                                    if (rive == null ||
                                        !rive.isReady ||
                                        rive.controller == null) {
                                      return const CircularProgressIndicator();
                                    }

                                    return Transform.scale(
                                      scale: 1.0,
                                      child: RiveWidget(
                                        controller: rive.controller!,
                                        fit: Fit.cover,
                                      ),
                                    );
                                  },
                                ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Center(
                  child: SizedBox(
                    width: avatarBoxW,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        InkResponse(
                          onTap: _endCall,
                          containedInkWell: false,
                          highlightShape: BoxShape.circle,
                          child: SvgPicture.asset(
                            'assets/images/stop_call.svg',
                            width: 64,
                            height: 64,
                          ),
                        ),
                        if (adminLogin) ...[
                          const SizedBox(width: 14),
                          ElevatedButton(
                            onPressed: _showRewardOverlay,
                            child: const Text('Reward'),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Center(
                  child: SizedBox(
                    width: avatarBoxW,
                    child: words.isEmpty
                        ? const Text(
                            'Hamza is listening...',
                            style: baseStyle,
                            textAlign: TextAlign.center,
                          )
                        : CustomPaint(
                            painter: _TranscriptionHighlightPainter(
                              text: displayText.toString(),
                              style: baseStyle,
                              textDirection: textDirection,
                              highlightStart: highlightStart,
                              highlightLength: highlightLen,
                              highlightColor: highlightColor,
                            ),
                            child: Text(
                              displayText.toString(),
                              style: baseStyle,
                              textAlign: TextAlign.center,
                            ),
                          ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
