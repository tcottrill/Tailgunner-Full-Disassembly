# tailgunner_emu — test emulator

`tailgunner_emu.exe` runs the real Tailgunner ROM (the MAME `tailg` set) on AAE's
CCPU core, so the original can be played and checked beside the disassembly in
[`../disasm/`](../disasm/README.md). It is the emulator twin of that listing, as
Tempest's `tempest_emu` is for its own.

- CPU: 4,980,750 Hz CCPU, 38 frames/s (131,072 cycles per frame).
- Watchdog: the frame timer (`cinevid_update`) ends each frame and counts the
  watchdog. Three frames without a CST instruction reset the CPU.

## What came from where

| file | from |
|---|---|
| `cpu/ccpu.cpp`, `cpu/ccpu.h` | AAE's CCPU core (Aaron Giles, after Zonn Moore), compiled unmodified from `cpu\`; byte-identical to AAE's `cpu_code\` |
| `cpu/cinematronics_video.cpp`, `cpu/cinematronics_video.h` | AAE's vector callback and bilevel intensity (OUT 6), from AAE's `vidhrdwr\` with its commented-out MAME leftovers (VIDEO_START / Space War blocks) removed; no code changes |
| `tg_board.cpp` | inputs, DIP shuffle, coin latch and the JMI stick comparator, copied from AAE's `drivers\cinematronics_driver.cpp`; the AAE input-port reads are replaced by board state |
| `tg_sound.cpp` | `cini_sound_control_w` and `tailg_sound`, copied from AAE's `sndhrdwr\cinematronics_sound.cpp` (the whole file needs AAE's Z80 and AY8910 boards); AAE sample numbers go through a table to the mixer |
| `tg_emu.h` | the declarations shared by the three `tg_*` files |
| `aae/aae_mame_driver.h`, `aae/deftypes.h` | stand-ins for the AAE framework, so the two `cpu\` files compile without code changes |
| `platform/` | the Windows backend (window, OpenGL beam renderer, XAudio2 mixer, raw input, DirectInput joystick, ini, log, miniz) from the Tempest project's `c_src/platform/windows`; `platform/monitor_select.*` a vendored copy of the shared monitor-selection module (keep in sync with its master) |
| `tg_main.cpp` | the host: ROM loading, frame loop and pacing, vector list to beam renderer, input mapping, ini, command line |

## Build

    cmd /c ".\build_emu.bat"

Run from `emu_src`. VS2022 x64 only; the script calls `VsDevCmd.bat` itself.
Objects go to `obj\`. The vendored and `cpu\` files compile at `/W3`, ours at
`/W4`, with no warnings.

## ROMs

Not distributed. Four 2 KB chips: `tgunner.t70 .p70 .t71 .p71`. `t` holds the
even bytes and `p` the odd; `70` is `$0000-$0FFF`, `71` is `$1000-$1FFF`.

Search order: `[main] roms=` in the ini, then `roms\tailg.zip`, `roms\tailg\`
beside the exe, then `..\roms\tailg.zip`, `..\roms\tailg\`. If nothing is
found, the program logs the failure, shows a message box (not with `--hidden`
or `--shot`) and exits. The log gives the 8K image's CRC32; the MAME set is
`553C9991`.

## Samples

Needs `hypersp sexplode slaser shield bounce thrust1 .wav` in a `tailg.zip`.

Search order: `[sound] samples=` in the ini, then `samples\tailg.zip` beside the
exe, `tailg.zip` beside the exe, `..\samples\tailg.zip`. No zip: the game runs
silent with a log warning. A missing wav silences only its own effect.

The sound latch is driven by OUT 0-2 (address), OUT 3 (data) and OUT 4
(strobe). Address bits: 0 explosion, 1 rumble, 2 laser, 3 shield, 4 bounce,
5 hyperspace; a bit is on while it is 0.

## Keys

| action | keyboard / mouse | joystick |
|---|---|---|
| aim | mouse, arrow keys | analog stick |
| fire | Ctrl, Space, LMB | button 1 |
| shield | Alt, Shift, RMB | button 2 |
| start | 1 | button 8 |
| coin | 5 or 3 | button 7 |

Also: P pause, F3 reset, F2 reset with START held for 2 s (the test pattern;
the ROM reads START once after reset), F8 mouse capture, Alt+Enter fullscreen,
Esc quit.

A higher analog value is right and up. The joystick is absolute and
self-centring; the mouse and keys leave the stick where they last put it.

## ini

`tailgunner_emu.ini` is read at start and written back with the effective
values. Sections: `[main]` (roms, vsync, starting monitor), `[dips]`,
`[vector]` (beam width, smoothing), `[input]` (mouse sensitivity, key rate,
invert_y, mouse capture), `[joystick]` (deadzone), `[sound]` (volume, samples).

DIP defaults as MAME: shield points 80, 1 coin 1 credit, and the three unknown
switches off.

## Command line

- `--hidden`: no window, no audio, no mouse capture
- `--quit-after-ms N`: stop after N ms
- `--shot FRAME FILE`: save a BMP at that frame (repeatable); implies `--hidden --turbo`
- `--turbo`: run without the 38 Hz pacing
- `--coin-at F`, `--start-at F` (0 = test pattern)
- `--fire FROM TO`, `--shield FROM TO`: hold the button for those frames
- `--stick X Y`: fix the stick (0x20 to 0xE0)

## Verification (2026-10-24, windowless)

- 15 s run: 570 frames, 37.97 fps, no watchdog resets; about 118 vector
  segments a frame.
- A coin at frame 300 gives credit 1 (RAM `$89`); START starts the game.
- Shots in `shots\`: attract, game, test pattern, stick extremes.
- Sample starts seen for laser, shield, hyperspace and rumble. Explosion and
  bounce were not reached in the scripted runs.

Not verified: live keyboard, mouse and joystick play, and the audio by ear.
