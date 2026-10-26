"""Write the sample songs: public-domain tunes, each as a MIDI file with a
melody, chords and a bass line, and as the app's built-in songs.

Usage:
  python scripts/make-sample-songs.py          # write them
  python scripts/make-sample-songs.py --check  # exit 1 when the files differ

The tunes are written out by hand below. Each becomes samples/<name>.mid
(three tracks: "Melody", "Chords", "Bass"; the song editor lists them) and,
through extract-melodies.py like any other song, the app's built-in
apps/key_games/assets/builtin/<name>.json: the melody to play and the chords
and bass as its backing. Both are committed; CI runs --check so they never
drift from the tunes here.

A melody is notes like "C4 D#5:0.5 r:1": a note name with its octave (C4 is
middle C), then its length in beats (1 when left out); "r" is a rest. Chords
are "C:4 Am:2 G7:2" (major, m, 7 or m7; "r" for none), and together they last
as long as the melody. The style says how the band plays a chord:
  block   bass and chord held
  oompah  bass on beats 1 and 3 (root, then fifth), chord on 2 and 4
  waltz   bass on beat 1, chord on the others
  arp     root, fifth and octave one after another, half a beat each
"""

import filecmp
import importlib.util
import json
import os
import re
import struct
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
SAMPLE_DIR = os.path.join(ROOT, "samples")
BUILTIN_DIR = os.path.join(ROOT, "apps", "key_games", "assets", "builtin")
DIVISION = 480  # ticks per beat

spec = importlib.util.spec_from_file_location("extract_melodies", os.path.join(HERE, "extract-melodies.py"))
extractor = importlib.util.module_from_spec(spec)
spec.loader.exec_module(extractor)

TUNES = [
    {
        "name": "twinkle-twinkle", "title": "Twinkle Twinkle Little Star", "group": "Kids",
        "beat_ms": 500, "style": "oompah",
        "melody": "C4 C4 G4 G4 A4 A4 G4:2 F4 F4 E4 E4 D4 D4 C4:2 "
                  "G4 G4 F4 F4 E4 E4 D4:2 G4 G4 F4 F4 E4 E4 D4:2 "
                  "C4 C4 G4 G4 A4 A4 G4:2 F4 F4 E4 E4 D4 D4 C4:2",
        "chords": "C:4 F:2 C:2 F:2 C:2 G:2 C:2 C:2 F:2 C:2 G:2 C:2 F:2 C:2 G:2 "
                  "C:4 F:2 C:2 F:2 C:2 G:2 C:2",
    },
    {
        "name": "mary-had-a-little-lamb", "title": "Mary Had a Little Lamb", "group": "Kids",
        "beat_ms": 500, "style": "oompah",
        "melody": "E4 D4 C4 D4 E4 E4 E4:2 D4 D4 D4:2 E4 G4 G4:2 "
                  "E4 D4 C4 D4 E4 E4 E4 E4 D4 D4 E4 D4 C4:4",
        "chords": "C:4 C:4 G:4 C:4 C:4 C:4 G:4 C:4",
    },
    {
        "name": "hot-cross-buns", "title": "Hot Cross Buns", "group": "Kids",
        "beat_ms": 500, "style": "oompah",
        "melody": "E4 D4 C4:2 E4 D4 C4:2 C4:0.5 C4:0.5 C4:0.5 C4:0.5 "
                  "D4:0.5 D4:0.5 D4:0.5 D4:0.5 E4 D4 C4:2",
        "chords": "C:4 C:4 C:2 G:2 C:4",
    },
    {
        "name": "row-row-row-your-boat", "title": "Row, Row, Row Your Boat", "group": "Kids",
        "beat_ms": 250, "style": "block",
        "melody": "C4:3 C4:3 C4:2 D4 E4:3 E4:2 D4 E4:2 F4 G4:6 "
                  "C5 C5 C5 G4 G4 G4 E4 E4 E4 C4 C4 C4 G4:2 F4 E4:2 D4 C4:6",
        "chords": "C:6 C:6 C:6 C:6 C:6 C:6 G:6 C:6",
    },
    {
        "name": "london-bridge", "title": "London Bridge", "group": "Kids",
        "beat_ms": 500, "style": "oompah",
        "melody": "G4:1.5 A4:0.5 G4 F4 E4 F4 G4:2 D4 E4 F4:2 E4 F4 G4:2 "
                  "G4:1.5 A4:0.5 G4 F4 E4 F4 G4:2 D4:2 G4:2 E4 C4:3",
        "chords": "C:4 C:4 G:4 C:4 C:4 C:4 G:4 C:4",
    },
    {
        "name": "old-macdonald", "title": "Old MacDonald", "group": "Kids",
        "beat_ms": 450, "style": "oompah",
        "melody": "C4 C4 C4 G3 A3 A3 G3:2 E4 E4 D4 D4 C4:3 G3 "
                  "C4 C4 C4 G3 A3 A3 G3:2 E4 E4 D4 D4 C4:4",
        "chords": "C:4 F:2 C:2 C:2 G:2 C:4 C:4 F:2 C:2 C:2 G:2 C:4",
    },
    {
        "name": "frere-jacques", "title": "Frère Jacques", "group": "Kids",
        "beat_ms": 450, "style": "oompah",
        "melody": "C4 D4 E4 C4 C4 D4 E4 C4 E4 F4 G4:2 E4 F4 G4:2 "
                  "G4:0.5 A4:0.5 G4:0.5 F4:0.5 E4 C4 G4:0.5 A4:0.5 G4:0.5 F4:0.5 E4 C4 "
                  "C4 G3 C4:2 C4 G3 C4:2",
        "chords": "C:4 C:4 C:4 C:4 C:4 C:4 C:1 G:1 C:2 C:1 G:1 C:2",
    },
    {
        "name": "jingle-bells", "title": "Jingle Bells", "group": "Kids",
        "beat_ms": 450, "style": "oompah",
        "melody": "E4 E4 E4:2 E4 E4 E4:2 E4 G4 C4:1.5 D4:0.5 E4:4 "
                  "F4 F4 F4:1.5 F4:0.5 F4 E4 E4 E4:0.5 E4:0.5 E4 D4 D4 E4 D4:2 G4:2",
        "chords": "C:4 C:4 C:4 C:4 F:4 C:4 G:4 G:4",
    },
    {
        "name": "happy-birthday", "title": "Happy Birthday", "group": "Kids",
        "beat_ms": 500, "style": "waltz",
        "melody": "G3:0.75 G3:0.25 A3 G3 C4 B3:2 G3:0.75 G3:0.25 A3 G3 D4 C4:2 "
                  "G3:0.75 G3:0.25 G4 E4 C4 B3 A3:2 F4:0.75 F4:0.25 E4 C4 D4 C4:3",
        "chords": "r:1 C:3 G:3 G:3 C:3 C:3 F:3 C:2 G:2 C:3",
    },
    {
        "name": "ode-to-joy", "title": "Ode to Joy", "group": "Classical",
        "beat_ms": 450, "style": "oompah",
        "melody": "E4 E4 F4 G4 G4 F4 E4 D4 C4 C4 D4 E4 E4:1.5 D4:0.5 D4:2 "
                  "E4 E4 F4 G4 G4 F4 E4 D4 C4 C4 D4 E4 D4:1.5 C4:0.5 C4:2",
        "chords": "C:4 G:4 C:4 G:4 C:4 G:4 C:4 G:2 C:2",
    },
    {
        # The opening, in 3/8: a beat here is an eighth note.
        "name": "fur-elise", "title": "Für Elise", "group": "Classical",
        "beat_ms": 420, "style": "arp",
        "melody": "E5:0.5 D#5:0.5 E5:0.5 D#5:0.5 E5:0.5 B4:0.5 D5:0.5 C5:0.5 "
                  "A4 r:0.5 C4:0.5 E4:0.5 A4:0.5 B4 r:0.5 E4:0.5 G#4:0.5 B4:0.5 "
                  "C5 r:0.5 E4:0.5 E5:0.5 D#5:0.5 E5:0.5 D#5:0.5 E5:0.5 B4:0.5 D5:0.5 C5:0.5 "
                  "A4 r:0.5 C4:0.5 E4:0.5 A4:0.5 B4 r:0.5 E4:0.5 C5:0.5 B4:0.5 A4:3",
        "chords": "r:4 Am:3 E:3 Am:3 r:3 Am:3 E:3 Am:3",
    },
    {
        "name": "minuet-in-g", "title": "Minuet in G", "group": "Classical",
        "beat_ms": 480, "style": "waltz",
        "melody": "D5 G4:0.5 A4:0.5 B4:0.5 C5:0.5 D5 G4 G4 "
                  "E5 C5:0.5 D5:0.5 E5:0.5 F#5:0.5 G5 G4 G4 "
                  "C5 D5:0.5 C5:0.5 B4:0.5 A4:0.5 B4 C5:0.5 B4:0.5 A4:0.5 G4:0.5 "
                  "F#4 G4:0.5 A4:0.5 B4:0.5 G4:0.5 A4:3",
        "chords": "G:3 G:3 C:3 G:3 C:3 G:3 D:3 D:3",
    },
    {
        "name": "canon-in-d", "title": "Canon in D", "group": "Classical",
        "beat_ms": 500, "style": "block",
        "melody": "F#5:2 E5:2 D5:2 C#5:2 B4:2 A4:2 B4:2 C#5:2 "
                  "D5:2 C#5:2 B4:2 A4:2 G4:2 F#4:2 G4:2 E4:2 D4:4",
        "chords": "D:2 A:2 Bm:2 F#m:2 G:2 D:2 G:2 A:2 D:2 A:2 Bm:2 F#m:2 G:2 D:2 G:2 A:2 D:4",
    },
]

NOTE = re.compile(r"^([A-G])([#b]?)(-?\d)$")
CHORD = re.compile(r"^([A-G])([#b]?)(m7|m|7|)$")
LETTERS = {"C": 0, "D": 2, "E": 4, "F": 5, "G": 7, "A": 9, "B": 11}
ACCIDENTALS = {"": 0, "#": 1, "b": -1}
QUALITIES = {"": (0, 4, 7), "m": (0, 3, 7), "7": (0, 4, 7, 10), "m7": (0, 3, 7, 10)}
BASS_LOW = 40  # bass roots from E2 up
CHORD_LOW = 52  # chord notes from E3 up
MELODY, CHORDS, BASS = 0, 1, 2  # MIDI channels
PROGRAMS = {MELODY: 73, CHORDS: 0, BASS: 32}  # flute, piano, acoustic bass
VELOCITY = {MELODY: 100, CHORDS: 60, BASS: 75}


def steps(text):
    """[(token, beats)] from "C4 D4:2 r:0.5"."""
    out = []
    for word in text.split():
        token, _, beats = word.partition(":")
        out.append((token, float(beats) if beats else 1.0))
    return out


def note_number(name):
    match = NOTE.match(name)
    if not match:
        raise ValueError(f"not a note: {name}")
    letter, accidental, octave = match.groups()
    return 12 * (int(octave) + 1) + LETTERS[letter] + ACCIDENTALS[accidental]


def chord_notes(symbol):
    """(bass root, chord notes) for a chord symbol."""
    match = CHORD.match(symbol)
    if not match:
        raise ValueError(f"not a chord: {symbol}")
    letter, accidental, quality = match.groups()
    root = (LETTERS[letter] + ACCIDENTALS[accidental]) % 12
    bass = BASS_LOW + (root - BASS_LOW) % 12
    chord = sorted(CHORD_LOW + (root + step - CHORD_LOW) % 12 for step in QUALITIES[quality])
    return bass, chord


def tick(beats):
    return round(beats * DIVISION)


def melody_notes(tune):
    """([(channel, start_tick, end_tick, note)], beats) for the melody."""
    out, at = [], 0.0
    for token, beats in steps(tune["melody"]):
        if token != "r":
            out.append((MELODY, tick(at), tick(at + beats * 0.85), note_number(token)))
        at += beats
    return out, at


def band_notes(tune):
    """([(channel, start_tick, end_tick, note)], beats) for the chords and bass."""
    out, at = [], 0.0
    style = tune["style"]

    def play(channel, notes, start, length):
        for n in notes:
            out.append((channel, tick(at + start), tick(at + start + length), n))

    for symbol, beats in steps(tune["chords"]):
        if symbol != "r":
            bass, chord = chord_notes(symbol)
            if style == "block":
                play(BASS, [bass], 0, beats * 0.95)
                play(CHORDS, chord, 0, beats * 0.95)
            elif style == "arp":
                for i, n in enumerate([bass, bass + 7, bass + 12]):
                    if (i + 1) * 0.5 <= beats:
                        play(CHORDS, [n], i * 0.5, 0.45)
            else:
                for beat in range(int(beats)):
                    if beat == 0 or (style == "oompah" and beat % 2 == 0):
                        play(BASS, [bass if beat % 4 == 0 else bass + 7], beat, 0.9)
                    else:
                        play(CHORDS, chord, beat, 0.7)
        at += beats
    return out, at


def vlq(value):
    out = [value & 0x7F]
    value >>= 7
    while value:
        out.insert(0, (value & 0x7F) | 0x80)
        value >>= 7
    return bytes(out)


def chunk(events):
    """events: (tick, order, bytes) -> an MTrk chunk; at the same tick a lower
    order goes first (note-offs before note-ons)."""
    data, last = b"", 0
    for at, _, payload in sorted(events, key=lambda e: (e[0], e[1])):
        data += vlq(at - last) + payload
        last = at
    data += vlq(0) + b"\xff\x2f\x00"
    return b"MTrk" + struct.pack(">I", len(data)) + data


def meta(kind, payload):
    return bytes([0xFF, kind]) + vlq(len(payload)) + payload


def midi_file(tune):
    melody, melody_beats = melody_notes(tune)
    band, band_beats = band_notes(tune)
    if abs(melody_beats - band_beats) > 1e-9:
        raise ValueError(f"{tune['name']}: melody is {melody_beats} beats, chords {band_beats}")
    tempo = tune["beat_ms"] * 1000
    conductor = [
        (0, 0, meta(0x03, tune["title"].encode("utf-8"))),
        (0, 1, meta(0x51, tempo.to_bytes(3, "big"))),
    ]
    tracks = [chunk(conductor)]
    for channel, name in ((MELODY, "Melody"), (CHORDS, "Chords"), (BASS, "Bass")):
        events = [(0, 0, meta(0x03, name.encode("ascii"))),
                  (0, 1, bytes([0xC0 | channel, PROGRAMS[channel]]))]
        for ch, start, end, note in melody + band:
            if ch == channel:
                events.append((start, 3, bytes([0x90 | ch, note, VELOCITY[ch]])))
                events.append((end, 2, bytes([0x80 | ch, note, 0])))
        tracks.append(chunk(events))
    header = b"MThd" + struct.pack(">IHHH", 6, 1, len(tracks), DIVISION)
    return header + b"".join(tracks)


def write_all(sample_dir, builtin_dir):
    os.makedirs(sample_dir, exist_ok=True)
    os.makedirs(builtin_dir, exist_ok=True)
    picks = {}
    for tune in TUNES:
        name = tune["name"] + ".mid"
        with open(os.path.join(sample_dir, name), "wb") as handle:
            handle.write(midi_file(tune))
        picks[name] = {"title": tune["title"], "group": tune["group"]}
    with open(os.path.join(sample_dir, "song-picks.json"), "w", encoding="utf-8", newline="\n") as handle:
        json.dump(picks, handle, ensure_ascii=False, indent=2)
        handle.write("\n")
    for tune in TUNES:
        extractor.write_song(sample_dir, builtin_dir, tune["name"] + ".mid", picks)


def differences(made, kept):
    """File names that differ between two folders."""
    names = set(os.listdir(made)) | (set(os.listdir(kept)) if os.path.isdir(kept) else set())
    return sorted(n for n in names
                  if not (os.path.isfile(os.path.join(made, n)) and os.path.isfile(os.path.join(kept, n))
                          and filecmp.cmp(os.path.join(made, n), os.path.join(kept, n), shallow=False)))


def main():
    if "--check" not in sys.argv[1:]:
        write_all(SAMPLE_DIR, BUILTIN_DIR)
        print(f"[OK] {len(TUNES)} sample songs in samples/ and assets/builtin/")
        return
    with tempfile.TemporaryDirectory() as temp:
        samples, builtin = os.path.join(temp, "samples"), os.path.join(temp, "builtin")
        write_all(samples, builtin)
        stale = ([f"samples/{n}" for n in differences(samples, SAMPLE_DIR)]
                 + [f"assets/builtin/{n}" for n in differences(builtin, BUILTIN_DIR)])
    if stale:
        print("[X] out of date (run python scripts/make-sample-songs.py): " + ", ".join(stale))
        sys.exit(1)
    print(f"[OK] {len(TUNES)} sample songs are up to date")


if __name__ == "__main__":
    main()
