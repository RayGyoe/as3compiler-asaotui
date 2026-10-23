#!/usr/bin/env bash
# matrix.sh -- wasip1 (strict --target=wasm32-wasip1) size matrix + mitigations.
#
# Reproduces and extends wasip1-size.sh:
#   * adds `-Wl,--strip-debug` (the project's real default; see src/build.ts
#     debugInfoFlags/wasmStripFlags) so the comparison is apples-to-apples with
#     the emscripten 120.3 KiB figure,
#   * adds floor CONTROLS (init/printf/vfprintf/terminate/new/abort) to attribute
#     the delta,
#   * adds mitigation configs (-Oz, -fno-rtti, no -DNDEBUG, LTO, no -fs).
#
# Usage: bash matrix.sh 2>&1 | tee ../matrix.log
set -u

export PATH="/d/Program Files/Git/usr/bin:$PATH"

HERE="$(cd "$(dirname "$0")" && pwd)"
MEAS="$HERE/../.."                 # asaotui/measurements
SRC="$MEAS/yoga-src"
CTL="$HERE/controls"
WASI="/c/Users/rayle/Desktop/as3compiler-aot/build-tools/wasi"
SYSROOT="$WASI/wasi-sysroot-34.0"
RD="$WASI/resource-dir"
AR="/c/Program Files/LLVM/bin/llvm-ar.exe"
OUT="$HERE/matrix"
TARGET="wasm32-wasip1"

CXXBASE=(clang++ "--target=$TARGET" "--sysroot=$SYSROOT" "-resource-dir=$RD")
CCBASE=(clang   "--target=$TARGET" "--sysroot=$SYSROOT" "-resource-dir=$RD")
LIBS=(-L "$SYSROOT/lib/$TARGET/noeh")
NOEXC=(-fno-exceptions -D_LIBCPP_HAS_NO_EXCEPTIONS)
FS=(-ffunction-sections -fdata-sections)

mkdir -p "$OUT"

size() { stat -c %s "$1" 2>/dev/null || echo 0; }
kib()  { awk -v b="$1" 'BEGIN{printf "%.1f", b/1024}'; }

# build_lib <tag> <extra compile flags...>
build_lib() {
  local tag="$1"; shift
  local dir="$OUT/lib-$tag"; mkdir -p "$dir"
  local objs=()
  while IFS= read -r f; do
    local rel="${f#$SRC/}"; local obj="$dir/${rel//\//_}.o"
    "${CXXBASE[@]}" -std=c++20 "${NOEXC[@]}" "$@" "${FS[@]}" -I "$SRC" -c "$f" -o "$obj" || return 1
    objs+=("$obj")
  done < <(find "$SRC/yoga" -name '*.cpp' | sort)
  "$AR" rcs "$OUT/libyoga-$tag.a" "${objs[@]}" || return 1
}

# link_one <outname> <src C/C++ file> <archive|-> <extra link flags...>
# `-` means "no yoga archive". Always adds -Wl,--strip-debug unless $nostrip.
link_one() {
  local name="$1" src="$2" lib="$3"; shift 3
  local objs=()
  if [ "$lib" != "-" ]; then objs=("$lib"); fi
  "${CXXBASE[@]}" -O2 "${NOEXC[@]}" "${LIBS[@]}" -I "$SRC" -x c "$src" -x none "${objs[@]}" \
      -Wl,--strip-debug "$@" -o "$OUT/$name.wasm" || return 1
}

echo "########## [A] floors (stripped) ##########"
"${CCBASE[@]}"  -O2                       -x c "$CTL/c_floor.c"      "${LIBS[@]}" -Wl,--strip-debug -o "$OUT/floor_c.wasm"
"${CXXBASE[@]}" -O2 "${NOEXC[@]}"         -x c "$CTL/c_floor.c"      "${LIBS[@]}" -Wl,--strip-debug -o "$OUT/floor_cpp.wasm"
"${CXXBASE[@]}" -O2 "${NOEXC[@]}"         -x c "$CTL/floor_printf.c" "${LIBS[@]}" -Wl,--strip-debug -o "$OUT/floor_printf.wasm"
"${CXXBASE[@]}" -O2 "${NOEXC[@]}"         -x c "$CTL/floor_vfprintf.c" "${LIBS[@]}" -Wl,--strip-debug -o "$OUT/floor_vfprintf.wasm"
"${CXXBASE[@]}" -O2 "${NOEXC[@]}"         -x c++ "$CTL/floor_new.cc" "${LIBS[@]}" -Wl,--strip-debug -o "$OUT/floor_new.wasm"
"${CXXBASE[@]}" -O2 "${NOEXC[@]}"         -x c++ "$CTL/floor_terminate.cc" "${LIBS[@]}" -Wl,--strip-debug -o "$OUT/floor_terminate.wasm"
"${CXXBASE[@]}" -O2 "${NOEXC[@]}"         -x c "$CTL/floor_abort.c"  "${LIBS[@]}" -Wl,--strip-debug -o "$OUT/floor_abort.wasm"

for f in floor_c floor_cpp floor_printf floor_vfprintf floor_new floor_terminate floor_abort; do
  printf '%-18s %7d B  (%6s KiB)\n' "$f" "$(size "$OUT/$f.wasm")" "$(kib "$(size "$OUT/$f.wasm")")"
done

echo
echo "########## [B] mitigation configs: build libyoga + link yoga_one/yoga_min ##########"
declare -A TAGFLAGS
TAGFLAGS[o2]="-O2 -DNDEBUG"
TAGFLAGS[oz]="-Oz -DNDEBUG"
TAGFLAGS[o2_nrtti]="-O2 -DNDEBUG -fno-rtti"
TAGFLAGS[oz_nrtti]="-Oz -DNDEBUG -fno-rtti"
TAGFLAGS[oz_nnd]="-Oz"
TAGFLAGS[o2_nnd]="-O2"
TAGFLAGS[oz_lto]="-Oz -DNDEBUG -flto"
TAGFLAGS[oz_nofs]="-Oz -DNDEBUG"

for tag in o2 oz o2_nrtti oz_nrtti oz_nnd o2_nnd oz_lto; do
  echo "== build libyoga-$tag : ${TAGFLAGS[$tag]} =="
  # shellcheck disable=SC2086
  build_lib "$tag" ${TAGFLAGS[$tag]} || { echo "  BUILD FAILED"; continue; }
  echo "   libyoga-$tag.a = $(size "$OUT/libyoga-$tag.a") B"
done

# oz_nofs deliberately omits -ffunction-sections/-fdata-sections
echo "== build libyoga-oz_nofs : -Oz -DNDEBUG (NO -ffunction-sections) =="
{
  dir="$OUT/lib-oz_nofs"; mkdir -p "$dir"; objs=()
  while IFS= read -r f; do
    rel="${f#$SRC/}"; obj="$dir/${rel//\//_}.o"
    "${CXXBASE[@]}" -std=c++20 "${NOEXC[@]}" -Oz -DNDEBUG -I "$SRC" -c "$f" -o "$obj" || exit 1
    objs+=("$obj")
  done < <(find "$SRC/yoga" -name '*.cpp' | sort)
  "$AR" rcs "$OUT/libyoga-oz_nofs.a" "${objs[@]}"
}

echo
echo "########## [C] yoga_one / yoga_min per config (stripped) ##########"
printf '%-12s %12s %12s %12s %12s\n' config yoga_one KiB yoga_min KiB
for tag in o2 oz o2_nrtti oz_nrtti oz_nnd o2_nnd oz_lto oz_nofs; do
  [ -e "$OUT/libyoga-$tag.a" ] || continue
  # shellcheck disable=SC2086
  link_one "yoga_one_$tag" "$MEAS/tmp/yoga_one.c" "$OUT/libyoga-$tag.a" ${TAGFLAGS[$tag]} || { echo "$tag one FAIL"; continue; }
  # shellcheck disable=SC2086
  link_one "yoga_min_$tag" "$MEAS/tmp/yoga_min.c" "$OUT/libyoga-$tag.a" ${TAGFLAGS[$tag]} || { echo "$tag min FAIL"; continue; }
  o=$(size "$OUT/yoga_one_$tag.wasm"); m=$(size "$OUT/yoga_min_$tag.wasm")
  printf '%-12s %12d %12s %12d %12s\n' "$tag" "$o" "$(kib "$o")" "$m" "$(kib "$m")"
done

echo
echo "########## [D] strip vs no-strip, and --gc-sections explicit ##########"
# unstripped (the raw shape wasip1-size.sh measured)
"${CXXBASE[@]}" -O2 "${NOEXC[@]}" "${LIBS[@]}" -I "$SRC" -x c "$MEAS/tmp/yoga_min.c" -x none "$OUT/libyoga-o2.a" -o "$OUT/yoga_min_o2_nostrip.wasm"
printf 'yoga_min -O2   unstripped = %d B (%s KiB)\n' "$(size "$OUT/yoga_min_o2_nostrip.wasm")" "$(kib "$(size "$OUT/yoga_min_o2_nostrip.wasm")")"
printf 'yoga_min -O2   stripped   = %d B (%s KiB)\n' "$(size "$OUT/yoga_min_o2.wasm")" "$(kib "$(size "$OUT/yoga_min_o2.wasm")")"

"${CXXBASE[@]}" -O2 "${NOEXC[@]}" -I "$SRC" -x c "$MEAS/tmp/yoga_min.c" -x none "$OUT/libyoga-o2.a" -Wl,--gc-sections "${LIBS[@]}" -Wl,--strip-debug -o "$OUT/yoga_min_o2_gc.wasm"
printf 'yoga_min -O2 + explicit --gc-sections = %d B\n' "$(size "$OUT/yoga_min_o2_gc.wasm")"
cmp -s "$OUT/yoga_min_o2.wasm" "$OUT/yoga_min_o2_gc.wasm" && echo "  (byte-identical to default: wasm-ld gc-sections is already on)" || echo "  (DIFFERS)"

echo
echo "########## [E] delta vs floor_cpp (stripped) ##########"
F=$(size "$OUT/floor_cpp.wasm")
for tag in o2 oz o2_nrtti oz_nrtti oz_nnd oz_lto oz_nofs; do
  [ -e "$OUT/yoga_min_$tag.wasm" ] || continue
  m=$(size "$OUT/yoga_min_$tag.wasm")
  printf 'yoga_min(%s) - floor_cpp = %7d B (%6s KiB)\n' "$tag" "$((m-F))" "$(kib $((m-F)))"
done

echo
echo "done."
