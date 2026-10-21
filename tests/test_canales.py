"""Canales de E/S desde BASIC:
- CHKIN ($FFC6) y CHKOUT ($FFC9) devuelven en X el fichero logico: el
  BASIC lo guarda en CHANNL (STX) tras llamarlos. Antes devolvian el
  indice de la tabla, CHANNL quedaba a 0 con el primer fichero abierto y
  INPUT# escribia "? " en pantalla como si leyera del teclado.
- INPUT# desde el teclado (dispositivo 0) no pide con "?".
(El caso de un $14 dentro de los datos de INPUT#, que antes borraba el
caracter anterior, se comprobo en VICE con la 1541: ver CONTINUIDAD.)
"""
import sys
from arnes import Maquina

def caso(nombre, cond):
    print(("OK  " if cond else "FALLO ") + nombre)
    return cond

def main():
    ok = True
    mq = Maquina()
    mq.teclear(b"OPEN5,3:OPEN7,0\r", 40_000_000)
    for nombre, dire, lfn in (("CHKIN", 0xFFC6, 7), ("CHKOUT", 0xFFC9, 5)):
        mq.mpu.x = lfn
        mq.subrutina(dire)
        ok &= caso("%s con X=%d vuelve con X=%d y C=0" % (nombre, lfn, lfn),
                   mq.mpu.x == lfn and not (mq.mpu.p & 1))
        mq.subrutina(0xFFCC)                   # CLRCHN
    mq.mpu.x = 9
    mq.subrutina(0xFFC6)
    ok &= caso("CHKIN de un fichero no abierto: C=1, A=3",
               (mq.mpu.p & 1) and mq.mpu.a == 3)

    mq = Maquina()
    mq.teclear(b"10 OPEN1,0:INPUT#1,A$:CLOSE1:PRINT\"Z\"A$\"Z\"\rRUN\r",
               60_000_000)
    mq.teclear(b"HOLA\r", 40_000_000)
    v = [l.rstrip() for l in mq.pantalla()]
    i = v.index("RUN")
    ok &= caso("INPUT#1 desde el teclado: sin \"?\" y A$ = HOLA",
               v[i + 1] == "HOLA" and "ZHOLAZ" in v[i + 2:i + 4])
    sys.exit(0 if ok else 1)

if __name__ == "__main__":
    main()
