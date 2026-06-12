"""Tests del editor de pantalla (CHRIN v2, WYSIWYG)."""
import sys
from arnes import Maquina

IZQ = bytes([0x9D]); DEL = bytes([0x14])

def caso(nombre, cond):
    print(("OK  " if cond else "FALLO ") + nombre)
    return cond

def sesion(entrada, pasos=60_000_000):
    mq = Maquina()
    mq.teclear(entrada, pasos)
    return mq

def main():
    ok = True

    # sobrescritura con el cursor: PRONT -> PRINT
    mq = sesion(b"10 PRONT 5" + IZQ * 5 + b"I\rLIST\r", 40_000_000)
    ok &= caso("cursor+sobrescribir (WYSIWYG)",
               mq.pantalla_contiene("10 PRINT 5"))

    # DEL recoge el texto: PRIXNT -> PRINT
    mq = sesion(b"20 PRIXNT 7" + IZQ * 4 + DEL + b"\rLIST\r", 40_000_000)
    ok &= caso("DEL recoge el texto",
               mq.pantalla_contiene("20 PRINT 7"))

    # linea larga con wrap a dos filas
    larga = b"10 POKE 53280,1:POKE 53281,2:PRINT \"LINEA LARGA\":GOTO 10"
    mq = sesion(larga + b"\rLIST\r", 55_000_000)
    p = "\n".join(mq.pantalla())
    ok &= caso("linea con wrap integra en LIST",
               "LINEA LARGA\":GOTO 10" in p.replace("\n", ""))

    # paste: letras en codificacion alta y baja
    base = b"30 V=PEEK(788)\r"
    alta = bytes(c + 0x80 if 0x41 <= c <= 0x5A else c for c in base)
    mq = sesion(alta + b"LIST\r", 35_000_000)
    ok &= caso("paste PETSCII alto ($C1-$DA)",
               mq.pantalla_contiene("30 V=PEEK(788)"))
    baja = bytes(c + 0x20 if 0x41 <= c <= 0x5A else c for c in base)
    mq = sesion(baja + b"LIST\r", 35_000_000)
    ok &= caso("paste minusculas ($61-$7A)",
               mq.pantalla_contiene("30 V=PEEK(788)"))

    sys.exit(0 if ok else 1)

if __name__ == "__main__":
    main()
