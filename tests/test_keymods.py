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

    # C=+1..8 -> colores claros (naranja..gris claro)
    cbm_col = {'1': 0x81, '2': 0x95, '3': 0x96, '4': 0x97,
               '5': 0x98, '6': 0x99, '7': 0x9A, '8': 0x9B}
    for k, code in cbm_col.items():
        o, _ = emite({CBM, K[k]})
        ok &= caso(f"C=+{k} -> color ${code:02X}", o == bytes([code]))

    # SHIFT+C= conmuta el caso (toca $D018) y no emite caracter
    o, mq = emite({LSH, CBM})
    ok &= caso("SHIFT+C= no emite caracter", o == b'')
    ok &= caso("SHIFT+C= conmuta $D018 (bit 1)", (mq.mem[0xD018] & 0x02) != 0)

    sys.exit(0 if ok else 1)

if __name__ == "__main__":
    main()
