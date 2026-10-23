#!/usr/bin/env bash
# run-u1-wasip1.sh -- build the U1 seam acceptance test for strict wasm32-wasip1
# with the PROJECT'S real wasm flags (strip DWARF unless --debug-info), link it
# with and without LTO, run both under node:wasi, and report sizes.
set -eu

export PATH="/d/Program Files/Git/usr/bin:$PATH"

HERE="$(cd "$(dirname "$0")" && pwd)"
MEAS="$HERE/../.."                 # asaotui/measurements
SRC="$MEAS/yoga-src"
PROTO="$HERE/../../../u1-prototype"
WASI="/c/Users/rayle/Desktop/as3compiler-aot/build-tools/wasi"
SYSROOT="$WASI/wasi-sysroot-34.0"
RD="$WASI/resource-dir"
AR="/c/Program Files/LLVM/bin/llvm-ar.exe"
OUT="$HERE/u1-wasip1"
TARGET="wasm32-wasip1"
LIBS=(-L "$SYSROOT/lib/$TARGET/noeh")

mkdir -p "$OUT"
CXX=(clang++ "--target=$TARGET" "--sysroot=$SYSROOT" "-resource-dir=$RD")
CC=(clang   "--target=$TARGET" "--sysroot=$SYSROOT" "-resource-dir=$RD")
NOEXC=(-fno-exceptions -D_LIBCPP_HAS_NO_EXCEPTIONS)
FS=(-ffunction-sections -fdata-sections)

size() { stat -c %s "$1"; }
kib()  { awk -v b="$1" 'BEGIN{printf "%.1f", b/1024}'; }

build_lib() { # <tag> <extra flags...>
  local tag="$1"; shift
  local dir="$OUT/lib-$tag"; mkdir -p "$dir"; local objs=()
  while IFS= read -r f; do
    local rel="${f#$SRC/}"; local obj="$dir/${rel//\//_}.o"
    "${CXX[@]}" -std=c++20 "${NOEXC[@]}" "$@" "${FS[@]}" -I "$SRC" -c "$f" -o "$obj"
    objs+=("$obj")
  done < <(find "$SRC/yoga" -name '*.cpp' | sort)
  "$AR" rcs "$OUT/libyoga-$tag.a" "${objs[@]}"
}

build_and_run() { # <tag> <stripflag> <extra flags...>
  local tag="$1" strip="$2"; shift 2
  mkdir -p "$OUT/$tag"
  "${CXX[@]}" -std=c++20 -O2 "${NOEXC[@]}" "$@" "${FS[@]}" -I "$SRC" -I "$PROTO" \
      -c "$PROTO/yoga_glue.cc" -o "$OUT/$tag/yoga_glue.o"
  "${CC[@]}" -O2 "$@" -I "$PROTO" -c "$PROTO/test_layout.c" -o "$OUT/$tag/test_layout.o"
  "${CXX[@]}" -O2 "${NOEXC[@]}" "${LIBS[@]}" "$@" \
      "$OUT/$tag/test_layout.o" "$OUT/$tag/yoga_glue.o" "$OUT/libyoga-$tag.a" \
      $strip -o "$OUT/$tag/test_layout.wasm"
  local b; b=$(size "$OUT/$tag/test_layout.wasm")
  printf '%-16s seam_test = %8d B (%6s KiB)\n' "$tag" "$b" "$(kib "$b")"
  echo "   run: node --no-warnings $HERE/../run-wasi.mjs $OUT/$tag/test_layout.wasm"
  node --no-warnings "$HERE/../run-wasi.mjs" "$OUT/$tag/test_layout.wasm" | tail -4
  echo "   (exit ${PIPESTATUS[0]:-0})"
}

echo "== build libyoga variants =="
build_lib o2 -O2 -DNDEBUG
build_lib oz_lto -Oz -DNDEBUG -flto

echo
echo "== [1] -O2 -DNDEBUG + -Wl,--strip-debug (project default shape) =="
build_and_run o2 "-Wl,--strip-debug"

echo
echo "== [2] -Oz -DNDEBUG -flto + -Wl,--strip-debug (LTO) =="
build_and_run oz_lto "-Wl,--strip-debug" -Oz -flto