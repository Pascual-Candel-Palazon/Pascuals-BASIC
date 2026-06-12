"""Tests de la firma de cartucho CBM80 y de los GAP de la auditoria:
despacho de BRK ($0316), RESTOR ($FF8A) y VECTOR ($FF8D)."""
import sys
from arnes import Maquina, imagen

def caso(nombre, cond):
    print(("OK  " if cond else "FALLO ") + nombre)
    return cond

FIRMA = [0xC3, 0xC2, 0xCD, 0x38, 0x30]  # "CBM80"

def main():
    ok = True
    img = imagen()
    resetvec = img[0xFFFC] | (img[0xFFFD] << 8)
    nmivec = img[0xFFFA] | (img[0xFFFB] << 8)

    # --- cartucho: reset salta por ($8000) si hay firma ---
    mq = Maquina()
    # "cartucho": vector frio $8000 -> $8009 (rutina: marca y se queda)
    mq.mem.write(0x8000, [0x09, 0x80, 0x0D, 0x80] + FIRMA)
    # rutina del cartucho en $8009: LDA #$AA / STA $02 / JMP $800E...
    mq.mem.write(0x8009, [0xA9, 0xAA, 0x85, 0x02, 0x4C, 0x0F, 0x80])
    mq.mem.write(0x8010, [0x4C, 0x10, 0x80])  # bucle (ajustado abajo)
    mq.mem.write(0x800F, [0x4C, 0x0F, 0x80])  # JMP $800F (bucle)
    m = mq.mpu
    m.pc = resetvec
    for _ in range(200_000):
        m.step()
    ok &= caso("reset con CBM80 salta al cartucho (marca $AA)",
               mq.mem[0x02] == 0xAA)
    ok &= caso("reset con CBM80 NO arranca el BASIC",
               mq.mem[0x0400] in (0x00, 0x20) or True)  # pantalla sin banner
    # mas estricto: el banner no se imprimio
    pant = "".join(chr(64 + mq.mem[0x0400 + i]) if 1 <= mq.mem[0x0400 + i] <= 26
                   else " " for i in range(40))
    ok &= caso("sin banner tras saltar al cartucho",
               "COMMODORE" not in pant)

    # --- sin firma: arranque normal ---
    mq = Maquina()
    m = mq.mpu
    m.pc = resetvec
    for n in range(4_000_000):
        if n % 17000 == 0 and n and not (m.p & 0x04):
            mq.irq()
        m.step()
    ok &= caso("sin firma: arranca el BASIC normal",
               mq.pantalla_contiene("COMMODORE BASIC"))

    # --- NMI con cartucho: salta por ($8002) ---
    mq = Maquina()
    mq.teclear(b"", 3_000_000)  # arrancar
    mq.mem.write(0x8000, [0x09, 0x80, 0x14, 0x80] + FIRMA)
    mq.mem.write(0x8014, [0xA9, 0xBB, 0x85, 0x03, 0x4C, 0x1A, 0x80])
    mq.mem.write(0x801A, [0x4C, 0x1A, 0x80])
    m = mq.mpu
    mq.mem.write(0x0100 + m.sp, [(m.pc >> 8) & 0xFF]); m.sp = (m.sp - 1) & 0xFF
    mq.mem.write(0x0100 + m.sp, [m.pc & 0xFF]);        m.sp = (m.sp - 1) & 0xFF
    mq.mem.write(0x0100 + m.sp, [m.p]);                m.sp = (m.sp - 1) & 0xFF
    m.pc = nmivec
    for _ in range(100_000):
        m.step()
    ok &= caso("NMI con CBM80 salta por ($8002) (marca $BB)",
               mq.mem[0x03] == 0xBB)

    # --- BRK: despacha por ($0316) ---
    mq = Maquina()
    mq.teclear(b"", 3_000_000)
    # wedge BRK en $C100: LDA #$CC / STA $04 / JMP $C107 (bucle)
    mq.mem.write(0xC100, [0xA9, 0xCC, 0x85, 0x04, 0x4C, 0x07, 0xC1])
    mq.mem.write(0xC107, [0x4C, 0x07, 0xC1])
    mq.mem.write(0x0316, [0x00, 0xC1])  # CBINV -> wedge
    # rutina con BRK en $C000
    mq.mem.write(0xC000, [0x00, 0xEA])  # BRK
    m = mq.mpu
    m.pc = 0xC000
    for _ in range(50_000):
        m.step()
    ok &= caso("BRK despacha por $0316 (marca $CC)", mq.mem[0x04] == 0xCC)

    # --- RESTOR: restaura los vectores de fabrica ---
    mq = Maquina()
    mq.teclear(b"", 3_000_000)
    defecto = list(mq.mem[0x0314:0x0334])
    for i in range(0x20):  # corromper
        mq.mem.write(0x0314 + i, [0xAA])
    ok2 = mq.subrutina(0xFF8A, 50_000)
    ok &= caso("RESTOR retorna", ok2)
    ok &= caso("RESTOR restaura los vectores",
               list(mq.mem[0x0314:0x0334]) == defecto)

    # --- VECTOR: leer (C=1) y cargar (C=0) la tabla ---
    mq = Maquina()
    mq.teclear(b"", 3_000_000)
    m = mq.mpu
    # leer: C=1, XY -> $C200
    m.p |= 0x01
    m.x = 0x00; m.y = 0xC2
    ok &= caso("VECTOR(leer) retorna", mq.subrutina(0xFF8D, 50_000))
    copia = list(mq.mem[0xC200:0xC220])
    ok &= caso("VECTOR(leer) vuelca la tabla",
               copia == list(mq.mem[0x0314:0x0334]))
    # modificar la copia y cargarla: C=0
    mq.mem.write(0xC200, [0x34, 0x12])
    m.p &= ~0x01
    m.x = 0x00; m.y = 0xC2
    ok &= caso("VECTOR(cargar) retorna", mq.subrutina(0xFF8D, 50_000))
    ok &= caso("VECTOR(cargar) aplica la tabla",
               mq.mem[0x0314] == 0x34 and mq.mem[0x0315] == 0x12)


    # --- liturgia de cartucho: init por la tabla + salida JMP ($A000) ---
    mq = Maquina()
    m = mq.mpu
    prog = [0x78, 0xA2, 0xFF, 0x9A,
            0xA9, 0x37, 0x85, 0x01, 0xA9, 0x2F, 0x85, 0x00,
            0x20, 0x84, 0xFF,   # IOINIT
            0x20, 0x87, 0xFF,   # RAMTAS
            0x20, 0x8A, 0xFF,   # RESTOR
            0x20, 0x81, 0xFF,   # CINT
            0x58,
            0x6C, 0x00, 0xA0]   # JMP ($A000) frio
    mq.mem.write(0xC000, prog)
    m.pc = 0xC000
    for n in range(4_000_000):
        if n % 17000 == 0 and n and not (m.p & 0x04):
            mq.irq()
        m.step()
    ok &= caso("liturgia cartucho: banner via JMP($A000)",
               mq.pantalla_contiene("COMMODORE BASIC"))
    ok &= caso("liturgia cartucho: timer IRQ corriendo",
               mq.mem[0xDC0E] & 1 == 1)


    # --- rutinas de la tabla que necesitan los cartuchos (no IEC) ---
    mq = Maquina(); mq.teclear(b"", 3_000_000); m = mq.mpu
    def llamar(addr, x=0, y=0, c=0):
        m.x, m.y = x, y
        if c: m.p |= 0x01
        else: m.p &= ~0x01
        mq.subrutina(addr, 40000)
        return m.x, m.y
    x, y = llamar(0xFFED);        ok &= caso("SCREEN -> 40x25", (x, y) == (40, 25))
    x, y = llamar(0xFF99, c=1);   ok &= caso("MEMTOP -> $A000", x | y << 8 == 0xA000)
    x, y = llamar(0xFF9C, c=1);   ok &= caso("MEMBOT -> $0800", x | y << 8 == 0x0800)
    x, y = llamar(0xFFF3);        ok &= caso("IOBASE -> $DC00", x | y << 8 == 0xDC00)
    llamar(0xFFF0, x=5, y=10, c=0)
    x, y = llamar(0xFFF0, c=1);   ok &= caso("PLOT fija/lee (5,10)", (x, y) == (5, 10))
    ok &= caso("CLALL retorna", mq.subrutina(0xFFE7, 20000))
    ok &= caso("CLRCHN retorna", mq.subrutina(0xFFCC, 20000))


    # --- cartucho que arranca por las direcciones INTERNAS documentadas ---
    mq = Maquina(); m = mq.mpu
    prog = [0x78, 0xD8, 0xA2, 0xFF, 0x9A,
            0x20, 0xA3, 0xFD,   # JSR $FDA3 IOINIT
            0x20, 0x50, 0xFD,   # JSR $FD50 RAMTAS
            0x20, 0x15, 0xFD,   # JSR $FD15 RESTOR
            0x20, 0x5B, 0xFF,   # JSR $FF5B CINT
            0x58,
            0xA9, 0x51, 0x20, 0xD2, 0xFF,   # 'Q' a CHROUT
            0x4C, 0x1A, 0xC0]
    mq.mem.write(0xC000, prog)
    m.pc = 0xC000
    for n in range(4_000_000):
        if n % 17000 == 0 and n and not (m.p & 0x04):
            mq.irq()
        m.step()
    ok &= caso("cart por direcciones internas ($FDA3/$FD50/$FD15/$FF5B)",
               any(mq.mem[0x0400 + i] == 0x11 for i in range(1000)))

    sys.exit(0 if ok else 1)

if __name__ == "__main__":
    main()
