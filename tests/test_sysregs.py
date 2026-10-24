"""SYS carga A/X/Y/P desde 780-783 antes de saltar y los guarda al volver.

Interfaz publica del C64 (nivel B, Programmer's Reference Guide y
Mapping the C64): 780 ($030C) = A, 781 = X, 782 = Y, 783 = registro de
estado. Antes del 24 oct 2026 SYS saltaba sin cargarlos ni guardarlos:
POKE780,65:SYS65490 no imprimia nada.
"""
import sys
from arnes import Maquina

def caso(nombre, cond, extra=""):
    print(("OK  " if cond else "FALLO ") + nombre + (" " + extra if extra else ""))
    return cond

def main():
    ok = True

    # 1) A de entrada: CHROUT ($FFD2 = 65490) imprime la A de 780.
    mq = Maquina()
    mq.teclear(b'POKE780,65:SYS65490:PRINT"#"\r', 60_000_000)
    p = mq.pantalla()
    ok &= caso("POKE780,65:SYS65490 imprime A",
               any(f.strip() == "A#" for f in p),
               repr([f.rstrip() for f in p if f.strip()][:6]))

    # 2) Salida: rutina en 828 que deja A=$12 X=$34 Y=$56 y C=1.
    #    LDA #$12 / LDX #$34 / LDY #$56 / SEC / RTS
    mq = Maquina()
    mq.teclear(b'POKE828,169:POKE829,18:POKE830,162:POKE831,52\rPOKE832,160:POKE833,86:POKE834,56:POKE835,96\r', 60_000_000)
    mq.teclear(b'SYS828\r', 30_000_000)
    m = mq.mem
    ok &= caso("tras SYS, 780/781/782 = A/X/Y de la rutina",
               (m[0x030C], m[0x030D], m[0x030E]) == (0x12, 0x34, 0x56),
               "obtenido=%02X %02X %02X" % (m[0x030C], m[0x030D], m[0x030E]))
    ok &= caso("tras SYS, 783 guarda el estado (C=1)", m[0x030F] & 1 == 1,
               "783=%02X" % m[0x030F])

    # 3) Entrada X/Y: rutina TXA / STA 900 / TYA / STA 901 / RTS.
    mq = Maquina()
    mq.teclear(b'POKE828,138:POKE829,141:POKE830,132:POKE831,3\rPOKE832,152:POKE833,141:POKE834,133:POKE835,3\r', 60_000_000)
    mq.teclear(b'POKE836,96:POKE781,7:POKE782,9:SYS828\r', 40_000_000)
    m = mq.mem
    ok &= caso("X e Y de entrada salen de 781/782",
               (m[900], m[901]) == (7, 9),
               "obtenido=%d %d" % (m[900], m[901]))

    # 4) Estado de entrada: C de 783. Rutina LDA #0 / ROL A / STA 900 / RTS.
    for c in (1, 0):
        mq = Maquina()
        mq.teclear(b'POKE828,169:POKE829,0:POKE830,42:POKE831,141\rPOKE832,132:POKE833,3:POKE834,96\r', 60_000_000)
        mq.teclear(b'POKE900,99:POKE783,%d:SYS828\r' % c, 40_000_000)
        ok &= caso("C de entrada sale de 783 (POKE783,%d)" % c,
                   mq.mem[900] == c, "900=%d" % mq.mem[900])

    # 5) RAMTAS limpia la pagina 3 (interfaz publica: $0200-$03FF), asi
    #    que tras el arranque 780-783 valen 0, como en el C64. Se llena la
    #    pagina 3 de $FF antes del RESET para que el test discrimine (el
    #    arnes arranca con la RAM a cero).
    mq = Maquina()
    mq.mem.write(0x0300, [0xFF] * 256)
    mq.correr(8_000_000)
    m = mq.mem
    ok &= caso("tras el arranque 780-783 valen 0",
               [m[a] for a in range(0x030C, 0x0310)] == [0, 0, 0, 0],
               "obtenido=%r" % [m[a] for a in range(0x030C, 0x0310)])
    ok &= caso("tras el arranque 900 vale 0 (pagina 3 limpia)", m[900] == 0,
               "900=%d" % m[900])
    ok &= caso("los vectores de pagina 3 se ponen despues (READY.)",
               mq.pantalla_contiene("READY."))

    sys.exit(0 if ok else 1)

if __name__ == "__main__":
    main()
