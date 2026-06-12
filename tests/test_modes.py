"""Tests de modo inverso (CHR$(18)/146) y caso may/min (CHR$(14)/142)."""
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
