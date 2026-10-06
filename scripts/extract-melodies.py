"""Turn MIDI files into melody note lists for the Key Games song mode.

Usage:
  python scripts/extract-melodies.py [SONG_FOLDER] [OUT_FOLDER]

Defaults: SONG_FOLDER = private/songs, OUT_FOLDER = apps/key_games/assets/songs.
The output folder is ignored by Git: the songs are bundled into local app
builds only, never committed.

For each .mid file:
  1. Pick the melody part: the (track, channel) with the best melody score
     from inspect-midi.py, unless an override says otherwise.
  2. Keep one note per moment (the highest, "skyline"), so chords become a
     single line a child can play.
  3. Transpose to the key with the fewest black keys (easier for small
     hands), then move by octaves to fit the 37-key range C3..C6.
  4. Write JSON: {"title", "source", "notes": [[note, start_ms, length_ms], ...]}

Optional overrides live in SONG_FOLDER/song-picks.json, keyed by file name:
  {"tune.mid": {"title": "My Tune", "track": 1, "channel": 2,
                "skip": 0, "max_notes": 60, "transpose": false}}
"track"/"channel" choose the part (1-based channel, as inspect-midi.py
prints), "skip" drops leading notes (pickups, intros), "max_notes" caps the
length (default 80), "transpose": false keeps the original key.
"""

import importlib.util
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
LOW, HIGH = 48, 84  # C3..C6, the 37 keys the app pictures
WHITE = {0, 2, 4, 5, 7, 9, 11}
DEFAULT_MAX_NOTES = 80

spec = importlib.util.spec_from_file_location("inspect_midi", os.path.join(HERE, "inspect-midi.py"))
inspect_midi = importlib.util.module_from_spec(spec)
spec.loader.exec_module(inspect_midi)


def collect_parts(tracks):
    """Return {(track, channel): [(start_tick, end_tick, note)]} and tempo changes."""
    parts = {}
    tempos = []
    for index, events in enumerate(tracks):
        held = {}
        for tick, kind, fields in events:
            if kind == "meta":
                meta_type, payload = fields
                if meta_type == 0x51:
                    tempos.append((tick, int.from_bytes(payload, "big")))
                continue
            status, channel, *args = fields
            if status not in (0x80, 0x90):
                continue
            key = (index, channel)
            note = args[0]
            if status == 0x90 and args[1] > 0:
                if (key, note) in held:  # retrigger without note-off
                    start = held.pop((key, note))
                    parts.setdefault(key, []).append((start, tick, note))
                held[(key, note)] = tick
            elif (key, note) in held:
                start = held.pop((key, note))
                parts.setdefault(key, []).append((start, tick, note))
    tempos.sort()
    return parts, tempos


def melody_score(notes, channel):
    """Same idea as inspect-midi.py: monophonic, mid register, not drums."""
    if channel == 9 or not notes:
        return 0
    ordered = sorted(notes)
    overlaps = sum(1 for a, b in zip(ordered, ordered[1:]) if b[0] < a[1])
    mono = 1 - overlaps / len(ordered)
    mean = sum(n[2] for n in ordered) / len(ordered)
    register = max(0.0, 1 - abs(mean - 67) / 24)
    return 100 * (0.6 * mono + 0.4 * register) * min(1, len(ordered) / 40)


def ticks_to_ms(tick, tempos, division):
    ms = 0.0
    last_tick, tempo = 0, 500000
    for change_tick, change_tempo in tempos:
        if change_tick >= tick:
            break
        ms += (change_tick - last_tick) * tempo / division / 1000
        last_tick, tempo = change_tick, change_tempo
    return ms + (tick - last_tick) * tempo / division / 1000


def skyline(notes, division):
    """One line from a part that may hold chords or a bass line.

    Keeps the highest note of notes starting together (within 1/8 beat), and
    drops a lower note that starts while the kept melody note is still held
    (accompaniment under a long melody note, common in one-track piano files).
    """
    tolerance = max(1, division // 8)
    result = []
    for start, end, note in sorted(notes, key=lambda n: (n[0], -n[2])):
        if result:
            last_start, last_end, last_note = result[-1]
            if start - last_start <= tolerance:
                continue
            if note < last_note and last_end - start > tolerance:
                continue
        result.append((start, end, note))
    return result


def best_transpose(pitches):
    """Shift (-5..+6) that puts the most notes on white keys; smallest wins ties."""
    shifts = sorted(range(-5, 7), key=abs)
    return max(shifts, key=lambda s: sum((p + s) % 12 in WHITE for p in pitches))


def octave_shift(pitches):
    """Whole-octave shift that puts the tune's median near the middle (F#4)."""
    middle = sorted(pitches)[len(pitches) // 2]
    return 12 * round((66 - middle) / 12)


def fold(note):
    """Bring a straggler into the 37-key range by octaves."""
    while note < LOW:
        note += 12
    while note > HIGH:
        note -= 12
    return note


def title_from_file(name):
    return " ".join(word.capitalize() for word in os.path.splitext(name)[0].replace("_", "-").split("-"))


def extract(path, options):
    fmt, division, tracks = inspect_midi.read_file(path)
    if division >= 0x8000:
        raise ValueError("SMPTE time division is not supported")
    parts, tempos = collect_parts(tracks)
    if "track" in options or "channel" in options:
        candidates = [k for k in parts
                      if options.get("track", k[0]) == k[0]
                      and options.get("channel", k[1] + 1) == k[1] + 1]
        if not candidates:
            raise ValueError(f"no part matches override {options}")
        key = max(candidates, key=lambda k: len(parts[k]))
    else:
        key = max(parts, key=lambda k: melody_score(parts[k], k[1]))
    line = skyline(parts[key], division)
    line = line[options.get("skip", 0):][:options.get("max_notes", DEFAULT_MAX_NOTES)]
    if not line:
        raise ValueError("melody part is empty")
    pitches = [n[2] for n in line]
    shift = best_transpose(pitches) if options.get("transpose", True) else 0
    shift += octave_shift([p + shift for p in pitches])
    origin = ticks_to_ms(line[0][0], tempos, division)
    notes = []
    for start, end, note in line:
        start_ms = ticks_to_ms(start, tempos, division) - origin
        length_ms = max(60, ticks_to_ms(end, tempos, division) - origin - start_ms)
        notes.append([fold(note + shift), round(start_ms), round(length_ms)])
    return {
        "title": options.get("title") or title_from_file(os.path.basename(path)),
        "source": os.path.basename(path),
        "part": {"track": key[0], "channel": key[1] + 1},
        "notes": notes,
    }


def main():
    song_dir = sys.argv[1] if len(sys.argv) > 1 else os.path.join(ROOT, "private", "songs")
    out_dir = sys.argv[2] if len(sys.argv) > 2 else os.path.join(ROOT, "apps", "key_games", "assets", "songs")
    picks_path = os.path.join(song_dir, "song-picks.json")
    picks = {}
    if os.path.exists(picks_path):
        with open(picks_path, encoding="utf-8") as handle:
            picks = json.load(handle)
    os.makedirs(out_dir, exist_ok=True)
    for name in sorted(os.listdir(song_dir)):
        if not name.lower().endswith((".mid", ".midi")):
            continue
        try:
            song = extract(os.path.join(song_dir, name), picks.get(name, {}))
        except Exception as error:
            print(f"[X] {name}: {error}")
            continue
        out_name = os.path.splitext(name)[0] + ".json"
        with open(os.path.join(out_dir, out_name), "w", encoding="ascii", newline="\n") as handle:
            json.dump(song, handle, separators=(",", ":"))
        names = [inspect_midi.note_name(n[0]) for n in song["notes"][:8]]
        part = song["part"]
        print(f"[OK] {name}: {len(song['notes'])} notes from trk {part['track']} ch {part['channel']}"
              f", starts {' '.join(names)}")


if __name__ == "__main__":
    main()
