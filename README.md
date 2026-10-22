# MIDI Games

Kids' games played on a MIDI keyboard. The game is **Key Games**
(`apps/key_games`), a Flutter app for Android, Android TV and Windows: see
"App: Key Games" below. The rest of this repository is the bench that was
built first and still feeds it: a browser MIDI census and output lab for
learning what a keyboard sends and accepts, and a song editor that turns MIDI
files into the melodies the games play.

## Toolchain, tests and checks

| Part | Needs | Run |
|---|---|---|
| Key Games app | Flutter pinned in `apps/key_games/.fvmrc` (install with [FVM](https://fvm.app): `fvm install` in that folder, then `fvm flutter ...`) | `npm run test:app`, or `fvm flutter analyze` and `fvm flutter test` in `apps/key_games` |
| MIDI bench (browser pages and analysis) | Node 20+ | `npm test` |
| Song editor server | Python 3.12+ (no packages) | `npm run test:py` |

GitHub Actions (`.github/workflows/ci.yml`) runs all three on every push and
pull request, plus a check that nothing under `private/` is tracked. The same
privacy check runs locally as a Git hook; wire it once per clone with
`npm run hooks` (or `npm install`, which does the same). A version tag makes
a release with the installable builds: see "Releases" under the app.

## First experiment: identify the keyboard

One physical USB controller can appear in Windows as several related devices,
including MIDI, HID, audio, and composite-device interfaces. The initial workflow
therefore compares the complete Windows Plug-and-Play state instead of guessing
from a single friendly name.

1. Leave the MIDI keyboard disconnected.
2. Capture the current machine state and label every present node `NOT keyboard`:

   ```powershell
   .\scripts\Capture-PnpSnapshot.ps1
   ```

3. Connect the keyboard and wait a few seconds for Windows to finish enumerating it.
4. Compare the new state with the baseline:

   ```powershell
   .\scripts\Compare-PnpSnapshots.ps1
   ```

The scripts group newly appearing nodes using Windows device-container and parent
relationships, which makes composite controllers easier to recognize.

## Privacy boundary

Real device inventories can contain stable hardware identifiers. Real MIDI
performances, logs, screenshots, local configuration, paths, and personal notes
can be sensitive too. They belong under `private/`, which is ignored by Git.

Only generic code, documentation, and deliberately synthetic fixtures should be
committed. The scripts do not add hostname, username, or absolute-project-path
metadata, but Windows-provided device names can themselves contain identifying
text. Keep every raw snapshot private. Before publishing anything, inspect the
staged files; `.gitignore` is a guardrail, not a privacy audit.

Synthetic MIDI fixtures may be committed outside `private/` when the project
eventually needs tests. Real recordings should remain under `private/recordings/`.

## Run a complete MIDI capability census

The local listener opens every browser-visible MIDI input, inventories visible
outputs without opening them, and groups complete raw event streams into named
physical trials. The bundled plan covers keys, velocity, chords, pads and pad
banks, knobs and faders in both banks, wheels, pedals, panel buttons, presets,
musical transforms, USB/Bluetooth transport, output routing, audio, and recovery.

Each saved schema-version-2 census includes up to 100,000 ordered raw events,
relative event and callback timestamps, decoded MIDI fields, input/output port
topology, reconnect transitions, controller-state metadata, trial boundaries,
explicit no-MIDI results, and opt-in output observations. Raw mirror events are
preserved rather than silently deduplicated.

Run it from PowerShell:

```powershell
.\scripts\Start-MidiListener.ps1
```

By default, the launcher opens an isolated, Git-ignored Chrome/Edge profile with
Chromium's Windows Runtime MIDI backend enabled. This allows browser access to
Windows Bluetooth LE MIDI endpoints without changing the user's normal
`chrome://flags` settings. To test Chromium's default Windows MIDI backend
instead, pass `-MidiBackend Default`.

In the opened page:

1. Click **Enable MIDI**.
2. Record the controller screen/settings before changing modes.
3. Choose a guided trial, click **Begin selected trial**, operate only that
   control or mode at your own pace, choose the outcome, write any audible,
   visible, local-only, or uncertain observation, then click **Finish active
   trial**.
4. Use **Finish active: no MIDI** for local-only buttons. System clock and
   active-sensing noise do not prevent an honest no-MIDI result.
5. Click **Save private census**. The server saves the raw JSON and a derived
   Markdown analysis under ignored `private/midi/`.

Save after each small section. Each save is a checkpoint and does not clear the
active capture; the page also warns before leaving with unsaved evidence.

The output probe is deliberately separate and opt-in. It sends one short note at
a capped velocity to one selected output, then independently attempts Note Off,
All Notes Off, and All Sound Off and records every cleanup result. It does not
send Program Change, bank select, clock, reset, NRPN, or SysEx. The **Stop all
test notes** button sends cleanup-only messages on every channel to outputs that
remain open after uncertain cleanup, plus the currently selected output. Ports
with confirmed cleanup are closed after the probe so another MIDI program can
use them. Use connected headphones or powered-speaker volume at minimum and
complete the neutral-state checklist before probing.

For useful transport evidence, save separate sessions for neutral USB plus
Bluetooth, USB-only, and battery-powered Bluetooth-only operation. Do not mix
mode changes into a neutral control-mapping trial.

Starting again stops any previous listener server first. From cmd:

```bat
scripts\start-midi-listener.bat
scripts\midi-listener-status.bat
scripts\stop-midi-listener.bat
```

The server is a hidden `node` process identified by `serve-midi-listener.mjs`
in its command line. If the launching terminal is closed instead of stopped
with Ctrl+C, the server keeps running until `stop-midi-listener.bat` is run.

To regenerate or tune the offline analysis later:

```powershell
npm run midi:analyze -- private/midi/capability-census-EXAMPLE.json -o private/midi/capability-census-EXAMPLE-analysis.md
```

The analyzer reports per-port messages, signal ranges and step behavior,
trial-scoped note pairing/polyphony, unmatched events, and one-to-one exact-byte
mirror evidence with directional coverage and timing skew. It keeps attack and
release velocity separate and states limitations instead of inventing missing
capabilities.

## Output lab: what can the computer make the keyboard do?

A separate page that sends only standard, quiet MIDI to one chosen output:
a pad-light sweep (one note per pad, velocity capped at 32, each released and
followed by All Notes Off / All Sound Off), a single test note, and Program
Change. It never sends SysEx, reset, or clock. Incoming MIDI is logged during
tests, and the log saves under ignored `private/midi/output-lab-*.json`.

From cmd:

```bat
scripts\start-output-lab.bat
```

It uses the same server and stop/status scripts as the listener.

## Unattended output probe

Learns what the computer can make the keyboard's built-in synth do without
anyone watching: it sends quiet notes to every output port and channel while
recording the keyboard's own USB audio input, then measures which ports
sound, tuning, velocity and CC7 response, and whether Program Change changes
the sound. Needs PATCH on, nobody touching the keyboard, `ffmpeg` on PATH, and
Python with numpy. Takes about 3 minutes.

It needs the keyboard's audio input name and MIDI port name pattern. Pass
`-AudioDevice "..." -PortPattern "..."` or put them in ignored
`private/local-device.json` as `audioDevice` and `portPattern`.

```bat
scripts\run-auto-probe.bat
```

Results go to ignored `private/midi/auto-probe-*.json`; recordings to
`private/tmp/auto-probe/`. Pass `-SkipProgramChange` to avoid leaving the
synth on program 0.

## App: Key Games (Flutter, phone and PC)

`apps/key_games` is the same Color Keys game as a native app for Android and
Windows, with low-latency synth sound (SoLoud). It finds and connects to MIDI
keyboards by itself: Bluetooth LE MIDI devices from a scan, plus wired devices
with an input port. The status chip in the corner lists devices for manual
connect/disconnect. The real keys have no colors, so a 37-key picture of the
keyboard along the bottom shows them (white keys tinted, black keys with a
dot, note letters on the white keys) and makes every key of the target
note glow; the circle shows the note letter in its color; it follows the octave
buttons and can be played by touch. On a PC the keys `a s d f g h j k` play
too. Each new color plays its note.

Phone: connect the keyboard from inside the app only. If it is paired in the
phone's Bluetooth settings, Android may treat it as an audio device and send
the game's sound to it instead of the speaker.

Menus: home has categories (C Look, D Listen, E Songs, F Arcade; G is
Settings, a button in the header), each category lists its games (a category
with one game opens it straight away), and every game starts with a
difficulty picker: C Easy (ages 3+), D Medium (5+), E Hard (8+), F Expert
(grown-ups). Each game decides what the levels change (glowing keys, colors,
black keys, hints). Settings holds the Back pad (C, D forgets it) and About
(E: the version and the licenses page).

Keyboard only (TV boxes, no touch screen): every menu choice wears a note
letter and pressing any key of that letter picks it, so C C reaches the
first game on Easy (songs: first a group such as Kids or Classical, then a
song, C to A, B for the next page; end of a song:
C again, D listen, E more songs; end of Key Rush, Key Runner or Note Highway:
C again, E back). Going back: the on-screen back button, Escape, the remote's
back button, or a **Back pad**. Out of the box any pad goes back, once a
key has been played: a pad is a note on another MIDI channel than the keys
(the keys' channel is taken from the last note above 51, which no pad
sends; when keys and pads share a channel, no pad goes back). To use just
one pad or a panel button, pick it in Settings (G on the home menu, then C,
then press it); D there forgets it. Either way the Back pad never reaches a
game or makes a sound, and a picked one is remembered on the device. A key
that opens a page cannot also pick something on it: the app ignores menu picks for a moment after every page change. The
Android build also lists itself on Android TV home screens (banner, no touch
screen required).

How the app is put together: one key router (`lib/input/key_router.dart`)
owns every key the player presses (MIDI notes, the computer keys, Escape, the
Back pad) and hands them to the page on top only; every screen is a
`GamePage` (`lib/widgets/game_page.dart`) that supplies its header, body,
keyboard picture and overlays; the synth, the MIDI input, the router and the
settings live in `AppServices` (`lib/app/services.dart`) and are read with
`AppServices.of(context)`; colors, the typeface and the screen scale are in
`lib/app/theme.dart`; and each game keeps its rules in a pure `*_rules.dart`
file with its own unit tests.

Screens from a phone to a TV: the two that matter are a phone on its side
and a PC on a TV. `uiScale` (1 on a phone, 1.5 on a 1080p TV box, 2 on a
full-screen 1080p PC, and growing with the screen past that: 2.67 at 1440p)
grows every page's header, chips, badges and hints, the
countdowns, popups and end panels, and menu tiles are cards that never grow
wider than a hand-sized card at that scale, with everything drawn on them
scaling with the tile. Game boards fill the screen; the phone-sized caps on
their parts (lane widths, the road, the letters on the keyboard picture, its
height) grow with the same scale. The typeface is Nunito, bundled in
`apps/key_games/assets/fonts` under the SIL Open Font License (the license is
in the app's licenses page, Settings > About); text painted on a canvas
names the family itself, since painters do not inherit the theme.
`apps/key_games/tool/shoot-windows.ps1` screenshots every page of a debug
build at any screen size, driving it with the computer keys, for judging a
layout on a TV without one.

In Color Keys, a wrong key sounds once from the player's press and then the
right note sounds once by itself. The guided song and arcade games repeat the
wrong and right notes so they can be compared by ear.

The icon (Android, Android TV banner, Windows) is drawn by
`python scripts\make-app-icons.py` (needs Pillow).

```bat
cd apps\key_games
flutter build apk --release
flutter build windows --release
```

Windows: `scripts\start-key-games.bat` opens it borderless full screen (add
`--windowed` for a normal window); `scripts\stop-key-games.bat` or Alt+F4
quits. The app keeps the screen awake, since keyboard play is not screen
activity.

### Releases

Pushing a version tag builds the installable files and publishes them as a
GitHub release (`.github/workflows/release.yml`): the Android APK, named
`key-games-vX.Y.Z.apk`, and a Windows zip with the start and stop scripts
beside the exe. Bump `version` in `apps/key_games/pubspec.yaml` first (the
build number after `+` must grow, or Android refuses to install over the
last one; `lib/app/about.dart` carries the same version and a test checks
they match), then:

```bat
git tag v0.2.0
git push origin v0.2.0
```

The APK is signed with a release key, once made with
`scripts\make-android-key.ps1`. The script writes the keystore to
`private/keys/` and `apps/key_games/android/key.properties` (both ignored by
Git) and lists the four repository secrets the workflow needs
(`ANDROID_KEYSTORE_BASE64`, `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS`,
`ANDROID_KEY_PASSWORD`) in `private/keys/github-secrets.txt`, with a
`set-github-secrets.ps1` that adds them through the GitHub CLI. Back up
`private/keys`: a build signed with any other key, including the debug key a
plain checkout uses, does not install over one signed with it. A local
`flutter build apk --release` is signed with the same key once
`key.properties` exists.

### Song mode

Songs has two games, Song Steps and Note Highway, plus Song Box. In Song Steps, the glowing key walks
through a real melody one note at a time; the game waits for each note. The
octave matters (the keys send 48-84 with the octave button centered, matching
the picture; the octave buttons are followed by whole octaves), and the right
letter in the wrong octave shows "Higher!" or "Lower!". Bubbles show what comes next (higher notes sit higher), and
the next note sounds as a hint after a few quiet seconds. At the end the
melody plays back at real speed. On Easy and Medium the keyboard picture
shows only the keys from the song's lowest note to its highest.

The song list starts with the groups the songs are filed under (Kids,
Classical, Ballet, Musicals, Movies, Pop, Games, Anime, Rock), one letter
each (B turns the page when there are more than seven), then the songs of
the picked group.

Song Box (no levels) plays a picked song's melody, exactly the notes the
games use, at real speed with the keys lighting up: a quick way to hear
whether a song came out right. C plays it again, D stops, Back returns.

Ten old tunes are built in (`apps/key_games/lib/songs/builtin_songs.dart`,
all public domain: Twinkle Twinkle, Mary Had a Little Lamb, Ode to Joy and
friends), so the Songs games work in any build. More songs come from your
own MIDI files and are never committed:

```bat
python scripts\extract-melodies.py
cd apps\key_games
flutter build apk --release
```

The script reads `private/songs/*.mid`, picks the melody part (in a
karaoke file, the part that sings the lyrics; otherwise a one-note-at-a-time
part that is not a bass line, preferring tracks named like "Melody" or
"Vocal"), keeps one note at a time, shortens rests longer than
2.5 s (the melody part sitting out), moves it to the key with the fewest
black keys, fits it to the 37 keys, and writes
`apps/key_games/assets/songs/*.json` (ignored by Git). When it picks the
wrong part, add an override in `private/songs/song-picks.json`; the script's
header documents the options (track, channel, skip, max_notes, min_note,
lowest, title, group, transpose). Songs stop after 200 notes unless an
override says otherwise.

#### Song editor (pick the tune by hand)

When the script's pick is not quite the tune, the song editor lets you
choose the notes yourself, on a phone or the PC:

```bat
scripts\start-song-editor.bat -Phone
```

It starts a small server on this PC (`scripts/song-editor.py`, listening on
127.0.0.1:8766 only), runs `adb reverse` for every phone adb can see, and
opens `http://localhost:8766/` in Chrome on the phone (`-Browser brave` for
Brave, `-Pc` to open it on the PC too). `scripts\song-editor-status.bat`
says whether it is running; `scripts\stop-song-editor.bat` stops it.

The page lists the MIDI files in `private/songs` and in your Downloads
folder and shows a song as a piano roll: every note of every part in grey,
the tune in color (the script's pick, until you save your own).

- Tap: tap a note to keep it in the tune or drop it. The tune is one note at
  a time, so keeping a chord note drops whatever the tune had there.
- Keep / Drop: drag across notes to keep or drop many at once.
- Add: for a tune that is only sung over chords. Tap a spot or press a key
  (on screen, on the computer as in Key Games, or on a MIDI keyboard). The
  note starts on the nearest lyric syllable or note start in the song and
  lasts until the next tune note (or syllable), no longer than the chord
  under it, so nothing needs dragging. When stopped, each key press moves
  the start point on to the next syllable, so a line can be typed in note by
  note; while playing, notes land where you play them.
- Play plays the tune, or All plays the tune over the rest of the song.
  Parts shows and hides parts and keeps or drops a whole part.

Save writes the chosen notes to `private/songs/canon/<name>.json` (a file
from Downloads is copied into `private/songs` first) and rebuilds that
song's melody; build the app to play it. A canon file replaces the
script's pick for that song.

### Ear Notes

A mystery note plays and the child finds it by sound alone: the keyboard
picture has no colors and nothing glows. Any octave counts. A wrong key is
followed by the right note nearest to it, the mystery note replays after a
quiet spell (or a tap on the circle), and after two wrong
tries the answer lights up (found that way, it earns no star). Six stars move
up a level: C G, then C E G, then C D E F G, then all white keys, then all
twelve. The letters a level uses are shown above the keyboard; the level chip
skips ahead. Difficulty picks the starting level.

### Key Rush (Arcade)

After the arcade piano games: 3-2-1, then one minute to hit as many keys as
possible. The minute starts at the first right key, not at GO, so a player
can find the keys and set their fingers first. A board of tiles above the keyboard picture shows the key to press
now (bottom row) and the next three above it, lined up with the keys; each hit
moves the tiles down a row. Two ways to play:

- Easy: one octave is shown and only its four middle white keys (E F G A) are
  used, any octave counts, and the next key is never more than two keys away.
  Each hit plays the next note of a random bundled song (or a scale when none
  are bundled) instead of the key pressed, so the melody comes out. A wrong
  key makes no sound and costs nothing.
- Real: the keys are a random song's own notes in order, on their own keys,
  and each key sounds as itself. A wrong key plays itself and then the right
  note and freezes scoring for that moment while the clock runs.

Best scores are kept per level on the device.

### Note Highway (Songs)

Falling notes, Guitar Hero style: a song's notes come down lanes and are hit
as they reach the line, with a 3-2-1 while the first ones fall. Notes are never
made up: each lane is the note that sounds, and the song notes that are not
the player's (too fast for the level, or off its keys) are played by the game,
so the tune is always whole. Easy gives the player the notes on five
neighboring white keys (C to G for most songs; a song that is not on the white
keys is moved there first), slows the song down, and glows the next key on the
keyboard picture. On Easy and Medium the picture shows only the keys from
the lowest lane to the highest, in the octave last played. Medium uses all the white keys; Hard every letter with
sharps and flats, any octave; Expert the exact keys at full speed. A wrong key
plays itself and then the right note, and that note is missed; a key with
nothing due just plays.
Streaks of 10, 20 and 30 raise the score multiplier, and the end shows up to
three stars by the share of notes hit.

### Key Runner (Arcade)

Temple Run style: a runner on a three-lane road dodges rocks and grabs coins,
and the keys are just buttons that pick a lane. Each coin plays the next note
of a random bundled song, so a good run plays the melody. Easy: the low,
middle or high part of the keyboard picks the lane (marked above the keyboard
picture), no hearts to lose, one minute. Medium: C, E and G pick the lanes,
three hearts, the run goes on and slowly speeds up. Hard: three letters, sharps
too, that change every 20 seconds (the new ones play low to high). Expert:
faster, letters only, changing every 12 seconds. A row of rocks never blocks
all three lanes, and after a crash there is a moment to recover.
