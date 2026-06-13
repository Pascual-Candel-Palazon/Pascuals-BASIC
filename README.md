# ROMs libres para Commodore 64

ROMs de sustitucion (BASIC + KERNAL) para el Commodore 64 **de serie**
(16 KB de ROM, sin banking adicional), con licencia permisiva y cadena
de procedencia auditable. El espiritu es el de AltirraOS / Altirra
BASIC en el mundo Atari de 8 bits: una alternativa libre que arranca,
se programa y se comporta como la maquina real.

## Estado

Funciona hoy:

- Arranque: `### COMMODORE BASIC ###` / `38911 BYTES FREE`
- Interprete completo (fuente MIT de Microsoft, v1.1 de 1978): coma
  flotante, cadenas, FOR/GOSUB, programas con lineas numeradas, RUN,
  LIST, PEEK/POKE de RAM/ROM/E-S, SYS y USR
- Editor de pantalla v1 (WYSIWYG): cursores, DEL que recoge el texto,
  lineas logicas de 2 filas (80 col.), tolerante al paste de VICE
- Teclado completo por IRQ: matriz, shift, repeticion de tecla
- Cursor parpadeante; scroll
- Vectores RAM de pagina 3: IRQ/BRK/NMI redirigibles ($0314+), E/S
  interceptable ($031A-$0333), RESTOR y VECTOR
- Bus serie IEC, lado de ENVIO: `OPEN15,8,15,"i0"` completa con `ST=0`
  (la unidad acepta LISTEN, direccion secundaria, nombre y UNLISTEN).
  Parsing del BASIC de OPEN/CLOSE/LOAD/SAVE completo.

En curso (WIP): RECEPCION por el bus IEC (`ACPTR` + entrada serie). El
handshake completa sin colgarse pero el byte recibido aun no es correcto.
Ver el analisis y los proximos pasos en **`docs/CONTINUIDAD.md`** (el
documento de handoff con todo el contexto tecnico para retomar).

Pendiente (en orden): terminar recepcion IEC, LOAD/SAVE por el bus,
juego de caracteres propio, vectores del lado BASIC (IGONE/ICRNCH).

Mejoras candidatas post-1.0:

- **Recolector de basura de cadenas**: el BASIC hereda el GC cuadratico
  original de Microsoft (pausas largas con miles de cadenas). Mejorable
  implementando un GC lineal desde la descripcion algoritmica publicada
  (tecnica de back-pointers), NUNCA desde desensamblados de ROMs de
  Commodore (BASIC 3.5/7.0) - vease docs/PROCEDENCIA.md. Requisito
  previo: bateria de tests de estres del GC contra el actual como
  referencia (integridad + tiempos).

Proyecto hermano futuro: ROM libre de la unidad 1541 (mismo metodo de
sala limpia; formato GCR y protocolo IEC estan especificados
publicamente). Mientras tanto: VICE -iecdevice8 para emulacion y
SD2IEC (firmware ya libre) para hardware real.

## Uso

```
x64sc -kernal bin/kernal_c64.bin -basic bin/basic_c64.bin -chargen bin/chargen.bin
```

## Construccion

Requisitos: `python3`, `cc65`, y `py65` para los tests
(`pip install py65`).

```
./build.sh        # genera bin/basic_c64.bin y bin/kernal_c64.bin
cd tests
python3 test_humo.py
python3 test_teclado.py
python3 test_editor.py
```

## Arquitectura y procedencia

- **BASIC** (`$A000-$BFFF` y cola en `$E000`): derivado mecanicamente
  del fuente oficial MIT de Microsoft (`upstream/m6502.asm`, repo
  microsoft/BASIC-M6502) mediante `src/flatten.py` (resuelve los
  condicionales MACRO-10 con REALIO=3, el target Commodore) y
  `src/translate.py` (MACRO-10 -> ca65). Cada adaptacion al C64 esta
  anotada `[C64]` en el fuente generado: mapa de memoria, puerto del
  6510, tope de RAM, SYS/USR propios, candado anti-PEEK eliminado.
- **KERNAL** (`$E200+`): escrito desde cero para este proyecto, desde
  la interfaz publica documentada y el comportamiento observable.
  Politica estricta en `docs/PROCEDENCIA.md`.
- **CHARGEN**: temporalmente el de MEGA65 open-roms (licencia de
  terceros, vease su proyecto); pendiente de sustitucion.

La verificacion de no-similitud con las ROMs originales debe hacerla
un tercero: este proyecto no las descarga ni desensambla.

## Licencia

- Codigo propio (KERNAL, scripts, tests): MIT (LICENSE)
- BASIC: MIT de Microsoft (upstream/LICENSE-microsoft)
- chargen.bin: de MEGA65 open-roms, licencia propia de ese proyecto
