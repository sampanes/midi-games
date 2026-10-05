"""Summarize Standard MIDI Files: tracks, instruments, note counts and ranges.

Usage:
  python inspect-midi.py FILE_OR_FOLDER [...]

No dependencies. For each track it prints the track name, channels, General
MIDI instrument, note count, pitch range, and a melody score (higher = more
likely the tune: one note at a time, mid register, not drums).
"""

import os
import struct
import sys

GM_FAMILIES = [
    "piano", "chromatic perc", "organ", "guitar", "bass", "strings", "ensemble",
    "brass", "reed", "pipe", "synth lead", "synth pad", "synth fx", "ethnic",
    "percussive", "sound fx",
]
NOTE_NAMES = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]


def note_name(note):
    return f"{NOTE_NAMES[note % 12]}{note // 12 - 1}"


def read_vlq(data, pos):
    value = 0
    while True:
        byte = data[pos]
        pos += 1
        value = (value << 7) | (byte & 0x7F)
        if byte < 0x80:
            return value, pos


def parse_track(data):
    """Yield (abs_tick, kind, fields) for the events of one MTrk chunk."""
    pos = 0
    tick = 0
    running = None
    while pos < len(data):
        delta, pos = read_vlq(data, pos)
        tick += delta
        status = data[pos]
        if status == 0xFF:
            meta_type = data[pos + 1]
            length, pos = read_vlq(data, pos + 2)
            yield tick, "meta", (meta_type, data[pos:pos + length])
            pos += length
            if meta_type == 0x2F:
                return
            continue
        if status in (0xF0, 0xF7):
            length, pos = read_vlq(data, pos + 1)
            pos += length
            continue
        if status & 0x80:
            running = status
            pos += 1
        elif running is None:
            raise ValueError("data byte without running status")
        kind = running & 0xF0
        channel = running & 0x0F
        size = 1 if kind in (0xC0, 0xD0) else 2
        args = data[pos:pos + size]
        pos += size
        yield tick, "channel", (kind, channel, *args)


def read_file(path):
    with open(path, "rb") as handle:
        blob = handle.read()
    if blob[:4] != b"MThd":
        raise ValueError("not a Standard MIDI File")
    header_len = struct.unpack(">I", blob[4:8])[0]
    fmt, ntracks, division = struct.unpack(">HHH", blob[8:14])
    pos = 8 + header_len
    tracks = []
    while pos + 8 <= len(blob):
        chunk_id = blob[pos:pos + 4]
        length = struct.unpack(">I", blob[pos + 4:pos + 8])[0]
        if chunk_id == b"MTrk":
            tracks.append(list(parse_track(blob[pos + 8:pos + 8 + length])))
        pos += 8 + length
    return fmt, division, tracks


def summarize(path):
    fmt, division, tracks = read_file(path)
    tempo = None
    end_tick = 0
    rows = []
    for index, events in enumerate(tracks):
        name = ""
        programs = {}
        parts = {}  # channel -> {"notes": [...], "held": set(), "overlap": int}
        for tick, kind, fields in events:
            end_tick = max(end_tick, tick)
            if kind == "meta":
                meta_type, payload = fields
                if meta_type == 0x03 and not name:
                    name = payload.decode("latin-1", "replace").strip()
                elif meta_type == 0x51 and tempo is None:
                    tempo = int.from_bytes(payload, "big")
                continue
            status, channel, *args = fields
            if status == 0xC0:
                programs.setdefault(channel, args[0])
                continue
            part = parts.setdefault(channel, {"notes": [], "held": set(), "overlap": 0})
            if status == 0x90 and args[1] > 0:
                if part["held"]:
                    part["overlap"] += 1
                part["held"].add(args[0])
                part["notes"].append(args[0])
            elif status == 0x80 or (status == 0x90 and args[1] == 0):
                part["held"].discard(args[0])
        # One row per (track, channel): format-0 files keep every instrument
        # in a single track, separated only by channel.
        for channel, part in sorted(parts.items()):
            pitches = part["notes"]
            if not pitches:
                continue
            drums = channel == 9
            mono = 1 - part["overlap"] / len(pitches)
            mean = sum(pitches) / len(pitches)
            register = max(0.0, 1 - abs(mean - 67) / 24)
            score = 0 if drums else round(100 * (0.6 * mono + 0.4 * register) * min(1, len(pitches) / 40))
            if drums:
                instrument = "drums"
            else:
                program = programs.get(channel, 0)
                instrument = f"{GM_FAMILIES[program // 8]} (#{program})"
            rows.append((index, name[:24], str(channel + 1), instrument, len(pitches),
                         f"{note_name(min(pitches))}-{note_name(max(pitches))}", score))
    seconds = end_tick / division * (tempo or 500000) / 1e6 if division < 0x8000 else 0
    print(f"\n{os.path.basename(path)}  format {fmt}, {len(tracks)} tracks, ~{seconds:.0f}s"
          f", tempo {60e6 / tempo:.0f} bpm" if tempo else
          f"\n{os.path.basename(path)}  format {fmt}, {len(tracks)} tracks, ~{seconds:.0f}s")
    best = max(rows, key=lambda r: r[-1], default=None)
    for row in rows:
        mark = "*" if row is best else " "
        print(f" {mark} trk {row[0]:>2} {row[1]:24} ch {row[2]:3} {row[3]:22} {row[4]:>5} notes  {row[5]:9} melody {row[6]}")


def main():
    paths = []
    for arg in sys.argv[1:] or ["."]:
        if os.path.isdir(arg):
            paths += sorted(os.path.join(arg, f) for f in os.listdir(arg) if f.lower().endswith((".mid", ".midi")))
        else:
            paths.append(arg)
    for path in paths:
        try:
            summarize(path)
        except Exception as error:
            print(f"\n{os.path.basename(path)}  [X] {error}")


if __name__ == "__main__":
    main()
