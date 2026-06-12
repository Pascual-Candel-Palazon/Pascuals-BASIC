"""Tests del subsistema de color: codigos CTRL+1..8 / C=+1..8 y scroll."""
import sys
from arnes import Maquina

def caso(nombre, cond):
    print(("OK  " if cond else "FALLO ") + nombre)
    return cond

def color_de_X(codigo):
    """Imprime CHR$(codigo)"X" y devuelve el conjunto de colores de las X."""
    mq = Maquina()
    mq.teclear(b'PRINTCHR$(' + str(codigo).encode() + b')"X"\r', 45_000_000)
    cols = set()
    for f in range(25):
        for c in range(40):
            if mq.mem[0x0400 + f * 40 + c] == 0x18:  # screencode 'X'
                cols.add(mq.mem[0xD800 + f * 40 + c] & 0x0F)
    return cols

def main():
    ok = True
    # codigo PETSCII -> indice de color esperado
    casos = [(144, 0), (5, 1), (28, 2), (159, 3), (156, 4),
             (30, 5), (31, 6), (158, 7), (129, 8), (149, 9),
             (150, 10), (151, 11), (152, 12), (153, 13), (154, 14), (155, 15)]
    for cod, idx in casos:
        cols = color_de_X(cod)
        ok &= caso(f"CHR$({cod}) -> color {idx}", idx in cols)

    # el scroll preserva el color: llenar con texto rojo hasta forzar scroll
    mq = Maquina()
    # programa que imprime muchas lineas rojas
    mq.teclear(b'10 PRINTCHR$(28)"ROJA"\r20 FORI=1TO30:PRINT"ROJA":NEXT\rRUN\r',
               90_000_000)
    # tras el scroll, alguna celda de 'R' (screencode $12) debe seguir en rojo (2)
    rojo_tras_scroll = False
    for f in range(25):
        for c in range(40):
            if mq.mem[0x0400 + f * 40 + c] == 0x12:  # 'R'
                if (mq.mem[0xD800 + f * 40 + c] & 0x0F) == 2:
                    rojo_tras_scroll = True
    ok &= caso("el scroll preserva el color (texto rojo)", rojo_tras_scroll)

    sys.exit(0 if ok else 1)

if __name__ == "__main__":
    main()
