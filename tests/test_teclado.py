"""Tests del escaneo de teclado (KSCNKEY).

Cubre los bugs historicos: flag Z pisado en la columna 0, teclas de
bit 7, transiciones de shift, rollover y repeticion. Requiere haber
construido con build.sh (usa el listado para localizar KSCNKEY).
"""
import sys
from arnes import Maquina, etiqueta

SCN = etiqueta("KSCNKEY")

def escanear(teclas_secuencia):
    """teclas_secuencia: lista de conjuntos {(fila,bit)} por escaneo.
    Devuelve los bytes emitidos al bufer."""
    teclas = set()
    mq = Maquina(teclas_matriz=teclas)
    for i in range(16):
        mq.mem.write(0x02B0 + i, [0])
    for a in (0xC6, 0x02AB, 0x02AF, 0x02B8, 0x02B9, 0x02BA):
        mq.mem.write(a, [0])
    salida = []
    for conjunto in teclas_secuencia:
        teclas.clear(); teclas.update(conjunto)
        assert mq.subrutina(SCN), "KSCNKEY no retorno"
        n = mq.mem[0xC6]
        salida += list(mq.mem[0x0277:0x0277 + n])
        mq.mem.write(0xC6, [0])
    return bytes(salida)

def caso(nombre, cond):
    print(("OK  " if cond else "FALLO ") + nombre)
    return cond

def main():
    ok = True
    # columna 0 (el bug del flag Z): RETURN y DEL deben emitir
    ok &= caso("RETURN emite $0D", escanear([{(0, 1)}]) == b"\r")
    ok &= caso("DEL emite $14", escanear([{(0, 0)}]) == b"\x14")
    # bit 7 de filas normales
    ok &= caso("V (fila3,bit7)", escanear([{(3, 7)}]) == b"V")
    # shift
    ok &= caso("shift+2 = comillas", escanear([{(1, 7), (7, 3)}]) == b'"')
    ok &= caso("shift solo no emite", escanear([{(1, 7)}]) == b"")
    # rollover: espacio aun pulsado cuando baja la V
    sec = [{(7, 4)}] * 3 + [{(7, 4), (3, 7)}] * 2 + [{(3, 7)}] * 2 + [set()]
    ok &= caso("rollover espacio->V", escanear(sec) == b" V")
    # repeticion: espacio mantenido repite tras el retardo; Q no
    esp = escanear([{(7, 4)}] * 30)
    ok &= caso("espacio repite (retardo+cadencia)",
               esp[0:1] == b" " and 3 <= len(esp) <= 6)
    ok &= caso("Q no repite", escanear([{(7, 6)}] * 30) == b"Q")
    sys.exit(0 if ok else 1)

if __name__ == "__main__":
    if SCN is None:
        print("AVISO: falta build/rom_listado.txt; ejecuta ./build.sh")
        sys.exit(0)
    main()
