#!/usr/bin/env bash
# air-gallery/build.sh -- open the asaot.ui component documentation app in a
# window, on either backend.
#
#   ./build.sh           AIR reference arm: mxmlc the app, then `adl app.xml`
#   ./build.sh air <page>  the same, landed straight on a catalog page (e.g. `select`)
#   ./build.sh aot       our AOT arm: stage + compile it, then run the exe
#   ./build.sh web       our WEB arm: stage + compile to wasm32 (Emscripten), then serve
#   ./build.sh swf       compile the SWF and stop (no window, no exe)
#   ./build.sh clean     delete what the build arms produce
#
# WHY THERE ARE THREE ARMS
# ------------------------
# One tree of AS3, THREE runtimes: AIR is the REFERENCE (its pixels are what "correct"
# means), our native AOT is what the toolkit exists for, and the browser is the third
# host the same source has to look right on (the compiler's `--target wasm --package
# web`). This script makes "look at it" a single command on any of them, so a
# difference can be SEEN instead of argued about. The runners stay the whole recipe
# (`run-gallery.cjs` for native, `web-gallery.cjs` for the browser) -- this script only
# selects the arm, it does not re-implement a build.
#
# WHY THE WEB ARM IS THE ODD ONE OUT
# ----------------------------------
# A window is opened by an executable; a page is not. So the web arm cannot reuse
# `run-gallery.cjs` (no process to launch, no `.done` file to wait for, no
# `Stage.render` to measure) and it gets its own runner -- see
# `ui-demo/web-gallery.cjs` for the whole argument, including why the page is built
# from its own staged app dir.
#
# `--gpu` does NOT apply here and is refused by name: in a browser the composition
# backend is the browser's (canvas 2D or WebGL2), chosen by the compiler from
# `<renderMode>` in the descriptor, not by a flag of this script.
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
#   node         all arms (mxmlc-check.cjs, stage-air.cjs, run-gallery.cjs, web-gallery.cjs)
#   AIR SDK      the AIR arm. Point AIRSDK_HOME at the SDK root -- or just have the
#                SDK's bin/ on PATH; the root is then derived from adl/mxmlc.
#   clang        the AOT arm (`--cc clang`; set ASC_CC to name another compiler).
#   Emscripten   the WEB arm. Point EMSDK_HOME at an emsdk root (the directory holding
#                upstream/emscripten/emcc, or emcc.bat on Windows) -- `web-gallery.cjs`
#                also looks in the workspace's build-tools/ so this box needs no
#                variable. Since as-aot v0.4.240 the compiler launches emcc itself on
#                both platforms; this workspace needs no launcher of its own.
#
# `app.xml` is the source of truth for the window (size, title, renderMode,
# <requestedDisplayResolution>) on BOTH arms -- `--air-app` reads it for the AOT
# build and `adl` reads it at run time. Nothing about the window is repeated here.
#
# WINDOW COMPOSITION MODE (--gpu)
# ------------------------------
# `--gpu <mode>` picks what draws the window, on either arm:
#
#   ./build.sh --gpu cpu        software raster (what app.xml says today)
#   ./build.sh --gpu gpu        GPU composition, platform backend (D3D12 on Windows)
#   ./build.sh --gpu d3d12      GPU composition, D3D12 forced
#   ./build.sh --gpu gl         GPU composition over WGL/OpenGL (Windows only)
#   ./build.sh --gpu direct     AIR's "direct" (CPU composition + GPU blit)
#   ./build.sh aot --gpu gl     the same mode on our AOT arm
#
# The mode is NOT written into app.xml. That file is the tracked source of truth,
# and `check-dpi.cjs` requires it to differ from its `air-gallery-standard` twin in
# exactly one line (`requestedDisplayResolution`) -- a hand-flipped <renderMode>
# makes that A/B two-variable and turns the DPI gate red for a reason that has
# nothing to do with the experiment (it did, once). Instead a DERIVED descriptor
# `app.<mode>.xml` is written next to it on demand: gitignored (`.gitignore`:
# `/ui-demo/air-*/*`), removed by `clean`, and handed to BOTH arms -- `adl
# <descriptor>` for AIR, `--air-app` for the AOT. `run-gallery.cjs` then asserts
# the mode reached the generated manifest (ASC_RENDER_WINGPU + the backend's own
# define), because a mode that never reached the build renders IDENTICALLY to the
# software one and would look honoured.
#
# `gl` exists because D3D12 needs Windows 10 1507+ (WDDM 2.0 + feature level 11_0
# are hard requirements of device creation), while opengl32.dll has shipped with
# Windows since XP. The compiler's own notes are in as3compiler's
# docs/zh-cn/compile.md section 3.4.6.
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
  printf 'usage: %s [air [page]|aot|web|swf|desc|clean] [--gpu <mode>] [web flags]\n\n' "$(basename -- "$0")"
  printf '  air    (default) mxmlc the app, then run it under adl\n'
  printf '  air <page>     same, opened on that catalog page (select, combobox, ...)\n'
  printf '  aot    stage + compile with as-aot, then run the executable\n'
  printf '  web    stage + compile to wasm32 (Emscripten), then serve the page\n'
  printf '  swf    compile the SWF only\n'
  printf '  desc   derive/show the descriptor this --gpu would build from, build nothing\n'
  printf '  clean  remove the SWF / exe / generated C / web page / tour evidence\n\n'
  printf '  --gpu <mode>   what draws the window: cpu (default) | gpu | d3d12 | gl | direct\n'
  printf '                 Derives app.<mode>.xml from app.xml (never edits app.xml)\n'
  printf '                 and applies to the air and aot arms. gpu/direct use the\n'
  printf '                 platform backend (D3D12 on Windows); gl forces WGL/OpenGL.\n'
  printf '                 Not available on the web arm (a browser composites itself).\n\n'
  printf '  web flags:  --check       verify the Emscripten SDK + the flags, build nothing\n'
  printf '              --no-serve    build only (open the page yourself over HTTP)\n'
  printf '              --port <n>    port for the built-in static server (default 8080)\n'
}

# ---- the window's composition mode ---------------------------------------
# `app.xml` stays the single source of truth for the window, so `--gpu` never
# rewrites it: it derives `app.<mode>.xml` instead (see the header). Both arms are
# pointed at that file, and the generated build manifest lands where it always
# did, so nothing downstream has to know.
DESC=app.xml    # descriptor NAME inside $HERE -- read by both arms
RENDER=         # the <renderMode> written into a derived descriptor
BACKEND=        # empty = the platform's own GPU backend (D3D12 on Windows)

gpu_mode() {  # $1 = --gpu value -> DESC / RENDER / BACKEND, or a plain refusal
  case "$1" in
    cpu)    DESC=app.cpu.xml;    RENDER=cpu;    BACKEND= ;;
    gpu)    DESC=app.gpu.xml;    RENDER=gpu;    BACKEND= ;;
    d3d12)  DESC=app.d3d12.xml;  RENDER=gpu;    BACKEND=d3d12 ;;
    gl)     DESC=app.gl.xml;     RENDER=gpu;    BACKEND=gl ;;
    direct) DESC=app.direct.xml; RENDER=direct; BACKEND= ;;
    *)      die "unknown --gpu '$1' (known: cpu, gpu, d3d12, gl, direct)" ;;
  esac
  # The backend flag is Windows-only (macOS has Metal, its one window backend).
  # Refusing here names the reason; the compiler would refuse too, but only after
  # the SWF compile and the staging pass.
  if [ "$BACKEND" = gl ] && [ "$WIN" != 1 ]; then
    die '--gpu gl selects the WGL/OpenGL window backend, which is Windows-only (macOS composites on Metal: drop --gpu, or use --gpu gpu)'
  fi
}

# What the two building arms would be told, without building anything. Exists because
# "which descriptor, which backend" is the whole of `--gpu`, and checking it should
# not cost a 90-second compile -- `tools/buildsh-gpu.cjs` (a gate) runs exactly this.
desc() {
  if [ "$DESC" = app.xml ]; then
    say 'no --gpu: both arms use the tracked app.xml as-is, no extra arguments'
    return 0
  fi
  say "descriptor: $DESC  (<renderMode>$RENDER</renderMode>, derived from app.xml)"
  say "run-gallery.cjs args: $(aot_args)"
}

# The AOT arm's argv, in one place so `desc` can show exactly what `aot` would run
# (a mode that is printed but not passed would otherwise look honoured).
aot_args() {
  printf 'run-gallery.cjs'
  [ "$DESC" = app.xml ] || printf ' --app-xml %s' "$DESC"
  [ -z "$BACKEND" ] || printf ' --gpu-backend %s' "$BACKEND"
}

# Write `$DESC` from app.xml with <renderMode>$RENDER</renderMode>. A descriptor with
# no <renderMode> entry is refused rather than patched into place: guessing where the
# element belongs would silently produce a window the caller did not ask for.
write_descriptor() {
  if [ "$DESC" = app.xml ]; then return 0; fi
  ( cd "$HERE" && "$NODE" -e '
    const fs = require("fs");
    const [mode, out] = process.argv.slice(1);
    const src = fs.readFileSync("app.xml", "utf8");
    const re = /<renderMode>[^<]*<\/renderMode>/;
    if (!re.test(src)) {
      console.error("build.sh: app.xml has no <renderMode> under <initialWindow>");
      process.exit(2);
    }
    fs.writeFileSync(out, src.replace(re, "<renderMode>" + mode + "</renderMode>"));
  ' "$RENDER" "$DESC" ) || die "could not derive $DESC from app.xml"
  say "descriptor $DESC  (<renderMode>$RENDER</renderMode>${BACKEND:+, --gpu-backend $BACKEND}, derived from app.xml)"
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
  # SWF is written next to app.xml, so the two can never disagree. The descriptor
  # argument is `$DESC`: app.xml unless `--gpu` derived another one.
  ( cd "$HERE" && exec "$adl" "$DESC" )
}

run_aot() {
  say 'AOT arm: ui-demo/run-gallery.cjs (stage -> as-aot --air-app -> tour -> run)'
  # ARGUMENTS, not environment: the two halves of `--gpu` have to survive a
  # bash -> node.exe boundary, and an inline `VAR=value cmd` prefix is dropped
  # somewhere on that path (measured: the identical command typed by hand arrives
  # with both variables set, the same one run from this script arrives with both
  # empty). An argument has no such gap. The runner still accepts the ASC_* form
  # for callers that drive it by env.
  set -- $(aot_args)
  ( cd "$DEMO" && "$NODE" "$@" )
}

# The web arm's argv. Built in one place for the same reason as aot_args: `--check`
# prints what `web` would exec, and tools/buildsh-web.cjs pins that line.
web_args() {
  printf 'web-gallery.cjs'
  [ "$WEB_CHECK" = 1 ] && printf ' --check'
  [ "$WEB_SERVE" = 1 ] || printf ' --no-serve'
  [ "$WEB_PORT" = "" ] || printf ' --port %s' "$WEB_PORT"
  return 0
}

run_web() {
  say 'web arm: ui-demo/web-gallery.cjs (stage -> as-aot --target wasm --package web -> serve)'
  # ARGUMENTS, not environment -- see run_aot.
  set -- $(web_args)
  ( cd "$DEMO" && "$NODE" "$@" )
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
                   "air-mode.txt", "air-trace.txt",
                   // the whole web app dir: derived from app.xml + demo/** by
                   // web-gallery.cjs, so nothing in it is worth keeping (and a stale
                   // .js/.wasm pair is worse than useless -- a browser that reuses
                   // them shows the previous build)
                   "../air-gallery-web"];
    // `--gpu` derives extra descriptors from app.xml. app.xml itself is TRACKED and
    // never rewritten, so it is not a candidate.
    for (const n of fs.readdirSync(dir)) if (/^app\..+\.xml$/.test(n)) names.push(n);
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

# ---- arguments ------------------------------------------------------------
# Flags may appear anywhere (`./build.sh aot --gpu gl` and `./build.sh --gpu gl air
# select` are the same command), and at most one bare word is a page name. An
# unknown option is an error rather than ignored: `--gpu=gl` and `--gpu gl` both
# work, a typo does not.
ARM=
PAGE=
GPU=
WEB_SERVE=1
WEB_PORT=
WEB_CHECK=0
while [ $# -gt 0 ]; do
  case "$1" in
    air|adl|aot|native|web|swf|compile|desc|clean) ARM=$1; shift ;;
    --gpu)   [ $# -ge 2 ] || die '--gpu needs a value (cpu|gpu|d3d12|gl|direct)'; GPU=$2; shift 2 ;;
    --gpu=*) GPU=${1#--gpu=}; shift ;;
    # web-arm flags. Accepted on any arm so a habitual `--no-serve` is not an error;
    # `web` is the only arm that reads them.
    --check)    WEB_CHECK=1; shift ;;
    --no-serve) WEB_SERVE=0; shift ;;
    --serve)    WEB_SERVE=1; shift ;;
    --port)  [ $# -ge 2 ] || die '--port needs a number'; WEB_PORT=$2; shift 2 ;;
    --port=*) WEB_PORT=${1#--port=}; shift ;;
    -h|--help|help) usage; exit 0 ;;
    -*)      printf 'build.sh: unknown option %s\n' "$1" >&2; usage >&2; exit 2 ;;
    *)
      if [ -n "$PAGE" ]; then printf 'build.sh: unexpected argument %s\n' "$1" >&2; usage >&2; exit 2; fi
      PAGE=$1; shift ;;
  esac
done
ARM=${ARM:-air}

if [ -n "$GPU" ]; then
  # A browser page has no window backend to pick: the compiler derives its
  # composition path from the descriptor's <renderMode>, and that is the one thing a
  # flag here cannot honestly promise (canvas 2D vs WebGL2 is the whole range).
  if [ "$ARM" = web ]; then
    die '--gpu does not apply to the web arm: the browser composites for itself and the page is built from <renderMode> in app.xml (cpu = canvas 2D). Drop --gpu, or edit the descriptor'
  fi
  gpu_mode "$GPU"
  case "$ARM" in
    air|adl|aot|native|desc) write_descriptor ;;
    # `swf` compiles the same SWF in every mode (<renderMode> is a run-time window
    # setting), `clean` must not create what it is about to delete, and `web` is
    # refused above (a browser composites itself) so it never derives one either.
  esac
fi

case "$ARM" in
  air|adl)        run_air "$PAGE" ;;
  aot|native)     run_aot ;;
  web)            run_web ;;
  desc)           desc ;;
  swf|compile)
    root=$(sdk_root) || die 'no AIR SDK found: set AIRSDK_HOME to the SDK root (mxmlc lives in $AIRSDK_HOME/bin)'
    build_swf "$root" ;;
  clean)          clean ;;
  *)              usage >&2; exit 2 ;;
esac