// ignore_for_file: avoid_web_libraries_in_flutter
import 'dart:html' as html;
import 'package:flutter/foundation.dart';

import '../models/huda_avatar_types.dart';

/// Logger specifically for debugging lip sync timing issues.
/// Works on web - prints to console and accumulates logs.
/// Access accumulated logs via LipSyncBugLogger().getAllLogs()
class LipSyncBugLogger {
  static final LipSyncBugLogger _instance = LipSyncBugLogger._internal();
  factory LipSyncBugLogger() => _instance;
  LipSyncBugLogger._internal();

  final StringBuffer _logBuffer = StringBuffer();
  int _visemeCount = 0;
  int _highlightCount = 0;
  int _visemeAppliedCount = 0;
  int _highlightAppliedCount = 0;
  DateTime? _trackSubscribedTime;
  DateTime? _firstTranscriptionTime;
  DateTime? _audioStartSetTime;
  final List<_VisemeLogEntry> _visemeBuffer = [];
  final List<_HighlightLogEntry> _highlightBuffer = [];

  static const int _initialLogCount = 15; // Log first 15 events in detail

  /// Initialize the logger
  Future<void> init() async {
    _logBuffer.clear();
    _visemeCount = 0;
    _highlightCount = 0;
    _visemeAppliedCount = 0;
    _highlightAppliedCount = 0;
    _trackSubscribedTime = null;
    _firstTranscriptionTime = null;
    _audioStartSetTime = null;
    _visemeBuffer.clear();
    _highlightBuffer.clear();
    _log('=== LIP SYNC BUG LOG INITIALIZED ===');
    _log('Timestamp: ${DateTime.now().toIso8601String()}');
    _log('Platform: Web');
    _log('');
  }

  void _log(String message) {
    final timestamp = DateTime.now();
    final line = '[${timestamp.toIso8601String()}] $message';
    debugPrint('LIPSYNC: $message');
    _logBuffer.writeln(line);
  }

  /// Get all accumulated logs as a string (for copying from console)
  String getAllLogs() {
    return _logBuffer.toString();
  }

  /// Print all logs to console (call this at end to see full log)
  void printAllLogs() {
    debugPrint('');
    debugPrint('===== COMPLETE LIP SYNC BUG LOG =====');
    debugPrint(_logBuffer.toString());
    debugPrint('===== END OF LOG =====');
  }

  /// Download the log file (web only) - triggers browser download
  void downloadLogFile() {
    final content = _logBuffer.toString();
    // Pass string directly to Blob - it will encode as UTF-8
    final blob = html.Blob([content], 'text/plain;charset=utf-8');
    final url = html.Url.createObjectUrlFromBlob(blob);

    final anchor = html.AnchorElement(href: url)
      ..setAttribute('download', 'lipsync-bug-log.txt')
      ..style.display = 'none';

    html.document.body?.children.add(anchor);
    anchor.click();
    anchor.remove();
    html.Url.revokeObjectUrl(url);

    debugPrint('LIPSYNC: log file downloaded: lipsync-bug-log.txt');
  }

  /// Log when TrackSubscribed event fires (audio track arrives)
  void logTrackSubscribed(String kind, String participant) {
    _trackSubscribedTime = DateTime.now();
    _log('');
    _log('=== TRACK SUBSCRIBED EVENT ===');
    _log('Track Kind: $kind');
    _log('Participant: $participant');
    _log('Timestamp: ${_trackSubscribedTime!.millisecondsSinceEpoch}ms');

    if (_firstTranscriptionTime != null) {
      final gap = _firstTranscriptionTime!
          .difference(_trackSubscribedTime!)
          .inMilliseconds;
      _log(
          '⚠️ NOTE: First transcription arrived ${gap}ms BEFORE track subscribed');
    }
    _log('');
  }

  /// Log when first transcription data is received
  void logFirstTranscription(String text, double? startTime, double? endTime) {
    _firstTranscriptionTime = DateTime.now();
    _log('');
    _log('=== FIRST TRANSCRIPTION RECEIVED ===');
    _log('Text: "$text"');
    _log('Start Time (from TTS): ${startTime}s');
    _log('End Time (from TTS): ${endTime}s');
    _log('Timestamp: ${_firstTranscriptionTime!.millisecondsSinceEpoch}ms');

    if (_trackSubscribedTime != null) {
      final gap = _firstTranscriptionTime!
          .difference(_trackSubscribedTime!)
          .inMilliseconds;
      _log('📊 GAP: ${gap}ms after track subscribed');
      if (gap < 0) {
        _log('⚠️ TIMING ISSUE: Transcription arrived BEFORE audio track!');
      }
    } else {
      _log('⚠️ WARNING: Track subscribed event not yet received!');
    }
    _log('');
  }

  /// Log when _audioStartTime is set
  void logAudioStartTimeSet(DateTime audioStartTime,
      {bool isNewUtterance = false}) {
    _audioStartSetTime = DateTime.now();
    _log('');
    _log('=== AUDIO START TIME SET ===');
    _log('Is New Utterance: $isNewUtterance');
    _log('_audioStartTime value: ${audioStartTime.millisecondsSinceEpoch}ms');
    _log('Set at timestamp: ${_audioStartSetTime!.millisecondsSinceEpoch}ms');

    if (_trackSubscribedTime != null) {
      final gapFromTrack =
          audioStartTime.difference(_trackSubscribedTime!).inMilliseconds;
      _log('📊 GAP from track subscribed: ${gapFromTrack}ms');
      if (gapFromTrack > 100) {
        _log(
            '⚠️ POTENTIAL ISSUE: audioStartTime set ${gapFromTrack}ms after track arrived');
      }
    }

    if (_firstTranscriptionTime != null) {
      final gapFromTranscription =
          audioStartTime.difference(_firstTranscriptionTime!).inMilliseconds;
      _log('📊 GAP from first transcription: ${gapFromTranscription}ms');
    }
    _log('');
  }

  /// Log scheduleHighlight call with detailed timing
  void logScheduleHighlight({
    required int charId,
    required String charText,
    required int audioElapsedMs,
    required int charStartMs,
    required int charEndMs,
    required int delayMs,
    required bool scheduledWithDelay,
    required bool skipped,
    required bool immediatePartial,
  }) {
    _highlightCount++;
    final entry = _HighlightLogEntry(
      charId: charId,
      charText: charText,
      audioElapsedMs: audioElapsedMs,
      charStartMs: charStartMs,
      charEndMs: charEndMs,
      delayMs: delayMs,
      scheduledWithDelay: scheduledWithDelay,
      skipped: skipped,
      immediatePartial: immediatePartial,
      timestamp: DateTime.now(),
    );
    _highlightBuffer.add(entry);

    // Log first N highlights in detail
    if (_highlightCount <= _initialLogCount) {
      _log('');
      _log('--- HIGHLIGHT #$_highlightCount ---');
      _log('Char ID: $charId');
      _log('Char: "$charText"');
      _log('audioElapsedMs: $audioElapsedMs');
      _log('charStartMs: $charStartMs');
      _log('charEndMs: $charEndMs');
      _log('delayMs: $delayMs');

      if (delayMs <= 0) {
        _log('⚠️ LATE: delayMs <= 0 (event arrived late)');
      }
      if (skipped) {
        _log('⛔ SKIPPED: Character highlight was skipped entirely');
      }
      if (immediatePartial) {
        _log(
            '⚡ IMMEDIATE PARTIAL: Applied immediately with remaining duration');
      }
      if (scheduledWithDelay) {
        _log('✅ SCHEDULED: Will apply after ${delayMs}ms delay');
      }
    } else if (_highlightCount == _initialLogCount + 1) {
      _log('');
      _log('... (subsequent highlights logged to buffer, summary at end)');
    }
  }

  /// Log when a highlight is actually applied (ticker-driven mode)
  void logHighlightApplied({
    required int charId,
    required String charText,
    required int elapsedMs,
    required int charStartMs,
    required int charEndMs,
  }) {
    _highlightAppliedCount++;

    if (_highlightAppliedCount <= _initialLogCount) {
      _log('');
      _log('--- HIGHLIGHT APPLIED #$_highlightAppliedCount ---');
      _log('Char ID: $charId');
      _log('Char: "$charText"');
      _log('elapsedMs: $elapsedMs');
      _log('charStartMs: $charStartMs');
      _log('charEndMs: $charEndMs');
      _log('deltaFromStartMs: ${elapsedMs - charStartMs}');
    } else if (_highlightAppliedCount == _initialLogCount + 1) {
      _log('');
      _log('... (subsequent applied highlights not logged)');
    }
  }

  /// Log scheduleViseme call with detailed timing
  void logScheduleViseme({
    required HudaViseme visemeId,
    required String? charText,
    required int audioElapsedMs,
    required int targetMs,
    required int delayMs,
    required bool scheduledWithDelay,
    required bool appliedImmediately,
  }) {
    _visemeCount++;
    final entry = _VisemeLogEntry(
      visemeId: visemeId,
      charText: charText,
      audioElapsedMs: audioElapsedMs,
      targetMs: targetMs,
      delayMs: delayMs,
      scheduledWithDelay: scheduledWithDelay,
      appliedImmediately: appliedImmediately,
      timestamp: DateTime.now(),
    );
    _visemeBuffer.add(entry);

    // Log first N visemes in detail
    if (_visemeCount <= _initialLogCount) {
      _log('');
      _log('--- VISEME #$_visemeCount ---');
      _log('Viseme: ${visemeId.riveValue}');
      _log('Char: "$charText"');
      _log('audioElapsedMs: $audioElapsedMs');
      _log('targetMs: $targetMs');
      _log('delayMs: $delayMs');

      if (delayMs <= 0) {
        _log('⚠️ LATE: delayMs <= 0 (viseme arrived late)');
      }
      if (appliedImmediately) {
        _log('⚡ IMMEDIATE: Applied without delay');
      }
      if (scheduledWithDelay) {
        _log('✅ SCHEDULED: Will apply after ${delayMs}ms delay');
      }
    } else if (_visemeCount == _initialLogCount + 1) {
      _log('');
      _log('... (subsequent visemes logged to buffer, summary at end)');
    }
  }

  /// Log when a viseme is actually applied (ticker-driven mode)
  void logVisemeApplied({
    required HudaViseme visemeId,
    required int elapsedMs,
  }) {
    _visemeAppliedCount++;

    if (_visemeAppliedCount <= _initialLogCount) {
      _log('');
      _log('--- VISEME APPLIED #$_visemeAppliedCount ---');
      _log('Viseme: ${visemeId.riveValue}');
      _log('elapsedMs: $elapsedMs');
    } else if (_visemeAppliedCount == _initialLogCount + 1) {
      _log('');
      _log('... (subsequent applied visemes not logged)');
    }
  }

  /// Log viseme bunching analysis
  void logVisemeBunchingAnalysis() {
    if (_visemeBuffer.length < 2) return;

    _log('');
    _log('=== VISEME BUNCHING ANALYSIS ===');

    // Analyze first 20 visemes for bunching
    final analyzeCount = _visemeBuffer.length.clamp(0, 20);
    int bunchedCount = 0;
    int negativeDelayCount = 0;
    int zeroDelayCount = 0;

    for (var i = 0; i < analyzeCount; i++) {
      final v = _visemeBuffer[i];
      if (v.delayMs <= 0) negativeDelayCount++;
      if (v.delayMs == 0) zeroDelayCount++;

      if (i > 0) {
        final prev = _visemeBuffer[i - 1];
        final timeBetween =
            v.timestamp.difference(prev.timestamp).inMilliseconds;
        if (timeBetween < 10) bunchedCount++;
      }
    }

    _log('Analyzed first $analyzeCount visemes:');
    _log('  - Negative/zero delay count: $negativeDelayCount');
    _log('  - Zero delay count: $zeroDelayCount');
    _log('  - Bunched (<10ms apart): $bunchedCount');

    if (negativeDelayCount > analyzeCount * 0.5) {
      _log(
          '⚠️ TIMING MISMATCH DETECTED: >50% of initial visemes have negative/zero delay');
      _log(
          '   This indicates _audioStartTime was set AFTER the audio actually started playing.');
    }

    if (bunchedCount > analyzeCount * 0.3) {
      _log(
          '⚠️ BUNCHING DETECTED: >30% of initial visemes arrived within 10ms of each other');
      _log(
          '   This corroborates timing misalignment causing the initial "glitch".');
    }
    _log('');
  }

  /// Write summary and print all logs
  Future<void> writeSummaryAndClose({bool downloadFile = false}) async {
    _log('');
    _log('=== FINAL SUMMARY ===');
    _log('Total highlights processed: $_highlightCount');
    _log('Total visemes processed: $_visemeCount');
    _log('Total highlights applied: $_highlightAppliedCount');
    _log('Total visemes applied: $_visemeAppliedCount');

    // Analyze timing gaps
    if (_trackSubscribedTime != null && _audioStartSetTime != null) {
      final gap =
          _audioStartSetTime!.difference(_trackSubscribedTime!).inMilliseconds;
      _log('');
      _log('TIMING GAP ANALYSIS:');
      _log('  Track subscribed -> audioStartTime set: ${gap}ms');
      if (gap > 200) {
        _log(
            '  ⚠️ SIGNIFICANT DELAY: audioStartTime was set ${gap}ms after audio track arrived');
        _log(
            '     This is likely causing the initial lip sync/highlight "glitch".');
      }
    }

    // Viseme statistics
    if (_visemeBuffer.isNotEmpty) {
      final negativeDelays = _visemeBuffer.where((v) => v.delayMs < 0).length;
      final zeroDelays = _visemeBuffer.where((v) => v.delayMs == 0).length;
      final positiveDelays = _visemeBuffer.where((v) => v.delayMs > 0).length;

      _log('');
      _log('VISEME DELAY DISTRIBUTION:');
      _log('  - Negative delays (late): $negativeDelays');
      _log('  - Zero delays: $zeroDelays');
      _log('  - Positive delays (on time): $positiveDelays');
    }

    // Highlight statistics
    if (_highlightBuffer.isNotEmpty) {
      final skipped = _highlightBuffer.where((h) => h.skipped).length;
      final immediate =
          _highlightBuffer.where((h) => h.immediatePartial).length;
      final scheduled =
          _highlightBuffer.where((h) => h.scheduledWithDelay).length;

      _log('');
      _log('HIGHLIGHT SCHEDULING DISTRIBUTION:');
      _log('  - Skipped entirely: $skipped');
      _log('  - Immediate partial: $immediate');
      _log('  - Scheduled with delay: $scheduled');
    }

    logVisemeBunchingAnalysis();

    _log('');
    _log('=== END OF LOG ===');

    if (downloadFile) {
      downloadLogFile();
    }
  }

  /// Dispose resources
  Future<void> dispose({bool downloadFile = false}) async {
    await writeSummaryAndClose(downloadFile: downloadFile);
  }
}

class _VisemeLogEntry {
  final HudaViseme visemeId;
  final String? charText;
  final int audioElapsedMs;
  final int targetMs;
  final int delayMs;
  final bool scheduledWithDelay;
  final bool appliedImmediately;
  final DateTime timestamp;

  _VisemeLogEntry({
    required this.visemeId,
    required this.charText,
    required this.audioElapsedMs,
    required this.targetMs,
    required this.delayMs,
    required this.scheduledWithDelay,
    required this.appliedImmediately,
    required this.timestamp,
  });
}

class _HighlightLogEntry {
  final int charId;
  final String charText;
  final int audioElapsedMs;
  final int charStartMs;
  final int charEndMs;
  final int delayMs;
  final bool scheduledWithDelay;
  final bool skipped;
  final bool immediatePartial;
  final DateTime timestamp;

  _HighlightLogEntry({
    required this.charId,
    required this.charText,
    required this.audioElapsedMs,
    required this.charStartMs,
    required this.charEndMs,
    required this.delayMs,
    required this.scheduledWithDelay,
    required this.skipped,
    required this.immediatePartial,
    required this.timestamp,
  });
}
