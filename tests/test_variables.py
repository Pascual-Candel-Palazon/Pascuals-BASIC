"""Variables documentadas del editor y del teclado, y zonas libres para el
usuario. Direcciones y semantica: mapas de memoria publicos (nivel A/B de
docs/PROCEDENCIA.md).

- 197/203 ($C5/$CB): codigo de la tecla pulsada (columna*8 + fila), 64 sin
  tecla. 653 ($028D): bit0 SHIFT, bit1 C=, bit2 CTRL.
- 214 ($D6): fila del cursor. 648 ($0288): pagina de la pantalla (4).
- 678 ($02A6): 1 en PAL (el arnes simula un VIC-II PAL).
- 657 ($0291): con el bit 7 a 1, SHIFT+C= no cambia el juego de caracteres.
- 251-254 ($FB-$FE) y 679-767 ($02A7-$02FF) quedan libres para programas:
  el KERNAL no los toca al escribir ni al leer el teclado.
"""
import sys
from arnes import Maquina, etiqueta

SCN = etiqueta("KSCNKEY")

def caso(nombre, cond):
    print(("OK  " if cond else "FALLO ") + nombre)
    return cond

def ultima_cifra(mq):
    lineas = [f.strip() for f in mq.pantalla() if f.strip()]
    i = lineas.index("READY.", len(lineas) - 3) if "READY." in lineas[-3:] else -1
    return lineas[i - 1] if i > 0 else None

def main():
    ok = True

    mq = Maquina()
    mq.teclear(b"PRINTPEEK(197);PEEK(203);PEEK(648);PEEK(678)\r", 40_000_000)
    vals = (ultima_cifra(mq) or "").split()
    ok &= caso("sin tecla: PEEK(197) = PEEK(203) = 64", vals[:2] == ["64", "64"])
    ok &= caso("PEEK(648) = 4 (pantalla en $0400)", vals[2:3] == ["4"])
    ok &= caso("PEEK(678) = 1 (PAL)", vals[3:4] == ["1"])

    mq = Maquina()
    mq.teclear(b"PRINTCHR$(147);:PRINT:PRINT:PRINTPEEK(214)\r", 40_000_000)
    ok &= caso("PEEK(214) = fila del cursor (2, tras borrar y bajar dos)",
               mq.pantalla()[2].strip() == "2")

    # Teclas sostenidas, con KSCNKEY directo: A = columna 1, fila 2 -> 10;
    # espacio = columna 7, fila 4 -> 60
    t = set()
    mq = Maquina(teclas_matriz=t)
    t.add((1, 2))
    mq.subrutina(SCN)
    ok &= caso("A pulsada: $C5 = $CB = 10", mq.mem[0xC5] == 10 and mq.mem[0xCB] == 10)
    t.clear(); t.add((7, 4))
    mq.subrutina(SCN)
    ok &= caso("espacio pulsado: $C5 = 60", mq.mem[0xC5] == 60)
    t.clear()
    mq.subrutina(SCN)
    ok &= caso("al soltar: $C5 = 64", mq.mem[0xC5] == 64)
    t.update({(1, 7), (7, 2)})           # SHIFT izquierdo + CTRL
    mq.subrutina(SCN)
    ok &= caso("SHIFT+CTRL: $028D = 5 y $C5 = 64 (modificadores no cuentan)",
               mq.mem[0x028D] == 5 and mq.mem[0xC5] == 64)
    t.clear(); t.add((7, 5))             # C=
    mq.subrutina(SCN)
    ok &= caso("C=: $028D = 2", mq.mem[0x028D] == 2)

    # 657: bit 7 bloquea SHIFT+C=
    for bloqueo, esperado in ((0x00, True), (0x80, False)):
        t = set()
        mq = Maquina(teclas_matriz=t)
        mq.mem.write(0x0291, [bloqueo])
        d0 = mq.mem[0xD018]
        t.update({(1, 7), (7, 5)})
        mq.subrutina(SCN)
        cambio = mq.mem[0xD018] != d0
        ok &= caso("POKE657,%d: SHIFT+C= %s el juego de caracteres"
                   % (bloqueo, "cambia" if esperado else "no cambia"),
                   cambio == esperado)

    # Zonas libres: rellenar, teclear y escribir (IRQ, editor, scroll) y
    # comprobar que siguen intactas
    mq = Maquina()
    mq.teclear(b"", 3_000_000)
    patron = [(i * 37 + 11) & 0xFF for i in range(0x02A7, 0x0300)]
    mq.mem.write(0x02A7, patron)
    mq.mem.write(0xFB, [0x12, 0x34, 0x56, 0x78])
    mq.teclear(b"FORI=1TO30:PRINT\"LINEA\";I:NEXT\r", 120_000_000)
    ok &= caso("679-767 ($02A7-$02FF) intactos tras teclear y hacer scroll",
               list(mq.mem[0x02A7:0x0300]) == patron)
    ok &= caso("251-254 ($FB-$FE) intactos tras escribir en pantalla",
               list(mq.mem[0xFB:0xFF]) == [0x12, 0x34, 0x56, 0x78])

    sys.exit(0 if ok else 1)

if __name__ == "__main__":
    main()
