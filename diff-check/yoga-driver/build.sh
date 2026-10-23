#!/usr/bin/env bash
# build.sh -- build + run the C/Yoga side of the layout differential harness.
#
# It does NOT rebuild Yoga or the glue: it reuses the already-compiled artifacts
# in u1-prototype/build/native (yoga_glue.o + libyoga.a), which are READ-ONLY.
# All products land in this directory's build/.
#
# Usage:  bash build.sh [path/to/cases.txt]      (default ../spec/cases.txt)
set -e

# coreutils live in /usr/bin, which this host's PATH omits by default.
export PATH="/usr/bin:$PATH"

HERE="$(cd "$(dirname "$0")" && pwd)"
U1="$HERE/../../u1-prototype"

CC="${CC:-clang}"
CXX="${CXX:-clang++}"
OUT="$HERE/build"
mkdir -p "$OUT"

echo "+ $CC -O2 -D_CRT_SECURE_NO_WARNINGS -I $U1 -c yoga_driver.c -o build/yoga_driver.o"
"$CC" -O2 -D_CRT_SECURE_NO_WARNINGS -I "$U1" -c "$HERE/yoga_driver.c" -o "$OUT/yoga_driver.o"

echo "+ $CXX -O2 build/yoga_driver.o $U1/build/native/{yoga_glue.o,libyoga.a} -o build/yoga_driver.exe"
"$CXX" -O2 "$OUT/yoga_driver.o" "$U1/build/native/yoga_glue.o" \
    "$U1/build/native/libyoga.a" -Wl,/OPT:REF -Wl,/OPT:ICF \
    -o "$OUT/yoga_driver.exe"

echo "== run =="
"$OUT/yoga_driver.exe" "${1:-$HERE/../spec/cases.txt}"
rc=$?
echo "(exit code $rc)"
exit $rc
