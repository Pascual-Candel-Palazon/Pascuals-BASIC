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

    # v2: navegar arriba a una linea listada, editarla y re-entrarla
    ARRIBA = bytes([0x91]); DER = bytes([0x1D])
    mq = Maquina()
    mq.teclear(b"10 A=5\r20 B=6\rLIST\r", 70_000_000)
    extra = ARRIBA * 3 + DER * 6 + b"9\r"   # subir a '10 A=5' listada, '5'->'9'
    cola = list(extra); m = mq.mpu; n = 0; prox = 200_000
    while n < 70_000_000 and (cola or n < prox + 4_000_000):
        if n % 17000 == 0 and n and not (m.p & 0x04):
            mq.irq()
        if cola and n >= prox and mq.mem[0xC6] == 0:
            mq.mem.write(0x0277, [cola.pop(0)]); mq.mem.write(0xC6, [1])
            prox = n + 60_000
        m.step(); n += 1
    prog = bytes(mq.mem[0x0801:0x0820])
    ok &= caso("v2: editar linea listada re-entra (A=5 -> A=9)",
               bytes([0x41, 0xB2, 0x39]) in prog and
               bytes([0x41, 0xB2, 0x35]) not in prog)

    sys.exit(0 if ok else 1)

if __name__ == "__main__":
    main()
