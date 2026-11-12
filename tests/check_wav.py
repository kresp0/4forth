#!/usr/bin/env python3
# Frequency of the notes in a WAV recorded from MAME: counts rising zero crossings (around each
# window's mean) in windows of 0.1 s, and prints one line per steady note.
# With --expect f1,f2,... it fails unless each frequency was measured within 1 %.
# Usage: check_wav.py file.wav [--expect f1,f2,...]
# Copyright (C) 2026 Santiago Crespo
# SPDX-License-Identifier: GPL-3.0-or-later
import struct
import sys
import wave

w = wave.open(sys.argv[1])
n, r, ch = w.getnframes(), w.getframerate(), w.getnchannels()
s = struct.unpack("<%dh" % (n * ch), w.readframes(n))[::ch]
win = r // 10
notes = []
for t in range(0, len(s) - win, win):
    seg = s[t:t + win]
    if max(seg) - min(seg) < 1000:
        continue
    m = sum(seg) / len(seg)
    up = [i for i in range(1, len(seg)) if seg[i - 1] <= m < seg[i]]
    if len(up) < 3:
        continue
    f = (len(up) - 1) * r / (up[-1] - up[0])
    if notes and abs(notes[-1][2] - f) < 0.02 * f and notes[-1][1] == t / r:
        notes[-1] = (notes[-1][0], (t + win) / r, (notes[-1][2] + f) / 2)
    else:
        notes.append((t / r, (t + win) / r, f))
for a, b, f in notes:
    print("%6.2f-%6.2f s  %7.1f Hz" % (a, b, f))
if "--expect" in sys.argv:
    want = [float(x) for x in sys.argv[sys.argv.index("--expect") + 1].split(",")]
    miss = [x for x in want if not any(abs(f - x) <= 0.01 * x for _, _, f in notes)]
    if miss:
        sys.exit("not measured within 1 %%: %s Hz" % ", ".join("%g" % x for x in miss))
    print("all of %s Hz within 1 %%" % ", ".join("%g" % x for x in want))
