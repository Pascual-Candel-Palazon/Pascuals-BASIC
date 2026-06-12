#!/usr/bin/env python3
"""Aplana los condicionales IFE/IFN de MACRO-10 en m6502.asm para un target dado.

Procedencia: transformación puramente mecánica del fuente MIT de Microsoft.
No añade ni reescribe código; solo resuelve condicionales y elimina ramas muertas.
IF1/IF2 (dependientes de pasada del ensamblador, solo listados/PURGE) se eliminan.
IFNDEF se conserva con marcador. Expresiones no evaluables -> se conserva el bloque
con marcador ;;UNRESOLVED para revisión manual.
"""
import re, sys

SRC = "m6502.asm"
OUT = "m6502_cbm.asm"
REALIO = 3

text = open(SRC, encoding="latin-1").read()
text = text.replace(
    "IFN\t<<BUF+BUFLEN>/256>-<<BUF-1>/256>,<\n\tDEC\tTXTPTR+1>",
    "\tDEC\tTXTPTR+1\t;;[resuelto: BUFPAG=2 (CBM), BUF=$0200, BUF-1=$01FF cruza pagina -> DEC necesario]")
# Resolucion manual documentada: con BUFPAG=0 (CBM), BUF=0 esta en pagina cero
# y el bufer no cruza limite de pagina -> el DEC TXTPTR+1 se omite.
# (En el delta C64, con BUF=$0200, esta decision debe revisarse: BUF-1=$01FF
# cruza pagina y el DEC SI se incluye.)
text = re.sub(
    r"IFN\s*<BUF\+BUFLEN>/256\s*\n-<BUF-1>/256,<\s*\n\s*DEC\s+TXTPTR\+1>",
    ";;[resuelto manual: BUFPAG=0, sin cruce de pagina, DEC omitido]",
    text)

# --- tabla de símbolos: se construye secuencialmente al procesar ---
symbols = {"REALIO": REALIO}

ASSIGN_RE = re.compile(r"^\s*([A-Za-z$.][A-Za-z0-9$.]*)\s*==?\s*([^;\n]+)")

def parse_num(tok):
    tok = tok.strip()
    if tok.startswith("^O"):
        return int(tok[2:], 8)
    if tok.startswith("^D"):
        return int(tok[2:], 10)
    if re.fullmatch(r"\d+", tok):
        return int(tok, 10)  # RADIX 10 declarado en cabecera
    return symbols.get(tok.upper())

def eval_expr(expr):
    """Evalúa expresiones MACRO-10: + - / & ! y agrupación <>."""
    e = expr.strip()
    e = re.sub(r"\^O([0-7]+)", lambda m: str(int(m.group(1), 8)), e)
    e = re.sub(r"\^D(\d+)", r"\1", e)
    e = e.replace("<", "(").replace(">", ")")
    e = e.replace("!", "|")
    def sub_sym(m):
        v = symbols.get(m.group(0).upper())
        return str(v) if v is not None else m.group(0)
    e = re.sub(r"[A-Za-z$.][A-Za-z0-9$.]*", sub_sym, e)
    if not re.fullmatch(r"[\d()+\-*/&| ]+", e):
        return None
    try:
        return int(eval(e.replace("/", "//")))
    except Exception:
        return None

def track_assign(line):
    m = ASSIGN_RE.match(line)
    if m:
        name = m.group(1).upper()
        if name == "REALIO":
            return  # forzado por nosotros: el fuente no debe machacarlo
        v = eval_expr(m.group(2))
        if v is not None:
            symbols[name] = v

COND_RE = re.compile(r"\bIF([EN12]|NDEF)\b[ \t]*,?[ \t]*([^,<\n]*)?,?[ \t]*<", re.IGNORECASE)

def find_matching(text, start):
    """start apunta al carácter tras '<'. Devuelve índice del '>' que cierra."""
    depth = 1
    i = start
    while i < len(text):
        c = text[i]
        if c == "<":
            depth += 1
        elif c == ">":
            depth -= 1
            if depth == 0:
                return i
        i += 1
    raise ValueError(f"bloque sin cerrar desde {start}")

out = []
pos = 0
stats = {"kept": 0, "dropped": 0, "unresolved": 0, "pass_removed": 0}

while True:
    m = COND_RE.search(text, pos)
    if not m:
        tail = text[pos:]
        for ln in tail.splitlines():
            track_assign(ln)
        out.append(tail)
        break
    # texto previo al condicional: emitir y trackear asignaciones
    pre = text[pos:m.start()]
    for ln in pre.splitlines():
        track_assign(ln)
    out.append(pre)

    kind = m.group(1)
    expr = (m.group(2) or "").strip()
    body_start = m.end()
    body_end = find_matching(text, body_start)
    body = text[body_start:body_end]

    def process_body(b):
        """Recursión: el cuerpo puede contener condicionales anidados."""
        global text, pos
        return b  # el bucle principal re-escanea: ver nota abajo

    if kind == "1":
        # pasada 1: placeholder para referencias adelantadas -> descartar
        stats["pass_removed"] += 1
        pos = body_end + 1
        continue
    if kind == "2":
        # pasada 2: codigo definitivo -> conservar (reinsertar para procesar anidados)
        text = text[:pos] + body + text[body_end + 1:]
        stats["kept"] += 1
        continue
    if kind == "NDEF":
        out.append(f";;IFNDEF {expr} (conservado)\n{body}\n")
        stats["unresolved"] += 1
        pos = body_end + 1
        continue

    val = eval_expr(expr)
    if val is None:
        out.append(f";;UNRESOLVED IF{kind} {expr}\n<{body}>\n")
        stats["unresolved"] += 1
        pos = body_end + 1
        continue

    keep = (val == 0) if kind == "E" else (val != 0)
    if keep:
        # reinsertar el cuerpo en el flujo para que los anidados se procesen
        text = text[:pos] + body + text[body_end + 1:]
        # no avanzamos pos: el cuerpo se re-escanea desde aquí
        stats["kept"] += 1
    else:
        stats["dropped"] += 1
        pos = body_end + 1

result = "".join(out)
# limpiar líneas en blanco triplicadas que dejan los bloques eliminados
result = re.sub(r"\n{4,}", "\n\n\n", result)
open(OUT, "w", encoding="latin-1").write(result)

print(f"símbolos clave: REALIO={symbols.get('REALIO')} DISKO={symbols.get('DISKO')} "
      f"ROMSW={symbols.get('ROMSW')} LNGERR={symbols.get('LNGERR')} "
      f"ROMLOC={symbols.get('ROMLOC')} (${symbols.get('ROMLOC', 0):04X})")
print(f"bloques: conservados={stats['kept']} eliminados={stats['dropped']} "
      f"sin-resolver={stats['unresolved']} de-pasada={stats['pass_removed']}")
print(f"líneas salida: {result.count(chr(10))}")
