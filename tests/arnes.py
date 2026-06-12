"""Arnes de pruebas: C64 minimo sobre py65.

Carga las ROMs de bin/ (o build/ si existe), protege la ROM contra
escrituras, simula IRQs de jiffy y ofrece utilidades para inyectar
teclas (por el bufer del kernal o por la matriz CIA simulada) y para
volcar la pantalla.
"""
import os, re
from py65.devices.mpu6502 import MPU
from py65.memory import ObservableMemory

AQUI = os.path.dirname(os.path.abspath(__file__))
RAIZ = os.path.dirname(AQUI)

def _ruta(nombre):
    for d in ("build", "bin"):
        p = os.path.join(RAIZ, d, nombre)
        if os.path.exists(p):
            return p
    raise FileNotFoundError(nombre)

def imagen():
    img = bytearray(64 * 1024)
    img[0xA000:0xC000] = open(_ruta("basic_c64.bin"), "rb").read()
    img[0xE000:0x10000] = open(_ruta("kernal_c64.bin"), "rb").read()
    return img

def etiqueta(nombre):
    """Direccion de una etiqueta del kernal segun el listado (si existe)."""
    lst = os.path.join(RAIZ, "build", "rom_listado.txt")
    if not os.path.exists(lst):
        return None
    pat = re.compile(r"^00([0-9A-F]{4})\s+\d\s+" + re.escape(nombre) + r":")
    for ln in open(lst):
        m = pat.match(ln)
        if m:
            return int(m.group(1), 16)
    return None

class Maquina:
    def __init__(self, teclas_matriz=None):
        """teclas_matriz: conjunto mutable de (fila, bit) pulsadas."""
        self.img = imagen()
        self.mem = ObservableMemory()
        self.mem.write(0xA000, list(self.img[0xA000:0xC000]))
        self.mem.write(0xE000, list(self.img[0xE000:0x10000]))
        img = self.img
        for lo, hi in ((0xA000, 0xC000), (0xE000, 0x10000)):
            self.mem.subscribe_to_write(range(lo, hi), lambda a, v: img[a])
        self.teclas = teclas_matriz if teclas_matriz is not None else set()
        est = {"dc00": 0}
        self.mem.subscribe_to_write([0xDC00],
                                    lambda a, v: est.update(dc00=v) or v)
        def r_dc01(a):
            v = 0xFF
            for fila, bit in self.teclas:
                if not (est["dc00"] & (1 << fila)):
                    v &= ~(1 << bit)
            return v
        self.mem.subscribe_to_read([0xDC01], r_dc01)
        self.mpu = MPU(memory=self.mem)
        self.mpu.pc = self.img[0xFFFC] | (self.img[0xFFFD] << 8)
        self.irqvec = self.img[0xFFFE] | (self.img[0xFFFF] << 8)

    def irq(self):
        m = self.mpu
        if m.p & 0x04:
            return
        self.mem.write(0x0100 + m.sp, [(m.pc >> 8) & 0xFF]); m.sp = (m.sp - 1) & 0xFF
        self.mem.write(0x0100 + m.sp, [m.pc & 0xFF]);        m.sp = (m.sp - 1) & 0xFF
        self.mem.write(0x0100 + m.sp, [m.p & ~0x10]);        m.sp = (m.sp - 1) & 0xFF
        m.p |= 0x04
        m.pc = self.irqvec

    def correr(self, pasos, con_irq=True, cada=17000):
        for n in range(pasos):
            if con_irq and n % cada == 0 and n:
                self.irq()
            self.mpu.step()

    def teclear(self, texto, pasos_total, espera=2_500_000, cadencia=60_000,
                con_irq=True):
        """Inyecta bytes de uno en uno por el bufer del kernal."""
        cola = list(texto)
        prox = espera
        for n in range(pasos_total):
            if con_irq and n % 17000 == 0 and n:
                self.irq()
            if cola and n >= prox and self.mem[0xC6] == 0:
                self.mem.write(0x0277, [cola.pop(0)])
                self.mem.write(0xC6, [1])
                prox = n + cadencia
            self.mpu.step()
            if not cola and n > prox + 4_000_000:
                break

    def subrutina(self, direccion, max_pasos=20000):
        """Llama a una subrutina con retorno senuelo en $C000."""
        m = self.mpu
        m.pc = direccion
        m.sp = 0xFD
        self.mem.write(0x01FE, [0xFF, 0xBF])
        for _ in range(max_pasos):
            if m.pc == 0xC000:
                return True
            m.step()
        return False

    def pantalla(self):
        filas = []
        for f in range(25):
            s = ""
            for c in range(40):
                sc = self.mem[0x0400 + f * 40 + c]
                if sc == 0x20: s += " "
                elif 1 <= sc <= 26: s += chr(64 + sc)
                elif 0x20 <= sc <= 0x3F: s += chr(sc)
                else: s += "."
            filas.append(s.rstrip())
        return filas

    def pantalla_contiene(self, texto):
        return any(texto in f for f in self.pantalla())
