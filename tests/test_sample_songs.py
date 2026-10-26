"""Sample songs and backing: the samples are up to date, each gives its
melody to the player and its chords and bass to the band, the band follows
the tune's clock, and the song editor lists the samples and saves a copy.

Run: python -m unittest discover -s tests -p "test_*.py"
"""

import importlib.util
import json
import os
import shutil
import struct
import subprocess
import sys
import tempfile
import unittest

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def load(name, file):
    spec = importlib.util.spec_from_file_location(name, os.path.join(ROOT, "scripts", file))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


samples = load("make_sample_songs", "make-sample-songs.py")
extractor = samples.extractor
editor = load("song_editor", "song-editor.py")
BEAT = samples.DIVISION  # ticks per beat; 120 bpm, so one beat is 500 ms


def note_events(channel, start, end, pitch):
    return [(start, 3, bytes([0x90 | channel, pitch, 90])), (end, 2, bytes([0x80 | channel, pitch, 0]))]


def write_midi(path, parts):
    """parts: [(name, channel, [(start_beat, beats, pitch)])] -> a MIDI file."""
    tracks = []
    for name, channel, notes in parts:
        events = [(0, 0, samples.meta(0x03, name.encode("ascii")))]
        for start, beats, pitch in notes:
            events += note_events(channel, round(start * BEAT), round((start + beats) * BEAT), pitch)
        tracks.append(samples.chunk(events))
    header = b"MThd" + struct.pack(">IHHH", 6, 1, len(tracks), BEAT)
    with open(path, "wb") as handle:
        handle.write(header + b"".join(tracks))


class SampleSongsTest(unittest.TestCase):
    def test_committed_samples_match_the_tunes(self):
        result = subprocess.run([sys.executable, os.path.join(ROOT, "scripts", "make-sample-songs.py"), "--check"],
                                capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_each_sample_gives_the_player_its_melody_and_the_band_the_rest(self):
        with tempfile.TemporaryDirectory() as temp:
            sample_dir, out_dir = os.path.join(temp, "samples"), os.path.join(temp, "out")
            samples.write_all(sample_dir, out_dir)
            for tune in samples.TUNES:
                with open(os.path.join(out_dir, tune["name"] + ".json"), encoding="utf-8") as handle:
                    song = json.load(handle)
                melody, _ = samples.melody_notes(tune)
                band, _ = samples.band_notes(tune)
                self.assertEqual(song["title"], tune["title"])
                self.assertEqual(song["part"], {"track": 1, "channel": 1}, tune["name"])
                self.assertEqual(len(song["notes"]), len(melody), tune["name"])
                self.assertEqual(len(song["backing"]), len(band), tune["name"])

    def test_a_shortened_rest_is_taken_out_of_the_band_too(self):
        # Tune: a note at beat 1, then 10 beats (5 s) of rest, then a note.
        # Band: an intro note before the tune (left out), a note in the part
        # of the rest taken out (left out), and one with the second tune note
        # (moved earlier with it).
        with tempfile.TemporaryDirectory() as temp:
            path = os.path.join(temp, "rest.mid")
            write_midi(path, [
                ("Melody", 0, [(1, 1, 72), (12, 1, 74)]),
                ("Bass", 1, [(0, 1, 36), (8, 1, 38), (12, 1, 43)]),
            ])
            song = extractor.extract(path, {"transpose": False})
        self.assertEqual([n[1] for n in song["notes"]], [0, 3000])
        self.assertEqual(song["backing"], [[43, 3000, 500]])

    def test_the_band_moves_to_the_tunes_key_but_not_by_octaves(self):
        # A tune in D with a bass D: the tune moves to C (two down) and up an
        # octave to the middle of the keyboard; the bass only moves to C.
        with tempfile.TemporaryDirectory() as temp:
            path = os.path.join(temp, "in-d.mid")
            write_midi(path, [
                ("Melody", 0, [(i, 1, p) for i, p in enumerate([50, 52, 54, 55, 57])]),
                ("Bass", 1, [(0, 4, 38)]),
            ])
            song = extractor.extract(path, {})
        self.assertEqual([n[0] for n in song["notes"]], [60, 62, 64, 65, 67])
        self.assertEqual(song["backing"][0][0], 36)


class EditorSamplesTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        base = self.temp.name
        self.songs, self.out = os.path.join(base, "songs"), os.path.join(base, "out")
        self.samples, self.downloads = os.path.join(base, "samples"), os.path.join(base, "downloads")
        for folder in (self.songs, self.downloads):
            os.makedirs(folder)
        samples.write_all(self.samples, os.path.join(base, "builtin"))
        self.saved = (editor.SONG_DIR, editor.OUT_DIR, editor.DOWNLOADS, editor.SAMPLE_DIR)
        editor.SONG_DIR, editor.OUT_DIR, editor.DOWNLOADS, editor.SAMPLE_DIR = (
            self.songs, self.out, self.downloads, self.samples)

    def tearDown(self):
        editor.SONG_DIR, editor.OUT_DIR, editor.DOWNLOADS, editor.SAMPLE_DIR = self.saved
        self.temp.cleanup()

    def test_samples_are_listed_and_a_saved_one_becomes_your_song(self):
        listed = {s["id"]: s for s in editor.list_songs()["songs"]}
        self.assertEqual(len(listed), len(samples.TUNES))
        twinkle = listed["samples/twinkle-twinkle.mid"]
        self.assertEqual((twinkle["source"], twinkle["title"]), ("samples", "Twinkle Twinkle Little Star"))

        song = editor.load_song("samples/twinkle-twinkle.mid")
        self.assertEqual((song["title"], song["group"]), ("Twinkle Twinkle Little Star", "Kids"))
        self.assertEqual(len(song["auto"]), 42)
        result = editor.save_song("samples/twinkle-twinkle.mid", {
            "kept": song["auto"][:14], "title": song["title"], "group": song["group"]})
        self.assertEqual(result["id"], "songs/twinkle-twinkle.mid")
        self.assertTrue(os.path.exists(os.path.join(self.songs, "twinkle-twinkle.mid")))
        with open(os.path.join(self.out, "twinkle-twinkle.json"), encoding="utf-8") as handle:
            mine = json.load(handle)
        self.assertEqual((mine["title"], len(mine["notes"])), ("Twinkle Twinkle Little Star", 14))
        self.assertTrue(mine["backing"])

        # The copy in the songs folder now stands for the sample.
        listed = {s["id"] for s in editor.list_songs()["songs"]}
        self.assertIn("songs/twinkle-twinkle.mid", listed)
        self.assertNotIn("samples/twinkle-twinkle.mid", listed)


if __name__ == "__main__":
    unittest.main()
