# Continuidad del proyecto

Este documento es la **fuente de verdad** para retomar el trabajo tras
una pausa. Resume estado, arquitectura, metodo y lecciones. Leelo entero antes de tocar nada.

Ultima revision: 20 oct 2026 (auditoria completa del repo). Lo que se
hizo fuera del repo y se perdio esta en la seccion 12; las erratas del
historial git, en la seccion 13.

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
- Arranque limpio con la disposicion del C64: linea en blanco,
  `**** PASCUAL'S BASIC ****` (centrado, nombre propio en vez de la marca
  de Commodore; sustituido en translate.py), linea en blanco,
  `64K RAM SYSTEM  38911 BASIC BYTES FREE`, `READY.`
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

### Cambios del 18 jun al 3 jul (no recogidos antes en este documento)
- Teclado: tabla CTRL completa (CTRL+letra emite $01-$1A, CTRL+simbolo el
  resto), simbolos C=+@/+/libra, F1-F8 ($85-$8C) y SHIFT+RUN/STOP ($83, que
  mete `LOAD`+CR+`RUN`+CR en el bufer). Fuente: comportamiento publico
  (sta.c64.org). test_keymods: 64 casos.
- SETTMO ($FFA2): guarda A en KTIMOUT ($0285); antes era un stub.
- BLOAD (43f1eba): si una carga relocalizada deja menos de 2 bytes, fuerza
  un programa vacio ($00 $00) antes de LNKPRG. Validado en VICE el 21 oct
  (seccion 20).
- KUNLSN (b876e1c): el $3F se cargaba antes de KATNLO/KCLKLO/KATNDLY, que
  destruyen A; ahora se recarga justo antes de KISEND. Verificado en
  simulacion dual C64+1541 y en VICE (dos `LOAD"$",8` sin disco seguidos
  vuelven a READY).
- 20 oct: `bin/` regenerado (estaba parado desde af65a4e) y bit de
  ejecucion restaurado en build.sh y tests/run_all.sh.
- 21 oct: SAVE de cinta arreglado (llevaba roto desde 726cbda: el codigo
  crecio por encima del trampolin de $FD15 y el build lo piso sin avisar) y
  RAMTAS deja de escribir 0 en $00/$01 (`sta $0002,X` en modo pagina cero
  daba la vuelta). El build aborta ahora si dos secciones .org se solapan.
  Arnes de datasette (tests/cinta.py) y tests/test_cinta.py.
- 21 oct: tier-3 rehecho CON la cinta dentro (ver seccion 14).
- 20 oct: el buffer de linea del editor (KLINE) pasa de $033C a $0200.
  En $033C (828, buffer de cinta) cada linea tecleada machacaba las
  rutinas de usuario (`POKE828,96` + `SYS828` se colgaba). En $0200
  comparte el BUF del BASIC sin conflicto: INLIN guarda el caracter k en
  la posicion <= k despues de que el editor lo sirva. Test:
  tests/test_buffer828.py.

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

> **Superado el 21 oct 2026.** Esta subseccion y la de SAVE describen la
> version de julio. La prueba en VICE contra un C64 real (seccion 15)
> mostro que no leia cintas reales ni grababa en el formato real; lo de
> "verificado contra valores reales" y la tolerancia [-10 %, +45 %] se
> midieron con un arnes que reproducia lo mismo que grababa. El estado
> actual esta en la seccion 15.


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
  con fusion byte a byte: copia1 se almacena (los bytes con error de paridad
  se pasan con flag bderr para no desalinear); si copia1 falla el checksum,
  copia2 se lee en modo merge y sobrescribe solo los bytes que trae con
  paridad buena; el bloque fusionado se valida re-XOR contra el checksum
  esperado (chk_merged). Recupera un bloque aunque cada copia tenga errores
  en bytes distintos; falla solo si el MISMO byte esta mal en ambas.
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
- **HECHO (refinamiento)**: VERIFY de cinta. `VERIFY"NAME",1` compara la
  cinta contra memoria y pone ST bit4 ($10) en discrepancia; el comando
  BASIC muestra "?VERIFY ERROR" si hay diferencia y vuelve a READY si todo
  coincide. Detalles: el flag KVERCK (load=0 / verify=1) lo pone KLOAD desde
  A en la entrada de $FFD5; el comando BVERIFY hace `lda #$01` antes del
  `jsr $FFD5`. La CABECERA se almacena SIEMPRE (KVERCK se guarda en tverify
  y se limpia al entrar a tape_load; se restaura en tl_match para el bloque
  de datos), porque si no, la cabecera se compararia contra basura y el
  nombre/direcciones saldrian mal. En el bloque de datos, bb_data compara
  (dest) contra el byte decodificado en vez de almacenar, y pone ST bit4 en
  discrepancia (igual que la ruta serie). El mensaje "VERIFYING" lo elige
  KLDGMSG segun KVERCK. Verificado KERNAL-level (match: ST=$00, sin escribir
  memoria; mismatch: ST=$10) y end-to-end via BASIC (mismatch -> "?VERIFY
  ERROR"; match -> READY sin error).
- **HECHO (refinamiento)**: fusion byte a byte de las dos copias en LOAD
  (ver descripcion del decode arriba). Verificado con inyeccion de errores
  (test_merge_chars: copy1[i]+copy2[j] con i!=j se recupera; mismo byte malo
  en ambas falla; varios errores por copia en posiciones distintas se
  recuperan). Sin regresion en VERIFY, STOP ni matching.
- **LIMITES** (refinables, sobre base que funciona): SAVE de cinta no
  implementado. VERIFY usa recuperacion a nivel de copia (no aplica la
  fusion byte a byte; es una comprobacion, no una carga).
- **HECHO (refinamiento)**: correccion adaptativa de velocidad. El umbral
  corto/medio/largo se recalcula a partir del pulso corto del leader, que se
  mide al vuelo (Sest, suavizado (3*Sest+dur)/4) y se congela al primer
  marcador (pulso >= 1.5*Sest). Los umbrales son TSM=Sest*1.1875 y
  TML=Sest*1.5625 (puntos medios de las ratios reales medio/corto=1.375 y
  largo/corto=1.79). La calibracion es EFECTO COLATERAL del decode: los
  pulsos del leader siguen fluyendo por la maquina de estados (clasificados
  como cortos, ignorados con state=0); NO se saltan. Saltarlos (jmp setlast)
  desincronizaba el traspaso header->dato del decode IRQ-continuo y hacia que
  un do_copy sobre-leyera el bloque siguiente (bug detectado y corregido en
  esta iteracion). Tolerancia medida ~[-10%, +45%] de desviacion uniforme de
  velocidad (antes -4%/+8% con umbrales fijos), monotona. Sin regresion en la
  bateria de cinta ni determinista.
- **VERIFICADO contra valores reales**: el esquema de codificacion coincide
  con el formato CBM real (corto/medio/largo = nuevo-dato/marcador, fin de
  bloque, bits; 8 bits LSB, paridad impar, countdown de sync). Cargan las
  tres: canonico .TAP (384/528/688 ciclos), PAL (347/504/662) y NTSC
  (360/524/687). El KERNAL original tambien usa correccion adaptativa.
- **Traspaso cabecera->datos con leaders cortos (RESUELTO)**: con un leader de
  datos corto (p.ej. 32/20, que es lo que genera `tape_save` y el codec de
  pruebas), la copia1 del bloque de datos se consume durante la impresion de
  FOUND/LOADING; `do_copy` acaba sincronizando con la copia2 (lee los datos
  bien) y luego, al pedir descartar la copia2 que ya no existe, se quedaba
  esperando input para siempre (cuelgue). Es decir: el LOAD via BASIC leia los
  datos correctos pero NO retornaba (BASIC nunca reenlazaba el programa). Se
  corrigio con un **timeout de inactividad de pulsos en `do_copy`**: el IRQ
  incrementa `tpulse` ($0384) en cada pulso (en `setlast`); el spin de
  `dcwait`, en su sondeo throttled (cada 256 vueltas, junto al de STOP),
  cuenta las vueltas sin pulso nuevo en `tidle` ($03A0) y, si pasa `DCTMO`
  (~1.6s de silencio), abandona con blkstat=0. Con leaders largos (cintas
  reales) no se dispara nunca; con leaders cortos, en vez de colgarse, el LOAD
  retorna (con los datos ya leidos -> exito, y BASIC reenlaza). Bonus:
  `LOAD"inexistente",1` tambien retorna con error en vez de colgarse. Si en el
  futuro se soportan cintas reales con huecos entre bloques > ~1.6s habria que
  subir DCTMO. Validado: test_leader_corto.py (32/20 retorna), test_e2e_basic
  (reenlace correcto a $080B), sin regresion en merge/STOP/VERIFY/namematch.

### SAVE de cinta: ESCRITURA completa, integrada en KSAVE (HECHO y VERIFICADO)

> **Superado el 21 oct 2026.** Esta subseccion y la de SAVE describen la
> version de julio. La prueba en VICE contra un C64 real (seccion 15)
> mostro que no leia cintas reales ni grababa en el formato real; lo de
> "verificado contra valores reales" y la tolerancia [-10 %, +45 %] se
> midieron con un arnes que reproducia lo mismo que grababa. El estado
> actual esta en la seccion 15.


El espejo del decode de LOAD: la maquina de estados que EMITE los pulsos de un
bloque CBM completo (2 copias). YA esta conectada: `tape_save` escribe un
fichero (cabecera + datos) y KSAVE la invoca para dispositivo 1, asi que el
comando `SAVE"NOMBRE",1` de BASIC funciona. Round-trip validado por el punto de
entrada oficial KSAVE (`$FFD8`) con el jiffy (timer A) vivo.

- **Diseno (overhead constante)**: la IRQ (`whandler`, convencion CINV) carga
  en Timer B el pulso ya precomputado, togglea `$01` bit3 (flanco de
  escritura) y rearma el timer PRIMERO; el avance del estado (`jsr wgen`) va
  DESPUES. El overhead de la IRQ es asi constante y aditivo (~69 ciclos:
  S->453, M->597, L->757).
- **`tape_wblock`** escribe un BLOQUE = copia1 (countdown $89..$81 + datos +
  checksum) + copia2 (countdown $09..$01 + datos + checksum), ENCADENADAS sin
  hueco (copia2 arranca tras el marcador de fin de copia1). El llamador deja
  wptr=inicio (=$C1/KSAVPTR, en pagina cero para `(wptr),y`), wend=fin+1,
  wlcnt=leader1, wleader2=leader2. Variables de escritura en $0386-$039D; el
  bloque `wbyteadv`+`wcalcpar` vive reubicado en el hueco $FDA6-$FF5A.
- **Cada byte**: marcador [L,M] + 8 bits LSB-primero (dipolo por bit) + dipolo
  de paridad impar. Es el codificador autoconsistente del LOAD, en 6502.
- **VALIDACIONES**: bloque de 1 copia identico a `cod_copia` (292 pulsos);
  bloque de 2 copias identico a `cod_bloque` (592 pulsos); ROUND-TRIP
  SAVE->LOAD (el SAVE de la ROM genera cabecera+datos, los lee el LOAD de la
  ROM): programa BASIC cargado correcto salvo el byte 0 (el RE-ENLACE de
  linea de BASIC, $080B recalculado, ortogonal al SAVE); bloque de datos del
  SAVE byte-identico al codificador. LOAD sin regresion.
- **Cuatro bugs corregidos**: (1) `(wptr),y` exige pagina cero (wptr a $C1);
  (2) paridad: no reusar A para el shift del dato y el toggle (contar en Y con
  `iny`); (3) espacio: el codigo crecio mas alla de `.org $FD15` y los
  trampolines lo machacaban (reubicar al hueco grande); (4) copia2 no
  reseteaba wptr (anadido wsptr).
- **`tape_save`** (`$FE56`, espejo de `tape_load`): escribe el fichero entero.
  (1) "PRESS RECORD & PLAY ON TAPE" (`MRECORD`) + espera del sense (`$01`
  bit4=0); (2) "SAVING <nombre>" (`KSAVMSG`); (3) motor on + DESHABILITA el
  jiffy (`$DC0D=$01`, lee `$DC0D` para limpiar pendientes); (4) guarda el
  inicio en `tsstart` (`$039E`), porque el bloque de cabecera machaca
  wptr=`$C1`; (5) construye la cabecera de 21 bytes en `$0362` (libre durante
  SAVE) [ftype=1, inicio, fin, nombre(16, pad $20)]; (6) bloque cabecera
  (wptr=`$0362`, wend=`$0377`, leader 40/24); (7) bloque datos (wptr=tsstart,
  wend=KLDPTR, leader 32/20); (8) motor off + REHABILITA el jiffy
  (`$DC0D=$81`); (9) `clc/rts`.
- **Timer A (jiffy)**: `tape_wblock` NO lo toca (solo habilita el timer B).
  `tape_save` lo deshabilita ANTES de llamar a `tape_wblock` (antes de instalar
  whandler) y lo rehabilita al final, asi el jiffy no genera pulsos espurios
  durante la escritura. Confirmado: 0 disparos del jiffy durante la escritura
  activa.
- **Integracion en KSAVE** (rama dispositivo < 4, tras montar KSAVPTR=inicio y
  KLDPTR=fin+1): `cmp #$01 / beq @tape` (dispositivo 1 = cinta) antes del error
  9; `@tape: jmp tape_save`. El SAVE serie (>=4) intacto.
- **VALIDACIONES adicionales**: round-trip `tape_save`->LOAD 12/12 bytes
  (test_tape_save.py); idem con el jiffy disparandose, timer A gestionado
  (test_tape_save_jiffy.py); round-trip por el punto de entrada KSAVE `$FFD8`
  con la convencion de registros de BASIC (A=`$2B`, X/Y=VARTAB), retorno sin
  error, 12/12 bytes (test_ksave.py); y ROUND-TRIP BASIC COMPLETO TECLEADO en
  dos maquinas (test_basic_rt.py): la maquina A arranca BASIC, teclea un
  programa y `SAVE"",1` (capturando los pulsos), la maquina B arranca BASIC y
  teclea `LOAD"",1` alimentandolos; el programa se carga byte-identico, sin
  error. Esto cubre el camino entero (editor de BASIC, parser de SAVE, KSAVE,
  tape_save, los pulsos, tape_load, parser de LOAD): ya no queda nada del
  camino de SAVE sin probar end-to-end.

---

## 6. Metodo de verificacion (caja negra contra 1541 real)

La unica forma fiable de validar el bus es **VICE true-drive** con la ROM
DOS del 1541 real como **periferico opaco** (equivale a probar contra
hardware real). Reglas de sala limpia para esa ROM:
- Vive FUERA del arbol del repo (`~/test_only/dos1541`), NUNCA
  se mira/desensambla/distribuye, NUNCA la referencia `build.sh`.
- Solo se comprueba su metadato (tamano/hash), nunca su contenido.

Arnes de prueba (resumen):
```
c1541 -format ... test.d64 ; c1541 test.d64 -write host.bin "nombre,s"
x64sc -kernal build/kernal_c64.bin -basic build/basic_c64.bin \
  -chargen bin/chargen.bin -drive8type 1541 -drive8truedrive \
  -dos1541 ~/test_only/dos1541 -8 test.d64 \
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
- **ZP del BASIC = la del C64** desde la seccion 17: `TXTTAB=$2B`(43),
  `VARTAB=$2D`(45), `ARYTAB=$2F`(47), `STREND=$31`(49), `FRETOP=$33`(51),
  `MEMSIZ=$37`(55), `TXTPTR=$7A`(122). (Antes estaba 3 bytes por debajo:
  TXTTAB en $28.)
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
0. Antes de seguir con funciones nuevas: recuperar lo perdido (sec. 12),
   (la guarda de BLOAD quedo validada en la seccion 20 y el hueco de ZP
   de AUDITORIA.md en la 17).
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
docs/       PROCEDENCIA.md (legal), AUDITORIA.md, CONTINUIDAD.md (este),
            AUDITORIA_SIMILITUD.md (no-similitud, 20 oct)
tests/      arnes.py (clase Maquina, py65) + test_*.py + run_all.sh
tools/      comparador_ciego.py (auditoria de no-similitud; sin ROMs)
build.sh    construye todo
```

Editar SIEMPRE en `src/`; `build.sh` copia a `build/` y construye. Los
tests leen `build/basic_c64.bin`, `build/kernal_c64.bin` y
`build/rom_listado.txt`, asi que **reconstruir antes de testar**.

Tests rapidos: `cd tests && python3 test_humo.py` (etc.). `run_all.sh`
es lento; usar ficheros sueltos con `timeout` para regresion rapida.

---

## 11. Convenciones

- Documentacion, comentarios y mensajes de commit en **espanol**.
- **Sin guion largo** en textos y documentos: usar comas, puntos, dos
  puntos o parentesis.
- Ante un fallo no reproducible, conseguir primero la receta exacta que
  lo produce y no cambiar codigo hasta reproducirlo.

---

## 12. Pendiente de recuperar (trabajo hecho fuera del repo y perdido)

Inventario de la auditoria del 20 oct 2026. Se busco en GitHub, en el
clon local (C:\repo, parado en 4207426) y en Descargas/Escritorio: nada
de esto existe ya como fichero. Queda el registro de lo que se hizo, que
permite rehacerlo.

**Junio, cinta (datasette):**
- Arnes py65 con modelo de Timer B del CIA1 + interrupcion FLAG.
- Codificador de referencia (`cod_copia`, `cod_bloque`) y la cache de
  arranque (boot-cache) que evitaba ~158 s de boot por test.
- Tests: test_leader_corto, test_e2e_basic, test_merge_chars,
  test_namematch, test_stop_load / notfound, realvals.
- Consecuencia: el subsistema de cinta (~1000 lineas) no tiene hoy ningun
  test automatico en el repo.

**Junio y julio, bus IEC:**
- Arnes VICE true-drive con `testdisk.d64` y la simulacion dual C64+1541
  usada para KUNLSN. Los tests del repo solo cubren el parsing (fases 1,
  2a, 3), no el bus.

**Agosto, tier-3 (direcciones canonicas) y layout robusto:** (REHECHO el
21 oct con otro metodo y con la cinta dentro; ver seccion 14. Lo de abajo
queda como registro de la version perdida.)
- RESET en $FCE2 (arregla SYS 64738), entrada IRQ $FF48, NMI $FE43 con
  despacho $FE47 (y arreglo del contrato $0318: la ruta NMI consumia 6
  bytes de pila en vez de 3), BRK $FE66, salida RTI $FEBC, IRQ principal
  $EA31, salida IRQ $EA81. Para hacer sitio se quito la cinta y se
  reubicaron KCHRIN ($F44F), KCLKHI ($F621), KTALK/KSECND ($F62A).
- Deduplicacion KSENDNAME (envio del nombre por el bus comun a OPEN/LOAD/
  SAVE): 38 bytes.
- Placement directo de RESTOR/RAMTAS/IOINIT en $FD15/$FD50/$FDA3 (CINT no
  cabe en su hueco y sigue como trampolin).
- Layout robusto: 118 directivas .org, una por rutina de entrada, con
  binario identico al tier-3. Leccion clave: sin anclas, cualquier cambio
  de tamano desplaza todo hasta el siguiente .org y rompe el BASIC; hay
  que correr la suite completa, no solo el arranque.
- Infraestructura: tools/run_gate.sh, tests/test_nmi.py,
  tests/test_wbytepulse.py, tools/check_reproducible.py,
  tools/packing_report.py, tools/canonical_kernal.map.
- Reintroducir la cinta en el tier-3 no cabia sin desplazar codigo
  (faltaban 617 bytes contiguos; la compresion recupero 291 sin tocar la
  fusion de copias).

Estado del orden propuesto: (1) arnes de cinta + tests: HECHO (21 oct);
(2) tier-3: HECHO (21 oct, seccion 14); (3) arnes VICE en el repo, sin la
ROM del 1541: pendiente.

---

## 13. Fe de erratas del historial git

No se reescribe la historia publicada (sin force push). Lo que dicen mal
algunos commits queda corregido aqui:

| Commit | Dice | Realidad |
|--------|------|----------|
| b324db0 | "Update" | Cambio de permisos hecho desde Windows: quito el bit de ejecucion a build.sh y tests/run_all.sh. Corregido el 20 oct. |
| 020c21c, 97bae4e | "Update README.md" | Editados en la web: anaden la captura de pantalla; el segundo dejo la imagen pegada a "## Status" y rompio el titulo. Corregido el 20 oct. |
| 9624179 .. b876e1c | (no lo mencionan) | Cambiaron src/kernal.s sin regenerar bin/: las ROMs publicadas quedaron desfasadas hasta el 20 oct. |
| 43f1eba | "Pendiente de validacion en VICE" | Validado el 21 oct (seccion 20). |
| b876e1c | `#\$3F`, `"\$",8` | Las barras invertidas son un escape que se colo en el mensaje: se refiere a `#$3F` y `LOAD"$",8`. |
| 4207426 | "Merge branch 'main' of d:/pascuals-basic.bundle" | Merge de los commits de la sesion de banner (60a09ac, af65a4e) con los tres commits hechos en la web; sin conflictos. |
| rama fix-bload-guard | | Ya fusionada (PR #1). Se puede borrar en GitHub. |
| 726cbda | "Implementar SHIFT+RUN/STOP" | Sin saberlo, empujo el codigo por encima de $FD15 y rompio el SAVE de cinta (corregido el 21 oct en 930c9b9). |

---

## 14. Mapa del KERNAL (tier-3, 21 oct 2026)

Las direcciones internas que usan juegos y cartuchos estan en su sitio
canonico. Direcciones y semantica: interfaz publicada (nivel A/B). Cada
una tiene su test en tests/test_canonicas.py.

| Direccion | Que hay | Contrato |
|-----------|---------|----------|
| $EA31 | KIRQ, manejador principal del IRQ | destino por defecto de $0314; los programas encadenan con JMP $EA31 |
| $EA81 | salida del IRQ (PLA/TAY/PLA/TAX/PLA/RTI) | JMP $EA81 sale sin el trabajo del KERNAL |
| $FCE2 | KRESET | vector RESET; SYS 64738 |
| $FD15 | KRESTOR (colocado directo, sin trampolin) | RESTOR interno |
| $FD50 | KRAMTAS (directo) | RAMTAS interno |
| $FDA3 | KIOINIT (directo) | IOINIT interno |
| $FE43 | entrada NMI: SEI + JMP ($0318) | el manejador de usuario ve solo PC+P |
| $FE47 | NMI por defecto: apila A/X/Y y sigue en KNMI | destino por defecto de $0318 |
| $FE66 | BRK por defecto: arranque en caliente (KWARM) | destino por defecto de $0316 |
| $FEBC | salida comun (PLA/TAY/PLA/TAX/PLA/RTI) | JMP $FEBC |
| $FF48 | KIRQENT, entrada hardware IRQ/BRK | vector IRQ |
| $FF5B | trampolin a KCINT (CINT no cabe en su hueco) | CINT interno |

Cambios de comportamiento respecto a julio, ambos hacia lo documentado:
- NMI: antes la entrada apilaba A/X/Y ANTES de saltar por ($0318), asi que
  un manejador de usuario que acababa en RTI volvia a basura. Ahora solo
  SEI + JMP ($0318); el apilado lo hace el manejador por defecto ($FE47).
- BRK por defecto: antes restauraba y seguia (RTI); ahora arranque en
  caliente a READY con el programa intacto, como el C64.

Como esta organizado src/kernal.s:
- La seccion principal (`.org $E200`) fluye hasta $EA30; KIRQ va en
  `.org $EA31` con su salida en `.org $EA81`; el resto fluye desde `.org
  $EA87` hasta antes de $FCE2.
- Las islas de direccion fija (las de la tabla de arriba) y las islas de
  relleno (mensajes de error, KERRTAB, KIOMSG) estan al final, antes de la
  marca `;;; ISLAS-FIN`. Las cadenas de mensajes se repartieron en los
  huecos que dejan las canonicas porque son datos sin dependencias.
- El orden de las secciones en el fichero da igual: c64_build.py las
  coloca por su .org y ABORTA el build si dos se solapan. Al final imprime
  el espacio libre ("KERNAL libre: N bytes; huecos mayores: ...").
- Para meter codigo nuevo: si la seccion donde va se pasa, el build lo
  dice; mover entonces alguna rutina o cadena autocontenida a un hueco.

La cinta sigue completa (LOAD/SAVE/VERIFY, fusion de copias, velocidad
adaptativa): no hizo falta recortarla. Lo de agosto no cabia porque se
intentaba meter la cinta como bloque contiguo en un hueco; ahora se
movieron otras cosas (cadenas) a los huecos pequenos.


## 15. Prueba en VICE y cinta real (21 oct 2026)

Las ROMs se probaron en VICE 3.10 (x64sc) sin pantalla: `xvfb-run`,
`-keybuf` con el texto en minusculas, `-limitcycles` y
`-exitscreenshot`. Para la cinta: `-1 fichero.tap`, `+virtualdev1` y
`-moncommands` con `tapectrl 4` (grabar) o `tapectrl 1` (reproducir).
Para el disco: `-drive8truedrive +virtualdev8` y la ROM del 1541 como
periferico opaco.

Funcionaban ya:
- arranque;
- BRK con arranque en caliente;
- SYS 64738;
- IRQ encadenada por $EA31;
- NMI de usuario por $0318;
- disco 1541 (SAVE, VERIFY, `LOAD"$",8`, LOAD y RUN).

La cinta NO funcionaba con un C64 real. Como C64 de referencia se uso la
ROM original en VICE, como caja negra (ver `docs/PROCEDENCIA.md`, regla 2,
uso c). Fallos:

1. **Lector demasiado lento.** El manejador de FLAG tardaba unos 398
   ciclos por pulso y el pulso corto real dura unos 376: iba perdiendo
   pulsos y las medidas salian corridas. Los tests no lo veian porque
   nuestro grabador generaba pulsos mas largos (ver 2) y el arnes
   reproducia lo mismo que grababa.
2. **Grabador con otra forma de onda.** Emitia un flanco por pulso. En el
   formato CBM cada pulso es un ciclo completo de la linea, de subida a
   subida, asi que las cintas salian al doble de duracion y con pulsos
   mezclados.
3. **Formato recortado.** Cabecera de 21 bytes en vez de 192, y guias de
   20 a 40 pulsos.
4. **Variables solapadas.** `qd` y `tpulse` compartian $0384.

Arreglos en `src/kernal.s`:
- **Lector (HDLR).** Camino comun de unos 200 ciclos. La calibracion con
  la guia solo mide: media exponencial de 1/4, umbrales recalculados cada
  16 pulsos de guia, y el marcador solo cierra la guia tras 16 pulsos
  seguidos dentro de banda. Se recupera solo de ruido al arrancar el
  motor y de la vuelta del timer en una pausa.
- **Paridad.** Hubo un bug de paridad en la primera version del arreglo:
  ROR antes de guardar el bit.
- **Grabador.** Timer B en modo continuo: el CIA recarga del latch, asi
  que los flancos no dependen del manejador. Subida al empezar el pulso y
  bajada a la mitad. El bucle principal precalcula el pulso siguiente.
- **Formato.** Guias de $6A00 y $1500, 79 pulsos entre copias, 78 al
  final. Cabecera de 192 bytes con relleno $20, tipo 1 o 3 segun SA.
  Pausa de unos 0,33 s entre la cabecera y los datos, como el C64.
- **LOAD.** Un fichero de tipo 3 va a su direccion. Ignora bloques que no
  son de programa. Para en una cabecera de tipo 5.
- **Pantalla apagada mientras corre la cinta.** Las lineas malas del
  VIC-II paran la CPU unos 40 ciclos y movian los flancos.
- **Motor parado mientras se escriben FOUND y LOADING.** CHROUT corre con
  las IRQ enmascaradas.
- **Mensaje SEARCHING FOR** tambien en cinta.
- **Fin+1 de LOAD.** Se calcula despues de parar el IRQ: el IRQ pisaba
  dlo/dhi.

Encontrado de paso, fuera de la cinta:
- El retorno de carro no apagaba el modo inverso: tras `LOAD"$",8` y
  LIST todo salia en inverso. Corregido; test en `tests/test_modes.py`.
- VERIFY correcto en modo directo ahora escribe OK.

Resultado en VICE:
- Este KERNAL carga cintas grabadas por un C64 real.
- Un C64 real carga cintas grabadas por este KERNAL.
- Las cabeceras grabadas por los dos son identicas byte a byte.
- VERIFY da OK o ?VERIFY ERROR segun toque.

Tests:
- `tests/tapgen.py`: modelo del formato en Python, escrito aparte del
  KERNAL. Genera cintas y decodifica grabaciones.
- `tests/test_cinta.py` comprueba el formato de lo grabado desde fuera:
  - bloques, guias, cabecera de 192 bytes y pulsos de 384/528/688
    ciclos (media exacta; cada pulso +-8, lo que mide un byte de TAP);
  - LOAD de cintas generadas a velocidad nominal, un 25 % lenta y un 40 %
    rapida, con ruido;
  - LOAD en modo directo con pausa;
  - tipo 3;
  - fin de cinta.
- El arnes (`tests/cinta.py`) graba los flancos de subida, sincroniza el
  latch del timer y modela parar y arrancar el motor.

Diferencias que quedan respecto al C64:
- La cabecera se guarda en $0362, no en $033C.
- No hay ficheros de datos en cinta (OPEN 1,1).
- ~~LIST de BASIC deja un espacio antes del numero de linea (" 10 PRINT")
  donde el C64 no lo deja.~~ Resuelto en la seccion 18.

## 16. Editor y direcciones documentadas (21 oct 2026)

Repaso de pendientes contra todas las sesiones anteriores. Arreglado:

1. **$EA7E.** Antes tenia `NOP / BRK / BRK`. Ahora es `LDA $DC0D`
   (reconocer el CIA1) seguido de la salida $EA81, como el C64. KIRQ
   termina ahi, asi que el reconocimiento se hace al final del IRQ.
   Estaba pedido desde agosto y habia quedado sin hacer. Test en
   tests/test_canonicas.py.
2. **Modo comillas y modo insercion del editor.**
   - La comilla impresa o tecleada conmuta el modo ($D4).
   - Dentro de comillas, los controles no se ejecutan: se ven como
     caracteres invertidos ($00-$1F a pantalla $80-$9F, $80-$9F a
     $C0-$DF). DEL e INST siguen funcionando.
   - INST abre un hueco y cuenta en $D8. Lo que se teclee en el hueco,
     controles incluidos, se escribe invertido.
   - RETURN (o SHIFT+RETURN) sale de comillas, insercion e inverso.
   - Al leer la linea, un caracter invertido dentro de comillas vuelve a
     ser el control (rutina KSC2P), asi que `10 PRINT"{CLR}"` se guarda
     con $93.
   - LIST ya no ejecuta los controles de las cadenas.
3. **Direcciones documentadas que ahora se mantienen:**
   - 197/203 ($C5/$CB): tecla pulsada, columna*8 + fila, 64 sin tecla.
   - 653 ($028D): SHIFT/C=/CTRL.
   - 199 ($C7): inverso.
   - 212 ($D4): comillas.
   - 216 ($D8): insercion.
   - 214 ($D6): fila del cursor.
   - $D9-$F1: tabla de enlace de lineas.
   - $F3/$F4: puntero a la RAM de color.
   - $CD/$CF: parpadeo del cursor.
   - 648 ($0288): vale 4.
   - 678 ($02A6): 1 en PAL. Se detecta en CINT mirando si existe la linea
     de raster 311.
   - 657 ($0291): con el bit 7 a 1, SHIFT+C= no cambia el juego de
     caracteres.
4. **Zonas libres para programas.** El editor tenia su estado en
   $02A0-$02F2 y el puntero de color en $FB/$FC. En el C64, 251-254
   ($FB-$FE) y 679-767 ($02A7-$02FF) son libres para el usuario, y la
   lectura del teclado los pisaba en cada IRQ. El estado pasa a:
   - las posiciones documentadas de arriba;
   - posiciones de pagina cero que en el C64 son internas del KERNAL
     ($C8-$CA, $CE, $D0, $D5, $D7, $F2, $F5-$FA, $9B, $9E, $9F);
   - la zona RS232 de la pagina 2 ($0293-$02A5), que este KERNAL no usa;
   - $028B, $028C, $028E y $0292.
   Probado: tras teclear, escribir y hacer scroll, 679-767 y 251-254 siguen
   intactos (tests/test_variables.py y VICE).
5. **KSERIN usaba KTMP3**, que tambien usa el IRQ del teclado. Una tecla
   durante una lectura del disco podia cambiar el byte leido. Ahora usa
   su propia variable.

Espacio: el editor no cabia en su seccion. Se hizo sitio asi:
- CHROUT reutiliza KCUROFF, que ahora usa PHP/PLP en vez de SEI/CLI;
- el generador de pulsos de cinta es una tabla (la misma secuencia de
  pulsos, verificada contra la grabacion anterior), y los finales de byte
  comparten cola (wnewbyte);
- KSCROLL va a la seccion principal;
- tres tablas pequenas van a huecos de islas.

6. **Grabador de cinta: carrera en la entrega de pulsos.** El bucle
   principal dejaba el pulso siguiente en wnext (2 bytes) y el manejador
   lo copiaba al latch en la bajada. En el inicio de un byte, o al pasar
   de la guia a los datos, el calculo puede durar mas que un pulso. En
   VICE el IRQ cayo entre las dos escrituras de wnext: latch $0057 y un
   pulso de unos 90 ciclos en el primer marcador de cada bloque. En py65
   no salia por suerte de tiempos. Ahora el bucle llena una cola de 3
   pulsos (wqlo/wqhi, indices wqh/wqt) y el manejador la vacia, asi que
   los picos de calculo no llegan al timer. El fallo estaba latente desde
   la version que se subio en 60fe54c. tests/test_cinta.py comprueba que
   la cola nunca se vacia antes del final.

KERNAL libre: 28 bytes.

El arnes (tests/arnes.py) simula ahora el raster de un VIC-II PAL ($D011
bit 7 y $D012), porque CINT lo necesita para detectar PAL.

Queda pendiente:
- ~~648 se lee pero no se respeta.~~ Resuelto en la seccion 19.
- ~~650 (repeticion) no se usa.~~ Resuelto en la seccion 19.
- ~~Puntos de entrada internos sin colocar ($E544, $E56C, $E716, $E9FF).~~ Resuelto en la seccion 18.
- ~~La pagina cero del BASIC sigue desplazada (TXTTAB en $28).~~ Resuelto en la seccion 17.
- ~~LIST pone un espacio delante del numero de linea.~~ Resuelto en la seccion 18.
- Diferencias de cinta de la seccion 15.


## 17. Pagina cero del BASIC en las direcciones del C64 (21 oct 2026)

La pagina cero del BASIC empezaba en $03 con el orden del fuente MIT, asi
que TXTTAB caia en $28 y no en $2B: `POKE 43/44` (mover el inicio del
BASIC), `PEEK(45/46)` (fin del programa), `PEEK(55/56)` (tope de memoria)
y las cuñas de CHRGET en $73 o TXTPTR en $7A no funcionaban.

Ajuste en src/translate.py (capa de traduccion; el upstream no se toca).
Direcciones de los mapas de memoria publicos (nivel A/B):

| Direccion | Variable | Nota |
|---|---|---|
| $03/$05 | ADRAY1/ADRAY2 | nuevos: vectores FAC -> entero en A/Y (FACAY) y entero en A/Y -> FAC (GIVAYF); INIT los rellena (INIADR) |
| $07-$08 | CHARAC, ENDCHR | |
| $09 | CNTWFL | el ^O del fuente; en el C64 es un temporal de TAB |
| $0A | reservado | VERCK en el C64 |
| $0B-$13 | COUNT ... CHANNL | mismo orden que el C64 |
| $14 | LINNUM | desde aqui el orden del fuente ya era el del C64 |
| $2B..$38 | TXTTAB..MEMSIZ | |
| $73/$7A | CHRGET/TXTPTR | |
| $8B-$8F | RNDX | |

- LINWID y NCMWID se eliminan: INIT los escribia y nadie los leia. El
  comentario "no nulos para CHEAD" era para BUF en pagina cero; aqui
  BUF=$0200 e INIT pone BUF-3/BUF-4 a 1.
- FACAY e INIADR van al final del tramo $A000 (la continuacion en $E000,
  donde esta INIT, no tiene hueco). INIT llama a INIADR en lugar de las
  escrituras de LINWID/NCMWID (5 bytes menos en $E000). Libres en el tramo
  $A000: 19 bytes ($BFED-$BFFF).
- **Fallo encontrado de paso: POS, TAB y la coma.** TRMPOS era 198, la
  columna del PET; en el C64 es el contador del bufer de teclado. Efecto:
  `POS(0)` devolvia 0, la coma siempre anadia 10 espacios (Y salia en la
  columna 11) y `TAB` contaba desde 0 (`PRINT"AB";TAB(5)` dejaba la Z en
  la 7). Ahora TRMPOS = 211 ($D3), la columna del cursor.

Probado:
- tests/test_zp_basic.py: 43/44 = 2049, 55/56 = 40960, VARTAB/ARYTAB/
  STREND/FRETOP coherentes tras un RUN, CHRGET en $73, `POKE44,16:NEW`
  mueve el programa a $1001, ADRAY1/ADRAY2 desde codigo maquina via USR,
  POS/coma/TAB.
- VICE: `PRINT PEEK(43)+256*PEEK(44)` da 2049, 45/46 da 2051, 55/56 da
  40960; `AB 2`, coma en la columna 10, TAB(5) en la 5. Cinta (grabar,
  cargar, cargar la grabacion de la ROM original, la ROM original carga
  la nuestra, VERIFY bien y mal) y disco (SAVE/VERIFY/`LOAD"$"`/LOAD/RUN)
  siguen bien.
- Bateria completa en verde (19 tests).


## 18. Salida del BASIC como la del C64 y entradas internas del KERNAL (21 oct 2026)

Comparado en VICE con la ROM original como caja negra (misma secuencia de
teclas en las dos ROMs). Tras los cambios, LIST, RUN, errores y PRINT dan
la misma pantalla.

BASIC (src/translate.py):
1. **LIST sin espacio delante del numero.** LINPRT (LIST, " IN nn",
   BREAK IN, bytes libres del arranque) llama a FOUT con Y=0: el signo cae
   en LOFBUF ($FF) y la cadena empieza en la primera cifra de FBUFFR
   ($0100). El propio fuente ya lo pedia en LIST ("PRINT AS INT WITHOUT
   LEADING SPACE"). Efecto secundario correcto: el arranque queda
   " 64K RAM SYSTEM  38911" con dos espacios, como el C64 (antes tres).
2. **Linea en blanco tras cada linea tecleada.** El editor del KERNAL ya
   imprime el retorno al entregar el RETURN; FININL imprimia otro (CRDO).
   Afectaba a lineas de programa, ordenes directas e INPUT. FININL vuelve
   ya sin CRDO.
3. **"?SYNTAX  ERROR" con dos espacios**, como el C64 (" ERROR" ->
   "  ERROR"). tests/test_iec_fase2a.py actualizado.

KERNAL (src/kernal.s):
4. **Entradas internas conocidas** (direcciones y uso de los mapas de
   memoria publicos, nivel A/B):
   - $E544 (58692): borrar pantalla, cursor a (0,0). Es KCLS.
   - $E56C (58732): puntero de linea desde 214/211 (KE56C: PLOT con la
     fila y columna actuales). `POKE214,F:POKE211,C:SYS58732`.
   - $E716 (59158): escribir A en pantalla sin mirar el dispositivo de
     salida (KE716 -> KSCROUT). KCHROUT se ha partido: comprueba el
     dispositivo y, si es la pantalla, entra en KSCROUT.
   - $E9FF (59903): borrar la fila X (KCLRLN: espacios y color 646).
   Se colocan con la macro FIJA (rellena con NOP hasta la direccion y
   falla si el codigo anterior la ha pasado). Los bloques de la seccion
   principal ($E200-$EA30) se han reordenado para que encajen.
5. **CLR conservaba mal el color.** KCLS ponia 646 a azul claro: tras
   `PRINT CHR$(5)CHR$(147)` el texto volvia a azul. Ahora el color solo se
   fija en CINT y CLR pinta la RAM de color con el color actual (el C64
   original da 646=1 y la RAM de color a 1).
6. **Espacio.** KCLS borra fila a fila con KCLRLN; KROWP (fila -> puntero)
   sustituye tres multiplicaciones por 40 (PLOT, lectura de la linea,
   ultima fila del scroll). Las variables del editor que se definian
   despues de usarse (y por eso se ensamblaban con direccion absoluta) se
   han subido al principio de la seccion: ahora usan pagina cero. En total
   se ganaron unos 130 bytes, de los que ~97 se van en el relleno de las
   cuatro direcciones fijas. KERNAL libre: 65 bytes. BASIC ($A000): 19.

Probado:
- tests/test_entradas.py (las cuatro entradas, CLR y color) y
  tests/test_formato.py (LIST, linea en blanco, errores, arranque).
  tests/test_editor.py: el caso de editar una linea listada usa ahora la
  columna 5 (antes 6, por el espacio).
- VICE: SYS58692 y POKE214/211+SYS58732; cinta y disco como antes.
- Bateria completa en verde (21 tests).


## 19. 650 (repeticion) y 648 (pagina de la pantalla) (21 oct 2026)

**650 ($028A).** La repeticion ya existia para espacio, cursores, DEL e
INST (lo que hace el C64 con 650=0). Ahora, antes de mirar esa lista, el
bit 7 hace que repitan todas y el bit 6 que no repita ninguna. 7 bytes.
tests/test_repeticion.py.

**648 ($0288).** El editor escribe y lee en la pagina que diga 648, como
el C64. No mueve lo que se ve: el programa tiene que cambiar tambien
$D018 (y el banco del VIC-II si hace falta). Cambios:
- KROWP toma la base de 648; PLOT, CLR, $E544/$E9FF, la lectura de la
  linea y el scroll pasan todos por ella.
- Los limites del cursor (abajo, arriba, avance de linea) se comprueban
  con la fila (214), no comparando el puntero con $0400+1000. Mas corto.
- HOME usa PLOT.
- El puntero a la RAM de color sale de una sola rutina, KSETCP: el mismo
  desplazamiento desde $D800 que el puntero de pantalla desde la pagina
  648 (byte alto - 648 + $D8). Vale para cualquier pagina, no solo para
  las alineadas a 1K. La usan CHROUT, KCUROFF y el parpadeo del IRQ;
  KCLRLN hace la misma cuenta y el scroll parte directamente de $D800.
  Una primera version usaba "AND 3, OR $D8" y el comparador ciego marco
  14 bytes iguales al original; se cambio por la resta, que ademas es mas
  general.
- El scroll copia con punteros (KVPTR destino, KCPTR origen) en vez de
  direcciones absolutas: 960 bytes de pantalla y luego 960 de color.
  KCPTR se puede usar porque el IRQ esta inhibido dentro de CHROUT y lo
  recalcula al parpadear. El cursor queda en la fila 24 con su columna
  (con PLOT).
- KSTOP se ha movido delante de $E9FF: KCLRLN crecio un byte y la cola
  hasta $EA31 se pasaba por uno.

Espacio: el KERNAL queda con 91 bytes libres fuera de los rellenos (antes
65); lo que se ahorra en CHROUT se queda en el relleno antes de $E544.

Probado:
- tests/test_pagina648.py: con 648=200, CLR y PRINT escriben en $C800,
  una orden tecleada se lee de alli y se ejecuta, el scroll funciona,
  $0400 no se toca y el color va a $D800; con 648=4 vuelve a $0400.
- VICE, misma secuencia en las dos ROMs: `POKE648,32` + $D018 para ver
  la pantalla de $2000, CLR, PRINT, una orden y un bucle con scroll. Las
  dos pantallas salen iguales y el cursor parpadea en su sitio.
- Bateria completa en verde (23 tests).


## 20. DEL en INLIN, CHKIN/CHKOUT y guarda de BLOAD (21 oct 2026)

**Delta de DEL en INLIN, retirado.** translate.py hacia que INLIN tratara
$14 como retroceso. AUDITORIA.md lo daba por codigo muerto, pero no lo
era: INLIN ve $14 cuando es un caracter de verdad.
- Con el teclado no se notaba solo por casualidad: CHRIN de pantalla
  devuelve en X su propio indice, que coincide con el de INLIN porque la
  linea del editor esta en el mismo $0200 que BUF. El DEX de INLIN se
  perdia.
- Con un fichero si se notaba: KSERIN conserva X. En VICE, con la 1541,
  `PRINT#2,"AB"CHR$(20)"CD"` y despues `INPUT#2,A$` daba A$="ACD"
  (LEN 3); la ROM original da los 5 caracteres con el CHR$(20) en la
  tercera posicion. Sin el delta, igual que el original.

**CHKIN/CHKOUT devolvian en X el indice de la tabla de ficheros**, no el
numero de fichero logico. El BASIC hace `STX CHANNL` justo despues, asi
que con el primer fichero abierto (indice 0) CHANNL quedaba a 0 y el
BASIC creia estar leyendo del teclado: INPUT# escribia "? " en pantalla.
Ahora los dos guardan X a la entrada y la devuelven al salir (10 bytes).
En VICE, INPUT#, GET# y PRINT# a la 1541 dan la misma pantalla que la ROM
original. tests/test_canales.py (CHKIN/CHKOUT devuelven X; INPUT#1 desde
el teclado sin "?").

Diferencia que queda: tras leer el final de un fichero, un GET# mas deja
ST=64 en nuestra ROM y ST=66 (fin de fichero + tiempo agotado) en la
original.

**Guarda de BLOAD (43f1eba), validada en VICE.** Con un programa en
memoria (`10 PRINT"VIEJO"`, `20 GOTO 10`) y la 1541:
- PRG de 1 byte de datos: nuestra ROM deja un programa vacio (LIST no
  muestra nada, FRE(0) da -26627, es decir 38909 libres) y se puede
  teclear y ejecutar un
  programa nuevo. La ROM original, en cambio, reenlaza la memoria rancia
  y LIST vuelve a mostrar el programa viejo; al seguir tecleando acaba
  colgada. La guarda se queda: es una diferencia a favor.
- PRG de 2 bytes ($00 $00): igual en las dos.
- PRG sin datos (solo la direccion de carga): la original se queda
  colgada en LOADING; la nuestra da `?DEVICE NOT PRESENT  ERROR` con
  ST=-128 y conserva el programa. No es la guarda (la carga no llega a
  terminar), pero el mensaje no es el adecuado: queda anotado.

Probado: bateria completa en verde (24 tests); VICE como se describe.
KERNAL libre: 81 bytes.
