# AUDITORIA.md — evidencia que respalda cada cambio

Este documento clasifica cada delta y subsistema segun el tipo de
evidencia que lo respalda, sin adornos. Se redacta como rendicion de
cuentas: durante el desarrollo hubo cambios presentados con mas
confianza de la que la prueba sostenia, y varias "falsas alarmas". Esto
los separa de los cambios con prueba real.

Leyenda:
- TEST  : cubierto por un test automatico en tests/ (deterministra)
- VICE  : verificado visualmente en el emulador VICE real
- MECH  : causa raiz demostrada por traza/diff (no solo "funciona")
- STRUCT: necesidad estructural (no puede ser de otra forma) y arranca
- DEAD  : codigo hoy obsoleto/inalcanzable (se conserva, anotado)
- GAP   : sin test automatico todavia (verificacion pendiente)


## Deltas C64 del BASIC

| Delta | Evidencia | Nota |
|-------|-----------|------|
| ZP desde $03 (puerto 6510) | MECH + VICE | Se trazo la escritura de un opcode JMP a $00-$02; el monitor de VICE mostro $01=$5B. Causa demostrada, no supuesta. |
| ROMLOC=$A000 | STRUCT + TEST | La ROM tiene que estar donde esta; banner arranca. |
| RAMLOC=$0801 | STRUCT + TEST | $0400 es la pantalla; "38911 BYTES FREE" confirma. |
| .org $E000 (continuacion) | STRUCT | El BASIC desborda 8KB; Commodore hizo lo mismo. Arranca. |
| tope del sondeo en $A000 | TEST | "38911 BYTES FREE" exacto. |
| USRPOK=$0310 | TEST + VICE | test_basic: USR(7)->7. (Antes solo afirmado; ahora probado.) |
| SYS -> KSYS | VICE + MECH | Borde arcoiris por SYS; KSYS reubicado tras detectar ensamblado fuera de $FFFF. |
| candado anti-PEEK eliminado | TEST + VICE | test_basic: PEEK($A000)=117 (el candado daba 0). |
| FPWRT JEQ | MECH | Forzado por error real de rango del ensamblador. |
| fixup DEL en INLIN | **DEAD** | El editor de pantalla consume DEL antes de servir la linea; INLIN ya nunca ve $14. Codigo obsoleto, inofensivo. Candidato a retirar. |


## Subsistemas del KERNAL

| Subsistema | Evidencia | Nota |
|------------|-----------|------|
| Orden de arranque (puerto 6510) | MECH + VICE | El orden datos-antes-que-DDR se fijo tras pantalla negra en VICE. |
| CHROUT (conversion screencode) | TEST | Cubierto por tests de editor/paste. |
| SCNKEY + flag Z columna 0 | TEST + MECH | El LDX que pisaba Z se trazo; RETURN/DEL/V emiten. |
| Shift | TEST | shift+2 = comillas. |
| Repeticion de tecla | TEST | espacio repite con retardo+cadencia; Q no. |
| Cursor parpadeante + gating KBLSW | TEST + VICE | Transparencia del IRQ verificada por diff. |
| Scroll | TEST + MECH | El solape de copias se desnudo con el patron fila=valor. |
| Vectores pagina 3 (IRQ) | VICE | Demo del borde arcoiris encadenado al kernal. |
| BRK/NMI (despacho) | **GAP** | Solo la via IRQ tiene test (transparencia). BRK/NMI sin test automatico. |
| RESTOR / VECTOR ($FF8A/$FF8D) | **GAP** | Implementados, sin test automatico. |
| Editor v1 (WYSIWYG) | TEST | Sobrescritura, DEL que recoge, wrap, paste. |
| Editor v2 (line-link, nav vertical) | TEST | Editar linea listada y re-entrarla cambia el programa. |


## Huecos de compatibilidad encontrados en esta auditoria

1. **Variables ZP en direcciones no estandar.** Al desplazar la pagina
   cero del BASIC a $03, las variables internas (TXTTAB, MEMSIZ, etc.)
   NO caen en las direcciones documentadas del C64 ($2B/$2C, $37/$38...).
   `PEEK(44)` devuelve 3, no 8. Los programas que leen/escriben esas
   posiciones documentadas leeran valores incorrectos. Falta un mapa de
   compatibilidad ZP o reubicar variables clave a sus direcciones C64.
   NO RESUELTO.

2. **fixup DEL en INLIN es codigo muerto** (ver arriba).


## Falsas alarmas y ruido de proceso (rendicion de cuentas)

Estos episodios quedan documentados para honestidad del registro:

- **"El blink corrompe el sondeo de memoria"**: hipotesis falsa. El
  sondeo empieza en $0800; el cursor nunca lo toca. Se perdio tiempo
  persiguiendola.
- **"KROW=0" durante el desarrollo de v2**: no era bug del kernal, sino
  del arnes de pruebas, que cargaba un binario anterior a v2 desde
  build/. Lección: sincronizar src/ y reconstruir antes de testar.
- **Implicar que reconstruir binarios "frescos" (con sus MD5) podia
  resolver la corrupcion tecleada del usuario**: no habia base para esa
  insinuacion. Era entregar algo mientras no se hallaba la causa.
- **El arreglo del scroll (solape) y el del paste eran bugs REALES con
  prueba reproducible**, pero NO eran la corrupcion que el usuario
  reportaba al teclear a mano. Esa la causaba la falta de editor de
  pantalla, diagnosticada y resuelta despues. Durante la busqueda se
  presentaron arreglos intermedios con mas seguridad de la debida en
  vez de admitir antes "no reproduzco tu caso, necesito tu receta
  exacta".

El metodo correcto, aplicado al final y de aqui en adelante: ante un
fallo no reproducible, pedir la receta exacta del usuario antes de
cambiar codigo, y no presentar un cambio como solucion de SU problema
sin una prueba que lo ligue a ese problema.
