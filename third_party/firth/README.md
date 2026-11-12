# Firth

Firth by John Hardy, https://github.com/jhlagado/firth, commit `7dec4f31f3fe14b4a802a4a762c42aea49e3d38e`
(2021-06-21), released under the GNU General Public License version 3 (`LICENSE`, copied unchanged).

4Forth's kernel (`src/forth.s`) is derived from it: the register model (top of stack in BC, data stack
through IX, return stack on SP with the instruction pointer on top, IY = NEXT), the threading, the
header layout and the set of word names. The code was rewritten for sdas and for the Genio; no Firth
file is included as such. `../../README.md` lists what was kept and what changed.
