import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:provider/provider.dart';
import 'package:rive/rive.dart';

import '../controllers/rive_lipsync_controller.dart';
import '../models/huda_avatar_types.dart';
import '../providers/navigation_provider.dart';
import '../providers/session_provider.dart';
import '../services/elevenlabs_tts_service.dart';
import '../services/rive_avatar_cache.dart';
import '../main.dart' show adminLogin, kBackendBaseUrl;
import '../utils/lipsync_bug_logger.dart';
import '../utils/lipsync_engine.dart';

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

class _CallPageState extends State<CallPage>
    with SingleTickerProviderStateMixin {
  static const bool _enableLipSyncBugLogging = false;
  late final ElevenLabsTtsService _tts;
  RiveLipSyncController? _rive;
  Future<RiveLipSyncController>? _riveLoad;

  StreamSubscription? _statusSub;
  StreamSubscription<Map<String, dynamic>>? _transcriptionSub;
  StreamSubscription<Map<String, dynamic>>? _eventSub;

  final LipSyncEngine _lipSyncEngine = LipSyncEngine();
  Ticker? _ticker;
  final Stopwatch _utteranceStopwatch = Stopwatch();
  int _utteranceOffsetMs = 0;
  DateTime? _pendingAgentSpeechStart;
  int? _currentUtteranceId;
  int _lastSeq = -1;

  bool _isActive = false;
  bool _callEndedOnce = false; // guard against duplicate _endCall invocations

  // Transcript accumulation: text is buffered per utterance and committed when
  // a new utterance starts or the call ends.
  String _currentAgentText = '';
  int? _currentAgentUtteranceId;
  final List<_CharToken> _charBuffer = [];
  final List<_WordToken> _wordBuffer = [];
  final Map<int, int> _visibleCharIdToOffset = {};
  final Map<int, int> _visibleCharIdToLen = {};
  int _nextCharId = 0;
  int? _highlightedCharId;
  int _wordWindowStart = 0;
  DateTime? _audioStartTime;
  String _visibleSubtitleText = '';

  static const int _wordWindowSize = 10;
  static const int _agentSpeechStartRecentWindowMs = 2000;
  static const int _agentSpeechStartCompensationMs = 0;
  static const int _intraSentenceSilenceThresholdMs = 250;

  // Lip sync bug logger
  final LipSyncBugLogger _bugLogger = LipSyncBugLogger();
  bool _isFirstTranscription = true;

  @override
  void initState() {
    super.initState();

    // Initialize the bug logger
    if (_enableLipSyncBugLogging) {
      unawaited(_bugLogger.init());
    }

    _tts = ElevenLabsTtsService(
      tokenUrl: _buildTokenUrl(),
      enableLogging: true,
      tokenHeaders: _buildTokenHeaders(),
    );

    _bindTtsStreams();

    _riveLoad = RiveAvatarCache.getTalkingController();
    _riveLoad!.then((controller) {
      if (!mounted) return;
      setState(() => _rive = controller);
      _syncAvatarState();
    });

    _startCall();
  }

  void _bindTtsStreams() {
    _statusSub = _tts.statusStream.listen((status) {
      debugPrint('Status: $status');
    });

    // Listen for events (audio track + agent speaking)
    _eventSub = _tts.eventStream.listen((event) {
      final eventType = event['type'] as String?;
      final data = event['data'] as Map<String, dynamic>?;

      if (eventType == 'track_subscribed') {
        final kind = data?['kind'] as String? ?? 'unknown';
        final participant = data?['participant'] as String? ?? 'unknown';
        if (_enableLipSyncBugLogging &&
            (kind.contains('audio') || kind.contains('Audio'))) {
          _bugLogger.logTrackSubscribed(kind, participant);
        }
        return;
      }

      if (eventType == 'agent_speaking') {
        final speaking = data?['speaking'] == true;
        if (!speaking) return;

        final ts = (data?['timestamp'] as num?)?.toInt();
        final detectedStart = ts != null
            ? DateTime.fromMillisecondsSinceEpoch(ts)
            : DateTime.now();
        _pendingAgentSpeechStart = detectedStart.subtract(
          const Duration(milliseconds: _agentSpeechStartCompensationMs),
        );
      }
    });

    _transcriptionSub = _tts.transcriptionStream.listen((data) {
      final text = data['text'] as String?;
      final startTime = data['start_time'] as num?;
      final endTime = data['end_time'] as num?;
      final utteranceId = (data['utterance_id'] as num?)?.toInt();
      final seq = (data['seq'] as num?)?.toInt();

      if (text == null || text.isEmpty) return;

      final pieces =
          text.runes.map(String.fromCharCode).toList(growable: false);
      final hasLipSyncPieces = pieces.any(_drivesLipSync);

      final prevStartTime =
          _charBuffer.isNotEmpty ? _charBuffer.last.startTimeSeconds : null;

      final bool isNewUtterance;
      if (utteranceId != null) {
        final currentUtteranceId = _currentUtteranceId;
        if (currentUtteranceId != null && utteranceId < currentUtteranceId) {
          // Stale/out-of-order utterance: ignore.
          return;
        }
        isNewUtterance =
            currentUtteranceId == null || utteranceId != currentUtteranceId;
      } else {
        isNewUtterance = _charBuffer.isEmpty ||
            (startTime != null &&
                prevStartTime != null &&
                startTime.toDouble() < prevStartTime);
      }

      // Finalize previous utterance transcript before starting a new one.
      if (isNewUtterance) {
        final prevText = _currentAgentText.trim();
        if (prevText.isNotEmpty && mounted) {
          context.read<SessionProvider>().addTranscriptMessage('assistant', prevText);
        }
        _currentAgentText = '';
        _currentAgentUtteranceId = utteranceId;
      }

      if (isNewUtterance && !hasLipSyncPieces) {
        return;
      }

      if (isNewUtterance) {
        _currentUtteranceId = utteranceId;
        _lastSeq = -1;
        _lipSyncEngine.reset();
        _isFirstTranscription = true;
        _rive?.applyViseme(HudaViseme.ah);
        _rive?.applyPose(HudaPose.speaking);

        final now = DateTime.now();
        final firstStartMs = ((startTime?.toDouble() ?? 0.0) * 1000).toInt();

        DateTime estimatedAudioStart;
        final speechStart = _pendingAgentSpeechStart;
        if (speechStart != null) {
          final ageMs = now.difference(speechStart).inMilliseconds;
          final isRecent =
              ageMs >= 0 && ageMs <= _agentSpeechStartRecentWindowMs;
          estimatedAudioStart = isRecent
              ? speechStart
              : now.subtract(Duration(milliseconds: firstStartMs));
        } else {
          estimatedAudioStart =
              now.subtract(Duration(milliseconds: firstStartMs));
        }
        _pendingAgentSpeechStart = null;

        _utteranceOffsetMs = now.difference(estimatedAudioStart).inMilliseconds;
        _utteranceStopwatch
          ..reset()
          ..start();

        if (_enableLipSyncBugLogging) {
          _bugLogger.logAudioStartTimeSet(
            estimatedAudioStart,
            isNewUtterance: true,
          );
        }

        if (mounted) {
          setState(() {
            _resetTranscriptUi(estimatedAudioStart);
          });
        } else {
          _resetTranscriptUi(estimatedAudioStart);
        }
      } else {
        if (_audioStartTime == null) {
          final now = DateTime.now();
          _audioStartTime = now;
          _utteranceOffsetMs = 0;
          _utteranceStopwatch
            ..reset()
            ..start();
          if (_enableLipSyncBugLogging) {
            _bugLogger.logAudioStartTimeSet(now, isNewUtterance: false);
          }
        }
      }

      if (seq != null) {
        if (seq <= _lastSeq) return;
        _lastSeq = seq;
      }

      // Accumulate text for transcript capture (assistant speech).
      _currentAgentText += text;
      debugPrint('[CallPage] stream text chunk: "$text" | total so far: ${_currentAgentText.length} chars');

      // Log first transcription per utterance for bug analysis
      if (_enableLipSyncBugLogging && _isFirstTranscription) {
        _isFirstTranscription = false;
        _bugLogger.logFirstTranscription(
          text,
          startTime?.toDouble(),
          endTime?.toDouble(),
        );
      }

      final startSeconds = startTime?.toDouble();
      final endSeconds = endTime?.toDouble();
      final charTokens = <_CharToken>[];
      final timedTokens = <TimedCharToken>[];

      final hasTiming = startSeconds != null && endSeconds != null;
      final timingStart = startSeconds ?? 0.0;
      final timingEnd = endSeconds ?? 0.0;
      final totalDurationSeconds = timingEnd - timingStart;
      final speechPieceIndices = <int>[];
      for (var i = 0; i < pieces.length; i++) {
        if (_drivesLipSync(pieces[i])) {
          speechPieceIndices.add(i);
        }
      }
      final speechPieceCount = speechPieceIndices.length;
      final speechSlotByPieceIndex = <int, int>{};
      for (var i = 0; i < speechPieceIndices.length; i++) {
        speechSlotByPieceIndex[speechPieceIndices[i]] = i;
      }

      for (var i = 0; i < pieces.length; i++) {
        final piece = pieces[i];
        final charId = _nextCharId++;
        final speechSlot = speechSlotByPieceIndex[i];

        double? pieceStartSeconds;
        double? pieceEndSeconds;
        if (hasTiming && speechSlot != null) {
          if (speechPieceCount > 1 && totalDurationSeconds > 0) {
            pieceStartSeconds = timingStart +
                totalDurationSeconds * (speechSlot / speechPieceCount);
            pieceEndSeconds = speechSlot == speechPieceCount - 1
                ? timingEnd
                : timingStart +
                    totalDurationSeconds *
                        ((speechSlot + 1) / speechPieceCount);
          } else {
            pieceStartSeconds = timingStart;
            pieceEndSeconds = timingEnd;
          }
        }

        charTokens.add(
          _CharToken(
            id: charId,
            text: piece,
            startTimeSeconds: pieceStartSeconds,
            endTimeSeconds: pieceEndSeconds,
          ),
        );

        if (pieceStartSeconds != null && pieceEndSeconds != null) {
          var startMs = (pieceStartSeconds * 1000).round();
          var endMs = (pieceEndSeconds * 1000).round();
          if (endMs <= startMs) {
            endMs = startMs + 1;
          }

          timedTokens.add(
            TimedCharToken(
              id: charId,
              text: piece,
              startMs: startMs,
              endMs: endMs,
            ),
          );
        }
      }

      if (timedTokens.isNotEmpty) {
        _lipSyncEngine.addTokens(timedTokens);
      }

      if (charTokens.isNotEmpty) {
        if (mounted) {
          setState(() {
            _charBuffer.addAll(charTokens);
            _recomputeWordCache();
          });
        } else {
          _charBuffer.addAll(charTokens);
          _recomputeWordCache();
        }
      }
    });
  }

  // ── Session token helpers ──────────────────────────────────────────────

  /// Build the LiveKit token URL, including session_id and prompt_id as params.
  String _buildTokenUrl() {
    final session = context.read<SessionProvider>();
    final tokenUrl = session.buildTokenUrl();
    if (tokenUrl != null) return tokenUrl;
    // Fallback for dev/testing when no session was prepared
    return '$kBackendBaseUrl/token';
  }

  /// Build Authorization headers for the token server request.
  Map<String, String> _buildTokenHeaders() {
    return context.read<SessionProvider>().authHeaders();
  }

  // ─────────────────────────────────────────────────────────────────────────

  Future<void> _startCall() async {
    if (!mounted) return;

    setState(() => _isActive = true);
    _ticker ??= createTicker(_onTick);
    _ticker!.start();

    try {
      await _tts.start();
      // Notify backend that LiveKit session has started
      if (mounted) {
        unawaited(context.read<SessionProvider>().markStarted());
      }
    } catch (e, stackTrace) {
      debugPrint('Failed to start voice assistant: $e');
      debugPrintStack(stackTrace: stackTrace);
      if (!mounted) return;
      setState(() => _isActive = false);
    }
  }

  void _syncAvatarState() {
    final rive = _rive;
    if (rive == null || !rive.isReady) return;

    if (_audioStartTime == null || !_lipSyncEngine.hasTokens) {
      if (rive.visemeValue != HudaViseme.ah) {
        rive.applyViseme(HudaViseme.ah);
      }
      if (rive.poseValue != HudaPose.idle) {
        rive.applyPose(HudaPose.idle);
      }
      return;
    }

    final elapsedMs =
        _utteranceOffsetMs + _utteranceStopwatch.elapsedMilliseconds;
    final desiredPose = _lipSyncEngine.isSpeechActiveAt(
      elapsedMs,
      silenceThresholdMs: _intraSentenceSilenceThresholdMs,
    )
        ? HudaPose.speaking
        : HudaPose.idle;
    if (rive.poseValue != desiredPose) {
      rive.applyPose(desiredPose);
    }

    final frame = _lipSyncEngine.update(
      elapsedMs: elapsedMs,
      mapCharToViseme: rive.mapCharToViseme,
      neutralVisemeId: HudaViseme.ah,
      silenceThresholdMs: _intraSentenceSilenceThresholdMs,
    );
    if (rive.visemeValue != frame.visemeId) {
      rive.applyViseme(frame.visemeId);
    }
  }

  void _onTick(Duration _) {
    if (!_isActive) return;

    final rive = _rive;
    if (rive == null || !rive.isReady) return;

    if (_audioStartTime == null) {
      if (rive.poseValue != HudaPose.idle) {
        rive.applyPose(HudaPose.idle);
      }
      return;
    }

    if (!_lipSyncEngine.hasTokens) return;

    final elapsedMs =
        _utteranceOffsetMs + _utteranceStopwatch.elapsedMilliseconds;

    final desiredPose = _lipSyncEngine.isSpeechActiveAt(
      elapsedMs,
      silenceThresholdMs: _intraSentenceSilenceThresholdMs,
    )
        ? HudaPose.speaking
        : HudaPose.idle;
    if (rive.poseValue != desiredPose) {
      rive.applyPose(desiredPose);
    }

    final frame = _lipSyncEngine.update(
      elapsedMs: elapsedMs,
      mapCharToViseme: rive.mapCharToViseme,
      neutralVisemeId: HudaViseme.ah,
      silenceThresholdMs: _intraSentenceSilenceThresholdMs,
    );

    final rawHighlightId = frame.highlightedCharId;
    var effectiveHighlightId = _highlightedCharId;
    if (rawHighlightId != null) {
      final token = _charById(rawHighlightId);
      if (token != null && _isWordChar(token.text)) {
        effectiveHighlightId = rawHighlightId;
      }
    }

    if (effectiveHighlightId != _highlightedCharId && mounted) {
      setState(() {
        _highlightedCharId = effectiveHighlightId;
        if (effectiveHighlightId != null) {
          _maybeAdvanceWordWindow(effectiveHighlightId);
        }
      });

      if (effectiveHighlightId != null) {
        final token = _charById(effectiveHighlightId);
        final startSeconds = token?.startTimeSeconds;
        final endSeconds = token?.endTimeSeconds;
        if (_enableLipSyncBugLogging &&
            token != null &&
            startSeconds != null &&
            endSeconds != null) {
          _bugLogger.logHighlightApplied(
            charId: token.id,
            charText: token.text,
            elapsedMs: elapsedMs,
            charStartMs: (startSeconds * 1000).toInt(),
            charEndMs: (endSeconds * 1000).toInt(),
          );
        }
      }
    }

    final newVisemeId = frame.visemeId;
    if (newVisemeId != rive.visemeValue) {
      rive.applyViseme(newVisemeId);
      if (_enableLipSyncBugLogging) {
        _bugLogger.logVisemeApplied(
          visemeId: newVisemeId,
          elapsedMs: elapsedMs,
        );
      }
    }
  }

  bool _isWhitespace(String ch) => RegExp(r'\s').hasMatch(ch);

  bool _isWordChar(String ch) {
    return RegExp(r'[A-Za-z0-9\u0600-\u06FF\u0750-\u077F\u08A0-\u08FF]')
        .hasMatch(ch);
  }

  bool _isCombiningMark(String ch) {
    if (ch.runes.length != 1) return false;
    final cp = ch.runes.single;

    return (cp >= 0x0300 && cp <= 0x036F) ||
        (cp >= 0x064B && cp <= 0x065F) ||
        cp == 0x0670 ||
        (cp >= 0x06D6 && cp <= 0x06ED) ||
        (cp >= 0x08D4 && cp <= 0x08E1) ||
        (cp >= 0x08E3 && cp <= 0x08FF);
  }

  bool _drivesLipSync(String ch) {
    if (_isWhitespace(ch) || _isPunctuation(ch) || _isCombiningMark(ch)) {
      return false;
    }
    return _isWordChar(ch);
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
    if (_wordBuffer.isEmpty) {
      _wordWindowStart = 0;
      _rebuildVisibleSubtitleCache();
      return;
    }

    final wordIndex = _wordIndexForCharId(_wordBuffer, highlightedCharId);
    if (wordIndex == -1) return;

    final desiredStart = (wordIndex ~/ _wordWindowSize) * _wordWindowSize;
    if (desiredStart != _wordWindowStart) {
      _wordWindowStart = desiredStart;
      _rebuildVisibleSubtitleCache();
    }
  }

  List<_WordToken> _computeWordTokens(List<_CharToken> chars) {
    final tokens = <_WordToken>[];

    int? currentStartId;
    int? currentLastId;
    final current = StringBuffer();

    final pendingPrefix = StringBuffer();
    int? pendingPrefixStartId;
    int? pendingPrefixLastId;

    void clearPendingPrefix() {
      pendingPrefix.clear();
      pendingPrefixStartId = null;
      pendingPrefixLastId = null;
    }

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
        clearPendingPrefix();
        continue;
      }

      if (_isPunctuation(ch)) {
        if (currentStartId != null) {
          current.write(ch);
          currentLastId = c.id;
        } else {
          pendingPrefixStartId ??= c.id;
          pendingPrefix.write(ch);
          pendingPrefixLastId = c.id;
        }
        continue;
      }

      // Word character
      if (currentStartId == null) {
        if (pendingPrefixStartId != null && pendingPrefixLastId == c.id - 1) {
          currentStartId = pendingPrefixStartId;
          current.write(pendingPrefix.toString());
          currentLastId = pendingPrefixLastId;
        } else {
          currentStartId = c.id;
        }
        clearPendingPrefix();
      }
      current.write(ch);
      currentLastId = c.id;
    }

    finalizeCurrent();
    return tokens;
  }

  Future<void> _endCall() async {
    // Prevent duplicate invocations (e.g. button tap + stream disconnect).
    if (_callEndedOnce) return;
    _callEndedOnce = true;

    if (_isActive) {
      setState(() => _isActive = false);
      _rive?.applyPose(HudaPose.idle);
      await _tts.stop();
    }

    _ticker?.stop();
    _utteranceStopwatch.stop();

    if (!mounted) return;

    // Finalize any remaining agent utterance text.
    final lastText = _currentAgentText.trim();
    if (lastText.isNotEmpty) {
      context.read<SessionProvider>().addTranscriptMessage('assistant', lastText);
    }
    _currentAgentText = '';

    // TODO: Integrate user STT transcript when available from LiveKit agent.
    // Currently only speaking start/stop timing is available, not text content.

    // Complete session (saves transcript, marks ended, runs AI analysis).
    final sessionProv = context.read<SessionProvider>();
    debugPrint('[CallPage] Sending ${sessionProv.transcriptMessages.length} transcript messages');
    for (final m in sessionProv.transcriptMessages) {
      debugPrint('[CallPage]   ${m['role']}: ${(m['text'] as String).substring(0, (m['text'] as String).length.clamp(0, 80))}');
    }
    final result = await sessionProv.completeSession(reason: 'user_ended');
    debugPrint('[CallPage] completeSession result: $result');

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
    _eventSub?.cancel();
    _ticker?.dispose();
    _ticker = null;
    _utteranceStopwatch.stop();
    unawaited(_tts.dispose());
    // Write summary and close the bug logger
    if (_enableLipSyncBugLogging) {
      unawaited(_bugLogger.dispose());
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final highlightId = _highlightedCharId;
    final highlightStart =
        highlightId != null ? _visibleCharIdToOffset[highlightId] : null;
    final highlightLen =
        highlightId != null ? _visibleCharIdToLen[highlightId] : null;

    final textDirection = Directionality.of(context);
    const baseStyle = TextStyle(color: Colors.white, fontSize: 24);
    const highlightColor = Color(0x4D0CC0DF);

    final subtitleText = _visibleSubtitleText;
    final subtitleDirection =
        RegExp(r'[\u0590-\u05FF\u0600-\u06FF\u0750-\u077F\u08A0-\u08FF]')
                .hasMatch(subtitleText)
            ? TextDirection.rtl
            : textDirection;

    InlineSpan subtitleSpan;
    final highlightStartIndex = highlightStart;
    final highlightLength = highlightLen;
    if (highlightStartIndex != null &&
        highlightLength != null &&
        highlightLength > 0) {
      final safeStart = highlightStartIndex.clamp(0, subtitleText.length);
      final safeEnd =
          (safeStart + highlightLength).clamp(0, subtitleText.length);
      if (safeStart < safeEnd) {
        subtitleSpan = TextSpan(
          style: baseStyle,
          children: [
            if (safeStart > 0)
              TextSpan(text: subtitleText.substring(0, safeStart)),
            TextSpan(
              text: subtitleText.substring(safeStart, safeEnd),
              style: baseStyle.copyWith(backgroundColor: highlightColor),
            ),
            if (safeEnd < subtitleText.length)
              TextSpan(text: subtitleText.substring(safeEnd)),
          ],
        );
      } else {
        subtitleSpan = TextSpan(text: subtitleText, style: baseStyle);
      }
    } else {
      subtitleSpan = TextSpan(text: subtitleText, style: baseStyle);
    }

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
                          borderRadius: BorderRadius.all(Radius.circular(20)),
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
                    child: subtitleText.isEmpty
                        ? const Text(
                            'Hamza is listening...',
                            style: baseStyle,
                            textAlign: TextAlign.center,
                          )
                        : Text.rich(
                            subtitleSpan,
                            textAlign: TextAlign.center,
                            textDirection: subtitleDirection,
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

  void _resetTranscriptUi(DateTime audioStartTime) {
    _audioStartTime = audioStartTime;
    _charBuffer.clear();
    _wordBuffer.clear();
    _visibleCharIdToOffset.clear();
    _visibleCharIdToLen.clear();
    _visibleSubtitleText = '';
    _nextCharId = 0;
    _highlightedCharId = null;
    _wordWindowStart = 0;
  }

  void _recomputeWordCache() {
    _wordBuffer
      ..clear()
      ..addAll(_computeWordTokens(_charBuffer));

    if (_wordBuffer.isEmpty) {
      _wordWindowStart = 0;
    } else if (_wordWindowStart >= _wordBuffer.length) {
      _wordWindowStart = ((_wordBuffer.length - 1) ~/ _wordWindowSize) *
          _wordWindowSize;
    }

    _rebuildVisibleSubtitleCache();
  }

  void _rebuildVisibleSubtitleCache() {
    _visibleCharIdToOffset.clear();
    _visibleCharIdToLen.clear();

    if (_wordBuffer.isEmpty) {
      _visibleSubtitleText = '';
      return;
    }

    var start = _wordWindowStart;
    if (start < 0) start = 0;
    if (start >= _wordBuffer.length) {
      start = ((_wordBuffer.length - 1) ~/ _wordWindowSize) * _wordWindowSize;
    }

    final end = (start + _wordWindowSize).clamp(0, _wordBuffer.length);
    final words = _wordBuffer.sublist(start, end);
    final displayText = StringBuffer();

    for (var i = 0; i < words.length; i++) {
      final w = words[i];
      if (i != 0) displayText.write(' ');

      for (var id = w.startCharId; id < w.endCharIdExclusive; id++) {
        final c = _charById(id);
        if (c == null) continue;
        _visibleCharIdToOffset[id] = displayText.length;
        _visibleCharIdToLen[id] = c.text.length;
        displayText.write(c.text);
      }
    }

    _visibleSubtitleText = displayText.toString();
  }
}
