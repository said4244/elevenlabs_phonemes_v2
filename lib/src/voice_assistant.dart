import 'dart:async';
import 'package:flutter/foundation.dart';
import 'connection_manager.dart';
import 'web_audio_manager.dart';
import 'logger.dart';

enum ConnectionState {
  disconnected,
  connecting,
  connected,
  error,
}

class VoiceAssistantConfig {
  final String tokenUrl;
  final String? livekitUrl;
  final bool enableLogging;

  const VoiceAssistantConfig({
    required this.tokenUrl,
    this.livekitUrl,
    this.enableLogging = true,
  });
}

class VoiceAssistant {
  final VoiceAssistantConfig config;
  late final ConnectionManager _connectionManager;

  ConnectionState _state = ConnectionState.disconnected;
  String _statusMessage = 'Disconnected';
  final _stateController = StreamController<ConnectionState>.broadcast();
  final _statusController = StreamController<String>.broadcast();
  final _eventController = StreamController<Map<String, dynamic>>.broadcast();
  final _transcriptionController =
      StreamController<Map<String, dynamic>>.broadcast();

  VoiceAssistant({required this.config}) {
    if (config.enableLogging) {
      VoiceAssistantLogger.info('Initializing VoiceAssistant');
      VoiceAssistantLogger.info('Token URL: ${config.tokenUrl}');
      VoiceAssistantLogger.info(
          'LiveKit URL: ${config.livekitUrl ?? "default"}');
      VoiceAssistantLogger.info('Platform: ${kIsWeb ? "Web" : "Native"}');
    }

    _connectionManager = ConnectionManager(
      tokenUrl: config.tokenUrl,
      livekitUrl: config.livekitUrl,
      onStatusChanged: _handleStatusChange,
      onEvent: _handleEvent,
    );

    WebAudioManager.logWebAudioState();
  }

  // Simple API - just three methods!
  Future<void> start() async {
    if (_state == ConnectionState.connected ||
        _state == ConnectionState.connecting) {
      VoiceAssistantLogger.warning('Already connected or connecting');
      return;
    }

    VoiceAssistantLogger.info('Starting voice assistant');
    _updateState(ConnectionState.connecting);

    try {
      // Request permissions if on web
      if (kIsWeb) {
        await WebAudioManager.requestMicrophonePermission();
      }

      // Connect to LiveKit
      await _connectionManager.connect();
      _updateState(ConnectionState.connected);

      VoiceAssistantLogger.info('Voice assistant started successfully');
    } catch (e) {
      VoiceAssistantLogger.error('Failed to start voice assistant', e);
      _updateState(ConnectionState.error);
      _statusMessage = 'Error: ${e.toString()}';
      rethrow;
    }
  }

  Future<void> stop() async {
    if (_state == ConnectionState.disconnected) {
      VoiceAssistantLogger.warning('Already disconnected');
      return;
    }

    VoiceAssistantLogger.info('Stopping voice assistant');

    try {
      await _connectionManager.disconnect();
      _updateState(ConnectionState.disconnected);
      VoiceAssistantLogger.info('Voice assistant stopped');
    } catch (e) {
      VoiceAssistantLogger.error('Error stopping voice assistant', e);
    }
  }

  void dispose() {
    VoiceAssistantLogger.info('Disposing voice assistant');
    stop();
    _stateController.close();
    _statusController.close();
    _eventController.close();
    _transcriptionController.close();
    _connectionManager.dispose();
  }

  // State and status
  ConnectionState get state => _state;
  String get status => _statusMessage;
  bool get isConnected => _state == ConnectionState.connected;
  bool get hasAgent => _connectionManager.hasAgent;

  // Streams for UI updates
  Stream<ConnectionState> get stateStream => _stateController.stream;
  Stream<String> get statusStream => _statusController.stream;
  Stream<Map<String, dynamic>> get eventStream => _eventController.stream;
  Stream<Map<String, dynamic>> get transcriptionStream =>
      _transcriptionController.stream;

  // Private methods
  void _updateState(ConnectionState newState) {
    _state = newState;
    _stateController.add(newState);
    VoiceAssistantLogger.debug('State updated: $newState');
  }

  void _handleStatusChange(String status) {
    _statusMessage = status;
    _statusController.add(status);

    // Update connection state based on status
    if (status.toLowerCase().contains('connected') &&
        !status.toLowerCase().contains('dis')) {
      if (status.toLowerCase().contains('ready')) {
        _updateState(ConnectionState.connected);
      }
    } else if (status.toLowerCase().contains('connecting')) {
      _updateState(ConnectionState.connecting);
    } else if (status.toLowerCase().contains('disconnected')) {
      _updateState(ConnectionState.disconnected);
    } else if (status.toLowerCase().contains('error') ||
        status.toLowerCase().contains('failed')) {
      _updateState(ConnectionState.error);
    }
  }

  void _handleEvent(String event, Map<String, dynamic> data) {
    _eventController.add({
      'type': event,
      'data': data,
      'timestamp': DateTime.now().toIso8601String(),
    });

    // Handle transcription events - pass full data including timing
    if (event == 'transcription') {
      _transcriptionController.add(data);
    }
  }
}
