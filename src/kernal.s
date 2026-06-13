; ============================================================
;  KERNAL libre v0 para Commodore 64 — sala limpia
;  Escrito desde especificacion documentada (tabla de saltos
;  estandar $FF81+, registros VIC-II/CIA publicados, matriz de
;  teclado documentada). Sin codigo derivado de la ROM original.
;
;  v0 implementa: RESET, pantalla+scroll, CHROUT, SCNKEY por IRQ,
;  GETIN, CHRIN (eco), STOP, UDTIM. El resto: stubs.
;  Arranca el BASIC (simbolo INIT del modulo BASIC).
; ============================================================

; --- RAM propia del kernal (fuera de las zonas que usa el BASIC) ---
KVPTR   = $C3
KCPTR   = $FB           ; puntero ZP a la RAM de color
KMSGFL  = $009D         ; flags de mensajes del kernal
KLDTND  = $0098         ; numero de ficheros abiertos
KDFLTN  = $0099         ; dispositivo de entrada por defecto
KDFLTO  = $009A         ; dispositivo de salida por defecto
KSTATUS = $0090         ; estado de E/S del kernal
KVERCK  = $0093         ; flag load(0)/verify(1)
KFNLEN  = $00B7         ; longitud del nombre de fichero
KLA     = $00B8         ; fichero logico actual
KSA     = $00B9         ; direccion secundaria actual
KFA     = $00BA         ; dispositivo actual
KFNADR  = $00BB         ; puntero al nombre (2 bytes)
KLAT    = $0259         ; tabla de ficheros logicos (10)
KFAT    = $0263         ; tabla de dispositivos (10)
KSAT    = $026D         ; tabla de direcciones secundarias (10)
KPNT    = $D1           ; puntero a linea actual de pantalla (lo/hi)
KCOL    = $D3           ; columna del cursor (0-39)
KNDX    = $C6           ; numero de teclas en bufer
KTIME   = $A0           ; reloj jiffy (3 bytes)
KBUF    = $0277         ; bufer de teclado (10 bytes)
KMATRIX = $02A0         ; estado anterior de la matriz (8 bytes)

SCREEN  = $0400
COLOR   = $D800

.org $E200              ; tras la continuacion del BASIC

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

; ------------------------------------------------------------
; RAMTAS ($FF87): limpiar areas de trabajo y reloj
; ------------------------------------------------------------
KRAMTAS:
        lda #$00
        tax
@rt1:   sta $0002,X     ; pagina cero (sin tocar el puerto 6510)
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
        lda #$06
        sta $D021       ; fondo azul
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
; limpiar pantalla y posicionar cursor en (0,0)
; ------------------------------------------------------------
KCLS:   ldx #$00
        lda #$20        ; espacio (codigo de pantalla)
@l1:    sta SCREEN,X
        sta SCREEN+$100,X
        sta SCREEN+$200,X
        sta SCREEN+$2E8,X
        inx
        bne @l1
        lda #$0E        ; azul claro por defecto
        sta KCOLOR
        ldx #$00
        lda KCOLOR
@l2:    sta COLOR,X
        sta COLOR+$100,X
        sta COLOR+$200,X
        sta COLOR+$2E8,X
        inx
        bne @l2
        lda #<SCREEN
        sta KPNT
        lda #>SCREEN
        sta KPNT+1
        lda #$00
        sta KCOL
        sta KROW
        ldx #$00
        lda #$80        ; toda fila es inicio de linea logica
@lk:    sta KLNK,X
        inx
        cpx #25
        bne @lk
        rts

; ------------------------------------------------------------
; CHROUT: imprime PETSCII en pantalla (A = caracter)
; conserva A, X, Y
; ------------------------------------------------------------
KCHROUT:
        php
        sei             ; el blink del IRQ no debe tocar mientras movemos
        pha
        txa
        pha
        tya
        pha
        ; --- apagar el cursor si esta encendido ---
        lda KBLON
        beq @nocur
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
        lda #20
        sta KBLCNT      ; reiniciar la cadencia al teclear
@nocur: tsx
        lda $0103,X     ; A original (pila: Y@+1, X@+2, A@+3, P@+4)
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
        inc KCOL
        lda KCOL
        cmp #40
        bcc @jd3
        lda #$00        ; wrap: la nueva fila es CONTINUACION
        sta KLNKV
        jmp @advrow
@cr:    lda #$80        ; CR explicito: la nueva fila INICIA linea logica
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
        ldx #39         ; limpiar ultima fila
        lda #$20
@s5:    sta SCREEN+960,X
        dex
        bpl @s5
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
        ldx #39         ; ultima fila de color = color actual
        lda KCOLOR
@cs5:   sta COLOR+960,X
        dex
        bpl @cs5
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
        ; --- SHIFT+C= conmuta el caso (deteccion de flanco) ---
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
        ldx KTMP2
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
@norpt: rts

KRPTSET: .byte $20,$1D,$9D,$11,$91,$14,$94

KTMP    = $02A8
KTMP2   = $02A9
KPREV   = $02B0         ; estado anterior para deteccion de flanco
KROWSEL: .byte $FE,$FD,$FB,$F7,$EF,$DF,$BF,$7F
KBITS:  .byte $01,$02,$04,$08,$10,$20,$40,$80

; tabla matriz->PETSCII (sin shift), fila=columna CIA, 8x8
KEYTAB:
        .byte $14,$0D,$1D,$00,$00,$00,$00,$11  ; DEL RET -> F7 F1 F3 F5 v
        .byte '3','W','A','4','Z','S','E',$00  ; ... LSHIFT
        .byte '5','R','D','6','C','F','T','X'
        .byte '7','Y','G','8','B','H','U','V'
        .byte '9','I','J','0','M','K','O','N'
        .byte '+','P','L','-','.',':','@',','
        .byte $5C,'*',';',$13,$00,'=',$5E,'/'  ; libra * ; HOME RSHIFT = flecha /
        .byte '1',$5F,$00,'2',' ',$00,'Q',$03  ; 1 <- CTRL 2 SPC C= Q STOP

; tabla con shift
KEYTABS:
        .byte $94,$0D,$9D,$00,$00,$00,$00,$91  ; INS RET <-cursor ... ^cursor
        .byte '#','W'+$80,'A'+$80,'$','Z'+$80,'S'+$80,'E'+$80,$00
        .byte '%','R'+$80,'D'+$80,'&','C'+$80,'F'+$80,'T'+$80,'X'+$80
        .byte $27,'Y'+$80,'G'+$80,'(','B'+$80,'H'+$80,'U'+$80,'V'+$80
        .byte ')','I'+$80,'J'+$80,'0','M'+$80,'K'+$80,'O'+$80,'N'+$80
        .byte '+','P'+$80,'L'+$80,'-','>','[','@','<'
        .byte $5C,'*',']',$93,$00,'=',$5E,'?'  ; shift+HOME = CLR
        .byte '!',$5F,$00,'"',' ',$00,'Q'+$80,$03  ; shift+2 = comillas

; tabla CTRL (CTRL+1..8 colores, +9/0 inverso on/off)
KEYTABT:
        .byte $00,$00,$00,$00,$00,$00,$00,$00
        .byte $1C,$00,$00,$9F,$00,$00,$00,$00
        .byte $9C,$00,$00,$1E,$00,$00,$00,$00
        .byte $1F,$00,$00,$9E,$00,$00,$00,$00
        .byte $12,$00,$00,$92,$00,$00,$00,$00
        .byte $00,$00,$00,$00,$00,$00,$00,$00
        .byte $00,$00,$00,$00,$00,$00,$00,$00
        .byte $90,$00,$00,$05,$00,$00,$00,$00
; tabla C= (Commodore+1..8 colores claros)
KEYTABC:
        .byte $00,$00,$00,$00,$00,$00,$00,$00
        .byte $96,$B3,$B0,$97,$AD,$AE,$B1,$00
        .byte $98,$B2,$AC,$99,$BC,$BB,$A3,$BD
        .byte $9A,$B7,$A5,$9B,$BF,$B4,$B8,$BE
        .byte $00,$A2,$B5,$00,$A7,$A1,$B9,$AA
        .byte $00,$AF,$B6,$00,$00,$00,$00,$00
        .byte $00,$00,$00,$00,$00,$00,$00,$00
        .byte $81,$00,$00,$95,$00,$00,$AB,$00

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

; PETSCII de los 16 codigos de color: CTRL+1..8 (0..7), C=+1..8 (8..15)
KCOLTAB:
        .byte $90,$05,$1C,$9F,$9C,$1E,$1F,$9E
        .byte $81,$95,$96,$97,$98,$99,$9A,$9B

KSHIFT  = $02AB

; ------------------------------------------------------------
; GETIN: saca un caracter del bufer (A=0, Z=1 si vacio)
; ------------------------------------------------------------
KGETIN: txa
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
KTMP3   = $02AA

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
KCHRIN: ldx KLLEN
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
        lda KPNT        ; recordar el inicio de la linea logica
        sta KLROW
        lda KPNT+1
        sta KLROW+1
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
        bcs @bucle
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
@sc0:   ; KVPTR = SCREEN + KSROW*40
        lda #<SCREEN
        sta KVPTR
        lda #>SCREEN
        sta KVPTR+1
        ldx KSROW
@mul:   beq @mulok
        clc
        lda KVPTR
        adc #40
        sta KVPTR
        bcc @m2
        inc KVPTR+1
@m2:    dex
        jmp @mul
@mulok: ; copiar fila de inicio: columnas KLSTRT2..39
        ldx #$00        ; X = longitud en KLINE
        ldy KLSTRT2
@cp1:   lda (KVPTR),Y
        and #$7F
        cmp #$20
        bcc @k1a        ; sc 0-31 -> PETSCII $41-$5F
        cmp #$40
        bcc @k1         ; sc $20-$3F: identico
        clc
        adc #$80        ; sc $40-$7E -> PETSCII $C0+ (mayus/graficos)
        jmp @k1
@k1a:   clc
        adc #$40
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
        and #$7F
        cmp #$20
        bcc @k2a        ; sc 0-31 -> PETSCII $41-$5F
        cmp #$40
        bcc @k2         ; sc $20-$3F: identico
        clc
        adc #$80        ; sc $40-$7E -> PETSCII $C0+ (mayus/graficos)
        jmp @k2
@k2a:   clc
        adc #$40
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

; apagar el cursor si esta invertido (auxiliar del editor)
KCUROFF:
        pha
        lda KBLON
        beq @no
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
        cli
@no:    pla
        rts

KLINE   = $033C         ; bufer de linea leida (cassette buffer, sin cinta)
KLLEN   = $02EA
KLPOS   = $02EB
KLSTART = $02EC
KLROW   = $02ED         ; (2 bytes)
KLLAST  = $02EF
KCOLOR  = $0286         ; color actual del cursor/texto
KGDCOL  = $0287         ; color guardado bajo el cursor (ubicacion C64)
KMBOT   = $0281         ; inicio de memoria (2 bytes)
KMTOP   = $0283         ; tope de memoria (2 bytes)

KRVS    = $02DF         ; flag de inverso ($00/$80)
KCTRL   = $02E0
KCBM    = $02E1
KCASE   = $02E2         ; flanco de SHIFT+C=
KLNK    = $02C0         ; tabla de enlace de lineas (25 bytes, $02C0-$02D8)
KROW    = $02D9         ; fila del cursor 0-24
KEDROW  = $02DA         ; fila donde empezo la entrada
KSROW   = $02DB         ; fila de inicio de la linea logica
KLSTRT2 = $02DC         ; columna inicial efectiva
KLNKV   = $02DD         ; valor a estampar en KLNK (inicio/continuacion)
KCNT    = $02DE
KSCR0   = $02F0
KSCRCNT = $02F1

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

; manejador por defecto del IRQ (destino inicial de $0314)
KIRQ:   lda $DC0D       ; reconocer la interrupcion del CIA1
        jsr KUDTIM
        jsr KSCNKEY
        ; --- parpadeo del cursor (solo si se espera entrada) ---
        lda KBLSW
        beq @nobl
        dec KBLCNT
        bne @nobl
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
        bne @nobl
@apag:  lda KGDCOL      ; apagar: restaurar el color guardado
        sta (KCPTR),Y
        lda #$00
        sta KBLON
@nobl:  pla
        tay
        pla
        tax
        pla
        rti

; BRK por defecto: restaurar y seguir (destino inicial de $0316)
KBRK:   pla
        tay
        pla
        tax
        pla
        rti


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

; NMI hardware: salva registros y despacha por ($0318)
KNMIENT:
        pha
        txa
        pha
        tya
        pha
        jmp ($0318)
; manejador por defecto del NMI: cartucho primero; si no,
; RUN/STOP-RESTORE = arranque en caliente
KNMI:   jsr KCBMCHK     ; ¿cartucho CBM80?
        bne @nocart
        jmp ($8002)     ; vector caliente del cartucho
@nocart:
        lda $DD0D       ; reconocer/limpiar la fuente NMI del CIA2
        jsr KSTOPRAW    ; ¿RUN/STOP pulsada? (Z=1 si si) - sin romper
        bne @ign
        ; --- arranque en caliente: programa intacto, vuelta a READY ---
        ldx #$FF
        txs             ; resetear la pila
        cli
        jsr KRESTOR     ; restaurar vectores de pagina 3
        jmp READY       ; entrada en caliente del BASIC
@ign:   pla             ; NMI espuria: restaurar y volver
        tay
        pla
        tax
        pla
        rti

; --- tabla ROM de vectores por defecto para pagina 3 ---
KVECTAB:
        .word KIRQ      ; $0314 CINV
        .word KBRK      ; $0316 CBINV
        .word KNMI      ; $0318 NMINV
        .word KSTUB     ; $031A IOPEN
        .word KSTUB     ; $031C ICLOSE
        .word KSTUB     ; $031E ICHKIN
        .word KSTUB     ; $0320 ICKOUT
        .word KSTUB     ; $0322 ICLRCH
        .word KCHRIN    ; $0324 IBASIN
        .word KCHROUT   ; $0326 IBSOUT
        .word KSTOP     ; $0328 ISTOP
        .word KGETIN    ; $032A IGETIN
        .word KSTUB     ; $032C ICLALL
        .word KSTUB     ; $032E USRCMD
        .word KSTUB     ; $0330 ILOAD
        .word KSTUB     ; $0332 ISAVE
KVECEND:

; RESTOR ($FF8A): restaurar los vectores por defecto
KRESTOR:
        ldx #$00
@l:     lda KVECTAB,X
        sta $0314,X
        inx
        cpx #(KVECEND-KVECTAB)
        bne @l
        rts

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

KBLCNT  = $02AC
KBLON   = $02AD
KBLSW   = $02AE
KLCOL   = $02AF
KLMASK  = $02B8
KLIDX   = $02B9
KRPT    = $02BA

KSTUB:  clc
        rts

; ------------------------------------------------------------
; Rutinas de la tabla de saltos que no dependen del bus IEC.
; ------------------------------------------------------------
; SETMSG ($FF90): A = flags de mensajes del kernal
KSETMSG:
        sta KMSGFL
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
        ; KPNT = SCREEN + fila*40
        lda #<SCREEN
        sta KPNT
        lda #>SCREEN
        sta KPNT+1
        cpx #$00
        beq @done
@m:     clc
        lda KPNT
        adc #40
        sta KPNT
        bcc @m2
        inc KPNT+1
@m2:    dex
        bne @m
@done:  rts
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
        lda #$00
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
        ; (fase 2: si KFA es serie, abrir el canal por el bus)
        clc
        rts
; CLOSE ($FFC3): A = fichero logico a cerrar
KCLOSE: jsr KFINDFL
        bcs @hay
        clc             ; no abierto: nada que hacer
        rts
@hay:   ; compactar las tablas desde X
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
        clc
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
        ; (fase 2: si serie, enviar TALK + direccion secundaria)
        clc
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
        ; (fase 2: si serie, enviar LISTEN + direccion secundaria)
        clc
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
@go:    jsr KOPEN
        bcs @err
        rts
@err:   jmp KIOERR      ; A = codigo de error del kernal -> mensaje largo
; CLOSE lfn
BCLOSE: jsr GETBYT      ; fichero logico -> X
        txa
        jsr KCLOSE
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
        lda #$00        ; 0 = LOAD (1 seria VERIFY)
        sta KVERCK
        ; (handshake pendiente) JSR KLOAD aqui, luego relink del BASIC
        rts
; SAVE ["nombre"][,dispositivo][,secundaria]
BSAVE:  jsr BPARSE
        ; (handshake pendiente) JSR KSAVE aqui
        rts

; ------------------------------------------------------------
; KIOERR: imprime un mensaje de error de E/S largo (estilo Commodore)
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
KIOMSG: .word KIOM1,KIOM2,KIOM3,KIOM4,KIOM5
        .word KIOM6,KIOM7,KIOM8,KIOM9
KIOM1:  .byte "TOO MANY FILES",0
KIOM2:  .byte "FILE OPEN",0
KIOM3:  .byte "FILE NOT OPEN",0
KIOM4:  .byte "FILE NOT FOUND",0
KIOM5:  .byte "DEVICE NOT PRESENT",0
KIOM6:  .byte "NOT INPUT FILE",0
KIOM7:  .byte "NOT OUTPUT FILE",0
KIOM8:  .byte "MISSING FILE NAME",0
KIOM9:  .byte "ILLEGAL DEVICE NUMBER",0


; ------------------------------------------------------------
; SYS (delta C64): evalua la expresion con las rutinas del BASIC
; y salta a la direccion; un RTS alli devuelve al BASIC.
; ------------------------------------------------------------
KSYS:   jsr FRMNUM      ; evaluar la expresion tras SYS
        jsr GETADR      ; convertir a entero en POKER
        jmp (POKER)     ; el RTS del usuario vuelve a NEWSTT

; ------------------------------------------------------------
; Tabla de saltos estandar documentada
; ------------------------------------------------------------
; ------------------------------------------------------------
; Trampolines de compatibilidad en las direcciones INTERNAS
; documentadas que muchos cartuchos y programas llaman directamente
; (en vez de la tabla de saltos). Honran una interfaz publicada;
; no contienen codigo derivado de la ROM original.
; ------------------------------------------------------------
.org $FD15
        jmp KRESTOR     ; RESTOR interno
.org $FD50
        jmp KRAMTAS     ; RAMTAS interno
.org $FDA3
        jmp KIOINIT     ; IOINIT interno
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
        jmp KSTUB       ; $FF93 SECOND
        jmp KSTUB       ; $FF96 TKSA
        jmp KMEMTOP     ; $FF99 MEMTOP
        jmp KMEMBOT     ; $FF9C MEMBOT
        jmp KSCNKEY     ; $FF9F SCNKEY
        jmp KSTUB       ; $FFA2 SETTMO
        jmp KSTUB       ; $FFA5 ACPTR
        jmp KSTUB       ; $FFA8 CIOUT
        jmp KSTUB       ; $FFAB UNTLK
        jmp KSTUB       ; $FFAE UNLSN
        jmp KSTUB       ; $FFB1 LISTEN
        jmp KSTUB       ; $FFB4 TALK
        jmp KSTUB       ; $FFB7 READST
        jmp KSETLFS     ; $FFBA SETLFS
        jmp KSETNAM     ; $FFBD SETNAM
        jmp KOPEN       ; $FFC0 OPEN
        jmp KCLOSE      ; $FFC3 CLOSE
        jmp KCHKIN      ; $FFC6 CHKIN
        jmp KCHKOUT     ; $FFC9 CHKOUT
        jmp KCLRCHN     ; $FFCC CLRCHN
        jmp ($0324)     ; $FFCF CHRIN  (IBASIN)
        jmp ($0326)     ; $FFD2 CHROUT (IBSOUT)
        jmp KSTUB       ; $FFD5 LOAD
        jmp KSTUB       ; $FFD8 SAVE
        jmp KSETTIM     ; $FFDB SETTIM
        jmp KRDTIM      ; $FFDE RDTIM
        jmp ($0328)     ; $FFE1 STOP  (ISTOP)
        jmp ($032A)     ; $FFE4 GETIN (IGETIN)
        jmp KCLALL      ; $FFE7 CLALL
        jmp KUDTIM      ; $FFEA UDTIM
        jmp KSCREEN     ; $FFED SCREEN
        jmp KPLOT       ; $FFF0 PLOT
        jmp KIOBASE     ; $FFF3 IOBASE

.org $FFFA
        .word KNMIENT   ; NMI
        .word KRESET    ; RESET
        .word KIRQENT   ; IRQ/BRK
