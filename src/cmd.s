; cmd.s - 4Forth page 1: the command line (a scrolling console where each line is interpreted, ending
; in " ok"), its line editor (also ACCEPT's), the errors, and the words that go to the editor:
; EDIT, LINE n, LOCATE text, NEW. The line editor and the console handling are EASM's.
; Copyright (C) 2026 Santiago Crespo
; SPDX-License-Identifier: 0BSD

	.include "shared.inc"
	.area	CODE

;cmdloop - the command line. Entered by a jump; the stack is reset.
cmdloop::
	xor	a
	ld	(LEN), a
	ld	(CUR), a
cmdnext::
	ld	sp, #STACK
	ld	(ERRSP), sp
	ld	hl, #cmderr
	ld	(ERRJP), hl
	ld	iy, #next
	xor	a
	ld	(HOFS), a
	ld	(CURSOFF), a
	ld	(RLMODE), a
	call	NEWLINE
	ld	a, (PRUN)		; a command given by an editor key runs at once
	or	a
	jr	z, 1$
	xor	a
	ld	(PRUN), a
	ld	a, (LEN)
	ld	(CUR), a
	ld	a, #0xFF
	ld	(RLCOL), a
	call	rldraw
	jr	2$
1$:	call	readline
	jr	nc, 2$
	call	clrrow			; ANSWER: the line is cleared, the editor comes
	jp	toedit
2$:	ld	a, #0x20
	call	PUTCHAR
	ld	a, (LEN)		; the line is interpreted from WBUF (ACCEPT reuses LBUF)
	ld	(LASTLEN), a
	ld	c, a
	ld	b, #0
	ld	(SRCL), bc
	ld	hl, #LBUF
	ld	de, #WBUF
	ld	(SRCA), de
	or	a
	jr	z, 3$
	ldir
3$:	ld	hl, #0
	ld	(TOIN), hl
	ld	a, #1
	ld	(RUNNING), a
	call	interp
	xor	a
	ld	(RUNNING), a
	ld	hl, #oktxt
	ld	a, (CX)			; no space at the start of a row
	or	a
	jr	nz, 4$
	inc	hl
4$:	call	PRINTSTR
	jp	cmdloop

oktxt:	.asciz	" ok"

; Clear the cursor's row, the cursor at its start
clrrow:	ld	a, (CY)
	ld	e, a
	add	a, a
	add	a, a
	add	a, e
	add	a, a
	add	a, a
	ld	e, a
	ld	d, #0
	ld	hl, #SCR
	add	hl, de
	ld	b, #20
1$:	ld	(hl), #0x20
	inc	hl
	djnz	1$
	xor	a
	ld	(CX), a
	ret

;fstop - leave Forth: a definition being compiled is dropped, interpretation stops. Destroys A,H,L,F.
fstop:	xor	a
	ld	(RUNNING), a
	ld	(LOADING), a
	ld	hl, (CURDEF)
	ld	a, h
	or	l
	jr	z, 1$
	ld	hl, (DPSAVE)
	ld	(HERE), hl
	ld	hl, (LPSAVE)
	ld	(LATEST), hl
	ld	hl, #0
	ld	(CURDEF), hl
1$:	ld	hl, #0
	ld	(STATE), hl
	ret

; Error handler of the command line: the stacks are emptied; the line of the text during LOAD,
; the word, the message
cmderr:	ld	sp, #STACK
	ld	iy, #next
	ld	ix, #DS0
	ld	a, (LOADING)
	push	af
	call	fstop
	ld	a, (ISRON)
	or	a
	jr	z, 1$
	im	1
	ei
1$:	call	NEWLINE
	pop	af
	or	a
	jr	z, 2$
	ld	hl, (LDLINE)		; during LOAD: "Line n:" and the line, kept for the editor
	inc	hl
	ld	(ERRLN), hl
	ld	hl, (ERRWA)		; column: the start of the word
	ld	a, l
	ld	(ERRCOL), a
	ld	hl, #ltxt
	call	PRINTSTR
	ld	hl, (ERRLN)
	call	PRDEC
	ld	a, #':
	call	PUTCHAR
	call	NEWLINE
	ld	hl, #WBUF
	ld	a, (SRCL)
	cp	#20
	jr	c, 3$
	ld	a, #20
3$:	or	a
	jr	z, 4$
	ld	b, a
5$:	ld	a, (hl)
	call	PUTCHAR
	inc	hl
	djnz	5$
4$:	call	NEWLINE
2$:	ld	a, (ERRNO)
	cp	#E_ABORTQ
	jr	nz, 6$
	ld	hl, (ERRWA)		; ABORT" text
	call	typec
	jr	9$
6$:	cp	#E_UNDEF
	jr	nz, 7$
	ld	hl, (ERRWA)		; the unknown word (15 characters at most), then " ?"
	ld	a, (ERRWL)
	cp	#16
	jr	c, 8$
	ld	a, #15
8$:	ld	e, a
	ld	d, #0
	call	typen
	ld	a, #0x20
	call	PUTCHAR
7$:	ld	a, (ERRNO)
	call	errmsg
	call	prmsg
9$:	call	BEEP
	jp	cmdloop

ltxt:	.asciz	"Line "

;errmsg - HL = the message of error A (1-n). Destroys A,F.
errmsg::
	ld	hl, #ERRTXT
1$:	dec	a
	ret	z
2$:	bit	7, (hl)
	inc	hl
	jr	z, 2$
	jr	1$

;prmsg - print the message at HL (last character with bit 7). Destroys A,F,H,L.
prmsg::	ld	a, (hl)
	and	#0x7F
	call	PUTCHAR
	bit	7, (hl)
	inc	hl
	jr	z, prmsg
	ret

ERRTXT:	.db	'?+0x80			; E_UNDEF
	.ascii	"Stack empt"
	.db	'y+0x80
	.ascii	"Stack ful"
	.db	'l+0x80
	.ascii	"Return stack ful"
	.db	'l+0x80
	.ascii	"Compile onl"
	.db	'y+0x80
	.ascii	"Dictionary ful"
	.db	'l+0x80
	.ascii	"Text ful"
	.db	'l+0x80
	.ascii	"Division erro"
	.db	'r+0x80
	.ascii	"Name missin"
	.db	'g+0x80
	.ascii	"Unbalanced contro"
	.db	'l+0x80
	.ascii	"Brea"
	.db	'k+0x80
	.ascii	"Word in RO"
	.db	'M+0x80
	.ascii	"LOAD in LOA"
	.db	'D+0x80
	.ascii	"Nothing to ru"
	.db	'n+0x80
	.db	0x20+0x80		; E_ABORTQ (its own text)
	.ascii	"Abor"
	.db	't+0x80
	.ascii	"Unfinished "
	.db	':+0x80
	.ascii	"Not foun"
	.db	'd+0x80

;---------------------------------------------------------------- words that go to the editor

; EDIT: the editor, as it was left (jumped to from the word; Forth stops)
cmdedit::
	call	fstop
	jp	toedit

; LINE n: the editor at line n (counting from 1)
cmdline::
	call	pnamer
	call	number
	ld	a, #E_UNDEF
	jp	c, error
	ld	a, h
	or	l
	jr	z, 1$
	dec	hl
1$:	ex	de, hl
	call	clampl
	ld	(CURL), de
	xor	a
	ld	(ECUR), a
	jr	cmdedit

; DE = a line number limited to the text (0 to NLINES-1). Destroys A,F,H,L.
clampl::
	ld	hl, (NLINES)
	dec	hl
	or	a
	sbc	hl, de
	ret	nc
	ld	de, (NLINES)
	dec	de
	ret

; LOCATE text: the editor at the next line (after the current one, round to it) containing the text
; (the rest of the command line), in any case
cmdlocate::
	call	srcpos
2$:	ld	a, c			; skip spaces
	or	a
	jr	z, 9$
	ld	a, (hl)
	cp	#0x21
	jr	nc, 3$
	inc	hl
	dec	c
	jr	2$
3$:	ld	(LABPOS), hl		; the text to find, C characters
	ld	a, c
	ld	(FCOUNT), a
	ld	de, (CURL)
	ld	hl, (NLINES)		; lines to try
	ld	(SPP), hl
4$:	inc	de
	ld	hl, (NLINES)
	or	a
	sbc	hl, de
	jr	nz, 5$
	ld	de, #0
5$:	push	de
	call	lineptr
	ld	de, #LBUF		; (LBUF is free: the command was copied to WBUF)
	call	expand
	pop	de
	call	instr
	jr	c, 6$
	ld	(CURL), de
	ld	(ECUR), a
	jr	cmdedit
6$:	ld	hl, (SPP)
	dec	hl
	ld	(SPP), hl
	ld	a, h
	or	l
	jr	nz, 4$
	ld	a, #E_NOTFOUND
	jp	error
9$:	ld	a, #E_NAME
	jp	error

; NC and A = the column where the text (LABPOS, FCOUNT characters) is in LBUF (B characters), any case;
; else carry. Destroys A,B,C,H,L,F.
instr:	ld	a, (FCOUNT)
	ld	c, a
	ld	hl, #LBUF
1$:	ld	a, b
	cp	c
	ret	c			; fewer characters left than in the text
	push	bc
	push	de
	push	hl
	ld	de, (LABPOS)
2$:	ld	a, (de)
	call	upper
	ld	b, a
	ld	a, (hl)
	call	upper
	cp	b
	jr	nz, 3$
	inc	hl
	inc	de
	dec	c
	jr	nz, 2$
	pop	hl			; found
	pop	de
	pop	bc
	ld	a, l
	or	a
	ret
3$:	pop	hl
	pop	de
	pop	bc
	inc	hl
	dec	b
	jr	1$

; NEW: erase the text, if confirmed
cmdnew::
	ld	hl, #suretxt
	call	PRINTSTR
	call	GETKEY
	cp	#CR
	ret	nz
	call	txtnew
	xor	a
	ld	(ECUR), a
	ld	hl, #newtxt
	jp	PRINTSTR

suretxt:
	.asciz	" Erase text? INTRO"
newtxt:	.asciz	" erased"

;---------------------------------------------------------------- output helpers

; Row: the text at HL (ending in 0) padded to 20 cells from cell E. E ends at the next row.
; Destroys A,B,C,H,L,F.
putrow::
	ld	b, #20
1$:	ld	a, (hl)
	or	a
	jr	z, 2$
	inc	hl
	jr	3$
2$:	ld	a, #0x20
3$:	push	hl
	push	bc
	call	putcell
	pop	bc
	pop	hl
	inc	e
	djnz	1$
	ret

;---------------------------------------------------------------- line input

;readline - edit LBUF (LEN, CUR) on the console row from the current column to the end of the row,
; scrolling sideways. ENTER: carry clear, the cursor after the text. ANSWER: carry set (at the
; command line). At the command line (RLMODE 0), HELP opens the guide (its example replaces the
; line), up brings back the last line, and the panel's command keys run their command; in ACCEPT
; (RLMODE 1) those keys do nothing.
readline::
	ld	a, #0xFF
	ld	(RLCOL), a
1$:	call	rldraw
	call	GETKEY
	cp	#CR
	jr	z, 8$
	ld	b, a
	ld	a, (RLMODE)
	or	a
	ld	a, b
	jr	nz, 3$
	cp	#ESC
	jr	z, 9$
	cp	#UP
	jr	nz, 7$
	ld	a, (LASTLEN)		; the last line again
	ld	(LEN), a
	ld	(CUR), a
	jr	1$
7$:	cp	#HELP
	jr	nz, 2$
	call	savescr
	ld	a, #1
	call	help			; the guide; an example comes back in WBUF (carry)
	push	af
	call	restscr
	pop	af
	call	c, exline
	jr	1$
2$:	call	actkey
	jr	nc, 4$
	cp	#A_ACT
	jr	c, 5$
	cp	#A_LINE			; LINE and LOCATE are typed, to be completed
	jr	z, 5$
	cp	#A_LOCATE
	jr	z, 5$
	call	actrun			; LOAD, RUN, WORDS run at once; the others do nothing here
	jr	nc, 1$
	call	acttext
	xor	a
	ld	(LEN), a
	ld	(CUR), a
	call	instext
	jr	8$
3$:	cp	#HELP			; ACCEPT: no guide, no commands
	jr	z, 1$
	cp	#ESC
	jr	z, 1$
	call	actkey
	jr	nc, 4$
	cp	#A_ACT
	jr	nc, 1$
5$:	call	acttext			; a text key: its text
	call	instext
	jr	1$
4$:	call	edkey			; editing keys and characters
	jr	1$
8$:	ld	a, (LEN)
	ld	(CUR), a
	call	rldraw
	or	a
	ret
9$:	call	rldraw
	scf
	ret

; Draw LBUF from HOFS on the row, from RLCOL; the cursor at CUR
rldraw::
	ld	a, (CX)
	cp	#20
	jr	c, 1$
	call	newline			; no room on this row
	xor	a
1$:	ld	b, a
	ld	a, (RLCOL)
	cp	#0xFF
	jr	nz, 2$
	ld	a, b
	ld	(RLCOL), a
2$:	ld	c, a			; C = first column
	ld	a, #19			; width - 1
	sub	c
	call	hscroll
	ld	a, (CY)
	ld	e, a
	add	a, a
	add	a, a
	add	a, e
	add	a, a
	add	a, a
	add	a, c
	ld	e, a			; cell
	ld	a, #20
	sub	c
	ld	b, a
	ld	a, (HOFS)
	ld	d, a
3$:	ld	a, (LEN)
	cp	d
	ld	a, #0x20
	jr	z, 4$
	jr	c, 4$
	ld	hl, #LBUF
	ld	l, d
	ld	a, (hl)
4$:	push	bc
	push	de
	call	putcell
	pop	de
	pop	bc
	inc	e
	inc	d
	djnz	3$
	ld	a, (HOFS)
	ld	b, a
	ld	a, (CUR)
	sub	b
	add	a, c
	ld	(CX), a
	ret

;hscroll - keep CUR within HOFS .. HOFS+A (A = shown width - 1); moving left, four characters
; before the cursor stay in view. Destroys A,B,F.
hscroll::
	ld	b, a
	ld	a, (CUR)
	push	hl
	ld	hl, #HOFS
	cp	(hl)
	jr	nc, 1$
	sub	#4			; left of the window
	jr	nc, 3$
	xor	a
3$:	ld	(hl), a
	pop	hl
	ret
1$:	sub	(hl)
	cp	b
	jr	c, 2$
	jr	z, 2$
	sub	b			; right of it
	add	a, (hl)
	ld	(hl), a
2$:	pop	hl
	ret
