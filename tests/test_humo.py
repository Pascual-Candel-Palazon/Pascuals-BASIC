"""Humo: arranque bajo IRQs, banner, memoria, scroll y transparencia."""
import sys
from arnes import Maquina, etiqueta

def caso(nombre, cond):
    print(("OK  " if cond else "FALLO ") + nombre)
    return cond

def test_arranque():
    mq = Maquina()
    salida = []
    vec = mq.irqvec
    for n in range(4_000_000):
        if mq.mpu.pc == 0xFFD2:
            salida.append(mq.mpu.a)
        if n % 17000 == 0 and n:
            mq.irq()
        mq.mpu.step()
    txt = bytes(salida).decode("latin-1", "replace")
    return caso("banner bajo IRQs", "COMMODORE BASIC" in txt) & \
           caso("38911 BYTES FREE", "38911" in txt)

def test_scroll():
    kscroll = etiqueta("KSCROLL")
    if kscroll is None:
        print("AVISO: sin listado; omitido test de scroll")
        return True
    mq = Maquina()
    for f in range(25):
        mq.mem.write(0x0400 + f * 40, [f + 1] * 40)
    assert mq.subrutina(kscroll, 30000)
    err = sum(1 for f in range(24)
              if bytes(mq.mem[0x0400 + f*40:0x0400 + f*40 + 40]) != bytes([f+2]*40))
    limpia = bytes(mq.mem[0x0400 + 960:0x0400 + 1000]) == b"\x20" * 40
    return caso("scroll: 24 filas exactas", err == 0) & \
           caso("scroll: ultima fila en blanco", limpia)

def test_transparencia_irq():
    """Un IRQ no debe alterar registros ni RAM (salvo jiffy y pila)."""
    mq = Maquina()
    for _ in range(16999):
        mq.mpu.step()
    m = mq.mpu
    antes = (m.a, m.x, m.y, m.p, m.sp)
    ram0 = bytes(mq.mem[0:0x300])
    pc0 = m.pc
    mq.irq()
    for k in range(5000):
        m.step()
        if m.pc == pc0:
            break
    regs = (m.a, m.x, m.y, m.p, m.sp) == antes
    ram1 = bytes(mq.mem[0:0x300])
    difs = [i for i in range(0x300)
            if ram0[i] != ram1[i] and not (0xA0 <= i <= 0xA2)  # jiffy
            and not (0x0100 <= i <= 0x01FF)]                   # pila
    return caso("IRQ transparente: registros", regs) & \
           caso("IRQ transparente: RAM (salvo jiffy/pila)", not difs)

if __name__ == "__main__":
    ok = test_arranque() & test_scroll() & test_transparencia_irq()
    sys.exit(0 if ok else 1)
