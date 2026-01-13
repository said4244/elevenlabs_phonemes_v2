import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'dart:math' as math;

import '../providers/navigation_provider.dart';

double _topAppBarContentInset(BuildContext context) {
  // Matches the horizontal span of TopAppBar's Row using the same
  // `MainAxisAlignment.spaceEvenly` distribution.
  final screenWidth = MediaQuery.sizeOf(context).width;
  const outerPadding =
      12.0; // TopAppBar uses EdgeInsets.symmetric(horizontal: 12)
  final availableWidth = math.max(0.0, screenWidth - outerPadding * 2);

  const iconSize = 36.0;
  const smallIconSize = iconSize * 0.75;

  // _CottonProgress width in top_app_bar.dart:
  // barLeft + barWidth where barLeft = iconSize * 0.62 and barWidth = iconSize * 3.1
  final cottonWidth = iconSize * 0.62 + iconSize * 3.1;

  const textStyle = TextStyle(
    fontSize: 20,
    fontWeight: FontWeight.w700,
    height: 1,
  );

  double iconValueWidth(String valueText) {
    final painter = TextPainter(
      text: const TextSpan(style: textStyle, text: ''),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..text = TextSpan(style: textStyle, text: valueText);
    painter.layout();
    return smallIconSize + 6 + painter.width;
  }

  // These are hard-coded in TopAppBar.
  const streakValue = '1';
  const coinsValue = '69';
  const gemsValue = '16';

  final childrenTotalWidth = cottonWidth +
      iconValueWidth(streakValue) +
      iconValueWidth(coinsValue) +
      iconValueWidth(gemsValue);

  const childCount = 4;
  final space =
      math.max(0.0, (availableWidth - childrenTotalWidth) / (childCount + 1));

  // In spaceEvenly, left and right edge spacing are equal.
  return outerPadding + space;
}

class MainPageContent extends StatelessWidget {
  const MainPageContent({super.key});

  @override
  Widget build(BuildContext context) {
    final mediaPadding = MediaQuery.paddingOf(context);
    final horizontalInset = _topAppBarContentInset(context);

    return Material(
      type: MaterialType.transparency,
      child: Container(
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
        child: Padding(
          padding: EdgeInsets.only(
            top: mediaPadding.top + 56 + 10,
            bottom: mediaPadding.bottom + 56 + 12,
          ),
          child: Column(
            children: [
              _UserBar(horizontalInset: horizontalInset),
              const SizedBox(height: 8),
              _ChestButtonsRow(horizontalInset: horizontalInset),
              const SizedBox(height: 8),
              LayoutBuilder(
                builder: (context, constraints) {
                  final target = 300.0;
                  final width = math.min(target, constraints.maxWidth);
                  return SvgPicture.asset(
                    'assets/images/hamza_profile.svg',
                    width: width,
                  );
                },
              ),
              const SizedBox(height: 6),
              SvgPicture.asset(
                'assets/images/purple_chests_bubble.svg',
                width: 170,
              ),
              const SizedBox(height: 10),
              _SvgTapButton(
                assetPath: 'assets/images/call_button.svg',
                width: MediaQuery.sizeOf(context).width - (horizontalInset * 2),
                onTap: () {
                  context
                      .read<NavigationProvider>()
                      .goTo(AppPage.waiting);
                },
              ),
              const Spacer(),
            ],
          ),
        ),
      ),
    );
  }
}

class _UserBar extends StatelessWidget {
  const _UserBar({required this.horizontalInset});

  final double horizontalInset;

  static const _fill = Color(0xB0232323);
  static const _radius = 3.0;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width - (horizontalInset * 2);

    return Align(
      alignment: Alignment.topCenter,
      child: SizedBox(
        width: width,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: _fill,
            border: const Border.fromBorderSide(
              BorderSide(
                color: Colors.black,
                width: 1,
              ),
            ),
            borderRadius: const BorderRadius.all(Radius.circular(_radius)),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4.5),
            child: Row(
              children: [
                const Text(
                  'Said4424',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                    height: 1,
                    shadows: const [
                      Shadow(
                        color: Colors.black54,
                        blurRadius: 2,
                        offset: Offset(0, 1),
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                const _CupProgress(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CupProgress extends StatelessWidget {
  const _CupProgress();

  @override
  Widget build(BuildContext context) {
    const valueText = '343';

    // Mirrors the TopAppBar cotton layout: icon overlays the left edge
    // of a short progress bar.
    const iconSize = 22.0;
    final barHeight = iconSize * 0.42 * 1.75;
    final barWidth = iconSize * 2.6;
    final barTop = (iconSize - barHeight) / 2;
    final barLeft = iconSize * 0.62;

    return SizedBox(
      width: barLeft + barWidth,
      height: iconSize + 6,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: barLeft,
            top: barTop,
            child: _CupBar(
              width: barWidth,
              height: barHeight,
              text: valueText,
            ),
          ),
          Positioned(
            left: 0,
            top: 0,
            child: SvgPicture.asset(
              'assets/images/cup.svg',
              width: iconSize,
              height: iconSize,
            ),
          ),
        ],
      ),
    );
  }
}

class _CupBar extends StatelessWidget {
  const _CupBar({
    required this.width,
    required this.height,
    required this.text,
  });

  final double width;
  final double height;
  final String text;

  static const _fill = Color(0xB0232323);
  static const _radius = BorderRadius.all(Radius.circular(3));
  static const _textColor = Color(0xFFFFC800);

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: height,
      child: DecoratedBox(
        decoration: const BoxDecoration(
          color: _fill,
          borderRadius: _radius,
        ),
        child: Center(
          child: Text(
            text,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: _textColor,
              height: 1,
              shadows: [
                Shadow(
                  color: Colors.black54,
                  blurRadius: 2,
                  offset: Offset(0, 1),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ChestButtonsRow extends StatelessWidget {
  const _ChestButtonsRow({required this.horizontalInset});

  final double horizontalInset;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width - (horizontalInset * 2);

    return Align(
      alignment: Alignment.topCenter,
      child: SizedBox(
        width: width,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _SvgTapButton(
              assetPath: 'assets/images/wood_chest_button.svg',
              width: 150,
              onTap: () {},
            ),
            _SvgTapButton(
              assetPath: 'assets/images/green_chest_button.svg',
              width: 150,
              onTap: () {},
            ),
          ],
        ),
      ),
    );
  }
}

class _SvgTapButton extends StatelessWidget {
  const _SvgTapButton({
    required this.assetPath,
    required this.width,
    required this.onTap,
  });

  final String assetPath;
  final double width;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      child: InkResponse(
        onTap: onTap,
        containedInkWell: false,
        highlightShape: BoxShape.rectangle,
        child: SvgPicture.asset(
          assetPath,
          width: width,
          fit: BoxFit.contain,
          alignment: Alignment.center,
          clipBehavior: Clip.none,
          allowDrawingOutsideViewBox: true,
        ),
      ),
    );
  }
}
