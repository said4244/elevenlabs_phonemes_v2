import 'package:flutter/material.dart';

class FriendsPageContent extends StatelessWidget {
  const FriendsPageContent({super.key});

  @override
  Widget build(BuildContext context) {
    final mediaPadding = MediaQuery.paddingOf(context);

    return Container(
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
        child: const Column(
          children: [
            Spacer(),
          ],
        ),
      ),
    );
  }
}
