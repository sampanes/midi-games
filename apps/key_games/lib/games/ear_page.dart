// Ear Notes screen: a mystery note plays and the child finds it on the
// keyboard by sound alone. After a wrong key, that note and then the mystery
// note (the nearest one) play, to compare by ear; after two wrong tries the
// answer lights up. Tap the big circle to hear the note again.
//
// Easy starts with "high or low?": any key in the low or high half of the
// keyboard answers, and the halves are colored. Easy and Medium color the
// level's notes on the keyboard picture, and other keys only sound, so the
// one question is which of the few notes it was. Hard and Expert draw the
// picture plain, and every key is an answer.
//
// Input: the keyboard and the computer keys, through the key router, plus
// touching the keyboard picture.

import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import '../app/services.dart';
import '../app/theme.dart';
import '../audio/miss_echo.dart';
import '../audio/synth.dart';
import '../midi/midi_input.dart';
import '../widgets/game_page.dart';
import '../widgets/piano_strip.dart';
import '../widgets/sparks.dart';
import '../widgets/win_banner.dart';
import '../widgets/zones.dart';
import 'color_keys_rules.dart';
import 'difficulty.dart';
import 'ear_rules.dart';

const _hitDelay = Duration(milliseconds: 1300);
const _levelUpDelay = Duration(milliseconds: 3000);
const _idleReplay = Duration(seconds: 7);

// The mystery note is played around middle C.
const _mysteryOctave = 60;

// Difficulty picks the starting level; stars still move up from there.
const earStartLevel = {
  Difficulty.easy: 0,
  Difficulty.medium: 1,
  Difficulty.hard: 3,
  Difficulty.expert: 5,
};

const earLevelsText = {
  Difficulty.easy: 'High or low? Any key in that half',
  Difficulty.medium: 'C or G, lit on the keyboard',
  Difficulty.hard: 'C D E F G, then all the white keys',
  Difficulty.expert: 'All twelve notes',
};

class EarPage extends StatefulWidget {
  const EarPage({
    super.key,
    this.difficulty = Difficulty.easy,
    this.random,
  });

  final Difficulty difficulty;

  // Fixed in tests.
  final Random? random;

  @override
  State<EarPage> createState() => _EarPageState();
}

class _EarPageState extends State<EarPage> with TickerProviderStateMixin {
  late final Synth _synth = AppServices.of(context).synth;
  late final Random _random = widget.random ?? Random();
  final GlobalKey<SparksState> _sparksKey = GlobalKey();
  final GlobalKey _circleKey = GlobalKey();
  late final AnimationController _pulse =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 380));
  late final AnimationController _shake =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 420));
  late EarState _state = EarState.start(earStartLevel[widget.difficulty]!, _random);
  late final MissEcho _echo = MissEcho(_synth);
  Timer? _advanceTimer;
  Timer? _replayTimer;
  bool _celebrating = false;
  int _base = 48;
  final Set<int> _held = {};

  @override
  void initState() {
    super.initState();
    // First note once the synth has had time to load.
    _scheduleReplay(const Duration(milliseconds: 1200));
  }

  @override
  void dispose() {
    _advanceTimer?.cancel();
    _replayTimer?.cancel();
    _echo.cancel();
    for (final note in _held) {
      _synth.noteOff(note);
    }
    _pulse.dispose();
    _shake.dispose();
    super.dispose();
  }

  // Easy and Medium: the level's notes are colored, and other keys only sound.
  bool get _helped => widget.difficulty.index <= Difficulty.medium.index;

  int get _mysteryNote =>
      _state.zoned ? earZoneNotes[_state.target] : _mysteryOctave + _state.target;

  Color get _targetColor =>
      _state.zoned ? zoneColors(earZoneCount)[_state.target] : pitchColor(_state.target);

  String get _targetName =>
      _state.zoned ? zoneNames(earZoneCount)[_state.target] : pitchClasses[_state.target].name;

  void _playMystery() {
    if (!mounted) return;
    _synth.blip(_mysteryNote, velocity: 85, lengthMs: 600);
    _scheduleReplay(_idleReplay);
  }

  // Plays the mystery note after [delay], replacing any earlier plan. While a
  // found note is showing, nothing replays.
  void _scheduleReplay(Duration delay) {
    _replayTimer?.cancel();
    _replayTimer = Timer(delay, () {
      if (mounted && !_state.locked) _playMystery();
    });
  }

  void _onNote(NoteEvent event) {
    if (!isGameNote(event.note)) return;
    if (!event.on) {
      _synth.noteOff(event.note);
      setState(() => _held.remove(event.note));
      return;
    }
    _synth.noteOn(event.note, event.velocity);
    final base = fitBase(_base, event.note);
    final answer = _state.zoned
        ? zoneOf(event.note, pictureKeys(context, base), earZoneCount)
        : event.note;
    final result = pressEarNote(_state, answer, onlyChoices: _helped);
    setState(() {
      _state = result.state;
      _base = base;
      _held.add(event.note);
    });
    for (final effect in result.effects) {
      switch (effect) {
        case EarEffect.miss:
          _shake.forward(from: 0);
          _echo.play(event.note,
              _state.zoned ? _mysteryNote : nearestOfClass(event.note, _state.target));
          _scheduleReplay(MissEcho.length + _idleReplay);
        case EarEffect.reveal:
          break;
        case EarEffect.hit:
          _celebrateHit(big: true);
        case EarEffect.found:
          _celebrateHit(big: false);
        case EarEffect.nextSoon:
          _scheduleAdvance(_hitDelay);
        case EarEffect.levelUp:
          _celebrateLevelUp();
          _scheduleAdvance(_levelUpDelay);
      }
    }
  }

  void _celebrateHit({required bool big}) {
    _replayTimer?.cancel();
    _echo.cancel();
    _pulse.forward(from: 0);
    final color = _targetColor;
    _sparksKey.currentState?.burst(
      _circleCenter(),
      big ? [color, Colors.white, AppColors.starGold] : [color, Colors.white],
      count: big ? 40 : 18,
      speed: big ? 520 : 320,
    );
    final top = _state.zoned ? (_state.target == 0 ? 0 : 7) : _state.target;
    if (big) _synth.tune([84 + top, 91 + top], stepMs: 70, lengthMs: 150);
  }

  void _celebrateLevelUp() {
    setState(() => _celebrating = true);
    final rainbow = [for (final pc in whitePitchClasses) pitchColor(pc)];
    final size = MediaQuery.sizeOf(context);
    final sparks = _sparksKey.currentState;
    for (var i = 0; i < 5; i++) {
      Timer(Duration(milliseconds: 250 * i), () {
        if (!mounted) return;
        final at = Offset(
          size.width * (0.15 + 0.7 * _random.nextDouble()),
          size.height * (0.2 + 0.5 * _random.nextDouble()),
        );
        sparks?.burst(at, rainbow, count: 50, speed: 650);
      });
    }
    _synth.tune([84, 88, 91, 96, 91, 96], stepMs: 130, lengthMs: 200);
  }

  void _scheduleAdvance(Duration delay) {
    _advanceTimer?.cancel();
    _advanceTimer = Timer(delay, () {
      if (!mounted) return;
      setState(() {
        _state = advanceEar(_state, _random);
        _celebrating = false;
      });
      _scheduleReplay(const Duration(milliseconds: 400));
    });
  }

  // Tapping the level chip moves to the next level (and wraps around).
  void _nextLevel() {
    _advanceTimer?.cancel();
    setState(() {
      _state = EarState.start((_state.level + 1) % earLevels.length, _random);
      _celebrating = false;
    });
    _scheduleReplay(const Duration(milliseconds: 400));
  }

  Offset _circleCenter() {
    final circle = _circleKey.currentContext?.findRenderObject() as RenderBox?;
    final sparks = _sparksKey.currentContext?.findRenderObject() as RenderBox?;
    if (circle == null || sparks == null) return Offset.zero;
    final global = circle.localToGlobal(circle.size.center(Offset.zero));
    return sparks.globalToLocal(global);
  }

  @override
  Widget build(BuildContext context) {
    final show = _state.locked || _state.revealed;
    final color = show ? _targetColor : AppColors.mystery;
    return GamePage(
      onNote: _onNote,
      backdrop: AnimatedContainer(
        duration: const Duration(milliseconds: 400),
        decoration: BoxDecoration(
          gradient: RadialGradient(
            colors: [color.withValues(alpha: show ? 0.28 : 0.4), AppColors.background],
            radius: 0.9,
          ),
        ),
      ),
      header: [
        Expanded(child: _StarRow(stars: _state.stars)),
        const SizedBox(width: 8),
        ActionChip(
          avatar: Icon(Icons.trending_up, size: 18 * uiScale(context)),
          label: Text('Level ${_state.level + 1}'),
          onPressed: _nextLevel,
        ),
        const SizedBox(width: 8),
      ],
      body: Center(child: _buildCircle(show, color)),
      footer: [
        if (_state.zoned)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: ZoneBar(
              count: earZoneCount,
              picture: pictureKeys(context, _base),
              lit: show ? _state.target : null,
            ),
          )
        else
          _ChoiceRow(choices: _state.choices, colored: _helped),
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
          child: SizedBox(
            height: pianoStripHeight(context),
            child: PianoStrip(
              base: _base,
              target: show && !_state.zoned ? _state.target : null,
              plain: true,
              choices: _state.zoned ? null : _state.choices,
              colorChoices: _helped,
              zones: _state.zoned ? earZoneCount : null,
              litZone: show && _state.zoned ? _state.target : null,
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

  Widget _buildCircle(bool show, Color color) {
    final darkText = show && color.computeLuminance() > 0.5;
    final ink = darkText ? AppColors.ink : Colors.white;
    return LayoutBuilder(
      builder: (context, constraints) {
        final diameter = min(constraints.maxWidth, constraints.maxHeight) * 0.72;
        return GestureDetector(
          onTap: _state.locked ? null : _playMystery,
          child: AnimatedBuilder(
            animation: Listenable.merge([_pulse, _shake]),
            builder: (context, child) {
              final p = _pulse.value;
              final s = _shake.value;
              return Transform.translate(
                offset: Offset(sin(s * pi * 6) * 22 * (1 - s), 0),
                child: Transform.scale(scale: 1 + 0.16 * sin(p * pi), child: child),
              );
            },
            child: AnimatedContainer(
              key: _circleKey,
              duration: const Duration(milliseconds: 250),
              width: diameter,
              height: diameter,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                boxShadow: [BoxShadow(color: color.withValues(alpha: 0.6), blurRadius: 60)],
              ),
              alignment: Alignment.center,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Padding(
                  padding: EdgeInsets.all(diameter * 0.12),
                  child: show
                      ? Text(
                          _targetName,
                          style: TextStyle(
                            fontSize: diameter * 0.42,
                            fontWeight: FontWeight.w900,
                            color: ink,
                          ),
                        )
                      : Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.hearing, size: diameter * 0.32, color: ink),
                            Text(
                              '?',
                              style: TextStyle(
                                fontSize: diameter * 0.2,
                                fontWeight: FontWeight.w900,
                                color: ink,
                              ),
                            ),
                          ],
                        ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

// The letters this level uses, so a child knows what the choices are; in
// their key colors when [colored].
class _ChoiceRow extends StatelessWidget {
  const _ChoiceRow({required this.choices, this.colored = false});

  final List<int> choices;
  final bool colored;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Text.rich(
          TextSpan(children: [
            for (var i = 0; i < choices.length; i++)
              TextSpan(
                text: '${i == 0 ? '' : '   '}${pitchClasses[choices[i]].name}',
                style: TextStyle(color: colored ? pitchColor(choices[i]) : Colors.white54),
              ),
          ]),
          style: TextStyle(
            fontSize: 26 * uiScale(context),
            fontWeight: FontWeight.w800,
            letterSpacing: 1,
          ),
        ),
      ),
    );
  }
}

class _StarRow extends StatelessWidget {
  const _StarRow({required this.stars});

  final int stars;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = min(48.0 * uiScale(context), constraints.maxWidth / earStarsPerLevel);
        return Row(
          children: [
            for (var i = 0; i < earStarsPerLevel; i++)
              AnimatedScale(
                scale: i < stars ? 1.0 : 0.8,
                duration: const Duration(milliseconds: 300),
                curve: Curves.elasticOut,
                child: Icon(
                  Icons.star_rounded,
                  size: size,
                  color: i < stars ? AppColors.starGold : Colors.white24,
                ),
              ),
          ],
        );
      },
    );
  }
}
