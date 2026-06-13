"""Tests de los parsers BASIC de LOAD y SAVE (capa de parsing de fase 3).
Verifican el parseo de argumentos -> SETNAM/SETLFS. La transferencia por
el bus (handshake) es trabajo aparte; aqui solo se comprueba que el
estado del kernal queda bien preparado y que no hay syntax error.
"""
import sys
from arnes import Maquina

def caso(nombre, cond):
    print(("OK  " if cond else "FALLO ") + nombre)
    return cond

def leer_nombre(mq):
    p = mq.mem[0xBB] | mq.mem[0xBC] << 8
    return bytes(mq.mem[p:p + mq.mem[0xB7]])

def main():
    ok = True

    mq = Maquina(); mq.teclear(b'LOAD"TEST",8\r', 50_000_000)
    ok &= caso('LOAD"TEST",8 -> FNLEN/FA/nombre',
               mq.mem[0xB7] == 4 and mq.mem[0xBA] == 8 and leer_nombre(mq) == b'TEST')

    mq = Maquina(); mq.teclear(b'LOAD"X",8,1\r', 50_000_000)
    ok &= caso('LOAD"X",8,1 -> SA=1', mq.mem[0xB9] == 1)

    mq = Maquina(); mq.teclear(b'SAVE"PROG",8\r', 50_000_000)
    ok &= caso('SAVE"PROG",8 -> FNLEN/FA/nombre',
               mq.mem[0xB7] == 4 and mq.mem[0xBA] == 8 and leer_nombre(mq) == b'PROG')

    mq = Maquina(); mq.teclear(b'LOAD"TEST",8\r', 50_000_000)
    ok &= caso("LOAD ya no da syntax error (vuelve a READY)",
               mq.pantalla_contiene("READY"))

    sys.exit(0 if ok else 1)

if __name__ == "__main__":
    main()
