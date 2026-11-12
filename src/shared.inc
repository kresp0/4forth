; shared.inc - 4Forth constants shared by both cartridge pages: key codes, RAM layout, page selectors,
; firmware addresses, error numbers, page-2 jump-table slots.
; Copyright (C) 2026 Santiago Crespo
; SPDX-License-Identifier: GPL-3.0-or-later

CR = 13
LF = 10
ESC = 27
BS = 8
TAB = 9
DEL = 0x7F
LEFT = 136			; key codes (as in EASM and EBASIC)
RIGHT = 137
DOWN = 138
UP = 139
HOME = 140			; ALT+LEFT / ALT+RIGHT
END = 141
HELP = 142			; SHIFT+HELP is TAB
MAXLEN = 250			; characters in a line

PAGE1 = 0x80			; port 0x03: first 16 KiB of the cartridge (4Forth)
PAGE2 = 0x83			; second 16 KiB (guide): bit 1 selects it on the RevD board, bit 0 in MAME

; Firmware RAM, used only to run its interrupt routine as a timer and cursor service (see EBASIC)
FW_KEYST = 0xDB00		; D0 = "key pending": the ISR then skips its keyboard scan and idle power-off
FW_KEYCODE = 0xDB01		; must not be B4 (OFF) while FW_KEYST = D0
FW_DIRTY = 0xDCF0		; 4 row-dirty flags, then cursor column, row, style, enable
FW_HOOK = 0xDFF5

; Dictionary header: [link][flags+length][name][code field]
F_IMM = 0x80			; immediate
F_HIDE = 0x40			; being defined: not found
F_COMP = 0x20			; compile only
F_LEN = 0x1F

;---------------------------------------------------------------- RAM (C000-DAFF; DB00-DFFF is the firmware's)
LBUF = 0xC000			; 256: the line being edited (editor, command line); page aligned
VARS = 0xC100			; 256: variables
WBUF = 0xC200			; 256: the line being interpreted, a page of the guide; page aligned
ROWBUF = WBUF+0x80		; 81: a screen being built (error messages in the editor)
RAMCODE = 0xC300		; trampolines and interrupt hook (copied from ROM)
SCRSAVE = 0xC380		; 80: the console while the editor or the guide covers it
HLINES = 0xC3D0			; 40: start/end of each line of a guide page
DS0 = 0xC400			; data stack, growing up (the top of stack is kept in BC)
DSLIM = 0xC47C			; highest stack pointer allowed (62 cells)
RSLIM = 0xC4A0			; lowest return stack pointer allowed when a word is entered
STACK = 0xC560			; initial SP: the return stack runs down from here
SRCBEG = 0xC560			; source text
SRCLIM = 0xD000
DICT0 = 0xD000			; the dictionary of the words defined in RAM
DICTLIM = 0xDA60		; HERE stays below: the number buffer (HERE..PAD) and PAD (HERE+64) follow it

SCR = VARS			; 80-byte shadow screen
CX = SCR+80
CY = CX+1
CAPS = CY+1
P12 = CAPS+1			; last value written to port 0x12
RELCNT = P12+1
LASTSC = RELCNT+1
REPCNT = LASTSC+1
OFFARM = REPCNT+1
OFFCNT = OFFARM+1		; interrupts that saw OFF held (while a word runs)
ISRON = OFFCNT+1		; the firmware ISR is enabled
RUNNING = ISRON+1		; Forth runs: ANSWER breaks it, OFF is watched by the hook
CURSOFF = RUNNING+1		; no cursor while waiting for a key
; editor
TXTEND = CURSOFF+1		; end of the source text (first free byte)
NLINES = TXTEND+2		; number of lines (at least 1)
CURL = NLINES+2			; line being edited (0-based)
TOPL = CURL+2			; line on the top row
CUR = TOPL+2			; cursor in LBUF
LEN = CUR+1			; length of LBUF
HOFS = LEN+1			; first character of LBUF shown
MODIF = HOFS+1			; LBUF differs from the stored line
NUMSHOW = MODIF+1		; line numbers on the left
LINEPTR = NUMSHOW+1		; scratch
; Forth
TOSV = LINEPTR+2		; top of the data stack while the interpreter (assembly) runs
HERE = TOSV+2			; first free byte of the dictionary
LATEST = HERE+2			; header of the last word
STATE = LATEST+2		; 0 interpreting, -1 compiling
BASE = STATE+2
TOIN = BASE+2			; >IN: offset in the source
SRCA = TOIN+2			; the source: address and length
SRCL = SRCA+2
CURDEF = SRCL+2			; header of the word being defined (0: none)
DPSAVE = CURDEF+2		; HERE and LATEST before it, for an error
LPSAVE = DPSAVE+2
CSP = LPSAVE+2			; data stack pointer at ":" (checked by ";")
HLD = CSP+2			; pictured numeric output pointer
XTSLOT = HLD+2			; 4: the thread that runs one word from the interpreter
LOADING = XTSLOT+4		; LOAD is reading the text
LDLINE = LOADING+1		; the line LOAD is at (0-based), and its record
LDPTR = LDLINE+2
PENDK = LDPTR+2			; a key seen by KEY? and not yet read by KEY
LASTLEN = PENDK+1		; length of the last command line (UP brings it back), 0: none
MORECNT = LASTLEN+1		; lines printed since the last pause (WORDS, DUMP)
ERRSP = MORECNT+1		; error recovery: stack pointer and handler
ERRJP = ERRSP+2
ERRNO = ERRJP+2			; last error, its line (+1, 0: none) and column
ERRLN = ERRNO+1
ERRCOL = ERRLN+2
ERRWA = ERRCOL+1		; the word of the error (address, length), or ABORT"'s text
ERRWL = ERRWA+2
; guide
HSEL = ERRWL+1
HTOP = HSEL+1
HLINE = HTOP+1
HLEN = HLINE+1
HNL = HLEN+1
HEX = HNL+1			; offset of the example (0: none)
HCTX = HEX+2			; caller: 0 editor, 1 command line
; command line and editor scratch
ECUR = HCTX+1			; editor cursor while the command line is shown
PRUN = ECUR+1			; the command in LBUF (from an editor key) runs at once
RLCOL = PRUN+1			; first column of the input line
RLMODE = RLCOL+1		; readline: 0 at the command line, 1 in ACCEPT
FCOUNT = RLMODE+1		; scratch
LABPOS = FCOUNT+2		; scratch
SPP = LABPOS+2			; splice: position, old and new size
SPOLD = SPP+2
SPNEW = SPOLD+2
SAVCXY = SPNEW+2		; CX, CY of the saved console
VARS_END = SAVCXY+2

; Error numbers (messages in cmd.s)
E_UNDEF = 1
E_EMPTY = 2
E_FULL = 3
E_RFULL = 4
E_COMP = 5
E_DICT = 6
E_TXTFULL = 7
E_DIV = 8
E_NAME = 9
E_STRUCT = 10
E_BREAK = 11
E_PROT = 12
E_NEST = 13
E_NORUN = 14
E_ABORTQ = 15
E_ABORT = 16
E_UNFIN = 17
E_NOTFOUND = 18

; Page-2 jump table at 0x8000: slot n is at 0x8000+3*n
S_HELP = 0
