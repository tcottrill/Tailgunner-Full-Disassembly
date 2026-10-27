# Tailgunner (Cinematronics, 1979) - annotated disassembly

A byte-exact, labelled listing of the Tailgunner program ROM (MAME set `tailg`) for the
**Cinematronics CCPU**, in the format of the
[Tempest](https://github.com/tcottrill/Tempest-Full-Disassembly-and-C-Port) and Space Duel
disassemblies: an address label on every line, routine headers, a defines file, and a
read-back verifier.

No source code for Tailgunner is known to survive, so unlike Tempest there was no source to
re-assemble. Code and data were separated by **running the ROM** on the AAE emulator's CCPU
core (`../emu_src/cpu/ccpu.cpp`, compiled unmodified into `trace/tgtrace.exe`) and following
its jumps. Every name and description is this disassembly's own, written by reading the code
and checked where the code alone does not show it: RAM snapshots taken at game events
(`trace/ramdiff.py`), per-word value statistics over all the traces (`trace/ramreport.py`),
and frames captured from the running ROM.

[`shapes_preview.html`](shapes_preview.html) draws every picture the ROM keeps in a table:
the four fighter models, the 3D title letters, the test pattern, the crosshair, the shield
and the vector font.

## Regenerate and verify

```
cd disasm
python gen_from_roms.py                    # ROMs from ../roms (zip or loose files)
python gen_from_roms.py ..\roms\tailg.zip --traces
```

The four chips are found by CRC32. The steps:

1. `romset.py`: interleave the chips into `build/tailg_8k.bin` (the t chips hold the even
   bytes and the p chips the odd ones; t70/p70 = bank 0, t71/p71 = bank 1)
2. `trace/run_traces.py`: build `tgtrace.exe` (Visual Studio 2022) if needed and run every
   script in `trace/scripts/`, writing `build/trace_*.json`. This runs when the traces are
   missing or with `--traces`
3. `analyze.py` -> `build/analysis.json`: code, data, P register and accumulator per
   instruction
4. `emit.py` -> `tailgunner_program_rom.asm`
5. `emit_defines.py` -> `tailgunner_defines.asm`
6. `verify.py`: must print `MISMATCHES : 0` and `PAGE ERRORS : 0`
7. `emit_shapes.py` -> `shapes_preview.html`

Current result: 8192 / 8192 bytes re-encoded, 0 mismatches, 0 RAM page errors.

| | |
|---|---|
| instructions | **5,276** (6,002 bytes): 5,032 executed in the traces, 244 found by following jumps |
| data | 2,190 bytes, of which 935 are development-system leftovers (below) |
| routine headers | **63**, all described |
| RAM words named | **256** of 256 (about 45 are written only by the power-on clear) |
| line comments | **434** hand-written notes and **20** comment blocks, beside the mechanical notes on every jump, indirect access, call and sound command |
| traced frames | 117,791 over 12 scripts (attract, coin-up, games with an aim cheat, DIP settings, shield, laser, test mode) |

## Files

| File | What |
|---|---|
| `tailgunner_program_rom.asm` | program ROM `$0000-$1FFF` (generated) |
| `tailgunner_defines.asm` | memory map, inputs, switches, outputs, sound bits, RAM words (generated) |
| `shapes_preview.html` | decoded models, letters, font, crosshair, shield, strings (generated) |
| `gen_from_roms.py` | driver (above) |
| `romset.py` | finds the chips, builds the 8K image |
| `ccpu.py` | CCPU instruction set: decode and encode |
| `analyze.py` | code / data separation from the traces plus a static walk |
| `names.py` | routine, table and RAM names and descriptions, and each routine's call parameters |
| `comments.py` | the hand-written line notes and comment blocks |
| `tables.py` | decoders for the data tables, shared by `emit.py` and `emit_shapes.py` |
| `hwinfo.py` | board I/O: inputs, DIP switch wiring, outputs, sound register |
| `emit.py`, `emit_defines.py`, `emit_shapes.py` | generators |
| `verify.py` | independent read-back: re-encodes every line and compares with the ROM |
| `trace/tgtrace.cpp`, `build_trace.bat` | the tracing harness around the unmodified `../emu_src/cpu/ccpu.cpp` |
| `trace/run_traces.py` | builds the harness and runs every script |
| `trace/scripts/*.txt` | input scripts (coin, start, stick, fire, shield, DIP byte, RAM snapshots, frame captures, the `autoaim` cheat that makes shots hit) |
| `trace/ramdiff.py`, `trace/ramreport.py` | RAM snapshot diffs; per-word writes, values and users over all traces |
| `trace/svg2png.py`, `trace/notecheck.py` | frame contact sheets; every hand note printed on the line it lands on |

## The CCPU and this syntax

The CCPU is a TTL processor with 12-bit accumulators A and B, 8-bit opcodes, 8K of program
ROM in two 4K banks, and 256 words of 12-bit RAM in 16 pages selected by the P register.
Semantics are those of `ccpu.cpp` (Aaron Giles, after Zonn Moore's documentation).

| syntax | opcode | effect |
|---|---|---|
| `LDAI #$300` | `0n` | acc = n << 8 (only the high nibble can be loaded) |
| `A4I #$n` / `A8I #$nn` | `2n` / `20 nn` | acc += n (also a compare: the jumps test acc against n) |
| `S4I` / `S8I` | `3n` / `30 nn` | acc -= n |
| `LPAI label` | `4j nn` | J = 12-bit target in the bank of the jump that uses it |
| `JMP`, `JEQ`, `JLT`, `JCZ`, `JOS`, `JVN`, `JMI` | `58`-`5E` | jump to J (conditionally) |
| `T4K` | `50` | jump to J in the bank P selects (P=1 bank 0, P=2 bank 1) |
| `JMIB` ... `JOSB`, `SSA` | `51`-`57` | as above / no-op, and the next instruction uses B |
| `LDA STA ADD SUB TST WS name` | `An Dn 6n 7n Bn Cn` | RAM word n of page P |
| `SETP $p` | `8p` | P = p |
| `INP name` / `OUT name` | `1n` / `9n` | read / write one I/O bit |
| `LDAP STAP ADDP SUBP ANDP` | `EA E6 E7 E8 E9` | RAM[I] |
| `LKP` | `E2 5F` | acc = ROM byte at (bank) + acc; the CPU skips the byte after it ($5F) |
| `SHR SHL ASR SHRB SHLB MUL NV` | `EB`-`EF`, `E3`, `E4` | shifts, multiply step, normalise |
| `IV` / `DV` | `F0` / `E0` | move the beam to A,B / draw a vector to A,B |
| `FRM` / `CST` | `E5` / `F7` | wait for the frame / clear the watchdog (and ADDP) |

Opcodes `$E0-$FF` exist in two rows; where both do the same thing the F-row form gets a
trailing `F` (`LKPF`, `MULF`, ...).

## Conventions (program listing)

- Every code and data line starts with its address label `Lxxxx:`. Named labels sit on
  their own line above it.
- `B,` before an operand (or `B` alone) marks an instruction that runs on the B
  accumulator, as the trace or the preceding B-select jump shows. The encoding is the
  same either way.
- RAM operands are full addresses (`STA SCORE_HI` = word `$6A`) wherever the page is
  known; the opcode keeps only the low nibble. `P:$x` is word x of a page that differs
  between calls (the comment gives the pages seen). `verify.py` checks every full address
  against the last `SETP` on its straight-line path.
- `LPAI` operands are labels in the bank the jump goes to (`T4K to bank 1` noted).
- Mechanical comments, from a simulation of A, B, I and the compare flags along each
  straight-line run (restarted wherever something jumps in): every conditional jump's
  condition and target (`if FTRS_LEFT = 0 -> L00DF`, `count up to 0 (a delay of $12
  loops)`); the RAM word each `LDAP` / `STAP` / `ADDP` ... touches (`store to SHOT`); each
  stored return address and each store to a routine's parameter at a call (`PRINT: x`);
  each sound command at its `OUT OUT_SND_DATA` line (`sound: laser on`); the intensity,
  stick axis or coin-latch level an `OUT` sets; `J from RAM -> ...` where an indirect jump
  went in the traces; the table range each `LKP` read.
- Hand-written comments (`comments.py`) come first on a line and say what the code is
  for; comment blocks above a line describe a whole step.
- Data tables are printed one record to a line with the record decoded: model headers,
  vertices (`vertex 0: x -20 y +2 z +20`) and edges (`edges 0-1 1-2 ...`), crosshair and
  shield points, font grid and strokes, strings, formation steps, sine entries.
- Lines never executed in the traces but reached by following jumps are introduced by
  `;[static]`. Data regions say who read them, or `not read in the traces`.
- Routine headers mark entries reached by a call, a jump through RAM, or a bank change.

## What the program does

One pass per frame from `MAINLOOP` (bank 0): sounds, fighters that got past (`PASSCHK`),
the star field, the wave logic (`ENDPASS`), fighters flying away, the shield, the stick
(read by successive approximation through `JMI`), the crosshair and fire button, the three
fighters (`FTRUPDATE`: steering toward the formation point, motion along two heading angles,
a shift-and-subtract perspective divide, the hit test) interleaved with the two laser beams.
Then `T4K` to bank 1 for the 3D models (`DRAWMODEL` / `DRAWMODEL3D`), the score lines
(`PRINT`, a stroke font), the next formation step, coins and credits, and the game-over,
credit and attract screens, which jump back to `MAINLOOP`. Each fighter has a 16-word record
in RAM page 3, 4 or 5 (`FTRn_*`).

- The game ends when `FTRS_LEFT` (10 at the start) reaches 0: each fighter that gets
  nearer than z = `$115` unhit takes one away. Shields only delay that.
- A wave cleared by shooting starts the next at once; a fighter getting past sets off the
  hyperspace jump first (`WAVE_TIMER`, the stars rushing in).
- `NEWWAVE` picks the model (with its points: 7, 11, 17 or 23), the speed (from the score)
  and the formation pattern from the pseudo-random generator.
- A shot lasts 9 frames; only the last 3 can hit; the third hit of a wave scores twice.
- An exploding fighter (`FTRn_STATE` 3 to `$18`) is its model with each edge moved out
  from the centre in proportion to the count.

Power-on with START held runs `TESTMODE`, a fixed test pattern.

## Development-system leftovers

`$0924-$0BFF`, `$0F6D-$0FFF` and `$1FC8-$1FFF` are not Tailgunner: they hold 8080/Z80
machine code (`CD xx xx` calls, `C3` jumps) and the text `NEXT  PC`, presumably left in the
EPROMs by the development system. Nothing reads them.

## Credits

- **Tailgunner**: Cinematronics, 1979.
- CCPU core `ccpu.cpp`: Aaron Giles (MAME), with thanks to Zonn Moore for his
  documentation; adapted in the AAE emulator (`emu_src/cpu/` here). Hardware notes from
  the AAE Cinematronics driver (after MAME's `cinemat.cpp`) and its Tailgunner sound
  handler: `drivers/cinematronics_driver.cpp` and `sndhrdwr/cinematronics_sound.cpp` in
  the [AAE](https://github.com/tcottrill/AAE) source.
- Listing format and tooling pattern: the Tempest and Space Duel disassembly projects.
