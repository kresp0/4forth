#!/bin/sh
# All the MAME tests: the scripted ones (tests/t*.txt), every example of the guide (gen_examples.py)
# and the frequencies of TONE in a recorded WAV (check_wav.py). Logs in tests/results/.
# Usage: tests/run_tests.sh [quick]   (quick: only the scripted tests)
# Copyright (C) 2026 Santiago Crespo
# SPDX-License-Identifier: GPL-3.0-or-later
cd "$(dirname "$0")/.." || exit 1
R=tests/results
mkdir -p $R
fail=0
check() {
  res=$(grep "^RESULT" "$R/$1/drive.log" || echo "RESULT none (MAME did not finish)")
  echo "$1: $res"
  case "$res" in *"fail=0"*) ;; *) fail=1 ;; esac
}
for t in tests/t[0-9]*.txt; do
  n=$(basename "$t" .txt)
  if [ "$n" = t05_sound ]; then
    SOUND="-sound sdl -wavwrite $PWD/$R/tone.wav" tests/run_mame.sh "$t" "$R/$n" 60 >/dev/null 2>&1
  else
    tests/run_mame.sh "$t" "$R/$n" 120 >/dev/null 2>&1
  fi
  check "$n"
done
python3 tests/check_wav.py $R/tone.wav --expect 440,1000,262,330,392,523 > $R/tone.txt 2>&1 || fail=1
echo "tone: $(tail -1 $R/tone.txt)"
[ "$1" = quick ] && { [ $fail = 0 ] && echo "ALL PASSED" || echo "SOME TESTS FAILED"; exit $fail; }
python3 tests/gen_examples.py >/dev/null
tests/run_mame.sh tests/gen/t_examples.txt "$R/t_examples" 300 >/dev/null 2>&1
check t_examples
[ $fail = 0 ] && echo "ALL PASSED" || echo "SOME TESTS FAILED"
exit $fail
