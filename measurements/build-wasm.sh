#!/usr/bin/env bash
# build-wasm.sh -- compile Yoga with emscripten (em++) to wasm32 and link the
# probe programs. emcc 3.1.44. This is the `--package web` backend shape.
#
# NOTE: this machine has NO wasi-libc sysroot, so the project's *actual* wasm
# target (`clang --target=wasm32-wasip1` + WASI_SDK_HOME, build.ts:1110) cannot be
# exercised here. emcc's `-sSTANDALONE_WASM` output IS a `wasi_snapshot_preview1`
# module (verified via WebAssembly.Module.imports), so it is the closest runnable
# surrogate for the ABI shape. See the report's M4 for the exact failure of the
# strict --target=wasm32-wasip1 path.
set -e
export PATH="/d/Program Files/Git/usr/bin:$PATH"
HERE="$(cd "$(dirname "$0")" && pwd)"
SRC="$HERE/yoga-src"
O="$HERE/build/wasm-obj"
W="$HERE/build"
mkdir -p "$O" "$W"

# 1) compile 19 TUs
for f in $(find "$SRC/yoga" -name '*.cpp' | sort); do
  rel="${f#$SRC/}"
  em++ -std=c++20 -O2 -DNDEBUG -DYG_NDEBUG -ffunction-sections -fdata-sections \
    -I "$SRC" -c "$f" -o "$O/${rel//\//_}.o"
done
emar rcs "$O/libyoga.a" "$O"/*.o

# 2) link probes
em++ -O2 -sSTANDALONE_WASM "$HERE/tmp/c_floor.c"   -o "$W/wasm_floor.wasm"
for p in yoga_one yoga_min yoga_many; do
  em++ -O2 -sSTANDALONE_WASM -I "$SRC" "$HERE/tmp/$p.c" "$O/libyoga.a" -o "$W/wasm_$p.wasm"
done
# emscripten default (JS glue) == the --package web shape
em++ -O2 -I "$SRC" "$HERE/tmp/yoga_min.c" "$O/libyoga.a" -o "$W/yoga_web.js"

echo wrote "$W"/wasm_*.wasm and "$W"/yoga_web.{js,wasm}
