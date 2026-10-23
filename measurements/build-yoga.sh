#!/usr/bin/env bash
# build-yoga.sh <config-name> [extra clang++ flags ...]
#
# Compiles the 19 Yoga .cpp files (single translation units) into per-config
# object files and archives them into libyoga.a. This is the NATIVE (host) build
# used for the size matrix. Deliberately avoids CMake: its only generated product
# is yogaConfig.cmake (a *package* config for `find_package`, not a header we
# need), and its Release flags are exactly the ones we pass by hand
# (-O2 -ffunction-sections -fdata-sections + --gc-sections / -dead_strip).
#
# Usage:
#   bash build-yoga.sh o2-ndbg-fs -O2 -DNDEBUG -DYG_NDEBUG -ffunction-sections -fdata-sections
set -e
export PATH="/d/Program Files/Git/usr/bin:$PATH"

HERE="$(cd "$(dirname "$0")" && pwd)"
SRC="$HERE/yoga-src"
NAME="$1"; shift
OUT="$HERE/build/$NAME"
mkdir -p "$OUT"

CXXFLAGS=(-std=c++20 -I "$SRC" "$@")

# One object per source file, so -ffunction-sections has per-TU granularity and
# the archive is a real archive (member-per-TU) rather than a single blob.
: > "$OUT/objects.txt"
objs=()
while IFS= read -r f; do
  rel="${f#$SRC/}"
  obj="$OUT/${rel//\//_}.o"
  clang++ "${CXXFLAGS[@]}" -c "$f" -o "$obj"
  objs+=("$obj")
  echo "$obj" >> "$OUT/objects.txt"
done < <(find "$SRC/yoga" -name '*.cpp' | sort)

# Archive (llvm-ar rcs). `rcs` = replace/create + symbol index, the normal shape.
"/c/Program Files/LLVM/bin/llvm-ar.exe" rcs "$OUT/libyoga.a" "${objs[@]}"

echo "config=$NAME"
echo "objects=$(find "$OUT" -name '*.o' | wc -l)"
echo "obj_total_bytes=$(find "$OUT" -name '*.o' -printf '%s\n' | awk '{s+=$1} END {print s}')"
echo "a_bytes=$(stat -c %s "$OUT/libyoga.a")"
