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
- Arranque limpio: `**** PASCUAL'S BASIC ****` (centrado, nombre propio en
  vez de la marca de Commodore; sustituido en translate.py) / `38911 BYTES
  FREE` / `READY.`
- Mensajes de error LARGOS del BASIC (estilo C64): los 18 errores del MS se
  imprimen completos (`?SYNTAX ERROR`, `?DIVISION BY ZERO ERROR`, `?NEXT
  WITHOUT FOR ERROR IN nn`, etc.) en vez de los codigos de 2 letras del MS.
  Mecanismo: el manejador del BASIC llama a `KERRMSG` (kernal.s), que indexa
  una tabla de punteros `KERRTAB` con el mismo X (offset en ERRTAB) e imprime
  via STROUT. Los textos viven en el KERNAL (la ROM del BASIC esta llena);
  ERRTAB se conserva intacto (sus posiciones definen los indices ERRNF/...).
  Sustitucion en translate.py. Verificado en VICE. Los 9 errores de E/S
  (KIOERR) ya eran largos.
- Interprete BASIC completo (MIT Microsoft): coma flotante, cadenas,
  FOR/GOSUB, RUN/LIST, PEEK/POKE, SYS/USR, etc.
- Editor de pantalla WYSIWYG, teclado por IRQ (matriz/shift/repeticion),
  codigos de control, graficos C= y SHIFT, cursor parpadeante, scroll.
- Vectores RAM de pagina 3 (IRQ/BRK/NMI, E/S interceptable).
- Autoarranque de cartuchos CBM80, API init de cartuchos.
- **Bus IEC completo (verificado byte a byte contra el 1541 real en VICE):**
  envio, recepcion (con EOI), OPEN/CLOSE/CHKIN/CHKOUT serie, READST,
  LOAD/SAVE/VERIFY, `LOAD"$",8` (directorio) + LIST, y lectura del canal
  de comandos/errores (15) por INPUT#. Round-trip de programa BASIC
  (SAVE/NEW/LOAD/RUN) funciona. Comodines en nombres (matching del 1541) y
  LOAD encadenado (SA=0 en programa re-ejecuta desde el inicio conservando
  variables) verificados (sec. 9). Variables reservadas `ST`/`TI`/`TI$`
  operativas (ST lee KSTATUS $90; TI/TI$ leen el jiffy del KERNAL $A0).

### IEC: estado por fases
- **Parsing del BASIC (fases 1, 2a, 3): COMPLETO y verificado.**
  OPEN/CLOSE/LOAD/SAVE se parsean y registran en tablas (KLAT/KFAT/KSAT).
  `translate.py` redirige los dispatch del BASIC: CQLOAD->BLOAD,
  CQSAVE->BSAVE, CQOPEN->BOPEN, CQCLOS->BCLOSE.
- **Envio por el bus: FUNCIONA, VERIFICADO byte a byte.**
  Primitivas `KLISTN/KTALK/KSECND/KTKSA/KCIOUT/KUNLSN/KUNTLK` + `KISEND`,
  todas con SEI/CLI. `KCIOUT` hace envio DIFERIDO para el EOI. Verificado
  escribiendo ficheros SEQ/PRG y releyendolos con `c1541 -extract` (los
  bytes coinciden exactamente, sin byte extra; el EOI cae en el ultimo).
- **Recepcion: FUNCIONA, VERIFICADA byte a byte con EOI.** `KACPTR` lee
  bytes del talker; `CHKIN` envia TALK+TKSA, `CHRIN/GETIN` derivan a
  `KACPTR` via `KSERIN`. Lectura de un SEQ conocido `ABCDEFGH` -> bytes
  65..72 exactos, KSTATUS = 0 0 0 0 0 0 0 64 (EOI solo en el ultimo).
- **READST ($FFB7): IMPLEMENTADO.** `KREADST = lda KSTATUS / rts`. La
  variable `ST` del BASIC YA funciona (lee KSTATUS en $90 via CQSTAT, ver
  seccion 9). `PEEK(144)` sigue siendo equivalente.
- **LOAD ($FFD5) y SAVE ($FFD8): IMPLEMENTADOS y VERIFICADOS.**
  - `LOAD"prog",8,1` (absoluto, SA=1): carga a la direccion del fichero,
    fin+1 correcto en X/Y ($AE/$AF), bytes exactos en memoria.
  - `SAVE"x",8`: crea PRG valido (direccion de carga + programa tokenizado).
  - Round-trip BASIC: `SAVE -> NEW -> LOAD -> RUN` ejecuta el programa.
  - `BLOAD` con SA=0 relocaliza a TXTTAB, fija VARTAB=fin y llama `LNKPRG`
    ($A370, reenlace de lineas del BASIC). Ademas hace un CLR de punteros:
    iguala ARYTAB=STREND=VARTAB y FRETOP=MEMSIZ (sin tocar la pila). Sin
    esto, ARYTAB/STREND quedaban obsoletos (en el inicio del programa tras
    NEW) y al crear la 1a variable tras LOAD (p.ej. `a=5`) se corrompia el
    programa. Verificado: `load"rt",8 : a=5 : print a : list` da a=5 y el
    programa intacto.
  - **DEVICE NOT PRESENT**: OPEN/LOAD/SAVE a un dispositivo ausente dan
    `?DEVICE NOT PRESENT ERROR` y paran (no se cuelgan). La deteccion esta
    en `KISEND`: un timeout de handshake bajo ATN (KATNF bit7) pone ST bit7
    ($80), en fase de datos pone ST bit1 ($02). El ack de ATN lo da
    cualquier dispositivo del bus, asi que el caso real (dispositivo
    direccionado ausente con otro presente) se detecta en el timeout del
    frame-ack de la secundaria, no muestreando DATA tras el ATN.
    KOPEN/KSAVE abortan con codigo 5 si ven ST bit7 tras direccionar (KLOAD
    ya lo hacia tras KTKSA). Verificado contra dispositivo 9 ausente con el
    8 presente; sin regresion en el 8.

### CLAVE del protocolo LOAD/SAVE (descubierto y verificado)
El 1541 distingue LOAD de SAVE por el **numero de canal** de la secundaria,
NO por la SA de SETLFS:
- **LOAD usa siempre el canal 0**: OPEN con `$F0`, TALK/TKSA con `$60`.
- **SAVE usa siempre el canal 1**: OPEN con `$F1`, datos `$61`, CLOSE `$E1`.
La SA de SETLFS (el `,1` de `LOAD"x",8,1`) controla SOLO la relocalizacion
del lado C64 (SA=0 relocaliza a X/Y; SA!=0 usa la direccion del fichero),
NUNCA el canal IEC. Usar `$F0|SA`/`$60|SA` rompe el LOAD (manda canal 1).

### LOAD de cinta (datasette, dispositivo 1): IMPLEMENTADO y VERIFICADO

Decode clean-room del formato CBM de cinta, verificado end-to-end
(`LOAD"",1` + `RUN` carga y ejecuta un programa, comprobado en py65 con un
modelo del Timer B del CIA1 + interrupcion FLAG).

- **Enganche**: en `KLOAD`, rama dispositivo<4: `lda KFA / cmp #$01 / beq ->
  tape_load`; si no, error 9 como antes. El camino serie (>=4) intacto.
- **`tape_load`** (en espacio libre del KERNAL, ~$F463): guarda CINV y lo
  redirige a un manejador de cinta en CONVENCION CINV (no re-salva
  registros; epilogo `pla/tay/pla/tax/pla/rti` como KIRQ); CIA1 timer B
  continuo + deshabilita IRQ de timer A + habilita FLAG; motor on (`$01`
  bit5=0); lee cabecera y datos; al terminar restaura timer A, CINV y motor.
  Devuelve fin+1 en X/Y (clc) o error en A (sec), igual que el serie.
- **Formato** (codificador<->decodificador autoconsistente): dipolos de
  pulso (corto/medio/largo), marcador de byte (L,M), 8 bits LSB + paridad
  impar, fin de bloque (L,S); bloque = leader + cuenta atras de sync
  ($89..$81 copia1 / $09..$01 copia2) + datos + checksum XOR. Doble copia
  con recuperacion a nivel de copia (flag store/discard).
- **Memoria**: punteros en ZP libre ($A8-$AB); estado en el buffer de cinta
  ($0340-$0361); `tsav` (CINV guardado) en $033C; cabecera leida en $0362.
  CUIDADO con la colision que tuvo `tsav`: estaba en $0367 DENTRO del buffer
  de cabecera, y los bytes del nombre lo machacaban -> CINV a basura ->
  cuelgue tras cada load. Lo destapo la verificacion end-to-end. Movido a
  $033C (libre, debajo del scratch).
- **HECHO (refinamiento)**: casa nombre (`LOAD"NAME",1` escanea y salta los
  ficheros que no coinciden, prefijo estilo CBM; sin nombre carga el
  primero); mensajes PRESS PLAY ON TAPE / FOUND <nombre> / LOADING con
  espera del sense de PLAY ($01 bit4). Verificado end-to-end (LOAD+RUN) y
  con cinta de 2 ficheros (`LOAD"DOS"` salta UNO y carga DOS). REQUISITO de
  formato: el bloque de datos necesita un leader adecuado (las cintas CBM
  reales lo tienen). Causa: el IRQ procesa bloques de forma autonoma; si
  imprimir FOUND/LOADING tarda mas que el leader, la copia1 del bloque pasa
  durante la impresion y la lectura se desalinea (do_copy captura la copia2
  y luego espera una tercera inexistente -> cuelgue). Con leader largo el
  decode se arma durante el leader y va bien. El codificador de pruebas usa
  256 pulsos de leader en los bloques de datos.
- **HECHO (refinamiento)**: abort por RUN/STOP durante la carga. El jiffy
  esta deshabilitado durante la carga (IRQ redirigido al manejador de
  cinta), asi que la bandera $91 de STOP no se actualiza; se sondea la
  tecla DIRECTAMENTE leyendo la matriz (fila 7 / bit 7) en el spin de
  `do_copy`, throttled cada 256 vueltas para no bloquear el FLAG. El sondeo
  es inline y SIN sei (el IRQ de cinta no toca $DC00/01, no hay carrera; y
  el arnes py65 pierde edges durante sei al no modelar el latch del ICR).
  Al detectar STOP: `read_block` corta tras copy1 (sin esto, copy2 se
  cuelga si ya no hay pulsos), `tape_load` restaura (motor off, CINV,
  timer A) y salta al BREAK del BASIC (`jmp STOP`), volviendo a READY.
  Verificado: STOP durante carga normal aborta con BREAK; y STOP rescata el
  cuelgue de "nombre no encontrado" (`LOAD"ZZZ"` escanea, no halla, se
  cuelga buscando la siguiente cabecera; STOP -> BREAK, nada cargado).
- **LIMITES** (refinables, sobre base que funciona): no VERIFY;
  recuperacion a nivel de copia (no fusion byte a byte). SAVE de cinta no
  implementado.
- **NOTA de compatibilidad**: las longitudes de pulso y el esquema de sync
  son autoconsistentes (nuestro codificador<->decodificador). Para leer
  cintas C64 REALES habria que clavar las longitudes/sync exactos del
  estandar CBM (afinado posterior); el mecanismo esta probado.

---

## 6. Metodo de verificacion (caja negra contra 1541 real)

La unica forma fiable de validar el bus es **VICE true-drive** con la ROM
DOS del 1541 real como **periferico opaco** (equivale a probar contra
hardware real). Reglas de sala limpia para esa ROM:
- Vive FUERA del arbol del repo (`/home/claude/test_only/dos1541`), NUNCA
  se mira/desensambla/distribuye, NUNCA la referencia `build.sh`.
- Solo se comprueba su metadato (tamano/hash), nunca su contenido.

Arnes de prueba (resumen; detalle en los transcripts):
```
c1541 -format ... test.d64 ; c1541 test.d64 -write host.bin "nombre,s"
x64sc -kernal build/kernal_c64.bin -basic build/basic_c64.bin \
  -chargen bin/chargen.bin -drive8type 1541 -drive8truedrive \
  -dos1541 /home/claude/test_only/dos1541 -8 test.d64 \
  -warp -limitcycles 2e8 -keybuf "<programa>" -exitscreenshot out.png
c1541 test.d64 -extract  (verificar bytes con od -An -tx1)
```
Gotchas: GET#/GET en modo DIRECTO da "?ILLEGAL DIRECT ERROR" (usar
programa numerado + RUN); crear PRG host con `python3 bytes()` (el printf
de dash NO soporta `\xNN`); `PEEK(144)`=KSTATUS, `PEEK(174/175)`=$AE/$AF.
py65 (arnes) NO modela el bus ($DD00 es RAM): solo VICE valida el bus.

### Resumen de los bugs resueltos en el bus
1. **Timeout RFD en re-direccionamiento (@wr de KISEND):** al re-abrir un
   canal con fichero ya abierto, el 1541 tarda mas de ~0.9ms en soltar
   DATA (RFD). Solucion: timeout extendido de 24 bits con `KSERHI` ($A7),
   `cmp #$40` (~58ms).
2. **KACPTR reescrito:** (a) orden correcto del handshake: esperar CLOCK
   alto (RTS) ANTES de soltar DATA (RFD), no al reves; (b) muestrear DATA
   con **CLOCK alto** (ventana valida), no en la bajada (carrera con la
   liberacion de DATA por el talker). Timeout extendido en `@w2b` para no
   colgarse al leer mas alla del EOF.
3. **Canal LOAD/SAVE:** ver "CLAVE del protocolo" arriba.

### Detalle de KISEND (emisor) y KACPTR (receptor)
Emisor, por bit (LSB primero): fija DATA=bit, `KCLKHI` (reloj alto = bit
valido), `KSDLY` (~55us), `KCLKLO`, `KDATHI`. El dato es valido con CLOCK
alto. Receptor (espejo): espera CLOCK alto, suelta DATA (RFD), espera
CLOCK bajo con timeout corto (EOI), y por bit espera CLOCK alto, muestrea
DATA, espera CLOCK bajo; ack final con DATA bajo.

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
- **ARTEFACTO de timing del `-exitscreenshot`** (me costo varias iteraciones):
  el `-keybuf` inyecta ~1 char por jiffy, asi que el ultimo comando puede
  no haber TERMINADO de renderizar cuando se dispara el screenshot. Sintoma
  tipico: `LIST` "vacio" o salida ausente que en realidad SI funciona.
  Solucion: poner SIEMPRE una linea marcadora despues del comando que
  interesa (`... \n list \n print"fin-marcador" \n`); si aparece el
  marcador, lo de arriba ya se renderizo. No concluir "roto" sin marcador.
- **ZP del BASIC, NO la del C64 real**: `TXTTAB=$28`(40), `VARTAB=$2A`(42),
  `ARYTAB=$2C`(44), `STREND=$2E`(46), `FRETOP=$30`(48), `MEMSIZ=$34`(52).
  Para depurar con PEEK usar PEEK(40/41) y PEEK(42/43), NO PEEK(43)/PEEK(45)
  (esas son las del C64 de Commodore y aqui dan basura).
- **`INPUT#`/`GET#` solo en modo PROGRAMA**: en modo directo dan
  `?ILLEGAL DIRECT`. Para probar el canal de comandos usar un programa
  numerado + RUN, nunca una linea directa.

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

HECHO y VERIFICADO (esta sesion): envio, recepcion, READST, LOAD, SAVE,
VERIFY, round-trip de programa BASIC, `LOAD"$",8` (directorio) + LIST, y
lectura del canal de comandos/errores (15) por `INPUT#` (devuelve el
"73,CBM DOS V2.6 1541,00,00" de power-up). VERIFY da "?VERIFY ERROR" en
discrepancia (BVERIFY, con CQVERF redirigido en translate.py). Ver sec. 5/6.

HECHO y VERIFICADO (esta sesion, contra el 1541 real en VICE true-drive):
- **Comodines en nombres**: ya funcionaban sin codigo. El nombre se envia
  verbatim por el bus (bucle `@nm` de KLOAD/KSAVE/KOPEN, sin filtrar `*`/`?`);
  el matching lo hace el DOS del 1541. Verificado: `LOAD"TE*",8` casa con
  "TEST" y carga. No hay nada que implementar en el lado C64.
- **Semantica re-RUN del LOAD encadenado (SA=0)**: implementada. Ver detalle
  abajo. `10 LOAD"PARTE2",8` carga PARTE2 y re-ejecuta desde su primera
  linea, conservando variables.

Pendiente:
1. Post-1.0: chargen propio; recolector de basura de cadenas lineal (desde
   descripcion algoritmica publica, NUNCA desensamblados); ROM libre del
   1541 (proyecto hermano).

### LOAD encadenado (re-RUN, SA=0) y comodines (HECHO)
Implementado en `BLOAD` (`@lok`, src/kernal.s). Tras un LOAD con SA=0 se fija
VARTAB=fin y se reenlaza (LNKPRG); a partir de ahi el comportamiento depende
del modo (interfaz observable, spec publica del LOAD = nivel B):
- **Directo** (CURLIN+1=$FF): CLR de punteros (ARYTAB=STREND=VARTAB,
  FRETOP=MEMSIZ) y RTS -> READY. Identico al comportamiento previo (fix de
  corrupcion al crear la 1a variable tras un LOAD directo). Sin tocar pila.
- **Programa** (LOAD encadenado): NO se borran variables (el encadenado pasa
  datos entre partes, por spec). Se reapunta el texto al inicio del programa
  cargado (`STXTPT`, TXTPTR=TXTTAB-1), se repone la pila a la base (`STKINI`,
  que ademas prohibe CONT y NO toca variables) y se re-ejecuta desde la
  primera linea (`JMP NEWSTT`). STKINI evita acumular marcos de pila entre
  saltos de cadena.
Simbolos del BASIC MIT usados (alcanzables como LNKPRG): STXTPT, STKINI,
NEWSTT. STKINI solo repone SP + temporales de cadena + OLDTXT+1 + SUBFLG;
no toca ARYTAB/STREND/VARTAB/FRETOP, por eso conserva variables.

Verificado en VICE true-drive contra el 1541 real:
- Re-RUN: part1 (`10 print"parte uno":20 load"part2",8:30 print"no-deberia-verse"`)
  + part2 (`10 print"parte dos ok"`) -> imprime "parte uno" y "parte dos ok";
  la linea 30 de part1 NO se ejecuta (re-ejecuta part2 desde el inicio).
- Variables conservadas: con partes de IGUAL longitud (VARTAB no se mueve),
  vp1 fija x=42 y vp2 imprime "x vale 42". Caveat de spec (igual que CBM): si
  la parte cargada tiene distinta longitud, VARTAB se desplaza y las
  variables previas quedan desalineadas (no se borran, pero pueden no
  localizarse). El encadenado fiable usa partes de longitud comparable.
- Comodin: `LOAD"TE*",8` carga "TEST".
- Sin regresion en modo directo: `load"test",8 : a=5 : print a : list` da
  a=5 y el programa intacto.
NOTA: esta semantica se valida SOLO en VICE (necesita un LOAD real completo,
que py65 no modela). No hay test py65 dedicado; la evidencia es la de VICE.

### Dispositivo no presente y CLR tras LOAD (HECHO, esta sesion)
- OPEN/LOAD/SAVE a un dispositivo ausente dan `?DEVICE NOT PRESENT ERROR`
  y paran (no se cuelgan). Deteccion en el timeout de handshake de `KISEND`
  bajo ATN (ST bit7). KOPEN/KSAVE abortan con codigo 5; KLOAD ya lo hacia.
  Ver detalle en la sec. 5.
- `BLOAD` SA=0 ahora hace CLR de punteros (ARYTAB=STREND=VARTAB,
  FRETOP=MEMSIZ) tras fijar VARTAB. Corrige un bug pre-existente: crear una
  variable tras LOAD corrompia el programa. Ver detalle en la sec. 5.

### Vectores RAM de pagina 3 (HECHO)
Los vectores de E/S de pagina 3 (`$031A-$0333`: IOPEN/ICLOSE/ICHKIN/ICKOUT/
ICLRCH/IBASIN/IBSOUT/ISTOP/IGETIN/ICLALL/USRCMD/ILOAD/ISAVE) apuntan a las
rutinas reales en `KVECTAB` y se instalan en reset via `KRESTOR`. Las
entradas `$FFxx` del KERNAL saltan INDIRECTO a traves de ellos (p.ej.
`$FFC0 OPEN` = `jmp ($031A)`, `$FFD5 LOAD` = `jmp ($0330)`). Los manejadores
del BASIC (BOPEN/BCLOSE/BLOAD/BSAVE/BVERIFY) llaman por los vectores
(`jsr $FFC0`, `jsr $FFD5`, etc.), asi que la E/S del BASIC es interceptable
(caso de uso: fast-loaders). USRCMD ($032E) queda como KSTUB (vector libre
sin uso en C64). Verificado en VICE: enganchar ILOAD a una rutina propia
intercepta el `LOAD` del BASIC y, encadenando al KLOAD real, la carga
funciona (marca=1, dato cargado correcto). Test py65 `test_vectores.py`
comprueba que quedan instalados y distintos (no re-stubeados).

### Mensajes SEARCHING/LOADING/SAVING/VERIFYING (HECHO)
LOAD imprime "SEARCHING FOR <nombre>" + "LOADING"; VERIFY "VERIFYING";
SAVE "SAVING <nombre>". Solo en modo directo: `BLOAD/BSAVE/BVERIFY` llaman
a `KDIRMSG`, que pone `KMSGFL` ($9D) bit7 si `CURLIN+1=$FF` (directo) y lo
limpia en programa, asi un cargador `10 LOAD...` carga en silencio (igual
que CBM). Las rutinas `KSRCHMSG/KLDGMSG/KSAVMSG` imprimen via STROUT/CHROUT
gated en bit7. Verificado: directo muestra; programa silencioso y continua.

### Variables reservadas ST/TI/TI$ (RESUELTO)
El BASIC MS de MIT YA trae el manejo de ST/TI/TI$ en `ISVAR` (activo con
los flags `EXTIO=1`/`TIME=1` de la config CBM). Solo leian direcciones que
no coincidian con nuestro KERNAL. Arreglado en `translate.py` (config, sin
tocar el upstream):
- `ST`: el BASIC leia `CQSTAT`=$96; nuestro KERNAL guarda el estado en $90
  (KSTATUS). Cambiado `CQSTAT` a 144 ($90). `get#...:if st=0` ya funciona.
- `TI`/`TI$`: el reloj `CQTIMR` estaba en $8D (reloj propio del MS, que
  nadie incrementaba). Apuntado a $A0 (`CQTIMR`=160), el reloj jiffy del
  KERNAL que la IRQ incrementa a 60Hz (big-endian $A0=alto, igual que el
  MS). `GETTIM` lee 5 bytes desde `CQTIMR-2`=$9E; `$9E/$9F` los limpia
  RAMTAS y nadie los reescribe, asi la mantissa alta queda 0 y el valor =
  jiffies. Verificado: `TI` avanza, `TI$` formatea HHMMSS, y `TI$="123456"`
  fija el reloj (round-trip exacto, ti=2717760 jiffies).

Pendiente general: consulta a abogado de PI antes de publicar. CTRL+letra
sin asignar es deliberado.

NOTA de test py65: `test_iec_fase1.py` "CLOSE compacta" ahora prueba la
compactacion de tablas con dispositivos NO-serie (dev 0), porque CLOSE de
un dispositivo serie hace E/S de bus que py65 no modela (el handshake
necesita respuestas dinamicas). La compactacion serie se valida en VICE.

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
