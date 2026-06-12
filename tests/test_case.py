"""Test: en modo minusculas, shift+letra produce la MAYUSCULA.

PETSCII autentico: la tecla sin shift emite $41-$5A (minuscula en modo
texto); con shift emite $C1-$DA (mayuscula en modo texto, grafico en
modo mayusculas). La relectura de pantalla preserva la distincion.
"""
import sys
from arnes import Maquina, etiqueta

SCN = etiqueta("KSCNKEY")

def caso(nombre, cond):
    print(("OK  " if cond else "FALLO ") + nombre)
    return cond

def emite(teclas):
    t = set(); mq = Maquina(teclas_matriz=t)
    for i in range(16):
        mq.mem.write(0x02B0 + i, [0])
    for a in (0xC6, 0x02AB, 0x02E0, 0x02E1, 0x02E2):
        mq.mem.write(a, [0])
    t.update(teclas); mq.subrutina(SCN)
    n = mq.mem[0xC6]
    return bytes(mq.mem[0x0277:0x0277 + n])

def main():
    ok = True
    if SCN is not None:
        LSH = (1, 7)
        ok &= caso("shift+A emite $C1", emite({LSH, (1, 2)}) == b'\xC1')
        ok &= caso("shift+Z emite $DA", emite({LSH, (1, 4)}) == b'\xDA')
        ok &= caso("A sin shift emite $41", emite({(1, 2)}) == b'A')

    # en modo minusculas, $C1 renderiza como sc $41 (mayuscula del set)
    mq = Maquina()
    mq.teclear(b'PRINTCHR$(14);\r' + bytes([0xC1]) + b'B\r', 60_000_000)
    ok &= caso("modo minusc: shift+letra -> sc $41 en pantalla",
               any(mq.mem[0x0400 + i] == 0x41 for i in range(1000)))
    ok &= caso("modo minusc activo ($D018=$17)", mq.mem[0xD018] == 0x17)

    sys.exit(0 if ok else 1)

if __name__ == "__main__":
    main()
