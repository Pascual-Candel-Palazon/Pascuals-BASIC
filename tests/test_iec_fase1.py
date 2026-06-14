"""Tests del andamiaje de E/S (fase 1 IEC): gestion de estado de
ficheros logicos. Sin bus todavia - solo SETNAM/SETLFS/OPEN/CLOSE/
CHKIN/CHKOUT y sus tablas.
"""
import sys
from arnes import Maquina

def caso(nombre, cond):
    print(("OK  " if cond else "FALLO ") + nombre)
    return cond

def main():
    ok = True
    mq = Maquina(); mq.teclear(b"", 3_000_000); m = mq.mpu

    def call(addr, a=0, x=0, y=0):
        m.a, m.x, m.y = a, x, y
        m.p &= ~0x01
        mq.subrutina(addr, 40000)
        return m.a, (m.p & 1)

    # SETNAM: longitud y puntero del nombre
    call(0xFFBD, a=4, x=0x00, y=0xC0)
    ok &= caso("SETNAM guarda longitud y puntero",
               mq.mem[0xB7] == 4 and (mq.mem[0xBB] | mq.mem[0xBC] << 8) == 0xC000)

    # SETLFS: fichero logico, dispositivo, secundaria
    call(0xFFBA, a=2, x=8, y=1)
    ok &= caso("SETLFS guarda LA/FA/SA",
               (mq.mem[0xB8], mq.mem[0xBA], mq.mem[0xB9]) == (2, 8, 1))

    # OPEN registra en las tablas
    a, c = call(0xFFC0)
    ok &= caso("OPEN registra (LDTND=1, LAT[0]=2)",
               mq.mem[0x98] == 1 and c == 0 and mq.mem[0x0259] == 2)

    # OPEN duplicado -> error 2
    a, c = call(0xFFC0)
    ok &= caso("OPEN duplicado da error 2", c == 1 and a == 2)

    # fichero logico 0 no permitido -> error 6
    call(0xFFBA, a=0, x=8, y=0)
    a, c = call(0xFFC0)
    ok &= caso("OPEN fichero 0 da error 6", c == 1 and a == 6)

    # segundo fichero
    call(0xFFBA, a=5, x=8, y=0); call(0xFFC0)
    ok &= caso("segundo OPEN (LDTND=2)", mq.mem[0x98] == 2)

    # CHKIN / CHKOUT fijan el dispositivo del canal
    call(0xFFC6, x=5)
    ok &= caso("CHKIN fija DFLTN=8", mq.mem[0x99] == 8)
    call(0xFFC9, x=2)
    ok &= caso("CHKOUT fija DFLTO=8", mq.mem[0x9A] == 8)

    # CHKIN de fichero no abierto -> error 3
    a, c = call(0xFFC6, x=7)
    ok &= caso("CHKIN fichero no abierto da error 3", c == 1 and a == 3)

    # Compactacion de tablas con dispositivos NO-serie (dev 0): aisla la
    # logica de tablas del bus. El CLOSE de canal serie hace E/S por el bus
    # y se valida con true-drive en VICE, no en py65 (que no modela el bus).
    call(0xFFE7)                                   # reset de tablas (sin E/S de bus)
    call(0xFFBD, a=0, x=0, y=0)                    # SETNAM vacio
    call(0xFFBA, a=3, x=0, y=0); call(0xFFC0)      # file 3 dev0 -> slot 0
    call(0xFFBA, a=4, x=0, y=0); call(0xFFC0)      # file 4 dev0 -> slot 1
    call(0xFFBA, a=7, x=0, y=0); call(0xFFC0)      # file 7 dev0 -> slot 2
    ok &= caso("tres OPEN no-serie (LDTND=3)", mq.mem[0x98] == 3)
    call(0xFFC3, a=3)                              # CLOSE slot 0 -> desplaza 4,7
    ok &= caso("CLOSE compacta (LDTND=2, LAT[0]=4, LAT[1]=7)",
               mq.mem[0x98] == 2 and mq.mem[0x0259] == 4 and mq.mem[0x025A] == 7)

    # CLALL cierra todo
    call(0xFFE7)
    ok &= caso("CLALL cierra todo (LDTND=0)", mq.mem[0x98] == 0)

    sys.exit(0 if ok else 1)

if __name__ == "__main__":
    main()
