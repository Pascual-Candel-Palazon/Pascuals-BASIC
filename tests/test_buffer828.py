"""Regresion: teclear lineas no debe tocar el buffer de cinta ($033C, 828).

En un C64 real el editor de pantalla no usa $033C, y es el sitio clasico
para rutinas cortas en codigo maquina (POKE ... : SYS 828). Hasta el
20 oct 2026 el editor copiaba cada linea tecleada en $033C, asi que
SYS828 tras cargar una rutina se colgaba.
"""
import sys
from arnes import Maquina

def caso(nombre, cond):
    print(("OK  " if cond else "FALLO ") + nombre)
    return cond

def main():
    ok = True
    mq = Maquina()
    # RTS en 828; despues, en OTRA linea, saltar a ella.
    mq.teclear(b'POKE828,96\rSYS828:PRINT"HECHO"\r', 60_000_000)
    p = mq.pantalla()
    ok &= caso("SYS828 con RTS en 828 vuelve e imprime HECHO",
               any(f.strip() == "HECHO" for f in p))
    ok &= caso("$033C sigue valiendo 96 tras teclear otra linea",
               mq.mem[0x033C] == 96)
    # Una linea larga (2 filas) no debe tocar 828..907 y debe ejecutarse.
    mq = Maquina()
    mq.teclear(b'POKE828,96\r'
               b'PRINT"ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789ABCDEFGHIJKLMNOPQRSTU"\r',
               70_000_000)
    p = mq.pantalla()
    ok &= caso("linea de 2 filas se ejecuta entera",
               any("ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789ABCD" in f for f in p))
    ok &= caso("linea de 2 filas no toca $033C",
               mq.mem[0x033C] == 96)
    sys.exit(0 if ok else 1)

if __name__ == "__main__":
    main()
