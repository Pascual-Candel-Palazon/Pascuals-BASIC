"""Formato de la salida del BASIC igual que el C64 (comparado en VICE con
la ROM original como caja negra, nivel B de docs/PROCEDENCIA.md):

- LIST: el numero de linea va en la columna 0 ("10 PRINT", no " 10").
- " IN nn" y los bytes libres del arranque, sin espacio de signo.
- Tras teclear una linea no queda una linea en blanco debajo.
- Mensajes de error con dos espacios antes de ERROR ("?SYNTAX  ERROR").
- PRINT de numeros conserva el espacio del signo (" 10 -5").
"""
import sys
from arnes import Maquina

def caso(nombre, cond):
    print(("OK  " if cond else "FALLO ") + nombre)
    return cond

def main():
    ok = True
    mq = Maquina()
    mq.teclear(b"10 PRINT\"HOLA\":X\r20 GOTO 5\rLIST\rRUN\rPRINT 10;-5\r",
               120_000_000)
    v = [l.rstrip() for l in mq.pantalla()]
    ok &= caso("arranque: \" 64K RAM SYSTEM  38911 BASIC BYTES FREE\"",
               " 64K RAM SYSTEM  38911 BASIC BYTES FREE" in v)
    i = v.index("10 PRINT\"HOLA\":X")
    ok &= caso("sin linea en blanco tras teclear una linea",
               v[i + 1] == "20 GOTO 5" and v[i + 2] == "LIST")
    ok &= caso("LIST: numeros en la columna 0",
               v[i + 3] == "" and v[i + 4] == "10 PRINT\"HOLA\":X" and
               v[i + 5] == "20 GOTO 5" and v[i + 6] == "READY.")
    ok &= caso("RUN: salida en la linea siguiente",
               v[i + 7] == "RUN" and v[i + 8] == "HOLA")
    ok &= caso("?SYNTAX  ERROR IN 10 (dos espacios, sin signo en el numero)",
               "?SYNTAX  ERROR IN 10" in v)
    j = v.index("PRINT 10;-5")
    ok &= caso("PRINT conserva el espacio del signo: \" 10 -5\"",
               v[j + 1] == " 10 -5")
    sys.exit(0 if ok else 1)

if __name__ == "__main__":
    main()
