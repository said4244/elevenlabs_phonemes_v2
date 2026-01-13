import 'package:flutter/material.dart';

class RewardOverlayPage extends StatelessWidget {
  const RewardOverlayPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.green.withAlpha((0.5 * 255).round()),
    );
  }
}
