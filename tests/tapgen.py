"""Formato de cinta CBM en Python, independiente del KERNAL: genera cintas
y decodifica grabaciones para comprobar el formato desde fuera.

Formato (interfaz publica, nivel A/B de docs/PROCEDENCIA.md):
- Tres pulsos: corto (S), medio (M) y largo (L); nominales 384, 528 y 688
  ciclos (bytes $30, $42 y $56 de un TAP).
- Byte: marcador [L,M], 8 bits de menor a mayor (0 = [S,M], 1 = [M,S]) y
  bit de comprobacion = 1 XOR (XOR de los 8 bits).
- Bloque: guia de pulsos cortos, cuenta atras $89..$81 (copia 1) o
  $09..$01 (copia 2), datos, checksum (XOR de los datos) y marcador de fin
  [L,S]. Cada bloque va dos veces; tras la copia 2, 78 pulsos cortos.
- Fichero de programa: bloque de cabecera de 192 bytes (tipo, inicio,
  fin+1, nombre de 16, relleno $20) con guia de $6A00 pulsos, y bloque de
  datos con guia de $1500. Entre copias, 79 pulsos cortos.
"""
import random

S, M, L = 384, 528, 688


def _byte(v):
    p = [L, M]
    chk = 1
    for k in range(8):
        b = (v >> k) & 1
        chk ^= b
        p += [M, S] if b else [S, M]
    p += [M, S] if chk else [S, M]
    return p


def bloque(datos, guia, guia2=79):
    """Pulsos de un bloque completo (dos copias y cola)."""
    p = []
    for copia, g in ((0x80, guia), (0x00, guia2)):
        p += [S] * g
        for c in range(9, 0, -1):
            p += _byte(c | copia)
        x = 0
        for v in datos:
            p += _byte(v)
            x ^= v
        p += _byte(x) + [L, S]
    return p + [S] * 78


def cabecera(nombre, ini, fin, tipo=1):
    n = (bytes(nombre) + b" " * 16)[:16]
    h = bytes([tipo, ini & 0xFF, ini >> 8, fin & 0xFF, fin >> 8]) + n
    return h + b" " * (192 - len(h))


def programa(nombre, ini, datos, tipo=1):
    """Pulsos de un fichero de programa completo."""
    fin = ini + len(datos)
    return (bloque(cabecera(nombre, ini, fin, tipo), 0x6A00)
            + bloque(bytes(datos), 0x1500))


def instantes(pulsos, velocidad=1.0, jitter=0, semilla=1, inicio=0):
    """Pulsos -> instantes (ciclos) para el arnes; velocidad > 1 = cinta
    rapida (pulsos mas cortos); jitter = ruido uniforme en ciclos."""
    r = random.Random(semilla)
    t, out = inicio, [inicio]
    for d in pulsos:
        t += max(1, round(d / velocidad + r.uniform(-jitter, jitter)))
        out.append(t)
    return out


def decodificar(instantes_):
    """Instantes -> lista de bloques [(guia, bytes, checksum_ok, fin_ok)].
    Umbrales fijos entre los nominales."""
    d = [b - a for a, b in zip(instantes_, instantes_[1:])]
    sym = ['S' if x < 456 else 'M' if x < 608 else 'L' if x < 1500 else 'P'
           for x in d]
    out, i, n = [], 0, len(sym)
    while i < n:
        g = 0
        while i < n and sym[i] == 'S':
            g += 1
            i += 1
        bs = []
        while i + 20 <= n and sym[i] == 'L' and sym[i + 1] == 'M':
            v, chk, ok = 0, 1, True
            for k in range(9):
                par = sym[i + 2 + 2 * k:i + 4 + 2 * k]
                b = {('S', 'M'): 0, ('M', 'S'): 1}.get(tuple(par))
                if b is None:
                    ok = False
                    break
                if k < 8:
                    v |= b << k
                    chk ^= b
                elif b != chk:
                    ok = False
            if not ok:
                break
            bs.append(v)
            i += 20
        fin = sym[i:i + 2] == ['L', 'S']
        if bs:
            x = 0
            for v in bs[9:-1]:
                x ^= v
            out.append((g, bytes(bs), len(bs) > 10 and x == bs[-1], fin))
            i += 2 if fin else 0
        elif not g:
            i += 1
    return out
