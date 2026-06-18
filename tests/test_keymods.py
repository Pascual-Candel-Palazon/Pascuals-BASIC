"""Tests de modificadores de teclado: CTRL, C= (Commodore) y SHIFT+C=.

Conducen KSCNKEY directamente con conjuntos de teclas de la matriz.
Indices de matriz: (columna, bit). CTRL=(7,2), C==(7,5), LSHIFT=(1,7).
"""
import sys
from arnes import Maquina, etiqueta

SCN = etiqueta("KSCNKEY")

def caso(nombre, cond):
    print(("OK  " if cond else "FALLO ") + nombre)
    return cond

def emite(teclas_set):
    """Escanea una vez con el conjunto de teclas dado; devuelve el buffer."""
    t = set()
    mq = Maquina(teclas_matriz=t)
    for i in range(16):
        mq.mem.write(0x02B0 + i, [0])
    for a in (0xC6, 0x02AB, 0x02AF, 0x02B8, 0x02B9, 0x02BA,
              0x02E0, 0x02E1, 0x02E2):
        mq.mem.write(a, [0])
    t.update(teclas_set)
    mq.subrutina(SCN)
    n = mq.mem[0xC6]
    return bytes(mq.mem[0x0277:0x0277 + n]), mq

def main():
    if SCN is None:
        print("AVISO: falta el listado; ejecuta ./build.sh"); sys.exit(0)
    ok = True
    CTRL = (7, 2); CBM = (7, 5); LSH = (1, 7)
    # teclas numericas (col, bit)
    K = {'1': (7, 0), '2': (7, 3), '3': (1, 0), '4': (1, 3), '5': (2, 0),
         '6': (2, 3), '7': (3, 0), '8': (3, 3), '9': (4, 0), '0': (4, 3)}

    # CTRL+1..8 -> codigos de color (negro..amarillo)
    ctrl_col = {'1': 0x90, '2': 0x05, '3': 0x1C, '4': 0x9F,
                '5': 0x9C, '6': 0x1E, '7': 0x1F, '8': 0x9E}
    for k, code in ctrl_col.items():
        o, _ = emite({CTRL, K[k]})
        ok &= caso(f"CTRL+{k} -> color ${code:02X}", o == bytes([code]))

    # CTRL+9 / CTRL+0 -> inverso on/off
    o, _ = emite({CTRL, K['9']})
    ok &= caso("CTRL+9 -> RVS ON ($12)", o == b'\x12')
    o, _ = emite({CTRL, K['0']})
    ok &= caso("CTRL+0 -> RVS OFF ($92)", o == b'\x92')

    # CTRL+letra -> codigo de control PETSCII (1..26). (col, bit) de matriz.
    L = {'A': (1, 2), 'B': (3, 4), 'C': (2, 4), 'D': (2, 2), 'E': (1, 6),
         'F': (2, 5), 'G': (3, 2), 'H': (3, 5), 'I': (4, 1), 'J': (4, 2),
         'K': (4, 5), 'L': (5, 2), 'M': (4, 4), 'N': (4, 7), 'O': (4, 6),
         'P': (5, 1), 'Q': (7, 6), 'R': (2, 1), 'S': (1, 5), 'T': (2, 6),
         'U': (3, 6), 'V': (3, 7), 'W': (1, 1), 'X': (2, 7), 'Y': (3, 1),
         'Z': (1, 4)}
    for i, (letra, pos) in enumerate(sorted(L.items())):
        code = i + 1                      # A=1, B=2, ... Z=26
        o, _ = emite({CTRL, pos})
        ok &= caso(f"CTRL+{letra} -> ${code:02X}", o == bytes([code]))

    # CTRL+simbolo -> resto de codigos de control
    sym = {": (colon)": ((5, 5), 0x1B), "; (semicolon)": ((6, 2), 0x1D),
           "libra": ((6, 0), 0x1C), "= (equal)": ((6, 5), 0x1F),
           "flecha arriba": ((6, 6), 0x1E)}
    for nombre, (pos, code) in sym.items():
        o, _ = emite({CTRL, pos})
        ok &= caso(f"CTRL+{nombre} -> ${code:02X}", o == bytes([code]))

    # C=+1..8 -> colores claros (naranja..gris claro)
    cbm_col = {'1': 0x81, '2': 0x95, '3': 0x96, '4': 0x97,
               '5': 0x98, '6': 0x99, '7': 0x9A, '8': 0x9B}
    for k, code in cbm_col.items():
        o, _ = emite({CBM, K[k]})
        ok &= caso(f"C=+{k} -> color ${code:02X}", o == bytes([code]))

    # C=+simbolo -> grafico (los unicos: @ + libra)
    csym = {"+ (plus)": ((5, 0), 0xA6), "@ (at)": ((5, 6), 0xA4),
            "libra": ((6, 0), 0xA8)}
    for nombre, (pos, code) in csym.items():
        o, _ = emite({CBM, pos})
        ok &= caso(f"C=+{nombre} -> grafico ${code:02X}", o == bytes([code]))

    # SHIFT+C= conmuta el caso (toca $D018) y no emite caracter
    o, mq = emite({LSH, CBM})
    ok &= caso("SHIFT+C= no emite caracter", o == b'')
    ok &= caso("SHIFT+C= conmuta $D018 (bit 1)", (mq.mem[0xD018] & 0x02) != 0)

    sys.exit(0 if ok else 1)

if __name__ == "__main__":
    main()
