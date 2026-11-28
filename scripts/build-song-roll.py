"""Build a piano-roll sidecar from one original MIDI track and channel.

The sidecar is local song data. It preserves simultaneous notes, pitches and
MIDI timing; it does not guess a melody, fold octaves, or shorten rests.
"""

import argparse
import importlib.util
import json
from pathlib import Path

HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location('extract_melodies', HERE / 'extract-melodies.py')
extractor = importlib.util.module_from_spec(spec)
spec.loader.exec_module(extractor)


def build_roll(path, track, channel, description):
    division, _, parts, tempos = extractor.load(str(path))
    notes = parts.get((track, channel - 1))
    if not notes:
        raise ValueError(f'No notes on track {track}, channel {channel}')
    result = []
    for start, end, pitch in sorted(notes):
        start_ms = round(extractor.ticks_to_ms(start, tempos, division))
        end_ms = round(extractor.ticks_to_ms(end, tempos, division))
        result.append([pitch, start_ms, max(1, end_ms - start_ms)])
    return {'description': description, 'notes': result}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('midi', type=Path)
    parser.add_argument('output', type=Path, help='Sidecar path with the .roll extension')
    parser.add_argument('--track', required=True, type=int, help='Zero-based MIDI track')
    parser.add_argument('--channel', required=True, type=int, choices=range(1, 17))
    parser.add_argument('--description', required=True)
    args = parser.parse_args()
    if args.output.suffix != '.roll':
        parser.error('output must have the .roll extension')
    result = build_roll(args.midi, args.track, args.channel, args.description)
    # Exclusive creation protects the prior work if the user runs this twice.
    with args.output.open('x', encoding='utf-8', newline='\n') as handle:
        json.dump(result, handle, separators=(',', ':'))
    print(f"Wrote {len(result['notes'])} notes to {args.output}")


if __name__ == '__main__':
    main()
