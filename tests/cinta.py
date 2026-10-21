"""Arnes de datasette para py65: CIA1 (Timer A, Timer B, FLAG, ICR) a nivel
de ciclo, puerto $01 (motor, sense, escritura) y entrega de IRQ.

Modelo (interfaz publica del hardware, nivel A):
- Timer A/B: cuentan hacia abajo a 1 por ciclo de reloj; al pasar por cero
  ponen su bit en el ICR (A=bit0, B=bit1) y recargan del latch; en modo
  one-shot (CRx bit3) se paran. CRx bit0 = start, bit4 = force load.
- ICR $DC0D: escribir con bit7=1 activa las mascaras indicadas, con bit7=0
  las desactiva. Leer devuelve los flags (bit7 si alguno habilitado esta
  activo) y los borra.
- FLAG (bit4): el flanco de la linea de lectura de cinta.
- $01: bit3 = salida de escritura, bit4 = sense (0 = PLAY pulsado),
  bit5 = motor (0 = en marcha).

Grabar: se registran los ciclos de cada flanco de subida del bit3 de $01.
Un pulso de cinta es un ciclo completo de la linea (de subida a subida),
que es tambien lo que guarda un fichero TAP.
Reproducir: cada instante de la lista genera un evento FLAG (el lector del
datasette da un flanco por pulso).
TAP: `a_tap` y `de_tap` convierten entre la lista de instantes y un fichero
TAP v1 (un byte = ciclos/8; 0 + 3 bytes para pausas largas).
"""
from arnes import Maquina, imagen


def a_tap(instantes):
    """Lista de instantes de pulso (ciclos) -> fichero TAP v1."""
    out = bytearray()
    for a, b in zip(instantes, instantes[1:]):
        d = b - a
        v = (d + 4) // 8
        if 0 < v < 256:
            out.append(v)
        else:
            out += bytes([0, d & 0xFF, (d >> 8) & 0xFF, (d >> 16) & 0xFF])
    return b"C64-TAPE-RAW" + bytes([1, 0, 0, 0]) + len(out).to_bytes(4, "little") + out


def de_tap(datos):
    """Fichero TAP (v0 o v1) -> lista de instantes de pulso (ciclos)."""
    ver, p = datos[12], datos[20:]
    t, out, i = 0, [0], 0
    while i < len(p):
        v = p[i]
        i += 1
        if v == 0:
            if ver >= 1:
                d = p[i] | p[i + 1] << 8 | p[i + 2] << 16
                i += 3
            else:
                d = 256 * 8
        else:
            d = v * 8
        t += d
        out.append(t)
    return out


class CIA1:
    def __init__(self, mq):
        self.mq = mq
        self.lat = {'A': 0xFFFF, 'B': 0xFFFF}
        self.cnt = {'A': 0xFFFF, 'B': 0xFFFF}
        self.run = {'A': False, 'B': False}
        self.oneshot = {'A': False, 'B': False}
        self.flags = 0
        self.mask = 0
        self.t = 0                      # ciclos ya contabilizados
        m = mq.mem
        m.subscribe_to_write([0xDC04], lambda a, v: self._lat('A', v, 0))
        m.subscribe_to_write([0xDC05], lambda a, v: self._lat('A', v, 1))
        m.subscribe_to_write([0xDC06], lambda a, v: self._lat('B', v, 0))
        m.subscribe_to_write([0xDC07], lambda a, v: self._lat('B', v, 1))
        m.subscribe_to_write([0xDC0E], lambda a, v: self._cr('A', v))
        m.subscribe_to_write([0xDC0F], lambda a, v: self._cr('B', v))
        m.subscribe_to_write([0xDC0D], self._icr_w)
        m.subscribe_to_read([0xDC04], lambda a: self._cnt('A') & 0xFF)
        m.subscribe_to_read([0xDC05], lambda a: self._cnt('A') >> 8)
        m.subscribe_to_read([0xDC06], lambda a: self._cnt('B') & 0xFF)
        m.subscribe_to_read([0xDC07], lambda a: self._cnt('B') >> 8)
        m.subscribe_to_read([0xDC0D], self._icr_r)

    # -- registros --
    def _lat(self, t, v, hi):
        self.sync()                 # una recarga anterior usa el latch viejo
        if hi:
            self.lat[t] = (self.lat[t] & 0xFF) | (v << 8)
        else:
            self.lat[t] = (self.lat[t] & 0xFF00) | v
        return v

    def _cr(self, t, v):
        self.sync()
        self.run[t] = bool(v & 1)
        self.oneshot[t] = bool(v & 8)
        if v & 0x10:
            self.cnt[t] = self.lat[t]
        return v

    def _icr_w(self, a, v):
        if v & 0x80:
            self.mask |= v & 0x1F
        else:
            self.mask &= ~v & 0x1F
        return v

    def _icr_r(self, a):
        self.sync()
        r = self.flags | (0x80 if self.flags & self.mask else 0)
        self.flags = 0
        return r

    def _cnt(self, t):
        self.sync()
        return self.cnt[t]

    # -- tiempo --
    def sync(self):
        now = self.mq.mpu.processorCycles
        d = now - self.t
        self.t = now
        if d <= 0:
            return
        for t, bit in (('A', 1), ('B', 2)):
            if not self.run[t]:
                continue
            c = self.cnt[t]
            if d <= c:
                self.cnt[t] = c - d
                continue
            # paso por cero
            self.flags |= bit
            if self.oneshot[t]:
                self.cnt[t] = self.lat[t]
                self.run[t] = False
            else:
                per = self.lat[t] + 1
                rest = (d - c - 1) % per
                self.cnt[t] = self.lat[t] - rest

    def flag(self):
        self.flags |= 0x10

    def irq_activa(self):
        self.sync()
        return bool(self.flags & self.mask)


class Datasette:
    """Maquina C64 de py65 con CIA1 modelada y un datasette."""

    def __init__(self):
        self.mq = Maquina()
        self.cia = CIA1(self.mq)
        self.img = imagen()
        self.irqvec = self.img[0xFFFE] | (self.img[0xFFFF] << 8)
        self.puerto = 0x37
        self.flancos = []          # ciclos de cada cambio de bit3 (grabacion)
        self.cinta = []            # ciclos relativos de eventos FLAG (reproduccion)
        self.t0 = None             # inicio de la reproduccion
        self.i = 0
        self.pos = 0
        self.motor = False
        m = self.mq.mem
        m.subscribe_to_write([0x01], self._w01)
        m.subscribe_to_read([0x01], lambda a: (self.puerto & ~0x10) & 0xFF)

    def _w01(self, a, v):
        if (v & 0x08) and not (self.puerto & 0x08):
            self.flancos.append(self.mq.mpu.processorCycles)
        ahora = self.mq.mpu.processorCycles
        if (self.puerto & 0x20) and not (v & 0x20) and self.cinta:
            # motor en marcha: la cinta sigue donde se paro (tras 2000
            # ciclos de arranque)
            if self.t0 is None:
                self.t0, self.i = ahora + 2000, 0
            else:
                self.t0 = ahora + 2000 - self.pos
            self.motor = True
        elif not (self.puerto & 0x20) and (v & 0x20) and self.t0 is not None:
            self.pos = ahora - self.t0    # motor parado: la cinta se detiene
            self.motor = False
        self.puerto = v
        return v

    def arrancar(self):
        self.mq.teclear(b"", 3_000_000)
        self.cia.t = self.mq.mpu.processorCycles

    def paso(self):
        m = self.mq.mpu
        if self.motor and self.i < len(self.cinta):
            if m.processorCycles >= self.t0 + self.cinta[self.i]:
                self.cia.sync()
                self.cia.flag()
                self.i += 1
        if not (m.p & 0x04) and self.cia.irq_activa():
            mem = self.mq.mem
            mem.write(0x0100 + m.sp, [(m.pc >> 8) & 0xFF]); m.sp = (m.sp - 1) & 0xFF
            mem.write(0x0100 + m.sp, [m.pc & 0xFF]);        m.sp = (m.sp - 1) & 0xFF
            mem.write(0x0100 + m.sp, [m.p & ~0x10]);        m.sp = (m.sp - 1) & 0xFF
            m.p |= 0x04
            m.pc = self.irqvec
        m.step()

    def llamar(self, dir_, a=0, x=0, y=0, max_ciclos=60_000_000):
        """JSR a una rutina del KERNAL; vuelve a $C000 (centinela)."""
        m = self.mq.mpu
        m.sp = 0xFD
        self.mq.mem.write(0x01FE, [0xFF, 0xBF])
        m.pc, m.a, m.x, m.y = dir_, a, x, y
        fin = m.processorCycles + max_ciclos
        while m.pc != 0xC000:
            if m.processorCycles > fin:
                return None
            self.paso()
        return {'a': m.a, 'x': m.x, 'y': m.y, 'c': m.p & 1}

    def setnam(self, nombre, donde=0xC300):
        self.mq.mem.write(donde, list(nombre))
        self.llamar(0xFFBD, a=len(nombre), x=donde & 0xFF, y=donde >> 8)

    def setlfs(self, la, dev, sa):
        self.llamar(0xFFBA, a=la, x=dev, y=sa)

    def save(self, nombre, ini, fin_mas_1, sa=1):
        self.flancos = []
        self.setnam(nombre)
        self.setlfs(1, 1, sa)
        self.mq.mem.write(0xFB, [ini & 0xFF, ini >> 8])
        r = self.llamar(0xFFD8, a=0xFB, x=fin_mas_1 & 0xFF, y=fin_mas_1 >> 8)
        base = self.flancos[0] if self.flancos else 0
        return r, [f - base for f in self.flancos]

    def load(self, nombre, cinta, verify=False, sa=1, destino=0x0801):
        self.cinta = cinta
        self.t0 = None
        self.setnam(nombre)
        self.setlfs(1, 1, sa)
        r = self.llamar(0xFFD5, a=1 if verify else 0,
                        x=destino & 0xFF, y=destino >> 8)
        return r, self.mq.mem[0x90]
