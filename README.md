# MIDI Games

An early workspace for small games and experiments controlled by a USB MIDI
keyboard. The concrete game, language, and runtime are intentionally undecided.

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

## Inventory physical MIDI controls

The local listener opens every browser-visible MIDI input simultaneously and
aggregates signals by port, channel, message type, and note/controller number.
It can label physical controls, record panel buttons that produce no MIDI, flag
possible mirrored events, and save a bounded inventory under ignored
`private/midi/`.

Run it from PowerShell:

```powershell
.\scripts\Start-MidiListener.ps1
```

By default, the launcher opens an isolated, Git-ignored Chrome/Edge profile with
Chromium's Windows Runtime MIDI backend enabled. This allows browser access to
Windows Bluetooth LE MIDI endpoints without changing the user's normal
`chrome://flags` settings. To test Chromium's default Windows MIDI backend
instead, pass `-MidiBackend Default`.

In the opened page, click **Enable MIDI**, exercise controls at your own pace,
then click **Save private inventory**. Keep the launching terminal open; press
Ctrl+C there when finished.

Starting again stops any previous listener server first. From cmd:

```bat
scripts\start-midi-listener.bat
scripts\midi-listener-status.bat
scripts\stop-midi-listener.bat
```

The server is a hidden `node` process identified by `serve-midi-listener.mjs`
in its command line. If the launching terminal is closed instead of stopped
with Ctrl+C, the server keeps running until `stop-midi-listener.bat` is run.

Labels typed in the page are copied to identical events that arrive on mirror
ports within the mirror window. Note ranges show press velocity only; release
velocity is excluded.
