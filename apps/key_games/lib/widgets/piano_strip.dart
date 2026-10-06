// On-screen picture of the real keyboard (37 keys, C to C), colored like
// stickers, with every key of the target color glowing. The physical keys
// have no colors, so this is how a child finds which key to press. It is also
// playable by touch, with several fingers at once.

import 'dart:math';

import 'package:flutter/material.dart';

import '../games/color_keys_rules.dart';

const pianoKeyCount = 37;

// Lowest C shown. The keyboard's octave buttons shift note numbers, so the
// game moves this by whole octaves to keep pressed notes on the picture.
int fitBase(int base, int note) {
  while (note < base) {
    base -= 12;
  }
  while (note > base + pianoKeyCount - 1) {
    base += 12;
  }
  return base;
}

class PianoStrip extends StatefulWidget {
  const PianoStrip({
    super.key,
    required this.base,
    required this.target,
    required this.held,
    required this.onNoteOn,
    required this.onNoteOff,
  });

  final int base;
  final int? target;
  final Set<int> held;
  final void Function(int note) onNoteOn;
  final void Function(int note) onNoteOff;

  @override
  State<PianoStrip> createState() => _PianoStripState();
}

class _PianoStripState extends State<PianoStrip> with SingleTickerProviderStateMixin {
  late final AnimationController _glow =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 700))
        ..repeat(reverse: true);
  final Map<int, int> _pointerNotes = {};

  @override
  void dispose() {
    _glow.dispose();
    super.dispose();
  }

  void _down(PointerDownEvent event, Size size) {
    final note = _PianoLayout(widget.base, size).noteAt(event.localPosition);
    if (note == null) return;
    _pointerNotes[event.pointer] = note;
    widget.onNoteOn(note);
  }

  void _up(PointerEvent event) {
    final note = _pointerNotes.remove(event.pointer);
    if (note != null) widget.onNoteOff(note);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.biggest;
        return Listener(
          onPointerDown: (event) => _down(event, size),
          onPointerUp: _up,
          onPointerCancel: _up,
          child: AnimatedBuilder(
            animation: _glow,
            builder: (context, _) => CustomPaint(
              size: size,
              painter: _PianoPainter(
                layout: _PianoLayout(widget.base, size),
                target: widget.target,
                held: widget.held,
                glow: Curves.easeInOut.transform(_glow.value),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _PianoLayout {
  _PianoLayout(this.base, this.size) {
    for (var note = base; note < base + pianoKeyCount; note++) {
      if (pitchClasses[pitchClass(note)].white) whites.add(note);
    }
    whiteWidth = size.width / whites.length;
    blackWidth = whiteWidth * 0.62;
    blackHeight = size.height * 0.6;
  }

  final int base;
  final Size size;
  final List<int> whites = [];
  late final double whiteWidth;
  late final double blackWidth;
  late final double blackHeight;

  Rect whiteRect(int index) => Rect.fromLTWH(index * whiteWidth, 0, whiteWidth, size.height);

  // A black key sits on the line after the white key just below it.
  Rect blackRect(int note) {
    final below = whites.indexOf(note - 1);
    final x = (below + 1) * whiteWidth - blackWidth / 2;
    return Rect.fromLTWH(x, 0, blackWidth, blackHeight);
  }

  Iterable<int> get blacks sync* {
    for (var note = base; note < base + pianoKeyCount; note++) {
      if (!pitchClasses[pitchClass(note)].white) yield note;
    }
  }

  int? noteAt(Offset point) {
    for (final note in blacks) {
      if (blackRect(note).contains(point)) return note;
    }
    for (var i = 0; i < whites.length; i++) {
      if (whiteRect(i).contains(point)) return whites[i];
    }
    return null;
  }
}

class _PianoPainter extends CustomPainter {
  _PianoPainter({
    required this.layout,
    required this.target,
    required this.held,
    required this.glow,
  });

  final _PianoLayout layout;
  final int? target;
  final Set<int> held;
  final double glow;

  @override
  void paint(Canvas canvas, Size size) {
    final fill = Paint();
    final edge = Paint()
      ..style = PaintingStyle.stroke
      ..color = const Color(0xFF14111C)
      ..strokeWidth = 2;
    // Ring width scales with the key: portrait phones have narrow keys.
    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..color = Colors.white
      ..strokeWidth = layout.whiteWidth * (0.06 + 0.06 * glow);

    for (var i = 0; i < layout.whites.length; i++) {
      final note = layout.whites[i];
      final pc = pitchClass(note);
      final color = Color(pitchClasses[pc].argb);
      final isTarget = pc == target;
      final isHeld = held.contains(note);
      final rect = layout.whiteRect(i).deflate(1.5);
      final rounded = RRect.fromRectAndCorners(
        rect,
        bottomLeft: const Radius.circular(8),
        bottomRight: const Radius.circular(8),
      );
      // Other keys keep their sticker color but dimmed, so the target keys
      // are clearly the brightest thing on the keyboard.
      fill.color = isHeld
          ? Color.lerp(color, Colors.black, 0.25)!
          : isTarget
              ? color
              : Color.lerp(color, const Color(0xFF14111C), 0.6)!;
      canvas.drawRRect(rounded, fill);
      canvas.drawRRect(rounded, edge);
      if (isTarget) {
        canvas.drawRRect(rounded.deflate(ring.strokeWidth / 2), ring);
        // Bouncing dot near the bottom: "press here".
        final dot = Offset(rect.center.dx, rect.bottom - rect.width * (0.7 + 0.35 * glow));
        fill.color = Colors.white;
        canvas.drawCircle(dot, rect.width * 0.24, fill);
      }
    }

    for (final note in layout.blacks) {
      final rect = layout.blackRect(note);
      final rounded = RRect.fromRectAndCorners(
        rect,
        bottomLeft: const Radius.circular(5),
        bottomRight: const Radius.circular(5),
      );
      fill.color = held.contains(note) ? const Color(0xFF4A4458) : const Color(0xFF1E1A26);
      canvas.drawRRect(rounded, fill);
      // Small sticker dot in the key's own color.
      fill.color = Color(pitchClasses[pitchClass(note)].argb);
      canvas.drawCircle(
        Offset(rect.center.dx, rect.bottom - rect.width * 0.45),
        min(rect.width * 0.26, 9),
        fill,
      );
    }
  }

  @override
  bool shouldRepaint(_PianoPainter old) => true;
}
