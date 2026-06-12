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


    # PRINT# / CMD / GET# (handlers del MS, ahora que CHKIN/CHKOUT/CLRCHN
    # funcionan tras la fase 1)
    mq = Maquina()
    mq.teclear(b'10 OPEN1,3\r20 PRINT#1,"HOLA"\r30 CLOSE1\rRUN\r', 60_000_000)
    ok &= caso("PRINT#1 a pantalla imprime", mq.pantalla_contiene("HOLA"))

    mq = Maquina()
    mq.teclear(b'10 OPEN1,3\r20 CMD1\r30 PRINT"VIACMD"\r40 CLOSE1\rRUN\r', 60_000_000)
    ok &= caso("CMD1 redirige la salida", mq.pantalla_contiene("VIACMD"))

    mq = Maquina()
    mq.teclear(b'10 OPEN1,0\r20 GET#1,A$\r30 PRINT"GOT"\r40 CLOSE1\rRUN\r', 60_000_000)
    ok &= caso("GET#1 desde teclado no cuelga", mq.pantalla_contiene("GOT"))


    # mensajes de error de E/S largos (estilo Commodore, en el kernal)
    mq = Maquina(); mq.teclear(b'OPEN1,3\rOPEN1,3\r', 50_000_000)
    ok &= caso('error duplicado -> "?FILE OPEN ERROR"',
               mq.pantalla_contiene("FILE OPEN ERROR"))

    prog = b''.join(b'OPEN%d,3\r' % i for i in range(1, 12))
    mq = Maquina(); mq.teclear(prog, 120_000_000)
    ok &= caso('11 ficheros -> "?TOO MANY FILES ERROR"',
               mq.pantalla_contiene("TOO MANY FILES ERROR"))

    sys.exit(0 if ok else 1)

if __name__ == "__main__":
    main()
