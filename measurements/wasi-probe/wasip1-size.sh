#!/usr/bin/env bash
# wasip1-size.sh -- the wasm delta for CI blocker (1) of u1-yoga-precheck.md.
#
# Compares, on the SAME program shape, "with libyoga.a" vs "without libyoga.a"
# under the strict `wasm32-wasip1` target. Two floors are measured:
#   floor_c   -- linked with the C driver  (no libc++ at all)
#   floor_cpp -- linked with the C++ driver (drags in static libc++/libc++abi)
# The C++ floor is the honest baseline: subtracting the C floor would report
# libc++'s size as if it were Yoga's.
set -e

export PATH="/d/Program Files/Git/usr/bin:$PATH"

HERE="$(cd "$(dirname "$0")" && pwd)"
MEAS="$HERE/.."
SRC="$MEAS/yoga-src"
TMP="$MEAS/tmp"
WASI="/c/Users/rayle/Desktop/as3compiler-aot/build-tools/wasi"
SYSROOT="$WASI/wasi-sysroot-34.0"
RD="$WASI/resource-dir"
LIBY="$HERE/build-wasip1/libyoga.a"   # from build-u1-wasip1.sh
OUT="$HERE/build-wasip1-size"
TARGET="wasm32-wasip1"

[ -e "$LIBY" ] || { echo "ERROR: $LIBY not built yet -- run build-u1-wasip1.sh first" >&2; exit 1; }
mkdir -p "$OUT"

# noeh FIRST/only: everything here is built -fno-exceptions, so libc++/libc++abi
# must come from the noeh subdir. (Linking the eh libc++abi instead fails on
# __cpp_exception / _Unwind_RaiseException.)
CXX="clang++ --target=$TARGET --sysroot=$SYSROOT -resource-dir=$RD -L$SYSROOT/lib/$TARGET/noeh"
CC="clang   --target=$TARGET --sysroot=$SYSROOT -resource-dir=$RD -L$SYSROOT/lib/$TARGET/noeh"

size() { stat -c %s "$1"; }
kib()  { awk -v b="$1" 'BEGIN{printf "%.1f", b/1024}'; }

echo "== wasip1 size matrix: $TARGET, -O2 -fno-exceptions, noeh libc++ =="

# floors
$CC  -O2 -x c "$TMP/c_floor.c" -o "$OUT/floor_c.wasm"
$CXX -O2 -fno-exceptions -x c "$TMP/c_floor.c" -o "$OUT/floor_cpp.wasm"
# DCE probe: new/free only  (-x none so the .a is not parsed as C)
$CXX -O2 -fno-exceptions -I "$SRC" -x c "$TMP/yoga_one.c" -x none "$LIBY" -o "$OUT/yoga_one.wasm"
# full: a real flex row with grow
$CXX -O2 -fno-exceptions -I "$SRC" -x c "$TMP/yoga_min.c" -x none "$LIBY" -o "$OUT/yoga_min.wasm"
# the seam itself (30 functions, driven by the acceptance test)
cp "$HERE/build-wasip1/test_layout.wasm" "$OUT/seam_test.wasm"

C=$(size "$OUT/floor_c.wasm")
F=$(size "$OUT/floor_cpp.wasm")
O=$(size "$OUT/yoga_one.wasm")
M=$(size "$OUT/yoga_min.wasm")
S=$(size "$OUT/seam_test.wasm")

echo
printf '%-26s %8d B   (%6s KiB)\n' 'floor_c   (C driver)'      "$C" "$(kib "$C")"
printf '%-26s %8d B   (%6s KiB)\n' 'floor_cpp (+static libc++)' "$F" "$(kib "$F")"
printf '%-26s %8d B   (%6s KiB)\n' 'yoga_one  (new/free)'       "$O" "$(kib "$O")"
printf '%-26s %8d B   (%6s KiB)\n' 'yoga_min  (real layout)'    "$M" "$(kib "$M")"
printf '%-26s %8d B   (%6s KiB)\n' 'seam_test (30 fns, cases)'  "$S" "$(kib "$S")"

echo
echo "== split the big number: what is libc++ vs what is Yoga =="
printf 'libc++ floor      = floor_cpp - floor_c    = %8d B  (%6s KiB)\n' "$((F-C))" "$(kib $((F-C)))"
printf 'yoga_one          = yoga_one  - floor_cpp  = %8d B  (%6s KiB)\n' "$((O-F))" "$(kib $((O-F)))"
printf 'yoga_min          = yoga_min  - floor_cpp  = %8d B  (%6s KiB)  <-- full flex engine\n' "$((M-F))" "$(kib $((M-F)))"
printf 'seam_test         = seam_test - floor_cpp  = %8d B  (%6s KiB)\n' "$((S-F))" "$(kib $((S-F)))"

echo
echo "== DCE check (does the unreached layout core drop?) =="
printf 'yoga_min - yoga_one = %d B  (%s KiB)\n' "$((M-O))" "$(kib $((M-O)))"
echo "   both link the SAME libyoga.a; a modest positive gap means the layout core is"
echo "   pulled in only when reached, i.e. wasm-ld's GC-sections is working."

echo
echo "== budget (u1-yoga-precheck.md section 6.1, gate B) =="
echo "   wasm delta <= 192 KiB (196,608 B). Compare the yoga_min / seam_test rows."
