#!/usr/bin/env python3
# Checks the T-state count of TONE's loop (io.s) from the assembler listing: the inner delay loop must
# take 26 T-states per turn and the rest of a half period 86 (60 + the 26 of the last, shorter turn),
# as forth.s's w_tone assumes when it converts Hz into turns. Fails the build otherwise.
# Usage: check_tone.py out/io.lst
# Copyright (C) 2026 Santiago Crespo
# SPDX-License-Identifier: GPL-3.0-or-later
import re
import sys

lst = open(sys.argv[1]).read().split("\n")
i = next(n for n, l in enumerate(lst) if re.search(r"\btone::", l))
cyc = []
for l in lst[i + 3:i + 17]:		# from 1$ to the jr nz, 1$
    m = re.search(r"\[\s*(\d+)\]\s+\d+\s+(\S.*)$", l)
    cyc.append((int(m.group(1)), m.group(2)))
assert cyc[0][1].startswith("1$:") and cyc[-1][1].startswith("jr\tnz, 1$"), cyc
body = [c for c, _ in cyc]
inner = sum(body[5:9])			# dec de .. jr nz, 2$ (12 when taken)
per_half = lambda n: sum(body[:5]) + inner * n - 5 + sum(body[9:])
assert inner == 26, "inner loop: %d T-states, not 26" % inner
for n in (1, 2, 100, 5000):
    assert per_half(n) == 26 * n + 86, "half period with %d turns: %d T-states, not %d" % (n, per_half(n), 26 * n + 86)
print("tone: %d T-states per turn, %d + 26*n per half period: OK" % (inner, per_half(0)))
