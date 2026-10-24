#!/usr/bin/env bash
# air-gallery/build.sh -- open the asaot.ui component documentation app in a
# window, on either backend.
#
#   ./build.sh           AIR reference arm: mxmlc the app, then `adl app.xml`
#   ./build.sh air <page>  the same, landed straight on a catalog page (e.g. `select`)
#   ./build.sh aot       our AOT arm: stage + compile it, then run the exe
#   ./build.sh swf       compile the SWF and stop (no window, no exe)
#   ./build.sh clean     delete what the two build arms produce
#
# WHY THERE ARE TWO ARMS
# ----------------------
# One tree of AS3, two runtimes: AIR is the REFERENCE (its pixels are what "correct"
# means), and our AOT is what the toolkit exists for. This script makes "look at it"
# a single command on either side, so a difference can be SEEN instead of argued
# about. `run-gallery.cjs` stays the AOT arm's whole recipe (stage, build, tour,
# measure) -- this script only selects the arm, it does not re-implement a build.
#
# WHY THE AIR ARM HAS ITS OWN ENTRY CLASS
# ---------------------------------------
# `demo/DocsMain.as` is the AOT document class AND its headless acceptance tour. The
# tour needs `Stage.dispatchMouse` / `Stage.dispatchWheel` / `Stage.render` -- hooks
# only our AOT has -- so mxmlc rejects that file outright. The AIR arm therefore
# starts from `demo/DocsAir.as`, which mounts the same model + view + UiApp and no
# tour. Same split as everywhere else in this workspace: AIR shows the picture, our
# AOT also proves itself with rects (see ui-demo/demo/DocsAir.as).
#
# REQUIREMENTS
# ------------
#   node         both arms (mxmlc-check.cjs, stage-air.cjs, run-gallery.cjs)
#   AIR SDK      the AIR arm. Point AIRSDK_HOME at the SDK root -- or just have the
#                SDK's bin/ on PATH; the root is then derived from adl/mxmlc.
#   clang        the AOT arm (`--cc clang`; set ASC_CC to name another compiler).
#
# `app.xml` is the source of truth for the window (size, title, renderMode,
# <requestedDisplayResolution>) on BOTH arms -- `--air-app` reads it for the AOT
# build and `adl` reads it at run time. Nothing about the window is repeated here.
set -eu

# `node` is the one tool neither arm can avoid, and the shells this workspace is
# opened from do not always agree on how it is spelled (`node` vs `node.exe`), so it
# is resolved once and can be overridden with NODE=... .
NODE=${NODE:-}
if [ -z "$NODE" ]; then
  NODE=$(command -v node 2>/dev/null || command -v node.exe 2>/dev/null || true)
fi
if [ -z "$NODE" ]; then
  printf 'build.sh: no node on PATH (set NODE=/path/to/node)\n' >&2
  exit 2
fi

HERE=$(cd -- "$(dirname -- "$0")" && pwd)   # .../ui-demo/air-gallery
DEMO=$(cd -- "$HERE/.." && pwd)             # .../ui-demo
APP=$(basename -- "$HERE")                  # air-gallery (or its `standard` twin)
SWF=$APP/GalleryApp.swf

# Which executable spelling this platform wants. The AIR SDK ships BOTH `adl` and
# `adl.exe` in bin/, and on Windows the extension-less one is the Unix shell wrapper
# -- choosing it fails with "cannot execute binary file: Exec format error"
# (measured). node's own filename is the reliable tell: a Windows node is `node.exe`.
case "$(basename -- "$NODE")" in
  *.exe) WIN=1 ;;
  *)     WIN=0 ;;
esac

say() { printf '[build] %s\n' "$*"; }
die() { printf 'build.sh: %s\n' "$*" >&2; exit 2; }

usage() {
  printf 'usage: %s [air [page]|aot|swf|clean]\n\n' "$(basename -- "$0")"
  printf '  air    (default) mxmlc the app, then run it under adl\n'
  printf '  air <page>     same, opened on that catalog page (select, combobox, ...)\n'
  printf '  aot    stage + compile with as-aot, then run the executable\n'
  printf '  swf    compile the SWF only\n'
  printf '  clean  remove the SWF / exe / generated C / tour evidence\n'
}

# ---- path spelling --------------------------------------------------------
# This workspace is driven from Git-Bash AND from WSL, and the two disagree about
# what a Windows path looks like: bash can only exec `/mnt/d/x.exe` or `/d/x.exe`
# (a `D:/x.exe` argument is a relative path there), while the node on this box is the
# WINDOWS build and cannot open either. So a path is offered in both spellings and
# each caller takes the one it can use -- measured, not guessed.
lower() { local s=$1; printf '%s' "${s,,}"; }
upper() { local s=$1; printf '%s' "${s^^}"; }

posix_of() {
  local p=$1
  case "$p" in
    [A-Za-z]:[\\/]*)
      p=${p//\\//}                       # D:\x -> D:/x
      printf '/mnt/%s%s' "$(lower "${p:0:1}")" "${p:2}" ;;
    *) printf '%s' "$p" ;;
  esac
}

win_of() {
  case "$1" in
    /mnt/[A-Za-z]/*) printf '%s:%s' "$(upper "${1:5:1}")" "${1:6}" ;;   # WSL
    /[A-Za-z]/*)     printf '%s:%s' "$(upper "${1:1:1}")" "${1:2}" ;;   # Git-Bash (/c/x)
    *) printf '%s' "$1" ;;
  esac
}

# ---- the AIR SDK ----------------------------------------------------------
# AIRSDK_HOME is this project's one way of naming the SDK (never a hardcoded machine
# path). Falling back to PATH is not a hidden default -- it is how the SDK is
# installed on the dev box -- and the resolved root is printed either way.
sdk_root() {
  if [ -n "${AIRSDK_HOME:-}" ]; then printf '%s\n' "$AIRSDK_HOME"; return 0; fi
  local t p
  for t in adl adl.exe mxmlc mxmlc.bat; do
    p=$(command -v "$t" 2>/dev/null || true)
    [ -n "$p" ] || continue
    printf '%s\n' "$(cd -- "$(dirname -- "$p")/.." && pwd)"
    return 0
  done
  return 1
}

sdk_bin() {  # $1 = sdk root, $2 = tool name (adl|mxmlc) -> an executable path
  local root=$1 base=$2 alt c
  alt=$(posix_of "$root")
  if [ "$WIN" = 1 ]; then
    for c in "$root/bin/$base.exe" "$root/bin/$base.bat" "$root/bin/$base" \
             "$alt/bin/$base.exe" "$alt/bin/$base.bat" "$alt/bin/$base"; do
      if [ -x "$c" ]; then printf '%s\n' "$c"; return 0; fi
    done
  else
    for c in "$root/bin/$base" "$alt/bin/$base" \
             "$root/bin/$base.exe" "$alt/bin/$base.exe"; do
      if [ -x "$c" ]; then printf '%s\n' "$c"; return 0; fi
    done
  fi
  return 1
}

# ---- the two things this script actually does -----------------------------
build_swf() {
  local root=$1 sdkwin
  sdkwin=$(win_of "$root")
  say "AIR SDK: $sdkwin"
  say "mxmlc: demo/DocsAir.as + kit/ + seam/  ->  $SWF"
  # `--sdk` instead of AIRSDK_HOME: this workspace's shells do not all deliver an
  # environment variable to a native child (measured: the value was exported by the
  # calling script and still arrived empty), an argument always does.
  #
  # `--src` is ui-demo itself, NOT demo/: the classes are `package demo`, so the root
  # has to be the directory the `demo/` folder sits in (measured: `--src demo` makes
  # mxmlc look for a top-level `DocsMain` and fail with "无法解析 SWF 的根类").
  ( cd "$DEMO" && "$NODE" ../tools/mxmlc-check.cjs --sdk "$sdkwin" \
      --root demo/DocsAir.as --src . --src ../kit --src ../seam --out "$SWF" )
}

run_air() {
  local root adl page
  page=${1:-}
  root=$(sdk_root) || die 'no AIR SDK found: set AIRSDK_HOME to the SDK root (adl lives in $AIRSDK_HOME/bin)'
  adl=$(sdk_bin "$root" adl) || die "no adl under $root/bin -- is AIRSDK_HOME an AIR SDK root?"
  build_swf "$root"
  # How the app is told which page to open: a sidecar file, because `NativeApplication
  # .argv` does not compile for this class (measured) -- see ui-demo/demo/DocsAir.as.
  # No page means delete the file: the app then lands on the first page, and a stale
  # request from a previous run can never decide what this window shows.
  if [ -n "$page" ]; then
    ( cd "$HERE" && "$NODE" -e '
      require("fs").writeFileSync("air-mode.txt", process.argv[1] + "\n");
    ' "$page" )
    say "page: $page (air-mode.txt)"
  else
    ( cd "$HERE" && "$NODE" -e 'try { require("fs").unlinkSync("air-mode.txt"); } catch (e) {}' )
  fi
  say "adl: $adl"
  say 'the window is open -- close it (or Ctrl-C) to come back to the shell'
  # cwd = this directory: adl resolves <content> relative to the descriptor, and the
  # SWF is written next to app.xml, so the two can never disagree.
  ( cd "$HERE" && exec "$adl" app.xml )
}

run_aot() {
  say 'AOT arm: ui-demo/run-gallery.cjs (stage -> as-aot --air-app -> tour -> run)'
  ( cd "$DEMO" && "$NODE" run-gallery.cjs )
}

# `rm` is not guaranteed in this workspace's bash (measured: "command not found"), so
# removal goes through node -- which both arms need anyway.
clean() {
  # cwd = this directory and a RELATIVE argument: a path handed to node has to be in
  # the Windows spelling either way, and `.` sidesteps the question entirely.
  ( cd "$HERE" && "$NODE" -e '
    const fs = require("fs"), path = require("path");
    const dir = process.argv[1];
    // A live window holds the .exe on Windows (the delete fails with EPERM), so the
    // app is killed first -- the same helper run-gallery.cjs uses at build time.
    try { require("../air-run.cjs").killImage("GalleryApp.exe"); } catch (e) {}
    const names = ["GalleryApp.swf", "GalleryApp.exe", "GalleryApp.c",
                   "GalleryApp.build.json", "GalleryApp.exports.json",
                   "gallery.done", "gallery.txt", "src",
                   // the AIR driver file and the log it writes (tools/air-sweep.cjs
                   // reads that log; a stale one must not survive a clean)
                   "air-mode.txt", "air-trace.txt"];
    for (const n of names) {
      const p = path.join(dir, n);
      if (!fs.existsSync(p)) continue;
      fs.rmSync(p, { recursive: true, force: true });
      console.log("[build] removed " + n);
    }
    // The page PNGs are TRACKED evidence (the README shows them), so they stay.
    console.log("[build] kept gallery-page*.png (evidence, tracked)");
  ' . )
}

case "${1:-air}" in
  air|adl)        run_air "${2:-}" ;;
  aot|native)     run_aot ;;
  swf|compile)
    root=$(sdk_root) || die 'no AIR SDK found: set AIRSDK_HOME to the SDK root (mxmlc lives in $AIRSDK_HOME/bin)'
    build_swf "$root" ;;
  clean)          clean ;;
  -h|--help|help) usage ;;
  *) usage >&2; exit 2 ;;
esac