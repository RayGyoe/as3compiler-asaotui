#!/usr/bin/env bash
# link-yoga.sh
#
# Builds the link-size matrix: the SAME minimal C program (tmp/yoga_min.c) linked
# against each libyoga.a config, with and without COFF dead-code elimination.
#
# COFF equivalent of -Wl,--gc-sections / -Wl,-dead_strip:
#   /OPT:REF  = drop unreferenced functions/data  (needs -ffunction-sections /
#               -fdata-sections at COMPILE time to work per-function)
#   /OPT:ICF  = fold identical COMDATs
# clang's `-Wl,--gc-sections` is IGNORED by lld-link (measured: "warning: ignoring
# unknown argument '--gc-sections'"), so the MSVC spellings must be used here.
set -e
export PATH="/d/Program Files/Git/usr/bin:$PATH"

HERE="$(cd "$(dirname "$0")" && pwd)"
SRC="$HERE/yoga-src"
TMP="$HERE/tmp"
OUT="$HERE/build"
mkdir -p "$OUT"

link() { # <name> <lib> <extra flags...>
  local name="$1" lib="$2"; shift 2
  clang++ -O2 "$TMP/yoga_min.c" -I "$SRC" "$lib" "$@" -o "$OUT/$name.exe" 2>/dev/null
  printf '%-28s %10s B\n' "$name" "$(stat -c %s "$OUT/$name.exe")"
}

# Floors (no Yoga at all)
clang  -O2 "$TMP/yoga_min.c" -I "$SRC" -c -o "$TMP/yoga_min_c.o"
printf '%-28s %10s B\n' "c_floor(printf)"  "$(clang  -O2 "$TMP/c_floor.c" -o "$OUT/c_floor.exe";       stat -c %s "$OUT/c_floor.exe")"
printf '%-28s %10s B\n' "c_floor_cpp"      "$(clang++ -O2 "$TMP/c_floor.c" -o "$OUT/c_floor_cpp.exe"; stat -c %s "$OUT/c_floor_cpp.exe")"

echo "--- with Yoga ---"
link yoga_o2-fs_gc        "$OUT/o2-fs/libyoga.a"        -Wl,/OPT:REF -Wl,/OPT:ICF
link yoga_o2-fs_nogc      "$OUT/o2-fs/libyoga.a"
link yoga_o2-nofs_gc      "$OUT/o2-nofs/libyoga.a"      -Wl,/OPT:REF -Wl,/OPT:ICF
link yoga_o2-nofs_nogc    "$OUT/o2-nofs/libyoga.a"
link yoga_oz-fs_gc        "$OUT/oz-fs/libyoga.a"        -Wl,/OPT:REF -Wl,/OPT:ICF
link yoga_o2-fs-noexc_gc  "$OUT/o2-fs-noexc/libyoga.a"  -Wl,/OPT:REF -Wl,/OPT:ICF
link yoga_oz-fs-noexc_gc  "$OUT/oz-fs-noexc/libyoga.a"  -Wl,/OPT:REF -Wl,/OPT:ICF
