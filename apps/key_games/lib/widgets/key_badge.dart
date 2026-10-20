// The note letter that picks a menu choice, in its color.

import 'package:flutter/material.dart';

import '../app/theme.dart';
import '../games/color_keys_rules.dart';

class KeyBadge extends StatelessWidget {
  const KeyBadge({super.key, required this.pc, this.size = 44});

  final int pc;
  final double size;

  @override
  Widget build(BuildContext context) {
    final color = pitchColor(pc);
    final dark = color.computeLuminance() > 0.5;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: size * 0.06),
        boxShadow: [BoxShadow(color: color.withValues(alpha: 0.6), blurRadius: size * 0.4)],
      ),
      child: Text(
        pitchClasses[pc].name,
        style: TextStyle(
          fontSize: size * 0.5,
          fontWeight: FontWeight.w900,
          color: dark ? AppColors.ink : Colors.white,
        ),
      ),
    );
  }
}
