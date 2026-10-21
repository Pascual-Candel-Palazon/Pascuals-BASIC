"""Datasette de extremo a extremo con el arnes de tests/cinta.py.

SAVE por $FFD8 graba los flancos que genera el KERNAL; LOAD/VERIFY por
$FFD5 los reproduce como eventos FLAG del CIA1. Ademas se corrompen
pulsos a proposito para probar la fusion de las dos copias del formato
CBM: un byte malo en una sola copia se recupera; el mismo byte malo en
las dos no.
"""
import sys
from cinta import Datasette

def caso(nombre, cond):
    print(("OK  " if cond else "FALLO ") + nombre)
    return cond

DATOS = [(i * 7 + 3) & 0xFF for i in range(64)]
INI, FIN = 0xC100, 0xC100 + len(DATOS)

def tiempos(intervalos):
    t, out = 0, [0]
    for d in intervalos:
        t += d
        out.append(t)
    return out

def intervalos(tiempos_):
    return [b - a for a, b in zip(tiempos_, tiempos_[1:])]

def clasificar(iv):
    # umbrales a medio camino entre los pulsos grabados (incluyen la latencia de IRQ)
    s = sorted(iv)
    corto = s[len(s) // 4]
    return ['S' if d < corto * 1.19 else 'M' if d < corto * 1.56 else 'L' for d in iv]

def segmentos(iv):
    """Indices de inicio de cada byte ([L,M] + 18 pulsos), agrupados por copia
    (cada copia termina con el marcador de fin [L,S])."""
    sym = clasificar(iv)
    segs, cur, i = [], [], 0
    while i < len(sym) - 1:
        if sym[i] == 'L' and sym[i + 1] == 'M':
            cur.append(i)
            i += 20
        elif sym[i] == 'L' and sym[i + 1] == 'S':
            if cur:
                segs.append(cur)
            cur = []
            i += 2
        else:
            i += 1
    if cur:
        segs.append(cur)
    return segs

def corromper(iv, inicio_byte):
    """Intercambia los dos semipulsos del primer bit: invierte ese bit y rompe
    la paridad del byte sin alterar la duracion total."""
    iv = list(iv)
    p = inicio_byte + 2
    iv[p], iv[p + 1] = iv[p + 1], iv[p]
    return iv

def cargar(cinta, nombre=b"PRUEBA", verify=False, preparar=None):
    e = Datasette()
    e.arrancar()
    if preparar:
        preparar(e)
    r, st = e.load(nombre, cinta, verify=verify)
    return e, r, st

def main():
    ok = True

    d = Datasette()
    d.arrancar()
    d.mq.mem.write(INI, DATOS)
    r, flancos = d.save(b"PRUEBA", INI, FIN)
    ok &= caso("SAVE a cinta termina sin error", r is not None and r['c'] == 0)

    iv = intervalos(flancos)
    segs = segmentos(iv)
    ok &= caso("la grabacion tiene 4 copias (cabecera x2, datos x2)", len(segs) == 4)

    e, r, st = cargar(flancos)
    ok &= caso("LOAD por nombre devuelve sin error", r is not None and r['c'] == 0)
    ok &= caso("LOAD: datos identicos", list(e.mq.mem[INI:FIN]) == DATOS)
    ok &= caso("LOAD: X/Y = fin+1", r is not None and (r['x'] | r['y'] << 8) == FIN)

    e, r, st = cargar(flancos, verify=True,
                      preparar=lambda m: m.mq.mem.write(INI, DATOS))
    ok &= caso("VERIFY igual: ST bit4 = 0", r is not None and not (st & 0x10))
    malos = list(DATOS); malos[10] ^= 0xFF
    e, r, st = cargar(flancos, verify=True,
                      preparar=lambda m: m.mq.mem.write(INI, malos))
    ok &= caso("VERIFY distinto: ST bit4 = 1", r is not None and bool(st & 0x10))

    if len(segs) == 4:
        k = 9 + 20                      # 9 bytes de sincronismo + byte 20 de datos
        c1 = corromper(iv, segs[2][k])
        e, r, st = cargar(tiempos(c1))
        ok &= caso("byte malo solo en la copia 1: se recupera",
                   r is not None and r['c'] == 0 and list(e.mq.mem[INI:FIN]) == DATOS)
        c2 = corromper(iv, segs[3][k])
        e, r, st = cargar(tiempos(c2))
        ok &= caso("byte malo solo en la copia 2: se usa la copia 1",
                   r is not None and r['c'] == 0 and list(e.mq.mem[INI:FIN]) == DATOS)
        cruz = corromper(corromper(iv, segs[2][k]), segs[3][k + 5])
        e, r, st = cargar(tiempos(cruz))
        ok &= caso("bytes malos distintos en cada copia: la fusion recupera",
                   r is not None and r['c'] == 0 and list(e.mq.mem[INI:FIN]) == DATOS)
        ambos = corromper(corromper(iv, segs[2][k]), segs[3][k])
        e, r, st = cargar(tiempos(ambos))
        ok &= caso("mismo byte malo en las dos copias: no se da por bueno",
                   r is None or r['c'] == 1 or list(e.mq.mem[INI:FIN]) != DATOS)

    # dos ficheros seguidos: LOAD por nombre salta el que no coincide
    d2 = Datasette()
    d2.arrancar()
    d2.mq.mem.write(INI, [0x11] * len(DATOS))
    _, f_a = d2.save(b"UNO", INI, FIN)
    d2.mq.mem.write(INI, DATOS)
    _, f_b = d2.save(b"DOS", INI, FIN)
    hueco = 600_000
    cinta = f_a + [f_a[-1] + hueco + t for t in f_b]
    e, r, st = cargar(cinta, nombre=b"DOS")
    ok &= caso("LOAD \"DOS\" salta \"UNO\" y carga el segundo",
               r is not None and r['c'] == 0 and list(e.mq.mem[INI:FIN]) == DATOS)

    sys.exit(0 if ok else 1)

if __name__ == "__main__":
    main()
