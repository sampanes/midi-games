// Burst-of-sparks effect. Call SparksState.burst through a GlobalKey; the
// ticker runs only while sparks are alive.

import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

class _Spark {
  _Spark(this.position, this.velocity, this.color, this.size);

  Offset position;
  Offset velocity;
  final Color color;
  final double size;
  double life = 1;
}

class Sparks extends StatefulWidget {
  const Sparks({super.key});

  @override
  State<Sparks> createState() => SparksState();
}

class SparksState extends State<Sparks> with SingleTickerProviderStateMixin {
  final List<_Spark> _sparks = [];
  final Random _random = Random();
  late final Ticker _ticker = createTicker(_tick);
  Duration _last = Duration.zero;

  void burst(Offset center, List<Color> colors, {int count = 40, double speed = 520}) {
    for (var i = 0; i < count; i++) {
      final angle = _random.nextDouble() * 2 * pi;
      final v = speed * (0.35 + 0.65 * _random.nextDouble());
      _sparks.add(_Spark(
        center,
        Offset(cos(angle) * v, sin(angle) * v),
        colors[i % colors.length],
        5 + _random.nextDouble() * 9,
      ));
    }
    if (!_ticker.isActive) {
      _last = Duration.zero;
      _ticker.start();
    }
  }

  void _tick(Duration elapsed) {
    final dt = _last == Duration.zero ? 1 / 60 : (elapsed - _last).inMicroseconds / 1e6;
    _last = elapsed;
    for (final s in _sparks) {
      s.position += s.velocity * dt;
      s.velocity = s.velocity * pow(0.18, dt).toDouble() + Offset(0, 420 * dt);
      s.life -= dt / 1.1;
    }
    _sparks.removeWhere((s) => s.life <= 0);
    if (_sparks.isEmpty) _ticker.stop();
    setState(() {});
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: CustomPaint(painter: _SparksPainter(_sparks), size: Size.infinite),
    );
  }
}

class _SparksPainter extends CustomPainter {
  _SparksPainter(this.sparks);

  final List<_Spark> sparks;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint();
    for (final s in sparks) {
      paint.color = s.color.withValues(alpha: s.life.clamp(0, 1));
      canvas.drawCircle(s.position, s.size * (0.4 + 0.6 * s.life), paint);
    }
  }

  @override
  bool shouldRepaint(_SparksPainter oldDelegate) => true;
}
