"""Song editor server: load, save a canon tune, and load it back.

Run: python -m unittest discover -s tests -p "test_*.py"
Uses a made-up MIDI file in a temporary folder; no real songs are touched.
"""

import importlib.util
import json
import os
import struct
import tempfile
import unittest

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
spec = importlib.util.spec_from_file_location("song_editor", os.path.join(ROOT, "scripts", "song-editor.py"))
editor = importlib.util.module_from_spec(spec)
spec.loader.exec_module(editor)

DIVISION = 480  # ticks per beat; 120 bpm, so one beat is 500 ms


def vlq(value):
    out = [value & 0x7F]
    value >>= 7
    while value:
        out.insert(0, (value & 0x7F) | 0x80)
        value >>= 7
    return bytes(out)


def track(events):
    """events: (tick, bytes) in any order -> an MTrk chunk."""
    data = b""
    last = 0
    for tick, payload in sorted(events, key=lambda e: e[0]):
        data += vlq(tick - last) + payload
        last = tick
    data += vlq(0) + b"\xff\x2f\x00"
    return b"MTrk" + struct.pack(">I", len(data)) + data


def note(tick, length, pitch, channel=0):
    return [(tick, bytes([0x90 | channel, pitch, 100])), (tick + length, bytes([0x80 | channel, pitch, 0]))]


def write_song(path):
    # Track 0: tempo and a chord on every beat (C E G), with a lyric syllable
    # on beats 1 and 3. Track 1: drums.
    chords = [(0, b"\xff\x51\x03\x07\xa1\x20")]
    for beat in range(4):
        for pitch in (60, 64, 67):
            chords += note(beat * DIVISION, DIVISION, pitch)
    chords += [(DIVISION, b"\xff\x05\x02la"), (3 * DIVISION, b"\xff\x05\x02lo")]
    drums = []
    for beat in range(4):
        drums += note(beat * DIVISION, 60, 42, channel=9)
    header = b"MThd" + struct.pack(">IHHH", 6, 1, 2, DIVISION)
    with open(path, "wb") as handle:
        handle.write(header + track(chords) + track(drums))


class SongEditorTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        base = self.temp.name
        self.songs = os.path.join(base, "songs")
        self.out = os.path.join(base, "out")
        self.downloads = os.path.join(base, "downloads")
        for folder in (self.songs, self.downloads):
            os.makedirs(folder)
        write_song(os.path.join(self.songs, "test-tune.mid"))
        write_song(os.path.join(self.downloads, "Same Tune.mid"))  # a copy: left out
        write_song(os.path.join(self.downloads, "Other Tune.mid"))
        with open(os.path.join(self.downloads, "Other Tune.mid"), "ab") as handle:
            handle.write(b"\0")  # different bytes, same music
        self.saved = (editor.SONG_DIR, editor.OUT_DIR, editor.DOWNLOADS)
        editor.SONG_DIR, editor.OUT_DIR, editor.DOWNLOADS = self.songs, self.out, self.downloads

    def tearDown(self):
        editor.SONG_DIR, editor.OUT_DIR, editor.DOWNLOADS = self.saved
        self.temp.cleanup()

    def test_lists_songs_and_new_downloads(self):
        ids = [s["id"] for s in editor.list_songs()["songs"]]
        self.assertEqual(ids, ["songs/test-tune.mid", "downloads/Other Tune.mid"])

    def test_load_gives_every_note_in_ms_with_lyrics(self):
        song = editor.load_song("songs/test-tune.mid")
        self.assertEqual(len(song["notes"]), 16)
        self.assertEqual([p["drums"] for p in song["parts"]], [False, True])
        self.assertEqual(song["lyrics"], [[500, "la"], [1500, "lo"]])
        # The auto pick is the top of each chord.
        self.assertEqual([song["notes"][i][2] for i in song["auto"]], [67, 67, 67, 67])
        self.assertIsNone(song["saved"])

    def test_save_and_load_back(self):
        song = editor.load_song("songs/test-tune.mid")
        e_notes = [i for i, n in enumerate(song["notes"]) if n[2] == 64 and n[3] == 0]
        body = {"title": "Made Up", "group": "Kids", "kept": e_notes[:2], "added": [[1000, 1500, 62]]}
        result = editor.save_song("songs/test-tune.mid", body)
        self.assertEqual(result["notes"], 3)

        with open(os.path.join(self.out, "test-tune.json")) as handle:
            built = json.load(handle)
        self.assertEqual(built["title"], "Made Up")
        self.assertEqual(built["group"], "Kids")
        self.assertEqual([n[1] for n in built["notes"]], [0, 500, 1000])

        again = editor.load_song("songs/test-tune.mid")
        self.assertEqual(again["title"], "Made Up")
        self.assertEqual(sorted(again["saved"]["kept"]), e_notes[:2])
        self.assertEqual(again["saved"]["added"], [[1000, 1500, 62]])

    def test_saving_a_download_copies_it_into_the_songs(self):
        song = editor.load_song("downloads/Other Tune.mid")
        result = editor.save_song(song["id"], {"kept": song["auto"]})
        self.assertEqual(result["id"], "songs/other-tune.mid")
        self.assertTrue(os.path.exists(os.path.join(self.songs, "other-tune.mid")))
        self.assertTrue(os.path.exists(os.path.join(self.songs, "canon", "other-tune.json")))

    def test_ms_to_ticks_undoes_ticks_to_ms(self):
        tempos = [(0, 500000), (960, 250000)]
        for tick in (0, 100, 960, 1500):
            ms = editor.extractor.ticks_to_ms(tick, tempos, DIVISION)
            self.assertEqual(editor.ms_to_ticks(ms, tempos, DIVISION), tick)


if __name__ == "__main__":
    unittest.main()
