#!/usr/bin/env bash
# build-u1-wasip1.sh -- U1 gate, strict `wasm32-wasip1` (i.e. the project's
# `--target wasm --package raw` shape, *not* the emscripten/web shape).
#
#   bash build-u1-wasip1.sh
#
# This exists to close CI blocker (1) of asaotui/measurements/u1-yoga-precheck.md:
# "on a CI with WASI_SDK_HOME, `clang --target=wasm32-wasip1` compiles and links
#  Yoga, and the wasm delta is <= 192 KiB" -- previously untestable on this host
# because there was no WASI sysroot.
#
# Toolchain (installed under build-tools/wasi/, same family as build-tools/.../emsdk):
#   wasi-sysroot-34.0.tar.gz  -> wasi-sysroot-34.0/  (libc, libc++, crt1.o)
#   libclang_rt-34.0.tar.gz  -> resource-dir/lib/wasm32-unknown-wasip1/libclang_rt.builtins.a
#                               (our clang 23 has no wasm builtins of its own)
# The sysroot's LTO libs are stamped `23.1.0-wasi-sdk`; our clang is 23.1.3.
set -e

export PATH="/d/Program Files/Git/usr/bin:$PATH"

HERE="$(cd "$(dirname "$0")" && pwd)"
PROTO="$HERE/../../u1-prototype"
SRC="$HERE/../../measurements/yoga-src"
WASI="/c/Users/rayle/Desktop/as3compiler-aot/build-tools/wasi"
SYSROOT="$WASI/wasi-sysroot-34.0"
RD="$WASI/resource-dir"
AR="/c/Program Files/LLVM/bin/llvm-ar.exe"
OUT="$HERE/build-wasip1"

TARGET="wasm32-wasip1"
# The wasi-sdk sysroot keeps libc++/libc++abi in `eh/` (with exceptions) and
# `noeh/` (without) subdirs, and wasi-sdk's own clang driver picks the right one.
# Our stock clang does NOT, so the link line must name the subdir explicitly --
# otherwise `__cxa_allocate_exception`/`__cxa_throw` stay undefined.
EXC="${EXC:-eh}"                    # eh | noeh
EXTRA_FNOEXC=""
[ "$EXC" = "noeh" ] && EXTRA_FNOEXC="-fno-exceptions -D_LIBCPP_HAS_NO_EXCEPTIONS"
CXX="clang++ --target=$TARGET --sysroot=$SYSROOT -resource-dir=$RD"
CC="clang   --target=$TARGET --sysroot=$SYSROOT -resource-dir=$RD"

run() { printf '+'; printf ' %q' "$@"; printf '\n'; "$@"; }

for p in "$SYSROOT" "$RD/lib/wasm32-unknown-wasip1/libclang_rt.builtins.a" "$SRC/yoga"; do
  [ -e "$p" ] || { echo "ERROR: missing $p (see header comment)" >&2; exit 1; }
done

mkdir -p "$OUT"

# Yoga's own Release flags: -O2 -ffunction-sections -fdata-sections, plus -DNDEBUG
# so its asserts do not abort. NOTE: -DYG_NDEBUG is a no-op in this Yoga revision.
echo "== [1/4] build Yoga for $TARGET (exception model: $EXC) =="
objs=()
while IFS= read -r f; do
  rel="${f#$SRC/}"; obj="$OUT/${rel//\//_}.o"
  run $CXX -std=c++20 -O2 -DNDEBUG $EXTRA_FNOEXC -ffunction-sections -fdata-sections -I "$SRC" -c "$f" -o "$obj"
  objs+=("$obj")
done < <(find "$SRC/yoga" -name '*.cpp' | sort)
run "$AR" rcs "$OUT/libyoga.a" "${objs[@]}"
echo "   -> $(stat -c %s "$OUT/libyoga.a") bytes : libyoga.a"

echo "== [2/4] compile the glue (the ONLY TU that includes <yoga/Yoga.h>) =="
run $CXX -std=c++20 -O2 -DNDEBUG $EXTRA_FNOEXC -ffunction-sections -fdata-sections \
    -I "$SRC" -I "$PROTO" -c "$PROTO/yoga_glue.cc" -o "$OUT/yoga_glue.o"

echo "== [3/4] compile the acceptance test (pure C, no Yoga headers) =="
run $CC -O2 -I "$PROTO" -c "$PROTO/test_layout.c" -o "$OUT/test_layout.o"

echo "== [4/4] link (command model => _start; -L.../$EXC for libc++abi) =="
run $CXX -O2 $EXTRA_FNOEXC "$OUT/test_layout.o" "$OUT/yoga_glue.o" "$OUT/libyoga.a" \
    -L "$SYSROOT/lib/$TARGET/$EXC" -o "$OUT/test_layout.wasm"
echo "   -> $(stat -c %s "$OUT/test_layout.wasm") bytes : test_layout.wasm"

echo
echo "== run (node:wasi) =="
run node --no-warnings "$HERE/run-wasi.mjs" "$OUT/test_layout.wasm"
rc=$?
echo "(exit code $rc)"
exit $rc
