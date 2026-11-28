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
| Song editor server, song scripts | Python 3.12+ (no packages) | `npm run test:py` |

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

## My songs: a scrollable piano roll

Open **Songs > My songs** and choose a song. Its roll reads from top to bottom:
columns are keys, bars are notes, and bar length shows how long to hold a note.
Scroll vertically through the whole piece and sideways when there are more keys
than fit on the screen. The key names stay visible at the top. A roll made from
an original MIDI part can show simultaneous notes; older extracted song files
provide a simplified single-note line instead. Neither requires a MIDI keyboard.

A title marked **Notes not added yet** is just a reminder. The app does not
download music. Add a MIDI with the local song editor and local build workflow
below. To retain a polyphonic original MIDI part for the guide, use
`scripts/build-song-roll.py` to create a `.roll` file alongside its song JSON.
Run `python scripts/build-song-roll.py --help` for the track and channel options.
Private song files are bundled only in local builds, not committed or included
in GitHub release builds.

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
too, and `w e t y u` are the black keys between them. Each new color plays
its note.

Phone: connect the keyboard from inside the app only. If it is paired in the
phone's Bluetooth settings, Android may treat it as an audio device and send
the game's sound to it instead of the speaker.

Menus: home has six tiles (C Look, D Listen, E Memory, F Songs, G Arcade,
A Free Play) and two buttons in the header: Settings, on the black key F#
where a small child picking letters does not land on it, and, once a game
has been played, B Again. The categories say what a game asks for. Look: a
note is shown, find it. Listen: a note is heard, find it. Memory: here is a
pattern, play it back. Songs: real tunes, read as they go by. Arcade:
against the clock. Each category lists its games (a category with one game opens it
straight away), and every game starts with a difficulty picker: C Easy (ages
3+), D Medium (5+), E Hard (8+), F Expert (grown-ups). Each game decides what
the levels change (glowing keys, colors, black keys, hints), and a level
with a best score wears it in a gold pill. Free Play has no levels. Again
opens the game played last at its level, a song game straight into its song;
the line under the tiles says which. Settings holds the Back pad (C, D
forgets it), About (E: the version and the licenses page), the key sound (F)
and how loud a song's band is (G).

Sound: a key is struck like a toy piano: it starts at full level with a short
bright ring and fades to a soft hold while it is held, so a child leaning on
the keys is not a wall of sound. Settings > Key sound switches to Organ, the
plain steady tone the app started with, and plays a few notes to hear the
change. Settings > Band sets the music under a song to Full, Soft or Off.
Both are remembered on the device.

Keyboard only (TV boxes, no touch screen): on menus, song lists, and game-end
choices, C#/Db moves to the next choice and A#/Bb selects it. The current
selection is named on screen. These keys still play notes during games. The
existing letter shortcuts also work: every menu choice wears a note
letter and pressing any key of that letter picks it, so C C reaches the
first game on Easy (songs: first a group such as Kids or Classical, then a
song, C to A, B for the next page; end of a song:
C again, D listen, E more songs, F the next song of the list; end of Key
Rush, Key Runner, Copy Cat or Note Highway: C again, E back). Going back: the on-screen back button, Escape, the remote's
back button, or a **Back pad**. Out of the box any pad goes back, once a
key has been played: a pad is a note on another MIDI channel than the keys
(the keys' channel is taken from the last note above 51, which no pad
sends; when keys and pads share a channel, no pad goes back). To use just
one pad or a panel button, pick it in Settings (F# on the home menu, then C,
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
layout on a TV without one (`-Walk levels` shows just the easy levels,
`-Walk new` Free Play, Copy Cat, Settings and the stars on the song lists,
`-Walk memory` Song Memory from its first note to its end screen).

Playing without a keyboard: while no MIDI keyboard is connected, the
keyboard picture in every game is the keyboard, so it shows one octave of big
keys for fingers, middle C to the C above (also the computer keys' octave).
With a keyboard it shows 37 keys that follow the octave buttons. A song game
that needs more than that octave pictures just the song's keys instead.

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
melody plays back at real speed with its band, and the song earns up to
three stars: all three for (nearly) no wrong keys, one for getting to the
end at all. On Easy and Medium the keyboard picture shows only the keys from
the song's lowest note to its highest.

The song list starts with the groups the songs are filed under (Kids,
Holidays, Classical, Ballet, Musicals, Movies, Pop, Games, Anime, Rock), one
letter each (B turns the page when there are more than seven), then the
songs of the picked group. In Song Steps and Note Highway every song card
shows the most stars won on it at that level, and every group how many of
its stars are won. The end of a song offers the next song of the list (F),
so a child can play through a group without going back to the list.

Song Box (no levels) plays a picked song's melody, exactly the notes the
games use, at real speed with the keys lighting up and the song's band under
it: a quick way to hear whether a song came out right. C plays it again, D
stops, F plays the next song, Back returns.

Every song is a melody, the part the player plays (the singer's line, the
part people remember), and a backing: the rest of the music, chords, bass and
other parts, played by the app as a band. Note Highway and Song Box play the
band in time, on softer voices of their own; Song Steps waits for each note,
so it plays the melody alone until the play-back at the end.

Twenty-eight tunes are built in, all public domain: fifteen nursery and folk
songs (Twinkle Twinkle, Mary Had a Little Lamb, Itsy Bitsy Spider, Yankee
Doodle and friends), seven for the holidays (Jingle Bells, Deck the Halls,
Silent Night, Auld Lang Syne and more) and six classical themes (Ode to Joy,
Für Elise, Minuet in G, Canon in D, Brahms' Lullaby, In the Hall of the
Mountain King). They are written
out by hand in `scripts/make-sample-songs.py`, melody and chords, which writes
each as a MIDI file in `samples/` (a melody, chords and bass track: the song
editor lists them) and runs it through the same script as your own songs
into `apps/key_games/assets/builtin/`. Both are committed; after changing a
tune run `python scripts\make-sample-songs.py` (CI checks they are up to
date). More songs come from your own MIDI files and are never committed:

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
black keys, fits it to the 37 keys, keeps everything else the file plays
(drums aside) as the backing, moved to the same key and with the same
shortened rests, and writes `apps/key_games/assets/songs/*.json` (ignored by
Git). A song of yours with a built-in tune's title replaces it. When it picks the
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

The page lists the MIDI files in `private/songs`, the samples and your
Downloads folder and shows a song as a piano roll: every note of every part in grey,
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

Save writes the chosen notes to `private/songs/canon/<name>.json` (a sample
or a file from Downloads is copied into `private/songs` first) and rebuilds
that song's melody and backing (every note not in the tune); build the app
to play it. A canon file replaces the script's pick for that song.

### Free Play

No rules and nothing to get wrong, for the smallest players: every key plays
its note and sends a glowing ball of its color up from its place on the
keyboard picture, wearing the note's letter, and the ball bursts into sparks
at the top of its flight. A harder press flies higher.

### Copy Cat (Memory)

After the light-and-sound memory toys: the game plays a pattern on a row of
big pads (each lights up and sounds), then the player plays it back. A
pattern played back right grows by one note; a wrong note shows the pattern
again. The dots under the pads count the pattern and fill as it is played
back. Good for taking turns.

- Easy: the pads are the low, middle and high part of the keyboard (any key
  in the part counts). It cannot be lost, and a pattern of six is a win.
- Medium: C, E and G, in their colors on the keyboard picture; three hearts,
  one lost for each wrong note.
- Hard: C D E F G, a little faster.
- Expert: every white key, by ear: the pads stay dark while the pattern
  plays.

A key that is not one of the pads only sounds. The longest pattern played
back is the score, and the best per level is kept on the device.

### Song Memory (Memory)

A real tune learned by heart. The game plays a bit of the tune in the tune's
own rhythm (the keys light up and a big bubble shows each note), then the
player plays it back from memory. Played back right, it grows; a whole line
known, the next line starts. The letter counts, in any octave, and the
player's timing is never judged: the rhythm is for the ear.

A song is cut into lines where the tune takes a breath: a note held half as
long again as the song's everyday step ends a line of four to eight notes,
so "Twinkle, twinkle, little star" is one line and "how I wonder what you
are" the next. A tune that runs on without a breath is cut after its
longest note within reach.

- Easy: one more note each time, each line from its own start, for the
  first two lines of the song. A wrong key never starts over: the right key
  glows. So does waiting a while.
- Medium: one more note each time, the whole song. A wrong key, or a long
  wait, plays the bit again.
- Hard: a whole new line is played at once, and the player plays the song
  from the top up to it. Three hearts for each line, one lost for each wrong
  key; a wrong key plays everything again from the top.
- Expert: as Hard, by ear: the keys and the bubble stay dark while the game
  plays, and the song plays at its real speed.

A quick tune is slowed down on the other levels (Easy slowest) until its
everyday step is long enough to follow. The dots count what is to be played
back, with a gap between lines, and fill as it is played. At the end the
whole song plays at its real speed with its band, and the song earns up to
three stars per level (with hearts: all three for no wrong key; without: as
in Song Steps), shown on its card in the song list.

### Ear Notes

A mystery note plays and the child finds it by sound alone: nothing glows.
Any octave counts. A wrong key is followed by the right note nearest to it,
the mystery note replays after a quiet spell (or a tap on the circle), and
after two wrong tries the answer lights up (found that way, it earns no
star). Six stars move up a level: high or low, then C G, then C E G, then
C D E F G, then all white keys, then all twelve. High or low plays a very
low or very high note, and any key in the low or high half of the keyboard
picture answers (the halves are colored and named). The letters a level
uses are shown above the keyboard; the level chip skips ahead.

Difficulty picks the starting level and how much help there is. Easy starts
at high or low, Medium at C G; on both the level's notes keep their colors on
the keyboard picture, and a key that is not one of them only sounds, so the
one question is which of the few notes it was. Hard starts at C D E F G and
Expert at all twelve, on a plain picture where every key is an answer.

### Key Rush (Arcade)

After the arcade piano games: 3-2-1, then one minute to hit as many keys as
possible. The minute starts at the first right key, not at GO, so a player
can find the keys and set their fingers first. A board of tiles above the keyboard picture shows the key to press
now (bottom row) and the next three above it, lined up with the keys; each hit
moves the tiles down a row. Three ways to play:

- Easy: the board has three lanes, the low, middle and high part of the
  keyboard, lined up with the parts of the keyboard picture (tinted and
  named, the part to press lit). Any key in the part counts, so mashing works.
- Medium: one octave is shown and only C, E and G are used, any octave
  counts.
- On both, each hit plays the next note of a random bundled song (or a scale
  when none are bundled) instead of the key pressed, so the melody comes out,
  and a wrong key makes no sound and costs nothing.
- Real (the Hard slot): the keys are a random song's own notes in order, on their own keys,
  and each key sounds as itself. A wrong key plays itself and then the right
  note and freezes scoring for that moment while the clock runs.

Best scores are kept per level on the device (Real keeps the ones it had
when it was the second level).

### Note Highway (Songs)

Falling notes, Guitar Hero style: a song's notes come down lanes and are hit
as they reach the line, with a 3-2-1 while the first ones fall. Notes are never
made up: each lane is the note that sounds, and the song notes that are not
the player's (too fast for the level, or off its keys) are played by the game,
so the tune is always whole, and the song's band plays along whatever the
player hits. Easy has three wide lanes, the low, middle and
high part of the keyboard: the song's notes are shared out by how high they
are, so the lanes follow the tune up and down, any key in the part plays the
song's own note, the song is slowed down, and the next part glows on the
keyboard picture. Medium gives the player the notes on five neighboring white
keys (C to G for most songs; a song that is not on the white keys is moved
there first), slows the song down, glows the next key, and pictures only the
keys from the lowest lane to the highest, in the octave last played. Hard
every letter with sharps and flats, any octave; Expert the exact keys at full
speed. Best scores and the most stars per song and level are kept on the
device (Medium keeps the scores it had when it was Easy). A wrong key
plays itself and then the right note, and that note is missed; a key with
nothing due just plays.
Streaks of 10, 20 and 30 raise the score multiplier, and the end shows up to
three stars by the share of notes hit.

### Key Runner (Arcade)

Temple Run style: a runner on a three-lane road dodges rocks and grabs coins,
and the keys are just buttons that pick a lane. Each coin plays the next note
of a random bundled song, so a good run plays the melody. Easy: the low,
middle or high part of the keyboard picks the lane (marked above the keyboard
picture, which is tinted by part with the runner's part lit), no hearts to
lose, one minute. The parts are the same in every game that uses them: Ear
Notes, Key Rush and Note Highway on Easy. Medium: C, E and G pick the lanes,
three hearts, the run goes on and slowly speeds up. Hard: three letters, sharps
too, that change every 20 seconds (the new ones play low to high). Expert:
faster, letters only, changing every 12 seconds. A row of rocks never blocks
all three lanes, and after a crash there is a moment to recover.
