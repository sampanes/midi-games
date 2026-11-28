"""A piano-roll export retains simultaneous notes and original rests."""
import importlib.util
from pathlib import Path
import tempfile
import unittest

from test_sample_songs import write_midi

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('build_song_roll', ROOT / 'scripts' / 'build-song-roll.py')
roll = importlib.util.module_from_spec(spec)
spec.loader.exec_module(roll)


class PianoRollExportTest(unittest.TestCase):
    def test_polyphony_timing_and_track_selection(self):
        with tempfile.TemporaryDirectory() as temp:
            path = Path(temp) / 'example.mid'
            write_midi(path, [
                ('Piano', 0, [(0, 2, 60), (0, 1, 64), (10, 1, 67)]),
                ('Other', 1, [(0, 1, 48)]),
            ])
            result = roll.build_roll(path, 0, 1, 'Piano')
            self.assertEqual(result['notes'], [[64, 0, 500], [60, 0, 1000], [67, 5000, 500]])
            self.assertEqual(result['description'], 'Piano')
            with self.assertRaises(ValueError):
                roll.build_roll(path, 0, 2, 'Missing')
