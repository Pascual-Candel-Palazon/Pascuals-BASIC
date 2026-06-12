"""Tests de los parsers BASIC de OPEN y CLOSE (fase 2a IEC).
Verifican que el BASIC parsea los argumentos y llama a las primitivas,
sin syntax error. Sin bus todavia (dispositivos 0=teclado, 3=pantalla).
"""
import sys
from arnes import Maquina

def caso(nombre, cond):
    print(("OK  " if cond else "FALLO ") + nombre)
    return cond

def main():
    ok = True

    mq = Maquina(); mq.teclear(b'OPEN5,8,15\r', 40_000_000)
    ok &= caso("OPEN5,8,15 -> LA/FA/SA correctos",
               (mq.mem[0xB8], mq.mem[0xBA], mq.mem[0xB9], mq.mem[0x98]) == (5, 8, 15, 1))

    mq = Maquina(); mq.teclear(b'OPEN1,8,2,"TEST"\r', 45_000_000)
    ok &= caso('OPEN1,8,2,"TEST" -> nombre (FNLEN=4)',
               (mq.mem[0xB7], mq.mem[0xBA], mq.mem[0xB9]) == (4, 8, 2))

    mq = Maquina(); mq.teclear(b'OPEN3\r', 40_000_000)
    ok &= caso("OPEN3 -> defaults FA=1 SA=0",
               (mq.mem[0xB8], mq.mem[0xBA], mq.mem[0xB9]) == (3, 1, 0))

    mq = Maquina(); mq.teclear(b'OPEN1,3\rCLOSE1\r', 50_000_000)
    ok &= caso("OPEN1,3 : CLOSE1 -> cierra (LDTND=0)", mq.mem[0x98] == 0)

    # ya no hay syntax error: el programa continua tras OPEN
    mq = Maquina()
    mq.teclear(b'10 OPEN1,3\r20 PRINTCHR$(81)\rRUN\r', 50_000_000)
    ok &= caso("OPEN no aborta: el PRINT siguiente se ejecuta",
               any(mq.mem[0x0400 + i] == 0x11 for i in range(1000)))

    sys.exit(0 if ok else 1)

if __name__ == "__main__":
    main()
