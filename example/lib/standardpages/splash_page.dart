import 'dart:math' as math;

import 'package:circular_reveal_animation/circular_reveal_animation.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';

import '../providers/navigation_provider.dart';
import 'main_page.dart';

class SplashPage extends StatefulWidget {
  const SplashPage({super.key});

  @override
  State<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends State<SplashPage>
    with SingleTickerProviderStateMixin {
  late final VideoPlayerController _videoController;
  late final AnimationController _revealController;
  late final Animation<double> _revealAnimation;

  bool _videoReady = false;
  bool _transitionScheduled = false;
  bool _transitioning = false;
  bool _navigated = false;
  bool _svgsPreloaded = false;

  @override
  void initState() {
    super.initState();

    // Start preloading SVGs in the background
    _preloadSvgs();

    _revealController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 650),
      value: 0,
    );
    _revealAnimation = CurvedAnimation(
      parent: _revealController,
      curve: Curves.easeInOut,
      reverseCurve: Curves.easeInOut,
    );
    _revealController.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        _goToMain();
      }
    });

    _videoController =
        VideoPlayerController.asset('assets/videos/intro_final.mp4')
          ..setLooping(false)
          ..initialize().then((_) {
            if (!mounted) return;
            if (kIsWeb) {
              _videoController.setVolume(0);
            }
            setState(() => _videoReady = true);
            _videoController.play();
          });

    _videoController.addListener(_onVideoTick);
  }

  Future<void> _preloadSvgs() async {
    // List all SVGs used in main_page and characters_page
    final svgAssets = [
      // From main_page.dart
      'assets/images/hamza_profile.svg',
      'assets/images/purple_chests_bubble.svg',
      'assets/images/call_button.svg',
      'assets/images/wood_chest_button.svg',
      'assets/images/green_chest_button.svg',
      'assets/images/cup.svg',
      // From characters_page.dart
      'assets/images/ali_profile.svg',
      'assets/images/common_profile.svg',
      'assets/images/rare_profile.svg',
      'assets/images/legend_profile.svg',
    ];

    try {
      // Preload all SVGs in parallel
      await Future.wait(
        svgAssets.map((asset) => _precacheSvg(asset)),
      );

      if (mounted) {
        setState(() => _svgsPreloaded = true);
      }
    } catch (e) {
      // If preloading fails, continue anyway - SVGs will load on-demand
      debugPrint('SVG preloading failed: $e');
      if (mounted) {
        setState(() => _svgsPreloaded = true);
      }
    }
  }

  Future<void> _precacheSvg(String assetPath) async {
    try {
      final loader = SvgAssetLoader(assetPath);
      await svg.cache
          .putIfAbsent(loader.cacheKey(null), () => loader.loadBytes(null));
    } catch (e) {
      debugPrint('Failed to precache $assetPath: $e');
    }
  }

  void _onVideoTick() {
    if (_transitionScheduled || _transitioning || _navigated) return;
    if (!_videoController.value.isInitialized) return;

    final position = _videoController.value.position;
    final duration = _videoController.value.duration;
    if (duration == Duration.zero) return;

    if (position >= duration) {
      _scheduleRevealTransition();
    }
  }

  void _scheduleRevealTransition() {
    if (_transitionScheduled || _transitioning || _navigated) return;
    _transitionScheduled = true;
    _videoController.pause();

    Future.delayed(const Duration(seconds: 1), () {
      if (!mounted || _transitioning || _navigated) return;
      setState(() => _transitioning = true);
      _revealController.forward(from: 0);
    });
  }

  Future<void> _goToMain() async {
    if (!mounted || _navigated) return;
    _navigated = true;
    
    // Wait for SVGs to finish preloading before navigating
    while (!_svgsPreloaded && mounted) {
      await Future.delayed(const Duration(milliseconds: 50));
    }
    
    if (mounted) {
      context.read<NavigationProvider>().goTo(AppPage.main);
    }
  }

  @override
  void dispose() {
    _videoController.removeListener(_onVideoTick);
    _videoController.dispose();
    _revealController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const backgroundColor = Color(0xFFFFD08B);
    const accentColor = Color(0xFF6C3428);

    return Material(
      color: backgroundColor,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          final videoHeight = width * (16 / 9) * 0.4;
          final fontSize = math.max(28.0, width * 0.12);

          return Stack(
            fit: StackFit.expand,
            children: [
              Container(
                alignment: Alignment.center,
                color: backgroundColor,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SizedBox(
                      height: videoHeight,
                      child: _videoReady
                          ? AspectRatio(
                              aspectRatio: 16 / 9,
                              child: VideoPlayer(_videoController),
                            )
                          : const SizedBox.shrink(),
                    ),
                    const SizedBox(height: 32),
                    Text(
                      'Huda',
                      style: TextStyle(
                        fontSize: fontSize,
                        fontWeight: FontWeight.bold,
                        color: accentColor,
                      ),
                    ),
                    const SizedBox(height: 16),
                    AnimatedOpacity(
                      opacity: _transitioning ? 0 : 1,
                      duration: const Duration(milliseconds: 150),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'جاري الاتصال...',
                            style: TextStyle(
                              fontSize: 16,
                              color: accentColor.withOpacity(0.7),
                            ),
                          ),
                          const SizedBox(height: 8),
                          const CircularProgressIndicator(
                            valueColor:
                                AlwaysStoppedAnimation<Color>(accentColor),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              if (_transitioning)
                IgnorePointer(
                  child: CircularRevealAnimation(
                    animation: _revealAnimation,
                    centerAlignment: Alignment.center,
                    child: const MainPageContent(),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
