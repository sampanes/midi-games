// Big rainbow "YAY!" shown when a round or song is finished.

import 'dart:math';

import 'package:flutter/material.dart';

import '../games/color_keys_rules.dart';

Color _pitchColor(int pc) => Color(pitchClasses[pc].argb);

class WinBanner extends StatelessWidget {
  const WinBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final rainbow = [for (final pc in whitePitchClasses) _pitchColor(pc)];
    return IgnorePointer(
      child: Center(
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0.3, end: 1),
          duration: const Duration(milliseconds: 700),
          curve: Curves.elasticOut,
          builder: (context, scale, child) => Transform.scale(scale: scale, child: child),
          child: ShaderMask(
            shaderCallback: (rect) => LinearGradient(colors: rainbow).createShader(rect),
            child: Text(
              'YAY!',
              style: TextStyle(
                fontSize: min(MediaQuery.sizeOf(context).width * 0.28, 220),
                fontWeight: FontWeight.w900,
                color: Colors.white,
                shadows: const [Shadow(color: Colors.black54, blurRadius: 24)],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
