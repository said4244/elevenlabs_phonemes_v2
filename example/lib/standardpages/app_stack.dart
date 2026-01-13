import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/navigation_provider.dart';
import '../widgets/bottom_app_bar.dart';
import '../widgets/top_app_bar.dart';
import 'call_success_page.dart';
import 'characters_page.dart';
import 'fight_page.dart';
import 'friends_page.dart';
import 'main_page.dart';
import 'practice_page.dart';
import 'profile_page.dart';
import 'reward_overlay_page.dart';
import 'splash_page.dart';
import 'training_page.dart';
import 'waiting_page.dart';
import 'call_page.dart';

class AppStack extends StatefulWidget {
  const AppStack({super.key});

  @override
  State<AppStack> createState() => _AppStackState();
}

class _AppStackState extends State<AppStack> {
  // Bottom nav bar order: profile(0), characters(1), main(2), friends(3), training(4)
  static int _navBarIndex(AppPage page) {
    return switch (page) {
      AppPage.profile => 0,
      AppPage.characters => 1,
      AppPage.main => 2,
      AppPage.friends => 3,
      AppPage.training => 4,
      _ => -1, // Not a bottom nav page
    };
  }

  static bool _isNavBarPage(AppPage page) {
    return _navBarIndex(page) >= 0;
  }

  Widget _buildPageContent(AppPage page) {
    return switch (page) {
      AppPage.splash => const SplashPage(),
      AppPage.main => const MainPageContent(),
      AppPage.characters => const CharactersPageContent(),
      AppPage.profile => const ProfilePageContent(),
      AppPage.friends => const FriendsPageContent(),
      AppPage.training => const TrainingPageContent(),
      AppPage.waiting => const WaitingPage(),
      AppPage.call => const CallPage(),
      AppPage.callSuccess => const CallSuccessPage(),
      AppPage.practice => const PracticePage(),
      AppPage.fight => const FightPage(),
    };
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<NavigationProvider>(
      builder: (context, nav, _) {
        // Determine slide direction based on nav bar position
        final currentIndex = _navBarIndex(nav.currentPage);
        final previousIndex = nav.previousPage != null
            ? _navBarIndex(nav.previousPage!)
            : -1;

        // Only animate if both pages are in the bottom nav bar
        final shouldAnimate = currentIndex >= 0 && previousIndex >= 0;
        
        // If going from left to right (e.g., home -> friends), slide from right
        // If going from right to left (e.g., friends -> home), slide from left
        final slideFromRight = currentIndex > previousIndex;

        // Check if current page is a nav bar page (needs fixed bars)
        final isNavBarPage = _isNavBarPage(nav.currentPage);

        if (isNavBarPage) {
          // For nav bar pages: fixed TopAppBar and BottomAppBar with transitioning content
          return Stack(
            children: [
              // Keep the previous page visible underneath during transition
              if (shouldAnimate && nav.previousPage != null)
                Positioned.fill(
                  child: _buildPageContent(nav.previousPage!),
                ),
              // Current page content with slide animation
              Positioned.fill(
                child: shouldAnimate
                    ? _SlideTransitionWrapper(
                        key: ValueKey(nav.currentPage),
                        slideFromRight: slideFromRight,
                        child: _buildPageContent(nav.currentPage),
                      )
                    : _buildPageContent(nav.currentPage),
              ),
              // Fixed TopAppBar (not transitioning)
              const Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: TopAppBar(title: 'Huda'),
              ),
              // Fixed BottomAppBar (not transitioning)
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: BottomAppBarNav(
                  backgroundColor: nav.currentPage == AppPage.characters
                      ? const Color(0xFF232323)
                      : null,
                ),
              ),
              if (nav.rewardOverlayVisible)
                const Positioned.fill(child: RewardOverlayPage()),
            ],
          );
        } else {
          final isWaitingToCall = nav.previousPage == AppPage.waiting &&
              nav.currentPage == AppPage.call;

          final page = _buildPageContent(nav.currentPage);

          // For non-nav bar pages: render the full page, with a special morph
          // transition for Waiting -> Call.
          return Stack(
            children: [
              Positioned.fill(child: page),
              if (isWaitingToCall)
                _WaitingToCallMorphOverlay(),
              if (nav.rewardOverlayVisible)
                const Positioned.fill(child: RewardOverlayPage()),
            ],
          );
        }
      },
    );
  }
}

class _WaitingToCallMorphOverlay extends StatefulWidget {
  const _WaitingToCallMorphOverlay();

  @override
  State<_WaitingToCallMorphOverlay> createState() =>
      _WaitingToCallMorphOverlayState();
}

class _WaitingToCallMorphOverlayState
    extends State<_WaitingToCallMorphOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _t;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 650),
    );
    _t = CurvedAnimation(parent: _controller, curve: Curves.easeInOutCubic);
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        if (_controller.isCompleted) return const SizedBox.shrink();
        final screenSize = MediaQuery.sizeOf(context);
        final w = screenSize.width;
        final h = screenSize.height;

        final endW = w * 0.85;
        final endH = h * 0.60;
        final endLeft = (w - endW) / 2;
        final endTop = h * 0.10;

        final t = _t.value;
        final currentLeft = _lerp(0, endLeft, t);
        final currentTop = _lerp(0, endTop, t);
        final currentWidth = _lerp(w, endW, t);
        final currentHeight = _lerp(h, endH, t);
        final currentRadius = _lerp(0, 20, t);

        return Positioned(
          left: currentLeft,
          top: currentTop,
          width: currentWidth,
          height: currentHeight,
          child: IgnorePointer(
            ignoring: true,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: const Color(0xFF17375A),
                borderRadius: BorderRadius.circular(currentRadius),
              ),
            ),
          ),
        );
      },
    );
  }
}

double _lerp(double start, double end, double t) => start + (end - start) * t;

class _SlideTransitionWrapper extends StatefulWidget {
  const _SlideTransitionWrapper({
    super.key,
    required this.slideFromRight,
    required this.child,
  });

  final bool slideFromRight;
  final Widget child;

  @override
  State<_SlideTransitionWrapper> createState() => _SlideTransitionWrapperState();
}

class _SlideTransitionWrapperState extends State<_SlideTransitionWrapper>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );

    // Slide from right means start at (1, 0) and go to (0, 0)
    // Slide from left means start at (-1, 0) and go to (0, 0)
    final begin = widget.slideFromRight
        ? const Offset(1.0, 0.0)
        : const Offset(-1.0, 0.0);

    _slideAnimation = Tween<Offset>(
      begin: begin,
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
    ));

    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SlideTransition(
      position: _slideAnimation,
      child: widget.child,
    );
  }
}
