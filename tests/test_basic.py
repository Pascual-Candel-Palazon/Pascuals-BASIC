"""Tests de deltas C64 en el BASIC: USR ($0310), PEEK de ROM y E/S.

Estos cubren fixups que en su dia se verificaron solo a ojo en VICE;
aqui quedan como verificacion automatica y permanente.
"""
import sys
from arnes import Maquina, imagen

def caso(nombre, cond):
    print(("OK  " if cond else "FALLO ") + nombre)
    return cond

def sesion(lineas, pasos=60_000_000):
    mq = Maquina()
    mq.teclear(lineas, pasos)
    return mq

def main():
    ok = True
    img = imagen()

    # USR en $0310: POKE 785/786 fija el destino; rutina RTS devuelve FAC.
    # USR(7) -> 7 en pantalla.
    mq = sesion(b"POKE785,0:POKE786,192\rPOKE49152,96\rPRINTUSR(7)\r", 70_000_000)
    p = mq.pantalla()
    # buscar una linea cuyo unico contenido sea " 7"
    tiene7 = any(f.strip() == "7" for f in p)
    ok &= caso("USR en $0310 (USR(7) -> 7)", tiene7)

    # PEEK de ROM: el candado original devolvia 0 para direcciones de ROM.
    # PEEK(40960) debe devolver el byte real ($A000 = 117).
    objetivo = str(img[0xA000])
    mq = sesion(b"PRINTPEEK(40960)\r", 35_000_000)
    p = mq.pantalla()
    ok &= caso(f"PEEK de ROM $A000 = {objetivo} (candado eliminado)",
               any(f.strip() == objetivo for f in p))

    # PEEK/POKE de ida y vuelta en RAM: prueba la via de lectura sin
    # depender de direcciones ZP (que NO coinciden con las del C64 por el
    # desplazamiento de pagina cero del BASIC; vease la auditoria).
    mq = sesion(b"POKE49152,123\rPRINTPEEK(49152)\r", 50_000_000)
    p = mq.pantalla()
    ok &= caso("PEEK/POKE de RAM ida y vuelta (123)",
               any(f.strip() == "123" for f in p))

    sys.exit(0 if ok else 1)

if __name__ == "__main__":
    main()
