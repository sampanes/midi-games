"""Analyze an unattended MIDI output probe recording.

The probe script sends MIDI to the keyboard while recording the keyboard's own
USB audio input. This script lines the recording up with the send schedule
(using a marker note sent first) and measures what each trial produced.

Usage:
  python analyze-auto-probe.py PHASE WAV SCHEDULE_JSON OUT_JSON

PHASE is "matrix" or "detail". Requires numpy.
"""

import json
import sys
import wave

import numpy as np

SOUND_THRESHOLD_DB = -60.0
MARKER_THRESHOLD_DB = -60.0
FRAME_S = 0.01


def load_wav(path):
    with wave.open(path, "rb") as handle:
        rate = handle.getframerate()
        channels = handle.getnchannels()
        width = handle.getsampwidth()
        raw = handle.readframes(handle.getnframes())
    if width != 2:
        raise SystemExit(f"expected 16-bit audio, got {width * 8}-bit")
    samples = np.frombuffer(raw, dtype=np.int16).astype(np.float64) / 32768.0
    if channels > 1:
        samples = samples.reshape(-1, channels).mean(axis=1)
    return rate, samples


def db(value):
    return float(20.0 * np.log10(value + 1e-12))


def frame_levels(samples, rate):
    size = int(rate * FRAME_S)
    count = len(samples) // size
    frames = samples[: count * size].reshape(count, size)
    return np.sqrt(np.mean(frames ** 2, axis=1))


def find_marker_onset(samples, rate):
    levels = frame_levels(samples, rate)
    loud = np.nonzero(20.0 * np.log10(levels + 1e-12) > MARKER_THRESHOLD_DB)[0]
    if len(loud) == 0:
        return None
    return float(loud[0] * FRAME_S)


def segment(samples, rate, start_s, length_s):
    start = max(0, int(start_s * rate))
    end = min(len(samples), int((start_s + length_s) * rate))
    return samples[start:end]


def rms_db(chunk):
    if len(chunk) == 0:
        return None
    return round(db(np.sqrt(np.mean(chunk ** 2))), 1)


def onset_ms(chunk, rate):
    if len(chunk) == 0:
        return None
    size = int(rate * 0.002)
    count = len(chunk) // size
    if count == 0:
        return None
    levels = np.sqrt(np.mean(chunk[: count * size].reshape(count, size) ** 2, axis=1))
    loud = np.nonzero(20.0 * np.log10(levels + 1e-12) > SOUND_THRESHOLD_DB)[0]
    return None if len(loud) == 0 else round(float(loud[0] * 2.0), 1)


def spectrum(chunk, rate):
    if len(chunk) < 2048:
        return None, None
    window = np.hanning(len(chunk))
    magnitude = np.abs(np.fft.rfft(chunk * window))
    freqs = np.fft.rfftfreq(len(chunk), 1.0 / rate)
    return freqs, magnitude


def estimate_f0(chunk, rate):
    """Strongest spectral peak between 25 Hz and 2.5 kHz.

    FM (DX7-style) tones have inharmonic sidebands that send harmonic-product
    estimators to wrong octaves; on this synth the fundamental is the
    strongest partial, so the dominant peak is the more reliable estimate.
    """
    freqs, magnitude = spectrum(chunk, rate)
    if freqs is None or magnitude.max() <= 0:
        return None
    valid = (freqs >= 25) & (freqs <= 2500)
    if not valid.any():
        return None
    index = int(np.argmax(np.where(valid, magnitude, 0)))
    return round(float(freqs[index]), 2)


def fingerprint(chunk, rate):
    """Coarse log-spaced band energies, normalized, for timbre comparison."""
    freqs, magnitude = spectrum(chunk, rate)
    if freqs is None:
        return None
    edges = np.geomspace(50, 12000, 33)
    bands = []
    for low, high in zip(edges[:-1], edges[1:]):
        mask = (freqs >= low) & (freqs < high)
        bands.append(float(np.sum(magnitude[mask] ** 2)) if mask.any() else 0.0)
    vector = np.log10(np.array(bands) + 1e-12)
    vector -= vector.mean()
    norm = np.linalg.norm(vector)
    return (vector / norm).tolist() if norm > 0 else None


def similarity(a, b):
    if a is None or b is None:
        return None
    return round(float(np.dot(np.array(a), np.array(b))), 3)


def expected_hz(note):
    return 440.0 * 2 ** ((note - 69) / 12.0)


def main():
    if len(sys.argv) != 5:
        raise SystemExit(__doc__)
    phase, wav_path, schedule_path, out_path = sys.argv[1:]
    with open(schedule_path, "r", encoding="utf-8-sig") as handle:
        schedule = json.load(handle)
    rate, samples = load_wav(wav_path)

    marker = next(event for event in schedule["events"] if event["kind"] == "marker")
    audio_marker_s = find_marker_onset(samples, rate)
    result = {
        "phase": phase,
        "durationS": round(len(samples) / rate, 2),
        "noiseFloorDb": rms_db(segment(samples, rate, 0.2, 0.5)),
        "markerFound": audio_marker_s is not None,
        "trials": [],
    }
    if audio_marker_s is None:
        result["error"] = "Marker note was silent: PATCH may be off or synth audio is not reaching USB."
        with open(out_path, "w", encoding="utf-8") as handle:
            json.dump(result, handle, indent=2)
        return

    offset_s = audio_marker_s - marker["t"]
    result["clockOffsetS"] = round(offset_s, 3)
    baseline = None
    for event in schedule["events"]:
        if event["kind"] == "marker":
            continue
        start = event["t"] + offset_s
        window = segment(samples, rate, start - 0.05, 0.6)
        body = segment(samples, rate, start + 0.05, 0.3)
        level = rms_db(window)
        trial = dict(event)
        trial["levelDb"] = level
        trial["sounded"] = level is not None and level > SOUND_THRESHOLD_DB
        trial["onsetMsInWindow"] = onset_ms(window, rate) if trial["sounded"] else None
        if phase == "detail" and trial["sounded"]:
            if event["kind"] == "pitch":
                found = estimate_f0(body, rate)
                trial["f0Hz"] = found
                trial["expectedHz"] = round(expected_hz(event["note"]), 2)
                if found:
                    trial["centsOff"] = round(1200 * np.log2(found / trial["expectedHz"]), 1)
            if event["kind"] == "program":
                trial["fingerprint"] = fingerprint(body, rate)
                if event.get("program") is None:
                    baseline = trial["fingerprint"]
        result["trials"].append(trial)

    if phase == "detail":
        for trial in result["trials"]:
            if trial["kind"] == "program" and trial.get("fingerprint") is not None:
                trial["similarityToBaseline"] = similarity(baseline, trial["fingerprint"])
                del trial["fingerprint"]

    with open(out_path, "w", encoding="utf-8") as handle:
        json.dump(result, handle, indent=2)


if __name__ == "__main__":
    main()
