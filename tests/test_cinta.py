"""Datasette de extremo a extremo con el arnes de tests/cinta.py.

SAVE por $FFD8 graba los flancos que genera el KERNAL; LOAD/VERIFY por
$FFD5 los reproduce como eventos FLAG del CIA1. Ademas se corrompen
pulsos a proposito para probar la fusion de las dos copias del formato
CBM: un byte malo en una sola copia se recupera; el mismo byte malo en
las dos no.

Ademas se comprueba el formato desde fuera con tests/tapgen.py (escrito
aparte del KERNAL, desde el formato publicado): lo que graba SAVE se
decodifica en Python, y LOAD lee cintas generadas en Python, tambien con
la velocidad desviada (-25 % y +40 %) y ruido en los pulsos.
"""
import sys
from cinta import Datasette
from arnes import etiqueta
import tapgen

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

def cargar(cinta, nombre=b"PRUEBA", verify=False, preparar=None, sa=1,
           destino=0x0801):
    e = Datasette()
    e.arrancar()
    if preparar:
        preparar(e)
    r, st = e.load(nombre, cinta, verify=verify, sa=sa, destino=destino)
    return e, r, st

def main():
    ok = True

    d = Datasette()
    d.arrancar()
    d.mq.mem.write(INI, DATOS)
    # el manejador nunca debe encontrar vacia la cola de pulsos antes del
    # final: si pasa, el timer repite la mitad anterior y el pulso sale mal
    vacia, vaciados = etiqueta("wh_vacia"), []
    paso0 = d.paso
    def paso():
        if d.mq.mpu.pc == vacia and d.mq.mem[0x038C] == 0:   # wdone = 0
            vaciados.append(d.mq.mpu.processorCycles)
        paso0()
    d.paso = paso
    r, flancos = d.save(b"PRUEBA", INI, FIN)
    d.paso = paso0
    ok &= caso("SAVE a cinta termina sin error", r is not None and r['c'] == 0)
    ok &= caso("SAVE: la cola de pulsos nunca se vacia antes del final",
               vacia is not None and not vaciados)

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

    # --- formato visto desde fuera (decodificador de tapgen) ---
    bl = tapgen.decodificar(flancos)
    ok &= caso("formato: 4 bloques con checksum y marcador de fin",
               len(bl) == 4 and all(b[2] and b[3] for b in bl))
    if len(bl) == 4:
        ok &= caso("formato: guias $6A00 / 79 / >= $1500 / 79",
                   bl[0][0] >= 0x6A00 and bl[1][0] == 79
                   and bl[2][0] >= 0x1500 and bl[3][0] == 79)
        cab = tapgen.cabecera(b"PRUEBA", INI, FIN, tipo=3)
        ok &= caso("formato: cabecera de 192 bytes (tipo 3 con SA=1, relleno $20)",
                   bl[0][1][9:-1] == cab and bl[1][1][9:-1] == cab)
        ok &= caso("formato: cuenta atras $89..$81 y $09..$01",
                   bl[0][1][:9] == bytes(range(0x89, 0x80, -1))
                   and bl[1][1][:9] == bytes(range(9, 0, -1)))
        ok &= caso("formato: bloque de datos = DATOS",
                   bl[2][1][9:-1] == bytes(DATOS) and bl[3][1][9:-1] == bytes(DATOS))
    grupos = {'S': [], 'M': [], 'L': []}
    for x in iv:
        k = 'S' if x < 456 else 'M' if x < 608 else 'L' if x < 1500 else None
        if k:
            grupos[k].append(x)
    nominal = {'S': tapgen.S, 'M': tapgen.M, 'L': tapgen.L}
    # media exacta; cada pulso +-8 (un byte de TAP): el flanco sale de una
    # IRQ y su latencia depende de la instruccion en curso (hasta 7 ciclos)
    ok &= caso("pulsos S/M/L de 384/528/688 ciclos de subida a subida "
               "(media +-1,5; cada uno +-8)",
               all(g and abs(sum(g) / len(g) - nominal[k]) <= 1.5
                   and max(abs(x - nominal[k]) for x in g) <= 8
                   for k, g in grupos.items()))

    # --- LOAD de cintas generadas por tapgen ---
    PROG = bytes((i * 13 + 5) & 0xFF for i in range(100))
    def prog_ok(e, r, base):
        return (r is not None and r['c'] == 0
                and bytes(e.mq.mem[base:base + len(PROG)]) == bytes(PROG)
                and (r['x'] | r['y'] << 8) == base + len(PROG))
    gen = tapgen.instantes(tapgen.programa(b"GEN", 0x2000, PROG))
    e, r, st = cargar(gen, nombre=b"GEN", sa=0, destino=0x3000)
    ok &= caso("LOAD de cinta generada (tipo 1, SA=0): se reubica al destino",
               prog_ok(e, r, 0x3000))
    for vel, txt in ((1.40, "un 40 % rapida"), (0.75, "un 25 % lenta")):
        gen = tapgen.instantes(tapgen.programa(b"GEN", 0x2000, PROG),
                               velocidad=vel, jitter=12, semilla=int(vel * 100))
        e, r, st = cargar(gen, nombre=b"GEN", sa=1)
        ok &= caso("LOAD de cinta generada " + txt + " con ruido de +-12 ciclos",
                   prog_ok(e, r, 0x2000))
    # modo directo (mensajes FOUND/LOADING) y pausa de 0,3 s entre cabecera
    # y datos, como graba un C64: CHROUT enmascara IRQ y la pausa hace dar
    # la vuelta al timer; el lector no debe perder la sincronia
    cab = tapgen.bloque(tapgen.cabecera(b"GEN", 0x2000, 0x2000 + len(PROG)), 0x6A00)
    dat = tapgen.bloque(PROG, 0x1500)
    gen = tapgen.instantes(cab + [327685] + dat)
    e, r, st = cargar(gen, nombre=b"GEN", sa=1,
                      preparar=lambda m: m.mq.mem.write(0x9D, [0x80]))
    ok &= caso("LOAD en modo directo con pausa entre cabecera y datos",
               prog_ok(e, r, 0x2000))
    gen = tapgen.instantes(tapgen.programa(b"ABS", 0x2000, PROG, tipo=3))
    e, r, st = cargar(gen, nombre=b"ABS", sa=0, destino=0x3000)
    ok &= caso("LOAD tipo 3 con SA=0: va a la direccion de la cabecera",
               prog_ok(e, r, 0x2000))
    fin_cinta = tapgen.bloque(tapgen.cabecera(b"", 0, 0, tipo=5), 0x6A00)
    gen = tapgen.instantes(fin_cinta + tapgen.programa(b"GEN", 0x2000, PROG))
    e, r, st = cargar(gen, nombre=b"GEN", sa=1)
    ok &= caso("cabecera tipo 5 (fin de cinta): FILE NOT FOUND sin seguir",
               r is not None and r['c'] == 1 and r['a'] == 4)

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
