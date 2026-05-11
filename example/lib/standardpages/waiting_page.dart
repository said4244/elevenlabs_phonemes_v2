import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/navigation_provider.dart';
import '../services/mic_permission_service.dart';
import '../services/rive_avatar_cache.dart';

class WaitingPage extends StatefulWidget {
  const WaitingPage({super.key});

  @override
  State<WaitingPage> createState() => _WaitingPageState();
}

class _WaitingPageState extends State<WaitingPage> {
  bool _requesting = false;
  String? _permissionError;
  Timer? _timer;

  void _preloadRive() {
    RiveAvatarCache.getTalkingController();
  }

  Future<void> _requestMicThenProceed() async {
    if (_requesting) return;
    setState(() {
      _requesting = true;
      _permissionError = null;
    });

    final granted = await MicPermissionService.requestMicrophone();

    if (!mounted) return;

    if (!granted) {
      setState(() {
        _requesting = false;
        _permissionError =
            'Microphone access is required before starting the call.';
      });
      return;
    }

    _timer?.cancel();
    _timer = Timer(const Duration(milliseconds: 250), () {
      if (!mounted) return;
      context.read<NavigationProvider>().goTo(AppPage.call);
    });
  }

  @override
  void initState() {
    super.initState();
    _preloadRive();
    _requestMicThenProceed();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final errorMessage = _permissionError;

    return Scaffold(
      body: Stack(
        children: [
          const Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(color: Color(0xFF17375A)),
            ),
          ),
          Positioned.fill(
            child: Container(
              color: Colors.black.withAlpha((0.75 * 255).round()),
            ),
          ),
          Positioned.fill(
            child: Center(
              child: errorMessage == null
                  ? const CircularProgressIndicator()
                  : Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.mic_off,
                            color: Colors.white,
                            size: 40,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            errorMessage,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 16),
                          ElevatedButton(
                            onPressed: _requestMicThenProceed,
                            child: const Text('Allow Microphone'),
                          ),
                        ],
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
