; main.s - 4Forth page 1: cartridge header, start-up, the RAM trampolines to page 2, the interrupt hook
; (ANSWER breaks a running word, OFF switches off) and errors. The start-up and the trampolines are
; EASM's (from EBASIC).
; Copyright (C) 2026 Santiago Crespo
; SPDX-License-Identifier: GPL-3.0-or-later

	.include "shared.inc"
	.area	CODE

	.db	0x55, 0xAA, 0x59, 0x45	; autostart signature
	jp	cold			; 8004
	.ascii	"4Forth 1.0"		; 8007-8010

cold:	di
	ld	sp, #STACK
	ld	hl, #ramsrc
	ld	de, #RAMCODE
	ld	bc, #ramsrc_end-ramsrc
	ldir
	ld	hl, #VARS		; all variables
	ld	de, #VARS+1
	ld	bc, #VARS_END-VARS-1
	ld	(hl), #0
	ldir
	call	lcdinit
	ld	a, #1
	ld	(CAPS), a		; caps lock on: the words are upper case
	call	accents
	call	setled
	call	txtnew
	call	fcold
	ld	hl, (0x0039)		; enable the firmware ISR only if 0038 is JP 0119 and the hook is 0033
	ld	de, #0x0119
	or	a
	sbc	hl, de
	jr	nz, 3$
	ld	hl, (FW_HOOK)
	ld	de, #0x0033
	or	a
	sbc	hl, de
	jr	nz, 3$
	ld	a, #0xFF
	ld	(FW_KEYCODE), a
	ld	a, #0xD0
	ld	(FW_KEYST), a
	ld	hl, #FW_DIRTY
	ld	b, #8
4$:	ld	(hl), #0
	inc	hl
	djnz	4$
	ld	hl, #R_HOOK
	ld	(FW_HOOK), hl
	ld	a, #1
	ld	(ISRON), a
	im	1
	ei
3$:	call	CLS
	ld	hl, #banner
	call	PRINTSTR
	call	unused
	call	PRDEC
	ld	hl, #freetxt
	call	PRINTSTR
	jp	cmdloop

banner:	.ascii	"4Forth 1.0"
	.db	CR, LF
	.ascii	"after Hardy's Firth"
	.db	CR, LF, 0
freetxt:
	.asciz	" bytes free"

;error - abandon the current operation with error A: the handler at ERRJP runs with SP = ERRSP.
error::	ld	(ERRNO), a
	ld	sp, (ERRSP)
	ld	hl, (ERRJP)
	jp	(hl)

; ANSWER while a word runs (from the hook: page 1 mapped, SP = STACK, interrupts off)
brkerr:	call	waitrel
	ld	a, #E_BREAK
	jr	error

;---------------------------------------------------------------- code copied to RAMCODE
; Page switching must run from RAM: the code of the page being left disappears with the OUT.
ramsrc:
; HL = page-2 address to call, the caller's HL on the stack. All other registers pass both ways.
rfar:	ld	(RAMCODE+rfar_t-ramsrc+1), hl
	pop	hl
	push	af
	ld	a, #PAGE2
	out	(0x03), a
	pop	af
rfar_t:	call	0
	push	af
	ld	a, #PAGE1
	out	(0x03), a
	pop	af
	ret
; The same from page 2 to a page-1 routine.
rcall1:	ld	(RAMCODE+rcall1_t-ramsrc+1), hl
	pop	hl
	push	af
	ld	a, #PAGE1
	out	(0x03), a
	pop	af
rcall1_t:	call	0
	push	af
	ld	a, #PAGE2
	out	(0x03), a
	pop	af
	ret
; Interrupt hook, called by the firmware ISR (registers already saved). While Forth runs, ANSWER
; (column 7, port 0x10 bit 6) breaks it and OFF (port 0x11 bit 1) held for two interrupts switches
; the unit off, so that both work in a loop that never reads the keyboard. In RAM because either
; page may be mapped when the interrupt comes.
hook:	ld	a, (RUNNING)
	or	a
	ret	z
	ld	a, #0x80
	out	(0x10), a
	nop
	in	a, (0x11)
	ld	c, a
	in	a, (0x10)
	ld	b, a
	xor	a
	out	(0x10), a
	ld	hl, #OFFCNT
	bit	1, c
	jr	nz, 3$
	ld	a, (OFFARM)		; OFF held since power-on does not count
	or	a
	jr	z, 4$
	inc	(hl)
	ld	a, (hl)
	cp	#2
	jr	c, 4$
	di				; the firmware's own power-off sequence
	ld	a, #0x01
	out	(0x12), a
5$:	halt
	jr	5$
3$:	ld	(hl), #0
	ld	a, #1
	ld	(OFFARM), a
4$:	bit	6, b
	ret	nz
	xor	a
	ld	(RUNNING), a
	ld	a, #PAGE1
	out	(0x03), a
	ld	sp, #STACK
	jp	brkerr
ramsrc_end:

R_FAR == RAMCODE+rfar-ramsrc
R_CALL1 == RAMCODE+rcall1-ramsrc
R_HOOK == RAMCODE+hook-ramsrc

	.ifgt	VARS_END-VARS-256		; the variables fit in their page
	.error	1
	.endif
	.ifgt	ramsrc_end-ramsrc-0x80		; and the RAM code in its 128 bytes
	.error	1
	.endif

; Entry point that runs slot n of the page-2 jump table
.macro	FAR	name, n
name::	push	hl
	ld	hl, #0x8000+3*n
	jp	R_FAR
.endm
	FAR	help, S_HELP
