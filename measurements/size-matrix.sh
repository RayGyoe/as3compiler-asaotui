#!/usr/bin/env bash
# size-matrix.sh -- regenerate the whole U1 precheck size matrix and write a log.
#
# Native (host) target, clang 23.1.3, x86_64-pc-windows-msvc, static CRT (/MT).
# Run from the measurements/ dir. Produces:
#   size-matrix.log   full raw output (build lines + final tables + artifact list)
set -e
export PATH="/d/Program Files/Git/usr/bin:$PATH"
HERE="$(cd "$(dirname "$0")" && pwd)"
TMP="$HERE/tmp"
SRC="$HERE/yoga-src"
OUT="$HERE/build"
LOG="$HERE/size-matrix.log"
: > "$LOG"
say() { echo "$@" | tee -a "$LOG"; }

# name | optimization | extra flags
CFGS=(
  "o2-nofs|-O2|-DNDEBUG -DYG_NDEBUG"
  "o2-fs|-O2|-DNDEBUG -DYG_NDEBUG -ffunction-sections -fdata-sections"
  "os-fs|-Os|-DNDEBUG -DYG_NDEBUG -ffunction-sections -fdata-sections"
  "oz-fs|-Oz|-DNDEBUG -DYG_NDEBUG -ffunction-sections -fdata-sections"
  "o2-fs-noexc|-O2|-DNDEBUG -DYG_NDEBUG -ffunction-sections -fdata-sections -fno-exceptions"
  "oz-fs-noexc|-Oz|-DNDEBUG -DYG_NDEBUG -ffunction-sections -fdata-sections -fno-exceptions"
)

say "==== BUILD (.o totals + .a) ===="
for c in "${CFGS[@]}"; do
  IFS='|' read -r name opt extra <<< "$c"
  bash "$HERE/build-yoga.sh" "$name" $opt $extra >> "$LOG" 2>&1
done

say ""
say "config|opt|obj_total_B|archive_B|n_obj"
for c in "${CFGS[@]}"; do
  IFS='|' read -r name opt extra <<< "$c"
  d="$OUT/$name"
  o=$(find "$d" -name '*.o' -printf '%s\n' | awk '{s+=$1}END{print s}')
  a=$(stat -c %s "$d/libyoga.a")
  n=$(find "$d" -name '*.o' | wc -l)
  say "$name|$opt|$o|$a|$n"
done

# ---- linked executable matrix ---------------------------------------------
say ""
say "==== LINK (final .exe bytes; floor = printf program, no Yoga) ===="
clang   -O2 "$TMP/c_floor.c" -o "$OUT/c_floor.exe" 2>/dev/null
clang++ -O2 "$TMP/c_floor.c" -o "$OUT/c_floor_cpp.exe" 2>/dev/null
floor=$(stat -c %s "$OUT/c_floor_cpp.exe")
say "floor_C_driver|$(stat -c %s "$OUT/c_floor.exe")"
say "floor_Cpp_driver|$floor"

link() { # name lib flags...
  local name="$1" lib="$2"; shift 2
  clang++ -O2 "$TMP/yoga_min.c" -I "$SRC" "$lib" "$@" -o "$OUT/$name.exe" 2>/dev/null
  local b; b=$(stat -c %s "$OUT/$name.exe")
  say "$name|$b|delta=$((b-floor))"
}
for c in "${CFGS[@]}"; do
  IFS='|' read -r name opt extra <<< "$c"
  link "min_${name}_gc" "$OUT/$name/libyoga.a" -Wl,/OPT:REF -Wl,/OPT:ICF
done
link "min_o2-fs_nogc" "$OUT/o2-fs/libyoga.a"

say ""
say "-- DCE linearity (cfg oz-fs-noexc, /OPT:REF) --"
for p in yoga_one yoga_min yoga_many; do
  clang++ -O2 "$TMP/$p.c" -I "$SRC" "$OUT/oz-fs-noexc/libyoga.a" -Wl,/OPT:REF -Wl,/OPT:ICF -o "$OUT/${p}_final.exe" 2>/dev/null
  b=$(stat -c %s "$OUT/${p}_final.exe")
  say "$p|$b|delta=$((b-floor))"
done

say ""
say "==== ARTIFACT SIZE LIST (.o per config) ===="
for d in "$OUT"/*/; do
  [ -f "$d/libyoga.a" ] || continue
  say "-- $(basename "$d") --"
  find "$d" -name '*.o' -printf '%s %f\n' | sort -rn | awk '{printf "%8d  %s\n",$1,$2}' >> "$LOG"
done
echo "wrote $LOG"
