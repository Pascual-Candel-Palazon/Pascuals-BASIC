# PROCEDENCIA.md: política de sala limpia del proyecto

## Principio

Este proyecto reimplementa las ROMs del Commodore 64 sin acceso a la
expresión original. La frontera operativa distingue tres niveles de
información:

**Nivel A: hardware e interfaz pública (uso libre y necesario).**
Registros del VIC-II y los CIA, códigos de pantalla, matriz del teclado,
mapa de memoria de la máquina, la tabla de saltos del KERNAL
($FF81-$FFF3) con sus contratos de entrada/salida, los vectores de
$FFFA, y las posiciones de RAM/ZP documentadas de las que depende el
software de la época (búfer de teclado, flags de repetición, vectores de
página 3...). Son la máquina y su contrato público, no la obra.

**Nivel B: comportamiento observable (uso permitido, documentándolo).**
Todo lo que un usuario constata desde fuera: qué teclas repiten y a qué
cadencia, cuándo parpadea el cursor, qué imprime el arranque, semántica
de los comandos. El comportamiento se especifica por observación, no por
inspección del código.

**Nivel C: implementación interna del original (PROHIBIDO).**
Desensamblados de las ROMs de Commodore, walkthroughs rutina a rutina,
descripciones de flujo de instrucciones, asignación interna de
variables, trucos concretos de la implementación original. No se
consultan ni siquiera "para inspirarse". Si una fuente mezcla niveles
(p. ej. Mapping the Commodore 64 documenta interfaz Y narra tripas), se
usan solo las partes de nivel A/B y se anota.

## Reglas operativas

1. Cada subsistema nuevo registra en su cabecera las fuentes usadas y su
   nivel.
2. Nadie del proyecto desensambla ni consulta el contenido de las ROMs
   originales, ni siquiera para comparar. La verificación de no-similitud
   la hará un tercero externo contra la ROM real, en sentido único.
   Usos de las ROMs originales que NO consultan su contenido, y que quedan
   anotados: (a) VICE las trae de serie y la ROM del 1541 se usa como
   periférico opaco emulado para probar el bus IEC; (b) la auditoría
   ciega del 20 oct 2026 (`docs/AUDITORIA_SIMILITUD.md`), en la que un
   script lee la ROM y el operador solo ve métricas; (c) la prueba de
   cinta del 21 oct 2026: la ROM original corrió en VICE como caja negra,
   igual que un C64 de referencia, para grabar un programa de prueba a un
   TAP y para cargar los TAP grabados con este KERNAL. Solo se observó el
   comportamiento (la forma de onda grabada y la pantalla), que es nivel
   B; no se miró su código. De esa grabación se midieron las longitudes
   de guía ($6A00, $1500, 79 entre copias, 78 al final) y el relleno de
   la cabecera, que coinciden con el formato publicado. La cinta grabada
   no está en el repositorio: los tests usan `tests/tapgen.py`, escrito
   desde el formato publicado.
3. El historial de desarrollo (sesiones, commits, bugs corregidos) se
   conserva como evidencia de creación independiente. Los errores de
   primera escritura son huellas de autoría.
4. Distinción honesta: reimplementar un método descrito puede ser
   legalmente defendible (los métodos no son protegibles), pero debilita
   la evidencia de independencia. Este proyecto opta por el estándar
   probatorio fuerte, no por el mínimo legal.
5. El asistente de IA usado en el desarrollo declara exposición previa a
   desensamblados en su entrenamiento. Mitigaciones: implementaciones
   estructuralmente más simples que el original, anclaje a
   especificación citable, y revisión externa futura (regla 2).

## Procedencia por componente

- **BASIC**: fuente oficial MIT de Microsoft (repo microsoft/BASIC-M6502)
  transformado por cadena mecánica auditable (flatten.py + translate.py).
  Deltas C64 anotados [C64] en el fuente, derivados de hechos de nivel A
  (mapa de memoria del C64).
- **KERNAL**: escritura original de este proyecto desde niveles A y B.
  Posiciones de RAM propias salvo las elegidas deliberadamente en
  ubicaciones documentadas por compatibilidad (anotado en el fuente).
- **CHARGEN** (`bin/chargen.bin`): la fuente PXL de MEGA65 Open ROMs
  (autor Retrofan), incluida tal cual bajo LGPL-3.0-or-later. Es el unico
  componente no-MIT; textos de licencia y atribucion en `licenses/chargen/`.
  Idéntica bit a bit a chargen_openroms.rom (sha256 5e3451...). Puente
  temporal, pendiente de sustitución por un juego propio.

## Estado de cumplimiento (autoauditoría continua)

Cada sesión de desarrollo cierra con una revisión: ¿se consultó algo de
nivel C? En caso afirmativo, se anota aquí y se evalúa re-derivar el
componente afectado. Hasta la fecha, en el desarrollo de este repositorio:
ninguna consulta de nivel C.

### Nomenclatura de las etiquetas

Las variables del KERNAL en posiciones documentadas llevan el nombre que
les dan los mapas de memoria públicos, con el prefijo K (KNDX, KLDTND,
KDFLTN, KMSGFL, KGDCOL, KLAT/KFAT/KSAT...). Esos nombres proceden en
origen del fuente de Commodore, pero se toman de la documentación pública
como parte de la interfaz (nivel A), no de su código. Las rutinas y
variables propias tienen nombres propios.

### Tarea abierta: fuentes por subsistema (regla 1)

La auditoría del 20 oct 2026 encontró que la regla 1 se cumple en parte.
Citan fuente en `src/kernal.s`: bus IEC, tablas CTRL y C=, semántica de
LOAD y mensajes. Falta anotar la fuente concreta de: editor de pantalla,
SCNKEY, IRQ/NMI/BRK y RUN/STOP-RESTORE, cartuchos CBM80, rutinas no IEC de
la tabla de saltos, tablas de ficheros y cinta. No se han añadido a
posteriori porque solo el autor puede decir qué fuente se usó.


## Trampolines de compatibilidad (direcciones internas)

Algunos cartuchos y programas llaman a rutinas del kernal en sus
DIRECCIONES INTERNAS fijas de la ROM original ($FDA3 IOINIT, $FD50
RAMTAS, $FD15 RESTOR, $FF5B CINT...) en vez de la tabla de saltos
documentada. Colocamos en esas direcciones nuestra implementacion
(desde el tier-3 de octubre, directamente; solo CINT en $FF5B sigue siendo
un trampolin, JMP a nuestra rutina, porque no cabe en su hueco). Justificacion clean-room: esas direcciones son
INTERFAZ PUBLICADA (figuran como puntos de entrada en referencias como
"Mapping the C64"); honrar una direccion documentada con codigo propio
es nivel B, no copiar la expresion de Commodore (nivel C). No se
desensambla ni se reproduce su codigo; solo se respeta la direccion.
