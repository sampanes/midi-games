# Screenshots of the Windows build at a chosen screen size, for judging the
# layout on a TV without one: launches the debug exe windowed, sizes its
# client area to W x H physical pixels on a monitor, walks the menus and the
# games with the computer keys (A S D F G H J = C D E F G A B, T = F#,
# Escape = back) by posting key messages to the Flutter view, and saves one
# PNG per page.
#
#   flutter build windows --debug
#   .\tool\shoot-windows.ps1 -ListMonitors                # which monitor is which
#   .\tool\shoot-windows.ps1 -W 1920 -H 1080              # a 1080p TV box (1.5x: 1280x720 logical)
#   .\tool\shoot-windows.ps1 -W 2880 -H 1620 -Monitor 2   # 1920x1080 logical on a 150% monitor
#   .\tool\shoot-windows.ps1 -W 1323 -H 617 -Monitor 2    # a phone on its side (882x411 logical)
#   .\tool\shoot-windows.ps1 -Walk levels ...             # each game's easy levels only
#   .\tool\shoot-windows.ps1 -Walk songs ...              # the classical songs, with their band
#   .\tool\shoot-windows.ps1 -Walk new ...                # Free Play, Copy Cat, Settings, stars
#   .\tool\shoot-windows.ps1 -Walk memory ...             # Song Memory, a song learned by heart
#
# The logical size Flutter lays out is W x H divided by the monitor's scale.
# Pages are captured with PrintWindow, which gives a blank frame while the
# displays are asleep, so a zero-pixel mouse move wakes them first. The
# full walk takes about four minutes: Key Rush and Key Runner each run a
# full minute to reach their end screens. The levels walk (about two
# minutes) shows the pickers and the first levels of Ear Notes, Note
# Highway, Key Rush and Key Runner. The new walk shows Free Play, Copy Cat,
# Settings, and the stars, "Next song" and Again that playing a song leaves.
# The memory walk (about three minutes) learns the start of Twinkle Twinkle
# on Easy to its end screen, then opens it on Hard and Expert.
# The app remembers best scores, stars and the last game between runs
# (shared_preferences), so those show up from the second run on.

param(
  [string]$Out = "$PSScriptRoot\..\build\shots",
  [int]$Monitor = -1,
  [int]$W = 1920,
  [int]$H = 1080,
  [ValidateSet('all', 'levels', 'songs', 'new', 'memory')][string]$Walk = 'all',
  [switch]$ListMonitors
)
$ErrorActionPreference = 'Stop'

$sig = @"
using System;
using System.Runtime.InteropServices;
using System.Collections.Generic;
public class W {
  [DllImport("shcore.dll")] public static extern int SetProcessDpiAwareness(int v);
  [DllImport("user32.dll")] public static extern bool MoveWindow(IntPtr h, int x, int y, int w, int hgt, bool repaint);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern bool GetClientRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern bool ClientToScreen(IntPtr h, ref POINT p);
  [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr h, uint msg, IntPtr w, IntPtr l);
  [DllImport("user32.dll")] public static extern uint MapVirtualKey(uint code, uint type);
  [DllImport("user32.dll")] public static extern bool EnumChildWindows(IntPtr h, EnumProc cb, IntPtr l);
  [DllImport("user32.dll")] public static extern int GetClassName(IntPtr h, System.Text.StringBuilder s, int n);
  [DllImport("user32.dll")] public static extern bool EnumDisplayMonitors(IntPtr hdc, IntPtr clip, MonProc cb, IntPtr l);
  [DllImport("user32.dll")] public static extern bool GetMonitorInfo(IntPtr h, ref MONITORINFO mi);
  [DllImport("shcore.dll")] public static extern int GetDpiForMonitor(IntPtr h, int type, out uint x, out uint y);
  [DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr h, IntPtr hdc, uint flags);
  [DllImport("user32.dll")] public static extern uint SendInput(uint n, INPUT[] inputs, int size);
  [StructLayout(LayoutKind.Sequential)] public struct MOUSEINPUT { public int dx; public int dy; public uint mouseData; public uint dwFlags; public uint time; public IntPtr dwExtraInfo; }
  [StructLayout(LayoutKind.Sequential)] public struct INPUT { public uint type; public MOUSEINPUT mi; }
  public static uint Nudge() {
    var input = new INPUT[1];
    input[0].type = 0;
    input[0].mi.dwFlags = 0x0001;
    return SendInput(1, input, Marshal.SizeOf(typeof(INPUT)));
  }
  public delegate bool EnumProc(IntPtr h, IntPtr l);
  public delegate bool MonProc(IntPtr h, IntPtr hdc, ref RECT r, IntPtr l);
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int L, T, R, B; }
  [StructLayout(LayoutKind.Sequential)] public struct POINT { public int X, Y; }
  [StructLayout(LayoutKind.Sequential)] public struct MONITORINFO { public int cb; public RECT rcMonitor; public RECT rcWork; public uint flags; }
  public static List<IntPtr> Children(IntPtr h) {
    var l = new List<IntPtr>();
    EnumChildWindows(h, (c, p) => { l.Add(c); return true; }, IntPtr.Zero);
    return l;
  }
  public static List<int[]> Monitors() {
    var l = new List<int[]>();
    EnumDisplayMonitors(IntPtr.Zero, IntPtr.Zero, (IntPtr h, IntPtr hdc, ref RECT r, IntPtr p) => {
      var mi = new MONITORINFO(); mi.cb = Marshal.SizeOf(typeof(MONITORINFO)); GetMonitorInfo(h, ref mi);
      uint dx, dy; GetDpiForMonitor(h, 0, out dx, out dy);
      l.Add(new int[]{ mi.rcMonitor.L, mi.rcMonitor.T, mi.rcMonitor.R, mi.rcMonitor.B, (int)dx, (int)(mi.flags & 1) });
      return true;
    }, IntPtr.Zero);
    return l;
  }
}
"@
Add-Type -TypeDefinition $sig
try { [W]::SetProcessDpiAwareness(2) | Out-Null } catch {}
Add-Type -AssemblyName System.Drawing

$mons = [W]::Monitors()
for ($i = 0; $i -lt $mons.Count; $i++) {
  $m = $mons[$i]
  Write-Host ("monitor {0}: at {1},{2} size {3}x{4} dpi={5} primary={6}" -f $i, $m[0], $m[1], ($m[2]-$m[0]), ($m[3]-$m[1]), $m[4], $m[5])
}
if ($ListMonitors) { return }
if ($Monitor -lt 0) {
  for ($j = 0; $j -lt $mons.Count; $j++) {
    $m = $mons[$j]
    if ($m[4] -eq 96 -and ($m[2]-$m[0]) -ge $W -and ($m[3]-$m[1]) -ge $H) { $Monitor = $j; break }
  }
  if ($Monitor -lt 0) { for ($j = 0; $j -lt $mons.Count; $j++) { if ($mons[$j][5] -eq 1) { $Monitor = $j } } }
}
$m = $mons[$Monitor]
Write-Host "using monitor $Monitor (dpi $($m[4])): a $W x $H client is $([int]($W*96/$m[4])) x $([int]($H*96/$m[4])) logical"

New-Item -ItemType Directory -Force $Out | Out-Null
[W]::Nudge() | Out-Null
Start-Sleep -Milliseconds 3000
$exe = Join-Path $PSScriptRoot "..\build\windows\x64\runner\Debug\key_games.exe"
$proc = Start-Process -FilePath $exe -ArgumentList '--windowed' -WorkingDirectory (Split-Path $exe) -PassThru
try {
  $deadline = (Get-Date).AddSeconds(30)
  while ((Get-Date) -lt $deadline) {
    $proc.Refresh()
    if ($proc.MainWindowHandle -ne [IntPtr]::Zero) { break }
    Start-Sleep -Milliseconds 200
  }
  $hwnd = $proc.MainWindowHandle
  if ($hwnd -eq [IntPtr]::Zero) { throw "the app opened no window" }
  Start-Sleep -Milliseconds 15000

  # Place the window and size its client area to W x H physical pixels. Flutter
  # resizes itself when the window crosses to another DPI, so apply it twice.
  for ($pass = 0; $pass -lt 2; $pass++) {
    $wr = New-Object W+RECT; [W]::GetWindowRect($hwnd, [ref]$wr) | Out-Null
    $cr = New-Object W+RECT; [W]::GetClientRect($hwnd, [ref]$cr) | Out-Null
    $dw = ($wr.R - $wr.L) - ($cr.R - $cr.L); $dh = ($wr.B - $wr.T) - ($cr.B - $cr.T)
    [W]::MoveWindow($hwnd, $m[0], $m[1], $W + $dw, $H + $dh, $true) | Out-Null
    Start-Sleep -Milliseconds 800
  }
  $cr = New-Object W+RECT; [W]::GetClientRect($hwnd, [ref]$cr) | Out-Null
  Write-Host ("client is {0} x {1}" -f ($cr.R-$cr.L), ($cr.B-$cr.T))

  $view = $hwnd
  foreach ($c in [W]::Children($hwnd)) {
    $sb = New-Object System.Text.StringBuilder 256
    [W]::GetClassName($c, $sb, 256) | Out-Null
    if ($sb.ToString() -eq 'FLUTTERVIEW') { $view = $c }
  }

  # The computer keys the app plays: A S D F G H J K are the notes C D E F G
  # A B C, so the menu letter E is the D key, and T is the black key F#. A
  # key code of 0 must never be posted: it leaves the app's key handling
  # confused for a while.
  $vk = @{ A=0x41; S=0x53; D=0x44; F=0x46; G=0x47; H=0x48; J=0x4A; K=0x4B; T=0x54; ESC=0x1B }
  function Press($name) {
    if (-not $vk.ContainsKey($name)) { throw "unknown key '$name' (use A S D F G H J K, T or ESC)" }
    $code = [int]$vk[$name]
    $scan = [int][W]::MapVirtualKey([uint32]$code, 0)
    $down = [int64](1 -bor ($scan -shl 16))
    $up = [int64]($down -bor 0xC0000000)
    [W]::PostMessage($view, 0x100, [IntPtr]$code, [IntPtr]$down) | Out-Null
    Start-Sleep -Milliseconds 80
    [W]::PostMessage($view, 0x101, [IntPtr]$code, [IntPtr]$up) | Out-Null
    Start-Sleep -Milliseconds 1100
  }

  # A quick press, for playing notes in a game: no wait for a page to settle.
  function Tap($name) {
    $code = [int]$vk[$name]
    $scan = [int][W]::MapVirtualKey([uint32]$code, 0)
    $down = [int64](1 -bor ($scan -shl 16))
    $up = [int64]($down -bor 0xC0000000)
    [W]::PostMessage($view, 0x100, [IntPtr]$code, [IntPtr]$down) | Out-Null
    Start-Sleep -Milliseconds 70
    [W]::PostMessage($view, 0x101, [IntPtr]$code, [IntPtr]$up) | Out-Null
    Start-Sleep -Milliseconds 50
  }

  function Shot($name, $settle = 1200) {
    Start-Sleep -Milliseconds $settle
    $wr = New-Object W+RECT; [W]::GetWindowRect($hwnd, [ref]$wr) | Out-Null
    $cr = New-Object W+RECT; [W]::GetClientRect($hwnd, [ref]$cr) | Out-Null
    $origin = New-Object W+POINT; [W]::ClientToScreen($hwnd, [ref]$origin) | Out-Null
    $ww = $wr.R - $wr.L; $wh = $wr.B - $wr.T
    $cw = $cr.R - $cr.L; $ch = $cr.B - $cr.T
    $full = New-Object System.Drawing.Bitmap $ww, $wh
    $g = [System.Drawing.Graphics]::FromImage($full)
    $hdc = $g.GetHdc()
    [W]::PrintWindow($hwnd, $hdc, 2) | Out-Null
    $g.ReleaseHdc($hdc); $g.Dispose()
    $crop = New-Object System.Drawing.Rectangle ($origin.X - $wr.L), ($origin.Y - $wr.T), $cw, $ch
    $bmp = $full.Clone($crop, $full.PixelFormat)
    $full.Dispose()
    $bmp.Save("$Out\$name.png", [System.Drawing.Imaging.ImageFormat]::Png)
    $bmp.Dispose()
    Write-Host "shot $name ($cw x $ch)"
  }

  # Key Rush's minute starts at the first right key, so its end step first
  # taps one key in each part of the keyboard.
  # From the home menu, in menu letters: A = C (Look), S = D (Listen), D = E
  # (Memory), F = F (Songs), G = G (Arcade), H = A (Free Play), J = B (Again)
  # and T = F# (Settings). Look and Listen (one game each) open their game's
  # levels straight away; a difficulty picker is replaced by its game, so
  # Escape from a game returns to the menu above the picker. Songs pick a group
  # (Kids), then a song: F is Hot Cross Buns, the shortest, which the Song
  # Steps walk plays to its end on the computer keys (E D C = D S A).
  $hotCrossBuns = @('D', 'S', 'A', 'D', 'S', 'A', 'A', 'A', 'A', 'A', 'S', 'S', 'S', 'S', 'D', 'S', 'A')
  $steps = @(
    @{ name = 'home';               keys = @() },
    @{ name = 'difficulty-color';   keys = @('A') },
    @{ name = 'game-color-keys';    keys = @('A') },
    @{ name = 'menu-songs';         keys = @('ESC', 'ESC', 'F') },
    @{ name = 'difficulty-steps';   keys = @('A') },
    @{ name = 'groups-steps';       keys = @('A') },
    @{ name = 'songlist-steps';     keys = @('A') },
    @{ name = 'game-steps';         keys = @('F'); wait = 1500 },
    @{ name = 'end-steps';          keys = $hotCrossBuns; wait = 12000 },
    @{ name = 'songbox-groups';     keys = @('ESC', 'ESC', 'ESC', 'D') },
    @{ name = 'songbox';            keys = @('A', 'A'); wait = 1500 },
    @{ name = 'difficulty-highway'; keys = @('ESC', 'ESC', 'ESC', 'S') },
    @{ name = 'groups-highway';     keys = @('A') },
    @{ name = 'songlist-highway';   keys = @('A') },
    @{ name = 'game-highway';       keys = @('F'); wait = 5000 },
    @{ name = 'end-highway';        keys = @(); wait = 16000 },
    @{ name = 'menu-arcade';        keys = @('ESC', 'ESC', 'ESC', 'ESC', 'G') },
    @{ name = 'game-rush';          keys = @('A', 'A'); wait = 3500 },
    @{ name = 'end-rush';           keys = @(); tap = @('A', 'F', 'H'); wait = 61000 },
    @{ name = 'game-runner';        keys = @('ESC', 'S', 'A'); wait = 3500 },
    @{ name = 'end-runner';         keys = @(); wait = 60000 },
    @{ name = 'game-ear';           keys = @('ESC', 'ESC', 'S', 'A'); wait = 1500 },
    @{ name = 'settings';           keys = @('ESC', 'T') },
    @{ name = 'about';              keys = @('D') },
    @{ name = 'learn-back';         keys = @('ESC', 'A') }
  )
  # The first levels of each game. From a one-game category's game, Escape
  # goes home; from a song game, three Escapes reach the Songs menu.
  $levelSteps = @(
    @{ name = 'difficulty-ear';     keys = @('S') },
    @{ name = 'game-ear-easy';      keys = @('A'); wait = 1500 },
    @{ name = 'game-ear-medium';    keys = @('ESC', 'S', 'S'); wait = 3000 },
    @{ name = 'difficulty-highway'; keys = @('ESC', 'F', 'S') },
    @{ name = 'game-highway-easy';  keys = @('A', 'A', 'F'); wait = 5500 },
    @{ name = 'game-highway-medium'; keys = @('ESC', 'ESC', 'ESC', 'S', 'S', 'A', 'F'); wait = 5500 },
    @{ name = 'difficulty-rush';    keys = @('ESC', 'ESC', 'ESC', 'ESC', 'G', 'A') },
    @{ name = 'game-rush-easy';     keys = @('A'); wait = 3500 },
    @{ name = 'game-rush-medium';   keys = @('ESC', 'A', 'S'); wait = 3500 },
    @{ name = 'game-rush-real';     keys = @('ESC', 'A', 'D'); wait = 3500 },
    @{ name = 'game-runner-easy';   keys = @('ESC', 'S', 'A'); wait = 4500 }
  )
  if ($Walk -eq 'levels') { $steps = @(@{ name = 'home'; keys = @() }) + $levelSteps }

  # The built-in classical songs (the third group): Song Box and Note
  # Highway on Canon in D (the second of them), which play its band.
  $songSteps = @(
    @{ name = 'menu-songs';          keys = @('F') },
    @{ name = 'songbox-groups';      keys = @('D') },
    @{ name = 'songbox-classical';   keys = @('D') },
    @{ name = 'songbox-canon';       keys = @('S'); wait = 2500 },
    @{ name = 'songlist-highway';    keys = @('ESC', 'ESC', 'ESC', 'S', 'A', 'D') },
    @{ name = 'game-highway-canon';  keys = @('S'); wait = 6500 }
  )
  if ($Walk -eq 'songs') { $steps = @(@{ name = 'home'; keys = @() }) + $songSteps }

  # What is new in 0.3.0. A step's "tap" keys are played quickly after its
  # "keys" (notes in a game), and "settle" is the pause before its shot,
  # short when the shot must catch something in the air or a pad lit.
  $newSteps = @(
    @{ name = 'free-play';         keys = @('H'); tap = @('A', 'D', 'G', 'K', 'S', 'F', 'H'); settle = 150 },
    @{ name = 'menu-memory';       keys = @('ESC', 'D') },
    @{ name = 'difficulty-copy';   keys = @('A') },
    @{ name = 'game-copy-easy';    keys = @('A'); settle = 500 },
    @{ name = 'game-copy-medium';  keys = @('ESC', 'A', 'S'); settle = 500 },
    @{ name = 'game-copy-turn';    keys = @(); wait = 1500 },
    @{ name = 'game-copy-hard';    keys = @('ESC', 'A', 'D'); settle = 500 },
    @{ name = 'game-copy-expert';  keys = @('ESC', 'A', 'F'); wait = 1500 },
    @{ name = 'settings';          keys = @('ESC', 'ESC', 'T') },
    @{ name = 'groups-steps';      keys = @('ESC', 'F', 'A', 'A') },
    @{ name = 'end-steps';         keys = @('A', 'F') + $hotCrossBuns; wait = 12000 },
    @{ name = 'songlist-steps';    keys = @('ESC') },
    @{ name = 'songbox-holidays';  keys = @('ESC', 'ESC', 'D', 'S') },
    @{ name = 'songbox';           keys = @('A'); wait = 2500 },
    @{ name = 'home-again';        keys = @('ESC', 'ESC', 'ESC', 'ESC') }
  )
  if ($Walk -eq 'new') { $steps = @(@{ name = 'home'; keys = @() }) + $newSteps }

  # Song Memory on Twinkle Twinkle Little Star (Kids, third page, second
  # song: J J S), whose first two lines are C C G G A A G and F F E E D D C,
  # all on the computer keys. Easy grows each line a note at a time: the
  # walk plays every turn back (a step without a name takes no shot), with
  # one wrong key on the way to show the help, to the end screen. Then the
  # same song on Hard, a whole line at a time from the top, and on Expert.
  $twinkle = @('J', 'J', 'S')
  $line1 = @('A', 'A', 'G', 'G', 'H', 'H', 'G')
  $line2 = @('F', 'F', 'D', 'D', 'S', 'S', 'A')
  # After a turn of $n notes is played back, how long until the next turn
  # ($n + 1 notes, half a second apart) has been played and handed over.
  function NextTurn($n) { 900 + 300 + $n * 500 + 1600 }
  $memorySteps = @(
    @{ name = 'menu-memory';         keys = @('D') },
    @{ name = 'difficulty-memory';   keys = @('S') },
    @{ name = 'groups-memory';       keys = @('A') },
    @{ name = 'songlist-memory';     keys = @('A', 'J', 'J') },
    @{ name = 'game-memory-watch';   keys = @('S'); settle = 550 },
    @{ name = 'game-memory-turn';    keys = @(); wait = 1200 }
  )
  foreach ($first in $true, $false) {
    $line = if ($first) { $line1 } else { $line2 }
    for ($n = 1; $n -le 7; $n++) {
      $turn = @($line[0..($n - 1)])
      if ($first -and $n -eq 3) {
        # C C, then a wrong key: the right one glows.
        $memorySteps += @{ name = 'game-memory-help'; keys = @(); tap = @('A', 'A', 'F'); settle = 500 }
        $memorySteps += @{ keys = @(); tap = @('G'); wait = (NextTurn $n) }
      } elseif ($first -and $n -eq 5) {
        # Part of the way through a turn: the dots fill as it is played.
        $memorySteps += @{ name = 'game-memory-dots'; keys = @(); tap = @($turn[0..2]); settle = 120 }
        $memorySteps += @{ keys = @(); tap = @($turn[3..4]); wait = (NextTurn $n) }
      } elseif ($n -lt 7) {
        $memorySteps += @{ keys = @(); tap = $turn; wait = (NextTurn $n) }
      } elseif ($first) {
        $memorySteps += @{ name = 'game-memory-line'; keys = @(); tap = $turn; settle = 500 }
        # The next line starts with one note, after a longer pause.
        $memorySteps += @{ keys = @(); wait = 1700 + 300 + 1600 }
      } else {
        $memorySteps += @{ name = 'game-memory-win'; keys = @(); tap = $turn; settle = 900 }
      }
    }
  }
  $memorySteps += @(
    @{ name = 'game-memory-listen';  keys = @(); wait = 4000 },
    @{ name = 'end-memory';          keys = @(); wait = 24000 },
    @{ name = 'songlist-memory-stars'; keys = @('ESC') },
    @{ name = 'game-memory-hard';    keys = @('ESC', 'ESC', 'S', 'D', 'A') + $twinkle; settle = 1500 },
    @{ keys = @(); wait = 4500 },
    @{ name = 'game-memory-top';     keys = @(); tap = $line1; wait = 1700 + 300 + 4500; settle = 300 },
    @{ name = 'game-memory-expert';  keys = @('ESC', 'ESC', 'ESC', 'S', 'F', 'A') + $twinkle; settle = 1500 },
    @{ name = 'home-again';          keys = @('ESC', 'ESC', 'ESC', 'ESC') }
  )
  if ($Walk -eq 'memory') { $steps = @(@{ name = 'home'; keys = @() }) + $memorySteps }

  foreach ($s in $steps) {
    foreach ($k in $s.keys) { Press $k }
    foreach ($k in $s.tap) { Tap $k }
    if ($s.wait) { Start-Sleep -Milliseconds $s.wait }
    if (-not $s.name) { continue }
    if ($s.settle) { Shot $s.name $s.settle } else { Shot $s.name }
  }
} finally {
  if (-not $proc.HasExited) { Stop-Process -Id $proc.Id -Force }
  Write-Host "app closed"
}
