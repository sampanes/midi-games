"""Song editor server: pick by hand which notes of a MIDI file are the tune.

Usage:
  python scripts/song-editor.py [--port 8766]

Start and stop it with scripts\\start-song-editor.bat and
scripts\\stop-song-editor.bat. It listens on 127.0.0.1 only; a phone reaches
it over USB or wireless debugging with "adb reverse tcp:8766 tcp:8766" (the
start script does this) and opens http://localhost:8766/.

It lists the MIDI files in private/songs and in the Downloads folder, sends
the page every note of a file, and saves the notes chosen there as the file's
canon version (private/songs/canon/<name>.json, see extract-melodies.py). A
file saved from Downloads is copied into private/songs first. Saving also
rebuilds that song's melody for the app (apps/key_games/assets/songs).
"""

import hashlib
import importlib.util
import json
import os
import re
import shutil
import sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, urlparse

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
PAGE_DIR = os.path.join(ROOT, "src")
PAGE_FOLDERS = ("song-editor", "games")
DOWNLOADS = os.path.join(os.path.expanduser("~"), "Downloads")
MIDI_EXTENSIONS = (".mid", ".midi", ".kar")
MAX_BODY = 2_000_000
CONTENT_TYPES = {".html": "text/html", ".js": "text/javascript", ".css": "text/css"}

spec = importlib.util.spec_from_file_location("extract_melodies", os.path.join(HERE, "extract-melodies.py"))
extractor = importlib.util.module_from_spec(spec)
spec.loader.exec_module(extractor)
inspect_midi = extractor.inspect_midi
SONG_DIR = extractor.SONG_DIR
OUT_DIR = extractor.OUT_DIR


def file_hash(path):
    with open(path, "rb") as handle:
        return hashlib.sha1(handle.read()).hexdigest()


def song_files():
    """{id: path} for every MIDI file the editor offers. Downloads files that
    are byte-for-byte copies of a song already in the song folder are left out."""
    files = {}
    known = set()
    if os.path.isdir(SONG_DIR):
        for name in sorted(os.listdir(SONG_DIR)):
            path = os.path.join(SONG_DIR, name)
            if name.lower().endswith(MIDI_EXTENSIONS) and os.path.isfile(path):
                files["songs/" + name] = path
                known.add(file_hash(path))
    if os.path.isdir(DOWNLOADS):
        for folder, dirs, names in os.walk(DOWNLOADS):
            depth = os.path.relpath(folder, DOWNLOADS).count(os.sep)
            if depth >= 2:
                dirs[:] = []
            for name in sorted(names):
                path = os.path.join(folder, name)
                if name.lower().endswith(MIDI_EXTENSIONS) and file_hash(path) not in known:
                    files["downloads/" + os.path.relpath(path, DOWNLOADS).replace(os.sep, "/")] = path
    return files


def song_title(song_id, picks):
    name = song_id.split("/")[-1]
    if song_id.startswith("songs/"):
        canon = extractor.read_canon(SONG_DIR, name) or {}
        title = canon.get("title") or picks.get(name, {}).get("title")
        if title:
            return title
    return extractor.title_from_file(name)


def song_group(name, picks):
    canon = extractor.read_canon(SONG_DIR, name) or {}
    return canon.get("group") or picks.get(name, {}).get("group", "Songs")


def list_songs():
    picks = extractor.read_picks(SONG_DIR)
    songs = []
    for song_id in song_files():
        source, name = song_id.split("/", 1)
        edited = source == "songs" and extractor.read_canon(SONG_DIR, name) is not None
        songs.append({
            "id": song_id,
            "source": source,
            "file": name,
            "title": song_title(song_id, picks),
            "group": song_group(name, picks) if source == "songs" else "",
            "edited": edited,
        })
    return {"songs": songs}


def ms_to_ticks(ms, tempos, division):
    """Inverse of extractor.ticks_to_ms."""
    done = 0.0
    last_tick, tempo = 0, 500000
    for change_tick, change_tempo in tempos:
        span = (change_tick - last_tick) * tempo / division / 1000
        if done + span >= ms:
            break
        done += span
        last_tick, tempo = change_tick, change_tempo
    return round(last_tick + (ms - done) * division * 1000 / tempo)


def file_notes(parts):
    """Every note of the file in a fixed order: [(key, start, end, note)]."""
    return [(key, *n) for key in sorted(parts) for n in sorted(parts[key])]


def programs_and_lyrics(tracks):
    programs = {}
    lyrics = []
    for index, events in enumerate(tracks):
        texts = []
        for tick, kind, fields in events:
            if kind == "meta":
                if fields[0] in (0x01, 0x05) and tick > 0:
                    texts.append((tick, fields[0], fields[1].decode("latin-1", "replace")))
            elif fields[0] == 0xC0:
                programs.setdefault((index, fields[1]), fields[2])
        if any(meta == 0x05 for _, meta, _ in texts):
            texts = [t for t in texts if t[1] == 0x05]
        lyrics += [(tick, text) for tick, _, text in texts]
    return programs, sorted(lyrics)


def lyric_text(text):
    text = text.lstrip("/\\").replace("\r", " ").replace("\n", " ")
    return "" if text.startswith("@") else text.strip()


def load_song(song_id):
    path = song_files().get(song_id)
    if path is None:
        raise KeyError(song_id)
    source, name = song_id.split("/", 1)
    picks = extractor.read_picks(SONG_DIR)
    options = picks.get(name, {}) if source == "songs" else {}
    division, tracks, parts, tempos = extractor.load(path)
    names = extractor.track_names(tracks)
    programs, lyrics = programs_and_lyrics(tracks)

    def ms(tick):
        return round(extractor.ticks_to_ms(tick, tempos, division))

    keys = sorted(parts)
    part_list = []
    for key in keys:
        drums = key[1] == 9
        program = programs.get(key, 0)
        part_list.append({
            "track": key[0],
            "channel": key[1] + 1,
            "name": names[key[0]] or "",
            "instrument": "drums" if drums else inspect_midi.GM_FAMILIES[program // 8],
            "drums": drums,
            "count": len(parts[key]),
        })
    notes = file_notes(parts)
    index_of = {(key, start, note): i for i, (key, start, end, note) in enumerate(notes)}

    try:
        key, line = extractor.pick_line(division, tracks, parts, options)
        auto = [index_of[(key, start, note)] for start, end, note in line if (key, start, note) in index_of]
    except Exception:
        auto = []

    canon = extractor.read_canon(SONG_DIR, name) if source == "songs" else None
    saved = None
    if canon:
        free = {}
        for i, (key, start, end, note) in enumerate(notes):
            free.setdefault((start, note), []).append(i)
        kept, added = [], []
        for start, end, note, track, channel in canon["notes"]:
            matches = free.get((start, note))
            if track >= 0 and matches:
                kept.append(matches.pop(0))
            else:
                added.append([ms(start), ms(end), note])
        saved = {"kept": kept, "added": added}

    groups = sorted({p.get("group", "Songs") for p in picks.values()} | {"Songs"})
    return {
        "id": song_id,
        "source": source,
        "file": name,
        "title": song_title(song_id, picks),
        "group": song_group(name, picks) if source == "songs" else "Songs",
        "groups": groups,
        "parts": part_list,
        "notes": [[ms(start), ms(end), note, keys.index(key)] for key, start, end, note in notes],
        "lyrics": [[ms(tick), lyric_text(text)] for tick, text in lyrics if lyric_text(text)],
        "auto": auto,
        "saved": saved,
    }


def safe_name(name):
    stem = re.sub(r"[^a-z0-9]+", "-", os.path.splitext(name)[0].lower()).strip("-") or "song"
    return stem + ".mid"


def save_song(song_id, body):
    path = song_files().get(song_id)
    if path is None:
        raise KeyError(song_id)
    source, name = song_id.split("/", 1)
    if source == "downloads":
        name = safe_name(os.path.basename(name))
        stem = os.path.splitext(name)[0]
        number = 2
        while os.path.exists(os.path.join(SONG_DIR, name)):
            name = f"{stem}-{number}.mid"
            number += 1
        shutil.copyfile(path, os.path.join(SONG_DIR, name))
    division, tracks, parts, tempos = extractor.load(os.path.join(SONG_DIR, name))
    notes = file_notes(parts)
    out = []
    for i in body.get("kept", []):
        key, start, end, note = notes[int(i)]
        out.append([start, end, note, key[0], key[1] + 1])
    for start_ms, end_ms, note in body.get("added", []):
        start = ms_to_ticks(float(start_ms), tempos, division)
        end = max(start + 1, ms_to_ticks(float(end_ms), tempos, division))
        out.append([start, end, int(note), -1, 0])
    if not out:
        raise ValueError("no notes chosen")
    out.sort()
    canon = {"source": name, "notes": out}
    for field in ("title", "group"):
        value = str(body.get(field, "")).strip()
        if value:
            canon[field] = value
    canon_dir = os.path.join(SONG_DIR, "canon")
    os.makedirs(canon_dir, exist_ok=True)
    canon_path = os.path.join(canon_dir, os.path.splitext(name)[0] + ".json")
    with open(canon_path, "w", encoding="utf-8", newline="\n") as handle:
        json.dump(canon, handle, separators=(",", ":"))
    song = extractor.write_song(SONG_DIR, OUT_DIR, name, extractor.read_picks(SONG_DIR))
    return {"id": "songs/" + name, "file": name, "notes": len(song["notes"])}


class Handler(BaseHTTPRequestHandler):
    server_version = "SongEditor"

    def log_message(self, fmt, *args):
        pass

    def send_json(self, status, payload):
        data = json.dumps(payload).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(data)

    def host_ok(self):
        # Only pages served from this machine (or the phone through adb
        # reverse, which also says localhost) may talk to the server.
        host = (self.headers.get("Host") or "").rsplit(":", 1)[0]
        if host in ("localhost", "127.0.0.1"):
            return True
        self.send_json(403, {"error": "forbidden host"})
        return False

    def do_GET(self):
        if not self.host_ok():
            return
        url = urlparse(self.path)
        query = parse_qs(url.query)
        try:
            if url.path == "/api/songs":
                return self.send_json(200, list_songs())
            if url.path == "/api/song":
                return self.send_json(200, load_song(query.get("id", [""])[0]))
        except KeyError:
            return self.send_json(404, {"error": "no such song"})
        except Exception as error:
            return self.send_json(500, {"error": str(error)})
        self.send_page(url.path)

    def do_POST(self):
        if not self.host_ok():
            return
        url = urlparse(self.path)
        if url.path != "/api/save":
            return self.send_json(404, {"error": "not found"})
        length = int(self.headers.get("Content-Length") or 0)
        if length > MAX_BODY:
            return self.send_json(413, {"error": "too big"})
        try:
            body = json.loads(self.rfile.read(length) or b"{}")
            return self.send_json(200, save_song(parse_qs(url.query).get("id", [""])[0], body))
        except KeyError:
            return self.send_json(404, {"error": "no such song"})
        except Exception as error:
            return self.send_json(400, {"error": str(error)})

    def send_page(self, path):
        if path in ("/", ""):
            path = "/song-editor/index.html"
        parts = [p for p in path.split("/") if p]
        if len(parts) != 2 or parts[0] not in PAGE_FOLDERS or parts[1].startswith("."):
            return self.send_json(404, {"error": "not found"})
        full = os.path.join(PAGE_DIR, parts[0], parts[1])
        kind = CONTENT_TYPES.get(os.path.splitext(full)[1])
        if kind is None or not os.path.isfile(full):
            return self.send_json(404, {"error": "not found"})
        with open(full, "rb") as handle:
            data = handle.read()
        self.send_response(200)
        self.send_header("Content-Type", kind + "; charset=utf-8")
        self.send_header("Content-Length", str(len(data)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(data)


def main():
    port = 8766
    if "--port" in sys.argv:
        port = int(sys.argv[sys.argv.index("--port") + 1])
    server = ThreadingHTTPServer(("127.0.0.1", port), Handler)
    print(f"Song editor at http://localhost:{port}/ (Ctrl+C or scripts\\stop-song-editor.bat stops it)")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    main()
