# AUDITORIA_SIMILITUD.md: no-similitud con la ROM original

Fecha: 20 oct 2026. Objeto: `bin/kernal_c64.bin` (sha256 `4acb5cba...`,
compilado desde 45da60d, estado de GitHub a 3 jul) y `bin/basic_c64.bin`.

Este informe NO sustituye la verificacion por un tercero que exige la
regla 2 de `PROCEDENCIA.md`. La hizo el propio entorno de desarrollo, con
las salvaguardas descritas abajo, para dejar el expediente preparado para
ese tercero. No es una opinion juridica.

## Auditoria A: comparacion ciega y mecanica

### Metodo
- Herramienta: `tools/comparador_ciego.py`. Lee la ROM de referencia y
  solo imprime metricas y posiciones en el binario PROPIO. Nunca imprime
  bytes, opcodes ni direcciones de la referencia: el operador no ve su
  contenido. El repositorio no incluye ninguna ROM de Commodore.
- Referencias: las ROMs que distribuye VICE 3.10 (C64 KERNAL 901227-01,
  -02 y -03; C64 BASIC 901226-01; VIC-20 KERNAL 901486-07; DOS 1541
  325302-01+901229-05).
- Metricas:
  1. Bytes iguales en la misma direccion.
  2. Coincidencias maximales de bytes de 8 o mas, en cualquier posicion
     (detecta copia literal aunque este reubicada).
  3. Similitud de Jaccard de 6-gramas de opcodes, ignorando operandos
     (detecta codigo copiado y reubicado, con direcciones cambiadas).
  Las rachas de relleno ($00/$FF) se descartan.
- Controles:
  - Negativos (codigo 6502 independiente): linea base de coincidencia
    casual.
  - Positivos: VIC-20 KERNAL contra C64 KERNAL (mismo linaje, conocido) y
    BASIC propio contra BASIC de Commodore (ambos derivan del MS BASIC).
  - Positivo sintetico: se injertan 48 bytes copiados de la referencia en
    una copia del binario propio, en 10 posiciones aleatorias.

### Resultados

KERNAL propio desde $E200 (sin la cola del BASIC de Microsoft):

| Comparacion | Jaccard opcodes | Bytes en coincidencias >=8 | Coincidencia max. |
|---|---|---|---|
| **Propio vs C64 KERNAL** | **0,025** | 464 (6,0 %) | 54 |
| Propio vs VIC-20 KERNAL | 0,012 | 216 (2,8 %) | 26 |
| Propio vs DOS 1541 (independiente) | 0,005 | 8 (0,1 %) | 8 |
| C64 KERNAL vs DOS 1541 (linea base) | 0,004 | 9 (0,1 %) | 9 |
| VIC-20 vs C64 KERNAL (parentesco) | 0,426 | 3369 (41,1 %) | 117 |
| BASIC propio vs C64 BASIC (MS, legitimo) | 0,717 | 1472 (18,0 %) | 256 |

- Las tres revisiones del C64 KERNAL dan el mismo resultado (35
  coincidencias, unos 735 bytes sobre el binario completo).
- Injerto sintetico de 48 bytes: detectado 10 de 10 veces.
- Bytes iguales en la misma direccion: 2,1 % (linea base 1,2 %).

Lectura: el KERNAL propio esta unas 17 veces por debajo de un parentesco
real (0,025 frente a 0,426). Queda por encima de la linea base de codigo
independiente (0,005) porque comparte hardware e interfaz documentada; la
clasificacion de abajo explica cada coincidencia.

### Clasificacion de las 35 coincidencias (lado propio)

| Tipo | Bytes | Explicacion |
|---|---|---|
| Cola del BASIC en $E000-$E1FF | 272 | Codigo de Microsoft (MIT). La ROM de Commodore lleva la misma cola porque sale del mismo fuente. Legitimo. |
| Texto | 133 | Tablas de teclado (matriz a PETSCII: hecho del hardware) y mensajes observables (PRESS PLAY ON TAPE, PRESS RECORD & PLAY ON TAPE, SEARCHING, VERIFYING, "LOAD"+CR+"RUN"+CR). Niveles A/B. |
| Tabla de saltos | 31 | `JMP ($031A)`... por los vectores de pagina 3: interfaz documentada. |
| Codigo del KERNAL | 300 | Fragmentos de 8 a 19 bytes, salvo uno de 54, impuestos por el hardware o por direcciones documentadas (detalle abajo). |

Fragmentos de codigo del KERNAL propio que coinciden:

| Direccion | Bytes | Rutina | Por que coincide |
|---|---|---|---|
| $E225 | 8 | KIOINIT | `LDA #$7F / STA $DC0D / STA $DD0D`: apagar IRQ de los dos CIA. Hardware. |
| $E247 | 10 | KIOINIT | Timer A del jiffy a $4295: constante de temporizacion PAL. |
| $E604 | 8 | KSCNKEY | `LDA $D018 / EOR #$02 / STA $D018`: conmutar juego de caracteres. |
| $E700-$E7DF | 15-36 | KEYTAB* | Tablas de decodificacion del teclado (hecho del hardware y de PETSCII). |
| $E81E | 17 | KXLATE | Tabla de codigos PETSCII de color. |
| $E849 | 10 | KSRTAB | Texto "LOAD"+CR+"RUN"+CR (comportamiento observable). |
| $E86A | 12 | KGETIN | Desplazar el bufer de teclado ($0277, $C6): direcciones documentadas. |
| $EA95, $F78F | 8 | KSTOPRAW, dcwait | Leer la fila 7 de la matriz ($DC00/$DC01). Hardware. |
| $EAA8 | 10 | KUDTIM | Incremento del reloj de 3 bytes en $A0-$A2 (documentado). |
| $EAB3 | 19 | KIRQENT | Ver "Casos para el tercero". |
| $EBB9 | 8 | KMEMTOP | `STX $0283 / STY $0284 / RTS`: direccion documentada. |
| $EC02 | 16 | KSETTIM/KRDTIM | `SEI`, guardar o leer $A0-$A2, `CLI`: contrato de la API. |
| $EC37 | 54 | KCLKLO..KATNHI | Ver "Casos para el tercero". |
| $EEAF | 14 | KSETNAM/KSETLFS | Guardar A/X/Y en $B7-$BC: contrato de la API y direcciones documentadas. |
| $F199 | 13 | KSAVE | Entrada de SAVE: X/Y fin, A indice ZP del inicio, a $AE/$C1. Contrato de la API. |
| $FBB9 | 8 | whandler | `LDA #$19 / STA $DC0F / LDA $DC0D`: arrancar Timer B y reconocer IRQ. Hardware. |
| $FBD8 | 9 | wh_ack | `LDA $DC0D / PLA / TAY / PLA / TAX / PLA / RTI`: salida de IRQ con el orden de pila documentado. |

### Casos para el tercero
1. **KCLKLO..KATNHI ($EC37, 54 bytes).** Seis rutinas de 9 bytes
   `LDA $DD00 / ORA o AND #mascara / STA $DD00 / RTS` (CLOCK, DATA y ATN,
   cada una a nivel bajo y alto). Cada rutina la impone el hardware; el
   ORDEN de las seis tambien coincide con la referencia. Es el orden
   natural (por linea, bajo antes que alto), pero no el unico posible.
2. **KIRQENT ($EAB3, 19 bytes).** Apilar A, X e Y, mirar el flag B en la
   copia de P de la pila y saltar por `($0316)` (BRK) o `($0314)` (IRQ).
   El contrato documentado lo impone casi entero: el orden de apilado es
   el que esperan los manejadores de usuario y los vectores son
   publicos. Lo unico elegible era el orden de los dos saltos.

### Limitaciones
- Detecta copia literal y copia reubicada de secuencias de instrucciones.
  No detecta una reescritura que siga la misma estructura con otras
  instrucciones; eso solo lo puede juzgar un revisor humano con acceso a
  ambos fuentes, que es el papel del tercero.
- La ejecuto el entorno de desarrollo, no un tercero independiente.
- El script lee la ROM original (la que trae VICE); el
  operador solo ve metricas. Queda anotado en `PROCEDENCIA.md`.

### Reproducir
```
./build.sh
python3 tools/comparador_ciego.py --vice RUTA_A_VICE --listado build/rom_listado.txt
```

## Auditoria B: interna, sin el original

1. **Regla 1 (fuentes por subsistema): se cumple en parte.** Citan fuente
   en `src/kernal.s`: bus IEC (Butterfield / Programmer's Reference),
   tablas CTRL y C= (sta.c64.org), semantica de LOAD y mensajes (nivel
   B). No la citan: editor, SCNKEY, IRQ/NMI/BRK y RUN/STOP-RESTORE,
   cartuchos CBM80, rutinas no IEC de la tabla de saltos, tablas de
   ficheros y cinta (dice "formato CBM publicado" sin decir cual). No se
   han anadido citas a posteriori: solo el autor puede decir que fuente
   se uso. Queda como tarea en `PROCEDENCIA.md`.
2. **RAM y pagina cero.** Las direcciones documentadas del C64 se usan a
   proposito ($90, $93, $98-$9A, $9D, $A0-$A2, $B7-$BC, $C6, $D1, $D3,
   $0259-$0276, $0277, $0281-$0287), como permite la politica. Los
   NOMBRES de etiqueta (KLDTND, KDFLTN, KMSGFL, KC3PO, KBSOUR, KGDCOL,
   KNDX, KLAT/KFAT/KSAT...) siguen la nomenclatura de los mapas de memoria
   publicos, que a su vez procede del fuente de Commodore. No es codigo,
   pero un revisor lo notara; queda declarado en `PROCEDENCIA.md`.
   Observacion pendiente de comprobar contra un mapa publico: KC3PO esta
   en $A3, y es probable que en esos mapas el nombre corresponda a $94.
3. **Historial git.** Empieza desde cero el 12 jun 2026 y avanza en pasos
   pequenos, con errores de primera escritura y su causa documentada
   (KISEND destruia Y, carrera de KSTOP, tverify pisado por la cabecera,
   KUNLSN). Es buena evidencia de creacion independiente (regla 3).
4. **Bug encontrado de paso (compatibilidad, no procedencia).** El editor
   usaba $033C (828) como buffer de linea: ver `AUDITORIA.md`, hueco 3.
   Corregido el mismo dia (KLINE a $0200).

## Repeticion tras el tier-3 (21 oct 2026)

Mismo metodo y mismas referencias, sobre el KERNAL con las direcciones
canonicas colocadas (ver `docs/CONTINUIDAD.md`, seccion 14):

| Comparacion | Jaccard opcodes | Bytes en coincidencias >=8 | Coincidencia max. |
|---|---|---|---|
| **Propio vs C64 KERNAL** | **0,025** | 493 (6,4 %) | 54 |
| Propio vs VIC-20 KERNAL | 0,012 | 226 (2,9 %) | 26 |
| Propio vs DOS 1541 (independiente) | 0,005 | 8 (0,1 %) | 8 |

Sin cambio material. Coincidencias nuevas, todas por estar en la
direccion canonica y cumplir su contrato:
- $FCF7 (10 B, KRESET): `JSR $FDA3 / JSR $FD50 / JSR $FD15`. Al colocar
  IOINIT, RAMTAS y RESTOR en sus direcciones documentadas, las llamadas
  de arranque producen los mismos bytes.
- $FDA3 (8 B) y $FDC5 (10 B, KIOINIT): apagar las IRQ de los CIA y cargar
  el timer A del jiffy ($4295). Hardware.
- $FE43 (9 B): entrada NMI `SEI / JMP ($0318)` seguida de `PHA / TXA /
  PHA / TYA / PHA` en $FE47. Es el contrato del vector $0318.
- $FF48 (19 B, KIRQENT): ya estaba en el informe; ahora ademas en la misma
  direccion que el original, porque es su direccion canonica.

Bytes iguales en la misma direccion: 2,6 % (antes 2,1 %), por estas
mismas piezas.

## Repeticion tras rehacer la cinta (21 oct 2026)

Mismo metodo, despues de rehacer el lector y el grabador de cinta (ver
`docs/CONTINUIDAD.md`, seccion 15):

| Comparacion | Jaccard opcodes | Bytes en coincidencias >=8 | Coincidencia max. |
|---|---|---|---|
| **Propio vs C64 KERNAL** | **0,025** | 500 (6,5 %) | 54 |
| Propio vs VIC-20 KERNAL | 0,012 | 226 (2,9 %) | 26 |
| Propio vs DOS 1541 (independiente) | 0,005 | 8 (0,1 %) | 8 |

Sin cambio material. Las coincidencias nuevas son de 8 bytes en $FD82,
$FD8B y $FD93 (`tp_blank`, `tp_show`, `tm_off`/`tm_on`): leer, cambiar un
bit y escribir $D011 (pantalla) o $01 (motor), con su RTS. Lo impone el
hardware.

## Repeticion tras el editor y $EA7E (21 oct 2026)

Propio vs C64 KERNAL: Jaccard 0,025; 508 bytes (6,6 %) en coincidencias
de 8 o mas; maximo 54. Sin cambio material. Coincidencia nueva: $EA7E
(9 B), `LDA $DC0D` seguido de la salida PLA/TAY/PLA/TAX/PLA/RTI. Es la
direccion canonica y su contrato documentado (reconocer el CIA y salir).

## Repeticion tras las entradas internas y la salida del BASIC (21 oct 2026)

Propio vs C64 KERNAL: Jaccard 0,024; 550 bytes (7,1 %) en coincidencias
de 8 o mas (antes 508); maximo 54 (el mismo). VIC-20: 0,012. DOS 1541:
0,005.

La subida viene de que las variables del editor ahora se ensamblan en
pagina cero (antes, por estar definidas despues de usarse, iban con
direccion absoluta). Al usar las mismas direcciones documentadas que el
C64, algunas secuencias cortas dan los mismos bytes:
- $E4FB (11 B, GETIN): desplazar el bufer de teclado un byte (`LDA
  KBUF+1,X / STA KBUF,X / INX / CPX KNDX`) en 631/198.
- $E742 (8 B, CHRIN): guardar columna (211) y fila (214) del cursor.
- $E9A1 (8 B, STOP): seleccionar la fila 7 del CIA y leer el bit de
  RUN/STOP.
- $E5D7 (8 B, SCNKEY): conmutar el juego de caracteres en $D018.
Todas las impone la direccion documentada o el hardware. Las cuatro
entradas fijas nuevas ($E544, $E56C, $E716, $E9FF) no coinciden con el
original: solo comparten la direccion.

## Repeticion tras 648/650 (21 oct 2026)

Propio vs C64 KERNAL: Jaccard 0,024; 559 bytes (7,2 %) en coincidencias
de 8 o mas; maximo 54. VIC-20: 0,012.

Una primera version del puntero a la RAM de color (byte alto AND 3,
OR $D8, en KSETCP) coincidia en 14 bytes con el original. Se cambio por
"byte alto - 648 + $D8", que no coincide y ademas sirve para paginas no
alineadas a 1K. Nueva coincidencia de 8 bytes en KMEMTOP ($EB77):
`STX/STY $0283/$0284` + RTS, la direccion documentada de MEMTOP.
