"""Turn MIDI files into melody note lists for the Key Games song mode.

Usage:
  python scripts/extract-melodies.py [SONG_FOLDER] [OUT_FOLDER]

Defaults: SONG_FOLDER = private/songs, OUT_FOLDER = apps/key_games/assets/songs.
The output folder is ignored by Git: the songs are bundled into local app
builds only, never committed.

For each .mid file:
  1. Pick the melody part, unless an override says otherwise. Karaoke files
     carry lyrics: the part whose notes start with the syllables is the sung
     line. Otherwise the (track, channel) with the best melody score: one
     note at a time, not low (bass), named like a melody ("Melody", "Vocal",
     "Lead", "Right Hand") rather than an accompaniment.
  2. Keep one note per moment (the highest, "skyline"), so chords become a
     single line a child can play.
  3. Shorten rests longer than 2.5 s (the melody part sitting out while the
     band plays) to 2.5 s, so the tune never stops for long.
  4. Transpose to the key with the fewest black keys (easier for small
     hands), then move by octaves to fit the 37-key range C3..C6.
  5. Write JSON: {"title", "source", "notes": [[note, start_ms, length_ms], ...]}

Optional overrides live in SONG_FOLDER/song-picks.json, keyed by file name:
  {"tune.mid": {"title": "My Tune", "group": "Kids", "track": 1, "channel": 2,
                "skip": 0, "max_notes": 60, "min_note": 60, "lowest": true,
                "transpose": false}}
"track"/"channel" choose the part (1-based channel, as inspect-midi.py
prints), "skip" drops leading notes (pickups, intros), "max_notes" caps the
length (default 200), "min_note" drops lower notes before the melody is taken
(a left hand mixed into the part), "lowest": true keeps the lowest note of each
chord instead of the highest (piano covers that put harmony above the tune),
"transpose": false keeps the original key.
"group" files the song under a heading in the song list (default "Songs").
"""

import bisect
import importlib.util
import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
LOW, HIGH = 48, 84  # C3..C6, the 37 keys the app pictures
WHITE = {0, 2, 4, 5, 7, 9, 11}
DEFAULT_MAX_NOTES = 200
MAX_REST_MS = 2500
MELODY_NAME = re.compile(r"melody|vocal|vox|voice|lead|solo|right hand|rh", re.I)
BACKING_NAME = re.compile(r"bass|drum|left hand|lh|pad|chord|accomp|rhythm", re.I)

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


def melody_score(notes, channel, name=""):
    """Like inspect-midi.py: one note at a time, mid register, not drums.

    Low parts lose fast (a bass line is never the tune), and the track name
    counts: "Melody" or "Vocal" up, "Bass" or "Left Hand" down.
    """
    if channel == 9 or not notes:
        return 0
    ordered = sorted(notes)
    overlaps = sum(1 for a, b in zip(ordered, ordered[1:]) if b[0] < a[1])
    mono = 1 - overlaps / len(ordered)
    mean = sum(n[2] for n in ordered) / len(ordered)
    register = max(0.0, 1 - (67 - mean) / 12 if mean < 67 else 1 - (mean - 67) / 24)
    score = 100 * (0.6 * mono + 0.4 * register) * min(1, len(ordered) / 40)
    if MELODY_NAME.search(name):
        score *= 1.5
    elif BACKING_NAME.search(name):
        score *= 0.5
    return score


def track_names(tracks):
    names = []
    for events in tracks:
        name = ""
        for tick, kind, fields in events:
            if kind == "meta" and fields[0] == 0x03:
                name = fields[1].decode("latin-1", "replace").strip()
                break
        names.append(name)
    return names


def lyric_ticks(tracks):
    """Start ticks of the lyric syllables (lyric events, or the text events
    karaoke .kar files use)."""
    ticks = []
    for events in tracks:
        texts = [(tick, fields[0]) for tick, kind, fields in events
                 if kind == "meta" and fields[0] in (0x01, 0x05) and tick > 0]
        if any(meta == 0x05 for _, meta in texts):
            texts = [t for t in texts if t[1] == 0x05]
        ticks += [tick for tick, _ in texts]
    return sorted(ticks)


def sung_part(parts, lyrics, division):
    """The part whose notes start with the most syllables, or None when the
    file has no lyrics or no part follows them."""
    if len(lyrics) < 20:
        return None
    tolerance = max(1, division // 16)
    best, best_share = None, 0.0
    for key, notes in parts.items():
        if key[1] == 9:
            continue
        starts = sorted(n[0] for n in notes)
        hits = 0
        for tick in lyrics:
            i = bisect.bisect_left(starts, tick - tolerance)
            hits += i < len(starts) and starts[i] <= tick + tolerance
        share = hits / len(lyrics)
        if share > best_share:
            best, best_share = key, share
    return best if best_share >= 0.6 else None


def ticks_to_ms(tick, tempos, division):
    ms = 0.0
    last_tick, tempo = 0, 500000
    for change_tick, change_tempo in tempos:
        if change_tick >= tick:
            break
        ms += (change_tick - last_tick) * tempo / division / 1000
        last_tick, tempo = change_tick, change_tempo
    return ms + (tick - last_tick) * tempo / division / 1000


def skyline(notes, division, lowest=False):
    """One line from a part that may hold chords or a bass line.

    Keeps the highest note of notes starting together (within 1/8 beat), and
    drops a lower note that starts while the kept melody note is still held
    (accompaniment under a long melody note, common in one-track piano files).
    With lowest, the same from below: the lowest note, dropping higher ones.
    """
    tolerance = max(1, division // 8)
    side = 1 if lowest else -1
    result = []
    for start, end, note in sorted(notes, key=lambda n: (n[0], side * n[2])):
        if result:
            last_start, last_end, last_note = result[-1]
            if start - last_start <= tolerance:
                continue
            if side * (note - last_note) > 0 and last_end - start > tolerance:
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
        names = track_names(tracks)
        key = sung_part(parts, lyric_ticks(tracks), division) or max(
            parts, key=lambda k: melody_score(parts[k], k[1], names[k[0]]))
    low = options.get("min_note", 0)
    line = skyline([n for n in parts[key] if n[2] >= low], division,
                   options.get("lowest", False))
    line = line[options.get("skip", 0):][:options.get("max_notes", DEFAULT_MAX_NOTES)]
    if not line:
        raise ValueError("melody part is empty")
    pitches = [n[2] for n in line]
    shift = best_transpose(pitches) if options.get("transpose", True) else 0
    shift += octave_shift([p + shift for p in pitches])
    origin = ticks_to_ms(line[0][0], tempos, division)
    notes = []
    cut = 0.0  # rest time taken out so far
    last_end = 0.0
    for start, end, note in line:
        start_ms = ticks_to_ms(start, tempos, division) - origin
        end_ms = ticks_to_ms(end, tempos, division) - origin
        cut += max(0.0, start_ms - cut - last_end - MAX_REST_MS)
        start_ms -= cut
        length_ms = max(60, end_ms - cut - start_ms)
        last_end = max(last_end, start_ms + length_ms)
        notes.append([fold(note + shift), round(start_ms), round(length_ms)])
    return {
        "title": options.get("title") or title_from_file(os.path.basename(path)),
        "group": options.get("group", "Songs"),
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
