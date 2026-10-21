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
- Internal KERNAL entry points that games and cartridges call directly
  are at their documented addresses: main IRQ `$EA31` and IRQ exit
  `$EA81`, IRQ entry `$FF48`, NMI entry `$FE43` (only the CPU frame is on
  the stack when a user `$0318` handler runs) and default NMI `$FE47`, BRK
  warm start `$FE66`, common exit `$FEBC`, RESET `$FCE2` (`SYS 64738`
  works), RESTOR/RAMTAS/IOINIT/CINT at `$FD15`/`$FD50`/`$FDA3`/`$FF5B`
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
- **Datasette (tape): LOAD, SAVE and VERIFY in the real CBM format.**
  Checked in VICE against a stock C64 used as a black box: this KERNAL
  loads tapes recorded by a real C64, and a real C64 loads tapes recorded
  by this KERNAL (`docs/CONTINUIDAD.md`, section 15).
  - Format: S/M/L pulses of 384/528/688 cycles (full square-wave cycles),
    sync countdown, per-byte parity, XOR checksum, two copies per block.
    The header block is 192 bytes, with type 1 (relocatable, `SAVE"X",1`)
    or 3 (absolute, `SAVE"X",1,1`). Leaders are $6A00 pulses before the
    header and $1500 before the data.
  - The whole 192-byte header is kept in the tape buffer at 828-1019
    ($033C), as on the C64: type at 828, start/end at 829-832, name from
    833, and any loader code a tape stores in the rest of the header.
    178/179 point to the buffer.
  - LOAD: filename matching (CBM-style prefix; no name loads the first
    program). Skips data files and stops at an end-of-tape header (type 5).
    A type 3 file always loads at its own address.
  - Merge: the two copies are merged byte by byte, so a block survives
    read errors in different bytes of each copy.
  - Speed: the loader recalibrates from each leader. In the test harness it
    reads tapes from 30% slow to 40% fast with +-12 cycles of pulse noise.
  - Messages: PRESS PLAY / PRESS RECORD & PLAY, SEARCHING, FOUND, LOADING,
    SAVING, VERIFYING and OK. The screen is blanked while the tape runs, as
    on the C64.
  - Also: RUN/STOP abort, and a timeout instead of a hang when the tape ends
    early.
  - Tests: `tests/test_cinta.py`, with a cycle-level CIA1 model
    (`tests/cinta.py`) and an independent Python model of the tape format
    (`tests/tapgen.py`).
- Screen editor with C64 quote mode and insert mode: cursor and color
  keys typed inside quotes are stored in the line and shown reversed, and
  LIST shows them instead of executing them.
- Documented editor and keyboard locations kept up to date for programs
  that PEEK/POKE them. The current key is at 197/203 and the
  SHIFT/C=/CTRL flags at 653. The cursor row is at 214, and the reverse,
  quote and insert flags are at 199/212/216. 648 is the screen page the
  editor writes to and reads from (change it together with $D018 to use a
  second screen), 650 selects which keys repeat (0 = cursor keys, space,
  DEL and INST; 128 = all; 64 = none), 678 is the PAL/NTSC flag, and 657
  can lock SHIFT+C=. The user areas 251-254 and 679-767 are left
  untouched.
- BASIC zero page at the documented C64 addresses: start of program at
  43/44, end at 45/46, top of memory at 55/56, CHRGET at $73 and TXTPTR
  at 122/123, so `POKE 43/44` and CHRGET wedges work. The ADRAY1/ADRAY2
  conversion vectors are at 3/4 and 5/6. POS, TAB and the comma follow the
  cursor column (211).
- Internal KERNAL entry points that many programs call directly: clear
  screen (58692/$E544), set the line pointer from 214/211 (58732/$E56C),
  print to the screen (59158/$E716) and clear a screen line (59903/$E9FF).
  BASIC output matches the C64: LIST without a leading space, no blank line
  after each typed line, and CLR keeps the text color.
- Long BASIC error messages (C64 style, two spaces before ERROR): `?SYNTAX  ERROR`,
  `?DIVISION BY ZERO  ERROR`, `?NEXT WITHOUT FOR  ERROR IN nn`, etc.
- `DEVICE NOT PRESENT` detection; reserved variables `ST` / `TI` / `TI$`

The full technical handoff (architecture, memory map, build chain,
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
./run_all.sh      # full suite: 18 tests (slow under py65, about 15 minutes)
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
