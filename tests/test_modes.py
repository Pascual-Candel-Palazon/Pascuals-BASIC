"""Tests de modo inverso (CHR$(18)/146), modo comillas, modo insercion y
caso may/min (CHR$(14)/142)."""
import sys
from arnes import Maquina

def caso(nombre, cond):
    print(("OK  " if cond else "FALLO ") + nombre)
    return cond

def hay_screencode(mq, sc):
    return any(mq.mem[0x0400 + f * 40 + c] == sc
               for f in range(25) for c in range(40))

def main():
    ok = True

    # Inverso: CHR$(18)"A" CHR$(146)"B" -> A con bit7 ($81), B normal ($02)
    mq = Maquina()
    mq.teclear(b'PRINTCHR$(18)"A"CHR$(146)"B"\r', 55_000_000)
    ok &= caso("inverso ON: A invertida ($81)", hay_screencode(mq, 0x81))
    ok &= caso("inverso OFF: B normal ($02)", hay_screencode(mq, 0x02))

    # El retorno de carro apaga el inverso: PRINT CHR$(18)"A" (CR) y luego
    # PRINT"Z" sale normal ($1A), como tras el titulo de un LOAD"$"
    mq = Maquina()
    mq.teclear(b'PRINTCHR$(18)"A":PRINT"Z"\r', 55_000_000)
    ok &= caso("CR apaga el inverso: Z normal ($1A) y no invertida ($9A)",
               hay_screencode(mq, 0x1A) and not hay_screencode(mq, 0x9A))

    # Modo comillas: tras una comilla impresa, CHR$(147) no borra la
    # pantalla sino que se ve como corazon invertido (pantalla $D3)
    mq = Maquina()
    mq.teclear(b'PRINTCHR$(34);CHR$(147);"ZZ"\r', 55_000_000)
    ok &= caso("comillas: CHR$(147) se ve invertido ($D3) y no borra",
               hay_screencode(mq, 0xD3)
               and any("PASCUAL'S BASIC" in f for f in mq.pantalla()))
    # el RETURN sale del modo: CHR$(18) vuelve a activar el inverso
    mq = Maquina()
    mq.teclear(b'PRINTCHR$(34):PRINTCHR$(18)"X"\r', 55_000_000)
    ok &= caso("RETURN sale de comillas: CHR$(18) vuelve a ejecutarse (X = $98)",
               hay_screencode(mq, 0x98))

    # Teclear controles entre comillas los guarda en el programa, y LIST
    # los muestra invertidos en vez de ejecutarlos
    mq = Maquina()
    mq.teclear(b'10 PRINT"\x93\x11HOLA"\rLIST\r', 70_000_000)
    ok &= caso("comillas al teclear: se guardan CLR y abajo ($93 $11)",
               bytes(mq.mem[0x0805:0x080D]) == b'\x99"\x93\x11HOLA')
    ok &= caso("LIST muestra los controles invertidos ($D3 $91) sin borrar",
               hay_screencode(mq, 0xD3) and hay_screencode(mq, 0x91)
               and any("PASCUAL'S BASIC" in f for f in mq.pantalla()))

    # Modo insercion: INST abre hueco y lo siguiente se escribe aunque sea
    # un control (izquierda x2, INST, abajo -> PRINT"A{abajo}C")
    mq = Maquina()
    mq.teclear(b'10 PRINT"AC"\x9d\x9d\x94\x11\r', 70_000_000)
    ok &= caso("insercion: INST + abajo guarda el control en el hueco",
               bytes(mq.mem[0x0805:0x080B]) == b'\x99"A\x11C"')

    # Caso: CHR$(14) -> $D018=$17 (minusculas); CHR$(142) -> $15 (mayusc.)
    mq = Maquina()
    mq.teclear(b'PRINTCHR$(14)\r', 35_000_000)
    ok &= caso("CHR$(14): $D018 = $17 (texto/minusculas)",
               mq.mem[0xD018] == 0x17)
    mq.teclear(b'PRINTCHR$(142)\r', 35_000_000)
    ok &= caso("CHR$(142): $D018 = $15 (mayus/graficos)",
               mq.mem[0xD018] == 0x15)

    sys.exit(0 if ok else 1)

if __name__ == "__main__":
    main()
