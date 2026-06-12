"""Tests de la conversion PETSCII->screencode completa y codigos de
control HOME / INST, mas la emision de graficos por C=+letra."""
import sys
from arnes import Maquina, etiqueta

SCN = etiqueta("KSCNKEY")

def caso(nombre, cond):
    print(("OK  " if cond else "FALLO ") + nombre)
    return cond

def aparece(codigo, sc):
    mq = Maquina()
    mq.teclear(b'PRINTCHR$(' + str(codigo).encode() + b');\r', 40_000_000)
    return any(mq.mem[0x0400 + i] == sc for i in range(1000))

def main():
    ok = True

    # Conversion completa por rangos -> screencode esperado
    for cod, sc, desc in [(65, 0x01, "A"), (91, 0x1B, "["),
                          (0xA1, 0x61, "grafico C= bajo"),
                          (0xB0, 0x70, "grafico C="),
                          (0xC1, 0x41, "grafico shift")]:
        ok &= caso(f"CHR$({cod}) [{desc}] -> screencode ${sc:02X}",
                   aparece(cod, sc))

    # HOME (CHR$(19)): el caracter siguiente cae en la esquina (0,0)
    mq = Maquina()
    mq.teclear(b'PRINTCHR$(19);"Z"\r', 40_000_000)
    ok &= caso("HOME: caracter en (0,0)", mq.mem[0x0400] == 0x1A)

    # INST (CHR$(148)): inserta espacio desplazando la fila
    mq = Maquina()
    mq.teclear(b'PRINTCHR$(19);"AB";CHR$(19);CHR$(148)\r', 50_000_000)
    fila = [mq.mem[0x0400 + c] for c in range(3)]
    ok &= caso("INST: desplaza la fila (espacio,A,B)",
               fila == [0x20, 0x01, 0x02])

    # C=+letra emite el codigo grafico (teclado)
    if SCN is not None:
        def emite(teclas):
            t = set(); mq = Maquina(teclas_matriz=t)
            for i in range(16):
                mq.mem.write(0x02B0 + i, [0])
            for a in (0xC6, 0x02AB, 0x02E0, 0x02E1, 0x02E2):
                mq.mem.write(a, [0])
            t.update(teclas); mq.subrutina(SCN)
            n = mq.mem[0xC6]
            return bytes(mq.mem[0x0277:0x0277 + n])
        CBM = (7, 5)
        ok &= caso("C=+A -> grafico $B0", emite({CBM, (1, 2)}) == b'\xB0')
        ok &= caso("C=+Z -> grafico $AD", emite({CBM, (1, 4)}) == b'\xAD')

    sys.exit(0 if ok else 1)

if __name__ == "__main__":
    main()
