"""Tests de RUN/STOP (romper) y RUN/STOP-RESTORE (arranque en caliente)."""
import sys
from arnes import Maquina, imagen

def caso(nombre, cond):
    print(("OK  " if cond else "FALLO ") + nombre)
    return cond

def disparar_nmi(mq):
    img = imagen()
    nmivec = img[0xFFFA] | (img[0xFFFB] << 8)
    m = mq.mpu
    mq.mem.write(0x0100 + m.sp, [(m.pc >> 8) & 0xFF]); m.sp = (m.sp - 1) & 0xFF
    mq.mem.write(0x0100 + m.sp, [m.pc & 0xFF]);        m.sp = (m.sp - 1) & 0xFF
    mq.mem.write(0x0100 + m.sp, [m.p]);                m.sp = (m.sp - 1) & 0xFF
    m.pc = nmivec

def correr(mq, pasos, soltar_en=None, tecla=None):
    m = mq.mpu
    for n in range(pasos):
        if soltar_en is not None and n == soltar_en and tecla:
            mq.teclas.discard(tecla)
        if n % 17000 == 0 and n and not (m.p & 0x04):
            mq.irq()
        m.step()

def main():
    ok = True

    # RUN/STOP rompe un bucle infinito -> "BREAK IN 10" y READY
    mq = Maquina()
    mq.teclear(b"10 GOTO 10\rRUN\r", 50_000_000)
    mq.teclas.add((7, 7))
    correr(mq, 5_000_000)
    mq.teclas.discard((7, 7))
    correr(mq, 2_000_000)
    pant = mq.pantalla()
    ok &= caso("RUN/STOP rompe el bucle (BREAK)",
               any("BREAK" in f for f in pant))

    # RUN/STOP-RESTORE (NMI con STOP): warm start, programa intacto, READY
    mq = Maquina()
    mq.teclear(b"10 PRINT 42\r", 35_000_000)
    prog0 = bytes(mq.mem[0x0801:0x0810])
    mq.teclas.add((7, 7))
    disparar_nmi(mq)
    correr(mq, 5_000_000, soltar_en=300_000, tecla=(7, 7))
    ok &= caso("RUN/STOP-RESTORE: programa intacto",
               prog0 == bytes(mq.mem[0x0801:0x0810]))
    ok &= caso("RUN/STOP-RESTORE: vuelve a READY",
               any("READY" in f for f in mq.pantalla()))

    # NMI espuria (RESTORE sin STOP): no rompe ni altera el programa
    mq = Maquina()
    mq.teclear(b"10 PRINT 42\r", 35_000_000)
    prog0 = bytes(mq.mem[0x0801:0x0810])
    disparar_nmi(mq)
    correr(mq, 800_000)
    ok &= caso("NMI espuria no altera el programa",
               prog0 == bytes(mq.mem[0x0801:0x0810]))

    # Ejecucion normal sin STOP: READY sin BREAK falso
    mq = Maquina()
    mq.teclear(b"10 PRINT 1\rRUN\r", 45_000_000)
    pant = mq.pantalla()
    ok &= caso("RUN normal no produce BREAK falso",
               any("READY" in f for f in pant) and
               not any("BREAK" in f for f in pant))

    # Bucle infinito largo SIN tecla: no debe romper (race IRQ/KSTOP)
    mq = Maquina()
    mq.teclear(b"10 GOTO 10\rRUN\r", 50_000_000)
    m = mq.mpu
    for n in range(9_000_000):
        if n % 17000 == 0 and n and not (m.p & 0x04):
            mq.irq()
        m.step()
    ok &= caso("bucle infinito no rompe solo (sin race)",
               not any("BREAK" in f for f in mq.pantalla()))

    sys.exit(0 if ok else 1)

if __name__ == "__main__":
    main()
