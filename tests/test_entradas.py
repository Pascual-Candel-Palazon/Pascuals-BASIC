"""Entradas internas del KERNAL que muchos programas llaman directamente
(direcciones y uso de los mapas de memoria publicos, nivel A/B de
docs/PROCEDENCIA.md):

- 58692 ($E544): borrar la pantalla y cursor a (0,0).
- 58732 ($E56C): rehacer el puntero de linea desde 214 (fila) y 211
  (columna): POKE214,F:POKE211,C:SYS58732 mueve el cursor.
- 59158 ($E716): escribir A en la pantalla, sin mirar el dispositivo de
  salida.
- 59903 ($E9FF): borrar la fila X.
Ademas: CLR (CHR$(147)) conserva el color de texto (646) y pinta la RAM
de color con el, como el C64 (antes volvia a azul claro).
"""
import sys
from arnes import Maquina

def caso(nombre, cond):
    print(("OK  " if cond else "FALLO ") + nombre)
    return cond

SCR, COL = 0x0400, 0xD800

def main():
    ok = True

    # CLR conserva el color
    mq = Maquina()
    mq.teclear(b"PRINTCHR$(5)CHR$(147);\r", 40_000_000)
    ok &= caso("CHR$(147) tras CHR$(5): 646 sigue en 1 (blanco)",
               mq.mem[0x0286] == 1)
    ok &= caso("CHR$(147): RAM de color al color de texto (1)",
               all(mq.mem[COL + i] & 15 == 1 for i in range(0, 1000, 37)))

    # $E544
    mq = Maquina()
    mq.teclear(b"", 3_000_000)
    mq.mem.write(SCR, [1] * 1000)
    mq.mem.write(0x0286, [7])
    mq.mem.write(0xD3, [12]); mq.mem.write(0xD6, [9])
    mq.subrutina(0xE544, 200_000)
    ok &= caso("$E544: pantalla en blanco",
               all(mq.mem[SCR + i] == 0x20 for i in range(1000)))
    ok &= caso("$E544: color = 646 (7) en toda la pantalla",
               all(mq.mem[COL + i] & 15 == 7 for i in range(1000)))
    ok &= caso("$E544: cursor en (0,0) y puntero de linea en $0400",
               mq.mem[0xD3] == 0 and mq.mem[0xD6] == 0 and
               mq.mem[0xD1] | mq.mem[0xD2] << 8 == SCR)

    # $E56C desde BASIC
    mq = Maquina()
    mq.teclear(b"PRINTCHR$(147);:POKE214,10:POKE211,5:SYS58732:PRINT\"X\";\r",
               60_000_000)
    ok &= caso("POKE214,10:POKE211,5:SYS58732: X en fila 10, columna 5",
               mq.mem[SCR + 10 * 40 + 5] == 0x18)

    # $E716 con la salida por defecto en un dispositivo serie
    mq = Maquina()
    mq.teclear(b"PRINTCHR$(147);\r", 30_000_000)
    mq.mem.write(0x9A, [4])
    for c in (0x48, 0x4F, 0x4C, 0x41):              # "HOLA" en PETSCII
        mq.mpu.a = c
        mq.subrutina(0xE716)
    mq.mem.write(0x9A, [3])
    fila = bytes(mq.mem[SCR:SCR + 1000])
    ok &= caso("$E716 escribe en pantalla aunque 154 sea 4 (HOLA)",
               b"\x08\x0f\x0c\x01" in fila)

    # $E9FF
    mq = Maquina()
    mq.teclear(b"", 3_000_000)
    mq.mem.write(SCR, [1] * 1000)
    mq.mem.write(COL, [0] * 1000)
    mq.mem.write(0x0286, [5])
    mq.mpu.x = 5
    mq.subrutina(0xE9FF)
    f5 = range(SCR + 200, SCR + 240)
    ok &= caso("$E9FF con X=5: fila 5 en blanco",
               all(mq.mem[a] == 0x20 for a in f5))
    ok &= caso("$E9FF: color de la fila 5 = 646",
               all(mq.mem[a - SCR + COL] & 15 == 5 for a in f5))
    ok &= caso("$E9FF: filas 4 y 6 intactas",
               mq.mem[SCR + 199] == 1 and mq.mem[SCR + 240] == 1)

    sys.exit(0 if ok else 1)

if __name__ == "__main__":
    main()
