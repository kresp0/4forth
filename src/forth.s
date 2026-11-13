; forth.s - 4Forth page 1: the Forth kernel. The machine model is Firth's (J. Hardy): the top of the
; data stack in BC, the rest of the data stack through IX (growing up), the return stack on SP with
; the instruction pointer on top of it, and IY holding the address of NEXT. Direct threading: a code
; word starts with machine code, a colon word with CALL docol (Firth's RST 08 lands in the Genio's
; ROM). Header: [link][flags+length][name], names in upper case. The dictionary in ROM ends at
; ROMLAST; the words defined by the user follow from DICT0 in RAM. The outer interpreter and the
; compiler are in assembly here; README.md explains what was kept from Firth and what is new.
; Copyright (C) 2026 Santiago Crespo
; Parts derived from Firth, Copyright (C) John Hardy, GPL-3.0 (third_party/firth/LICENSE)
; SPDX-License-Identifier: 0BSD AND GPL-3.0-only

	.include "shared.inc"
	.area	CODE

LINK = 0
; A header; the name follows as .ascii (tools/gen_help.py reads both and checks the length)
.macro	HEAD	len, flags
	.dw	LINK
LINK = . - 2
	.db	len+flags
.endm
.macro	NEXT
	jp	(iy)
.endm
; push BC on the data stack (BC itself is then the new top)
.macro	PDUP
	ld	0(ix), c
	ld	1(ix), b
	inc	ix
	inc	ix
.endm
; BC = the cell below the top (the old top is dropped)
.macro	PDROP
	dec	ix
	dec	ix
	ld	c, 0(ix)
	ld	b, 1(ix)
.endm
; HL = the cell below the top, removed (BC stays)
.macro	POPHL
	dec	ix
	dec	ix
	ld	l, 0(ix)
	ld	h, 1(ix)
.endm
.macro	POPDE
	dec	ix
	dec	ix
	ld	e, 0(ix)
	ld	d, 1(ix)
.endm

;---------------------------------------------------------------- inner interpreter

; NEXT: the instruction pointer is on top of the return stack
next::	pop	hl
	ld	e, (hl)
	inc	hl
	ld	d, (hl)
	inc	hl
	push	hl
	ex	de, hl
	jp	(hl)

; Code field of a colon word: CALL docol pushed the address of its body, the new IP
docol::	ld	hl, #-RSLIM
	add	hl, sp
	jp	nc, rsfull
	NEXT
rsfull:	ld	a, #E_RFULL
	jp	error

; CREATE and VARIABLE: the address of the body
dovar:	pop	hl
	PDUP
	ld	b, h
	ld	c, l
	NEXT
; CONSTANT: the value in the body
docon:	pop	hl
	PDUP
	ld	c, (hl)
	inc	hl
	ld	b, (hl)
	NEXT
; DOES>: the child's CALL pushed its body, the CALL dodoes after DOES> the thread to run
dodoes:	pop	hl
	pop	de
	PDUP
	ld	b, d
	ld	c, e
	push	hl
	NEXT

;fcold - IY and an empty dictionary and data stack. Destroys A,H,L,F.
fcold::	ld	iy, #next
	ld	ix, #DS0
	ld	hl, #10
	ld	(BASE), hl
	ld	hl, #xret
	ld	(XTSLOT+2), hl
empty:	ld	hl, #ROMLAST
	ld	(LATEST), hl
	ld	hl, #DICT0
	ld	(HERE), hl
	ret

;execxt - run the word HL from assembly, with the top of stack in TOSV. Destroys all but IX, IY.
execxt::
	ld	(XTSLOT), hl
	ld	hl, #XTSLOT
	push	hl
	ld	bc, (TOSV)
	NEXT
xret:	ld	(TOSV), bc
	pop	hl
	ret

; Data stack pointer within DS0..DSLIM, else an error (used where loops branch back)
dschk:	push	ix
	pop	hl
	ld	de, #-(DSLIM+1)
	add	hl, de
	ret	nc
dsfull:	ld	a, #E_FULL
	jp	error

;---------------------------------------------------------------- runtime words (no headers)

xlit:	PDUP
	pop	hl
	ld	c, (hl)
	inc	hl
	ld	b, (hl)
	inc	hl
	push	hl
	NEXT
xbran:	call	dschk
xbran1:	pop	hl
	ld	e, (hl)
	inc	hl
	ld	d, (hl)
	push	de
	NEXT
xqbran:	ld	a, b
	or	c
	PDROP
	jr	z, xbran
xskip:	pop	hl			; skip the inline cell
	inc	hl
	inc	hl
	push	hl
	NEXT

; DO: the return stack holds (from the top) IP, index-limit', limit' = limit xor 8000h, the address
; after LOOP (where LEAVE goes); LOOP ends when adding to index-limit' overflows.
xqdo:	POPHL				; limit
	push	hl
	or	a
	sbc	hl, bc
	pop	hl
	jr	nz, xdo1
	PDROP				; start = limit: skip the loop
	jr	xbran1
xdo:	POPHL
xdo1:	ex	(sp), hl		; HL = limit, BC = start; HL = IP, limit on the stack
	ld	e, (hl)
	inc	hl
	ld	d, (hl)
	inc	hl
	ex	(sp), hl		; IP+2 on the stack, HL = limit
	ex	de, hl			; HL = exit, DE = limit
	ex	(sp), hl		; exit on the stack, HL = IP+2
	push	hl
	ld	a, d
	xor	#0x80
	ld	d, a			; DE = limit'
	ld	h, b
	ld	l, c
	or	a
	sbc	hl, de			; HL = start - limit'
	ex	(sp), hl		; HL = IP+2
	ex	de, hl			; HL = limit', DE = IP+2
	ex	(sp), hl		; limit' on the stack, HL = start - limit'
	push	hl
	push	de
	PDROP
	NEXT
xloop:	ld	de, #1
	jr	xploop1
xploop:	ld	d, b
	ld	e, c
	PDROP
xploop1:
	pop	hl			; IP
	ex	(sp), hl		; HL = index - limit'
	or	a
	adc	hl, de
	jp	pe, 1$			; overflow: the end
	ex	(sp), hl
	push	hl
	call	dschk
	jp	xbran1
1$:	pop	hl			; IP
	pop	de
	pop	de
	push	hl
	jp	xskip

xdotq:	pop	hl			; ." : print the inline counted string
	call	typec
	push	hl
	NEXT
xsq:	pop	hl			; S" : its address and length
	PDUP
	ld	e, (hl)
	ld	d, #0
	inc	hl
	ld	b, h
	ld	c, l
	PDUP
	ld	b, d
	ld	c, e
	add	hl, de
	push	hl
	NEXT
xabq:	pop	hl			; ABORT" : error with the inline text if the flag is true
	ld	a, b
	or	c
	PDROP
	jr	nz, 1$
	ld	e, (hl)
	ld	d, #0
	inc	hl
	add	hl, de
	push	hl
	NEXT
1$:	ld	(ERRWA), hl
	ld	a, #E_ABORTQ
	jp	error
xdoes:	pop	hl			; (DOES>): the last word runs the code after DOES>, then EXIT
	ex	de, hl
	push	bc
	ld	hl, (LATEST)
	call	hdrxt
	pop	bc
	inc	hl			; past the CALL opcode of CREATE
	ld	(hl), e
	inc	hl
	ld	(hl), d
	NEXT

; Print the counted string at HL; HL ends after it. Destroys A,D,E,F.
typec::	ld	e, (hl)
	inc	hl
	ld	d, #0
; Print DE characters from HL with EMIT. Destroys A,D,E,F.
typen::	ld	a, d
	or	e
	ret	z
	ld	a, (hl)
	inc	hl
	call	emit
	dec	de
	jr	typen

;emit - EMIT's character A: 10 or 13 new line, 8 back, 7 beep, 12 clear; any other code goes into
; the cell as it is (0-6 and 15: the CGRAM glyphs). Keeps everything but F.
emit::	push	af
	push	bc
	push	de
	push	hl
	cp	#CR
	jr	nz, 1$
	ld	a, #LF
1$:	cp	#LF
	jr	nz, 2$
	call	newline
	jr	3$
2$:	cp	#BS
	jr	z, 4$
	cp	#7
	jr	z, 4$
	cp	#12
	jr	z, 4$
	call	wcell
	jr	3$
4$:	call	PUTCHAR
3$:	pop	hl
	pop	de
	pop	bc
	pop	af
	ret

;---------------------------------------------------------------- assembly helpers

; A in upper case (ASCII letters)
upper::	cp	#'a
	ret	c
	cp	#123
	ret	nc
	sub	#0x20
	ret

; HL = xt of the header at HL. Destroys A,F.
hdrxt::	inc	hl
	inc	hl
	ld	a, (hl)
	and	#F_LEN
	inc	a
	add	a, l
	ld	l, a
	ret	nc
	inc	h
	ret

;comma - compile HL. ccomma - compile A. Destroy A,D,E,H,L,F.
comma::	ex	de, hl
	ld	hl, (HERE)
	ld	(hl), e
	inc	hl
	ld	(hl), d
	inc	hl
	jr	setdp
ccomma::
	ld	hl, (HERE)
	ld	(hl), a
	inc	hl
; HERE = HL, below DICTLIM. Destroys A,D,E,F.
setdp:	ld	de, #DICTLIM
	ld	a, h
	cp	#0xC0			; (a negative ALLOT below the RAM is also an error)
	jr	c, 1$
	push	hl
	or	a
	sbc	hl, de
	pop	hl
	jr	nc, 1$
	ld	(HERE), hl
	ret
1$:	ld	a, #E_DICT
	jp	error

; Compile a call to code HL (CALL opcode and address). Destroys A,D,E,H,L,F.
ccall:	ld	a, #0xCD
	push	hl
	call	ccomma
	pop	hl
	jr	comma

;pname - the next name in the source: HL = its address, B = its length, Z if there is none.
; Characters up to 32 are spaces. >IN goes past the name and one space. Destroys A,C,D,E,F.
pname::	call	srcpos
1$:	ld	a, c
	or	a
	ret	z			; (B = 0)
	ld	a, (hl)
	cp	#0x21
	jr	nc, 2$
	inc	hl
	dec	c
	jr	1$
2$:	ld	a, #0x20
	jr	parse1
;parse - the text up to the character A (or the end), from >IN: HL, B = address and length, Z if
; empty. >IN goes past the delimiter. Destroys A,C,D,E,F.
parse::	push	af
	call	srcpos
	pop	af
parse1:	ld	b, #0
	ld	e, a
	push	hl
1$:	ld	a, c
	or	a
	jr	z, 3$
	ld	a, (hl)
	inc	hl
	dec	c
	cp	e
	jr	z, 2$
	ld	a, e			; a space ends a name at any character up to 32
	cp	#0x20
	jr	nz, 4$
	dec	hl
	ld	a, (hl)
	inc	hl
	cp	#0x21
	jr	c, 2$
4$:	inc	b
	jr	1$
2$:	ld	a, #1			; the delimiter counts for >IN
	.db	0x0E			; (ld c, #n: skips the xor)
3$:	xor	a
	pop	hl
	push	hl
	add	a, b
	ld	e, a
	ld	d, #0
	add	hl, de
	ld	de, (SRCA)
	or	a
	sbc	hl, de
	ld	(TOIN), hl
	pop	hl
	ld	a, b
	or	a
	ret

; HL = SRCA + >IN, C = characters left (0 if >IN is past the end). Destroys A,D,E,F.
srcpos::	ld	hl, (SRCL)
	ld	de, (TOIN)
	or	a
	sbc	hl, de
	ld	c, l
	jr	nc, 1$
	ld	c, #0
1$:	ld	hl, (SRCA)
	add	hl, de
	ret

; The next name, which must be there (else "Name missing"). HL, B as pname.
pnamer::	call	pname
	ret	nz
	ld	a, #E_NAME
	jp	error

;find - the word named by HL, B characters (any case): DE = its header, A = its flags byte and NC;
; carry if there is none. Hidden words are not found. Destroys C,F.
find::	ld	de, (LATEST)
1$:	ld	a, d
	or	e
	scf
	ret	z
	push	de
	inc	de
	inc	de
	ld	a, (de)
	and	#F_HIDE+F_LEN
	cp	b
	jr	nz, 4$
	push	hl
	push	bc
2$:	inc	de
	ld	a, (hl)
	call	upper
	ld	c, a
	ld	a, (de)
	cp	c
	jr	nz, 3$
	inc	hl
	djnz	2$
	pop	bc
	pop	hl
	pop	de
	push	de
	inc	de
	inc	de
	ld	a, (de)
	pop	de
	or	a
	ret
3$:	pop	bc
	pop	hl
4$:	pop	de
	ex	de, hl
	ld	a, (hl)
	inc	hl
	ld	h, (hl)
	ld	l, a
	ex	de, hl
	jr	1$

; The next name must be a word: HL = its xt, A = its flags. Destroys B,C,D,E,F.
tick:	call	pnamer
	ld	(ERRWA), hl
	ld	a, b
	ld	(ERRWL), a
	call	find
	ld	a, #E_UNDEF
	jp	c, error
	ex	de, hl
	push	hl
	inc	hl
	inc	hl
	ld	a, (hl)
	pop	hl
	push	af
	call	hdrxt
	pop	af
	ret

;number - the number named by HL, B characters, in BASE: HL = its value and NC, else carry.
; Accepts a sign, the prefixes $ (hex), # (decimal), % (binary) and 'c' (a character).
; Destroys A,B,C,D,E,F.
number::
	ld	a, (BASE)
	ld	c, a
	ld	a, b
	cp	#3
	jr	nz, 1$
	ld	a, (hl)
	cp	#0x27
	jr	nz, 1$
	inc	hl
	inc	hl
	ld	a, (hl)
	cp	#0x27
	scf
	ret	nz
	dec	hl
	ld	l, (hl)
	ld	h, #0
	or	a
	ret
1$:	ld	a, (hl)
	ld	d, #16
	cp	#'$
	jr	z, 2$
	ld	d, #10
	cp	#'#
	jr	z, 2$
	ld	d, #2
	cp	#'%
	jr	nz, 3$
2$:	ld	c, d
	inc	hl
	dec	b
3$:	ld	a, b
	or	a
	scf
	ret	z
	ld	a, (hl)
	cp	#'-
	ld	a, #0
	jr	nz, 4$
	inc	hl
	dec	b
	scf
	ret	z			; "-" alone
	dec	a
4$:	push	af			; A = FF: negative
	ld	de, #0
5$:	ld	a, (hl)
	call	upper
	sub	#'0
	jr	c, 9$
	cp	#10
	jr	c, 6$
	sub	#17
	jr	c, 9$
	add	a, #10
6$:	cp	c
	jr	nc, 9$
	push	hl			; DE = DE*C + A
	push	bc
	ld	l, a
	ld	h, #0
	ld	b, c
7$:	add	hl, de
	djnz	7$
	ex	de, hl
	pop	bc
	pop	hl
	inc	hl
	djnz	5$
	pop	af
	ex	de, hl
	or	a
	ret	z
	xor	a			; negative
	sub	l
	ld	l, a
	sbc	a, a
	sub	h
	ld	h, a
	or	a
	ret
9$:	pop	af
	scf
	ret

; Push HL on the data stack while the interpreter runs (top of stack in TOSV). Destroys B,C.
tpush:	ld	bc, (TOSV)
	PDUP
	ld	(TOSV), hl
	ret

;stkchk - errors for an empty or full data stack. Destroys A,D,E,H,L,F.
stkchk::
	push	ix
	pop	hl
	ld	de, #-DS0
	add	hl, de
	ld	a, #E_EMPTY
	jp	nc, error
	jp	dschk

;interp - interpret the source (SRCA, SRCL from >IN). Destroys all but IX, IY.
interp::
1$:	call	pname
	ret	z
	ld	(ERRWA), hl
	ld	a, b
	ld	(ERRWL), a
	call	find
	jr	c, 5$
	ld	c, a			; a word: compile it, unless it is immediate
	ex	de, hl
	call	hdrxt
	ld	a, (STATE)
	or	a
	jr	z, 3$
	bit	7, c
	jr	nz, 4$
	call	comma
	jr	1$
3$:	bit	5, c
	ld	a, #E_COMP
	jp	nz, error
4$:	call	execxt
	call	stkchk
	jr	1$
5$:	call	number			; else a number
	ld	a, #E_UNDEF
	jp	c, error
	ld	a, (STATE)
	or	a
	jr	z, 6$
	push	hl
	ld	hl, #xlit
	call	comma
	pop	hl
	call	comma
	jr	1$
6$:	call	tpush
	call	stkchk
	jr	1$

;mkhead - a header for the next name (hidden while it is defined). HERE and LATEST are kept for an
; error. Destroys all but BC, IX, IY.
mkhead:	push	bc
	call	pnamer
	ld	a, b
	cp	#F_LEN+1
	ld	a, #E_NAME
	jp	nc, error
	ld	de, (HERE)
	ld	(DPSAVE), de
	ld	de, (LATEST)
	ld	(LPSAVE), de
	push	hl
	ld	hl, (HERE)		; room for the header and a little code
	ld	e, b
	ld	d, #0
	add	hl, de
	ld	de, #8
	add	hl, de
	call	setdp
	ld	hl, (DPSAVE)
	ld	(HERE), hl
	ld	hl, (LATEST)
	call	comma
	ld	hl, (DPSAVE)
	ld	(LATEST), hl
	ld	a, b
	or	#F_HIDE
	call	ccomma
	pop	hl
1$:	ld	a, (hl)
	call	upper
	push	hl
	call	ccomma
	pop	hl
	inc	hl
	djnz	1$
	pop	bc
	ret

; Show the word at LATEST
reveal:	ld	hl, (LATEST)
	inc	hl
	inc	hl
	res	6, (hl)
	ret

;---------------------------------------------------------------- the words in ROM
; Stack effects: ( before -- after ); the guide (help.txt) has one page for each word.

	HEAD	3, 0
	.ascii	"DUP"
w_dup:	PDUP
	NEXT
	HEAD	4, 0
	.ascii	"DROP"
w_drop:	PDROP
	NEXT
	HEAD	4, 0
	.ascii	"SWAP"
w_swap:	ld	l, -2(ix)
	ld	h, -1(ix)
	ld	-2(ix), c
	ld	-1(ix), b
	ld	b, h
	ld	c, l
	NEXT
	HEAD	4, 0
	.ascii	"OVER"
w_over:	ld	l, -2(ix)
	ld	h, -1(ix)
	PDUP
	ld	b, h
	ld	c, l
	NEXT
	HEAD	3, 0
	.ascii	"ROT"
w_rot:	ld	l, -4(ix)		; a b c -- b c a
	ld	h, -3(ix)
	ld	e, -2(ix)
	ld	d, -1(ix)
	ld	-4(ix), e
	ld	-3(ix), d
	ld	-2(ix), c
	ld	-1(ix), b
	ld	b, h
	ld	c, l
	NEXT
	HEAD	4, 0
	.ascii	"-ROT"
w_mrot:	ld	l, -4(ix)		; a b c -- c a b
	ld	h, -3(ix)
	ld	e, -2(ix)
	ld	d, -1(ix)
	ld	-4(ix), c
	ld	-3(ix), b
	ld	-2(ix), l
	ld	-1(ix), h
	ld	b, d
	ld	c, e
	NEXT
	HEAD	3, 0
	.ascii	"NIP"
w_nip:	dec	ix
	dec	ix
	NEXT
	HEAD	4, 0
	.ascii	"TUCK"
w_tuck:	ld	l, -2(ix)		; a b -- b a b
	ld	h, -1(ix)
	ld	-2(ix), c
	ld	-1(ix), b
	ld	0(ix), l
	ld	1(ix), h
	inc	ix
	inc	ix
	NEXT
	HEAD	4, 0
	.ascii	"?DUP"
w_qdup:	ld	a, b
	or	c
	jr	z, 1$
	PDUP
1$:	NEXT
	HEAD	4, 0
	.ascii	"PICK"
w_pick:	ld	h, b
	ld	l, c
	add	hl, hl
	ex	de, hl
	push	ix
	pop	hl
	or	a
	sbc	hl, de
	dec	hl
	ld	b, (hl)
	dec	hl
	ld	c, (hl)
	NEXT
	HEAD	4, 0
	.ascii	"2DUP"
w_2dup:	ld	l, -2(ix)
	ld	h, -1(ix)
	PDUP
	ld	0(ix), l
	ld	1(ix), h
	inc	ix
	inc	ix
	NEXT
	HEAD	5, 0
	.ascii	"2DROP"
w_2drop:
	dec	ix
	dec	ix
	PDROP
	NEXT
	HEAD	5, 0
	.ascii	"2SWAP"
w_2swap:
	ld	l, -6(ix)		; a b c d -- c d a b
	ld	h, -5(ix)
	ld	e, -2(ix)
	ld	d, -1(ix)
	ld	-6(ix), e
	ld	-5(ix), d
	ld	-2(ix), l
	ld	-1(ix), h
	ld	l, -4(ix)
	ld	h, -3(ix)
	ld	-4(ix), c
	ld	-3(ix), b
	ld	b, h
	ld	c, l
	NEXT
	HEAD	5, 0
	.ascii	"2OVER"
w_2over:
	ld	l, -6(ix)
	ld	h, -5(ix)
	ld	e, -4(ix)
	ld	d, -3(ix)
	PDUP
	ld	0(ix), l
	ld	1(ix), h
	inc	ix
	inc	ix
	ld	b, d
	ld	c, e
	NEXT
	HEAD	5, 0
	.ascii	"DEPTH"
w_depth:
	push	ix
	pop	hl
	ld	de, #-DS0
	add	hl, de
	srl	h
	rr	l
	PDUP
	ld	b, h
	ld	c, l
	NEXT
	HEAD	2, F_COMP
	.ascii	">R"
w_tor:	pop	hl
	push	bc
	push	hl
	PDROP
	NEXT
	HEAD	2, F_COMP
	.ascii	"R>"
w_rfrom:
	pop	hl
	PDUP
	pop	bc
	push	hl
	NEXT
	HEAD	2, F_COMP
	.ascii	"R@"
w_rat:	pop	hl
	pop	de
	push	de
	push	hl
	PDUP
	ld	b, d
	ld	c, e
	NEXT

; arithmetic
	HEAD	1, 0
	.ascii	"+"
w_plus:	POPHL
	add	hl, bc
	ld	b, h
	ld	c, l
	NEXT
	HEAD	1, 0
	.ascii	"-"
w_minus:
	POPHL
	or	a
	sbc	hl, bc
	ld	b, h
	ld	c, l
	NEXT
	HEAD	2, 0
	.ascii	"1+"
w_1plus:
	inc	bc
	NEXT
	HEAD	2, 0
	.ascii	"1-"
w_1minus:
	dec	bc
	NEXT
	HEAD	2, 0
	.ascii	"2+"
w_2plus:
	inc	bc
	inc	bc
	NEXT
	HEAD	2, 0
	.ascii	"2-"
w_2minus:
	dec	bc
	dec	bc
	NEXT
	HEAD	2, 0
	.ascii	"2*"
w_2star:
	sla	c
	rl	b
	NEXT
	HEAD	2, 0
	.ascii	"2/"
w_2slash:
	sra	b
	rr	c
	NEXT
	HEAD	5, 0
	.ascii	"CELLS"
	jr	w_2star
	HEAD	5, 0
	.ascii	"CELL+"
	jr	w_2plus
	HEAD	6, 0
	.ascii	"NEGATE"
w_negate:
	xor	a
	sub	c
	ld	c, a
	sbc	a, a
	sub	b
	ld	b, a
	NEXT
	HEAD	3, 0
	.ascii	"ABS"
w_abs:	bit	7, b
	jr	nz, w_negate
	NEXT
	HEAD	3, 0
	.ascii	"AND"
w_and:	POPHL
	ld	a, h
	and	b
	ld	b, a
	ld	a, l
	and	c
	ld	c, a
	NEXT
	HEAD	2, 0
	.ascii	"OR"
w_or:	POPHL
	ld	a, h
	or	b
	ld	b, a
	ld	a, l
	or	c
	ld	c, a
	NEXT
	HEAD	3, 0
	.ascii	"XOR"
w_xor:	POPHL
	ld	a, h
	xor	b
	ld	b, a
	ld	a, l
	xor	c
	ld	c, a
	NEXT
	HEAD	6, 0
	.ascii	"INVERT"
w_invert:
	ld	a, b
	cpl
	ld	b, a
	ld	a, c
	cpl
	ld	c, a
	NEXT
	HEAD	6, 0
	.ascii	"LSHIFT"
w_lshift:
	POPHL
	ld	a, c
1$:	or	a
	jr	z, 2$
	add	hl, hl
	dec	a
	jr	1$
2$:	ld	b, h
	ld	c, l
	NEXT
	HEAD	6, 0
	.ascii	"RSHIFT"
w_rshift:
	POPHL
	ld	a, c
1$:	or	a
	jr	z, 2$
	srl	h
	rr	l
	dec	a
	jr	1$
2$:	ld	b, h
	ld	c, l
	NEXT
	HEAD	1, 0
	.ascii	"*"
w_star:	POPDE
	call	umul
	ld	b, h
	ld	c, l
	NEXT
	HEAD	3, 0
	.ascii	"UM*"
w_umstar:
	POPDE
	call	umul
	PDUP
	ld	b, d
	ld	c, e
	ld	-2(ix), l
	ld	-1(ix), h
	NEXT
	HEAD	2, 0
	.ascii	"M*"
w_mstar:
	POPDE
	call	mstar
	PDUP
	ld	b, d
	ld	c, e
	ld	-2(ix), l
	ld	-1(ix), h
	NEXT
	HEAD	6, 0
	.ascii	"UM/MOD"
w_ummod:
	POPDE				; ud u -- rem quot
	POPHL
	call	udivc
	jr	divret
	HEAD	6, 0
	.ascii	"SM/REM"
w_smrem:
	POPDE
	POPHL
	call	smrem
divret:	PDUP
	ld	b, h
	ld	c, l
	ld	-2(ix), e
	ld	-1(ix), d
	NEXT
	HEAD	4, 0
	.ascii	"/MOD"
w_slmod:
	call	sdiv
	jr	divret
	HEAD	1, 0
	.ascii	"/"
w_slash:
	call	sdiv
	ld	b, h
	ld	c, l
	NEXT
	HEAD	3, 0
	.ascii	"MOD"
w_mod:	call	sdiv
	ld	b, d
	ld	c, e
	NEXT
	HEAD	5, 0
	.ascii	"*/MOD"
w_ssmod:
	call	ssmod
	jr	divret
	HEAD	2, 0
	.ascii	"*/"
w_ssl:	call	ssmod
	ld	b, h
	ld	c, l
	NEXT
	HEAD	3, 0
	.ascii	"MIN"
w_min:	POPHL
	push	hl
	call	slt			; carry if HL < BC
	pop	hl
	jr	nc, 1$
	ld	b, h
	ld	c, l
1$:	NEXT
	HEAD	3, 0
	.ascii	"MAX"
w_max:	POPHL
	push	hl
	call	slt
	pop	hl
	jr	c, 1$
	ld	b, h
	ld	c, l
1$:	NEXT

; comparisons: true is -1
	HEAD	1, 0
	.ascii	"="
w_eq:	POPHL
	or	a
	sbc	hl, bc
	jr	flagz
	HEAD	2, 0
	.ascii	"<>"
w_ne:	POPHL
	or	a
	sbc	hl, bc
	jr	flagnz
	HEAD	2, 0
	.ascii	"0="
w_0eq:	ld	a, b
	or	c
flagz:	ld	bc, #0
	jr	nz, 1$
	dec	bc
1$:	NEXT
	HEAD	3, 0
	.ascii	"0<>"
w_0ne:	ld	a, b
	or	c
flagnz:	ld	bc, #0
	jr	z, 1$
	dec	bc
1$:	NEXT
	HEAD	1, 0
	.ascii	"<"
w_lt:	POPHL
	call	slt
flagc:	sbc	a, a
	ld	b, a
	ld	c, a
	NEXT
	HEAD	1, 0
	.ascii	">"
w_gt:	POPDE
	ld	h, b
	ld	l, c
	ld	b, d
	ld	c, e
	call	slt
	jr	flagc
	HEAD	2, 0
	.ascii	"U<"
w_ult:	POPHL
	or	a
	sbc	hl, bc
	jr	flagc
	HEAD	2, 0
	.ascii	"U>"
w_ugt:	POPHL
	or	a
	push	bc
	ex	(sp), hl
	pop	bc
	sbc	hl, bc
	jr	flagc
	HEAD	2, 0
	.ascii	"0<"
w_0lt:	ld	a, b
	rla
	jr	flagc
	HEAD	2, 0
	.ascii	"0>"
w_0gt:	ld	hl, #0
	call	slt
	jr	flagc
	HEAD	6, 0
	.ascii	"WITHIN"
w_within:
	POPDE				; n lo hi: lo <= n < hi, unsigned round the circle
	POPHL
	or	a
	sbc	hl, de			; n - lo
	push	hl
	ld	h, b
	ld	l, c
	or	a
	sbc	hl, de			; hi - lo
	ld	b, h
	ld	c, l
	pop	hl
	or	a
	sbc	hl, bc
	jp	flagc
	HEAD	4, 0
	.ascii	"TRUE"
w_true:	PDUP
	ld	bc, #-1
	NEXT
	HEAD	5, 0
	.ascii	"FALSE"
w_false:
	PDUP
	ld	bc, #0
	NEXT

; carry if HL < BC, signed. Destroys A,H,L,F.
slt:	ld	a, h
	xor	b
	jp	p, 1$
	ld	a, h			; different signs: HL < BC if HL is negative
	rla
	ret
1$:	or	a
	sbc	hl, bc
	ret

;umul - DE:HL = DE * BC, unsigned. Destroys A,F.
umul:	ld	hl, #0
	ld	a, #16
1$:	add	hl, hl
	rl	e
	rl	d
	jr	nc, 2$
	add	hl, bc
	jr	nc, 2$
	inc	de
2$:	dec	a
	jr	nz, 1$
	ret

; DE:HL = DE * BC, signed. Destroys A,F.
mstar:	ld	a, d
	xor	b
	push	af
	bit	7, d
	jr	z, 1$
	ld	hl, #0
	or	a
	sbc	hl, de
	ex	de, hl
1$:	bit	7, b
	jr	z, 2$
	ld	hl, #0
	or	a
	sbc	hl, bc
	ld	b, h
	ld	c, l
2$:	call	umul
	pop	af
	ret	p
; DE:HL = -DE:HL. Destroys A,F.
dneg:	xor	a
	sub	l
	ld	l, a
	ld	a, #0
	sbc	a, h
	ld	h, a
	ld	a, #0
	sbc	a, e
	ld	e, a
	ld	a, #0
	sbc	a, d
	ld	d, a
	ret

;udivc - HL = DE:HL / BC, DE = the remainder, unsigned; an error if BC is 0 or the quotient does
; not fit 16 bits. Destroys A,F.
udivc:	ld	a, b
	or	c
	jr	z, 2$
	ex	de, hl
	or	a
	sbc	hl, bc
	add	hl, bc
	ex	de, hl
	jr	nc, 2$
	ld	a, #16
1$:	add	hl, hl
	ex	de, hl
	adc	hl, hl
	jr	c, 4$
	or	a
	sbc	hl, bc
	jr	nc, 5$
	add	hl, bc
	ex	de, hl
	jr	6$
4$:	or	a
	sbc	hl, bc
5$:	ex	de, hl
	inc	l
6$:	dec	a
	jr	nz, 1$
	ret
2$:	ld	a, #E_DIV
	jp	error

;smrem - symmetric division of DE:HL by BC: HL = quotient, DE = remainder (the sign of the
; dividend). Destroys A,F.
smrem:	ld	a, d			; quotient sign: dividend xor divisor
	xor	b
	push	af
	ld	a, d			; remainder sign: the dividend's
	push	af
	bit	7, d
	call	nz, dneg
	bit	7, b
	jr	z, 1$
	push	hl
	ld	hl, #0
	or	a
	sbc	hl, bc
	ld	b, h
	ld	c, l
	pop	hl
1$:	call	udivc
	pop	af
	or	a
	jp	p, 2$
	push	hl			; negative remainder
	ld	hl, #0
	or	a
	sbc	hl, de
	ex	de, hl
	pop	hl
2$:	pop	af
	or	a
	ret	p
	push	de			; negative quotient
	ld	de, #0
	ex	de, hl
	or	a
	sbc	hl, de
	pop	de
	ret

; ( n1 n2 ) -> HL = n1 / n2, DE = n1 mod n2 (symmetric); n1 is removed, BC is no longer needed
sdiv:	POPHL
	ld	d, h			; sign-extend n1 into DE
	ld	a, h
	rla
	sbc	a, a
	ld	d, a
	ld	e, a
	call	smrem
	jr	ssret
; ( n1 n2 n3 ) -> n1*n2/n3 in HL, the remainder in DE
ssmod:	POPDE				; n2
	push	bc			; n3
	POPHL				; n1
	ld	b, h
	ld	c, l
	call	mstar
	pop	bc
	call	smrem
ssret:	ret

; memory
	HEAD	1, 0
	.ascii	"@"
w_fetch:
	ld	h, b
	ld	l, c
	ld	c, (hl)
	inc	hl
	ld	b, (hl)
	NEXT
	HEAD	1, 0
	.ascii	"!"
w_store:
	ld	h, b
	ld	l, c
	POPDE
	ld	(hl), e
	inc	hl
	ld	(hl), d
	PDROP
	NEXT
	HEAD	2, 0
	.ascii	"C@"
w_cfetch:
	ld	a, (bc)
	ld	c, a
	ld	b, #0
	NEXT
	HEAD	2, 0
	.ascii	"C!"
w_cstore:
	POPDE
	ld	a, e
	ld	(bc), a
	PDROP
	NEXT
	HEAD	2, 0
	.ascii	"+!"
w_pstore:
	POPDE
	ld	h, b
	ld	l, c
	ld	a, (hl)
	add	a, e
	ld	(hl), a
	inc	hl
	ld	a, (hl)
	adc	a, d
	ld	(hl), a
	PDROP
	NEXT
	HEAD	4, 0
	.ascii	"FILL"
w_fill:	ld	a, c			; a n c --
	PDROP
	POPHL
fill1:	push	af
	ld	a, b
	or	c
	jr	z, 1$
	pop	af
	ld	(hl), a
	dec	bc
	ld	a, b
	or	c
	jr	z, 2$
	ld	d, h
	ld	e, l
	inc	de
	ldir
	jr	2$
1$:	pop	af
2$:	PDROP
	NEXT
	HEAD	5, 0
	.ascii	"ERASE"
w_erase:
	POPHL
	xor	a
	jr	fill1
	HEAD	4, 0
	.ascii	"MOVE"
w_move:	POPDE				; from to n --, overlapping or not
	POPHL
	ld	a, b
	or	c
	jr	z, 2$
	push	hl
	or	a
	sbc	hl, de
	pop	hl
	jr	c, 1$
	ldir
	jr	2$
1$:	add	hl, bc
	dec	hl
	ex	de, hl
	add	hl, bc
	dec	hl
	ex	de, hl
	lddr
2$:	PDROP
	NEXT
	HEAD	5, 0
	.ascii	"COUNT"
w_count:
	ld	a, (bc)
	inc	bc
	PDUP
	ld	c, a
	ld	b, #0
	NEXT

; the dictionary
	HEAD	4, 0
	.ascii	"HERE"
w_here:	PDUP
	ld	bc, (HERE)
	NEXT
	HEAD	3, 0
	.ascii	"PAD"
w_pad:	PDUP
	ld	hl, (HERE)
	ld	de, #64
	add	hl, de
	ld	b, h
	ld	c, l
	NEXT
	HEAD	6, 0
	.ascii	"UNUSED"
w_unused:
	PDUP
	call	unused
	ld	b, h
	ld	c, l
	NEXT
;unused - HL = bytes left in the dictionary. Destroys D,E,F.
unused::
	ld	hl, #DICTLIM
	ld	de, (HERE)
	or	a
	sbc	hl, de
	ret
	HEAD	1, 0
	.ascii	","
w_comma:
	ld	h, b
	ld	l, c
	call	comma
	PDROP
	NEXT
	HEAD	2, 0
	.ascii	"C,"
w_ccomma:
	ld	a, c
	call	ccomma
	PDROP
	NEXT
	HEAD	5, 0
	.ascii	"ALLOT"
w_allot:
	ld	hl, (HERE)
	add	hl, bc
	call	setdp
	PDROP
	NEXT
	HEAD	4, 0
	.ascii	"BASE"
w_base:	PDUP
	ld	bc, #BASE
	NEXT
	HEAD	5, 0
	.ascii	"STATE"
w_state:
	PDUP
	ld	bc, #STATE
	NEXT
	HEAD	3, 0
	.ascii	"HEX"
w_hex:	ld	a, #16
	ld	(BASE), a
	NEXT
	HEAD	7, 0
	.ascii	"DECIMAL"
w_decimal:
	ld	a, #10
	ld	(BASE), a
	NEXT
	HEAD	6, 0
	.ascii	"CREATE"
w_create:
	call	mkhead
	call	reveal
	ld	hl, #dovar
	call	ccall
	NEXT
	HEAD	8, 0
	.ascii	"VARIABLE"
w_variable:
	call	mkhead
	call	reveal
	ld	hl, #dovar
	call	ccall
	ld	hl, #0
	call	comma
	NEXT
	HEAD	8, 0
	.ascii	"CONSTANT"
w_constant:
	call	mkhead
	call	reveal
	ld	hl, #docon
	call	ccall
	ld	h, b
	ld	l, c
	call	comma
	PDROP
	NEXT
	HEAD	5, F_IMM+F_COMP
	.ascii	"DOES>"
w_does:	ld	hl, #xdoes
	call	comma
	ld	hl, #dodoes
	call	ccall
	NEXT
	HEAD	1, 0
	.ascii	":"
w_colon:
	call	mkhead
	ld	hl, (LATEST)
	ld	(CURDEF), hl
	ld	hl, #docol
	call	ccall
	ld	(CSP), ix
	ld	a, #0xFF
	ld	(STATE), a
	ld	(STATE+1), a
	NEXT
	HEAD	1, F_IMM+F_COMP
	.ascii	";"
w_semi:	push	ix
	pop	hl
	ld	de, (CSP)
	or	a
	sbc	hl, de
	ld	a, #E_STRUCT
	jp	nz, error
	ld	hl, #w_exit
	call	comma
	call	reveal
	ld	hl, #0
	ld	(CURDEF), hl
	jr	w_lbrac
	HEAD	9, 0
	.ascii	"IMMEDIATE"
w_immediate:
	ld	hl, (LATEST)
	inc	hl
	inc	hl
	set	7, (hl)
	NEXT
	HEAD	1, F_IMM
	.ascii	"["
w_lbrac:
	ld	hl, #0
	ld	(STATE), hl
	NEXT
	HEAD	1, 0
	.ascii	"]"
w_rbrac:
	ld	hl, #-1
	ld	(STATE), hl
	NEXT
	HEAD	1, 0
	.ascii	"'"
w_tick:	push	bc
	call	tick
	pop	bc
	PDUP
	ld	b, h
	ld	c, l
	NEXT
	HEAD	3, F_IMM+F_COMP
	.ascii	"[']"
w_btick:
	push	bc
	call	tick
	pop	bc
complit:			; compile LIT HL
	push	hl
	ld	hl, #xlit
	call	comma
	pop	hl
	call	comma
	NEXT
	HEAD	7, F_IMM+F_COMP
	.ascii	"LITERAL"
w_literal:
	ld	h, b
	ld	l, c
	PDROP
	jr	complit
	HEAD	8, F_IMM+F_COMP
	.ascii	"POSTPONE"
w_postpone:
	push	bc
	call	tick
	pop	bc
	bit	7, a
	jr	z, 1$
	call	comma			; an immediate word: compiled
	NEXT
1$:	push	hl			; another: code that compiles it
	ld	hl, #xlit
	call	comma
	pop	hl
	call	comma
	ld	hl, #w_comma
	call	comma
	NEXT
	HEAD	7, 0
	.ascii	"EXECUTE"
w_execute:
	ld	h, b
	ld	l, c
	PDROP
	jp	(hl)
	HEAD	7, F_IMM+F_COMP
	.ascii	"RECURSE"
w_recurse:
	ld	hl, (CURDEF)
	call	hdrxt
	call	comma
	NEXT
	HEAD	4, F_COMP
	.ascii	"EXIT"
w_exit:	pop	hl
	NEXT
	HEAD	6, 0
	.ascii	"FORGET"
w_forget:
	push	bc
	call	pnamer
	call	find
	ld	a, #E_UNDEF
	jp	c, error
	ld	hl, #-DICT0
	add	hl, de
	ld	a, #E_PROT
	jp	nc, error
	ld	(HERE), de
	ex	de, hl
	ld	e, (hl)
	inc	hl
	ld	d, (hl)
	ld	(LATEST), de
	pop	bc
	NEXT
	HEAD	5, 0
	.ascii	"EMPTY"
w_empty:
	call	empty
	NEXT

; control structures (compiling words)
	HEAD	2, F_IMM+F_COMP
	.ascii	"IF"
w_if:	ld	hl, #xqbran
mark:	call	comma			; compile HL and a cell to patch; its address on the stack
	PDUP
	ld	bc, (HERE)
	ld	hl, #0
	call	comma
	NEXT
	HEAD	4, F_IMM+F_COMP
	.ascii	"ELSE"
w_else:	ld	hl, #xbran
	call	comma
	ld	hl, (HERE)
	push	hl
	call	comma
	call	resolve
	pop	bc
	NEXT
	HEAD	4, F_IMM+F_COMP
	.ascii	"THEN"
w_then:	call	resolve
	PDROP
	NEXT
; The cell at BC = HERE
resolve:
	ld	hl, (HERE)
	ld	a, l
	ld	(bc), a
	inc	bc
	ld	a, h
	ld	(bc), a
	dec	bc
	ret
	HEAD	5, F_IMM+F_COMP
	.ascii	"BEGIN"
w_begin:
	PDUP
	ld	bc, (HERE)
	NEXT
	HEAD	5, F_IMM+F_COMP
	.ascii	"UNTIL"
w_until:
	ld	hl, #xqbran
back:	call	comma			; compile HL and the address on the stack
	ld	h, b
	ld	l, c
	call	comma
	PDROP
	NEXT
	HEAD	5, F_IMM+F_COMP
	.ascii	"AGAIN"
w_again:
	ld	hl, #xbran
	jr	back
	HEAD	5, F_IMM+F_COMP
	.ascii	"WHILE"
w_while:
	ld	hl, #xqbran
	call	comma
	PDUP
	ld	hl, (HERE)
	ld	-2(ix), l		; orig under dest
	ld	-1(ix), h
	ld	hl, #0
	call	comma
	NEXT
	HEAD	6, F_IMM+F_COMP
	.ascii	"REPEAT"
w_repeat:
	ld	hl, #xbran
	call	comma
	ld	h, b
	ld	l, c
	call	comma
	PDROP
	jp	w_then
	HEAD	2, F_IMM+F_COMP
	.ascii	"DO"
w_do:	ld	hl, #xdo
	jp	mark
	HEAD	3, F_IMM+F_COMP
	.ascii	"?DO"
w_qdo:	ld	hl, #xqdo
	jp	mark
	HEAD	4, F_IMM+F_COMP
	.ascii	"LOOP"
w_loop:	ld	hl, #xloop
loop1:	call	comma
	ld	h, b
	ld	l, c
	inc	hl
	inc	hl
	call	comma
	jp	w_then
	HEAD	5, F_IMM+F_COMP
	.ascii	"+LOOP"
w_ploop:
	ld	hl, #xploop
	jr	loop1
	HEAD	1, F_COMP
	.ascii	"I"
w_i:	ld	hl, #2
iloop:	add	hl, sp
	PDUP
	ld	e, (hl)
	inc	hl
	ld	d, (hl)
	inc	hl
	ld	c, (hl)
	inc	hl
	ld	b, (hl)
	ex	de, hl
	add	hl, bc
	ld	b, h
	ld	c, l
	NEXT
	HEAD	1, F_COMP
	.ascii	"J"
w_j:	ld	hl, #8
	jr	iloop
	HEAD	5, F_COMP
	.ascii	"LEAVE"
w_leave:
	pop	hl
	pop	hl
	pop	hl
	NEXT
	HEAD	6, F_COMP
	.ascii	"UNLOOP"
w_unloop:
	pop	hl
	pop	de
	pop	de
	pop	de
	push	hl
	NEXT

; text in the source
	HEAD	2, F_IMM
	.ascii	/."/
w_dotq:	push	bc
	ld	a, #0x22
	call	parse
	ld	a, (STATE)
	or	a
	jr	nz, 1$
	ld	e, b			; interpreting: print it now
	ld	d, #0
	call	typen
	pop	bc
	NEXT
1$:	ld	de, #xdotq
; Compile DE and the counted string HL, B characters, then BC from the stack
cstr:	push	hl
	ex	de, hl
	call	comma
	pop	hl
	ld	a, b
	push	hl
	call	ccomma
	pop	hl
	ld	a, b
	or	a
	jr	z, 3$
2$:	ld	a, (hl)
	push	hl
	call	ccomma
	pop	hl
	inc	hl
	djnz	2$
3$:	pop	bc
	NEXT
	HEAD	2, F_IMM
	.ascii	/S"/
w_squote:
	push	bc
	ld	a, #0x22
	call	parse
	ld	a, (STATE)
	or	a
	jr	nz, 1$
	ld	a, b			; interpreting: the text where it is in the source line
	pop	bc
	PDUP
	ld	b, h
	ld	c, l
	PDUP
	ld	c, a
	ld	b, #0
	NEXT
1$:	ld	de, #xsq
	jr	cstr
	HEAD	6, F_IMM+F_COMP
	.ascii	/ABORT"/
w_abortq:
	push	bc
	ld	a, #0x22
	call	parse
	ld	de, #xabq
	jr	cstr
	HEAD	5, 0
	.ascii	"ABORT"
w_abort:
	ld	a, #E_ABORT
	jp	error
	HEAD	2, F_IMM
	.ascii	".("
w_dotp:	push	bc
	ld	a, #')
	call	parse
	ld	e, b
	ld	d, #0
	call	typen
	pop	bc
	NEXT
	HEAD	1, F_IMM
	.ascii	"("
w_paren:
	push	bc
	ld	a, #')
	call	parse
	pop	bc
	NEXT
	HEAD	1, F_IMM
	.db	0x5C
w_bslash:
	ld	hl, (SRCL)
	ld	(TOIN), hl
	NEXT
	HEAD	4, 0
	.ascii	"CHAR"
w_char:	push	bc
	call	pnamer
	ld	a, (hl)
	pop	bc
	PDUP
	ld	c, a
	ld	b, #0
	NEXT
	HEAD	6, F_IMM+F_COMP
	.ascii	"[CHAR]"
w_bchar:
	push	bc
	call	pnamer
	ld	l, (hl)
	ld	h, #0
	pop	bc
	jp	complit

; output
	HEAD	4, 0
	.ascii	"EMIT"
w_emit:	ld	a, c
	call	emit
	PDROP
	NEXT
	HEAD	4, 0
	.ascii	"TYPE"
w_type:	ld	d, b
	ld	e, c
	PDROP
	ld	h, b
	ld	l, c
	call	typen
	PDROP
	NEXT
	HEAD	2, 0
	.ascii	"CR"
w_cr:	ld	a, #CR
	call	emit
	NEXT
	HEAD	5, 0
	.ascii	"SPACE"
w_space:
	ld	a, #0x20
	call	emit
	NEXT
	HEAD	6, 0
	.ascii	"SPACES"
w_spaces:
	bit	7, b
	jr	nz, 2$
1$:	ld	a, b
	or	c
	jr	z, 2$
	ld	a, #0x20
	call	emit
	dec	bc
	jr	1$
2$:	PDROP
	NEXT
	HEAD	4, 0
	.ascii	"PAGE"
w_page:	call	CLS
	NEXT
	HEAD	5, 0
	.ascii	"AT-XY"
w_atxy:	ld	d, c			; column row --
	PDROP
	ld	e, c
	call	SETCUR
	PDROP
	NEXT

; numbers
	HEAD	2, 0
	.ascii	"<#"
w_lsharp:
	call	padhl
	ld	(HLD), hl
	NEXT
	HEAD	1, 0
	.ascii	"#"
w_sharp:
	ld	d, b			; ud -- ud/base, a digit held
	ld	e, c
	ld	l, -2(ix)
	ld	h, -1(ix)
	call	digit
	ld	-2(ix), l
	ld	-1(ix), h
	ld	b, d
	ld	c, e
	NEXT
	HEAD	2, 0
	.ascii	"#S"
w_sharps:
	ld	d, b
	ld	e, c
	ld	l, -2(ix)
	ld	h, -1(ix)
1$:	call	digit
	ld	a, h
	or	l
	or	d
	or	e
	jr	nz, 1$
	ld	-2(ix), l
	ld	-1(ix), h
	ld	b, d
	ld	c, e
	NEXT
	HEAD	4, 0
	.ascii	"HOLD"
w_hold:	ld	a, c
	call	hold
	PDROP
	NEXT
	HEAD	4, 0
	.ascii	"SIGN"
w_sign:	bit	7, b
	ld	a, #'-
	call	nz, hold
	PDROP
	NEXT
	HEAD	2, 0
	.ascii	"#>"
w_sharpg:
	call	padhl			; ud -- addr n
	ld	de, (HLD)
	or	a
	sbc	hl, de
	ld	-2(ix), e
	ld	-1(ix), d
	ld	b, h
	ld	c, l
	NEXT
	HEAD	1, 0
	.ascii	"."
w_dot:	ld	a, #1
dot1:	ld	h, b
	ld	l, c
	PDROP
	ld	e, #0
	call	prnum
	ld	a, #0x20
	call	emit
	NEXT
	HEAD	2, 0
	.ascii	"U."
w_udot:	xor	a
	jr	dot1
	HEAD	2, 0
	.ascii	".R"
w_dotr:	ld	a, #1
dotr1:	ld	e, c			; n width --
	PDROP
	ld	h, b
	ld	l, c
	PDROP
	call	prnum
	NEXT
	HEAD	3, 0
	.ascii	"U.R"
w_udotr:
	xor	a
	jr	dotr1
	HEAD	1, 0
	.ascii	"?"
w_ques:	ld	h, b
	ld	l, c
	ld	c, (hl)
	inc	hl
	ld	b, (hl)
	jr	w_dot
	HEAD	2, 0
	.ascii	".S"
w_dots:	PDUP				; (all the stack in memory)
	push	ix
	pop	hl
	ld	de, #-DS0
	add	hl, de
	srl	h
	rr	l
	dec	hl			; depth, without the copy
	push	hl
	ld	a, #'<
	call	emit
	ld	a, #1
	ld	e, #0
	call	prnum
	ld	a, #'>
	call	emit
	pop	bc
	ld	hl, #DS0+2
1$:	ld	a, b
	or	c
	jr	z, 2$
	ld	a, #0x20
	call	emit
	ld	e, (hl)
	inc	hl
	ld	d, (hl)
	inc	hl
	push	hl
	ex	de, hl
	ld	a, #1
	ld	e, #0
	call	prnum
	pop	hl
	dec	bc
	jr	1$
2$:	ld	a, #0x20
	call	emit
	PDROP
	NEXT

; HL = PAD. Destroys D,E,F.
padhl:	ld	hl, (HERE)
	ld	de, #64
	add	hl, de
	ret
; Hold A in the number buffer. Destroys H,L,F.
hold:	ld	hl, (HLD)
	dec	hl
	ld	(hl), a
	ld	(HLD), hl
	ret
; Hold the next digit of DE:HL (DE:HL = DE:HL / BASE). Destroys A,F.
digit:	push	bc
	ld	a, (BASE)
	ld	c, a
	ld	b, #32
	xor	a
1$:	add	hl, hl
	rl	e
	rl	d
	rla
	cp	c
	jr	c, 2$
	sub	c
	inc	l
2$:	djnz	1$
	pop	bc
	add	a, #'0
	cp	#'9+1
	jr	c, 3$
	add	a, #7
3$:	push	hl
	call	hold
	pop	hl
	ret

;prnum - print HL in BASE, signed if A = 1, right-aligned in E columns. Destroys A,D,E,H,L,F.
prnum:	push	bc
	push	de
	ld	b, #0
	or	a
	jr	z, 1$
	bit	7, h
	jr	z, 1$
	inc	b			; negative
	xor	a
	sub	l
	ld	l, a
	sbc	a, a
	sub	h
	ld	h, a
1$:	push	hl
	call	padhl
	ld	(HLD), hl
	pop	hl
	ld	de, #0
2$:	call	digit
	ld	a, h
	or	l
	jr	nz, 2$
	ld	a, b
	or	a
	ld	a, #'-
	call	nz, hold
	call	padhl
	ld	de, (HLD)
	or	a
	sbc	hl, de			; L = length
	pop	de
	ld	a, e
	sub	l
	jr	c, 4$
	jr	z, 4$
	ld	b, a
3$:	ld	a, #0x20
	call	emit
	djnz	3$
4$:	ld	e, l
	ld	d, #0
	ld	hl, (HLD)
	call	typen
	pop	bc
	ret

; input
	HEAD	3, 0
	.ascii	"KEY"
w_key:	PDUP
	push	bc
	ld	a, (PENDK)
	or	a
	jr	nz, 1$
	call	GETKEY
1$:	pop	bc
	ld	c, a
	ld	b, #0
	xor	a
	ld	(PENDK), a
	NEXT
	HEAD	4, 0
	.ascii	"KEY?"
w_keyq:	PDUP
	push	bc
	ld	a, (PENDK)
	or	a
	jr	nz, 1$
	call	KEYPOLL
	ld	(PENDK), a
1$:	pop	bc
	ld	bc, #0
	or	a
	jr	z, 2$
	dec	bc
2$:	NEXT
	HEAD	6, 0
	.ascii	"ACCEPT"
w_accept:
	push	bc			; addr n -- n'
	xor	a
	ld	(LEN), a
	ld	(CUR), a
	ld	(LASTLEN), a
	ld	(HOFS), a
	inc	a
	ld	(RLMODE), a
	call	readline
	ld	a, #0x20
	call	PUTCHAR
	xor	a
	ld	(RLMODE), a
	pop	bc
	ld	a, (LEN)
	cp	c			; at most n characters
	jr	nc, 1$
	ld	c, a
1$:	ld	b, #0
	POPDE
	ld	hl, #LBUF
	ld	a, b
	or	c
	jr	z, 2$
	push	bc
	ldir
	pop	bc
2$:	NEXT

; the Genio
	HEAD	2, 0
	.ascii	"MS"
w_ms:	ld	h, b
	ld	l, c
	call	DELAY
	PDROP
	NEXT
	HEAD	4, 0
	.ascii	"BEEP"
w_beep:	call	BEEP
	NEXT
	HEAD	4, 0
	.ascii	"TONE"
w_tone:	push	bc			; hz ms --
	POPHL
	ld	a, h			; 0 Hz or more than 9999 Hz: silence
	or	l
	jr	z, 3$
	ld	de, #10000
	or	a
	sbc	hl, de
	add	hl, de
	jr	nc, 3$
	push	hl			; half periods = hz * ms / 500
	ex	de, hl
	call	umul
	ld	bc, #500
	call	udivc
	ex	(sp), hl		; HL = hz
	ld	b, h
	ld	c, l
	ld	de, #0x0001		; turns of the delay loop: 3065895 T-states / 26 / hz, less 86 / 26
	ld	hl, #0xCC9F
	call	udivc
	ld	de, #-3
	add	hl, de
	jr	nc, 1$
	ld	a, h
	or	l
	jr	nz, 2$
1$:	ld	hl, #1
2$:	ex	de, hl
	pop	hl
	ld	a, h
	or	l
	call	nz, tone
	jr	4$
3$:	pop	hl			; silence: wait
	push	hl
	call	DELAY
4$:	pop	bc
	PDROP
	NEXT
	HEAD	3, 0
	.ascii	"LED"
w_led:	ld	a, b
	or	c
	ld	a, (P12)
	res	5, a
	jr	z, 1$
	set	5, a
1$:	and	#0xFE			; bit 0 would switch the unit off
	ld	(P12), a
	out	(0x12), a
	PDROP
	NEXT
	HEAD	5, 0
	.ascii	"GLYPH"
w_glyph:
	ld	a, c			; addr n --
	PDROP
	ld	h, b
	ld	l, c
	call	glyph
	PDROP
	NEXT
	HEAD	4, 0
	.ascii	"DUMP"
w_dump:	push	bc			; addr n --
	POPHL
	pop	bc
	ld	a, #0xFF
	ld	(MORECNT), a
1$:	ld	a, b
	or	c
	jr	z, 4$
	call	more
	call	NEWLINE
	call	PRHEX16
	ld	d, #4
2$:	ld	a, #0x20
	call	PUTCHAR
	ld	a, (hl)
	call	PRHEX8
	inc	hl
	dec	bc
	ld	a, b
	or	c
	jr	z, 3$
	dec	d
	jr	nz, 2$
3$:	jr	1$
4$:	PDROP
	NEXT
	HEAD	5, 0
	.ascii	"WORDS"
w_words:
	push	bc
	xor	a
	ld	(MORECNT), a
	call	NEWLINE
	ld	hl, (LATEST)
1$:	ld	a, h
	or	l
	jr	z, 5$
	push	hl
	inc	hl
	inc	hl
	ld	a, (hl)
	bit	6, a
	jr	nz, 4$
	and	#F_LEN
	ld	b, a
	ld	a, (CX)			; a new line if the name does not fit
	or	a
	jr	z, 2$
	add	a, b
	cp	#20
	jr	c, 2$
	call	more
	call	NEWLINE
2$:	inc	hl
	ld	a, (hl)
	call	PUTCHAR
	djnz	2$
	ld	a, (CX)
	cp	#20
	jr	nc, 4$
	ld	a, #0x20
	call	PUTCHAR
4$:	pop	hl
	ld	a, (hl)
	inc	hl
	ld	h, (hl)
	ld	l, a
	jr	1$
5$:	pop	bc
	NEXT

; After three lines of WORDS or DUMP, wait for a key. Destroys A,F.
more:	push	hl
	ld	hl, #MORECNT
	inc	(hl)
	ld	a, (hl)
	cp	#3
	jr	c, 1$
	ld	(hl), #0
	call	GETKEY
1$:	pop	hl
	ret

; the system
	HEAD	4, 0
	.ascii	"LOAD"
w_load:	ld	(TOSV), bc
	call	doload
	ld	bc, (TOSV)
	NEXT
	HEAD	3, 0
	.ascii	"RUN"
w_run:	ld	(TOSV), bc
	call	doload
	ld	hl, (LATEST)
	ld	de, #-DICT0
	add	hl, de
	ld	a, #E_NORUN
	jp	nc, error
	ld	hl, (LATEST)
	call	hdrxt
	call	execxt
	ld	bc, (TOSV)
	NEXT
	HEAD	4, 0
	.ascii	"EDIT"
w_edit:	ld	(TOSV), bc
	jp	cmdedit
	HEAD	4, 0
	.ascii	"LINE"
w_line:	ld	(TOSV), bc
	jp	cmdline
	HEAD	6, 0
	.ascii	"LOCATE"
w_locate:
	ld	(TOSV), bc
	jp	cmdlocate
	HEAD	3, 0
	.ascii	"NEW"
w_new:	push	bc
	call	cmdnew
	pop	bc
	NEXT
	HEAD	3, 0
	.ascii	"BYE"
w_bye:	di				; the firmware's "no key" state, as on entry
	ld	a, #0xC0
	ld	(FW_KEYST), a
	jp	0x0030
ROMLAST == LINK

;doload - EMPTY, then interpret the source text line by line. It ends the command line.
doload:	ld	a, (LOADING)
	or	a
	ld	a, #E_NEST
	jp	nz, error
	call	empty
	ld	a, #1
	ld	(LOADING), a
	ld	hl, #0
	ld	(LDLINE), hl
	ld	hl, #SRCBEG
	ld	(LDPTR), hl
1$:	ld	hl, (LDLINE)
	ld	de, (NLINES)
	or	a
	sbc	hl, de
	jr	nc, 2$
	ld	hl, (LDPTR)
	ld	de, #WBUF
	call	expand
	ld	(LDPTR), hl
	ld	l, b
	ld	h, #0
	ld	(SRCL), hl
	ld	hl, #WBUF
	ld	(SRCA), hl
	ld	hl, #0
	ld	(TOIN), hl
	call	interp
	ld	hl, (LDLINE)
	inc	hl
	ld	(LDLINE), hl
	jr	1$
2$:	xor	a
	ld	(LOADING), a
	ld	hl, (SRCL)		; nothing more on the command line
	ld	(TOIN), hl
	ld	a, (STATE)
	or	a
	ret	z
	ld	a, #E_UNFIN
	jp	error
