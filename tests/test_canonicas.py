"""Contrato de las direcciones canonicas de interrupcion y reset (tier-3).

Programas y juegos del C64 saltan a direcciones internas documentadas del
KERNAL (no a la tabla de saltos): encadenan su IRQ con JMP $EA31 o salen
por $EA81, instalan su NMI en $0318 esperando solo la trama de la CPU en
la pila, y reinician con SYS 64738. Direcciones y semantica: interfaz
publicada (mapas de memoria publicos, nivel A/B de docs/PROCEDENCIA.md).
"""
import sys
from arnes import Maquina, imagen

def caso(nombre, cond):
    print(("OK  " if cond else "FALLO ") + nombre)
    return cond

def w(img, a):
    return img[a] | (img[a + 1] << 8)

def empujar_trama(mq, b_flag=False):
    m = mq.mpu
    p = (m.p | 0x10) if b_flag else (m.p & ~0x10)
    mq.mem.write(0x0100 + m.sp, [(m.pc >> 8) & 0xFF]); m.sp = (m.sp - 1) & 0xFF
    mq.mem.write(0x0100 + m.sp, [m.pc & 0xFF]);        m.sp = (m.sp - 1) & 0xFF
    mq.mem.write(0x0100 + m.sp, [p]);                  m.sp = (m.sp - 1) & 0xFF
    m.p |= 0x04

def nmi(mq, img):
    empujar_trama(mq)
    mq.mpu.pc = w(img, 0xFFFA)

def irq(mq, img):
    if mq.mpu.p & 0x04:
        return False
    empujar_trama(mq)
    mq.mpu.pc = w(img, 0xFFFE)
    return True

def maquina_lista():
    mq = Maquina()
    mq.teclear(b"", 3_000_000)
    return mq

def bucle_en(mq, a=0xC200, x=0x5A, y=0xA5, acc=0x3C, sp=0xF0):
    """CPU parada en un bucle JMP * con registros conocidos."""
    mq.mem.write(0xC200, [0x4C, 0x00, 0xC2])
    m = mq.mpu
    m.pc, m.a, m.x, m.y, m.sp = 0xC200, acc, x, y, sp
    m.p &= ~0x04   # I=0

def correr(mq, pasos):
    for _ in range(pasos):
        mq.mpu.step()

def regs_intactos(mq):
    m = mq.mpu
    return (m.pc in (0xC200, 0xC201, 0xC202) and m.a == 0x3C and m.x == 0x5A
            and m.y == 0xA5 and m.sp == 0xF0)

def main():
    ok = True
    img = imagen()

    # --- vectores hardware ---
    ok &= caso("NMI $FFFA -> $FE43", w(img, 0xFFFA) == 0xFE43)
    ok &= caso("RESET $FFFC -> $FCE2", w(img, 0xFFFC) == 0xFCE2)
    ok &= caso("IRQ $FFFE -> $FF48", w(img, 0xFFFE) == 0xFF48)

    # --- vectores RAM por defecto tras el arranque ---
    mq = maquina_lista()
    ok &= caso("$0314 (CINV) = $EA31", w(mq.mem, 0x0314) == 0xEA31)
    ok &= caso("$0316 (CBINV) = $FE66", w(mq.mem, 0x0316) == 0xFE66)
    ok &= caso("$0318 (NMINV) = $FE47", w(mq.mem, 0x0318) == 0xFE47)

    # --- contrato $0318: el manejador de usuario ve SOLO la trama de la
    #     CPU (3 bytes) y su RTI vuelve con todo intacto ---
    mq = maquina_lista()
    # STX $C082 / TSX / STX $C080 / LDX $C082 / RTI (X se conserva)
    mq.mem.write(0xC000, [0x8E, 0x82, 0xC0, 0xBA, 0x8E, 0x80, 0xC0,
                          0xAE, 0x82, 0xC0, 0x40])
    mq.mem.write(0x0318, [0x00, 0xC0])
    bucle_en(mq)
    nmi(mq, img)
    correr(mq, 200)
    ok &= caso("NMI de usuario: SP a la entrada = $ED (solo PC+P apilados)",
               mq.mem[0xC080] == 0xED)
    ok &= caso("NMI de usuario: RTI vuelve con A/X/Y/SP intactos",
               regs_intactos(mq))

    # --- NMI por defecto (sin STOP ni cartucho): preserva todo ---
    mq = maquina_lista()
    bucle_en(mq)
    nmi(mq, img)
    correr(mq, 3000)
    ok &= caso("NMI espuria por defecto: A/X/Y/SP intactos", regs_intactos(mq))

    # --- $FEBC: salida comun (PLA/TAY/PLA/TAX/PLA/RTI) ---
    mq = maquina_lista()
    # NMI de usuario que apila A/X/Y, los machaca y sale por $FEBC
    mq.mem.write(0xC000, [0x48, 0x8A, 0x48, 0x98, 0x48,       # PHA TXA PHA TYA PHA
                          0xA9, 0x00, 0xAA, 0xA8,             # LDA #0 TAX TAY
                          0x4C, 0xBC, 0xFE])                  # JMP $FEBC
    mq.mem.write(0x0318, [0x00, 0xC0])
    bucle_en(mq)
    nmi(mq, img)
    correr(mq, 200)
    ok &= caso("JMP $FEBC restaura A/X/Y y vuelve", regs_intactos(mq))

    # --- IRQ encadenada: usuario cuenta en $C081 y sigue por $EA31 ---
    mq = maquina_lista()
    mq.mem.write(0xC000, [0xEE, 0x81, 0xC0, 0x4C, 0x31, 0xEA])  # INC $C081 / JMP $EA31
    mq.mem.write(0xC081, [0])
    mq.mem.write(0x0314, [0x00, 0xC0])
    t0 = mq.mem[0xA2]
    bucle_en(mq)
    for _ in range(5):
        irq(mq, img)
        correr(mq, 3000)
    ok &= caso("IRQ de usuario se ejecuta (5 veces)", mq.mem[0xC081] == 5)
    ok &= caso("JMP $EA31 sigue con el reloj (jiffy avanza 5)",
               (mq.mem[0xA2] - t0) & 0xFF == 5)
    ok &= caso("JMP $EA31: vuelve con A/X/Y/SP intactos", regs_intactos(mq))

    # --- IRQ que sale por $EA81 sin pasar por el KERNAL ---
    mq = maquina_lista()
    mq.mem.write(0xC000, [0xAD, 0x0D, 0xDC, 0xA9, 0x00,        # LDA $DC0D / LDA #0
                          0x4C, 0x81, 0xEA])                  # JMP $EA81
    mq.mem.write(0x0314, [0x00, 0xC0])
    t0 = mq.mem[0xA2]
    bucle_en(mq)
    irq(mq, img)
    correr(mq, 300)
    ok &= caso("JMP $EA81 restaura A/X/Y y vuelve", regs_intactos(mq))
    ok &= caso("JMP $EA81 no avanza el reloj", mq.mem[0xA2] == t0)

    # --- BRK por defecto ($FE66): arranque en caliente, programa intacto.
    #     Tras BRK NO debe seguir ejecutandose lo que hay detras ---
    mq = Maquina()
    mq.teclear(b'10 PRINT"BRKOK"\r', 30_000_000)
    # $C000: BRK / $EA (firma) / LDA #$77 / STA $C090 / RTS
    mq.mem.write(0xC000, [0x00, 0xEA, 0xA9, 0x77, 0x8D, 0x90, 0xC0, 0x60])
    mq.mem.write(0xC090, [0])
    mq.teclear(b"SYS49152\r", 30_000_000)
    ok &= caso("BRK por defecto no continua tras el BRK",
               mq.mem[0xC090] != 0x77)
    mq.teclear(b"RUN\r", 30_000_000)
    ok &= caso("BRK por defecto vuelve a READY con el programa intacto",
               any(f.strip() == "BRKOK" for f in mq.pantalla()))

    # --- SYS 64738: arranque en frio ---
    mq = Maquina()
    mq.teclear(b'10 PRINT"X"\rSYS64738\r', 80_000_000)
    mq.teclear(b"LIST\r", 30_000_000)
    p = mq.pantalla()
    ok &= caso("SYS 64738 rearranca (pantalla limpia y banner de nuevo)",
               any("PASCUAL'S BASIC" in f for f in p)
               and not any("SYS64738" in f for f in p))
    ok &= caso("SYS 64738 borra el programa (LIST vacio)",
               not any(f.startswith('10 PRINT') for f in p[-10:]))

    sys.exit(0 if ok else 1)

if __name__ == "__main__":
    main()
