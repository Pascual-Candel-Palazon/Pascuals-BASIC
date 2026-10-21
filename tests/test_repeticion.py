"""Repeticion de teclas segun 650 ($028A), direccion documentada (mapas de
memoria publicos, nivel A/B de docs/PROCEDENCIA.md):
- 0 (valor de arranque): repiten espacio, cursores, DEL e INST.
- 128 (bit 7): repiten todas.
- 64 (bit 6): no repite ninguna.
"""
import sys
from arnes import Maquina, etiqueta

SCN = etiqueta("KSCNKEY")
A = (1, 2)          # columna 1, fila 2
CRSR = (0, 2)       # cursor derecha/izquierda

def caso(nombre, cond):
    print(("OK  " if cond else "FALLO ") + nombre)
    return cond

def pulsaciones(valor, tecla, jiffies=60):
    t = set()
    mq = Maquina(teclas_matriz=t)
    mq.teclear(b"", 3_000_000)
    if valor is not None:
        mq.mem.write(0x028A, [valor])
    mq.mem.write(0xC6, [0])
    t.add(tecla)
    n = 0
    for _ in range(jiffies):
        mq.subrutina(SCN)
        n += mq.mem[0xC6]
        mq.mem.write(0xC6, [0])          # vaciar el bufer como un lector
    return n, mq

def main():
    ok = True
    n, mq = pulsaciones(None, A)
    ok &= caso("PEEK(650) = 0 al arrancar", mq.mem[0x028A] == 0)
    ok &= caso("650=0: la A mantenida no repite (1 pulsacion)", n == 1)
    n, _ = pulsaciones(None, CRSR)
    ok &= caso("650=0: el cursor mantenido repite (%d)" % n, n > 5)
    n, _ = pulsaciones(128, A)
    ok &= caso("650=128: la A mantenida repite (%d)" % n, n > 5)
    n, _ = pulsaciones(64, CRSR)
    ok &= caso("650=64: el cursor mantenido no repite (1 pulsacion)", n == 1)
    sys.exit(0 if ok else 1)

if __name__ == "__main__":
    main()
