import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/navigation_provider.dart';
import '../providers/session_provider.dart';
import '../services/mic_permission_service.dart';
import '../services/rive_avatar_cache.dart';

class WaitingPage extends StatefulWidget {
  const WaitingPage({super.key});

  @override
  State<WaitingPage> createState() => _WaitingPageState();
}

class _WaitingPageState extends State<WaitingPage> {
  bool _requesting = false;
  String? _errorMessage;
  Timer? _timer;

  void _preloadRive() {
    RiveAvatarCache.getTalkingController();
  }

  Future<void> _requestMicThenProceed() async {
    if (_requesting) return;
    setState(() {
      _requesting = true;
      _errorMessage = null;
    });

    // ── 1. Request microphone permission ──────────────────────────────────
    final granted = await MicPermissionService.requestMicrophone();

    if (!mounted) return;

    if (!granted) {
      setState(() {
        _requesting = false;
        _errorMessage = 'Microphone access is required before starting the call.';
      });
      return;
    }

    // ── 2. Prepare session (generates prompt, writes to DB) ───────────────
    final sessionProv = context.read<SessionProvider>();
    final ok = await sessionProv.prepareSession();

    if (!mounted) return;

    if (!ok) {
      setState(() {
        _requesting = false;
        _errorMessage =
            'Could not prepare session: ${sessionProv.lastError ?? 'Unknown error'}';
      });
      return;
    }

    // ── 3. Navigate to CallPage ───────────────────────────────────────────
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
    final errorMessage = _errorMessage;

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
                  ? const _LoadingIndicator()
                  : Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.error_outline, color: Colors.white70, size: 40),
                          const SizedBox(height: 16),
                          Text(
                            errorMessage,
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: Colors.white70, fontSize: 14),
                          ),
                          const SizedBox(height: 24),
                          ElevatedButton(
                            onPressed: _requestMicThenProceed,
                            child: const Text('Try Again'),
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

class _LoadingIndicator extends StatelessWidget {
  const _LoadingIndicator();

  @override
  Widget build(BuildContext context) {
    return const Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        CircularProgressIndicator(color: Colors.white),
        SizedBox(height: 16),
        Text(
          'Preparing your session...',
          style: TextStyle(color: Colors.white70, fontSize: 14),
        ),
      ],
    );
  }
}
