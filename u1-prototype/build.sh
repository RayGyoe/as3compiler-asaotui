#!/usr/bin/env bash
# build.sh -- one-shot: build Yoga -> build the glue -> build+link test_layout -> run.
#
#   bash build.sh            # native (clang++ / lld-link) : compile, link, run
#   bash build.sh --wasm     # emscripten (em++)            : compile, link, run under node
#   bash build.sh --clean    # wipe build/ first
#
# Every command this script runs is echoed (see the `run` helper) so check-layout.md
# can quote them verbatim. Reuses the pinned Yoga checkout from the U1 precheck
# (asaotui/measurements/yoga-src, commit 843dba86); it is NOT re-cloned here.
set -e

export PATH="/d/Program Files/Git/usr/bin:$PATH"   # cygwin-ish coreutils on this host

HERE="$(cd "$(dirname "$0")" && pwd)"
SRC="$HERE/../measurements/yoga-src"
CXX="${CXX:-clang++}"
AR="/c/Program Files/LLVM/bin/llvm-ar.exe"

MODE="native"
case "${1:-}" in
  --wasm) MODE="wasm" ;;
  --clean) rm -rf "$HERE/build"; echo "cleaned $HERE/build" ;;
  "" ) ;;
  *) echo "unknown arg: $1" >&2; exit 2 ;;
esac

# echo a command, then run it (shell-escaped so it is copy-pasteable)
run() {
  printf '+'
  printf ' %q' "$@"
  printf '\n'
  "$@"
}

if [ ! -d "$SRC/yoga" ]; then
  echo "ERROR: Yoga source not found at $SRC" >&2
  echo "       (see asaotui/measurements/u1-yoga-precheck.md section 9)" >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# Common: build the yoga static archive for the requested target.
# Yoga's own Release flags are exactly -O2 -ffunction-sections -fdata-sections;
# we keep -DNDEBUG to turn its asserts off (Yoga asserts abort the process).
# ---------------------------------------------------------------------------
build_yoga() { # <compiler> <outdir>
  local CC_="$1" OUT="$2"
  mkdir -p "$OUT"
  local objs=()
  while IFS= read -r f; do
    local rel="${f#$SRC/}"
    local obj="$OUT/${rel//\//_}.o"
    run "$CC_" -std=c++20 -O2 -DNDEBUG -ffunction-sections -fdata-sections \
        -I "$SRC" -c "$f" -o "$obj"
    objs+=("$obj")
  done < <(find "$SRC/yoga" -name '*.cpp' | sort)
  run "$AR" rcs "$OUT/libyoga.a" "${objs[@]}"
  echo "   -> $(stat -c %s "$OUT/libyoga.a") bytes : $OUT/libyoga.a"
}

# ---------------------------------------------------------------------------
if [ "$MODE" = "native" ]; then
  OBJ="$HERE/build/native"
  mkdir -p "$OBJ"

  echo "== [1/4] build Yoga (native) =="
  build_yoga "$CXX" "$OBJ"

  echo "== [2/4] compile the glue (the ONLY TU that includes <yoga/Yoga.h>) =="
  run "$CXX" -std=c++20 -O2 -DNDEBUG -ffunction-sections -fdata-sections \
      -I "$SRC" -I "$HERE" -c "$HERE/yoga_glue.cc" -o "$OBJ/yoga_glue.o"

  echo "== [3/4] compile the acceptance test (pure C, no Yoga headers) =="
  run clang -O2 -I "$HERE" -c "$HERE/test_layout.c" -o "$OBJ/test_layout.o"

  echo "== [4/4] link (C++ driver pulls libcpmt; /OPT:REF = COFF dead-strip) =="
  run "$CXX" -O2 "$OBJ/test_layout.o" "$OBJ/yoga_glue.o" "$OBJ/libyoga.a" \
      -Wl,/OPT:REF -Wl,/OPT:ICF -o "$OBJ/test_layout.exe"
  echo "   -> $(stat -c %s "$OBJ/test_layout.exe") bytes : $OBJ/test_layout.exe"

  echo
  echo "== run =="
  run "$OBJ/test_layout.exe"
  rc=$?
  echo "(exit code $rc)"
  exit $rc
fi

# ---------------------------------------------------------------------------
if [ "$MODE" = "wasm" ]; then
  EXX="${EXX:-em++}"
  ECC="${ECC:-emcc}"
  EOBJ="$HERE/build/wasm"
  mkdir -p "$EOBJ"

  echo "== [1/4] build Yoga (emscripten) =="
  build_yoga "$EXX" "$EOBJ"

  echo "== [2/4] compile the glue (wasm) =="
  run "$EXX" -std=c++20 -O2 -DNDEBUG -ffunction-sections -fdata-sections \
      -I "$SRC" -I "$HERE" -c "$HERE/yoga_glue.cc" -o "$EOBJ/yoga_glue.o"

  echo "== [3/4] compile the acceptance test (wasm) =="
  run "$ECC" -O2 -I "$HERE" -c "$HERE/test_layout.c" -o "$EOBJ/test_layout.o"

  echo "== [4/4] link to JS+wasm (runnable under node) =="
  run "$EXX" -O2 "$EOBJ/test_layout.o" "$EOBJ/yoga_glue.o" "$EOBJ/libyoga.a" \
      -sEXIT_RUNTIME=1 -o "$EOBJ/test_layout.js"
  echo "   -> $(stat -c %s "$EOBJ/test_layout.wasm") bytes : $EOBJ/test_layout.wasm"

  echo
  echo "== run (node) =="
  run node "$EOBJ/test_layout.js"
  rc=$?
  echo "(exit code $rc)"
  exit $rc
fi
