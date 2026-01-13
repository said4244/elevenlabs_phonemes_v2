import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../providers/navigation_provider.dart';

class BottomAppBarNav extends StatelessWidget {
  const BottomAppBarNav({super.key, this.backgroundColor});

  final Color? backgroundColor;

  static const double _barHeight = 56;
  static const double _iconSize = 39;
  static const double _largeIconScale = 1.5;
  static const double _selectionScale = 1.25;
  static const Duration _animDuration = Duration(milliseconds: 260);

  static const Color _topBorderColor = Color(0xFF4B4B4B);
  static const Color _selectionFill = Color(0xFF0CC0DF);
  static const Color _selectionBorder = Color(0xFF8DAEB4);

  int _indexForPage(AppPage page) {
    return switch (page) {
      AppPage.profile => 0,
      AppPage.characters => 1,
      AppPage.main => 2,
      AppPage.friends => 3,
      AppPage.training => 4,
      _ => 2,
    };
  }

  @override
  Widget build(BuildContext context) {
    final nav = context.watch<NavigationProvider>();
    final selectedIndex = _indexForPage(nav.currentPage);
    final bottomPadding = MediaQuery.paddingOf(context).bottom;

    // Use consistent selection box size for all navigable pages
    final selectionSize = _iconSize * _largeIconScale * _selectionScale;

    return Container(
      height: _barHeight + bottomPadding,
      decoration: BoxDecoration(
        color: backgroundColor ?? Colors.transparent,
        border: Border(
          top: BorderSide(
            color: _topBorderColor,
            width: 3,
          ),
        ),
      ),
      child: SafeArea(
        top: false,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final segmentWidth = constraints.maxWidth / 5;
            final selectionLeft = (segmentWidth * selectedIndex) +
                (segmentWidth - selectionSize) / 2;
            final selectionTop = (_barHeight - selectionSize) / 2;

            return Stack(
              children: [
                AnimatedPositioned(
                  duration: _animDuration,
                  curve: Curves.easeInOutCubic,
                  left: selectionLeft,
                  top: selectionTop,
                  width: selectionSize,
                  height: selectionSize,
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: _selectionFill.withOpacity(0.39),
                        border: Border.all(
                          color: _selectionBorder,
                          width: 1,
                        ),
                        borderRadius: BorderRadius.circular(9),
                      ),
                    ),
                  ),
                ),
                Row(
                  children: [
                    Expanded(
                      child: Center(
                        child: _NavSvgButton(
                          assetPath: 'assets/images/profile.svg',
                          size: _iconSize,
                          onTap: () => nav.goTo(AppPage.profile),
                        ),
                      ),
                    ),
                    Expanded(
                      child: Center(
                        child: _NavSvgButton(
                          assetPath: 'assets/images/charachtes2.svg',
                          size: _iconSize * _largeIconScale,
                          onTap: () => nav.goTo(AppPage.characters),
                        ),
                      ),
                    ),
                    Expanded(
                      child: Center(
                        child: _NavSvgButton(
                          assetPath: 'assets/images/home.svg',
                          size: _iconSize * _largeIconScale,
                          onTap: () => nav.goTo(AppPage.main),
                        ),
                      ),
                    ),
                    Expanded(
                      child: Center(
                        child: _NavSvgButton(
                          assetPath: 'assets/images/friends.svg',
                          size: _iconSize * _largeIconScale,
                          onTap: () => nav.goTo(AppPage.friends),
                        ),
                      ),
                    ),
                    Expanded(
                      child: Center(
                        child: _NavSvgButton(
                          assetPath: 'assets/images/dumbell.svg',
                          size: _iconSize,
                          onTap: () => nav.goTo(AppPage.training),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _NavSvgButton extends StatelessWidget {
  const _NavSvgButton({
    required this.assetPath,
    required this.size,
    required this.onTap,
  });

  final String assetPath;
  final double size;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;

    return Material(
      type: MaterialType.transparency,
      child: InkResponse(
        onTap: onTap,
        radius: size * 1.2,
        containedInkWell: false,
        child: Opacity(
          opacity: enabled ? 1 : 0.6,
          child: SvgPicture.asset(
            assetPath,
            width: size,
            height: size,
            fit: BoxFit.contain,
            alignment: Alignment.center,
            clipBehavior: Clip.none,
            allowDrawingOutsideViewBox: true,
          ),
        ),
      ),
    );
  }
}
