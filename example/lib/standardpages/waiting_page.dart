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
  Timer? _timer;

  void _preloadRive() {
    RiveAvatarCache.getTalkingController();
  }

  Future<void> _requestMicThenProceed() async {
    if (_requesting) return;
    setState(() => _requesting = true);

    await MicPermissionService.requestMicrophone();

    if (!mounted) return;

    _timer?.cancel();
    _timer = Timer(const Duration(seconds: 2), () {
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
          const Positioned.fill(
            child: Center(child: CircularProgressIndicator()),
          ),
        ],
      ),
    );
  }
}
