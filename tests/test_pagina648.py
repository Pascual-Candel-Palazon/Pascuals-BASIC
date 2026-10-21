"""648 ($0288): pagina de la pantalla en la que escribe el editor
(direccion documentada, mapas de memoria publicos, nivel A/B de
docs/PROCEDENCIA.md). Cambiarla no mueve lo que muestra el VIC-II (eso es
$D018); solo dice al editor donde escribir y leer. La RAM de color sigue
en $D800.
"""
import sys
from arnes import Maquina

def caso(nombre, cond):
    print(("OK  " if cond else "FALLO ") + nombre)
    return cond

PAG = 0xC800        # 648 = 200

def texto(mq, base, fila):
    sc = bytes(mq.mem[base + fila * 40: base + fila * 40 + 40])
    return "".join(chr(c + 64) if 1 <= c <= 26 else chr(c) if 32 <= c < 64 else "."
                   for c in sc).rstrip()

def filas(mq, base):
    return [texto(mq, base, f) for f in range(25)]

def main():
    ok = True
    mq = Maquina()
    mq.teclear(b"", 3_000_000)
    mq.mem.write(PAG, [0xAA] * 1000)
    mq.teclear(b"POKE648,200:PRINTCHR$(5)CHR$(147)\"HOLA\"\r", 60_000_000)
    antes = bytes(mq.mem[0x0400:0x07E8])
    v = filas(mq, PAG)
    ok &= caso("CLR y PRINT escriben en $C800 (HOLA en la fila 0)", v[0] == "HOLA")
    ok &= caso("CLR limpia $C800 (filas 5-24 en blanco)",
               all(mq.mem[PAG + i] == 0x20 for i in range(200, 1000)))
    ok &= caso("color de HOLA en $D800 (blanco)", mq.mem[0xD800] & 15 == 1)
    # una orden tecleada se lee de la nueva pagina y se ejecuta
    mq.teclear(b"PRINT 6*7\r", 40_000_000)
    v = filas(mq, PAG)
    ok &= caso("orden tecleada leida de $C800 y ejecutada (42)", " 42" in v)
    # scroll en la pagina nueva
    mq.teclear(b"FORI=1TO30:PRINTI:NEXT\r", 200_000_000)
    v = filas(mq, PAG)
    ok &= caso("scroll en $C800: ultimas lineas 30 y READY.",
               " 30" in v[-4:] and "READY." in v[-3:])
    ok &= caso("scroll: la fila 0 ya no es HOLA", v[0] != "HOLA")
    ok &= caso("la pantalla de $0400 no se ha tocado",
               bytes(mq.mem[0x0400:0x07E8]) == antes)
    # volver a 4
    mq.teclear(b"POKE648,4:PRINTCHR$(147)\"ADIOS\"\r", 60_000_000)
    ok &= caso("POKE648,4: vuelve a escribir en $0400", texto(mq, 0x0400, 0) == "ADIOS")
    sys.exit(0 if ok else 1)

if __name__ == "__main__":
    main()
