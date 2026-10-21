"""Pagina cero del BASIC en las direcciones documentadas del C64 (mapas de
memoria publicos, nivel A/B de docs/PROCEDENCIA.md):

- 43/44 TXTTAB, 45/46 VARTAB, 47/48 ARYTAB, 49/50 STREND, 51/52 FRETOP,
  55/56 MEMSIZ, 57/58 CURLIN, 122/123 TXTPTR, $73 CHRGET.
- 3/4 ADRAY1 (FAC -> entero en A/Y) y 5/6 ADRAY2 (entero en A/Y -> FAC).
- POS(0), TAB y la coma usan la columna del cursor (211, $D3).
"""
import sys
from arnes import Maquina

def caso(nombre, cond):
    print(("OK  " if cond else "FALLO ") + nombre)
    return cond

def lineas(mq):
    return [f.rstrip() for f in mq.pantalla()]

def resultado(mq):
    """Ultima linea no vacia antes del READY. final."""
    v = [l for l in lineas(mq) if l.strip()]
    i = max((k for k, l in enumerate(v) if l == "READY."), default=0)
    return v[i - 1] if i > 0 else None

def main():
    ok = True

    mq = Maquina()
    mq.teclear(b"10 A=1:B$=\"X\"+\"Y\"\rRUN\r", 60_000_000)
    mq.teclear(b"PRINTPEEK(43)+256*PEEK(44);PEEK(55)+256*PEEK(56)\r", 40_000_000)
    ok &= caso("PEEK(43/44) = 2049 y PEEK(55/56) = 40960",
               (resultado(mq) or "").split() == ["2049", "40960"])
    m = mq.mem
    w = lambda a: m[a] | m[a + 1] << 8
    ok &= caso("TXTTAB en $2B = $0801", w(0x2B) == 0x0801)
    ok &= caso("VARTAB en $2D = fin del programa (tras la linea 10)",
               0x0801 < w(0x2D) < 0x0830 and m[w(0x2D) - 1] == 0 and m[w(0x2D) - 2] == 0)
    ok &= caso("ARYTAB ($2F) = STREND ($31) = VARTAB + 2 variables",
               w(0x2F) == w(0x31) == w(0x2D) + 14)
    ok &= caso("FRETOP ($33) baja por la cadena \"XY\"", w(0x33) == 0xA000 - 2)
    ok &= caso("MEMSIZ en $37 = $A000", w(0x37) == 0xA000)
    ok &= caso("CHRGET en $73 (INC $7A)", list(m[0x73:0x75]) == [0xE6, 0x7A])
    ok &= caso("CURLIN+1 ($3A) = $FF en modo directo", m[0x3A] == 0xFF)

    # POKE 44 / NEW: mover el inicio del BASIC como en el C64
    mq = Maquina()
    mq.teclear(b"POKE44,16:POKE16*256,0:NEW\r", 60_000_000)
    mq.teclear(b"10 PRINT\"HOLA\"\rRUN\r", 60_000_000)
    v = lineas(mq)
    ok &= caso("POKE44,16:NEW mueve el programa a $1001",
               "HOLA" in v and mq.mem[0x1001] != 0 and
               (mq.mem[0x2B] | mq.mem[0x2C] << 8) == 0x1001)

    # ADRAY1/ADRAY2 desde codigo maquina: $C000 JSR ($0003) con FAC=-1234,
    # guarda A/Y; luego JSR ($0005) con A/Y=$1234 y vuelve al BASIC
    mq = Maquina()
    mq.mem.write(0xC000, [
        0x20, 0x0D, 0xC0,          # JSR $C00D (JMP ($0003))
        0x8D, 0x80, 0xC0,          # STA $C080
        0x8C, 0x81, 0xC0,          # STY $C081
        0x4C, 0x10, 0xC0,          # JMP $C010
        0x00,
        0x6C, 0x03, 0x00,          # $C00D: JMP ($0003)
        0xA9, 0x12, 0xA0, 0x34,    # $C010: LDA #$12 / LDY #$34
        0x6C, 0x05, 0x00])         # JMP ($0005) -> GIVAYF -> RTS a USR
    mq.teclear(b"POKE785,0:POKE786,192:PRINTUSR(-1234)\r", 80_000_000)
    r = (-1234) & 0xFFFF
    ok &= caso("ADRAY1: FAC=-1234 -> A/Y = $FB/$2E",
               mq.mem[0xC080] == r >> 8 and mq.mem[0xC081] == r & 0xFF)
    ok &= caso("ADRAY2: A/Y=$1234 -> FAC = 4660 (USR devuelve 4660)",
               (resultado(mq) or "").strip() == "4660")

    # Posicion de impresion
    mq = Maquina()
    mq.teclear(b"PRINT\"AB\";POS(0):PRINT\"X\",\"Y\":PRINT\"AB\";TAB(5)\"Z\"\r",
               80_000_000)
    v = lineas(mq)
    i = max(k for k, l in enumerate(v) if l.startswith("PRINT\"AB\""))
    i += 1
    while not v[i].startswith("AB"):
        i += 1
    ok &= caso("POS(0) tras \"AB\" = 2", v[i] == "AB 2")
    ok &= caso("coma: Y en la columna 10", v[i + 1] == "X" + " " * 9 + "Y")
    ok &= caso("TAB(5) tras \"AB\": Z en la columna 5", v[i + 2] == "AB   Z")

    sys.exit(0 if ok else 1)

if __name__ == "__main__":
    main()
