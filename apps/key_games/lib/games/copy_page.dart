// Copy Cat screen: the game plays a pattern on a row of big pads (each lights
// up and sounds), then the player plays it back on the keyboard. A pattern
// played back right grows by one note; a wrong note shows the pattern again.
//
// Easy's pads are the low, middle and high part of the keyboard (any key in
// the part counts, and the keyboard picture is tinted by part); it cannot be
// lost, and a pattern of six is a win. Medium's pads are C, E and G, Hard's
// C D E F G, both in their colors on the keyboard picture, with three hearts.
// Expert has every white key and is by ear: the pads stay dark while the
// pattern plays. A key that is not one of the pads only sounds.
//
// The dots under the pads count the pattern: one per note, filled as it is
// played back. At the end (out of hearts): the longest pattern, the best on
// the device, and C plays again, E goes back to the menu.
//
// Input: the keyboard and the computer keys, through the key router, plus
// touching the pads or the keyboard picture.

import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import '../app/services.dart';
import '../app/settings.dart';
import '../app/theme.dart';
import '../audio/synth.dart';
import '../midi/midi_input.dart';
import '../widgets/game_page.dart';
import '../widgets/key_badge.dart';
import '../widgets/piano_strip.dart';
import '../widgets/sparks.dart';
import '../widgets/win_banner.dart';
import '../widgets/zones.dart';
import 'color_keys_rules.dart';
import 'copy_rules.dart';
import 'difficulty.dart';

const _firstDelay = Duration(milliseconds: 1200);
const _growDelay = Duration(milliseconds: 1100);
const _missDelay = Duration(milliseconds: 1300);
const _winDelay = Duration(milliseconds: 3000);

const copyLevelsText = {
  Difficulty.easy: 'Low, middle or high: copy the pattern',
  Difficulty.medium: 'C, E and G: copy the pattern',
  Difficulty.hard: 'C D E F G: longer and faster',
  Difficulty.expert: 'All the white keys, by ear',
};

// Best scores on the device per level (Easy has none: it cannot be lost).
const copyBestKeys = {
  Difficulty.medium: 'copy.medium',
  Difficulty.hard: 'copy.hard',
  Difficulty.expert: 'copy.expert',
};

enum _Phase { watching, turn, between, done }

class CopyPage extends StatefulWidget {
  const CopyPage({super.key, this.difficulty = Difficulty.easy, this.random});

  final Difficulty difficulty;

  // Fixed in tests.
  final Random? random;

  @override
  State<CopyPage> createState() => _CopyPageState();
}

class _CopyPageState extends State<CopyPage> with SingleTickerProviderStateMixin {
  // Looked up when the page opens: a page left before it made a sound must
  // not look it up while it closes.
  late final Synth _synth;
  late final Settings _settings = AppServices.of(context).settings;
  late final Random _random = widget.random ?? Random();
  late final CopyLevel _rules = copyLevels[widget.difficulty]!;
  late final AnimationController _shake =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 420));
  final GlobalKey<SparksState> _sparksKey = GlobalKey();
  final GlobalKey _padsKey = GlobalKey();
  final List<Timer> _timers = [];
  Timer? _flashTimer;

  late CopyState _state = CopyState.start(_rules, _random);
  _Phase _phase = _Phase.between;

  // The pad lit now: the pattern playing, or the player's last right note.
  int? _lit;
  String _status = 'Watch and listen';
  bool _celebrating = false;
  bool _canPick = false;
  bool _newBest = false;
  int _base = 48;
  final Set<int> _held = {};

  bool get _zones => _rules.zones;
  String? get _bestKey => copyBestKeys[widget.difficulty];

  @override
  void initState() {
    super.initState();
    _synth = AppServices.of(context).synth;
    // The first pattern once the synth has had time to load.
    _later(_firstDelay, _playPattern);
  }

  @override
  void dispose() {
    _cancelTimers();
    for (final note in _held) {
      _synth.noteOff(note);
    }
    _shake.dispose();
    super.dispose();
  }

  // Lights a pad for a moment: the player's right note.
  void _flash(int answer) {
    _flashTimer?.cancel();
    setState(() => _lit = answer);
    _flashTimer = Timer(const Duration(milliseconds: 260), () {
      if (mounted && _phase == _Phase.turn) setState(() => _lit = null);
    });
  }

  void _cancelTimers() {
    _flashTimer?.cancel();
    for (final timer in _timers) {
      timer.cancel();
    }
    _timers.clear();
  }

  void _later(Duration delay, void Function() action) {
    _timers.add(Timer(delay, () {
      if (mounted) action();
    }));
  }

  Color _color(int answer) =>
      _zones ? zoneColors(copyZoneCount)[answer] : pitchColor(answer);

  String _name(int answer) =>
      _zones ? zoneNames(copyZoneCount)[answer] : pitchClasses[answer].name;

  // The game plays the pattern, one pad after another, then it is the
  // player's turn.
  void _playPattern() {
    _cancelTimers();
    setState(() {
      _phase = _Phase.watching;
      _lit = null;
      _status = _rules.shown ? 'Watch and listen' : 'Listen';
    });
    final pattern = _state.pattern;
    final step = _rules.stepMs;
    for (var i = 0; i < pattern.length; i++) {
      _later(Duration(milliseconds: 300 + i * step), () {
        setState(() => _lit = pattern[i]);
        _synth.blip(copyNote(_rules, pattern[i]), velocity: 90, lengthMs: step * 6 ~/ 10);
      });
      _later(Duration(milliseconds: 300 + i * step + step * 7 ~/ 10), () {
        setState(() => _lit = null);
      });
    }
    _later(Duration(milliseconds: 300 + pattern.length * step), () {
      setState(() {
        _phase = _Phase.turn;
        _status = 'Your turn!';
      });
    });
  }

  void _restart() {
    _cancelTimers();
    setState(() {
      _state = CopyState.start(_rules, _random);
      _phase = _Phase.between;
      _lit = null;
      _celebrating = false;
      _canPick = false;
      _newBest = false;
      _status = 'Watch and listen';
    });
    _later(const Duration(milliseconds: 600), _playPattern);
  }

  void _onNote(NoteEvent event) {
    if (!isGameNote(event.note)) return;
    if (!event.on) {
      // On Easy a key sounds as its part's note, a blip that ends by itself.
      if (!_zones) _synth.noteOff(event.note);
      setState(() => _held.remove(event.note));
      return;
    }
    final base = fitBase(_base, event.note);
    final answer = _zones
        ? zoneOf(event.note, pictureKeys(context, base), copyZoneCount)
        : pitchClass(event.note);
    if (_zones) {
      _synth.blip(copyNote(_rules, answer), velocity: event.velocity, lengthMs: 300);
    } else {
      _synth.noteOn(event.note, event.velocity);
    }
    setState(() {
      _base = base;
      _held.add(event.note);
    });
    _answer(answer);
  }

  // A pad touched on the screen: it sounds, and answers.
  void _tapPad(int answer) {
    _synth.blip(copyNote(_rules, answer), velocity: 100, lengthMs: 300);
    _answer(answer);
  }

  void _answer(int answer) {
    if (_phase != _Phase.turn) return;
    final step = pressCopy(_state, answer, _rules);
    if (step.result == CopyResult.ignored) return;
    setState(() => _state = step.state);
    switch (step.result) {
      case CopyResult.hit:
        _flash(answer);
      case CopyResult.patternDone:
        setState(() {
          _lit = answer;
          _phase = _Phase.between;
          _status = 'Yes!';
        });
        _celebrate(answer, big: false);
        _later(_growDelay, () {
          setState(() => _state = growCopy(_state, _rules, _random));
          _playPattern();
        });
      case CopyResult.won:
        setState(() {
          _lit = answer;
          _phase = _Phase.between;
          _celebrating = true;
          _status = 'You did it!';
        });
        _celebrate(answer, big: true);
        _later(_winDelay, _restart);
      case CopyResult.miss:
        _shake.forward(from: 0);
        setState(() {
          _lit = null;
          _phase = _Phase.between;
          _status = 'Watch again';
        });
        _later(_missDelay, _playPattern);
      case CopyResult.over:
        _shake.forward(from: 0);
        final key = _bestKey;
        setState(() {
          _lit = null;
          _phase = _Phase.done;
          _newBest = key != null && _settings.recordBest(key, _state.best);
        });
        _later(const Duration(milliseconds: 1500), () => setState(() => _canPick = true));
      case CopyResult.ignored:
        break;
    }
  }

  void _celebrate(int answer, {required bool big}) {
    final color = _color(answer);
    final sparks = _sparksKey.currentState;
    if (big) {
      final rainbow = [for (final pc in whitePitchClasses) pitchColor(pc)];
      final size = MediaQuery.sizeOf(context);
      for (var i = 0; i < 5; i++) {
        _later(Duration(milliseconds: 250 * i), () {
          final at = Offset(
            size.width * (0.15 + 0.7 * _random.nextDouble()),
            size.height * (0.2 + 0.5 * _random.nextDouble()),
          );
          sparks?.burst(at, rainbow, count: 50, speed: 650);
        });
      }
      _later(const Duration(milliseconds: 350),
          () => _synth.tune([84, 88, 91, 96, 91, 96], stepMs: 130, lengthMs: 200));
      return;
    }
    sparks?.burst(_padsCenter(), [color, Colors.white, AppColors.starGold]);
    _later(const Duration(milliseconds: 350),
        () => _synth.tune([84, 91], stepMs: 70, lengthMs: 150));
  }

  Offset _padsCenter() {
    final pads = _padsKey.currentContext?.findRenderObject() as RenderBox?;
    final sparks = _sparksKey.currentContext?.findRenderObject() as RenderBox?;
    if (pads == null || sparks == null) return Offset.zero;
    return sparks.globalToLocal(pads.localToGlobal(pads.size.center(Offset.zero)));
  }

  @override
  Widget build(BuildContext context) {
    final done = _phase == _Phase.done;
    final lit = _lit;
    final tint = lit == null ? AppColors.mystery : _color(lit);
    // The pattern lights the keyboard picture too, unless it is by ear.
    final showLit = _phase == _Phase.watching ? _rules.shown : true;
    return GamePage(
      picks: done && _canPick
          ? {0: _restart, 4: () => Navigator.maybePop(context)}
          : const {},
      onNote: _onNote,
      backdrop: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        decoration: BoxDecoration(
          gradient: RadialGradient(
            colors: [tint.withValues(alpha: showLit ? 0.3 : 0.4), AppColors.background],
            radius: 0.9,
          ),
        ),
      ),
      header: _header(),
      body: done ? Center(child: _buildEnd()) : _buildBoard(showLit),
      // Hidden at the end, so the end choices fit a landscape phone.
      footer: [
        if (!done && _zones)
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
            child: ZoneBar(
              count: copyZoneCount,
              picture: pictureKeys(context, _base),
              lit: showLit ? lit : null,
            ),
          ),
        if (!done)
          Padding(
            padding: EdgeInsets.fromLTRB(8, _zones ? 4 : 8, 8, 8),
            child: SizedBox(
              height: pianoStripHeight(context, design: 140, share: 0.2),
              child: PianoStrip(
                base: _base,
                plain: true,
                target: !_zones && showLit ? lit : null,
                choices: _zones ? null : _rules.choices,
                colorChoices: _rules.shown,
                zones: _zones ? copyZoneCount : null,
                litZone: _zones && showLit ? lit : null,
                held: _held,
                onNoteOn: (note) => _onNote(NoteEvent(note, 100, on: true)),
                onNoteOff: (note) => _onNote(NoteEvent(note, 0, on: false)),
              ),
            ),
          ),
      ],
      overlays: [
        Positioned.fill(child: IgnorePointer(child: Sparks(key: _sparksKey))),
        if (_celebrating) const WinBanner(),
      ],
    );
  }

  List<Widget> _header() {
    final scale = uiScale(context);
    final hearts = _rules.hearts;
    return [
      Icon(Icons.star_rounded, color: AppColors.starGold, size: 36 * scale),
      const SizedBox(width: 4),
      Text('${_state.best}', style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w900)),
      const SizedBox(width: 14),
      if (hearts != null)
        for (var i = 0; i < hearts; i++)
          Icon(Icons.favorite_rounded,
              size: 30 * scale,
              color: i < _state.heartsLeft(_rules) ? AppColors.red : Colors.white24),
      const Spacer(),
    ];
  }

  // The status line, the pads, and the dots that count the pattern.
  Widget _buildBoard(bool showLit) {
    final scale = uiScale(context);
    final choices = _rules.choices;
    return Padding(
      padding: EdgeInsets.fromLTRB(12 * scale, 0, 12 * scale, 4 * scale),
      child: Column(
        children: [
          Text(
            _status,
            style: TextStyle(
              fontSize: 26 * scale,
              fontWeight: FontWeight.w900,
              color: _phase == _Phase.turn ? AppColors.starGold : Colors.white70,
            ),
          ),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final gap = 12 * scale;
                final size = min(
                  (constraints.maxWidth - gap * (choices.length - 1)) / choices.length,
                  min(constraints.maxHeight - gap, 230 * scale),
                );
                return AnimatedBuilder(
                  animation: _shake,
                  builder: (context, child) => Transform.translate(
                    offset: Offset(sin(_shake.value * pi * 6) * 22 * (1 - _shake.value), 0),
                    child: child,
                  ),
                  child: Row(
                    key: _padsKey,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      for (var i = 0; i < choices.length; i++)
                        Padding(
                          padding: EdgeInsets.only(left: i == 0 ? 0 : gap),
                          child: _Pad(
                            size: size,
                            color: _color(choices[i]),
                            label: _name(choices[i]),
                            lit: showLit && _lit == choices[i],
                            onTap: () => _tapPad(choices[i]),
                          ),
                        ),
                    ],
                  ),
                );
              },
            ),
          ),
          _Dots(
            colors: [for (final answer in _state.pattern) _color(answer)],
            // While the pattern plays the dots stay empty: no peeking.
            filled: _phase == _Phase.watching ? 0 : _state.at,
            size: 16 * scale,
          ),
        ],
      ),
    );
  }

  Widget _buildEnd() {
    final key = _bestKey;
    final best = key == null ? 0 : _settings.best(key);
    final s = uiScale(context);
    final n = _state.best;
    return ScaledChrome(
      scale: s,
      child: SingleChildScrollView(
        padding: EdgeInsets.all(16 * s),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Out of hearts!',
                style: TextStyle(fontSize: 36, fontWeight: FontWeight.w900)),
            SizedBox(height: 8 * s),
            Text('$n in a row',
                style: const TextStyle(
                    fontSize: 52, fontWeight: FontWeight.w900, color: AppColors.starGold)),
            Text(
              n == 0
                  ? 'Watch the pads, then play them back'
                  : 'You copied a pattern of $n ${n == 1 ? 'note' : 'notes'}',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 18, color: Colors.white70),
            ),
            Text(_newBest ? 'New best!' : 'Best: $best',
                style: const TextStyle(fontSize: 20, color: Colors.white70)),
            SizedBox(height: 20 * s),
            Wrap(
              spacing: 16 * s,
              runSpacing: 12 * s,
              alignment: WrapAlignment.center,
              children: [
                FilledButton.icon(
                  onPressed: _restart,
                  style: keyButtonStyle(s),
                  icon: KeyBadge(pc: 0, size: 30 * s),
                  label: const Text('Play again'),
                ),
                OutlinedButton.icon(
                  onPressed: () => Navigator.maybePop(context),
                  style: keyButtonStyle(s),
                  icon: KeyBadge(pc: 4, size: 30 * s),
                  label: const Text('Menu'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// One pad: a big round button in its note's color, dim until it is lit.
class _Pad extends StatelessWidget {
  const _Pad({
    required this.size,
    required this.color,
    required this.label,
    required this.lit,
    required this.onTap,
  });

  final double size;
  final Color color;
  final String label;
  final bool lit;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final shown = lit ? color : Color.lerp(color, AppColors.background, 0.62)!;
    final dark = shown.computeLuminance() > 0.5;
    return GestureDetector(
      onTapDown: (_) => onTap(),
      child: AnimatedScale(
        scale: lit ? 1.0 : 0.88,
        duration: const Duration(milliseconds: 90),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 90),
          width: size,
          height: size,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: shown,
            shape: BoxShape.circle,
            border: Border.all(
              color: lit ? Colors.white : Colors.white24,
              width: size * 0.03,
            ),
            boxShadow: [
              if (lit) BoxShadow(color: color.withValues(alpha: 0.7), blurRadius: size * 0.35),
            ],
          ),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Padding(
              padding: EdgeInsets.all(size * 0.14),
              child: Text(
                label,
                textScaler: TextScaler.noScaling,
                style: TextStyle(
                  // A letter is big; a word (Low, Middle, High) fits the pad.
                  fontSize: size * (label.length == 1 ? 0.46 : 0.22),
                  fontWeight: FontWeight.w900,
                  color: dark ? AppColors.ink : Colors.white.withValues(alpha: lit ? 1 : 0.8),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// One dot per note of the pattern, in order: gray until the player has
// played it back, then its note's color.
class _Dots extends StatelessWidget {
  const _Dots({required this.colors, required this.filled, required this.size});

  final List<Color> colors;
  final int filled;
  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: size * 1.5,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < colors.length; i++)
              Container(
                width: size,
                height: size,
                margin: EdgeInsets.symmetric(horizontal: size * 0.25),
                decoration: BoxDecoration(
                  color: i < filled ? colors[i] : Colors.white24,
                  shape: BoxShape.circle,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
