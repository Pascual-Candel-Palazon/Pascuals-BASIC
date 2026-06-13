# Continuidad del proyecto (handoff)

Este documento es la **fuente de verdad** para retomar el trabajo en una
sesion nueva sin contexto previo. Resume estado, arquitectura, metodo y
lecciones. Leelo entero antes de tocar nada.

---

## 1. Que es esto

ROMs de sustitucion (BASIC + KERNAL) para el Commodore 64 **de serie**
(16 KB de ROM, sin banking adicional), licencia permisiva (MIT), con
cadena de procedencia auditable (sala limpia). Espiritu AltirraOS: una
alternativa libre que arranca, se programa y se comporta como la maquina
real.

- BASIC: desde el fuente **MIT de Microsoft** `microsoft/BASIC-M6502`
  (v1.1, 1978), configurado para CBM (`REALIO=3`).
- KERNAL: **sala limpia**, escrito desde cero a partir de interfaces y
  comportamiento observable documentados publicamente.
- Chargen actual: puente temporal de **MEGA65 open-roms** (`bin/chargen.bin`).
  Pendiente: chargen propio.

---

## 2. Arquitectura legal (resumen; detalle en `docs/PROCEDENCIA.md`)

Niveles de procedencia para CUALQUIER aportacion:

- **Nivel A** (libre): hardware, registros, interfaz publica (tabla de
  saltos del KERNAL, direcciones de E/S, formato de ficheros).
- **Nivel B** (permitido documentandolo): comportamiento observable
  (mensajes, timing, semantica) reimplementado desde especificaciones
  publicas. El protocolo IEC se toma de fuentes publicas (Butterfield,
  Programmer's Reference Guide), **nunca** del desensamblado de las
  rutinas serie de Commodore.
- **Nivel C** (PROHIBIDO): desensamblados de ROMs de Commodore. **Nunca
  descargar ni volcar la ROM de Commodore.** Nunca mirar desensamblados
  de BASIC 3.5/7.0 ni del KERNAL/DOS de Commodore.

Antes de publicar: consulta pendiente a un abogado de PI.

---

## 3. Layout y mapa tecnico

### Imagen de ROM
- BASIC: `$A000-$BFFF` (CASI LLENO, ~35 bytes libres en `$BFDD`).
- Cola del BASIC en `$E000-$E1BD`: parte de la ROM del KERNAL es codigo
  BASIC (quirk real del C64, como hizo Commodore).
- KERNAL: codigo desde `$E200` (RESET=`KRESET`=$E200). Mucho espacio
  libre tras el codigo hasta los trampolines.
- Trampolines a direcciones fijas: `$FD15`, `$FD50`, `$FDA3`, `$FF5B`.
- Tabla de saltos: `$FF81-$FFF5`.
- Vectores: `$FFFA` NMI=`KNMIENT`($EADD), `$FFFC` RESET=`KRESET`($E200),
  `$FFFE` IRQ=`KIRQENT`($EA5B).

### Polaridad del bus serie (MEDIDA empiricamente, `$DD00` reposo = 195)
`SERPRT = $DD00`.
- Salida (bits 3/4/5 = ATN/CLK/DATA): escribir **1 = tirar la linea a
  BAJO** (asertar). Mascaras `B_ATN=$08`, `B_CLK=$10`, `B_DATA=$20`.
- Entrada (bits 6/7 = CLK/DATA): leer **1 = ALTA/liberada**, **0 =
  BAJA/asertada**. Mascaras `B_CLKIN=$40`, `B_DATIN=$80`.
- Helpers que preservan los bits 0-2: `KCLKLO/KCLKHI/KDATLO/KDATHI/
  KATNLO/KATNHI`.

### ZP del subsistema serie (en `kernal.s`)
`KSTATUS=$90` (ST), `KVERCK=$93` (load/verify), `KATNF=$94` (bit7=byte
bajo ATN), `KBSOUR=$95` (byte diferido), `KC3PO=$A3` (bit7=byte CIOUT
pendiente), `KEOIF=$A4` (bit7=senalar EOI), `KBSOUR2=$A5` (byte en
curso / acumulador de recepcion), `KBITCNT=$A6` (contador de bits),
`KFNLEN=$B7`, `KLA=$B8`, `KSA=$B9`, `KFA=$BA`, `KFNADR=$BB/$BC`,
`KLDTND=$98`. Tablas: `KLAT=$0259`, `KFAT=$0263`, `KSAT=$026D`.
**El IRQ/teclado usa `$FB` (KCPTR), `$C6` (KNDX) y pagina 2 (KMATRIX
$02A0, KSHIFT $02AB, KGDCOL $0287, KCTRL $02E0, KCBM $02E1, KBLCNT
$02AC, KBLON $02AD): NO pisa la ZP serie.** Verificado.

### Helpers del BASIC utiles
`CHRGET=$70`, `GETBYT=$B5B1`, `COMBYT=$B605`, `CHKCOM=$AD31`,
`FRMEVL=$ABD8`, `FRESTR=$B4B6`, `STROUT=$A955`, `ERROR=$A286`.

---

## 4. Cadena de build (CRITICO)

Construir SIEMPRE con `./build.sh` desde la raiz del repo. Hace, en orden:

```
cp upstream/m6502.asm src/*.py src/kernal.s src/rom.s src/basic.cfg \
   src/c64_build.py  build/
cd build
python3 flatten.py          # aplana includes del fuente MIT
python3 translate.py        # traduce a sintaxis ca65 -> basic_cbm.s
ca65 rom.s -l rom_listado.txt -o rom.o     # OJO: -l SIEMPRE
ld65 -C basic.cfg rom.o -o c64_full.bin
python3 c64_build.py        # trocea -> basic_c64.bin, kernal_c64.bin
```

`rom.s` solo hace `.include "basic_cbm.s"` + `.include "kernal.s"`.

`basic.cfg`: una sola MEMORY `ALL` ($0000-$10000, type=rw) con segmento
CODE. `c64_full.bin` sale ~12320 bytes (segmentos concatenados por
`.org`, SIN rellenar huecos). `c64_build.py` reconstruye la imagen 64K
troceando `c64_full.bin` por las fronteras `.org` del listado, y corta
`basic_c64.bin` ($A000-$BFFF) y `kernal_c64.bin` ($E000-$FFFF).

### LECCION CRITICA del build (no repetir el error)
`c64_build.py` lee `rom_listado.txt` para las fronteras `.org`. Si el
listado esta **desincronizado** con `c64_full.bin` (p.ej. por ensamblar
con `ca65` SIN `-l`, dejando un listado viejo), la suma de longitudes de
seccion no cuadra, la asignacion de slices **encoge el bytearray**, y
`kernal_c64.bin` sale corto (perdiendo los vectores) -> **arranque
negro**. Por eso `build.sh` regenera el listado en cada build, y
`c64_build.py` esta endurecido con asserts ruidosos (`len(img)==0x10000`,
`len(ker)==8192`, `RESET!=0`). Si ves pantalla negra al arrancar:
sospecha del build/listado ANTES que del codigo.

### VICE headless (pruebas)
```
xvfb-run -a x64sc -default \
  -kernal build/kernal_c64.bin -basic build/basic_c64.bin \
  -chargen bin/chargen.bin \
  [-8 testdisk.d64] -warp \
  [-keybuf 'comandos\n...'] \
  -limitcycles N -exitscreenshot salida.png >/dev/null 2>&1
```
- Unidad real emulada: SOLO `-8 imagen.d64`. (`-virtualdev8` /
  `-drive8type` NO existen, rompen el parseo de argumentos.)
- Crear disco de prueba:
  `c1541 -format "test disk,01" d64 testdisk.d64 -write test.prg test`
  (programa "TEST" p.ej. `10 PRINT"HI"`).

---

## 5. Estado funcional

### Funciona y verificado
- Arranque limpio: `COMMODORE BASIC` / `38911 BYTES FREE` / `READY.`
- Interprete BASIC completo (MIT Microsoft): coma flotante, cadenas,
  FOR/GOSUB, RUN/LIST, PEEK/POKE, SYS/USR, etc.
- Editor de pantalla WYSIWYG, teclado por IRQ (matriz/shift/repeticion),
  codigos de control, graficos C= y SHIFT, cursor parpadeante, scroll.
- Vectores RAM de pagina 3 (IRQ/BRK/NMI, E/S interceptable).
- Autoarranque de cartuchos CBM80, API init de cartuchos.

### IEC: estado por fases
- **Parsing del BASIC (fases 1, 2a, 3): COMPLETO y verificado.**
  OPEN/CLOSE/LOAD/SAVE se parsean y registran en tablas (KLAT/KFAT/KSAT).
  `translate.py` redirige los dispatch del BASIC: CQLOAD->BLOAD,
  CQSAVE->BSAVE, CQOPEN->BOPEN, CQCLOS->BCLOSE.
- **Envio por el bus (fase 2b): FUNCIONA. (commit "IEC fase 2b ...")**
  `OPEN15,8,15,"i0"` completa, vuelve a READY, y `PRINT ST` da **0**: la
  unidad emulada responde y acepta cada byte (LISTEN, SECOND canal 15,
  nombre, UNLISTEN). Primitivas: `KLISTN/KTALK/KSECND/KTKSA/KCIOUT/
  KUNLSN/KUNTLK` + `KISEND` (envio de byte). Todas con **SEI/CLI** (el
  timing serie no tolera interrupciones). `KCIOUT` hace envio DIFERIDO
  para el EOI.
- **Recepcion (WIP, NO funciona aun): `KACPTR` + integracion de entrada.**
  Implementado y cableado: `CHKIN` envia TALK+TKSA, `CHKOUT` envia
  LISTEN+SECOND, `CLRCHN` envia UNTALK/UNLISTEN, `CHRIN/GETIN` derivan a
  `KACPTR` cuando el dispositivo es serie (rutina `KSERIN`).
  **El handshake completa sin colgarse** (ST=0, sin timeout, el reloj
  conmuta 8 veces por llamada), **pero ACPTR ensambla `$FF` o `$00` por
  byte** (los 8 bits iguales), no la cadena de estado ASCII.

### LOAD/SAVE de bus: STUBS
`$FFD5` (LOAD) y `$FFD8` (SAVE) del KERNAL siguen siendo `KSTUB`.
`ACPTR` ($FFA5) ya NO es stub (ver arriba, WIP).

---

## 6. ANALISIS del problema de recepcion (lo mas importante para seguir)

Depuracion hecha con captura cruda de muestras en RAM libre (`$C000`,
que el BASIC no toca; NO usar `$03C0+`, colisiona con el buffer interno
de GET#/INPUT#).

Hechos establecidos:
1. La recepcion NO se cuelga: `OPEN15,8,15` + `GET#15,A$` -> ST=0,
   `KACPTR` devuelve un byte, el reloj conmuta 8 veces (sin timeout).
2. `KACPTR` devuelve `$FF` o `$00` por byte: dentro de cada byte, las 8
   muestras de DATA salen iguales. No es la cadena de estado real.
3. **Cambiar el flanco de muestreo (leer DATA con CLOCK alto vs CLOCK
   bajo) NO altera el resultado.** Por tanto el problema NO es el flanco;
   es la **sincronizacion/tramado del byte** o algo mas arriba.
4. Se implemento lectura ATOMICA de CLOCK+DATA del mismo `lda $DD00` con
   `asl` (bit7 DATA -> carry; bit6 CLOCK -> bit7/N), para eliminar la
   carrera entre confirmar el reloj y leer el dato. No basto.
5. Timeouts de 16 bits en todas las esperas de ACPTR (el 1541 emulado es
   lento entre el "listo" y el primer bit; con timeout de 8 bits daba
   falsos timeout -> falso EOI).

### HIPOTESIS PRINCIPAL para la proxima sesion
Quiza el **ENVIO tampoco transmite bits correctos**. `ST=0` en el envio
solo significa "sin timeout del handshake", NO "el 1541 recibio los bits
bien". Si el bit-timing falla en AMBOS sentidos, la unidad nunca recibio
el comando, no hay estado real que leer, y `ACPTR` lee el bus en reposo
(de ahi los `$FF`/`$00`).

**Primer paso recomendado:** verificar que el ENVIO entrega bits
correctos de verdad, con un comando de **efecto observable**:
- p.ej. `OPEN15,8,15,"I0"` (Initialize) y luego comprobar el codigo de
  estado, o un `N:nombre,id` (NEW/format) y ver si cambia el disco, o
  escribir un fichero y releerlo con un emulador/herramienta externa
  (`c1541 testdisk.d64 -dir` desde el host para inspeccionar el d64
  despues de un SAVE).
- Si el envio NO tiene efecto real, arreglar primero el bit-timing de
  `KISEND` (setup del dato respecto al reloj, duracion de `KSDLY`), y
  luego la recepcion deberia caer en su sitio.

**Segundo paso:** revisar el estado tras el turnaround `KTKSA`
(talker->oyente) y si hace falta un retardo de establecimiento del dato
antes de muestrear; comprobar que la unidad realmente entra en modo
talker.

### Detalle de KISEND (emisor, referencia del protocolo)
Tras ver al oyente listo (DATA alto), por cada bit (LSB primero):
fija DATA=bit, `KCLKHI` (reloj alto = bit valido), `KSDLY` (retardo
corto), `KCLKLO` (reloj bajo), `KDATHI` (libera DATA). Es decir, **el
dato es valido mientras CLOCK esta alto**. La especificacion publica
(Butterfield) para el RECEPTOR dice leer DATA cuando CLOCK baja; ambas
convenciones se probaron en ACPTR sin diferencia (ver hecho 3).

---

## 7. Metodo de depuracion (probado, replicar)

- **VICE es el unico verificador real** del timing del bus; `py65` (el
  arnes) NO modela `$DD00` (las lecturas dan 0), solo sirve para logica
  sin timing.
- **Marcadores de color**: escribir en `$D020` (borde) y `$D021` (fondo)
  numeros de etapa para ver, en el `-exitscreenshot`, en que punto se
  cuelga/queda el codigo. Un fondo/borde que "parpadea" (bandas con el
  raster) = el codigo pasa por esa etapa repetidamente (bucle).
  Paleta C64: 0 negro, 1 blanco, 2 rojo, 3 cian, 5 verde, 6 azul,
  7 amarillo, 8 naranja, 9 marron, 10 rojo-claro, 13 verde-claro,
  15 gris-claro.
- **Captura de datos**: para volcar valores y leerlos, escribir en RAM
  libre `$C000-$C0FF` (bloque libre del C64) y leer con `PEEK(49152+n)`
  desde un programa BASIC. NO usar la pagina 3 / buffer de casete
  ($033C+), colisiona con la E/S del BASIC.
- Leer `ST` (`PRINT ST`) tras una operacion de bus para ver
  timeout(=128)/EOI(=64)/ok(=0).

---

## 8. Lecciones aprendidas (no repetir errores)

1. **Preservar registros alrededor de llamadas serie.** `KISEND` (y por
   tanto `KCIOUT`) **destruyen Y**. El cuelgue real del envio era que el
   bucle `@nm` de `KOPEN` usaba Y como indice del nombre a traves de las
   llamadas a `KCIOUT`: al enviar el primer byte, Y se corrompia y el
   bucle no terminaba. Solucion: `tya/pha ... pla/tay` alrededor de la
   llamada. **Cualquier bucle del KERNAL que llame a rutinas serie y
   dependa de X/Y debe preservarlos.**
2. **El listado debe ir sincronizado con el binario** (ver seccion 4).
3. **SEI durante el bit-banging serie**: el IRQ del jiffy interrumpe el
   timing. Todas las rutinas de bit (KISEND, KACPTR) hacen SEI al entrar
   y CLI en TODAS las salidas.
4. **El arnes (`py65`) es flaky por dependencia de ciclos**: tests como
   `test_editor`/`test_iec_fase2a`/`test_iec_fase3parse` pueden fallar en
   lote y pasar corridos en solitario. Ante un FALLO suelto, re-correr el
   test solo antes de asumir regresion.
5. **No reproducir** desensamblados de Commodore para nada (nivel C).

---

## 9. Roadmap restante (en orden)

1. **Verificar el envio de verdad** (efecto observable) y, si hace falta,
   corregir el bit-timing de `KISEND`. (Ver seccion 6.)
2. **Recepcion `KACPTR`**: una vez confirmado el envio, clavar el
   muestreo/tramado contra la unidad emulada.
3. **LOAD/SAVE de bus** (`$FFD5`/`$FFD8`): secuencia completa.
   - LOAD: LISTEN dispositivo, SECOND $F0 (open canal 0), nombre por
     CIOUT, UNLISTEN, TALK dispositivo, TKSA $60, recibir por ACPTR
     (primeros 2 bytes = direccion de carga, resto datos) hasta EOI,
     UNTALK; luego relinkar el BASIC.
   - SAVE: cabecera (direccion) + cuerpo por CIOUT.
   - Verificar `LOAD"$",8` (directorio) y `LOAD"TEST",8` contra
     `testdisk.d64`; SAVE de ida y vuelta.
4. Post-1.0: chargen propio; recolector de basura de cadenas lineal
   (desde descripcion algoritmica publica, NUNCA desensamblados);
   ROM libre del 1541 (proyecto hermano).

Pendiente general: consulta a abogado de PI antes de publicar. CTRL+letra
sin asignar es deliberado.

---

## 10. Estructura del repo

```
src/        kernal.s (sala limpia), translate.py, flatten.py,
            basic.cfg, rom.s, c64_build.py   <- FUENTES (editar aqui)
upstream/   m6502.asm (fuente MIT de Microsoft), LICENSE-microsoft
bin/        basic_c64.bin, kernal_c64.bin (construidas), chargen.bin
build/      generado por build.sh (gitignored)
docs/       PROCEDENCIA.md (legal), AUDITORIA.md, CONTINUIDAD.md (este)
tests/      arnes.py (clase Maquina, py65) + test_*.py + run_all.sh
build.sh    construye todo
```

Editar SIEMPRE en `src/`; `build.sh` copia a `build/` y construye. Los
tests leen `build/basic_c64.bin`, `build/kernal_c64.bin` y
`build/rom_listado.txt`, asi que **reconstruir antes de testar**.

Tests rapidos: `cd tests && python3 test_humo.py` (etc.). `run_all.sh`
es lento; usar ficheros sueltos con `timeout` para regresion rapida.

---

## 11. Notas de colaboracion

- Trabajo en **espanol**. Comunicacion directa, sin relleno; corregir
  premisas falsas; decir "no se" cuando no se sabe (anticomplacencia).
- **Nunca usar el guion largo** en textos, emails ni documentos (delata
  autoria de IA). Usar comas, puntos, dos puntos o parentesis.
- El usuario depura como ingeniero: sus pistas han resuelto varios bugs.
  Ante un fallo no reproducible, pedirle la receta exacta.
