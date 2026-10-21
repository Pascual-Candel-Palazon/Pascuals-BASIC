; ============================================================
;  KERNAL libre para Commodore 64: sala limpia
;  Escrito desde especificacion documentada (tabla de saltos
;  estandar $FF81+, registros VIC-II/CIA publicados, matriz de
;  teclado documentada) y comportamiento observable. Sin codigo
;  derivado de la ROM original. Politica: docs/PROCEDENCIA.md.
;
;  Implementa: arranque, pantalla y editor WYSIWYG, teclado por
;  IRQ, vectores de pagina 3, cartuchos CBM80, toda la tabla de
;  saltos (sin stubs), bus serie IEC y datasette (LOAD/SAVE/VERIFY).
;  No implementa RS-232 (dispositivo 2).
;  Arranca el BASIC (simbolo INIT del modulo BASIC).
; ============================================================

; --- RAM propia del kernal (fuera de las zonas que usa el BASIC) ---
KVPTR   = $C3
KSERT   = $9B             ; temporal de KSERIN (fuera del IRQ)
KCPTR   = $F3           ; puntero a la RAM de color (USER, documentado; $FB-$FE quedan libres)
KMSGFL  = $009D         ; flags de mensajes del kernal
KLDTND  = $0098         ; numero de ficheros abiertos
KDFLTN  = $0099         ; dispositivo de entrada por defecto
KDFLTO  = $009A         ; dispositivo de salida por defecto
KSTATUS = $0090         ; estado de E/S del kernal
KVERCK  = $0093         ; flag load(0)/verify(1)
KATNF   = $0094         ; bit7: byte bajo ATN
KBSOUR  = $0095         ; byte serie a enviar (diferido)
KC3PO   = $00A3         ; bit7: hay byte CIOUT pendiente
KEOIF   = $00A4         ; bit7: senalar EOI
KBSOUR2 = $00A5         ; byte en curso de envio (se desplaza)
KBITCNT = $00A6         ; contador de bits
KSERHI  = $00A7         ; byte alto del timeout RFD (espera de oyente)
KLDPTR  = $00AE         ; puntero destino/fin de LOAD-SAVE (lo/hi)
KLDTMP  = $00AC         ; byte bajo temporal de la direccion de carga
KSAVPTR = $00C1         ; puntero de trabajo de SAVE (lo/hi)
KFNLEN  = $00B7         ; longitud del nombre de fichero
KLA     = $00B8         ; fichero logico actual
KSA     = $00B9         ; direccion secundaria actual
KFA     = $00BA         ; dispositivo actual
KFNADR  = $00BB         ; puntero al nombre (2 bytes)
KLAT    = $0259         ; tabla de ficheros logicos (10)
KFAT    = $0263         ; tabla de dispositivos (10)
KSAT    = $026D         ; tabla de direcciones secundarias (10)
KTIMOUT = $0285         ; flag de timeout IEEE (mapa C64 publico). Lo pone
                        ; SETTMO; lo consulta el cartucho IEEE-488, no el bus serie.
KPNT    = $D1           ; puntero a linea actual de pantalla (lo/hi)
KCOL    = $D3           ; columna del cursor (0-39)
KNDX    = $C6           ; numero de teclas en bufer
KTIME   = $A0           ; reloj jiffy (3 bytes)
KBUF    = $0277         ; bufer de teclado (10 bytes)
KMATRIX = $0293         ; matriz del teclado (8 bytes; zona RS232, sin uso aqui)

SCREEN  = $0400
COLOR   = $D800

.org $E200              ; tras la continuacion del BASIC

; --- variables del editor y del teclado (antes repartidas por la seccion) ---
KBLCNT  = $CD           ; cuenta del parpadeo (documentado)
KBLON   = $CF           ; cursor encendido (documentado)
KBLSW   = $9F
KLCOL   = $028C
KLMASK  = $028E
KLIDX   = $9E
KRPT    = $028B         ; contador de repeticion (KOUNT)
KTMP    = $D7
KTMP2   = $F2
KPREV   = $029B         ; estado anterior para deteccion de flanco (8 bytes)
KSHIFT  = $02A3
KTMP3   = $F5
; KLINE: bufer de la linea logica leida de pantalla (hasta 80 bytes).
; Comparte direccion con el BUF del BASIC ($0200, 81 bytes). Es seguro
; porque quien consume CHRIN (INLIN del BASIC, o un lector de codigo
; maquina tipico) guarda el caracter k en la posicion <= k DESPUES de que
; el editor lo haya servido: nunca pisa algo que quede por leer.
; Antes estaba en $033C (buffer de cinta, 828): cada linea tecleada
; machacaba las rutinas de usuario que se cargan ahi (POKE + SYS 828).
KLINE   = $0200
KLLEN   = $C8
KLPOS   = $CE
KLSTART = $CA
KCOLOR  = $0286         ; color actual del cursor/texto
KGDCOL  = $0287         ; color guardado bajo el cursor (ubicacion C64)
KMBOT   = $0281         ; inicio de memoria (2 bytes)
KMTOP   = $0283         ; tope de memoria (2 bytes)
KRVS    = $C7           ; flag de inverso ($00/$80); direccion documentada (199)
KQTSW   = $D4           ; modo comillas (bit0); direccion documentada (212)
KINSRT  = $D8           ; espacios insertados pendientes (modo insercion, 216)
KLQ     = $F8           ; comillas vistas al leer la linea de pantalla (bit0)
KCTRL   = $02A4
KCBM    = $02A5
KCASE   = $0292         ; flanco de SHIFT+C=
KLNK    = $D9           ; tabla de enlace de lineas (25 bytes, $D9-$F1, como el C64)
KROW    = $D6           ; fila del cursor 0-24 (direccion documentada, 214)
KEDROW  = $C9           ; fila donde empezo la entrada
KSROW   = $D0           ; fila de inicio de la linea logica
KLSTRT2 = $D5           ; columna inicial efectiva
KLNKV   = $F6           ; valor a estampar en KLNK (inicio/continuacion)
KCNT    = $FA
KSCR0   = $F7
KSCRCNT = $F9

; FIJA dir: rellena con NOP hasta la direccion fija dir (entradas internas
; conocidas del C64 que los programas llaman directamente). Falla si el
; codigo anterior ya la ha pasado.
.macro FIJA dir
 .assert * <= dir, error, "FIJA: el codigo anterior pasa de la direccion fija"
 .if dir - * > 0
  .res dir - *, $EA
 .endif
.endmacro

; ------------------------------------------------------------
; CINT ($FF81): VIC de pantalla, editor y teclado
; ------------------------------------------------------------
KCINT:
        ; --- VIC-II ---
        lda #$1B
        sta $D011       ; modo texto, pantalla visible
        lda #$C8
        sta $D016       ; 40 columnas
        lda #$15        ; pantalla $0400, caracteres $1000 (chargen)
        sta $D018
        lda #$00
        sta $D015       ; sprites fuera
        lda #$0E
        sta $D020       ; borde azul claro
        sta KCOLOR      ; texto azul claro al arrancar (CLR no lo cambia)
        lda #$06
        sta $D021       ; fondo azul
        lda #$04
        sta $0288       ; pagina de la pantalla (648); el editor usa $0400
        ; --- PAL/NTSC ($02A6, 678): 1 si existe la linea de raster 311 ---
        ldx #$00
@pl:    lda $D011
        bpl @pl         ; esperar a una linea >= 256
@p2:    lda $D012
        cmp #$37        ; 311 = $137
        beq @pal
        lda $D011
        bmi @p2
        bpl @ntsc       ; volvio a < 256 sin pasar por la 311
@pal:   inx
@ntsc:  stx $02A6
        ; --- limpiar pantalla y color ---
        jsr KCLS
        ; --- estado de teclado y editor ---
        lda #$00
        sta KNDX
        sta KRVS
        sta KCTRL
        sta KCBM
        sta KCASE
        sta KSHIFT
        sta KBLON
        sta KBLSW
        sta KLMASK
        sta KRPT
        sta KLLEN
        sta KLPOS
        sta KSCRCNT
        lda #20
        sta KBLCNT
        lda #$00
        ldx #$07
@mx:    sta KMATRIX,X
        dex
        bpl @mx
        rts

; ------------------------------------------------------------
; CHROUT: imprime PETSCII en pantalla (A = caracter)
; conserva A, X, Y
; ------------------------------------------------------------
KCHROUT:
        pha
        ; --- si la salida por defecto es a dispositivo serie (>=4),
        ;     enviar el byte por el bus IEC en vez de a pantalla. ---
        lda KDFLTO
        cmp #$04
        bcc KSCRPL
        txa
        pha
        tya
        pha
        tsx
        lda $0103,X     ; A original (pila: Y@+1, X@+2, A@+3)
        jsr KCIOUT      ; CIOUT (envio diferido); destruye X/Y, restaurados al salir
        pla
        tay
        pla
        tax
        pla
        clc
        rts
KSCRPL: pla
; KSCROUT ($E716): escribe el caracter A en la pantalla, sin mirar el
; dispositivo de salida. Conserva A, X e Y.
KSCROUT:
        php
        sei             ; el blink del IRQ no debe tocar mientras movemos
        pha
        txa
        pha
        tya
        pha
        jsr KCUROFF     ; apagar el cursor si esta encendido
        lda #20
        sta KBLCNT      ; reiniciar la cadencia al teclear
@nocur: tsx
        lda $0103,X     ; A original (pila: Y@+1, X@+2, A@+3, P@+4)
        ; --- modo comillas y modo insercion (comportamiento documentado):
        ;     la comilla conmuta el modo; dentro, los controles no se
        ;     ejecutan sino que se ven como caracteres invertidos. DEL e
        ;     INST siguen funcionando en comillas; en insercion solo INST.
        ;     RETURN sale de los dos modos ---
        cmp #$22
        bne @noq
        inc KQTSW
        jmp @ok1        ; la comilla se imprime normal
@noq:   cmp #$8D        ; SHIFT+RETURN: retorno de carro
        bne @no8d
        jmp @cr
@no8d:  tay
        and #$7F
        cmp #$20
        bcs @nctl       ; no es control
        cpy #$0D
        beq @nctl
        lda KINSRT
        bne @rev        ; insercion: todo se ve (salvo INST)
        lda KQTSW
        lsr a
        bcc @nctl       ; modo normal: ejecutar
        cpy #$14
        beq @nctl       ; DEL funciona en comillas
@rev:   cpy #$94
        beq @nctl       ; INST siempre se ejecuta
        tya
        bmi @rv8
        ora #$80        ; $00-$1F -> pantalla $80-$9F (letra invertida)
        jmp @store
@rv8:   clc
        adc #$40        ; $80-$9F -> pantalla $C0-$DF
        jmp @store
@nctl:  tya
        ; --- ¿es un codigo de color (CTRL+1..8 / C=+1..8)? ---
        ldx #15
@colt:  cmp KCOLTAB,X
        beq @setcol
        dex
        bpl @colt
        cmp #$12        ; RVS ON (inverso)
        beq @jrvson
        cmp #$92        ; RVS OFF
        beq @jrvsoff
        cmp #$0E        ; minusculas (juego de texto)
        beq @jlower
        cmp #$8E        ; mayusculas/graficos
        beq @jupper
        cmp #$0D        ; retorno de carro
        beq @jcr
        cmp #$1D        ; cursor a la derecha
        beq @jright
        cmp #$11        ; cursor abajo
        beq @jdown
        cmp #$91        ; cursor arriba
        beq @jup
        cmp #$9D        ; cursor a la izquierda
        beq @jleft
        cmp #$14        ; DEL: retroceso visual
        beq @jdel
        cmp #$93        ; limpiar pantalla
        beq @jcls
        jmp @clasif
@jcr:   jmp @cr
@jright: jmp @right
@jdown: jmp @down
@jup:   jmp @up
@jleft: jmp @left
@jdel:  jmp @del
@jcls:  jmp @cls
@setcol: stx KCOLOR     ; X = indice de color 0..15
        jmp @done
@jrvson: lda #$80        ; inverso ON: bit 7 en el screencode
        sta KRVS
        jmp @done
@jrvsoff: lda #$00
        sta KRVS
        jmp @done
@jlower: lda #$17        ; $D018 bit1=1 -> juego de texto (minusculas)
        sta $D018
        jmp @done
@jupper: lda #$15        ; $D018 bit1=0 -> juego mayusculas/graficos
        sta $D018
        jmp @done
@clasif:
        cmp #$13        ; HOME
        beq @jhome
        cmp #$94        ; INST
        beq @jinst
        cmp #$20
        bcs @ok1
        jmp @done       ; otros controles: ignorar
@jhome: jmp @home
@jinst: jmp @inst
@ok1:
        ; --- PETSCII -> codigo de pantalla (conversion completa) ---
        cmp #$40
        bcc @store      ; $20-$3F: identico
        cmp #$60
        bcs @r60
        sec
        sbc #$40        ; $40-$5F -> $00-$1F
        jmp @store
@jd3:   jmp @done
@r60:   cmp #$80
        bcs @r80
        sec
        sbc #$20        ; $60-$7F -> $40-$5F
        jmp @store
@r80:   cmp #$A0
        bcc @jd3        ; $80-$9F: controles, ya tratados arriba
        cmp #$C0
        bcs @rc0
        sec
        sbc #$40        ; $A0-$BF -> $60-$7F (graficos C=)
        jmp @store
@rc0:   sec
        sbc #$80        ; $C0-$FF -> $40-$7F (graficos shift)
@store: ora KRVS        ; inverso: bit 7 si esta activo
        ldy KCOL
        sta (KPNT),Y
        ; escribir el color actual en la RAM de color ($D800 = KPNT+$D400)
        lda KPNT
        sta KCPTR
        lda KPNT+1
        clc
        adc #$D4
        sta KCPTR+1
        lda KCOLOR
        sta (KCPTR),Y
        lda KINSRT
        beq @nins
        dec KINSRT      ; un espacio insertado menos
@nins:  inc KCOL
        lda KCOL
        cmp #40
        bcc @jd3
        lda #$00        ; wrap: la nueva fila es CONTINUACION
        sta KLNKV
        jmp @advrow
@cr:    lda #$00        ; CR apaga inverso, comillas e insercion (documentado)
        sta KRVS
        sta KQTSW
        sta KINSRT
        lda #$80        ; CR explicito: la nueva fila INICIA linea logica
        sta KLNKV
@advrow:
        lda #$00
        sta KCOL
        clc
        lda KPNT
        adc #40
        sta KPNT
        bcc @ck
        inc KPNT+1
@ck:    inc KROW
        ; pasamos de la fila 24? (PNT > $07C0)
        lda KPNT+1
        cmp #>(SCREEN+1000)
        bcc @stamp
        bne @scroll
        lda KPNT
        cmp #<(SCREEN+1000)
        bcc @stamp
@scroll:
        jsr KSCROLL     ; resetea KPNT/KROW a fila 24 y desplaza KLNK
@stamp: ldx KROW
        lda KLNKV
        sta KLNK,X
        jmp @done
@right: inc KCOL
        lda KCOL
        cmp #40
        bcs @cr
        jmp @done
@home:  lda #<SCREEN    ; cursor a (0,0)
        sta KPNT
        lda #>SCREEN
        sta KPNT+1
        lda #$00
        sta KCOL
        sta KROW
        jmp @done
@inst:  ; insertar un espacio en el cursor: desplazar la fila a la derecha
        ldy #39
@ins1:  cpy KCOL
        beq @ins2       ; llegamos al hueco
        dey
        lda (KPNT),Y
        iny
        sta (KPNT),Y    ; col(y-1) -> col(y)
        dey
        jmp @ins1
@ins2:  lda #$20
        sta (KPNT),Y    ; espacio en la columna del cursor
        inc KINSRT      ; modo insercion: lo que se teclee en el hueco
        jmp @done
@del:   lda KCOL
        beq @done       ; en columna 0 no hay nada que borrar
        dec KCOL
        ldy KCOL
        lda #$20
        sta (KPNT),Y
        jmp @done
@down:  clc
        lda KPNT
        adc #40
        sta KPNT
        bcc @dk
        inc KPNT+1
@dk:    inc KROW
        lda KPNT+1
        cmp #>(SCREEN+1000)
        bcc @done
        bne @dsc
        lda KPNT
        cmp #<(SCREEN+1000)
        bcc @done
@dsc:   jsr KSCROLL     ; fija KROW=24
        jmp @done
@up:    lda KPNT+1
        cmp #>SCREEN
        bne @upok
        lda KPNT
        cmp #<SCREEN
        beq @jdone2     ; ya en la primera linea
@upok:  sec
        lda KPNT
        sbc #40
        sta KPNT
        bcs @uk
        dec KPNT+1
@uk:    dec KROW
        jmp @done
@left:  lda KCOL
        beq @jdone2     ; en columna 0: nada (sin wrap en v1)
        dec KCOL
        jmp @done
@jdone2: jmp @done
@cls:   jsr KCLS
@done:  pla
        tay
        pla
        tax
        pla
        plp
        clc
        rts

; codigo de pantalla (A) -> PETSCII (A) al leer la linea. Dentro de
; comillas, un caracter invertido es un control escrito en modo comillas
; ($80-$9F -> $00-$1F, $C0-$DF -> $80-$9F); fuera, el inverso se ignora.
KSC2P:  cmp #$22
        bne @n
        inc KLQ         ; comilla: conmuta (bit0)
        rts
@n:     cmp #$80
        bcc @norm
        pha
        lda KLQ
        lsr a
        pla
        bcc @norm       ; fuera de comillas
        and #$7F
        cmp #$20
        bcc @r          ; control $00-$1F
        cmp #$40
        bcc @norm2
        cmp #$60
        bcs @norm2
        adc #$40        ; $40-$5F -> control $80-$9F (C=0)
@r:     rts
@norm:  and #$7F
@norm2: cmp #$20
        bcc @a40        ; sc 0-31 -> PETSCII $41-$5F
        cmp #$40
        bcc @r          ; sc $20-$3F: identico
        adc #$7F        ; sc $40-$7E -> PETSCII $C0+ (C=1: +$80)
        rts
@a40:   adc #$40        ; (C=0)
        rts

; apagar el cursor si esta invertido (auxiliar del editor)
KCUROFF:
        pha
        lda KBLON
        beq @no
        php             ; (CHROUT la llama con IRQ ya enmascaradas)
        sei
        tya
        pha
        ldy KCOL
        lda (KPNT),Y
        eor #$80
        sta (KPNT),Y
        lda KPNT        ; restaurar el color guardado bajo el cursor
        sta KCPTR
        lda KPNT+1
        clc
        adc #$D4
        sta KCPTR+1
        lda KGDCOL
        sta (KCPTR),Y
        lda #$00
        sta KBLON
        pla
        tay
        plp
@no:    pla
        rts

; ------------------------------------------------------------
; GETIN: saca un caracter del bufer (A=0, Z=1 si vacio)
; ------------------------------------------------------------
KGETIN: lda KDFLTN
        cmp #$04
        bcc @noser
        jmp KSERIN      ; entrada desde el bus serie
@noser: txa
        pha             ; preservar X e Y: INLIN del BASIC depende de ello
        tya
        pha
        ldx KNDX
        beq @empty
        sei
        lda KBUF
        sta KTMP3
        ldx #$00
@sh:    lda KBUF+1,X
        sta KBUF,X
        inx
        cpx KNDX
        bcc @sh
        dec KNDX
        cli
        pla
        tay
        pla
        tax
        lda KTMP3       ; A = caracter (Z=0 salvo char NUL)
        rts
@empty: pla
        tay
        pla
        tax
        lda #$00
        rts

; X = indice 0-63 -> A = PETSCII segun modificadores (preserva Y).
; Prioridad: CTRL > C= > SHIFT > normal.
KXLATE:
        lda KCTRL
        bne @ct
        lda KCBM
        bne @cb
        lda KSHIFT
        bne @sh
        lda KEYTAB,X
        rts
@ct:    lda KEYTABT,X
        rts
@cb:    lda KEYTABC,X
        rts
@sh:    lda KEYTABS,X
        rts


FIJA $E544
; ------------------------------------------------------------
; CLS ($E544, entrada interna conocida): limpiar pantalla y cursor a (0,0). Conserva el color de
; texto (646) y rellena la RAM de color con el, como el C64.
; ------------------------------------------------------------
KCLS:   ldx #24
@r:     lda #$80        ; toda fila es inicio de linea logica
        sta KLNK,X
        txa
        pha
        jsr KCLRLN
        pla
        tax
        dex
        bpl @r
        ldx #$00        ; cursor a (0,0)
        ldy #$00
        clc
        jmp KPLOT

; PETSCII de los 16 codigos de color: CTRL+1..8 (0..7), C=+1..8 (8..15)
KCOLTAB:
        .byte $90,$05,$1C,$9F,$9C,$1E,$1F,$9E
        .byte $81,$95,$96,$97,$98,$99,$9A,$9B


FIJA $E56C
; $E56C (58732, entrada interna conocida): rehace el puntero de la linea
; de pantalla desde la fila (214) y la columna (211); p. ej.
; POKE214,F:POKE211,C:SYS58732 mueve el cursor.
KE56C:  ldx KROW
        ldy KCOL
        clc
        jmp KPLOT

; ------------------------------------------------------------
; SCNKEY: escaneo de la matriz; mete nuevas pulsaciones en KBUF
; (sin shift en v0). Deteccion de flanco contra KPREV.
; ------------------------------------------------------------
KSCNKEY:
        ldx #$00        ; columna CIA 0..7
@col:   lda KROWSEL,X
        sta $DC00
        lda $DC01
        eor #$FF        ; bits a 1 = teclas pulsadas
        sta KMATRIX,X
        inx
        cpx #$08
        bne @col
        lda #$00
        sta $DC00       ; todas las filas activas (para STOP)
        ; --- estado de shift: LSHIFT col1/bit7, RSHIFT col6/bit4 ---
        lda #$00
        sta KSHIFT
        lda KMATRIX+1
        and #$80
        beq @nols
        inc KSHIFT
@nols:  lda KMATRIX+6
        and #$10
        beq @nors
        inc KSHIFT
@nors:
        ; --- CTRL (col7 bit2) y C= (col7 bit5) ---
        lda #$00
        sta KCTRL
        sta KCBM
        lda KMATRIX+7
        and #$04
        beq @noctrl
        inc KCTRL
@noctrl: lda KMATRIX+7
        and #$20
        beq @nocbm
        inc KCBM
@nocbm:
        ; --- SHIFT+C= conmuta el caso (deteccion de flanco), salvo con el
        ;     bit 7 de $0291 (657) a 1, como en el C64 ---
        bit $0291
        bmi @combof
        lda KSHIFT
        beq @combof
        lda KCBM
        beq @combof
        lda KCASE
        bne @afterc
        lda $D018
        eor #$02
        sta $D018
        lda #$01
        sta KCASE
        jmp @afterc
@combof: lda #$00
        sta KCASE
@afterc:
        ; --- detectar flancos y traducir ---
        ldx #$00
@cmpc:  lda KMATRIX,X
        tay             ; actual
        eor KPREV,X
        and KMATRIX,X   ; 1 = recien pulsada
        sta KTMP
        tya
        sta KPREV,X
        ldy #$00
@bit:   lda KTMP
        and KBITS,Y
        beq @next
        ; indice en la tabla = columna*8 + bit
        txa
        asl
        asl
        asl
        sta KTMP2
        tya
        clc
        adc KTMP2
        stx KTMP2       ; preservar X
        tax
        jsr KXLATE
        beq @restx      ; tecla sin asignar: descartar
        cmp #$83        ; SHIFT+RUN/STOP: autollenar LOAD + RUN
        bne @srun
        jsr KSRSTUF
        ldx KTMP2       ; restaurar columna
        jmp @next
@srun:  ldx KTMP2
        sty KTMP2       ; preservar Y
        ; --- registrar la tecla para la repeticion ---
        pha
        txa
        sta KLCOL       ; columna de la ultima tecla
        ldy KTMP2
        lda KBITS,Y
        sta KLMASK      ; mascara de bit
        txa
        asl
        asl
        asl
        sta KLIDX
        tya
        clc
        adc KLIDX
        sta KLIDX       ; indice 0-63 en las tablas
        lda #$00
        sta KRPT        ; reiniciar el contador de repeticion
        pla
        ; --- al bufer ---
        ldy KNDX
        cpy #10
        bcs @full
        sta KBUF,Y
        inc KNDX
@full:  ldy KTMP2
        jmp @next
@restx: ldx KTMP2
@next:  iny
        cpy #$08
        bne @bit
        inx
        cpx #$08
        beq @scand
        jmp @cmpc
@scand: ; --- repeticion de tecla mantenida ---
        lda KLMASK
        beq @norpt      ; no hay tecla registrada
        ldx KLCOL
        and KMATRIX,X
        bne @held
        lda #$00        ; soltada: olvidar
        sta KLMASK
        beq @norpt
@held:  inc KRPT
        lda KRPT
        cmp #16         ; retardo inicial
        bcc @norpt
        cmp #20         ; cadencia: cada 4 jiffies
        bcc @norpt
        lda #16
        sta KRPT
        ; re-traducir con el shift actual
        ldx KLIDX
        jsr KXLATE
        beq @norpt
        ; ¿es repetible? espacio, cursores, DEL, INS
        ldx #$06
@rptst: cmp KRPTSET,X
        beq @rpok
        dex
        bpl @rptst
        bmi @norpt
@rpok:  ldx KNDX
        cpx #10
        bcs @norpt
        sta KBUF,X
        inc KNDX
@norpt: ; --- variables documentadas del teclado ---
        lda #64         ; $C5/$CB: codigo de la tecla pulsada (64 = ninguna)
        ldx KLMASK
        beq @nk
        lda KLIDX       ; columna*8 + fila de la matriz
@nk:    sta $CB
        sta $C5
        lda KCTRL       ; $028D: bit0 SHIFT, bit1 C=, bit2 CTRL
        asl a
        ora KCBM
        asl a
        ldx KSHIFT
        beq @ns
        ora #$01
@ns:    sta $028D
        rts

; tabla matriz->PETSCII (sin shift), fila=columna CIA, 8x8
KEYTAB:
        .byte $14,$0D,$1D,$88,$85,$86,$87,$11  ; DEL RET csrLR F7 F1 F3 F5 csrUD
        .byte '3','W','A','4','Z','S','E',$00  ; ... LSHIFT
        .byte '5','R','D','6','C','F','T','X'
        .byte '7','Y','G','8','B','H','U','V'
        .byte '9','I','J','0','M','K','O','N'
        .byte '+','P','L','-','.',':','@',','
        .byte $5C,'*',';',$13,$00,'=',$5E,'/'  ; libra * ; HOME RSHIFT = flecha /
        .byte '1',$5F,$00,'2',' ',$00,'Q',$03  ; 1 <- CTRL 2 SPC C= Q STOP


FIJA $E716
; $E716 (59158, entrada interna conocida): escribir A en la pantalla
KE716:  jmp KSCROUT

; ------------------------------------------------------------
; CHRIN: espera un caracter, lo devuelve con eco
; ------------------------------------------------------------
; ------------------------------------------------------------
; CHRIN v2: entrada editada en pantalla (WYSIWYG).
; Bucle editor: cursores mueven, DEL recoge el texto. Al pulsar
; RETURN se lee la linea DESDE la pantalla (codigo de pantalla ->
; PETSCII) y se sirve al BASIC caracter a caracter. Limite v1:
; la linea logica es una fila (40 columnas).
; ------------------------------------------------------------
KCHRIN: lda KDFLTN
        cmp #$04
        bcc @noser
        jmp KSERIN      ; entrada desde el bus serie
@noser: ldx KLLEN
        beq @editar     ; no hay linea pendiente: entrar al editor
@servir:
        ldx KLPOS
        cpx KLLEN
        bcc @sigue
        lda #$00        ; agotada
        sta KLLEN
        sta KLPOS
        lda #$0D
        jsr KCHROUT     ; eco del retorno (avanza linea)
        lda #$0D
        clc
        rts
@sigue: lda KLINE,X
        inc KLPOS
        clc
        rts

@editar:
        lda KCOL
        sta KLSTART
        lda KROW
        sta KEDROW      ; fila donde empezo la entrada (para la col inicial)
        lda KSCRCNT
        sta KSCR0       ; scrolls vistos al empezar a editar
        lda #$01
        sta KBLSW       ; cursor visible
@bucle: jsr KGETIN
        beq @bucle
        cmp #$0D
        beq @jfin
        ; en comillas o insercion las teclas de control se imprimen
        ; (KCHROUT las invierte), salvo INST y, solo en comillas, DEL
        tay
        and #$7F
        cmp #$20
        tya
        bcs @nomodo
        cmp #$94
        beq @nomodo
        ldx KINSRT
        bne @jimp
        ldx KQTSW
        beq @nomodo     ; (KQTSW: bit0; tras un CR vale 0)
        txa
        lsr a
        tya
        bcc @nomodo
        cmp #$14
        beq @nomodo
@jimp:  jmp @imp
@nomodo:
        cmp #$14        ; DEL: recoger el texto hacia atras
        beq @jdel2
        cmp #$1D        ; derecha
        beq @jder
        cmp #$9D        ; izquierda
        beq @jizq
        cmp #$11        ; abajo
        beq @jdwn
        cmp #$91        ; arriba
        beq @jup2
        cmp #$20
        bcc @ctl        ; controles: aplicar via KCHROUT (color/inverso/caso)
        cmp #$60
        bcc @imp        ; $20-$5F: directo
        cmp #$7B
        bcs @alta
        sec
        sbc #$20        ; $61-$7A (minusculas estilo ASCII) -> $41-$5A
        jmp @imp
@ctl:   jsr KCHROUT     ; codigos de control: color/inverso/caso aplican
        jmp @bucle
@jfin:  jmp @fin
@alta:  cmp #$C1
        bcc @ctl        ; $80-$C0 (color/inverso/caso altos) via KCHROUT
        cmp #$DB
        bcs @bucle
        jmp @imp        ; $C1-$DA: mayuscula/grafico shifted, imprimir tal cual
@imp:   jsr KCUROFF
        jsr KCHROUT     ; imprimir (sobrescribe en el cursor)
        jmp @bucle
@jdwn:  jsr KCUROFF
        lda #$11
        jsr KCHROUT     ; mueve KPNT/KROW abajo
        jmp @bucle
@jup2:  jsr KCUROFF
        lda #$91
        jsr KCHROUT     ; mueve KPNT/KROW arriba
        jmp @bucle
@jdel2: jmp @del2
@jder:  jsr KCUROFF
        lda KCOL
        cmp #39
        bcs @jb3
        inc KCOL
        jmp @bucle
@jizq:  jsr KCUROFF
        lda KCOL
        beq @jb3        ; ya en columna 0
        dec KCOL
@jb3:   jmp @bucle
@del2:  jsr KCUROFF
        lda KCOL
        beq @jb2        ; nada que borrar en columna 0
        dec KCOL
        ldy KCOL
@pull:  iny
        cpy #40
        bcs @cap
        lda (KPNT),Y
        dey
        sta (KPNT),Y
        iny
        jmp @pull
@cap:   lda #$20
        ldy #39
        sta (KPNT),Y
@jb2:   jmp @bucle

@fin:   jsr KCUROFF
        lda #$00
        sta KBLSW
        ; --- ajustar KEDROW por los scrolls ocurridos durante la edicion ---
        lda KSCRCNT
        sec
        sbc KSCR0
        beq @noadj
        sta KCNT
@adj:   dec KEDROW
        dec KCNT
        bne @adj
@noadj: lda KEDROW
        bpl @edok
        lda #$00
        sta KEDROW
@edok:  ; --- buscar la fila de INICIO de la linea logica desde KROW ---
        ldx KROW
@fs:    lda KLNK,X
        bmi @gs         ; bit7 = inicio
        dex
        bpl @fs
        ldx #$00
@gs:    stx KSROW
        ; columna inicial: si la fila de inicio es la de entrada, usar
        ; KLSTART (salta el prompt); si no, leer desde la columna 0
        lda #$00
        sta KLSTRT2
        lda KSROW
        cmp KEDROW
        bne @sc0
        lda KLSTART
        sta KLSTRT2
@sc0:   ldx KSROW       ; KVPTR = SCREEN + KSROW*40
        jsr KROWP
        ; copiar fila de inicio: columnas KLSTRT2..39
        ldx #$00        ; X = longitud en KLINE
        stx KLQ         ; fuera de comillas al empezar
        ldy KLSTRT2
@cp1:   lda (KVPTR),Y
        jsr KSC2P
@k1:    sta KLINE,X
        inx
        iny
        cpy #40
        bcc @cp1
        ; ¿hay fila de continuacion? (KSROW+1<=24 y su KLNK no es inicio)
        lda KSROW
        cmp #24
        bcs @strip
        tay
        iny
        lda KLNK,Y
        bmi @strip      ; la siguiente fila inicia otra linea
        clc
        lda KVPTR
        adc #40
        sta KVPTR
        bcc @c2
        inc KVPTR+1
@c2:    ldy #$00
@cp2:   lda (KVPTR),Y
        jsr KSC2P
@k2:    sta KLINE,X
        inx
        iny
        cpy #40
        bcc @cp2
@strip: ; quitar blancos finales ($20) de KLINE[0..X-1]
        cpx #$00
        beq @hecho
@st1:   dex
        lda KLINE,X
        cmp #$20
        bne @st2
        cpx #$00
        bne @st1
        ldx #$00        ; toda blanca
        jmp @hecho
@st2:   inx             ; X = longitud sin blancos finales
@hecho: stx KLLEN
        lda #$00
        sta KLPOS
        jmp @servir

; tabla con shift
KEYTABS:
        .byte $94,$0D,$9D,$8C,$89,$8A,$8B,$91  ; INS RET csrLR F8 F2 F4 F6 csrUD
        .byte '#','W'+$80,'A'+$80,'$','Z'+$80,'S'+$80,'E'+$80,$00
        .byte '%','R'+$80,'D'+$80,'&','C'+$80,'F'+$80,'T'+$80,'X'+$80
        .byte $27,'Y'+$80,'G'+$80,'(','B'+$80,'H'+$80,'U'+$80,'V'+$80
        .byte ')','I'+$80,'J'+$80,'0','M'+$80,'K'+$80,'O'+$80,'N'+$80
        .byte '+','P'+$80,'L'+$80,'-','>','[','@','<'
        .byte $5C,'*',']',$93,$00,'=',$5E,'?'  ; shift+HOME = CLR
        .byte '!',$5F,$00,'"',' ',$00,'Q'+$80,$83  ; shift+2=comillas; shift+RUN/STOP=LOAD+RUN

; tabla CTRL. CTRL+1..8 colores, +9/0 inverso, CTRL+letra = codigo de
; control PETSCII (1..26), mas algunos simbolos. Valores tomados del
; comportamiento publico documentado (sta.c64.org), no de desensamblado.
; $00 = sin caracter (lo descarta el escaneo, igual que los huecos $FF
; del C64 real, que aqui no se pueden usar como centinela).
KEYTABT:
        .byte $00,$00,$00,$00,$00,$00,$00,$00  ; DEL RET csrLR F7 F1 F3 F5 csrUD
        .byte $1C,$17,$01,$9F,$1A,$13,$05,$00  ; 3 W A 4 Z S E -
        .byte $9C,$12,$04,$1E,$03,$06,$14,$18  ; 5 R D 6 C F T X
        .byte $1F,$19,$07,$9E,$02,$08,$15,$16  ; 7 Y G 8 B H U V
        .byte $12,$09,$0A,$92,$0D,$0B,$0F,$0E  ; 9 I J 0 M K O N
        .byte $00,$10,$0C,$00,$00,$1B,$00,$00  ; + P L - . : @ ,
        .byte $1C,$00,$1D,$00,$00,$1F,$1E,$00  ; libra * ; HOME - = flecha /
        .byte $90,$00,$00,$05,$00,$00,$11,$00  ; 1 <- CTRL 2 SPC C= Q STOP

; tabla C= (Commodore). C=+letra = grafico izquierdo (PETSCII $A1..$BF),
; C=+1..8 = colores claros, y los simbolos @ + libra emiten su grafico.
; El resto no emite nada. Fuente: comportamiento publico (sta.c64.org).
KEYTABC:
        .byte $00,$00,$00,$00,$00,$00,$00,$00  ; DEL RET csrLR F7 F1 F3 F5 csrUD
        .byte $96,$B3,$B0,$97,$AD,$AE,$B1,$00  ; 3 W A 4 Z S E -
        .byte $98,$B2,$AC,$99,$BC,$BB,$A3,$BD  ; 5 R D 6 C F T X
        .byte $9A,$B7,$A5,$9B,$BF,$B4,$B8,$BE  ; 7 Y G 8 B H U V
        .byte $00,$A2,$B5,$00,$A7,$A1,$B9,$AA  ; 9 I J 0 M K O N
        .byte $A6,$AF,$B6,$00,$00,$00,$A4,$00  ; + P L - . : @ ,
        .byte $A8,$00,$00,$00,$00,$00,$00,$00  ; libra * ; HOME - = flecha /
        .byte $81,$00,$00,$95,$00,$00,$AB,$00  ; 1 <- CTRL 2 SPC C= Q STOP

; SHIFT+RUN/STOP: mete "LOAD" + CR + "RUN" + CR en el bufer de teclado,
; replicando el atajo del C64. El LOAD sin argumentos usa el dispositivo
; por defecto (1 = datasette), de ahi la carga de cinta; luego RUN. Son
; 9 bytes, que es lo que cabe en el bufer de 10. Preserva Y (lo usa el
; bucle de escaneo). Derivado del comportamiento, no de la ROM original.
KSRSTUF:
        tya
        pha
        ldx #$00
@cp:    lda KSRTAB,X
        beq @fin
        ldy KNDX
        cpy #10
        bcs @fin
        sta KBUF,Y
        inc KNDX
        inx
        bne @cp
@fin:   pla
        tay
        rts

; KROWP: KVPTR = SCREEN + X*40 (X = fila 0-24). Destruye A y X.
KROWP:  lda #<SCREEN
        sta KVPTR
        lda #>SCREEN
        sta KVPTR+1
@m:     dex
        bmi @r
        clc
        lda KVPTR
        adc #40
        sta KVPTR
        bcc @m
        inc KVPTR+1
        bne @m          ; siempre (el byte alto nunca es 0)
@r:     rts

; escaneo puro de RUN/STOP (sin romper): Z=1 si pulsada. Lo usa el NMI.
; Atomico: el IRQ tambien escanea la matriz; sin SEI, un IRQ entre la
; lectura y el test simula una pulsacion. El resultado viaja en X, que
; el IRQ preserva.
KSTOPRAW:
        php
        sei
        lda #$7F        ; fila 7
        sta $DC00
        lda $DC01
        and #$80        ; bit 7 = RUN/STOP
        tax             ; resultado a X (sobrevive a un IRQ)
        lda #$00
        sta $DC00
        plp
        txa             ; A = resultado, fija Z
        rts             ; Z=1 si pulsada

; ------------------------------------------------------------
; UDTIM: reloj jiffy
; ------------------------------------------------------------
KUDTIM: inc KTIME+2
        bne @r
        inc KTIME+1
        bne @r
        inc KTIME
@r:     rts


FIJA $E9FF
; KCLRLN ($E9FF): borra la fila X (0-24) de la pantalla con espacios y
; pone su RAM de color al color de texto actual. Usa KVPTR.
KCLRLN: jsr KROWP
        ldy #39
        lda #$20
@l1:    sta (KVPTR),Y
        dey
        bpl @l1
        lda KVPTR+1
        clc
        adc #>(COLOR-SCREEN)
        sta KVPTR+1
        ldy #39
        lda KCOLOR
@l2:    sta (KVPTR),Y
        dey
        bpl @l2
        rts

KROWSEL: .byte $FE,$FD,$FB,$F7,$EF,$DF,$BF,$7F

; ------------------------------------------------------------
; STOP: Z=1 si RUN/STOP pulsada
; ------------------------------------------------------------
; ISTOP ($0328/$FFE1) tal como lo espera el BASIC PET: si RUN/STOP esta
; pulsada, rompe la ejecucion saltando a STOP del BASIC (imprime BREAK
; y vuelve a READY). Si no, devuelve con el flag.
KSTOP:  jsr KSTOPRAW
        bne @ret        ; no pulsada: volver con el flag
        lda #$00        ; Z=1 y...
        sec             ; ...C=1 -> STOP imprime "BREAK" y va a READY
        jmp STOP
@ret:   rts

;.org $EA31: manejador principal del IRQ (destino por defecto de $0314).
; Direccion canonica: los programas encadenan su IRQ con JMP $EA31.
.org $EA31
KIRQ:   jsr KUDTIM
        jsr KSCNKEY
        ; --- parpadeo del cursor (solo si se espera entrada) ---
        lda KBLSW
        beq @ack
        dec KBLCNT
        bne @ack
        lda #20
        sta KBLCNT
        ; puntero a la RAM de color de la celda del cursor
        lda KPNT
        sta KCPTR
        lda KPNT+1
        clc
        adc #$D4
        sta KCPTR+1
        ldy KCOL
        lda (KPNT),Y
        eor #$80
        sta (KPNT),Y
        lda KBLON
        bne @apag
        lda (KCPTR),Y   ; encender: guardar el color de la celda...
        sta KGDCOL
        lda KCOLOR      ; ...y poner el color de texto actual
        sta (KCPTR),Y
        lda #$01
        sta KBLON
        bne @ack
@apag:  lda KGDCOL      ; apagar: restaurar el color guardado
        sta (KCPTR),Y
        lda #$00
        sta KBLON
        jmp @ack        ; (entre aqui y $EA7E hay relleno: no caer por el)
; $EA7E: reconocer la interrupcion del CIA1 y salir. Los manejadores de
; raster que no quieren el trabajo del KERNAL terminan con JMP $EA7E.
.org $EA7E
@ack:   lda $DC0D
; $EA81: salida canonica del IRQ (restaurar Y/X/A y RTI). Los programas
; que no quieren el trabajo del KERNAL salen por JMP $EA81.
.org $EA81
@nobl:  pla
        tay
        pla
        tax
        pla
        rti
.org $EA87

; ------------------------------------------------------------
; scroll de una linea hacia arriba
; Los bloques se copian SECUENCIALMENTE y completos: entrelazar
; las paginas con un mismo indice corrompe los 40 bytes que el
; bloque siguiente pisa antes de que el anterior los lea.
; ------------------------------------------------------------
KSCROLL:
        inc KSCRCNT     ; contador global (ajuste del editor)
        ldx #$00
@s1:    lda SCREEN+40,X
        sta SCREEN,X
        inx
        bne @s1
@s2:    lda SCREEN+$100+40,X
        sta SCREEN+$100,X
        inx
        bne @s2
@s3:    lda SCREEN+$200+40,X
        sta SCREEN+$200,X
        inx
        bne @s3
@s4:    lda SCREEN+$300+40,X
        sta SCREEN+$300,X
        inx
        cpx #<(1000-40-$300)
        bne @s4
        ; cursor a inicio de la ultima fila
        lda #<(SCREEN+960)
        sta KPNT
        lda #>(SCREEN+960)
        sta KPNT+1
        ; --- desplazar la RAM de color igual que la pantalla ---
        ldx #$00
@cs1:   lda COLOR+40,X
        sta COLOR,X
        inx
        bne @cs1
@cs2:   lda COLOR+$100+40,X
        sta COLOR+$100,X
        inx
        bne @cs2
@cs3:   lda COLOR+$200+40,X
        sta COLOR+$200,X
        inx
        bne @cs3
@cs4:   lda COLOR+$300+40,X
        sta COLOR+$300,X
        inx
        cpx #<(1000-40-$300)
        bne @cs4
        ldx #24         ; limpiar la ultima fila (espacios y color actual)
        jsr KCLRLN
        ; desplazar la tabla de enlace una fila hacia arriba
        ldx #$00
@shk:   lda KLNK+1,X
        sta KLNK,X
        inx
        cpx #24
        bne @shk
        lda #$80        ; la nueva fila inferior inicia linea (por defecto)
        sta KLNK+24
        lda #24
        sta KROW
        rts




; ¿firma de cartucho "CBM80" en $8004-$8008? Z=1 si esta
KCBMCHK:
        ldx #$04
@c:     lda $8004,X
        cmp KCBMSIG,X
        bne @no
        dex
        bpl @c
        lda #$00        ; Z=1: firma presente
        rts
@no:    lda #$01        ; Z=0
        rts
KCBMSIG: .byte $C3,$C2,$CD,$38,$30  ; "CBM80" en PETSCII

; manejador por defecto del NMI (llega desde $FE47 con A/X/Y ya apilados):
; cartucho primero; si no, RUN/STOP-RESTORE = arranque en caliente
KNMI:   jsr KCBMCHK     ; ¿cartucho CBM80?
        bne @nocart
        jmp ($8002)     ; vector caliente del cartucho
@nocart:
        lda $DD0D       ; reconocer/limpiar la fuente NMI del CIA2
        jsr KSTOPRAW    ; ¿RUN/STOP pulsada? (Z=1 si si) - sin romper
        beq KWARM
        jmp KRTIX       ; NMI espuria: restaurar A/X/Y y volver ($FEBC)
; arranque en caliente: programa intacto, vuelta a READY. Lo usan
; RUN/STOP-RESTORE y el BRK por defecto ($FE66).
KWARM:  ldx #$FF
        txs             ; resetear la pila
        cli
        jsr KRESTOR     ; restaurar vectores de pagina 3
        jmp READY       ; entrada en caliente del BASIC

; --- tabla ROM de vectores por defecto para pagina 3 ---
KVECTAB:
        .word KIRQ      ; $0314 CINV
        .word KBRKDEF   ; $0316 CBINV
        .word KNMIDEF   ; $0318 NMINV
        .word KOPEN     ; $031A IOPEN
        .word KCLOSE    ; $031C ICLOSE
        .word KCHKIN    ; $031E ICHKIN
        .word KCHKOUT   ; $0320 ICKOUT
        .word KCLRCHN   ; $0322 ICLRCH
        .word KCHRIN    ; $0324 IBASIN
        .word KCHROUT   ; $0326 IBSOUT
        .word KSTOP     ; $0328 ISTOP
        .word KGETIN    ; $032A IGETIN
        .word KCLALL    ; $032C ICLALL
        .word KSTUB     ; $032E USRCMD (vector libre, sin uso en C64)
        .word KLOAD     ; $0330 ILOAD
        .word KSAVE     ; $0332 ISAVE
KVECEND:

; VECTOR ($FF8D): C=1 copia los vectores a (X/Y); C=0 los carga desde (X/Y)
KVECTOR:
        stx KVPTR
        sty KVPTR+1
        ldy #(KVECEND-KVECTAB-1)
@v:     bcc @cargar
        lda $0314,Y
        sta (KVPTR),Y
        jmp @sig
@cargar:
        lda (KVPTR),Y
        sta $0314,Y
@sig:   dey
        bpl @v
        rts


KSTUB:  clc
        rts

; READST ($FFB7): devolver el estado de E/S del kernal (ST).
KREADST:lda KSTATUS
        rts

; ------------------------------------------------------------
; Rutinas de la tabla de saltos que no dependen del bus IEC.
; ------------------------------------------------------------
; SETMSG ($FF90): A = flags de mensajes del kernal
KSETMSG:
        sta KMSGFL
        rts
; SETTMO ($FFA2): A = flag de timeout IEEE. Solo lo almacena en KTIMOUT;
; en el C64 de serie lo consulta el cartucho IEEE-488, no el bus serie.
KSETTMO:
        sta KTIMOUT
        rts
; MEMTOP ($FF99): C=1 leer (X/Y), C=0 fijar
KMEMTOP:
        bcc @set
        ldx KMTOP
        ldy KMTOP+1
        rts
@set:   stx KMTOP
        sty KMTOP+1
        rts
; MEMBOT ($FF9C): C=1 leer (X/Y), C=0 fijar
KMEMBOT:
        bcc @set
        ldx KMBOT
        ldy KMBOT+1
        rts
@set:   stx KMBOT
        sty KMBOT+1
        rts
; SCREEN ($FFED): X=columnas, Y=filas
KSCREEN:
        ldx #40
        ldy #25
        rts
; PLOT ($FFF0): C=1 leer (X=fila,Y=col), C=0 fijar
KPLOT:  bcc @set
        ldx KROW
        ldy KCOL
        rts
@set:   stx KROW
        sty KCOL
        jsr KROWP       ; KPNT = SCREEN + fila*40
        lda KVPTR
        sta KPNT
        lda KVPTR+1
        sta KPNT+1
        ldx KROW
        rts
; IOBASE ($FFF3): X/Y = base de E/S (CIA1 = $DC00)
KIOBASE:
        ldx #$00
        ldy #$DC
        rts
; SETTIM ($FFDB): fijar el reloj jiffy (A/X/Y = medio/...)
KSETTIM:
        sei
        sta KTIME+2
        stx KTIME+1
        sty KTIME
        cli
        rts
; RDTIM ($FFDE): leer el reloj jiffy
KRDTIM:
        sei
        lda KTIME+2
        ldx KTIME+1
        ldy KTIME
        cli
        rts
; CLRCHN ($FFCC): canales de E/S a por defecto (teclado in, pantalla out)
KCLRCHN:
        lda KDFLTN
        cmp #$04
        bcc @noin
        jsr KUNTLK      ; cerrar el talker serie
@noin:  lda KDFLTO
        cmp #$04
        bcc @noout
        jsr KUNLSN      ; cerrar el listener serie
@noout: lda #$00
        sta KDFLTN      ; dispositivo de entrada = 0 (teclado)
        lda #$03
        sta KDFLTO      ; dispositivo de salida = 3 (pantalla)
        clc
        rts
; CLALL ($FFE7): cerrar todos los ficheros y resetear canales
KCLALL:
        lda #$00
        sta KLDTND      ; numero de ficheros abiertos = 0
        jmp KCLRCHN

; ============================================================
; Bus serie IEC (fase 2b). Protocolo desde especificacion publica
; (Butterfield / Programmer's Reference), NUNCA desde el desensamblado
; de las rutinas serie de Commodore. Polaridad medida empiricamente:
;   OUT (bits 3/4/5 ATN/CLK/DATA): 1 = tirar la linea a BAJO (asertar)
;   IN  (bits 6/7 CLK/DATA): 1 = ALTA (liberada), 0 = BAJA (asertada)
; ============================================================
SERPRT  = $DD00
B_ATN   = $08
B_CLK   = $10
B_DATA  = $20
B_CLKIN = $40
B_DATIN = $80

KCLKLO: lda SERPRT
        ora #B_CLK
        sta SERPRT
        rts
KCLKHI: lda SERPRT
        and #($FF - B_CLK)
        sta SERPRT
        rts
KDATLO: lda SERPRT
        ora #B_DATA
        sta SERPRT
        rts
KDATHI: lda SERPRT
        and #($FF - B_DATA)
        sta SERPRT
        rts
KATNLO: lda SERPRT
        ora #B_ATN
        sta SERPRT
        rts
KATNHI: lda SERPRT
        and #($FF - B_ATN)
        sta SERPRT
        rts

; LISTEN ($FFB1): A = dispositivo
KLISTN: ora #$20
KLSTN2: pha
        jsr KATNLO
        jsr KCLKLO
        jsr KDATHI
        jsr KATNDLY     ; dar tiempo a los dispositivos a responder a ATN
        ; chequeo de presencia: un dispositivo presente asierta DATA (bajo) como
        ; ack de ATN. DATA alto tras el settle = no hay dispositivo.
        lda SERPRT
        and #B_DATIN
        beq @present
        lda KSTATUS
        ora #$80        ; bit7: dispositivo no presente
        sta KSTATUS
@present:
        pla
        sec
        ror KATNF       ; modo ATN
        jmp KISEND

; TALK ($FFB4): A = dispositivo
KTALK:  ora #$40
        jmp KLSTN2

; SECOND ($FF93): A = secundaria tras LISTEN
KSECND: sec
        ror KATNF
        jsr KISEND
        jsr KATNHI      ; liberar ATN: empieza la fase de datos
        rts

; retardo de respuesta a ATN (~1ms)
KATNDLY:txa
        pha
        tya
        pha
        ldx #$04
@o:     ldy #$00
@i:     dey
        bne @i
        dex
        bne @o
        pla
        tay
        pla
        tax
        rts

; TKSA ($FF96): A = secundaria tras TALK, con turnaround talker->oyente
KTKSA:  sec
        ror KATNF
        jsr KISEND
        jsr KDATLO      ; somos oyentes: asertar DATA
        jsr KATNHI      ; liberar ATN
        jsr KCLKHI      ; liberar CLOCK
        ldx #$00
        ldy #$00
@tw:    lda SERPRT
        and #B_CLKIN
        beq @twok       ; CLK bajo -> la unidad habla
        iny
        bne @tw
        inx
        bne @tw
        lda #$80        ; timeout: dispositivo no presente
        sta KSTATUS
@twok:  rts

; CIOUT ($FFA8): A = byte de datos (envio diferido para el EOI)
KCIOUT: bit KC3PO
        bmi @send
        sec
        ror KC3PO       ; marcar pendiente
        jmp @store
@send:  pha
        lda KBSOUR
        clc
        ror KATNF       ; modo datos (bit7=0)
        jsr KISEND
        pla
@store: sta KBSOUR
        rts

; UNLSN ($FFAE): enviar el ultimo byte con EOI y luego UNLISTEN
KUNLSN: jsr KISCLR
        lda KSTATUS
        pha             ; preservar el estado real de la transferencia
        sec
        ror KATNF
        jsr KATNLO
        jsr KCLKLO      ; CLOCK asertado durante ATN
        jsr KATNDLY     ; dar tiempo al dispositivo a responder a la re-asercion de ATN
        lda #$3F        ; recargar aqui: KATNLO/KCLKLO/KATNDLY destruyen A
        jsr KISEND      ; byte de liberacion: su handshake no es fiable ni relevante
        pla
        sta KSTATUS     ; restaurar (el dispositivo libera el bus, no hace ack)
        jmp KATNFIN
; UNTLK ($FFAB): UNTALK
KUNTLK: lda KSTATUS
        pha
        sec
        ror KATNF
        jsr KATNLO
        jsr KCLKLO      ; CLOCK asertado durante ATN
        jsr KATNDLY     ; settle de ATN
        lda #$5F
        jsr KISEND
        pla
        sta KSTATUS
KATNFIN:jsr KATNHI
        jsr KCLKHI
        rts

; KISCLR: si hay byte pendiente, enviarlo con EOI
KISCLR: bit KC3PO
        bpl @no
        sec
        ror KEOIF       ; senalar EOI en este ultimo byte
        lda KBSOUR
        clc
        ror KATNF
        jsr KISEND
        lsr KC3PO
@no:    rts

; KISEND: enviar un byte (A). KATNF bit7=ATN, KEOIF bit7=EOI.
; C=1 si timeout (dispositivo no presente).
KISEND: sta KBSOUR2
        sei             ; el timing serie no tolera interrupciones
        jsr KDATHI      ; liberar NUESTRA DATA (la posee el oyente)
        jsr KCLKHI      ; liberar CLOCK = "emisor listo para enviar" (RTS)
        ; esperar a que el oyente libere DATA (alto) = "listo para datos" (RFD).
        ; timeout 16 bits: el dispositivo puede tardar en responder tras ATN.
        ldx #$00
        ldy #$00
        lda #$00
        sta KSERHI      ; byte alto de cuenta (timeout RFD extendido)
@wr:    lda SERPRT
        and #B_DATIN
        bne @ready      ; DATA alto -> oyente listo
        iny
        bne @wr
        inx
        bne @wr
        inc KSERHI
        lda KSERHI
        cmp #$40        ; ~58ms: un 1541 con fichero abierto tarda en hacer RFD
        bne @wr
        jmp @tmout      ; timeout RFD
@ready: bit KEOIF       ; CLOCK ya esta alto desde RTS
        bmi @iseoi
        ; No-EOI: dar tiempo al oyente a entrar en su bucle de recepcion antes
        ; de bajar CLOCK. Si se baja demasiado pronto el 1541 pierde la
        ; transicion y, al expirar su Tne, lo interpreta como EOI (desincronia).
        jsr KSDLY
        jmp @noeoi
@iseoi: ; EOI: esperar el ack del oyente (DATA bajo y luego alto), con timeout
        ldx #$00
        ldy #$00
@e1:    lda SERPRT
        and #B_DATIN
        beq @e1b        ; DATA bajo -> ack EOI recibido
        iny
        bne @e1
        inx
        bne @e1
        jmp @toeoi      ; timeout EOI
@e1b:   ldx #$00
        ldy #$00
@e2:    lda SERPRT
        and #B_DATIN
        bne @noeoi      ; DATA alto otra vez -> seguir
        iny
        bne @e2
        inx
        bne @e2
@toeoi: jmp @tmout       ; timeout de ack de EOI
; timeout de handshake: bajo ATN = dispositivo no presente (ST bit7);
; en fase de datos = timeout de escritura (ST bit1).
@tmout: lda KATNF
        bmi @tmndp
        lda KSTATUS
        ora #$02        ; bit1: timeout de escritura
        jmp @tmend
@tmndp: lda KSTATUS
        ora #$80        ; bit7: dispositivo no presente
@tmend: sta KSTATUS
        cli
        sec
        rts
@noeoi: jsr KCLKLO
        lda #$08
        sta KBITCNT
@bit:   lda KBSOUR2
        lsr
        sta KBSOUR2
        bcs @one
        jsr KDATLO
        jmp @clk
@one:   jsr KDATHI
@clk:   jsr KCLKHI
        jsr KSDLY
        jsr KCLKLO
        jsr KDATHI
        dec KBITCNT
        bne @bit
        ldx #$00
        ldy #$00
@fr:    lda SERPRT
        and #B_DATIN
        beq @ok
        iny
        bne @fr
        inx
        bne @fr
        jmp @tmout      ; timeout de frame-ack
@ok:    lsr KEOIF
        cli
        clc
        rts

KSERIN: txa
        pha
        tya
        pha
        jsr KACPTR
        sta KSERT       ; (no KTMP3: la usa el IRQ del teclado)
        pla
        tay
        pla
        tax
        lda KSERT
        clc
        rts

KSDLY:  txa
        pha
        ldx #$0A
@d:     dex
        bne @d
        pla
        tax
        rts

; ACPTR ($FFA5): recibir un byte del talker. Espejo de KISEND.
; Dato valido con CLOCK alto. EOI -> bit6 de KSTATUS. C=1 si timeout.
; Estado de entrada (tras TKSA): oyente con DATA bajo, talker con CLOCK bajo.
KACPTR: sei
        ; 1) Esperar CLOCK alto (talker suelta CLOCK = RTS). El talker lo
        ;    mantiene alto hasta ver nuestro RFD, asi que es estable.
        lda #$00
        sta KSERHI
        ldx #$00
        ldy #$00
@w1:    lda SERPRT
        and #B_CLKIN
        bne @rfd            ; CLOCK alto -> el talker esta listo
        iny
        bne @w1
        inx
        bne @w1
        inc KSERHI
        lda KSERHI
        cmp #$40            ; ~58ms: el 1541 puede tardar en preparar el byte
        bne @w1
        jmp @to             ; dispositivo no presente
@rfd:   jsr KDATHI          ; soltar DATA = RFD (listo para datos)
        ; 2) Esperar CLOCK bajo (el talker baja CLOCK para empezar los bits).
        ;    Si retiene CLOCK alto mas de ~256us -> EOI (ultimo byte).
        ldx #$00
        ldy #$00
@w2:    lda SERPRT
        and #B_CLKIN
        beq @rdy            ; CLOCK bajo -> vienen bits
        iny
        bne @w2
        inx
        bne @w2
        ; --- EOI: el talker retiene CLOCK = ultimo byte ---
        lda KSTATUS
        ora #$40
        sta KSTATUS         ; senalar EOI
        jsr KDATLO          ; pulso de reconocimiento de EOI (~60us)
        ldx #$20
@eod:   dex
        bne @eod
        jsr KDATHI
        lda #$00
        sta KSERHI
        ldx #$00
        ldy #$00
@w2b:   lda SERPRT          ; ahora si, esperar CLOCK bajo (empiezan los bits)
        and #B_CLKIN
        beq @rdy
        iny
        bne @w2b
        inx
        bne @w2b
        inc KSERHI
        lda KSERHI
        cmp #$40            ; ~58ms sin byte tras EOI = fin real (mas alla del ultimo)
        bne @w2b
        lda #$00            ; sin byte valido; KSTATUS ya tiene bit6 (EOI)
        cli
        sec
        rts
@rdy:   lda #$08
        sta KBITCNT
        ; 3) Bucle de bits: esperar CLOCK alto, muestrear DATA (ventana valida),
        ;    luego esperar CLOCK bajo (fin de bit). LSB primero.
@bit:   ldx #$00
        ldy #$00
@bhi:   lda SERPRT
        asl                 ; C = DATA (bit7), N = CLOCK (bit6)
        bmi @smp            ; CLOCK alto -> muestrear ahora (C = DATA)
        iny
        bne @bhi
        inx
        bne @bhi
        jmp @to
@smp:   ror KBSOUR2         ; meter el bit DATA (C ya = DATA), LSB primero
        ldx #$00
        ldy #$00
@blo:   lda SERPRT
        and #B_CLKIN
        beq @nxt            ; CLOCK bajo -> fin de bit
        iny
        bne @blo
        inx
        bne @blo
        jmp @to
@nxt:   dec KBITCNT
        bne @bit
        jsr KDATLO          ; reconocer byte recibido (DATA bajo)
        lda KBSOUR2
        cli
        clc
        rts
@to:    lda #$80
        sta KSTATUS         ; timeout: dispositivo no presente
        cli
        sec
        rts


; ------------------------------------------------------------
; Andamiaje de E/S (fase 1 IEC): gestion de estado, sin bus todavia.
; ------------------------------------------------------------
; SETNAM ($FFBD): A=longitud, X/Y=direccion del nombre
KSETNAM:
        sta KFNLEN
        stx KFNADR
        sty KFNADR+1
        rts
; SETLFS ($FFBA): A=fichero logico, X=dispositivo, Y=direccion secundaria
KSETLFS:
        sta KLA
        stx KFA
        sty KSA
        rts
; buscar el fichero logico A en la tabla LAT; C=1 y X=indice si esta,
; C=0 si no esta
KFINDFL:
        ldx KLDTND
@l:     dex
        bmi @no
        cmp KLAT,X
        bne @l
        sec
        rts
@no:    clc
        rts
; OPEN ($FFC0): registrar el fichero logico en las tablas
KOPEN:  lda KLA
        bne @ok0
        lda #$06        ; error 6: fichero logico 0 no permitido
        sec
        rts
@ok0:   jsr KFINDFL     ; ¿ya abierto?
        bcc @nuevo
        lda #$02        ; error 2: fichero ya abierto
        sec
        rts
@nuevo: ldx KLDTND
        cpx #10
        bcc @add
        lda #$01        ; error 1: demasiados ficheros
        sec
        rts
@add:   lda KLA
        sta KLAT,X
        lda KFA
        sta KFAT,X
        lda KSA
        sta KSAT,X
        inc KLDTND
        ; --- si es dispositivo serie (>=4), abrir el canal por el bus ---
        lda KFA
        cmp #$04
        bcc @done
        lda #$00
        sta KSTATUS     ; estado limpio al iniciar la transaccion serie
        lda KFA
        jsr KLISTN
        lda KSA
        ora #$F0        ; OPEN + canal
        jsr KSECND
        ldy #$00
@nm:    cpy KFNLEN
        beq @nmend
        tya
        pha             ; guardar el indice (KISEND destruye Y)
        lda (KFNADR),Y
        jsr KCIOUT
        pla
        tay             ; restaurar el indice
        iny
        bne @nm
@nmend: jsr KUNLSN
        lda KSTATUS
        bpl @done       ; bit7 claro: dispositivo respondio
        dec KLDTND      ; no presente: quitar la entrada de fichero recien anadida
        lda #$05        ; error 5: DEVICE NOT PRESENT
        sec
        rts
@done:  clc
        rts
; CLOSE ($FFC3): A = fichero logico a cerrar
KCLOSE: pha             ; guardar num de fichero logico
        jsr KFINDFL
        bcs @hay
        pla
        clc             ; no abierto: nada que hacer
        rts
@hay:   ; X = indice. Si el dispositivo es serie, enviar CLOSE de canal.
        lda KFAT,X
        cmp #$04
        bcc @noser
        lda KSAT,X      ; leer secundaria ANTES (las rutinas serie destruyen X)
        ora #$E0        ; comando CLOSE de canal
        pha
        lda KFAT,X
        jsr KLISTN
        pla
        jsr KSECND
        jsr KUNLSN
@noser: pla             ; recuperar num de fichero logico
        jsr KFINDFL     ; recomputar X (KLISTN/KSECND/KUNLSN destruyen X)
        bcc @nada
        ; compactar las tablas desde X
        ldy KLDTND
        dey
@comp:  cpx KLDTND
        bcs @fin
        cpx #9
        bcs @ult
        lda KLAT+1,X
        sta KLAT,X
        lda KFAT+1,X
        sta KFAT,X
        lda KSAT+1,X
        sta KSAT,X
@ult:   inx
        cpx KLDTND
        bcc @comp
@fin:   dec KLDTND
@nada:  clc
        rts
; CHKIN ($FFC6): X = fichero logico -> canal de entrada
KCHKIN: txa
        jsr KFINDFL
        bcs @hay
        lda #$03        ; error 3: fichero no abierto
        sec
        rts
@hay:   lda KFAT,X
        sta KDFLTN      ; dispositivo de entrada = el del fichero
        cmp #$04
        bcc @done       ; no serie: listo
        lda KSAT,X      ; leer secundaria ANTES (KTALK->KISEND destruye X)
        ora #$60        ; secundaria de TALK
        pha
        lda KFAT,X
        jsr KTALK       ; A = dispositivo -> TALK
        pla
        jsr KTKSA
@done:  clc
        rts
; CHKOUT ($FFC9): X = fichero logico -> canal de salida
KCHKOUT: txa
        jsr KFINDFL
        bcs @hay
        lda #$03
        sec
        rts
@hay:   lda KFAT,X
        sta KDFLTO      ; dispositivo de salida = el del fichero
        cmp #$04
        bcc @done       ; no serie: listo
        lda KSAT,X      ; leer secundaria ANTES (KLISTN->KISEND destruye X)
        ora #$60        ; secundaria de LISTEN (canal de datos)
        pha
        lda KFAT,X
        jsr KLISTN      ; A = dispositivo -> LISTEN
        pla
        jsr KSECND
@done:  clc
        rts

; ------------------------------------------------------------
; Parsers del lado BASIC para OPEN y CLOSE (el MS puro no los trae;
; Commodore los anadio). Usan los helpers del BASIC (GETBYT/COMBYT/
; CHKCOM/FRMEVL/FRESTR) y nuestras primitivas del kernal.
; ------------------------------------------------------------
; OPEN lfn [,dispositivo [,secundaria [,"nombre"]]]
BOPEN:  lda #$01
        sta KFA         ; dispositivo por defecto = 1 (cinta)
        lda #$00
        sta KSA         ; secundaria por defecto = 0
        sta KFNLEN      ; sin nombre
        jsr GETBYT      ; fichero logico -> X (flags sobre el terminador)
        stx KLA
        beq @go
        jsr COMBYT      ; ,dispositivo -> X
        stx KFA
        beq @go
        jsr COMBYT      ; ,secundaria -> X
        stx KSA
        beq @go
        jsr CHKCOM      ; coma antes del nombre
        jsr FRMEVL      ; evaluar la cadena del nombre
        jsr FRESTR      ; A=longitud, X=lo, Y=hi
        sta KFNLEN
        stx KFNADR
        sty KFNADR+1
@go:    jsr $FFC0       ; OPEN via vector IOPEN (interceptable)
        bcs @err
        rts
@err:   jmp KIOERR      ; A = codigo de error del kernal -> mensaje largo
; CLOSE lfn
BCLOSE: jsr GETBYT      ; fichero logico -> X
        txa
        jsr $FFC3       ; CLOSE via vector ICLOSE (interceptable)
        rts

; ------------------------------------------------------------
; Parsers del lado BASIC para LOAD y SAVE. Igual que OPEN, el MS los
; despacha crudos al kernal sin parsear. Parsean ["nombre"][,disp][,sec]
; y dejan el estado listo (SETNAM/SETLFS). La transferencia por el bus
; (handshake) se engancha en @bus cuando exista.
; ------------------------------------------------------------
; comun: parsea [nombre][,dispositivo][,secundaria] en KFNLEN/KFA/KSA
BPARSE: lda #$01
        sta KFA         ; dispositivo por defecto = 1 (cinta)
        lda #$00
        sta KSA
        sta KFNLEN      ; sin nombre
        sta KLA         ; LOAD/SAVE usan fichero logico 0
        jsr CHRGOT      ; ¿hay argumentos?
        beq @fin
        jsr FRMEVL      ; evaluar la cadena del nombre
        jsr FRESTR      ; A=longitud, X=lo, Y=hi
        sta KFNLEN
        stx KFNADR
        sty KFNADR+1
        jsr CHRGOT
        beq @fin
        jsr COMBYT      ; ,dispositivo -> X
        stx KFA
        jsr CHRGOT
        beq @fin
        jsr COMBYT      ; ,secundaria -> X
        stx KSA
@fin:   rts
; LOAD ["nombre"][,dispositivo][,secundaria]
BLOAD:  jsr BPARSE
        jsr KDIRMSG     ; mensajes de control segun modo directo/programa
        lda #$00        ; 0 = LOAD (1 seria VERIFY)
        sta KVERCK
        ldx TXTTAB      ; destino por defecto (SA=0) = inicio del programa BASIC
        ldy TXTTAB+1
        jsr $FFD5       ; LOAD via vector ILOAD (interceptable)
        bcc @lok
        jmp KIOERR      ; error de E/S
@lok:   ; si SA=0 (programa BASIC), fijar VARTAB=fin y reenlazar
        lda KSA
        bne @lret
        stx VARTAB      ; X/Y = fin+1 devuelto por KLOAD
        sty VARTAB+1
        ; Guarda: si la carga relocalizada dejo menos de 2 bytes (longitud =
        ; VARTAB-TXTTAB < 2), el area de programa puede no tener un terminador
        ; $00 $00 fiable en TXTTAB y LNKPRG/CHEAD recorreria memoria rancia
        ; (cuelgue al editar la primera linea). En ese caso forzar un programa
        ; BASIC vacio y bien formado: TXTTAB = $00 $00, VARTAB = TXTTAB+2.
        sec
        lda VARTAB
        sbc TXTTAB
        tax             ; X = longitud (byte bajo)
        lda VARTAB+1
        sbc TXTTAB+1
        bne @relink     ; longitud >= 256: carga valida
        cpx #2
        bcs @relink     ; longitud >= 2: carga valida
        lda #$00        ; longitud < 2: vaciar de forma limpia
        ldy #$00
        sta (TXTTAB),y
        iny
        sta (TXTTAB),y
        lda TXTTAB
        clc
        adc #2
        sta VARTAB
        lda TXTTAB+1
        adc #0
        sta VARTAB+1
@relink:
        jsr LNKPRG      ; reenlazar los punteros de linea del BASIC
        ; Comportamiento dependiente del modo (interfaz observable, spec
        ; publica del LOAD: nivel B):
        ;  - DIRECTO (CURLIN+1=$FF): CLR de punteros (ARYTAB=STREND=VARTAB,
        ;    FRETOP=MEMSIZ). Sin esto quedan obsoletos y al crear la 1a
        ;    variable tras el LOAD se corrompe el programa. No se toca la
        ;    pila (a diferencia de CLEARC/STKINI). Vuelve a READY.
        ;  - PROGRAMA (LOAD encadenado): NO se borran variables (el
        ;    encadenado pasa datos entre partes), se reapunta el texto al
        ;    inicio del programa cargado y se RE-EJECUTA desde la primera
        ;    linea. Se repone la pila a la base (STKINI) para no acumular
        ;    marcos entre saltos de cadena. No se vuelve aqui.
        lda CURLIN+1
        cmp #$FF
        bne @prog
        ; --- modo directo: CLR de punteros ---
        ldx VARTAB
        ldy VARTAB+1
        stx ARYTAB
        sty ARYTAB+1
        stx STREND
        sty STREND+1
        lda MEMSIZ
        sta FRETOP
        lda MEMSIZ+1
        sta FRETOP+1
@lret:  rts
        ; --- modo programa: re-RUN encadenado, sin borrar variables ---
@prog:  jsr STXTPT      ; TXTPTR = TXTTAB-1 (antes de la 1a linea)
        jsr STKINI      ; pila a la base, prohibe CONT; NO toca variables
        jmp NEWSTT      ; ejecutar desde la primera linea del nuevo programa
; SAVE ["nombre"][,dispositivo][,secundaria]
BSAVE:  jsr BPARSE
        jsr KDIRMSG     ; mensajes de control segun modo directo/programa
        lda TXTTAB      ; inicio del programa
        sta KLDTMP
        lda TXTTAB+1
        sta KLDTMP+1
        lda VARTAB      ; fin+1 del programa
        tax
        lda VARTAB+1
        tay
        lda #KLDTMP     ; A = indice ZP del puntero de inicio
        jsr $FFD8       ; SAVE via vector ISAVE (interceptable)
        bcc @sret
        jmp KIOERR
@sret:  rts
; VERIFY ["nombre"][,dispositivo][,secundaria]: como LOAD pero compara.
BVERIFY:jsr BPARSE
        jsr KDIRMSG     ; mensajes de control segun modo directo/programa
        lda #$01
        sta KVERCK
        ldx TXTTAB
        ldy TXTTAB+1
        jsr $FFD5       ; LOAD/VERIFY via vector ILOAD (interceptable)
        bcc @vok
        jmp KIOERR
@vok:   lda KSTATUS
        and #$10            ; bit4 = discrepancia
        bne @verr
        bit KMSGFL
        bpl @vr             ; en programa: sin mensaje
        lda #<KVOK
        ldy #>KVOK
        jmp STROUT          ; modo directo: "OK"
@vr:    rts
@verr:  jsr KCLRCHN
        jsr CRDO
        jsr OUTQST          ; "?"
        lda #<KVMSG
        ldy #>KVMSG
        jsr STROUT
        jmp TYPERR          ; " ERROR" + linea + READY

; ------------------------------------------------------------
; LOAD ($FFD5): A=0 carga / 1 verifica; X/Y = destino si SA=0.
; Lee del dispositivo serie a memoria. Los 2 primeros bytes del fichero
; son su direccion de carga: si SA=0 se relocaliza a X/Y, si SA<>0 se usa
; la del fichero. Devuelve X/Y = fin+1; C=1 y A=codigo si error.
; ------------------------------------------------------------
KLOAD:  sta KVERCK
        stx KLDPTR
        sty KLDPTR+1
        lda KFA
        cmp #$04
        bcs @ser
        lda KFA
        cmp #$01
        bne @notape
        jmp tape_load       ; dispositivo 1 = cinta (devuelve clc/sec + X/Y o A)
@notape:
        lda #$09            ; otros dispositivos no-serie: no soportados
        sec
        rts
@ser:   lda #$00
        sta KSTATUS
        jsr KSRCHMSG        ; "SEARCHING FOR <nombre>" si los mensajes ON
        ; 1) enviar el nombre por el canal de OPEN (secundaria $F0|SA)
        lda KFA
        jsr KLISTN
        lda #$F0            ; LOAD usa siempre el canal 0 (OPEN)
        jsr KSECND
        ldy #$00
@nm:    cpy KFNLEN
        beq @nmend
        tya
        pha
        lda (KFNADR),Y
        jsr KCIOUT
        pla
        tay
        iny
        bne @nm
@nmend: jsr KUNLSN
        jsr KLDGMSG         ; "LOADING" / "VERIFYING" si los mensajes ON
        ; 2) TALK + TKSA ($60) para leer
        lda KFA
        jsr KTALK
        lda #$60            ; canal 0
        jsr KTKSA
        lda KSTATUS
        and #$80            ; ¿dispositivo no presente?
        beq @addr
        jsr KUNTLK
        lda #$05            ; error 5: dispositivo no presente
        sec
        rts
@addr:  ; leer la direccion de carga del fichero (2 bytes)
        jsr KACPTR
        sta KLDTMP
        jsr KACPTR          ; A = byte alto
        ldx KSA
        beq @loop           ; SA=0 -> relocalizar a KLDPTR (X/Y de entrada)
        sta KLDPTR+1        ; SA<>0 -> usar la direccion del fichero
        lda KLDTMP
        sta KLDPTR
@loop:  lda KSTATUS
        and #$40            ; EOI ya en la direccion (fichero vacio)
        bne @eof
@rd:    jsr KACPTR
        ldy KVERCK
        bne @vrf
        ldy #$00
        sta (KLDPTR),Y
        jmp @next
@vrf:   ldy #$00
        cmp (KLDPTR),Y
        beq @next
        lda KSTATUS
        ora #$10            ; bit4: error de verificacion
        sta KSTATUS
@next:  inc KLDPTR
        bne @nc
        inc KLDPTR+1
@nc:    lda KSTATUS
        and #$40            ; EOI -> el byte ya almacenado era el ultimo
        beq @rd
@eof:   jsr KUNTLK
        ldx KLDPTR          ; devolver fin+1 en X/Y
        ldy KLDPTR+1
        clc
        rts

; ------------------------------------------------------------
; SAVE ($FFD8): A = indice ZP del puntero de inicio; X/Y = fin+1.
; Guarda memoria [inicio..fin) al dispositivo serie como fichero PRG.
; ------------------------------------------------------------
KSAVE:  stx KLDPTR          ; fin+1
        sty KLDPTR+1
        tax                 ; X = indice ZP del puntero de inicio
        lda $00,X
        sta KSAVPTR
        lda $01,X
        sta KSAVPTR+1
        lda KFA
        cmp #$04
        bcs @ser
        cmp #$01
        beq @tape           ; dispositivo 1 = cinta
        lda #$09            ; otros dispositivos < 4: no soportado
        sec
        rts
@tape:  jmp tape_save       ; KSAVPTR=inicio, KLDPTR=fin+1, nombre via SETNAM
@ser:   lda #$00
        sta KSTATUS
        jsr KSAVMSG         ; "SAVING <nombre>" si los mensajes ON
        ; 1) enviar el nombre (canal OPEN, secundaria $F0|SA)
        lda KFA
        jsr KLISTN
        lda #$F1            ; SAVE usa el canal 1 (OPEN)
        jsr KSECND
        ldy #$00
@nm:    cpy KFNLEN
        beq @nmend
        tya
        pha
        lda (KFNADR),Y
        jsr KCIOUT
        pla
        tay
        iny
        bne @nm
@nmend: jsr KUNLSN
        lda KSTATUS
        and #$80            ; ¿dispositivo no presente?
        beq @datch
        lda #$05            ; error 5: DEVICE NOT PRESENT
        sec
        rts
@datch: ; 2) abrir canal de datos: LISTEN + SECOND ($61)
        lda KFA
        jsr KLISTN
        lda #$61            ; canal 1 (datos de SAVE)
        jsr KSECND
        ; enviar la direccion de inicio (2 bytes, lo/hi)
        lda KSAVPTR
        jsr KCIOUT
        lda KSAVPTR+1
        jsr KCIOUT
        ; enviar bytes de datos [inicio..fin)
@sv:    lda KSAVPTR
        cmp KLDPTR
        lda KSAVPTR+1
        sbc KLDPTR+1
        bcs @svend          ; KSAVPTR >= fin -> terminar
        ldy #$00
        lda (KSAVPTR),Y
        jsr KCIOUT
        inc KSAVPTR
        bne @sv
        inc KSAVPTR+1
        jmp @sv
@svend: jsr KUNLSN          ; flush del ultimo byte con EOI + UNLISTEN
        ; cerrar el canal: LISTEN + SECOND ($E1) + UNLISTEN
        lda KFA
        jsr KLISTN
        lda #$E1            ; CLOSE del canal 1
        jsr KSECND
        jsr KUNLSN
        clc
        rts

; ------------------------------------------------------------
; Mensajes de control de LOAD/SAVE (estilo Commodore). Solo se imprimen
; si el bit7 de KMSGFL ($9D) esta activo (modo directo lo activa; un
; programa lo limpia, asi un cargador carga en silencio). Nivel A/B:
; texto observable reimplementado desde especificacion publica.
; ------------------------------------------------------------
KSRCHMSG:                   ; "SEARCHING FOR <nombre>" (o "SEARCHING")
        bit KMSGFL
        bpl @rts
        lda KFNLEN
        bne @named
        lda #<MSRCH0
        ldy #>MSRCH0
        jmp STROUT
@named: lda #<MSRCH
        ldy #>MSRCH
        jsr STROUT
        jmp KPRNAM
@rts:   rts
KLDGMSG:                    ; "LOADING" / "VERIFYING"
        bit KMSGFL
        bpl @rts2
        lda KVERCK
        bne @ver
        lda #<MLOAD
        ldy #>MLOAD
        jmp STROUT
@ver:   lda #<MVERIF
        ldy #>MVERIF
        jmp STROUT
@rts2:  rts
KSAVMSG:                    ; "SAVING <nombre>"
        bit KMSGFL
        bpl @rts3
        lda #<MSAVE
        ldy #>MSAVE
        jsr STROUT
        jmp KPRNAM
@rts3:  rts
KPRNAM:                     ; imprime KFNLEN bytes del nombre desde KFNADR
        ldy #$00
@l:     cpy KFNLEN
        beq @d
        lda (KFNADR),Y
        jsr KCHROUT
        iny
        bne @l
@d:     rts
MSRCH:  .byte $0D,"SEARCHING FOR ",0
MSRCH0: .byte $0D,"SEARCHING",0
MLOAD:  .byte $0D,"LOADING",0
MVERIF: .byte $0D,"VERIFYING",0
MSAVE:  .byte $0D,"SAVING ",0
; fija KMSGFL segun el modo: bit7 si modo directo (CURLIN+1=$FF), si no 0.
KDIRMSG:lda #$00
        ldy CURLIN+1
        iny                 ; $FF -> $00
        bne @s              ; no es directo (programa) -> mensajes OFF
        lda #$80            ; directo -> mensajes de control ON
@s:     sta KMSGFL
        rts
; y reengancha con la limpieza de error del BASIC. A = codigo (1-9).
; Los mensajes viven aqui, en el KERNAL, porque la ROM del BASIC esta
; llena. Texto en ingles descriptivo (interfaz observable, nivel A/B).
; ------------------------------------------------------------
KIOERR: cmp #$01
        bcs @ok
        lda #$01
@ok:    cmp #$0A
        bcc @ok2
        lda #$01
@ok2:   pha
        jsr KCLRCHN     ; cerrar canales como hace ERROR
        jsr CRDO        ; CRLF
        jsr OUTQST      ; "?"
        pla
        sec
        sbc #$01        ; codigo 1..9 -> indice 0..8
        asl             ; *2 (tabla de punteros)
        tax
        lda KIOMSG,X
        ldy KIOMSG+1,X
        jsr STROUT      ; imprimir el mensaje (sin " ERROR")
        jmp TYPERR      ; " ERROR" + numero de linea + READY
KIOM2:  .byte "FILE OPEN",0


; ------------------------------------------------------------
; SYS (delta C64): evalua la expresion con las rutinas del BASIC
; y salta a la direccion; un RTS alli devuelve al BASIC.
; ------------------------------------------------------------
KSYS:   jsr FRMNUM      ; evaluar la expresion tras SYS
        jsr GETADR      ; convertir a entero en POKER
        jmp (POKER)     ; el RTS del usuario vuelve a NEWSTT

; ------------------------------------------------------------
; KERRMSG (delta C64): imprime el mensaje LARGO de error del BASIC.
; El BASIC entra con X = indice de byte en ERRTAB (0,2,4,... ,34),
; que es el mismo indice valido para KERRTAB. Imprime via STROUT y
; vuelve (el BASIC sigue en TYPERR con " ERROR" + numero de linea).
; Los textos (interfaz observable, nivel B) viven aqui porque la ROM
; del BASIC esta llena; el orden coincide con ERRTAB en basic_cbm.s.
; ------------------------------------------------------------
KERRMSG:lda KERRTAB,X
        ldy KERRTAB+1,X
        jmp STROUT      ; imprime el mensaje y RTS
KERA02: .byte "SYNTAX",0
KERA06: .byte "OUT OF DATA",0
KERA10: .byte "OVERFLOW",0
KERA24: .byte "TYPE MISMATCH",0
KERA28: .byte "FILE DATA",0

; ============================================================
; CINTA (datasette): carga por dispositivo 1. Decode clean-room
; verificado (timer B del CIA1 + FLAG). Manejador en CINV.
; Variables: punteros en ZP libre; estado en el buffer de cinta.
; ============================================================
; --- punteros (direccionamiento indirecto): ZP libre del KERNAL ---
dest=$A8
dbase=$AA
; --- estado en RAM absoluta (buffer de cinta $033C-$03FB) ---
cur_lo=$0340
cur_hi=$0341
last_lo=$0342
last_hi=$0343
dlo=$0344
dhi=$0345
tcls=$0346
phase=$0347
p1=$0348
state=$0349
bitcnt=$034A
curbyte=$034B
parity=$034C
bitval=$034D
primed=$034E
bstate=$034F
syncn=$0350
chk=$0351
ncopy=$0352
tstore=$0353
blkstat=$0354
dcnt=$0355
maxst=$0357
got=$0359
phase_=$035A
startlo=$035B
starthi=$035C
endlo=$035D
endhi=$035E
loaddn=$035F
ftype=$0360
bval=$0361
tsav=$033C
tstop=$033E         ; bandera de abort por RUN/STOP durante la carga
dcstopc=$033F       ; contador para throttle del sondeo de STOP
tverify=$0377       ; VERIFY real guardado (la cabecera se almacena siempre)
bderr=$0378         ; el byte actual tuvo error de paridad (1) o no (0)
expchk=$0379        ; checksum esperado del bloque (de una copia con paridad buena)
expchkok=$037A      ; expchk capturado (1) o no (0)
mcnt=$037B          ; contador scratch para el re-XOR del bloque fusionado (lo/hi)
Sest=$037D          ; estimacion del pulso corto del leader (lo/hi)
TSM_v=$037F         ; umbral corto/medio calculado (lo/hi)
TML_v=$0381         ; umbral medio/largo calculado (lo/hi)
calibr=$0383        ; 1 = midiendo el leader (calibrando velocidad), 0 = congelado
tpulse=$0384        ; contador de actividad de pulsos (lo incrementa el IRQ en cada pulso)
tlast=$0385         ; ultimo tpulse visto por do_copy (deteccion de inactividad)
tidle=$03A0         ; vueltas de inactividad de pulsos en do_copy (lo/hi)
DCTMO = 512         ; umbral de inactividad (en ticks de 256 vueltas, ~1.6s): el stream paro
qd=$03A2            ; temporal para los calculos de umbral (lo/hi)
; --- variables de ESCRITURA de cinta (SAVE) ---
wst=$0386           ; fase de escritura: 0=leader 1=bytes 2=fin 3=hecho
wnext=$0387         ; siguiente pulso precomputado (lo/hi)
wlcnt=$0389         ; pulsos de leader restantes (lo/hi)
whalf=$038B         ; mitad del dipolo/marcador (0 o 1)
wdone=$038C         ; ultimo pulso emitido (1) -> falta el flanco de cierre
wfin=$038D          ; escritura terminada del todo (1)
wsym=$038E          ; simbolo dentro del byte: 0=marcador 1..8=bits 9=paridad
wcur=$038F          ; byte actual en escritura
wpar=$0390          ; paridad del byte actual (impar)
wbph=$0391          ; fase del flujo de bytes: 0=countdown 1=datos 2=checksum
wcdcnt=$0392        ; contador de countdown (9..1)
wcmask=$0393        ; mascara de copia para el countdown ($80 copia1, $00 copia2)
wptr=$C1            ; puntero de datos en pagina cero (=KSAVPTR), para (wptr),y
wend=$0396          ; fin+1 de datos (lo/hi)
wchk=$0398          ; checksum acumulado (XOR de datos)
wcopy=$0399         ; numero de copia (1 o 2)
wleader2=$039A      ; pulsos de leader de la copia 2 (lo/hi)
wsptr=$039C         ; puntero de inicio de datos guardado, para resetear en copia 2 (lo/hi)
tsstart=$039E       ; inicio guardado por tape_save (el bloque de cabecera machaca KSAVPTR) (lo/hi)
wpadn=$03A4         ; bytes de relleno ($20) que faltan tras los datos
wpad0=$03A5         ; relleno de cada copia (cabecera: 192-21; datos: 0)
wedge=$03A6         ; 0 = la siguiente IRQ es la bajada (mitad), 1 = la subida
wqh=$03A7           ; cola de pulsos: indice de lectura (manejador)
wqt=$03AB           ; cola de pulsos: indice de escritura (bucle principal)
wqlo=$03AC          ; cola de pulsos (4 huecos, lo)
wqhi=$03B0          ; cola de pulsos (4 huecos, hi)
wlast=$03A8         ; el pulso en curso es el ultimo del bloque
calcnt=$03A9        ; pulsos de guia hasta el siguiente recalculo de umbrales
calok=$03AA         ; ya hay umbrales calculados con esta guia (1) o no (0)
TSM=456
TML=608

; --- envoltorio: llamado desde KLOAD con dispositivo==1 ---
; entra: KLDPTR=destino, KSA=relocalizar(0)/dir-fichero, KVERCK=verify
; sale: clc + X/Y=fin+1 (exito) | sec + A=codigo (error)
tape_load:
        lda $0314
        sta tsav
        lda $0315
        sta tsav+1
        lda KVERCK
        sta tverify         ; recordar VERIFY; la cabecera se almacena siempre
        lda #$00
        sta KVERCK
        sta tstop           ; sin abort por STOP todavia
        sta KSTATUS         ; ST limpio (bit4 de verify parte de cero)
        lda #$80
        sta Sest            ; Sest = 384 (pulso corto canonico) por defecto
        lda #$01
        sta Sest+1
        jsr calc_thresh     ; umbrales por defecto (se recalibran con el leader)
        ; --- PRESS PLAY ON TAPE + esperar a que se pulse PLAY (sense $01 bit4) ---
        lda $01
        and #$10
        beq tl_playok       ; bit4=0 -> PLAY ya pulsado, no esperar
        bit KMSGFL
        bpl tl_waitp        ; mensajes off (cargador) -> esperar en silencio
        lda #<MPLAY
        ldy #>MPLAY
        jsr STROUT
tl_waitp:
        lda $01
        and #$10
        bne tl_waitp        ; bit4=1 -> aun sin pulsar, esperar
tl_playok:
        jsr KSRCHMSG        ; "SEARCHING FOR <nombre>" si los mensajes ON
        jsr tp_blank        ; pantalla apagada: sin lineas malas del VIC
        sei
        lda #<HDLR
        sta $0314
        lda #>HDLR
        sta $0315
        lda $01
        and #$DF            ; motor on (bit5=0)
        sta $01
        lda #$FF
        sta $DC06
        sta $DC07
        lda #%00010001      ; timer B continuo + force load + start
        sta $DC0F
        lda #$01
        sta $DC0D           ; deshabilitar IRQ timer A
        lda #$90
        sta $DC0D           ; habilitar FLAG
        lda #$FF
        sta last_lo
        sta last_hi
        lda #$00
        sta primed
        sta phase
        sta state
        sta bstate
        sta syncn
        sta blkstat
        cli
tl_nextfile:
        ; leer CABECERA en $0362
        lda #$62
        sta dest
        lda #$03
        sta dest+1
        lda #21             ; almacenar solo ftype+start+end+nombre (21 bytes)
        sta maxst           ; el relleno/checksum se lee para el XOR pero no se almacena
        lda #$00
        sta maxst+1
        jsr read_block
        lda tstop
        beq tl_hdrnostop    ; sin abort -> seguir
        jmp tl_break        ; RUN/STOP durante la lectura de cabecera
tl_hdrnostop:
        bcs tl_hdrok
        jmp tl_err
tl_hdrok:
        lda $0362           ; tipo de cabecera
        cmp #$05
        bne tl_no5
        jmp tl_err          ; fin de cinta logico: FILE NOT FOUND
tl_no5: and #$FD
        cmp #$01
        beq tl_prg          ; 1 (reubicable) o 3 (absoluto): programa
        jmp tl_nextfile     ; otro bloque (fichero de datos): seguir buscando
tl_prg: lda $0363
        sta startlo
        lda $0364
        sta starthi
        lda $0365
        sta endlo
        lda $0366
        sta endhi
        ; --- FOUND <nombre> (en cada cabecera, si mensajes ON) ---
        bit KMSGFL
        bpl tl_nofound
        jsr tm_off          ; CHROUT corre con IRQ enmascaradas: parar la
        lda #<MFOUND        ; cinta mientras se escribe para no perder pulsos
        ldy #>MFOUND
        jsr STROUT
        jsr tl_prnam
        jsr tm_on
tl_nofound:
        ; --- coincide el nombre pedido? (KFNLEN=0 -> cargar el primero) ---
        lda KFNLEN
        beq tl_match
        ldy #$00
tl_cmp:
        cpy KFNLEN
        beq tl_match        ; coincidieron todos los bytes pedidos (prefijo, como CBM)
        lda (KFNADR),y
        cmp $0367,y
        bne tl_skip
        iny
        bne tl_cmp
tl_skip:
        ; no coincide: descartar su bloque de datos y leer la siguiente cabecera
        jsr skip_block
        lda tstop
        bne tl_break        ; RUN/STOP mientras se salta un fichero
        jmp tl_nextfile
tl_match:
        lda tverify
        sta KVERCK          ; restaurar VERIFY para el bloque de datos
        jsr tm_off
        jsr KLDGMSG         ; "LOADING" / "VERIFYING" segun KVERCK (si mensajes ON)
        jsr tm_on
        ; destino: SA=0 y tipo 1 -> KLDPTR; si no, direccion del fichero
        lda KSA
        bne tl_fileaddr
        lda $0362
        cmp #$03
        beq tl_fileaddr
        lda KLDPTR
        sta dest
        lda KLDPTR+1
        sta dest+1
        jmp tl_setlen
tl_fileaddr:
        lda startlo
        sta dest
        lda starthi
        sta dest+1
tl_setlen:
        sec
        lda endlo
        sbc startlo
        sta maxst
        lda endhi
        sbc starthi
        sta maxst+1
        lda dest            ; guardar base de carga para fin+1
        sta startlo
        lda dest+1
        sta starthi
        jsr read_block
        lda tstop
        bne tl_break        ; RUN/STOP durante la lectura de datos
        bcc tl_err
        jsr tl_restore      ; primero parar el IRQ de cinta: usa dlo/dhi
        clc
        lda startlo
        adc maxst
        tax
        lda starthi
        adc maxst+1
        tay                 ; X/Y = fin+1
        clc
        rts
tl_err:
        jsr tl_restore
        lda #$04
        sec
        rts
tl_break:
        jsr tl_restore
        lda #$00
        sec
        jmp STOP            ; RUN/STOP durante la carga: BREAK y vuelta a READY
tl_restore:
        sei
        lda #$7F
        sta $DC0D           ; limpiar habilitaciones CIA1
        lda #$81
        sta $DC0D           ; re-habilitar timer A (jiffy)
        jsr t_cinv
        lda $01
        ora #$20            ; motor off
        sta $01
        jsr tp_show
        cli
        rts


; imprime el nombre de 16 chars de la cabecera ($0367) via KCHROUT
tl_prnam:
        ldy #$00
tl_pn:  lda $0367,y
        jsr KCHROUT
        iny
        cpy #$10
        bne tl_pn
        rts
MRECORD:.byte $0D,"PRESS RECORD & PLAY ON TAPE",0
MFOUND: .byte $0D,"FOUND ",0

; descarta un bloque completo (ambas copias) sin escribir memoria: tstore=0
skip_block:
        lda #$62
        sta dbase
        lda #$03
        sta dbase+1
        lda #$00
        sta tstore
        jsr do_copy         ; copia 1: descartar
        lda #$00
        sta tstore
        jsr do_copy         ; copia 2: descartar
        rts

read_block:
        lda dest
        sta dbase
        lda dest+1
        sta dbase+1
        lda #$00
        sta got
        sta expchkok        ; reset de la captura del checksum esperado
        ; copia 1: almacenar
        lda #$01
        sta tstore
        jsr do_copy
        cmp #$01
        bne rb1bad
        lda #$01
        sta got
rb1bad:
        lda tstop
        bne rbdone          ; STOP durante copia1: no leer copia2 (evita colgarse)
        lda got
        bne rb1ok           ; copia1 buena -> descartar copia2
        ; copia1 mala
        lda KVERCK
        bne rb2vrf          ; VERIFY: copia2 compara (sin merge), comportamiento actual
        ; LOAD con copia1 mala: leer copia2 en MODO MERGE (sobrescribir bytes buenos)
        lda #$02
        sta tstore
        jsr do_copy
        lda tstop
        bne rbdone          ; STOP durante copia2
        jsr chk_merged      ; got=1 si el checksum del bloque fusionado cuadra
        jmp rbdone
rb1ok:
        ; copia1 buena: descartar copia2
        lda #$00
        sta tstore
        jsr do_copy
        jmp rbdone
rb2vrf:
        ; VERIFY copia1 mala: copia2 compara (tstore=1 + KVERCK=1 -> bb_vrf)
        lda #$01
        sta tstore
        jsr do_copy
        cmp #$01
        bne rbdone
        lda #$01
        sta got
rbdone:
        lda got
        beq rbfail
        sec
        rts
rbfail:
        clc
        rts

; --- verificar el bloque fusionado: XOR de memory[dbase..dbase+maxst-1]
;     contra el checksum esperado. got=1 si cuadra. ---
chk_merged:
        lda expchkok
        beq cm_done         ; sin checksum capturado -> no verificable -> got queda 0
        lda dbase
        sta dest            ; reusar dest (pagina cero) como puntero; la copia ya termino
        lda dbase+1
        sta dest+1
        lda maxst
        sta mcnt
        lda maxst+1
        sta mcnt+1
        lda #$00
        sta chk             ; reusar chk como acumulador (ya no se usa tras las copias)
cm_loop:
        lda mcnt
        ora mcnt+1
        beq cm_check        ; mcnt==0 -> fin
        ldy #$00
        lda (dest),y
        eor chk
        sta chk
        inc dest
        bne cm_dec
        inc dest+1
cm_dec:
        lda mcnt
        bne cm_declo
        dec mcnt+1
cm_declo:
        dec mcnt
        jmp cm_loop
cm_check:
        lda chk
        cmp expchk
        bne cm_done
        lda #$01
        sta got             ; XOR del bloque fusionado == checksum -> recuperado
cm_done:
        rts

; --- leer UNA copia a (dbase); espera a que termine; A=blkstat ---
do_copy:
        lda dbase
        sta dest
        lda dbase+1
        sta dest+1
        lda #$00
        sta dcnt
        sta dcnt+1
        sta chk
        sta blkstat
        sta dcstopc
        sta tidle
        sta tidle+1         ; reset del contador de inactividad
        lda tpulse
        sta tlast           ; snapshot de la actividad de pulsos
        jsr resetblk
dcwait:
        lda blkstat
        bne dcdone
        dec dcstopc
        bne dcwait          ; throttle: cada 256 vueltas sondear STOP e inactividad
        lda #$7F
        sta $DC00           ; fila 7 del teclado (RUN/STOP)
        lda $DC01
        and #$80            ; bit7 = RUN/STOP
        beq dc_stop         ; pulsada -> abort
        ; STOP no pulsada: comprobar si siguen llegando pulsos
        lda tpulse
        cmp tlast
        beq dc_idle         ; sin pulso nuevo -> contar inactividad
        sta tlast           ; hubo pulso -> resetear inactividad
        lda #$00
        sta tidle
        sta tidle+1
        jmp dcwait
dc_idle:
        inc tidle
        bne dc_idchk
        inc tidle+1
dc_idchk:
        lda tidle
        cmp #<DCTMO
        lda tidle+1
        sbc #>DCTMO
        bcc dcwait          ; tidle < DCTMO -> seguir esperando el bloque
        jmp dcdone          ; timeout: el stream paro -> salir (blkstat=0 = fallo)
dc_stop:
        lda #$80
        sta tstop           ; pulsada -> marcar abort y salir del spin
dcdone:
        lda blkstat
        rts

resetblk:
        lda #$00
        sta bstate
        sta syncn
        sta ncopy
        sta calok           ; sin umbrales de esta guia todavia
        lda #16
        sta calcnt
        lda #$01
        sta calibr          ; re-calibrar velocidad con el leader de esta copia
        rts

; --- umbrales desde Sest: TSM=Sest*1.1875, TML=Sest*1.5625 (puntos medios
;     de las ratios reales medio/corto=1.375 y largo/corto=1.79) ---
calc_thresh:
        lda Sest+1
        lsr a
        sta qd+1
        lda Sest
        ror a
        sta qd              ; qd = Sest/2
        lda qd+1
        sta cur_hi
        lda qd
        lsr cur_hi
        ror a
        lsr cur_hi
        ror a
        lsr cur_hi
        ror a
        sta cur_lo          ; cur = q = Sest/16 (cur es libre fuera del IRQ)
        clc
        adc qd
        tax
        lda cur_hi
        adc qd+1
        tay                 ; Y:X = Sest/2 + q
        clc
        txa
        adc Sest
        sta TML_v
        tya
        adc Sest+1
        sta TML_v+1         ; TML = Sest + Sest/2 + q  (1.5625*Sest)
        lda cur_lo
        asl a
        tax
        lda cur_hi
        rol a
        tay                 ; Y:X = 2q
        clc
        txa
        adc cur_lo
        tax
        tya
        adc cur_hi
        tay                 ; Y:X = 3q
        clc
        txa
        adc Sest
        sta TSM_v
        tya
        adc Sest+1
        sta TSM_v+1         ; TSM = Sest + 3q  (1.1875*Sest)
        rts

; ===== pulso -> byte; manejador en convencion CINV (KIRQENT ya salvo A,X,Y) =====
; Presupuesto: el pulso corto real dura ~376 ciclos y el siguiente FLAG no
; puede llegar con este manejador aun en curso (se perderia y la medida del
; pulso siguiente saldria corrida). Camino comun ~200 ciclos con entrada y
; salida; el trabajo largo (umbrales, fin de byte) cae en pulsos seguidos de
; uno largo.
HDLR:
        lda $DC0D           ; reconocer FLAG
rdtb:   ldx $DC07
        lda $DC06
        cpx $DC07
        bne rdtb            ; X/A = timer B (alto/bajo) coherentes
        sta cur_lo
        stx cur_hi
        sec
        lda last_lo
        sbc cur_lo
        sta dlo
        lda last_hi
        sbc cur_hi
        sta dhi             ; d = last - cur (el timer cuenta hacia abajo)
        lda cur_lo
        sta last_lo
        stx last_hi
        inc tpulse          ; actividad de pulsos (deteccion de fin de stream)
        lda primed
        bne haved
        inc primed          ; primer flanco: solo referencia
        jmp hd_rti
haved:
        lda calibr
        bne hd_cal
        jmp hd_class
hd_cal:
        ; --- calibracion con la guia: solo se mide, no se decodifica.
        ;     Sest sigue a d (media exponencial 1/4). Tras 16 pulsos
        ;     seguidos dentro de banda (Sest/2 <= d < 1.5*Sest) se calculan
        ;     umbrales (calok=1) y el primer pulso >= 1.5*Sest es el
        ;     marcador que cierra la guia. Fuera de banda antes de eso
        ;     (ruido al arrancar el motor, vuelta del timer en una pausa)
        ;     solo reinicia la cuenta: Sest se recupera solo.
        sec
        lda dlo
        sbc Sest
        sta qd
        lda dhi
        sbc Sest+1
        sta qd+1            ; qd = d - Sest (con signo)
        lda Sest+1
        lsr a
        sta cur_hi
        lda Sest
        ror a
        sta cur_lo          ; cur = Sest/2 (cur ya no hace falta)
        bit qd+1
        bmi cal_neg
        lda qd
        cmp cur_lo
        lda qd+1
        sbc cur_hi
        bcc cal_in          ; d < 1.5*Sest
        lda calok
        bne cal_end         ; largo con umbrales listos: fin de la guia
        beq cal_oob
cal_neg:
        lda dlo
        cmp cur_lo
        lda dhi
        sbc cur_hi
        bcs cal_in          ; d >= Sest/2
        lda #$00
        sta calok           ; basura corta: volver a exigir 16 pulsos
cal_oob:
        lda #16
        sta calcnt
        ldx #$00
        beq cal_upd
cal_in: ldx #$01
cal_upd:
        lda qd+1            ; Sest += (d - Sest)/4
        cmp #$80
        ror a
        ror qd
        cmp #$80
        ror a
        ror qd
        tay
        clc
        lda qd
        adc Sest
        sta Sest
        tya
        adc Sest+1
        sta Sest+1
        txa
        beq cal_x           ; fuera de banda: no cuenta
        dec calcnt
        bne cal_x
        lda #16
        sta calcnt
        jsr calc_thresh     ; cada 16 pulsos de guia: umbrales al dia (ese
        lda #$01            ; manejador se alarga, pero en la guia da igual)
        sta calok
cal_x:  jmp hd_rti
cal_end:
        lda #$00            ; el marcador se clasifica con los umbrales ya
        sta calibr          ; calculados: aqui no hay tiempo para recalcular
hd_class:
        ; --- clasificar: X = 0 corto, 1 medio, 2 largo ---
        ldx #$00
        lda dlo
        cmp TSM_v
        lda dhi
        sbc TSM_v+1
        bcc hd_cls
        inx
        lda dlo
        cmp TML_v
        lda dhi
        sbc TML_v+1
        bcc hd_cls
        inx
hd_cls:
        stx tcls
classified:
        cpx #$02
        bne notlong
        stx p1              ; largo: primera mitad de un marcador
        lda #$01
        sta phase
        jmp hd_rti
notlong:
        lda phase
        bne second
        stx p1
        inc phase
        jmp hd_rti
second:
        lda #$00
        sta phase
        lda p1
        cmp #$02
        bne notLpair
        cpx #$01
        bne chk_LS
        lda #$01            ; [L,M]: marcador de byte
        sta state
        lda #$00
        sta bitcnt
        sta curbyte
        sta parity
        jmp hd_rti
chk_LS:
        cpx #$00
        bne framerr
        jsr blkend          ; [L,S]: fin de bloque
        jmp hd_rti
notLpair:
        lda state
        beq hd_rti
        lda p1
        bne chk_ms
        cpx #$01            ; [S,M] = 0
        bne framerr
        lda #$00
        beq gotbit
chk_ms:
        cpx #$00            ; [M,S] = 1
        bne framerr
        lda #$01
gotbit:
        ldy bitcnt
        cpy #$08
        beq dopar
        tax
        eor parity
        sta parity
        txa
        lsr a
        ror curbyte         ; LSB primero
        inc bitcnt
        jmp hd_rti
dopar:
        eor parity
        cmp #$01
        beq okpar
        ; paridad MALA
        lda bstate
        beq parbaddrop      ; en sync: descartar (no romper el sync)
        lda #$01
        sta bderr           ; en datos: marcar error y pasar el byte (mantener alineacion)
        lda curbyte
        jsr blkbyte
parbaddrop:
        lda #$00
        sta state
        jmp hd_rti
okpar:
        lda #$00
        sta bderr           ; byte con paridad buena
        lda curbyte
        jsr blkbyte
        lda #$00
        sta state
        jmp hd_rti
framerr:
        lda #$00
        sta state
        sta phase
hd_rti:
        pla
        tay
        pla
        tax
        pla
        rti

; ============ capa de bloque (byte -> bloque) ============
blkbyte:
        ldx bstate
        bne bb_data
        ldx syncn
        bne bb_match
        cmp #$89
        bne bb_t09
        ldx #$01
        stx ncopy
        ldx #$88
        stx syncn
        rts
bb_t09:
        cmp #$09
        beq bb_t09y
        rts                ; no es $09 -> volver (bb_ret esta lejos)
bb_t09y:
        ldx #$02
        stx ncopy
        ldx #$08
        stx syncn
        rts
bb_match:
        cmp syncn
        bne bb_syncbad
        cmp #$81
        beq bb_sdone
        cmp #$01
        beq bb_sdone
        dec syncn
        rts
bb_sdone:
        lda #$01
        sta bstate
        rts
bb_syncbad:
        lda #$00
        sta syncn
        rts
bb_data:
        sta bval
        lda tstore
        beq bb_nost
        lda dcnt
        cmp maxst
        lda dcnt+1
        sbc maxst+1
        bcs bb_nost        ; dcnt >= maxst (checksum/relleno) -> bb_nost
        lda tstore
        cmp #$02
        beq bb_merge       ; merge (LOAD copia2)
        lda KVERCK
        bne bb_vrf         ; verify: comparar en vez de almacenar
        lda bval
        ldy #$00
        sta (dest),y
        jmp bb_dinc
bb_merge:
        lda bderr
        bne bb_dinc        ; copia2 con error -> conservar el byte de copia1
        lda bval
        ldy #$00
        sta (dest),y       ; copia2 buena -> sobrescribir copia1
        jmp bb_dinc
bb_vrf:
        ldy #$00
        lda (dest),y
        cmp bval           ; memoria vs byte decodificado
        beq bb_dinc        ; coincide
        lda KSTATUS
        ora #$10           ; bit4: error de verificacion
        sta KSTATUS
bb_dinc:
        inc dest
        bne bb_d1
        inc dest+1
bb_d1:
bb_nost:
        lda expchkok
        bne bb_noexp
        lda dcnt
        cmp maxst
        bne bb_noexp
        lda dcnt+1
        cmp maxst+1
        bne bb_noexp       ; no es el byte de checksum del bloque
        lda bderr
        bne bb_noexp       ; checksum con error de paridad -> no capturar
        lda bval
        sta expchk         ; checksum esperado (de una copia con paridad buena)
        lda #$01
        sta expchkok
bb_noexp:
        lda bval
        eor chk
        sta chk
        inc dcnt
        bne bb_d2
        inc dcnt+1
bb_d2:
bb_ret:
        rts

blkend:
        lda bstate
        beq be_ret
        lda chk
        bne be_bad
        lda #$01
        sta blkstat
        jmp be_rst
be_bad:
        lda #$02
        sta blkstat
be_rst:
        lda #$00
        sta bstate
        sta syncn
be_ret:
        rts

; ============ ESCRITURA DE CINTA (SAVE) ============
; Formato CBM (interfaz publica): cada pulso es un ciclo completo de la
; linea de escritura ($01 bit3): sube al empezar el pulso y baja a la
; mitad. El lector mide de flanco a flanco del mismo sentido, asi que la
; duracion del pulso es la de subida a subida.
; Timer B en modo continuo: el CIA recarga solo desde el latch en cada
; underflow, asi que los flancos no dependen de lo que tarde el manejador.
; El manejador solo cambia la linea y, en la bajada, deja en el latch la
; mitad del pulso siguiente; el bucle principal precalcula ese pulso.
WS = 384/2-1            ; pulso corto (latch de medio periodo; periodo = latch+1)
WM = 528/2-1            ; pulso medio
WL = 688/2-1            ; pulso largo

tape_wblock:
        ; el llamador deja wptr=inicio, wend=fin+1, wlcnt=leader1,
        ; wleader2=leader2, wpad0=bytes de relleno ($20) tras los datos
        lda $0314
        sta tsav            ; guardar CINV
        lda $0315
        sta tsav+1
        lda #$00
        sta wst             ; fase 0 = leader
        sta whalf
        sta wdone
        sta wfin
        sta wlast
        lda #$01
        sta wedge           ; la primera IRQ da la subida del pulso 0
        sta wcopy           ; empezar por la copia 1
        lda wpad0
        sta wpadn
        lda wptr
        sta wsptr
        lda wptr+1
        sta wsptr+1         ; guardar inicio para resetear en copia 2
        sei
        lda #<whandler
        sta $0314
        lda #>whandler
        sta $0315
        lda $01
        and #$F7
        sta $01             ; linea en bajo antes del primer pulso
        jsr wgen            ; wnext = pulso 0
        lda wnext
        sta $DC06
        lda wnext+1
        sta $DC07
        lda #$11
        sta $DC0F           ; force load + start, continuo
        lda $DC0D           ; limpiar flags pendientes
        lda #$82
        sta $DC0D           ; habilitar IRQ de Timer B
        lda #$00
        sta wqh
        sta wqt             ; cola de pulsos vacia
        cli
; El bucle principal llena una cola de 3 pulsos por delante; el manejador
; la vacia. Un pulso puede costar mas de calcular que lo que dura (inicio
; de byte, cambio de copia), y con la cola esos picos no llegan al timer.
ws_wait:
        lda wfin
        bne ws_fin
        lda wdone
        bne ws_wait         ; ya no hay mas pulsos que calcular
        ldx wqt
        inx
        txa
        and #$03
        cmp wqh
        beq ws_wait         ; cola llena
        jsr wgen
        lda wdone
        bne ws_wait
        ldx wqt
        lda wnext
        sta wqlo,x
        lda wnext+1
        sta wqhi,x
        inx
        txa
        and #$03
        sta wqt             ; publicar despues de escribir el pulso
        jmp ws_wait
ws_fin:
        lda #$02
        sta $DC0D           ; deshabilitar IRQ de Timer B
t_cinv: lda tsav
        sta $0314           ; restaurar CINV
        lda tsav+1
        sta $0315
        rts

; manejador de escritura (CINV; KIRQENT ya apilo A/X/Y). Tiempo constante.
whandler:
        lda $DC0D           ; reconocer Timer B
        lda wedge
        bne wh_bound
        lda $01             ; mitad del pulso: bajada
        and #$F7
        sta $01
        inc wedge
        ldx wqh
        cpx wqt
        beq wh_vacia
        lda wqlo,x
        sta $DC06
        lda wqhi,x
        sta $DC07           ; latch = mitad del pulso siguiente (vale en la subida)
        inx
        txa
        and #$03
        sta wqh
        jmp wh_rti
wh_vacia:
        lda wdone           ; cola vacia: si no hay mas pulsos, este es el
        sta wlast           ; ultimo y el latch sigue con su mitad
        jmp wh_rti
wh_bound:
        lda $01             ; fin del pulso: subida (empieza el siguiente)
        ora #$08
        sta $01
        lda #$00
        sta wedge
        lda wlast
        beq wh_rti
        lda #$00
        sta $DC0F           ; era el ultimo: parar el timer
        lda #$01
        sta wfin
wh_rti:
        pla
        tay
        pla
        tax
        pla
        rti

; generador: wnext = pulso del estado actual; avanza el estado
wgen:
        lda wst
        cmp #$03
        bne wg_n3
        lda #$01
        sta wdone           ; wst==3 -> bloque hecho (inline)
        rts
wg_n3:
        cmp #$00
        beq wg_leader
        cmp #$02
        beq wg_end
        ; wst==1 (flujo de bytes):
        jsr wbytepulse
        jsr wbyteadv
        rts
wg_end:
        lda whalf
        bne wg_end1
        inc whalf
        ldy #$02            ; marcador de fin: mitad 0 -> L
        jmp wemit
wg_end1:
        ldy #$00            ; marcador de fin: mitad 1 -> S
        jsr wemit
        ; copia terminada: si era la copia 1, encadenar la copia 2
        lda wcopy
        cmp #$01
        bne wg_alldone
        lda #$02
        sta wcopy           ; pasar a copia 2
        lda wsptr
        sta wptr
        lda wsptr+1
        sta wptr+1          ; resetear puntero de datos al inicio
        lda wpad0
        sta wpadn           ; y el relleno
        lda wleader2
        sta wlcnt
        lda wleader2+1
        sta wlcnt+1         ; leader de la copia 2
        lda #$00
        sta wst             ; volver a fase leader (continuo, sin hueco)
        sta whalf
        rts
wg_alldone:
        lda #$03
        sta wcopy           ; copia 2 terminada: cola de pulsos cortos
        lda #78
        sta wlcnt
        lda #$00
        sta wlcnt+1
        sta wst
        sta whalf
        rts
wg_leader:
        ldy #$00
        jsr wemit           ; guia: pulsos cortos
        lda wlcnt
        bne wg_l1
        dec wlcnt+1
wg_l1:
        dec wlcnt
        lda wlcnt
        ora wlcnt+1
        bne wg_lret
        lda wcopy
        cmp #$03
        bne wg_lbytes
        sta wst             ; era la cola: tras este pulso, bloque hecho
        rts
wg_lbytes:
        lda #$01
        sta wst             ; leader hecho -> fase de bytes
        jsr wstartbytes
wg_lret:
        rts

; iniciar el flujo de bytes (al terminar el leader). El llamador deja
; wptr=inicio, wend=fin+1, wcopy=numero de copia.
wstartbytes:
        lda #$00
        sta wbph            ; fase 0 = countdown
        sta wchk            ; checksum = 0
        lda wcopy
        cmp #$01
        bne wsb_c2
        lda #$80            ; copia 1: countdown $89..$81
        sta wcmask
        jmp wsb_c3
wsb_c2:
        lda #$00            ; copia 2: countdown $09..$01
        sta wcmask
wsb_c3:
        lda #$09
        sta wcdcnt
        ora wcmask
        sta wcur            ; primer byte de countdown = 9 | mascara
        jmp wnewbyte

; wnext = pulso del simbolo actual (wsym, whalf) del byte wcur (paridad wpar).
; Simbolos: marcador [L,M], bit 0 [S,M], bit 1 [M,S]. Indice en wpsym =
; tipo*2 + mitad (tipo 0 marcador, 1 bit 0, 2 bit 1).
wbytepulse:
        lda wsym
        beq wbp_mark        ; 0: marcador (A=0)
        cmp #$09
        beq wbp_par
        tax                 ; 1..8: bit (wsym-1) de wcur
        lda wcur
wbp_sh: dex
        beq wbp_bit
        lsr a
        jmp wbp_sh
wbp_par:
        lda wpar            ; 9: bit de paridad
wbp_bit:
        and #$01
        asl a
        adc #$02            ; bit 0 -> 2, bit 1 -> 4 (C=0 tras el ASL)
wbp_mark:
        ora whalf
        tax
        ldy wpsym,x         ; 0 = S, 1 = M, 2 = L
; wnext = pulso Y (0 corto, 1 medio, 2 largo)
wemit:  lda wplo,y
        sta wnext
        lda wphi,y
        sta wnext+1
        rts

; --- continuacion de ESCRITURA de cinta (wbyteadv/wcalcpar) ---
; avanzar el estado tras emitir un pulso del flujo de bytes
wbyteadv:
        lda whalf
        bne wba_h1
        lda #$01            ; mitad 0 -> mitad 1 (mismo simbolo)
        sta whalf
        rts
wba_h1:
        lda #$00
        sta whalf
        lda wsym
        cmp #$09
        beq wba_bytedone
        inc wsym            ; siguiente simbolo del byte
        rts
wba_bytedone:
        lda wbph
        beq wba_cd
        cmp #$01
        beq wba_data
        lda #$02            ; wbph==2 (checksum hecho) -> marcador de fin
        sta wst
        lda #$00
        sta whalf
        rts
wba_cd:
        dec wcdcnt
        lda wcdcnt
        beq wba_cd2data
        lda wcdcnt          ; siguiente byte de countdown
        ora wcmask
        sta wcur
        jmp wnewbyte
wba_cd2data:
        lda #$01
        sta wbph
        jmp wba_loaddata
wba_data:
wba_loaddata:
        lda wptr            ; si wptr < wend -> dato; si no -> checksum
        cmp wend
        lda wptr+1
        sbc wend+1
        bcc wba_loadbyte
        lda wpadn
        beq wba_tochk
        dec wpadn           ; relleno de la cabecera hasta 192 bytes
        lda #$20
        bne wba_putbyte
wba_loadbyte:
        ldy #$00
        lda (wptr),y
        inc wptr
        bne wba_putbyte
        inc wptr+1
wba_putbyte:
        sta wcur
        eor wchk
        sta wchk            ; wchk ^= byte
wba_nd:
        jmp wnewbyte
wba_tochk:
        lda #$02
        sta wbph
        lda wchk
        sta wcur            ; byte de checksum
        jmp wnewbyte

; wnewbyte: wpar = paridad impar de wcur (1 XOR popcount-paridad), sin
; destruir wcur, y simbolo/mitad a cero (el byte empieza por su marcador)
wnewbyte:
        lda wcur
        ldx #$08
        ldy #$00            ; Y = cuenta de bits a 1
wcp_l:
        lsr a               ; bit -> carry (A guarda el dato, iny no lo toca)
        bcc wcp_s
        iny
wcp_s:
        dex
        bne wcp_l
        tya
        and #$01            ; popcount mod 2
        eor #$01            ; paridad impar = 1 XOR (popcount mod 2)
        sta wpar
        lda #$00            ; empezar el byte por su marcador
        sta wsym
        sta whalf
        rts

; ------------------------------------------------------------
; tape_save: escribe un fichero completo en cinta (bloque cabecera + bloque
; datos), espejo de tape_load. Lo llama KSAVE en la rama dispositivo 1.
; Entradas (las deja KSAVE): KSAVPTR ($C1/$C2)=inicio, KLDPTR ($AE/$AF)=fin+1,
;   nombre via SETNAM (KFNLEN, (KFNADR)), KSA (tipo de cabecera 1 o 3).
; Estructura (formato CBM): guia, cabecera de 192 bytes x2, guia, datos x2;
; cada copia termina con 78 pulsos cortos.
; ------------------------------------------------------------
tape_save:
        ; --- PRESS RECORD & PLAY ON TAPE + esperar sense ($01 bit4) ---
        lda $01
        and #$10
        beq ts_playok       ; bit4=0 -> tecla ya pulsada
        bit KMSGFL
        bpl ts_waitp        ; mensajes off (cargador) -> esperar en silencio
        lda #<MRECORD
        ldy #>MRECORD
        jsr STROUT
ts_waitp:
        lda $01
        and #$10
        bne ts_waitp        ; esperar a bit4=0
ts_playok:
        jsr KSAVMSG         ; "SAVING <nombre>" si los mensajes ON
        jsr tp_blank
        ; motor on + deshabilitar el jiffy (timer A) durante la escritura
        lda $01
        and #$DF
        sta $01             ; motor on (bit5=0)
        lda #$01
        sta $DC0D           ; deshabilitar IRQ de timer A
        lda $DC0D           ; limpiar flags pendientes
        ; guardar el inicio (el bloque de cabecera machaca wptr=KSAVPTR)
        lda KSAVPTR
        sta tsstart
        lda KSAVPTR+1
        sta tsstart+1
        ; construir la cabecera en $0362 (libre durante SAVE): 21 bytes
        ; reales; el escritor completa hasta 192 con relleno $20
        lda KSA
        and #$01
        asl a
        ora #$01
        sta $0362           ; tipo: 1 = reubicable (SA par), 3 = absoluto (SA impar)
        lda tsstart
        sta $0363           ; start lo
        lda tsstart+1
        sta $0364           ; start hi
        lda KLDPTR
        sta $0365           ; end lo
        lda KLDPTR+1
        sta $0366           ; end hi
        ldy #$00
ts_nm:
        cpy #$10
        bcs ts_nmend        ; y >= 16 -> nombre completo
        cpy KFNLEN
        bcs ts_pad          ; y >= longitud -> rellenar con espacio
        lda (KFNADR),Y
        jmp ts_put
ts_pad:
        lda #$20
ts_put:
        sta $0367,Y
        iny
        jmp ts_nm
ts_nmend:
        ; --- bloque de CABECERA: guia de $6A00 pulsos (unos 10 s), 79 entre copias ---
        lda #<$0362
        sta wptr
        lda #>$0362
        sta wptr+1
        lda #<$0377
        sta wend            ; $0362 + 21 = $0377
        lda #>$0377
        sta wend+1
        lda #192-21
        sta wpad0
        lda #<$6A00
        sta wlcnt
        lda #>$6A00
        sta wlcnt+1
        lda #79
        sta wleader2
        lda #$00
        sta wleader2+1
        jsr tape_wblock
        ; pausa de ~0,33 s entre cabecera y datos (linea quieta, motor en marcha)
        ldy #$00
        ldx #$00
ts_pau: dex
        bne ts_pau
        dey
        bne ts_pau
        ; --- bloque de DATOS: guia de $1500 pulsos (unos 2 s), 79 entre copias ---
        lda tsstart
        sta wptr            ; restaurar el inicio
        lda tsstart+1
        sta wptr+1
        lda KLDPTR
        sta wend            ; fin+1
        lda KLDPTR+1
        sta wend+1
        lda #$00
        sta wpad0
        lda #<$1500
        sta wlcnt
        lda #>$1500
        sta wlcnt+1
        lda #79
        sta wleader2
        lda #$00
        sta wleader2+1
        jsr tape_wblock
        ; motor off + rehabilitar el jiffy (timer A)
        lda $01
        ora #$20
        sta $01             ; motor off (bit5=1)
        lda #$81
        sta $DC0D           ; rehabilitar IRQ de timer A
        jsr tp_show
        clc
        rts




; (tabla del editor en el hueco del final de esta seccion)
KSRTAB: .byte "LOAD",$0D,"RUN",$0D,$00

.org $FCE2

; ------------------------------------------------------------
; RESET
; ------------------------------------------------------------
KRESET: sei
        cld
        ldx #$FF
        txs
        lda #$37        ; datos del puerto ANTES que la direccion:
        sta $01         ; si DDR se activa con datos=0, las ROMs se
        lda #$2F        ; desbancan con el PC dentro de ellas
        sta $00
        ; --- ¿cartucho con firma CBM80 en $8004? ---
        jsr KCBMCHK
        bne @nocart
        jmp ($8000)     ; vector frio del cartucho
@nocart:
        jsr KIOINIT     ; CIAs, VIC, timer de jiffy
        jsr KRAMTAS     ; limpiar areas de trabajo, reloj a cero
        jsr KRESTOR     ; vectores de pagina 3 por defecto
        jsr KCINT       ; editor de pantalla y teclado
        cli
        jmp INIT        ; arranque en frio del BASIC

; (tablas en el hueco libre de esta isla)
wpsym:  .byte 2,1, 0,1, 1,0
KBITS:  .byte $01,$02,$04,$08,$10,$20,$40,$80

.org $FD15

; RESTOR ($FF8A): restaurar los vectores por defecto
KRESTOR:
        ldx #$00
@l:     lda KVECTAB,X
        sta $0314,X
        inx
        cpx #(KVECEND-KVECTAB)
        bne @l
        rts

.org $FD50

; ------------------------------------------------------------
; RAMTAS ($FF87): limpiar areas de trabajo y reloj
; ------------------------------------------------------------
KRAMTAS:
        lda #$00
        tax
@rt1:   sta a:$0002,X   ; $0002-$0101. 'a:' fuerza modo absoluto: en modo
                        ; pagina cero,X el indice da la vuelta y pisaba $00/$01
        inx
        bne @rt1
@rt2:   sta $0200,X     ; pagina 2 (bufers)
        inx
        bne @rt2
        sta KTIME       ; reloj jiffy a cero
        sta KTIME+1
        sta KTIME+2
        ; punteros e indices de E/S por defecto
        lda #$00
        sta KMBOT       ; inicio de memoria = $0800
        sta KLDTND
        sta KDFLTN      ; entrada por defecto = teclado
        lda #$08
        sta KMBOT+1
        lda #$00
        sta KMTOP       ; tope de memoria = $A000
        lda #$A0
        sta KMTOP+1
        lda #$03
        sta KDFLTO      ; salida por defecto = pantalla
        rts

; (rutinas de cinta en el hueco libre de esta isla)
; Pantalla apagada durante la cinta: las lineas malas del VIC-II paran la
; CPU unos 40 ciclos y desplazarian los flancos medidos o generados.
tp_blank:
        lda $D011
        and #$EF
        sta $D011
        rts
tp_show:
        lda $D011
        ora #$10
        sta $D011
        rts
tm_off: lda $01
        ora #$20            ; motor parado
        sta $01
        rts
tm_on:  lda $01
        and #$DF            ; motor en marcha
        sta $01
        rts

.org $FDA3

; ------------------------------------------------------------
; IOINIT ($FF84): CIAs, VIC y reloj jiffy
; ------------------------------------------------------------
KIOINIT:
        ; --- CIAs: silenciar interrupciones ---
        lda #$7F
        sta $DC0D
        sta $DD0D
        lda $DC0D       ; limpiar pendientes
        lda $DD0D
        ; CIA1: puerto A salida (filas), puerto B entrada (columnas)
        lda #$FF
        sta $DC02
        lda #$00
        sta $DC03
        ; CIA2 puerto A: banco VIC 0 (bits 0-1 = 11)
        lda #$3F
        sta $DD02
        lda #$03
        sta $DD00
        ; --- reloj jiffy: CIA1 timer A ~60 Hz ---
        lda #$95
        sta $DC04
        lda #$42
        sta $DC05
        lda #$81        ; habilitar IRQ de timer A
        sta $DC0D
        lda #$11        ; arrancar timer, recarga continua
        sta $DC0E
        rts

.org $FF48

; ------------------------------------------------------------
; IRQ / NMI
; ------------------------------------------------------------
; ------------------------------------------------------------
; Entrada hardware de IRQ/BRK: salva registros y despacha por
; los vectores RAM de pagina 3 ($0314 IRQ / $0316 BRK), que el
; software puede redirigir.
; ------------------------------------------------------------
KIRQENT:
        pha
        txa
        pha
        tya
        pha
        tsx
        lda $0104,X     ; P apilado por el hardware
        and #$10        ; ¿flag B? entonces es BRK
        beq @hw
        jmp ($0316)     ; CBINV
@hw:    jmp ($0314)     ; CINV
;--- $FE43: entrada hardware del NMI. Solo SEI y salto por ($0318): el
;    manejador de usuario ve la trama de la CPU (PC+P) y vuelve con RTI.
.org $FE43
KNMIENT:
        sei
        jmp ($0318)
;--- $FE47: manejador NMI por defecto (destino de $0318): apila A/X/Y
KNMIDEF:
        pha
        txa
        pha
        tya
        pha
        jmp KNMI
; (cadena de cinta en el hueco libre de esta isla)
MPLAY:  .byte $0D,"PRESS PLAY ON TAPE",0
;--- $FE66: BRK por defecto (destino de $0316): arranque en caliente
.org $FE66
KBRKDEF:
        jmp KWARM
;--- $FEBC: salida comun de interrupcion: restaurar Y/X/A y RTI
.org $FEBC
KRTIX:  pla
        tay
        pla
        tax
        pla
        rti

.org $E1DE
KIOM9:  .byte "ILLEGAL DEVICE NUMBER",0
KVMSG:  .byte "VERIFY",0
KVOK:   .byte $0D,"OK",0

.org $FEC2
KERRTAB:
        .word KERA00,KERA02,KERA04,KERA06,KERA08,KERA10,KERA12
        .word KERA14,KERA16,KERA18,KERA20,KERA22,KERA24,KERA26
        .word KERA28,KERA30,KERA32,KERA34
KERA04: .byte "RETURN WITHOUT GOSUB",0
KERA30: .byte "FORMULA TOO COMPLEX",0
KIOM5:  .byte "DEVICE NOT PRESENT",0
KIOMSG: .word KIOM1,KIOM2,KIOM3,KIOM4,KIOM5
        .word KIOM6,KIOM7,KIOM8,KIOM9
KIOM8:  .byte "MISSING FILE NAME",0

.org $FDDA
KERA14: .byte "UNDEF'D STATEMENT",0
KERA00: .byte "NEXT WITHOUT FOR",0
KERA08: .byte "ILLEGAL QUANTITY",0
KERA20: .byte "DIVISION BY ZERO",0
KERA34: .byte "UNDEF'D FUNCTION",0
KIOM7:  .byte "NOT OUTPUT FILE",0

.org $FE69
KERA26: .byte "STRING TOO LONG",0
KIOM1:  .byte "TOO MANY FILES",0
KIOM4:  .byte "FILE NOT FOUND",0
KIOM6:  .byte "NOT INPUT FILE",0
KERA22: .byte "ILLEGAL DIRECT",0

; (tabla del teclado en el hueco libre de esta isla)
KRPTSET: .byte $20,$1D,$9D,$11,$91,$14,$94

.org $FD23
KERA32: .byte "CAN'T CONTINUE",0
KIOM3:  .byte "FILE NOT OPEN",0
KERA12: .byte "OUT OF MEMORY",0

.org $FF5E
KERA16: .byte "BAD SUBSCRIPT",0
KERA18: .byte "REDIM'D ARRAY",0
; (tabla de pulsos de cinta en el hueco libre de esta isla)
wplo:   .byte <WS,<WM,<WL
wphi:   .byte >WS,>WM,>WL
;;; ISLAS-FIN

.org $FF5B
        jmp KCINT       ; CINT interno

; ------------------------------------------------------------
.org $FF81
        jmp KCINT       ; $FF81 CINT
        jmp KIOINIT     ; $FF84 IOINIT
        jmp KRAMTAS     ; $FF87 RAMTAS
        jmp KRESTOR     ; $FF8A RESTOR
        jmp KVECTOR     ; $FF8D VECTOR
        jmp KSETMSG     ; $FF90 SETMSG
        jmp KSECND      ; $FF93 SECOND
        jmp KTKSA       ; $FF96 TKSA
        jmp KMEMTOP     ; $FF99 MEMTOP
        jmp KMEMBOT     ; $FF9C MEMBOT
        jmp KSCNKEY     ; $FF9F SCNKEY
        jmp KSETTMO     ; $FFA2 SETTMO
        jmp KACPTR      ; $FFA5 ACPTR
        jmp KCIOUT      ; $FFA8 CIOUT
        jmp KUNTLK      ; $FFAB UNTLK
        jmp KUNLSN      ; $FFAE UNLSN
        jmp KLISTN      ; $FFB1 LISTEN
        jmp KTALK       ; $FFB4 TALK
        jmp KREADST     ; $FFB7 READST
        jmp KSETLFS     ; $FFBA SETLFS
        jmp KSETNAM     ; $FFBD SETNAM
        jmp ($031A)     ; $FFC0 OPEN   (IOPEN)
        jmp ($031C)     ; $FFC3 CLOSE  (ICLOSE)
        jmp ($031E)     ; $FFC6 CHKIN  (ICHKIN)
        jmp ($0320)     ; $FFC9 CHKOUT (ICKOUT)
        jmp ($0322)     ; $FFCC CLRCHN (ICLRCH)
        jmp ($0324)     ; $FFCF CHRIN  (IBASIN)
        jmp ($0326)     ; $FFD2 CHROUT (IBSOUT)
        jmp ($0330)     ; $FFD5 LOAD   (ILOAD)
        jmp ($0332)     ; $FFD8 SAVE   (ISAVE)
        jmp KSETTIM     ; $FFDB SETTIM
        jmp KRDTIM      ; $FFDE RDTIM
        jmp ($0328)     ; $FFE1 STOP  (ISTOP)
        jmp ($032A)     ; $FFE4 GETIN (IGETIN)
        jmp ($032C)     ; $FFE7 CLALL  (ICLALL)
        jmp KUDTIM      ; $FFEA UDTIM
        jmp KSCREEN     ; $FFED SCREEN
        jmp KPLOT       ; $FFF0 PLOT
        jmp KIOBASE     ; $FFF3 IOBASE

.org $FFFA
        .word KNMIENT   ; NMI
        .word KRESET    ; RESET
        .word KIRQENT   ; IRQ/BRK
