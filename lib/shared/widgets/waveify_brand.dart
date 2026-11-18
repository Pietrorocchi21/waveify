import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

class WaveifyMark extends StatelessWidget {
  const WaveifyMark({super.key, this.width = 32});

  final double width;

  @override
  Widget build(BuildContext context) => SvgPicture.asset(
    'assets/images/waveify-mark.svg',
    width: width,
    height: width * .66,
    excludeFromSemantics: true,
  );
}

class WaveifyWordmark extends StatelessWidget {
  const WaveifyWordmark({super.key, this.stacked = false});

  final bool stacked;

  @override
  Widget build(BuildContext context) {
    final label = Text(
      'WAVEIFY',
      style: Theme.of(context).textTheme.titleMedium
          ?.copyWith(fontWeight: FontWeight.w700, letterSpacing: 2.5),
    );
    if (stacked) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const WaveifyMark(width: 76),
          const SizedBox(height: 8),
          label,
        ],
      );
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [const WaveifyMark(), const SizedBox(width: 8), label],
    );
  }
}
