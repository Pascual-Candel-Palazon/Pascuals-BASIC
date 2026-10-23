"""Fin de linea de PRINT#: solo CR, salvo ficheros logicos >= 128 (CR+LF).

Programmer's Reference Guide (nivel A): el LF tras el CR solo se manda
cuando el numero logico de fichero es 128 o mayor. Comprobado en VICE con
la ROM original como caja negra: OPEN2,8,2,"T,S,W":PRINT#2,"AB" deja
"AB"+CR en el disco, y con el fichero 130 deja "AB"+CR+LF.

Aqui se engancha el vector de salida ($0326) para registrar los bytes que
manda el BASIC a un fichero abierto a la pantalla (dispositivo 3).
"""
import sys
from arnes import Maquina

def caso(nombre, cond):
    print(("OK  " if cond else "FALLO ") + nombre)
    return cond

GANCHO = 0xC100
BUF = 0xC200

def main():
    ok = True
    mq = Maquina()
    mq.teclear(b'10 OPEN2,3:OPEN130,3:PRINT#2,"QX":PRINT#130,"QY":'
               b'PRINT#2,"QZ";CHR$(13);:CLOSE2:CLOSE130\r', 40_000_000)
    viejo = mq.mem[0x0326] | (mq.mem[0x0327] << 8)
    codigo = [0x8E, 0xF0, 0xC0,          # stx $C0F0
              0xAE, 0xF1, 0xC0,          # ldx $C0F1
              0x9D, BUF & 0xFF, BUF >> 8,  # sta BUF,x
              0xEE, 0xF1, 0xC0,          # inc $C0F1
              0xAE, 0xF0, 0xC0,          # ldx $C0F0
              0x6C, 0xF2, 0xC0]          # jmp ($C0F2) -> salida original
    mq.mem.write(GANCHO, codigo)
    mq.mem.write(0xC0F0, [0, 0, viejo & 0xFF, viejo >> 8])
    mq.mem.write(0x0326, [GANCHO & 0xFF, GANCHO >> 8])
    mq.teclear(b"RUN\r", 40_000_000)
    n = mq.mem[0xC0F1]
    sal = bytes(mq.mem[BUF + i] for i in range(n))

    def tras(marca):
        i = sal.find(marca)
        return sal[i + len(marca):i + len(marca) + 2] if i >= 0 else None

    ok &= caso("PRINT#2,\"QX\" termina en CR sin LF (%r)" % tras(b"QX"),
               tras(b"QX") is not None and tras(b"QX")[:1] == b"\r"
               and tras(b"QX")[1:2] != b"\n")
    ok &= caso("PRINT#130,\"QY\" termina en CR+LF (%r)" % tras(b"QY"),
               tras(b"QY") == b"\r\n")
    ok &= caso("PRINT#2,\"QZ\";CHR$(13); manda un solo CR (%r)" % tras(b"QZ"),
               tras(b"QZ") is not None and tras(b"QZ")[:1] == b"\r"
               and tras(b"QZ")[1:2] != b"\n")
    sys.exit(0 if ok else 1)

if __name__ == "__main__":
    main()
