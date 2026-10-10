// On-screen picture of the real keyboard (37 keys, C to C), colored like
// stickers, with every key of the target color glowing. The physical keys
// have no colors, so this is how a child finds which key to press. It is also
// playable by touch, with several fingers at once.
//
// [plain] draws it like the real keyboard (no sticker colors) for games where
// the sound is the clue; only a target, if any, lights up in its color.

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

// The keys from [low] to [high], widened to start and end on white keys.
({int low, int high}) whiteSpan(int low, int high) {
  while (!pitchClasses[pitchClass(low)].white) {
    low--;
  }
  while (!pitchClasses[pitchClass(high)].white) {
    high++;
  }
  return (low: low, high: high);
}

// Where [note]'s key sits across a strip [width] wide showing [low]..[high]
// (from [whiteSpan]), so things drawn above the strip line up with its keys.
({double left, double width}) keyColumn(int low, int high, double width, int note) {
  final layout = _PianoLayout(low, high, Size(width, 1));
  if (pitchClasses[pitchClass(note)].white) {
    final rect = layout.whiteRect(layout.whites.indexOf(note));
    return (left: rect.left, width: rect.width);
  }
  final rect = layout.blackRect(note);
  return (left: rect.left, width: rect.width);
}

class PianoStrip extends StatefulWidget {
  const PianoStrip({
    super.key,
    required this.base,
    this.span,
    this.target,
    this.targetNote,
    this.plain = false,
    this.choices,
    required this.held,
    required this.onNoteOn,
    required this.onNoteOff,
  });

  final int base;

  // Only these keys (low to high, from [whiteSpan]) instead of all 37 from
  // [base]: easy levels show just the keys a song needs.
  final ({int low, int high})? span;

  // Glow every key of this pitch class (0-11), or only the exact key
  // [targetNote] (songs, where the octave matters for the picture).
  final int? target;
  final int? targetNote;

  // No sticker colors. [choices] (pitch classes) are drawn a little lighter
  // than the other keys, to show which notes a level uses.
  final bool plain;
  final List<int>? choices;
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

  _PianoLayout _layout(Size size) {
    final span = widget.span ?? (low: widget.base, high: widget.base + pianoKeyCount - 1);
    return _PianoLayout(span.low, span.high, size);
  }

  void _down(PointerDownEvent event, Size size) {
    final note = _layout(size).noteAt(event.localPosition);
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
                layout: _layout(size),
                target: widget.target,
                targetNote: widget.targetNote,
                plain: widget.plain,
                choices: widget.choices,
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
  _PianoLayout(this.low, this.high, this.size) {
    for (var note = low; note <= high; note++) {
      if (pitchClasses[pitchClass(note)].white) whites.add(note);
    }
    whiteWidth = size.width / whites.length;
    blackWidth = whiteWidth * 0.62;
    blackHeight = size.height * 0.6;
    // Marks (dots, rings, letters) are sized by the key, but no bigger than
    // the strip's height allows: a few keys across a wide screen are wide.
    whiteUnit = min(whiteWidth, size.height * 0.4);
    blackUnit = whiteUnit * 0.62;
  }

  final int low;
  final int high;
  final Size size;
  final List<int> whites = [];
  late final double whiteWidth;
  late final double blackWidth;
  late final double blackHeight;
  late final double whiteUnit;
  late final double blackUnit;

  Rect whiteRect(int index) => Rect.fromLTWH(index * whiteWidth, 0, whiteWidth, size.height);

  // A black key sits on the line after the white key just below it.
  Rect blackRect(int note) {
    final below = whites.indexOf(note - 1);
    final x = (below + 1) * whiteWidth - blackWidth / 2;
    return Rect.fromLTWH(x, 0, blackWidth, blackHeight);
  }

  Iterable<int> get blacks sync* {
    for (var note = low; note <= high; note++) {
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
    required this.targetNote,
    required this.plain,
    required this.choices,
    required this.held,
    required this.glow,
  });

  final _PianoLayout layout;
  final int? target;
  final int? targetNote;
  final bool plain;
  final List<int>? choices;
  final Set<int> held;
  final double glow;

  bool _isTarget(int note) =>
      targetNote != null ? note == targetNote : pitchClass(note) == target;

  bool _isChoice(int note) => choices == null || choices!.contains(pitchClass(note));

  // Unlit key color in plain mode: slate like the real keys, lighter when
  // the key is one of the level's notes.
  Color _plainWhite(int note) =>
      _isChoice(note) ? const Color(0xFF4A4360) : const Color(0xFF28232F);

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
      ..strokeWidth = layout.whiteUnit * (0.06 + 0.06 * glow);

    for (var i = 0; i < layout.whites.length; i++) {
      final note = layout.whites[i];
      final pc = pitchClass(note);
      final color = Color(pitchClasses[pc].argb);
      final isTarget = _isTarget(note);
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
          ? (plain && !isTarget ? const Color(0xFF7A7090) : Color.lerp(color, Colors.black, 0.25)!)
          : isTarget
              ? color
              : plain
                  ? _plainWhite(note)
                  : Color.lerp(color, const Color(0xFF14111C), 0.6)!;
      canvas.drawRRect(rounded, fill);
      canvas.drawRRect(rounded, edge);
      final unit = layout.whiteUnit;
      _drawLetter(canvas, pitchClasses[pc].name, rect, unit, isTarget ? color : null);
      if (isTarget) {
        canvas.drawRRect(rounded.deflate(ring.strokeWidth / 2), ring);
        // Bouncing dot above the letter: "press here".
        final dot = Offset(rect.center.dx, rect.bottom - unit * (1.6 + 0.35 * glow));
        fill.color = Colors.white;
        canvas.drawCircle(dot, unit * 0.24, fill);
      }
    }

    for (final note in layout.blacks) {
      final rect = layout.blackRect(note);
      final rounded = RRect.fromRectAndCorners(
        rect,
        bottomLeft: const Radius.circular(5),
        bottomRight: const Radius.circular(5),
      );
      final color = Color(pitchClasses[pitchClass(note)].argb);
      final isTarget = _isTarget(note);
      fill.color = isTarget
          ? color
          : held.contains(note)
              ? const Color(0xFF6A6080)
              : plain && _isChoice(note) && choices != null
                  ? const Color(0xFF3A3448)
                  : const Color(0xFF1E1A26);
      canvas.drawRRect(rounded, fill);
      if (isTarget) {
        canvas.drawRRect(rounded.deflate(ring.strokeWidth / 2), ring);
        fill.color = Colors.white;
        canvas.drawCircle(
          Offset(rect.center.dx, rect.bottom - layout.blackUnit * (0.8 + 0.4 * glow)),
          layout.blackUnit * 0.28,
          fill,
        );
        continue;
      }
      if (plain) continue;
      // Small sticker dot in the key's own color.
      fill.color = color;
      canvas.drawCircle(
        Offset(rect.center.dx, rect.bottom - layout.blackUnit * 0.45),
        min(layout.blackUnit * 0.26, 9),
        fill,
      );
    }
  }

  // Note letter at the bottom of a white key. On a lit key the text color
  // depends on the key color (dark on yellow, white on blue).
  void _drawLetter(Canvas canvas, String letter, Rect rect, double unit, Color? litColor) {
    final dark = litColor != null && litColor.computeLuminance() > 0.5;
    final text = TextPainter(
      text: TextSpan(
        text: letter,
        style: TextStyle(
          fontSize: min(unit * 0.6, 22),
          fontWeight: FontWeight.w800,
          color: litColor == null ? Colors.white60 : (dark ? const Color(0xFF2A2233) : Colors.white),
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    text.paint(
      canvas,
      Offset(rect.center.dx - text.width / 2, rect.bottom - text.height - unit * 0.25),
    );
  }

  @override
  bool shouldRepaint(_PianoPainter old) => true;
}
