# asaot.ui demo (`asaotui/ui-demo/`)

Runnable demo of the GPUI-inspired AS3 UI toolkit (`asaotui/kit/asaot/ui/`), plus
self-checks that pin the toolkit's core invariants. **One app, three arms**, one
command each:

| Arm | What it is | Command |
|---|---|---|
| AIR (reference) | the docs site on AIR: `mxmlc` → `adl`, no tour | `air-gallery/build.sh` |
| Native (our AOT) | the same tree through `as-aot --air-app`, plus the headless tour | `air-gallery/build.sh aot` |
| Web (our wasm32) | the same tree through `as-aot --target wasm --package web`, served over HTTP | `air-gallery/build.sh web` |

All three arms read the **same** `air-gallery/app.xml`: `--air-app` reads it at build
time (and, on the web, bakes it into the page's virtual filesystem) while `adl` reads
it at run time, so the window (size, title, `renderMode`,
`<requestedDisplayResolution>`) is described once and nothing restates it.

**Live, with nothing to build:** <https://raygyoe.github.io/as3compiler-asaotui/> — the
web arm prebuilt, served from the `gh-pages` branch (8 files, 8.15 MB, byte-identical to
the build output). Refreshing it is `node ../tools/publish-pages.cjs --push`; see
[Publishing the online demo](#publishing-the-online-demo).

```sh
cd asaotui/ui-demo/air-gallery
./build.sh          # mxmlc the SWF, then open it under adl
./build.sh aot      # stage -> as-aot --air-app -> tour -> run the exe
./build.sh web      # stage -> as-aot --target wasm --package web -> serve the page
./build.sh swf      # compile only (a portability check, no window)
./build.sh desc     # show which descriptor / backend --gpu would build from (no build)
./build.sh clean    # drop the SWF / exe / generated C / web page / tour evidence
```

### Choosing what draws the window (`--gpu`)

`app.xml` says `<renderMode>cpu</renderMode>` today, and it is the tracked source of
truth — so `--gpu` does **not** edit it. It derives `app.<mode>.xml` next to it (one
line off `app.xml`, gitignored, removed by `clean`) and points both arms at that file:
`adl <descriptor>` on AIR, `--air-app <descriptor>` for the AOT.

```sh
./build.sh aot --gpu gpu      # GPU composition, the platform's own backend (D3D12)
./build.sh aot --gpu d3d12    # GPU composition, D3D12 named
./build.sh aot --gpu gl       # GPU composition over WGL/OpenGL (Windows only)
./build.sh aot --gpu direct   # AIR's "direct" mode
./build.sh --gpu cpu          # the software raster the descriptor already asks for
./build.sh air select --gpu gl  # flags and the page name may appear in any order
```

The mode travels in **two** places, and both are checked: the descriptor's
`<renderMode>`, and the AOT build's manifest field `gpu-backend` (`--gpu-backend`,
Windows-only, which AIR's XSD has no slot for — `as3compiler/docs/zh-cn/compile.md`
§3.4.6). `run-gallery.cjs` asserts a gpu mode really reached the generated manifest
(`ASC_RENDER_WINGPU=1` plus the backend's own define), because a mode that never
reached the build renders **identically** to the software one and would look honoured.

Nothing about this is observable by eye — all five modes draw the same 42 pages — so
`../tools/buildsh-gpu.cjs` pins the descriptor and the argv for every mode, and
`../tools/mutation-buildsh-gpu.cjs` (5/5) shows that gate goes red when the mapping,
the refusal of unknown modes, or the one-line-diff invariant is broken. The last one
matters because `check-dpi.cjs` requires `app.xml` and its `air-gallery-standard` twin
to differ in exactly one line; a derived descriptor that drifted a second line would
make that A/B two-variable.

The AIR arm starts from `demo/DocsAir.as`, not from the touring `demo/DocsMain.as`: the
tour needs `Stage.dispatchMouse` / `Stage.dispatchWheel` / `Stage.render`, which are OUR
test hooks and do not exist on AIR — mxmlc rejects that file, correctly. See
`../STATUS.md` §3.11.

### The browser arm (`web`)

A window is opened by an executable; a page is not. So `web` cannot reuse
`run-gallery.cjs` (nothing to launch, no `gallery.done` to wait for, no `Stage.render`
to measure) and it has its own runner, `web-gallery.cjs`, which stages
`../air-gallery-web/` (descriptor + `as-image.png` + one shipped font + `demo/**`), builds
with `--target wasm --package web`, and then serves that directory over HTTP — a
`.wasm` cannot be loaded from `file://`, and the server sends `application/wasm`.

```sh
./build.sh web                 # build, then open it (Ctrl-C stops the server)
./build.sh web --no-serve      # build only
./build.sh web --check         # ~0.3 s: the compiler says whether it can start emcc, and is the argv right?
./build.sh web --port 8090     # a different static-server port
./build.sh web --gpu gl        # REFUSED, with a reason: a browser composites itself
```

Two things about it are worth knowing before changing it:

- **The toolchain question is put to the compiler, not re-answered here.** `as-aot
  --package web` used to spawn `<EMSDK_HOME>/upstream/emscripten/emcc` directly, with no
  shell and a PATH-only environment — a `#!/bin/sh` script on Windows, so the spawn could
  not work (`compiler-gaps.md` **G27**). This runner used to stand a PE launcher
  (`tools/emcc-launcher.c`, a shim tree under `.scratch/`) in front of it. as-aot
  **v0.4.240** fixed the compiler instead (it launches `emcc.bat` through `cmd.exe`, keeps
  the inherited environment, joins PATH with the platform delimiter), so **the shim is
  gone**: `EMSDK_HOME` is the real SDK. `--check` now asks `as-aot doctor --json --target
  wasm --package web`, i.e. the same `webToolchainError()` the build runs — a check that
  spawned emcc itself would be a copy of the launch logic, free to drift from it, which
  is exactly how G27 stayed invisible for a round.
- **The page is the same page.** Measured against the native arm's
  `gallery-page0.png` (re-measured after v0.4.239 turned on Skia antialiasing, both arms
  re-rendered): the 48-point sample grid (6 columns x 8 rows, cell centres) is identical
  at **46 points**, total ink differs by **0.85%**, and seven of the eight most common
  colours agree within 0.35%. The leftovers are all glyphs: the page ships its own font
  (a wasm sandbox has no system fonts) while the native arm uses the system one, so text
  rasterises a fraction of a pixel differently — the outlier is the button blue
  `#2563eb` (−5.1%), whose pure-colour count is set by the label's coverage. Clicking a
  nav item in the browser changes the page like it does natively. That is the whole point
  of the arm: the same AS3 tree, three runtimes, one picture.

`../tools/buildsh-web.cjs` pins the decision path `web` takes (the compiler can start
emcc — and a stub `emcc.bat` that exits 1 must come back unusable — the argv, the size
taken from `app.xml`, the refusals, and the generated dir staying git-ignored) without
compiling anything, and `../tools/mutation-buildsh-web.cjs` (7/7) shows that gate goes
red — including a mutant that puts an `emcc` back outside the SDK, i.e. the shape of the
launcher this arm no longer needs.

Nothing under `asaotui/seam/`, `layout-check/`, `diff-check/` or `air-check/` is
modified or vendored; the seam is used read-only.

#### Publishing the online demo

`../tools/publish-pages.cjs` takes what `./build.sh web` left in
`../air-gallery-web/` and puts it on the `gh-pages` branch, which GitHub Pages serves:

```sh
node ../tools/publish-pages.cjs          # stage into .scratch/pages, print what would ship
node ../tools/publish-pages.cjs --serve  # ...and serve it locally (127.0.0.1:8123)
node ../tools/publish-pages.cjs --push   # commit on gh-pages + push
node ../tools/publish-pages.cjs --check  # fetch the live site, compare bytes with the build
```

The branch holds 8 files and nothing else: `index.html` (`GalleryApp.html`, renamed),
`GalleryApp.{js,wasm,data}`, `fonts/arial.ttf`, `app.xml`, `.nojekyll`, `README.md`.
It deliberately does **not** publish `../air-gallery-web/` as it stands, because that
directory also holds `GalleryApp.c` (5.6 MB), `src/` (19 staged copies of `demo/*.as`)
and `GalleryApp.build.json`.

Three invariants worth keeping if this is ever reworked:

- **Byte-identical, or nothing.** The stage step sha256s every copy and refuses a
  mismatch, and `--push` refuses to create a commit when the tree is already on the
  branch. `--check` compares the deployed bytes to the build in *this* tree — a 200 with
  a stale 7 MB wasm looks exactly like a 200 with the right one, so status codes prove
  nothing.
- **A branch, not eight files under `main`.** `.gitignore` states its rule out loud:
  inputs and unreproducible evidence go in, regenerable output does not — and
  `air-*/` is regenerable output. `gh-pages` is where GitHub serves from, so the rule
  survives and a clone of `main` keeps its size.
- **Plumbing, not `git checkout --orphan`.** The working tree carries 5.4 GB of ignored
  build output; `hash-object` → `mktree` → `commit-tree` → `update-ref` touches the
  object database and one ref, and leaves every checked-out file alone.

## Why `--air-app`

`<requestedDisplayResolution>high</requestedDisplayResolution>` gets you **HiDPI**: the
build defines `ASC_DISPLAY_HIGH=1`, the window asks SDL for a native-resolution drawable
and the render surface is allocated in *physical* pixels, so on this box's 150% display
a 700×560 stage produces a **1050×840** screenshot while the AS3 code keeps working in
logical coordinates. AIR's default `standard` renders at 1× and lets the compositor
stretch it — which is exactly what makes text blurry at 150%. See `check-dpi.cjs` for
the measured A/B of those two settings.

`--air-app` compiles `<appDir>/src` **plus every `--as-class-path` root**. The two
shared trees (`seam/` + `kit/`) are named as roots by both runners, so they are read
where they live; `stage-air.cjs` stages only the demo's own sources into `<appDir>/src`.

**Until 阶段二百五十 the toolkit was COPIED in** — `stage-air.cjs` materialized the whole
tree under `src/` (a junction under `src/` was invisible to the walker — measured, see
`CONTRIBUTING-widget.md` §4), and each of the three demos carried a byte-identical
91-file copy of `asaot/`. `--as-class-path` removed the need: there is now one
`kit/` + `seam/` on disk and **no copy to go stale**.

**No `--all-sources` here.** Both runners used to add it — and had to, because
`--air-app`'s default face prunes by a class-reference closure from the document class,
and that closure did not expand a class first discovered by a file carrying free
functions (`compiler-gaps.md` **G13**). Every widget in this toolkit is reached through
a lowercase factory *free function* (`chip.as` → `ChipNode`), so the closure kept the
node classes while dropping their shared superclass `Control` and the per-kind widget
objects their constructors register, and the build stopped at
`unknown superclass 'Control' of 'asaot_ui_AvatarNode'`.

G13 is **fixed** (阶段二百四十九): the plain closure now keeps **94/97** sources and
builds both apps unchanged. `--all-sources` is deliberately *not* re-added — it compiles
all of `src/` and would mask a future regression of exactly this defect. If that
`unknown superclass` error ever returns, the closure has regressed: fix it there, and
let `ui-demo`'s runners stay on the default face so it keeps being visible.
The regression pin is `probes/reach-freefn/run.cjs` (an engine-independent 5-file case),
and `probes/widgets/*` + this demo are the end-to-end half.

## Files

| File | Role |
|---|---|
| `demo/DocsMain.as` | The docs app as an **AIR document class** (`Sprite`) **and** its headless acceptance tour: hand-computed shell rects, block arithmetic on all 42 pages, a real wheel scroll, a real sidebar click, the overlay tree opened/closed, and 8 `gallery-page*.png` screenshots. Writes `gallery.txt` + `gallery.done` (`PASS` / `FAIL <problems>`). |
| `demo/DocsAir.as` | The **AIR arm's** entry class: same model + view + `UiApp`, same subscription, same landing page — **no tour** (the tour's `Stage.dispatchMouse`/`dispatchWheel`/`render` do not exist on AIR). This is what `build.sh` compiles with mxmlc. |
| `demo/DocsWeb.as` | The **web arm's** entry class: same model + view + `UiApp` again, no tour and no file channel, and **no `UncaughtErrorEvent`** — that class is what makes `DocsAir` uncompilable for wasm (it is not implemented here), so the browser needs its own three-line entry rather than a shared one. |
| `air-gallery/build.sh` | **The one command**: `./build.sh` = AIR arm (mxmlc → adl), `./build.sh aot` = AOT arm (delegates to `run-gallery.cjs`), `web` = browser arm (delegates to `web-gallery.cjs`), `swf` = compile only, `desc` = show what `--gpu` would build from, `clean` = remove the artifacts (never the tracked PNGs; it does remove the generated `air-gallery-web/`). `--gpu cpu|gpu|d3d12|gl|direct` picks the window's composition mode by deriving `app.<mode>.xml` (the `air`/`aot` arms only — `web` refuses it). `--check`/`--no-serve`/`--port <n>` belong to the web arm. Resolves the AIR SDK from `AIRSDK_HOME` or `PATH`, and picks `adl.exe` over the SDK's Unix `adl` wrapper on Windows. |
| `web-gallery.cjs` | The web arm's whole recipe: find the emsdk (`EMSDK_HOME`, else the workspace's `build-tools/`), build the Windows `emcc` launcher if needed, stage `../air-gallery-web/`, build with `--target wasm --package web`, verify `.html/.js/.wasm`, then serve the directory with `application/wasm`. `--check` prints the same argv the build execs (one definition, two consumers) and spawns `emcc --version` the way the compiler will; `--serve-only` re-opens an existing build without rebuilding; `ASC_NO_OPEN=1` skips the browser launch. |
| `air-gallery-web/` | **Generated** (gitignored whole): the web app dir. Descriptor and `as-image.png` are byte-verified copies, `src/` is `demo/**` from `stage-air.cjs`, everything else is compiler/emcc output. |
| `run-check.cjs` | Compile **and run** `CheckUi.as` through the AOT; propagates the exit code. |
| `run-gallery.cjs` | Report the compiler tree state, then stage + build (`--air-app`) + launch + wait for `gallery.done` + print the tour + measure the screenshots. **No retry** (G11 is closed: a differing build means the compiler tree itself moved — see the state line it prints). `ASC_AIR_DIR=<dir>` points it at another app dir (that is how `check-dpi.cjs` runs its twin). `ASC_NO_OPEN=1` closes the window as soon as the evidence is in. |
| `build-and-run.cjs` | The login demo, same pipeline. Writes its evidence into `air-uidemo/`. |
| `check-dpi.cjs` | The **descriptor A/B**: builds the same gallery from `air-gallery/app.xml` (`high`) and `air-gallery-standard/app.xml` (`standard`), and requires 1.5× vs exactly 1× with byte-identical tour text. `mutation-dpi.cjs` shows it has teeth. |
| `stage-air.cjs` | Materializes `<appDir>/src` from `demo/` **only** (the toolkit is compiled in place via `--as-class-path`, see above), byte-verifies every copy, prints a content hash and the two shared roots the build must name. Refuses to run without a reviewed `app.xml`. |
| `air-run.cjs` | Shared plumbing for the two runners: descriptor reader (comment-aware), window killer, result-file poller, screenshot measurement. |
| `air-gallery/app.xml` | The docs descriptor (`high`, 1000×700, `renderMode cpu`) — read by ALL THREE arms. `--gpu` never rewrites it; it derives `app.<mode>.xml` instead. |
| `air-gallery-standard/app.xml` | The control arm: identical window settings, `standard` resolution. |
| `../tools/mxmlc-check.cjs` | Compile an AS3 tree with the REAL reference compiler. This is the only evidence that "the toolkit is pure AS3" — our AOT accepts a superset (`--sdk` overrides `AIRSDK_HOME`, and the SDK is otherwise found on `PATH`). |
| `kit-list.cjs` | The `.as` units the AOT must be given explicitly (seam + kit). `ASC_KIT_OVERLAY=staging/<name>` swaps in shadow copies of same-named files (used to stage parallel work). |

## Commands

All commands run from `asaotui/ui-demo/`. Put `clang` on `PATH` (or set `ASC_CC`); on
the dev box it is `C:\Program Files\LLVM\bin`.

```sh
# (a) correctness self-check -- the CI-gateable one
node run-check.cjs                       # -> CHECKUI: 23 checks, 0 failures, exit 0

# (a2) the component-docs tour (42 pages, widget-driven switch, 8 screenshots)
ASC_NO_OPEN=1 node run-gallery.cjs       # -> [gallery] RESULT: PASS
                                         #    air-gallery/gallery{,.done,-page0..7}.{txt,png}

# (a2b) the SAME app on AIR -- one command, both directions
cd air-gallery && ./build.sh             # mxmlc -> adl (window stays open)
./build.sh aot                           # our AOT: stage -> build -> tour -> run
./build.sh web                           # our wasm32: stage -> build -> serve the page
                                         #   (~3 min; --serve-only re-opens it for free)

# (a3) prove the descriptor causes the high-resolution pixels (2 builds, ~2.5 min)
node check-dpi.cjs                       # -> standard 700x560 (1x) vs high 750x563+ ... here 1050x840 (1.5x)
node mutation-dpi.cjs                    # the same, with the control arm flipped: MUST go red
```

The gallery writes its evidence **into its own app dir** (`air-gallery/`, or
`air-gallery-standard/` when `check-dpi.cjs` points `ASC_AIR_DIR` at the twin), so the
high and standard arms cannot overwrite each other's screenshots. The login demo has
only one arm, so it writes `uidemo.txt` / `uidemo.done` / `uidemo-shot.png` into the
demo root, next to its sources — which is also where `run-check.cjs` leaves
`CheckUi.c`/`CheckUi.exe`. (`air-uidemo/` holds the staged tree, the generated `.c` and
the exe.)

## What the demo shows

`air-uidemo/uidemo-shot.png` (500×375 logical, **750×563 physical** at 150%; the file
itself is written into the demo root, see above) is a login
card: a bold title, a gray tagline, a light card (bg `F9FAFB`, 1px `E5E7EB` border,
12px radius) holding two bound text inputs (account prefilled, masked password), a
checked blue checkbox **Keep me signed in**, a full-width solid-blue **Sign in** button,
and a blue **status: ready** line the button rewrites through the model
(`notify(Dirty.VALUE)` → one repaint).

The **Catalog page (index 4)** is where the widgets that had no page of their own
live: `image` (fit), `spinner`, `skeleton`, `tooltip` on the left column and
`table` (2 columns, header + 2 rows, selected row), `accordion` (section 0 open),
`breadcrumb` and `pagination` (page 3 of 20) on the right. Every size is explicit so the
rect report under it stays readable, and it is the page that exposed the auto-width text
defect (`STATUS.md` §3.3 #4): the breadcrumb separator `/` was drawn glued to the next
crumb because its 4px glyph had been published as an 8px box.

The tour now also turns its three diagnostics (no engine node / zero rect / backing never
attached) into **failures**, not log lines: `mutation-gallery-zerorect.cjs` resizes the
catalog image to 0×0 and requires the tour to go red naming `page 4` (baseline green,
restore byte-identical).

`air-gallery/gallery-page{0..6}.png` are the gallery's seven pages; the tour's
hand-computed columns (`colA 24,132,320,374` / `colB 356,132,320,374`) are derived from
700 − 2×24 = 652 content width, two `flexGrow:1` columns and a 12 gap.

The **Advanced page (index 6)** is the last seven widgets that had no page: `select`,
`combobox`, `datePicker`, a `scrollView` of colour bands, a `virtualList` (500 rows, 9
mounted), a `tree` (two open branches, one selected row) and the two floating surfaces
those widgets open — a `popover` (opened by the tour, sampled at the body pixel) and a
`drawer` anchored to the bottom edge, **open on arrival**. The page stops at y = 470
because the drawer starts there: an edge drawer covered the tab strip and there was no
way back out of the page.

That list is no longer maintained by hand: `tools/kind-coverage.cjs` resolves every
`register("<kind>", ...)` to its node class, then to the factory functions that construct
that class, then asks whether this demo CALLS one. It is gate #20 and
`tools/mutation-kind-coverage.cjs` (3/3) proves it goes red — for a renamed call, for a
new kind+factory nothing shows, and for a call that survives only inside a `//` comment
(the scan's first version counted prose as code).

`adl` shows the identical login page in an AIR window; `ui-demo-air.txt` records the
settled rectangles and `AIR-CHECK: 7 checks, 0 failures`.

## Notes / gotchas found while making it run on both backends

These are recorded because they are real, reproducible platform constraints — not
workarounds hidden in the code. The `--air-app`-specific ones are also in
`CONTRIBUTING-widget.md` §4.

1. **mxmlc: one externally-visible definition per file, and the file must be named
   after it.** A package-level function `foo` must live in `foo.as`; a `public class
   Foo` must live in `Foo.as`. On Windows (case-insensitive FS) `foo.as` and `Foo.as`
   are the *same file*, so a top-level `box()` factory and a `Box` class cannot
   coexist. Consequence for this toolkit: the author-facing factories keep their
   documented top-level spelling (`box(...)`, `text(...)`, `button(...)`,
   `checkbox(...)`), and their description **classes** are named `BoxNode` /
   `TextNode` / `ButtonNode` / `CheckboxNode`. The convenience constructors
   `edges()/corners()/fill()/textStyle()` were dropped in favour of the identical class
   statics `Edges.of/Corners.of/Fill.solid/TextStyle.fromAny`.
2. **`with` is reserved.** `StyleRefinement.with()` had to be renamed `withPatch()`;
   mxmlc rejects `with` as a method name ("Syntax error: 'with' is not allowed here")
   even though our AOT accepts it.
3. **A 6-digit colour is opaque.** `Fill` treats `0xRRGGBB` (≤ `0xFFFFFF`) as opaque;
   otherwise the alpha came out 0 and the blue button rendered white. Use
   `Fill.fromArgb` for explicit alpha.
4. **AIR specifics** (from `air-check/`): `adl` never self-exits → the driver calls
   `NativeApplication.exit()`; `trace()` does not reach `adl.exe` stdout on Windows →
   the evidence file is the result channel; the document class must be a `Sprite`
   subclass.
5. **The AOT compile always needs** `-I ./vendor/curl/include -L
   ./vendor/curl/lib/windows-x64 -l zlib` — unless you use `--air-app`, whose generated
   manifest already carries every `-I`/`-L`/`-l`.
6. **`--air-app` needs the document class named explicitly** (`--main-class demo.X`):
   its inference matches any file whose name *ends with* `Main.as`, so `GalleryMain.as`
   makes it guess `demo.Main`, which does not exist. The descriptor does not carry the
   document class — the compiler is told.
7. **`--air-app` rewrites `<filename>.build.json` on every build.** Hand edits do not
   survive; change the descriptor instead.
8. **A recursion hazard worth knowing about**: these descriptors document themselves and
   quote tags inside their XML comments, so any code reading them must blank comments
   before matching (`air-run.cjs::blankComments`). A first-match regex otherwise
   "finds" a setting inside the prose — found the hard way by `mutation-dpi.cjs`.
