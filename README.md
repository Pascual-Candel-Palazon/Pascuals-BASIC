# Free ROMs for the Commodore 64

Drop-in replacement ROMs (BASIC + KERNAL) for the **stock** Commodore 64
(16 KB of ROM, no extra banking), under a permissive license with an
auditable provenance chain. The spirit is that of AltirraOS / Altirra
BASIC in the Atari 8-bit world: a free alternative that boots, programs
and behaves like the real machine.

<img width="703" height="538" alt="Pascual's BASIC boot screen" src="https://github.com/user-attachments/assets/1f2fb7c6-2b83-4800-b334-ec5c08372bad" />

## Status

Working and verified (functionally, in VICE, against a real 1541 used as
an opaque peripheral):

- Boot screen in the C64 layout: `**** PASCUAL'S BASIC ****`, then
  `64K RAM SYSTEM  38911 BASIC BYTES FREE`, then `READY.`
- Full interpreter (Microsoft MIT source, v1.1, 1978): floating point,
  strings, FOR/GOSUB, numbered-line programs, RUN, LIST, PEEK/POKE of
  RAM/ROM/I-O, SYS and USR
- WYSIWYG screen editor: cursor keys, DEL that reflows text, 2-row
  logical lines (80 columns), tolerant of VICE paste
- Full IRQ keyboard: matrix, shift, key repeat (space, cursors, DEL/INST);
  CTRL table (CTRL+letter emits PETSCII $01-$1A, CTRL+1..8 colors,
  CTRL+9/0 reverse on/off), C= graphics (letters and symbols) and light
  colors, SHIFT+C= case switch, function keys F1-F8, and SHIFT+RUN/STOP
  (types `LOAD` + `RUN` into the keyboard buffer)
- Reverse video, upper/lower case sets, 16 text colors, cursor that
  blinks in the current color
- Blinking cursor; screen scroll
- Page-3 RAM vectors: redirectable IRQ/BRK/NMI (`$0314+`), interceptable
  I/O (`$031A-$0333`), RESTOR and VECTOR
- RUN/STOP breaks a program; RUN/STOP+RESTORE warm-starts to READY with
  the program intact
- Cartridges: CBM80 autostart (cold vector at `$8000`, NMI through
  `$8002`), the init API (CINT/IOINIT/RAMTAS) through the jump table and
  through the documented internal addresses (`$FF5B`, `$FDA3`, `$FD50`,
  `$FD15`), and the BASIC cold/warm vectors at `$A000/$A002`
- Every KERNAL jump-table entry (`$FF81-$FFF3`) is implemented, none is a
  stub (SETMSG, MEMTOP, MEMBOT, SCREEN, PLOT, IOBASE, SETTIM, RDTIM,
  SETTMO included). Not implemented: RS-232 (device 2)
- **Complete IEC serial bus** (verified byte by byte against a real 1541):
  send, receive (with EOI), serial OPEN/CLOSE/CHKIN/CHKOUT, READST,
  LOAD/SAVE/VERIFY, `LOAD"$",8` (directory) + LIST, and reading the
  command/error channel (15). BASIC program round-trip (SAVE/NEW/LOAD/RUN)
  works.
- Filename wildcards (matched by the 1541) and chained LOAD: a `LOAD`
  inside a running program re-runs the loaded program from its first
  line, preserving variables
- **Datasette (tape) LOAD** (clean-room CBM tape decode, verified end to
  end: `LOAD"",1` followed by `RUN` loads and runs a program from tape).
  Reads the CBM block format (sync countdown, per-byte parity, XOR
  checksum, dual copy with byte-level merge that recovers a block even
  when each copy has read errors in different bytes). Supports filename
  matching (`LOAD"NAME",1` scans and skips non-matching files, CBM-style
  prefix match; no name loads the first file), the PRESS PLAY ON TAPE /
  FOUND <name> / LOADING messages with a PLAY-sense wait, RUN/STOP abort
  during load (BREAK, back to READY), and VERIFY (`VERIFY"NAME",1` compares
  the tape against memory and reports `?VERIFY ERROR` on a mismatch). If the
  tape stops mid-read (short leaders, an unexpected end, or a file that is not
  on the tape), the loader times out and returns instead of hanging.
  Adaptive speed correction (the short/medium/long pulse thresholds are
  recentred from the leader's measured short pulse) tolerates roughly -10%
  to +45% tape-speed deviation; the encoding matches the real CBM format and
  nominal PAL and NTSC tapes load. Tape SAVE is implemented and wired into the
  BASIC `SAVE"NAME",1` command: it writes a header block plus a data block (the
  CBM two-copy format), with motor control, the "PRESS RECORD & PLAY ON TAPE"
  prompt and `SAVING` message, and it disables the jiffy IRQ during the write so
  the timing stays clean. Verified end to end by typing `SAVE"",1` on one
  machine and `LOAD"",1` on another: the program survives the round trip byte
  for byte. Note: the tape checks were run with a py65 harness (CIA Timer B
  and FLAG model) that is not yet in this repository; see
  `docs/CONTINUIDAD.md`, section "Pendiente de recuperar".
- Long BASIC error messages (C64 style): `?SYNTAX ERROR`,
  `?DIVISION BY ZERO ERROR`, `?NEXT WITHOUT FOR ERROR IN nn`, etc.
- `DEVICE NOT PRESENT` detection; reserved variables `ST` / `TI` / `TI$`

The full technical notes (architecture, memory map, build chain,
verification method, lessons learned, roadmap) lives in
**`docs/CONTINUIDAD.md`**.

## Roadmap

- Own character generator (chargen) to replace the temporary borrowed one
- Linear string garbage collector: the BASIC inherits Microsoft's
  original quadratic GC (long pauses with thousands of strings). To be
  improved using the published algorithm (back-pointer technique),
  **never** from disassembled Commodore ROMs (BASIC 3.5/7.0); see
  `docs/PROCEDENCIA.md`. Prerequisite: a GC stress-test suite against the
  current one as a baseline (integrity + timing).
- Future sister project: a free 1541 drive ROM (same clean-room method;
  the GCR format and IEC protocol are publicly specified). Meanwhile,
  VICE `-iecdevice8` for emulation and SD2IEC (already-free firmware) for
  real hardware.

## Usage

```
x64sc -kernal bin/kernal_c64.bin -basic bin/basic_c64.bin -chargen bin/chargen.bin
```

## Building

Requirements: `python3`, `cc65`, and `py65` for the tests
(`pip install py65`).

```
./build.sh        # builds into build/ and copies the ROMs to bin/
cd tests
./run_all.sh      # full suite: 15 tests (slow under py65, several minutes)
python3 test_humo.py   # or any single test_*.py
```

The tests read `build/`, so run `./build.sh` before testing. Some tests
(`test_color`, `test_editor`, `test_iec_fase2a`) are sensitive to the py65
cycle budget: if one fails inside a batch, run it alone before assuming a
regression.

## Architecture and provenance

- **BASIC** (`$A000-$BFFF`, with its tail at `$E000`): mechanically
  derived from Microsoft's official MIT source (`upstream/m6502.asm`, the
  microsoft/BASIC-M6502 repo) via `src/flatten.py` (which resolves the
  MACRO-10 conditionals with REALIO=3, the Commodore target) and
  `src/translate.py` (MACRO-10 -> ca65). Every C64 adaptation is annotated
  `[C64]` in the generated source: memory map, 6510 port, RAM top, custom
  SYS/USR, removed anti-PEEK lock, long error messages.
- **KERNAL** (`$E200+`): written from scratch for this project, from the
  documented public interface and observable behavior. Strict policy in
  `docs/PROCEDENCIA.md`.
- **CHARGEN** (`bin/chargen.bin`): the PXL font from MEGA65 Open ROMs
  (created by Retrofan), included verbatim under **LGPL-3.0-or-later**.
  This is the only non-MIT component; details and full license text in
  `licenses/chargen/`. Temporary bridge, pending replacement by an own set.

Development never consults disassembled original ROMs. The original
ROMs that ship with VICE are only used as an opaque emulated peripheral
(the 1541 drive, to test the IEC bus) and by a blind comparator that
reports metrics without exposing their content (`tools/comparador_ciego.py`,
results in `docs/AUDITORIA_SIMILITUD.md`). The formal non-similarity
verification is left to an independent third party.

## License

- Own code (KERNAL, scripts, tests): MIT (`LICENSE`)
- BASIC: Microsoft's MIT (`upstream/LICENSE-microsoft`)
- `chargen.bin`: MEGA65 Open ROMs PXL font (Retrofan), **LGPL-3.0-or-later**
  (see `licenses/chargen/`)
