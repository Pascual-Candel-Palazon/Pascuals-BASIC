# PROCEDENCIA.md — Política de sala limpia del proyecto

## Principio

Este proyecto reimplementa las ROMs del Commodore 64 sin acceso a la
expresión original. La frontera operativa distingue tres niveles de
información:

**Nivel A — Hardware e interfaz pública (uso libre y necesario).**
Registros del VIC-II y los CIA, códigos de pantalla, matriz del teclado,
mapa de memoria de la máquina, la tabla de saltos del KERNAL
($FF81-$FFF3) con sus contratos de entrada/salida, los vectores de
$FFFA, y las posiciones de RAM/ZP documentadas de las que depende el
software de la época (búfer de teclado, flags de repetición, vectores de
página 3...). Son la máquina y su contrato público, no la obra.

**Nivel B — Comportamiento observable (uso permitido, documentándolo).**
Todo lo que un usuario constata desde fuera: qué teclas repiten y a qué
cadencia, cuándo parpadea el cursor, qué imprime el arranque, semántica
de los comandos. El comportamiento se especifica por observación, no por
inspección del código.

**Nivel C — Implementación interna del original (PROHIBIDO).**
Desensamblados de las ROMs de Commodore, walkthroughs rutina a rutina,
descripciones de flujo de instrucciones, asignación interna de
variables, trucos concretos de la implementación original. No se
consultan ni siquiera "para inspirarse". Si una fuente mezcla niveles
(p. ej. Mapping the Commodore 64 documenta interfaz Y narra tripas), se
usan solo las partes de nivel A/B y se anota.

## Reglas operativas

1. Cada subsistema nuevo registra en su cabecera las fuentes usadas y su
   nivel.
2. Nadie del proyecto descarga ni desensambla las ROMs originales, ni
   siquiera para comparar. La verificación de no-similitud la hará un
   tercero externo contra la ROM real, en sentido único.
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
- **CHARGEN**: actualmente el de MEGA65 open-roms (licencia de terceros,
  pendiente de sustitución por un juego propio).

## Estado de cumplimiento (autoauditoría continua)

Cada sesión de desarrollo cierra con una revisión: ¿se consultó algo de
nivel C? En caso afirmativo, se anota aquí y se evalúa re-derivar el
componente afectado. Hasta la fecha: ninguna consulta de nivel C.
