#!/usr/bin/env python3
"""Traductor MACRO-10 -> ca65 v2. Macros calcadas de los DEFINE originales del fuente."""
import re, sys
SRC, OUT = "m6502_cbm.asm", "basic_cbm.s"
C64 = True  # target: BASIC en $A000, continuacion en $E000

PRELUDE = r"""; ============================================================
; Prologo ca65 - macros transcritas 1:1 de los DEFINE del fuente
; MIT de Microsoft (lineas 77-149, 1030, 1166 del aplanado CBM).
; ============================================================
.feature string_escapes
.macro LDAI v
 lda #<(v)
.endmacro
.macro LDXI v
 ldx #<(v)
.endmacro
.macro LDYI v
 ldy #<(v)
.endmacro
.macro CMPI v
 cmp #<(v)
.endmacro
.macro CPXI v
 cpx #<(v)
.endmacro
.macro CPYI v
 cpy #<(v)
.endmacro
.macro ADCI v
 adc #<(v)
.endmacro
.macro SBCI v
 sbc #<(v)
.endmacro
.macro ANDI v
 and #<(v)
.endmacro
.macro ORAI v
 ora #<(v)
.endmacro
.macro EORI v
 eor #<(v)
.endmacro
.macro LDADY p
 lda (p),y
.endmacro
.macro STADY p
 sta (p),y
.endmacro
.macro ADCDY p
 adc (p),y
.endmacro
.macro SBCDY p
 sbc (p),y
.endmacro
.macro CMPDY p
 cmp (p),y
.endmacro
.macro JMPD p
 jmp (p)
.endmacro
.macro LDWD p
 lda p
 ldy 1+(p)
.endmacro
.macro STWD p
 sta p
 sty 1+(p)
.endmacro
.macro LDWDI v
 lda #<(v)
 ldy #>(v)
.endmacro
.macro LDWX p
 lda p
 ldx 1+(p)
.endmacro
.macro STWX p
 sta p
 stx 1+(p)
.endmacro
.macro LDWXI v
 lda #<(v)
 ldx #>(v)
.endmacro
.macro LDXY p
 ldx p
 ldy 1+(p)
.endmacro
.macro STXY p
 stx p
 sty 1+(p)
.endmacro
.macro LDXYI v
 ldx #<(v)
 ldy #>(v)
.endmacro
.macro PSHWD p
 lda 1+(p)
 pha
 lda p
 pha
.endmacro
.macro PULWD p
 pla
 sta p
 pla
 sta 1+(p)
.endmacro
.macro CLR p
 lda #0
 sta p
.endmacro
.macro COM p
 lda p
 eor #255
 sta p
.endmacro
.macro INCW p
 .local sk
 inc p
 bne sk
 inc 1+(p)
sk:
.endmacro
.macro JEQ t
 bne *+5
 jmp t
.endmacro
.macro JNE t
 beq *+5
 jmp t
.endmacro
.macro BCCA t
 bcc t
.endmacro
.macro BCSA t
 bcs t
.endmacro
.macro BEQA t
 beq t
.endmacro
.macro BNEA t
 bne t
.endmacro
.macro BMIA t
 bmi t
.endmacro
.macro BPLA t
 bpl t
.endmacro
.macro BVCA t
 bvc t
.endmacro
.macro BVSA t
 bvs t
.endmacro
.macro SKIP1
 .byte $24
.endmacro
.macro SKIP2
 .byte $2C
.endmacro
.macro ADR v
 .word v
.endmacro
.macro DT s
 .byte s
.endmacro
.macro DC s
 .repeat .strlen(s)-1, i
 .byte .strat(s,i)
 .endrepeat
 .byte .strat(s,.strlen(s)-1) | $80
.endmacro
.macro DCI s
 Q .set Q+1
 DC s
.endmacro
.macro DCE s
 Q .set Q+2
 DC s
.endmacro
.macro ACRLF
 .byte 13,10
.endmacro
.macro SYNCHK v
 lda #v
 jsr SYNCHR
.endmacro
; ============================================================
"""

text = open(SRC, encoding="latin-1").read()
lines = text.splitlines()

# --- pasada 1: contar asignaciones por simbolo ---
ASSIGN = re.compile(r"^\s*([A-Za-z$.][A-Za-z0-9$.]*)\s*(==|=)\s*([^;\n]*)")
counts = {}
for ln in lines:
    m = ASSIGN.match(ln)
    if m:
        counts[m.group(1)] = counts.get(m.group(1), 0) + 1
multi = {s for s, c in counts.items() if c > 1}

def fix_ident(s):
    colon = s.endswith(":")
    name = s[:-1] if colon else s
    name = name[:6]  # MACRO-10: solo 6 caracteres significativos
    name = name.replace("$", "S_").replace(".", "_")
    return name + (":" if colon else "")

def fix_expr(e):
    lits = []
    def stash(m):
        lits.append("'" + m.group(1) + "'")
        return "\x01" + str(len(lits) - 1) + "\x01"
    e = re.sub(r'"(.)"', stash, e)
    e = re.sub(r"\^O([0-7]+)", lambda m: str(int(m.group(1), 8)), e)
    e = re.sub(r"\^D(\d+)", r"\1", e)
    e = e.replace("<", "(").replace(">", ")")
    e = e.replace("!", "|")
    e = re.sub(r"(?<![\w])\.(?=\+|\-|\s|$)", "*", e)  # '.' = PC actual
    e = re.sub(r"[A-Za-z$.][A-Za-z0-9$.]*", lambda m: fix_ident(m.group(0)), e)
    e = re.sub("\x01(\\d+)\x01", lambda m: lits[int(m.group(1))], e)
    return e

def split_comment(line):
    inq = False
    for i, c in enumerate(line):
        if c == '"':
            inq = not inq
        elif c == ";" and not inq:
            return line[:i], line[i:]
    return line, ""


RADIX = [10]
def conv_bare_octal(e):
    def f(m):
        tok = m.group(0)
        if any(c in "89" for c in tok):
            return tok  # no puede ser octal: dejar y avisar fuera
        return str(int(tok, 8))
    return re.sub(r"(?<![\w$#.])\d+\b", f, e)

KNOWN = set("""ADC AND ASL BCC BCS BEQ BIT BMI BNE BPL BRK BVC BVS CLC CLD CLI CLV CMP CPX CPY
DEC DEX DEY EOR INC INX INY JMP JSR LDA LDX LDY LSR NOP ORA PHA PHP PLA PLP ROL ROR RTI RTS SBC SEC SED
SEI STA STX STY TAX TAY TSX TXA TXS TYA LDAI LDXI LDYI CMPI CPXI CPYI ADCI SBCI ANDI ORAI EORI LDADY
STADY ADCDY SBCDY CMPDY JMPD LDWD STWD LDWDI LDWX STWX LDWXI LDXY STXY LDXYI PSHWD PULWD CLR COM INCW
JEQ JNE BCCA BCSA BEQA BNEA BMIA BPLA BVCA BVSA SKIP1 SKIP2 ADR DT DC DCI DCE ACRLF SYNCHK""".split())
out = [PRELUDE, "Q .set 0\n"]
i = 0
warn = []
DROP = re.compile(r"^\s*(TITLE|SUBTTL|SEARCH|SALL|PAGE|XLIST|LIST|PRINTX|NLIST|PURGE|\.X?CREF)(?!:)\b")

while i < len(lines):
    raw = lines[i].replace("\f", "")
    line = raw.rstrip()
    s = line.strip()

    # bloques COMMENT <delim> ... <delim>
    m = re.match(r"^\s*COMMENT\s+(\S)", s)
    if m:
        delim = m.group(1)
        out.append("; [COMMENT]")
        i += 1
        while i < len(lines) and delim not in lines[i]:
            out.append("; " + lines[i].replace("\f", ""))
            i += 1
        out.append("; [/COMMENT]")
        i += 1
        continue

    # bloques DEFINE: saltar hasta cerrar <...> (sustituidos por el prologo)
    if re.match(r"^\s*DEFINE\b", s):
        depth = 0
        started = False
        while i < len(lines):
            for c in lines[i]:
                if c == "<":
                    depth += 1
                    started = True
                elif c == ">":
                    depth -= 1
            i += 1
            if started and depth <= 0:
                break
        out.append("; [DEFINE original sustituido por macro del prologo]")
        continue

    if not s:
        out.append("")
        i += 1
        continue
    mrad = re.match(r"^\s*RADIX\s+(\d+)", s)
    if mrad:
        RADIX[0] = int(mrad.group(1))
        out.append("; [m10] " + s)
        i += 1
        continue
    if DROP.match(s):
        out.append("; [m10] " + s)
        i += 1
        continue

    line = re.sub(r"^([A-Za-z$._][A-Za-z0-9$._]*):!", r"\1:", line)
    code, comment = split_comment(line)
    if not code.strip():
        out.append(line)
        i += 1
        continue

    m = re.match(r"^\s*ORG\s+(.*)$", code)
    if m:
        dest = fix_expr(m.group(1).strip())
        if C64 and dest == "0":
            dest = "3"
            comment = ";[C64] ZP desde $03: $00-$02 es el puerto del 6510 (USRPOK ahi destruia el banking) " + comment
        out.append(".org " + dest + "  " + comment)
        i += 1
        continue

    code = re.sub(r"^([A-Za-z$.][A-Za-z0-9$.]*)::",
                  lambda m: fix_ident(m.group(1)) + ":", code)

    if C64 and re.match(r"^ATN:", code):
        out.append("")
        out.append(".org $E000  ;[C64] continuacion del BASIC en ROM del KERNAL (como hizo Commodore)")
    mlab = re.match(r"^\s*([A-Za-z$._][A-Za-z0-9$._]*):\s*$", code)
    if mlab:
        out.append(fix_ident(mlab.group(1)) + ":  " + comment)
        i += 1
        continue
    m = ASSIGN.match(code)
    if m:
        name = fix_ident(m.group(1))
        op = ".set" if m.group(1) in multi else "="
        rhs = m.group(3).strip()
        if C64 and name == "ROMLOC":
            rhs = "40960"  ; comment = ";[C64] BASIC en $A000 " + comment
        if C64 and name == "RAMLOC":
            rhs = "2048"  ; comment = ";[C64] texto BASIC en $0801; $0400 es la pantalla " + comment
        if RADIX[0] == 8:
            rhs = conv_bare_octal(rhs)
        out.append(f"{name} {op} {fix_expr(rhs)}  {comment}")
        i += 1
        continue

    mdata = re.match(r"^(\s*[A-Za-z$._][A-Za-z0-9$._]*:)?\s*([-\d^<(\"][^;]*)$", code)
    if mdata and not re.match(r"^\s*[A-Za-z]", mdata.group(2)):
        lbl = fix_ident((mdata.group(1) or "").strip())
        d = mdata.group(2).strip().rstrip(",")
        if RADIX[0] == 8:
            d = conv_bare_octal(d)
        out.append(f"{lbl}\t.byte {fix_expr(d)} {comment}")
        i += 1
        continue
    m = re.match(r"^([A-Za-z$._][A-Za-z0-9$._]*:)?\s*([A-Za-z][A-Za-z0-9]*)"
                 r"\s*(\"[^\"]*\")?\s*(.*)$", code)
    if not m:
        warn.append((i + 1, raw))
        out.append("; [??] " + raw)
        i += 1
        continue
    label = fix_ident(m.group(1) or "")
    mnem = m.group(2)
    strarg = m.group(3) or ""
    rest = (m.group(4) or "").strip()
    U = mnem.upper()

    if U == "BLOCK" and rest:
        r = conv_bare_octal(rest) if RADIX[0] == 8 else rest
        out.append(f"{label}\t.res {fix_expr(r)} {comment}")
        i += 1
        continue
    if U == "EXP" and (rest or strarg):
        r = conv_bare_octal(rest) if RADIX[0] == 8 else rest
        out.append(f"{label}\t.byte {fix_expr(r)} {comment}")
        i += 1
        continue
    if U == "REPEAT":
        mr = re.match(r"([^,]+),\s*<(.*)>", rest)
        if mr:
            n = fix_expr(conv_bare_octal(mr.group(1)) if RADIX[0]==8 else mr.group(1))
            out.append(f"{label}\t.repeat {n}")
            out.append(f"\t{mr.group(2).strip()}")
            out.append("\t.endrepeat")
            i += 1
            continue
    if U not in KNOWN and not rest and not strarg and U not in ("XWD","END","EXP","BLOCK","REPEAT"):
        out.append(f"{label}\t.byte {fix_ident(mnem)} {comment}")
        i += 1
        continue
    if U == "END":
        out.append("; [m10] END")
        i += 1
        continue
    if mnem.upper() == "XWD":
        out.append(f"{label}\t.byte $A9 ; [m10 XWD] {comment}")
        i += 1
        continue
    if strarg and U in ("DT", "DCI", "DCE", "DC"):
        out.append(f"{label}\t{mnem} {strarg} {comment}")
        i += 1
        continue
    if strarg:
        rest = (strarg + " " + rest).strip()
    rest = rest.rstrip(",").strip()
    if rest:
        if RADIX[0] == 8:
            rest = conv_bare_octal(rest)
        out.append(f"{label}\t{mnem}\t{fix_expr(rest)}\t{comment}")
    else:
        out.append(f"{label}\t{mnem}\t{comment}")
    i += 1

result = "\n".join(out) + "\n"
# Fixups documentados: desviaciones minimas del original por limites de rango
# en el layout traducido (la tecnica JEQ es la del propio fuente).
# [C64] vectores de arranque en $A000: los cartuchos salen al BASIC
# con JMP ($A000) (frio) o JMP ($A002) (caliente); el C64 real los tiene
result = result.replace(".org ROMLOC  ",
    ".org ROMLOC  \n\t.word INIT  ;[C64] vector frio ($A000)\n\t.word READY  ;[C64] vector caliente ($A002)")

# [C64] redirigir el despacho de OPEN/CLOSE a nuestros parsers (kernal.s),
# que parsean los argumentos antes de llamar a la primitiva del kernal.
# El MS puro los mandaba crudos al kernal sin parsear (-> syntax error).
result = result.replace("CQOPEN=^O177700", "CQOPEN=BOPEN  ; [C64] parser BASIC")
result = result.replace("CQCLOS=^O177703", "CQCLOS=BCLOSE  ; [C64] parser BASIC")
# por si el octal ya se convirtio a decimal ($FFC0=65472, $FFC3=65475):
import re as _re
result = _re.sub(r"CQOPEN\s*=\s*65472", "CQOPEN = BOPEN", result)
result = _re.sub(r"CQCLOS\s*=\s*65475", "CQCLOS = BCLOSE", result)

result = result.replace("FPWRT:\tBEQ\tEXP\t",
                        "FPWRT:\tJEQ\tEXP\t; [fixup: rama original fuera de rango en este layout]")
if C64:
    # Delta C64: INLIN minimo del fuente no maneja DEL ($14); sin editor de
    # pantalla en el kernal, el retroceso debe hacerse aqui o el caracter
    # entra en el bufer y corrompe la linea.
    result = result.replace(
        "INLINC:\tJSR\tINCHR\t;GET A CHARACTER.\n\n\tCMPI\t13\t;CARRIAGE RETURN?\n\tBEQ\tFININ1\t;YES, FINISH UP.",
        "INLINC:\tJSR\tINCHR\t;GET A CHARACTER.\n\n\tCMPI\t13\t;CARRIAGE RETURN?\n"
        "\tBEQ\tFININ1\t;YES, FINISH UP.\n"
        "\tCMPI\t20\t;[C64] DEL?\n"
        "\tBNE\tGOODCH\n"
        "\tCPXI\t0\t;[C64] nada que borrar al inicio\n"
        "\tBEQ\tINLINC\n"
        "\tDEX\t;[C64] retroceder el indice del bufer\n"
        "\tJMP\tINLINC")
    # Delta C64: el sondeo de RAM del PET corta en $8000 (32K). En C64 el
    # limite natural es $A000 (la propia ROM hace fallar el test), pero
    # mantenemos un tope explicito por robustez.
    result = result.replace(
        "LOOPMM:\tINC\tLINNUM\t\n\tBNE\tLOOPM1\t\n\tINC\tLINNUM+1\t\n\n\tBMI\tUSEDEC",
        "LOOPMM:\tINC\tLINNUM\t\n\tBNE\tLOOPM1\t\n\tINC\tLINNUM+1\t\n"
        "\tLDA\tLINNUM+1\t;[C64] tope en $A000, no $8000\n"
        "\tCMPI\t160\n"
        "\tBCS\tUSEDEC")
    # Delta C64: SYS delegaba en el KERNAL del PET ($FFDE); en C64 necesita
    # manejador propio (KSYS, en kernal.s, usa FRMNUM/GETADR del BASIC).
    result = result.replace("\tADR\t(CQSYS-1)\t",
                            "\tADR\t(KSYS-1)\t;[C64] manejador SYS propio ")
    # Delta C64: eliminar el candado anti-volcado de PEEK (devolvia 0 para
    # direcciones en ROM). En el C64 leer ROM y E/S por PEEK es universal.
    result = result.replace(
        "\tCMPI\tROMLOC/256\t;IF WITHIN BASIC,\n\tBCC\tGETCON\t\n\tCMPI\tLASTWR/256\t\n\tBCC\tDOSGFL\t;GIVE HIM ZERO FOR AN ANSWER.",
        "\t;[C64] candado anti-PEEK de ROM eliminado")
    # Delta C64: vector USR en el $0310 estandar (POKE 785/786), no en ZP.
    result = result.replace("USRPOK:\tJMP\tFCERR\t;SET UP ORIG BY INIT.",
                            "USRPOK = 784 ;[C64] vector USR en $0310 estandar")
open(OUT, "w").write(result)
print(f"avisos: {len(warn)}")
for w in warn[:10]:
    print("  L%d: %s" % w)
