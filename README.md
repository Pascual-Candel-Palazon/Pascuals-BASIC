# Free ROMs for the Commodore 64

Drop-in replacement ROMs (BASIC + KERNAL) for the **stock** Commodore 64
(16 KB of ROM, no extra banking), under a permissive license with an
auditable provenance chain. The spirit is that of AltirraOS / Altirra
BASIC in the Atari 8-bit world: a free alternative that boots, programs
and behaves like the real machine.

## Status

Working and verified (functionally, in VICE, against a real 1541 used as
an opaque peripheral):

- Boot: `**** PASCUAL'S BASIC ****` / `38911 BYTES FREE`
- Full interpreter (Microsoft MIT source, v1.1, 1978): floating point,
  strings, FOR/GOSUB, numbered-line programs, RUN, LIST, PEEK/POKE of
  RAM/ROM/I-O, SYS and USR
- WYSIWYG screen editor: cursor keys, DEL that reflows text, 2-row
  logical lines (80 columns), tolerant of VICE paste
- Full IRQ keyboard: matrix, shift, key repeat (space, cursors, DEL/INST)
- Blinking cursor; screen scroll
- Page-3 RAM vectors: redirectable IRQ/BRK/NMI (`$0314+`), interceptable
  I/O (`$031A-$0333`), RESTOR and VECTOR
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
  checksum, dual copy with copy-level recovery). Supports filename
  matching (`LOAD"NAME",1` scans and skips non-matching files, CBM-style
  prefix match; no name loads the first file), the PRESS PLAY ON TAPE /
  FOUND <name> / LOADING messages with a PLAY-sense wait, and RUN/STOP
  abort during load (BREAK, back to READY). Current limit: no VERIFY.
  Tape SAVE not yet implemented.
- Long BASIC error messages (C64 style): `?SYNTAX ERROR`,
  `?DIVISION BY ZERO ERROR`, `?NEXT WITHOUT FOR ERROR IN nn`, etc.
- `DEVICE NOT PRESENT` detection; reserved variables `ST` / `TI` / `TI$`

The full technical handoff (architecture, memory map, build chain,
verification method, lessons learned, roadmap) lives in
**`docs/CONTINUIDAD.md`**.

## Roadmap

- Own character generator (chargen) to replace the temporary borrowed one
- Datasette (tape) SAVE, and tape LOAD refinements: VERIFY and byte-level
  merge of the two block copies
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
./build.sh        # produces bin/basic_c64.bin and bin/kernal_c64.bin
cd tests
python3 test_humo.py
python3 test_teclado.py
python3 test_editor.py
```

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

This project never downloads or disassembles the original ROMs. Any
non-similarity verification against them should be performed by a third
party.

## License

- Own code (KERNAL, scripts, tests): MIT (`LICENSE`)
- BASIC: Microsoft's MIT (`upstream/LICENSE-microsoft`)
- `chargen.bin`: MEGA65 Open ROMs PXL font (Retrofan), **LGPL-3.0-or-later**
  (see `licenses/chargen/`)
