#!/usr/bin/env python3
"""Reconstruye la imagen 64K desde el listado, corta basic/kernal.bin
y ejecuta la prueba de humo C64: RESET real, teclado inyectado en KBUF,
lectura de pantalla $0400 (ejercita el CHROUT del kernal limpio)."""
import re

img = bytearray(64 * 1024)
# trocear el binario lineal de ld65 usando los .org del listado como fronteras
secs = []   # (direccion_destino, pc_en_el_org)
for ln in open("rom_listado.txt", encoding="latin-1"):
    m = re.match(r"^00([0-9A-F]{4})r?\s+\d\s+\.org\s+(\S+)", ln)
    if m:
        pc = int(m.group(1), 16)
        tgt = m.group(2).replace("$", "0x")
        secs.append((pc, tgt))
# resolver destinos simbolicos conocidos
NAMES = {"ROMLOC": 0xA000}
starts = []
for pc, tgt in secs:
    if tgt in NAMES: d = NAMES[tgt]
    elif tgt.startswith("0x"): d = int(tgt, 16)
    else: d = int(tgt)
    starts.append((pc, d))
# tamano de cada seccion = pc del siguiente .org - direccion de esta...
# el PC del listado ya esta en espacio logico: la longitud emitida de la
# seccion k = (pc_org_{k+1} - dest_k); la ultima llega al final del fichero.
data = open("c64_full.bin", "rb").read()
off = 0
for k, (pc, dest) in enumerate(starts):
    if k + 1 < len(starts):
        length = starts[k + 1][0] - dest
    else:
        length = len(data) - off
    img[dest:dest + length] = data[off:off + length]
    off += length
open("basic_c64.bin", "wb").write(img[0xA000:0xC000])
open("kernal_c64.bin", "wb").write(img[0xE000:0x10000])
print(f"basic_c64.bin: 8192 bytes | kernal_c64.bin: 8192 bytes")
print(f"vector RESET: ${img[0xFFFC] | img[0xFFFD]<<8:04X}")

# ---------------- prueba de humo ----------------
from py65.devices.mpu6502 import MPU
from py65.memory import ObservableMemory

mem = ObservableMemory()
def protect(lo, hi):
    def hook(address, value):
        return img[address]  # escribir devuelve el original: ROM
    mem.subscribe_to_write(range(lo, hi), hook)

mem.write(0xA000, list(img[0xA000:0xC000]))
mem.write(0xE000, list(img[0xE000:0x10000]))
protect(0xA000, 0xC000)
protect(0xE000, 0x10000)
mem.write(0xDC01, [0xFF])  # CIA1 puerto B: ninguna tecla pulsada

m = MPU(memory=mem)
m.pc = img[0xFFFC] | (img[0xFFFD] << 8)  # RESET real

NDX, KBUF = 0xC6, 0x0277
linea = list(b"PRINT 2+2\r")
inyectado = False

def pantalla():
    out = []
    for fila in range(25):
        s = ""
        for c in range(40):
            sc = mem[0x0400 + fila * 40 + c]
            if sc == 0x20: s += " "
            elif 1 <= sc <= 26: s += chr(64 + sc)
            elif sc == 0: s += "@"
            elif 0x30 <= sc <= 0x3F: s += chr(sc)
            elif sc < 0x20: s += chr(sc + 64)
            else: s += "."
        if s.strip(): out.append(f"{fila:2d}|{s.rstrip()}")
    return "\n".join(out)

pasos = 0
while pasos < 8_000_000:
    m.step()
    pasos += 1
    if not inyectado and pasos == 3_000_000:
        # a estas alturas el banner deberia estar; inyectar comando
        for i, ch in enumerate(linea):
            mem.write(KBUF + i, [ch])
        mem.write(NDX, [len(linea)])
        inyectado = True

print(f"\npasos: {pasos}  PC final: ${m.pc:04X}")
print("=== PANTALLA ===")
print(pantalla())
