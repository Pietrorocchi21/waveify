import 'package:flutter/material.dart';

class ListeningBackdrop extends StatelessWidget {
  const ListeningBackdrop({super.key});

  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [
      Image.asset(
        'assets/images/listening-room.webp',
        fit: BoxFit.cover,
        excludeFromSemantics: true,
        errorBuilder: (_, _, _) => const SizedBox.shrink(),
      ),
      const DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0x66101529), Color(0xA6192036), Color(0x73101A2E)],
          ),
        ),
      ),
    ],
  );
}
