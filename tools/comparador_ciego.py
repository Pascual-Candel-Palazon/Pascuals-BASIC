#!/usr/bin/env python3
# Comparador ciego de no-similitud.
#
# Compara un binario PROPIO contra uno de REFERENCIA (p. ej. la ROM original
# que trae VICE) y solo imprime METRICAS y posiciones en el binario PROPIO.
# Nunca imprime bytes, opcodes ni direcciones del binario de referencia: quien
# lo ejecuta no ve su contenido. Ver docs/AUDITORIA_SIMILITUD.md.
#
# Este repositorio NO incluye ninguna ROM de Commodore. Las rutas a las de
# VICE se pasan por linea de comandos.
#
# Uso:
#   python3 tools/comparador_ciego.py --vice RUTA_A_VICE
#        [--kernal bin/kernal_c64.bin] [--basic bin/basic_c64.bin]
#        [--listado build/rom_listado.txt]
# Requiere py65 (tabla de longitudes de instruccion).
import sys, re, random

MINLEN = 8          # coincidencia minima en bytes a considerar
MINOPS = 10         # coincidencia minima en opcodes (operandos ignorados)

# longitud de instruccion 6502 por opcode, desde la tabla de py65
# (opcodes no documentados = 1 byte)
from py65.devices.mpu6502 import MPU as _MPU
_ML = {'imp': 1, 'acc': 1, 'imm': 2, 'zpg': 2, 'zpx': 2, 'zpy': 2, 'inx': 2,
       'iny': 2, 'rel': 2, 'abs': 3, 'abx': 3, 'aby': 3, 'ind': 3}
_T = _MPU().disassemble
LEN = [_ML.get(_T[op][1], 1) if _T[op][0] != '???' else 1 for op in range(256)]


def opstream(d):
    ops, pos, i = [], [], 0
    while i < len(d):
        ops.append(d[i]); pos.append(i)
        i += LEN[d[i]]
    return ops, pos


def maximal_matches(a, b, k):
    # coincidencias maximales de longitud >= k (secuencias genericas)
    idx = {}
    for j in range(len(b) - k + 1):
        idx.setdefault(tuple(b[j:j+k]), []).append(j)
    best = {}
    for i in range(len(a) - k + 1):
        for j in idx.get(tuple(a[i:i+k]), ()):
            if i > 0 and j > 0 and a[i-1] == b[j-1]:
                continue  # no es inicio maximal
            n = k
            while i+n < len(a) and j+n < len(b) and a[i+n] == b[j+n]:
                n += 1
            if n > best.get(i, 0):
                best[i] = n
    # fusionar solapes sobre el eje PROPIO
    runs = sorted(best.items())
    merged = []
    for s, n in runs:
        if merged and s < merged[-1][0] + merged[-1][1]:
            ps, pn = merged[-1]
            merged[-1] = (ps, max(pn, s + n - ps))
        else:
            merged.append((s, n))
    return merged


def labels(listado):
    lab = []
    if not listado:
        return lab
    rx = re.compile(r'^([A-Za-z_][A-Za-z0-9_]*):')
    for line in open(listado, encoding='latin-1'):
        if len(line) > 24 and re.match(r'^[0-9A-F]{6}\s', line):
            m = rx.match(line[24:])
            if m:
                lab.append((int(line[:6], 16), m.group(1)))
    lab.sort()
    return lab


def label_at(lab, addr):
    name = '?'
    for a, n in lab:
        if a <= addr:
            name = n
        else:
            break
    return name


def kind(seg):
    if len(set(seg)) == 1:
        return 'relleno'
    txt = sum(1 for c in seg if 0x20 <= c <= 0x5F or 0xC1 <= c <= 0xDA)
    if txt >= 0.8 * len(seg):
        return 'TEXTO'
    return 'codigo/datos'


def informe(prop, base_p, ref, lab, titulo, detalle=True):
    print('=' * 72)
    print(titulo)
    # 1) misma direccion
    n = min(len(prop), len(ref))
    eq = sum(1 for i in range(n) if prop[i] == ref[i])
    eqnf = sum(1 for i in range(n) if prop[i] == ref[i] and prop[i] not in (0x00, 0xFF))
    print('  bytes iguales en la misma direccion: %d/%d (%.1f%%); sin $00/$FF: %d'
          % (eq, n, 100.0*eq/n, eqnf))
    # 2) secuencias de bytes comunes en cualquier posicion
    m = maximal_matches(list(prop), list(ref), MINLEN)
    m = [(s, l) for s, l in m if kind(prop[s:s+l]) != 'relleno']
    cub = sum(l for s, l in m)
    largo = max((l for s, l in m), default=0)
    buck = {b: sum(1 for s, l in m if l >= b) for b in (8, 12, 16, 24, 32, 64)}
    print('  runs de bytes comunes >=%d: %d  (cubren %d bytes = %.1f%% del propio); max=%d'
          % (MINLEN, len(m), cub, 100.0*cub/len(prop), largo))
    print('    por longitud: ' + '  '.join('>=%d:%d' % (b, c) for b, c in buck.items()))
    # 3) secuencias de OPCODES comunes (operandos ignorados: detecta codigo
    #    copiado y reubicado)
    po, pp = opstream(prop)
    ro, _ = opstream(ref)
    mo = maximal_matches(po, ro, MINOPS)
    # descartar runs de opcodes que en el PROPIO son relleno ($00/$FF)
    mo = [(s, l) for s, l in mo if len(set(po[s:s+l])) > 1]
    lo = max((l for s, l in mo), default=0)
    def grams(o, k=6):
        return set(tuple(o[i:i+k]) for i in range(len(o)-k+1))
    gp, gr = grams(po), grams(ro)
    jac = len(gp & gr) / max(1, len(gp | gr))
    print('  runs de opcodes comunes >=%d instr: %d; max=%d instr; Jaccard 6-gramas=%.3f'
          % (MINOPS, len(mo), lo, jac))
    if detalle:
        top = sorted(m, key=lambda x: -x[1])[:12]
        if top:
            print('  mayores runs de BYTES (posicion en el PROPIO):')
        for s, l in top:
            print('    $%04X len=%3d %-12s %s' % (base_p+s, l, kind(prop[s:s+l]),
                                                label_at(lab, base_p+s)))
        topo = sorted(mo, key=lambda x: -x[1])[:12]
        if topo:
            print('  mayores runs de OPCODES (posicion en el PROPIO):')
        for s, l in topo:
            a = base_p + pp[s]
            print('    $%04X len=%3d instr  %s' % (a, l, label_at(lab, a)))
    return len(m), largo, len(mo), lo, jac


def kernal_start(lab):
    for a, n in lab:
        if n == 'KRESET':
            return a
    return 0xE200


def jaccard_ops(a, b, k=6):
    oa, _ = opstream(a)
    ob, _ = opstream(b)
    ga = set(tuple(oa[i:i+k]) for i in range(len(oa)-k+1))
    gb = set(tuple(ob[i:i+k]) for i in range(len(ob)-k+1))
    return len(ga & gb) / max(1, len(ga | gb))


def resumen(a, b, nombre):
    m = [(s, l) for s, l in maximal_matches(list(a), list(b), MINLEN)
         if kind(a[s:s+l]) != 'relleno']
    cub = sum(l for s, l in m)
    print('  %-50s Jaccard=%.3f  bytes en runs>=%d: %5d (%4.1f%%)  max=%d'
          % (nombre, jaccard_ops(a, b), MINLEN, cub, 100.0*cub/len(a),
             max([l for s, l in m] or [0])))


def main():
    import argparse, os
    ap = argparse.ArgumentParser()
    ap.add_argument('--vice', required=True, help='directorio de VICE (con C64/, VIC20/, DRIVES/)')
    ap.add_argument('--kernal', default='bin/kernal_c64.bin')
    ap.add_argument('--basic', default='bin/basic_c64.bin')
    ap.add_argument('--listado', default='build/rom_listado.txt')
    a = ap.parse_args()
    R = lambda p: open(os.path.join(a.vice, p), 'rb').read()
    OK, OB = open(a.kernal, 'rb').read(), open(a.basic, 'rb').read()
    lab = labels(a.listado if os.path.exists(a.listado) else None)
    ks = kernal_start(lab) - 0xE000
    CK = {r: R('C64/kernal-901227-0%d.bin' % r) for r in (1, 2, 3)}
    CB = R('C64/basic-901226-01.bin')
    VK = R('VIC20/kernal.901486-07.bin')
    D41 = R('DRIVES/dos1541-325302-01+901229-05.bin')

    print('### 1. KERNAL propio contra el KERNAL de Commodore (tres revisiones)')
    informe(OK, 0xE000, CK[3], lab, 'KERNAL propio vs C64 KERNAL 901227-03')
    for r in (2, 1):
        informe(OK, 0xE000, CK[r], lab, 'KERNAL propio vs C64 KERNAL 901227-0%d' % r, detalle=False)

    print()
    print('### 2. Tabla comparativa (KERNAL propio sin la cola del BASIC de Microsoft)')
    K = OK[ks:]
    resumen(K, CK[3], 'propio vs C64 KERNAL')
    resumen(K, VK, 'propio vs VIC-20 KERNAL')
    resumen(K, D41, 'propio vs DOS 1541 (codigo independiente)')
    resumen(CK[3][0x500:], D41, 'C64 KERNAL vs DOS 1541 (linea base)')
    resumen(VK, CK[3][0x500:], 'VIC-20 vs C64 KERNAL (parentesco conocido)')
    resumen(OB, CB, 'BASIC propio vs C64 BASIC (ambos MS BASIC, legitimo)')

    print()
    print('### 3. Todas las coincidencias de bytes >=%d (posicion en el PROPIO)' % MINLEN)
    m = [(s, l) for s, l in maximal_matches(list(OK), list(CK[3]), MINLEN)
         if kind(OK[s:s+l]) != 'relleno']
    for s, l in m:
        ad = 0xE000 + s
        zona = ('cola BASIC-MS' if s < ks else
                'tabla saltos' if ad >= 0xFF81 else 'KERNAL')
        print('  $%04X len=%3d %-12s %-14s %s' % (ad, l, kind(OK[s:s+l]), zona, label_at(lab, ad)))

    print()
    print('### 4. Control positivo sintetico: injerto de 48 bytes copiados')
    rnd = random.Random(64)
    hits = 0
    for t in range(10):
        src, dst = rnd.randrange(0x300, 0x1E00), rnd.randrange(0x300, 0x1E00)
        inj = bytearray(OK)
        inj[dst:dst+48] = CK[3][src:src+48]
        mm = maximal_matches(list(inj), list(CK[3]), MINLEN)
        hits += any(s <= dst and s + l >= dst + 48 for s, l in mm)
    print('  detectado %d/10 veces' % hits)


if __name__ == '__main__':
    main()
