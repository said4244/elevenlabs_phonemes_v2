import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

class TopAppBar extends StatelessWidget implements PreferredSizeWidget {
  final String title;

  const TopAppBar({
    super.key,
    this.title = 'Huda',
  });

  @override
  Size get preferredSize => const Size.fromHeight(56);

  @override
  Widget build(BuildContext context) {
    const iconSize = 27.0;
    const smallIconSize = iconSize * 0.75;

    // Hardcoded values for now.
    const cottonValue = '1';
    const progressText = '0/500';
    const streakValue = '1';
    const coinsValue = '69';
    const gemsValue = '16';

    return Material(
      color: Colors.transparent,
      child: SafeArea(
        bottom: false,
        child: SizedBox(
          height: preferredSize.height,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _CottonProgress(
                  iconSize: iconSize,
                  valueText: cottonValue,
                  progressText: progressText,
                ),
                const _IconValue(
                  asset: 'assets/images/streak.svg',
                  valueText: streakValue,
                  iconSize: smallIconSize,
                ),
                const _IconValue(
                  asset: 'assets/images/coins.svg',
                  valueText: coinsValue,
                  iconSize: smallIconSize,
                ),
                const _IconValue(
                  asset: 'assets/images/gems.svg',
                  valueText: gemsValue,
                  iconSize: smallIconSize,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _IconValue extends StatelessWidget {
  final String asset;
  final String valueText;
  final double iconSize;

  const _IconValue({
    required this.asset,
    required this.valueText,
    required this.iconSize,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SvgPicture.asset(
          asset,
          width: iconSize,
          height: iconSize,
        ),
        const SizedBox(width: 6),
        Text(
          valueText,
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: Colors.white,
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
      ],
    );
  }
}

class _CottonProgress extends StatelessWidget {
  final double iconSize;
  final String valueText;
  final String progressText;

  const _CottonProgress({
    required this.iconSize,
    required this.valueText,
    required this.progressText,
  });

  @override
  Widget build(BuildContext context) {
    // Tuned to mimic the screenshot.
    final barHeight = iconSize * 0.42 * 1.75;
    final barWidth = iconSize * 3.1;
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
            child: _ProgressBar(
              width: barWidth,
              height: barHeight,
              text: progressText,
            ),
          ),
          Positioned(
            left: 0,
            top: 0,
            child: SizedBox(
              width: iconSize,
              height: iconSize,
              child: Stack(
                children: [
                  SvgPicture.asset(
                    'assets/images/cotton.svg',
                    width: iconSize,
                    height: iconSize,
                  ),
                  Positioned.fill(
                    child: Center(
                      child: Text(
                        valueText,
                        style: const TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
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
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProgressBar extends StatelessWidget {
  final double width;
  final double height;
  final String text;

  const _ProgressBar({
    required this.width,
    required this.height,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    const radius = BorderRadius.all(Radius.circular(3));

    return SizedBox(
      width: width,
      height: height,
      child: Stack(
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.75),
                borderRadius: radius,
              ),
            ),
          ),
          Positioned.fill(
            child: Center(
              child: Text(
                text,
                style: const TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
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
        ],
      ),
    );
  }
}
