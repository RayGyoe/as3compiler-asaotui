# asaot.ui demo (`asaotui/ui-demo/`)

Runnable demos of the GPUI-inspired AS3 UI toolkit (`asaotui/kit/asaot/ui/`), plus
self-checks that pin the toolkit's core invariants. Two apps, three backends:

| App | What it is | Native (our AOT) | AIR (`mxmlc` → `adl`) |
|---|---|---|---|
| gallery | 5 pages (Home / Widgets / Data / Motion / Catalog) in one window, switched by the `tabs` widget | `node run-gallery.cjs` | — (AOT only, for now) |
| login | the login card from the API design's §8, with a bound model | `node build-and-run.cjs` | `node build-air.cjs` + `node run-adl.cjs` |

Both native apps are built the same way: **`as-aot --air-app <descriptor>`**, so the
AIR application descriptor — not a hand-written build manifest — is the source of
truth for the window (size, title, `renderMode`, `<requestedDisplayResolution>`).

Nothing under `asaotui/seam/`, `layout-check/`, `diff-check/` or `air-check/` is
modified or vendored; the seam is used read-only.

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
| `demo/GalleryMain.as` | Gallery **AIR document class** (`Sprite`): mounts `demo/GalleryView.as` and runs the headless tour — pages 0..4, hand-computed rect assertions, a synthetic `MouseEvent.CLICK` on `tabs` to prove a WIDGET drives the switch, two redundant `reflow()`s to prove they cost nothing, and 5 `gallery-page*.png` screenshots. Writes `gallery.txt` + `gallery.done` (`PASS` / `FAIL <problems>`). |
| `demo/GalleryModel.as` | Observable model for the gallery: `page`, login fields, `listIndex`/`items`, control values, and an animation `phase` flipped by `View.tick` (no timers). |
| `demo/GalleryView.as` | **One `render()` for five pages.** All pages render into the same `body` slot, so switching a page swaps a whole subtree — that is what exposes layout-dirty propagation bugs. |
| `demo/UiDemoMain.as` | Login demo **AIR document class**: mounts `demo/DemoView.as`, asserts the same hand-derived rects the AIR arm asserts (both stages are 500×375, so `uidemo.txt` and `ui-demo-air.txt` can be diffed), renders `uidemo-shot.png`, writes `uidemo.txt` + `uidemo.done`. |
| `demo/DemoModel.as` | Observable model (account / password / remember / status), shared by both login drivers. |
| `demo/DemoView.as` | The login page: title, tagline, card (2 fields + checkbox + button), status line. Pure `render()`. |
| `UiDemoAir.as` | AIR driver for the login demo (`Sprite` document class) — the reference-backend arm of the same view. |
| `CheckUi.as` | Headless self-check: 23 assertions, exits non-zero on any failure. |
| `run-check.cjs` | Compile **and run** `CheckUi.as` through the AOT; propagates the exit code. |
| `run-gallery.cjs` | Report the compiler tree state, then stage + build (`--air-app`) + launch + wait for `gallery.done` + print the tour + measure the screenshots. **No retry** (G11 is closed: a differing build means the compiler tree itself moved — see the state line it prints). `ASC_AIR_DIR=<dir>` points it at another app dir (that is how `check-dpi.cjs` runs its twin). `ASC_NO_OPEN=1` closes the window as soon as the evidence is in. |
| `build-and-run.cjs` | The login demo, same pipeline. Writes its evidence into `air-uidemo/`. |
| `check-dpi.cjs` | The **descriptor A/B**: builds the same gallery from `air-gallery/app.xml` (`high`) and `air-gallery-standard/app.xml` (`standard`), and requires 1.5× vs exactly 1× with byte-identical tour text. `mutation-dpi.cjs` shows it has teeth. |
| `stage-air.cjs` | Materializes `<appDir>/src` from `demo/` **only** (the toolkit is compiled in place via `--as-class-path`, see above), byte-verifies every copy, prints a content hash and the two shared roots the build must name. Refuses to run without a reviewed `app.xml`. |
| `air-run.cjs` | Shared plumbing for the two runners: descriptor reader (comment-aware), window killer, result-file poller, screenshot measurement. |
| `air-gallery/app.xml` | Gallery descriptor (`high`, 700×560, `renderMode cpu`). |
| `air-gallery-standard/app.xml` | The control arm: identical window settings, `standard` resolution. |
| `air-uidemo/app.xml` | Login descriptor (`high`, 500×375). |
| `build-air.cjs` / `run-adl.cjs` / `app-ui-demo.xml` | The AIR reference path: `mxmlc` the `.swf`, run it under `adl` with a timeout. |
| `kit-list.cjs` | The `.as` units the AOT must be given explicitly (seam + kit). `ASC_KIT_OVERLAY=staging/<name>` swaps in shadow copies of same-named files (used to stage parallel work). |

## Commands

All commands run from `asaotui/ui-demo/`. Put `clang` on `PATH` (or set `ASC_CC`); on
the dev box it is `C:\Program Files\LLVM\bin`.

```sh
# (a) correctness self-check -- the CI-gateable one
node run-check.cjs                       # -> CHECKUI: 23 checks, 0 failures, exit 0

# (a2) the multi-page gallery tour (5 pages, widget-driven switch, 5 screenshots)
ASC_NO_OPEN=1 node run-gallery.cjs       # -> [gallery] RESULT: PASS
                                         #    air-gallery/gallery{,-page0..4}.{txt,png}

# (a3) prove the descriptor causes the high-resolution pixels (2 builds, ~2.5 min)
node check-dpi.cjs                       # -> standard 700x560 (1x) vs high 750x563+ ... here 1050x840 (1.5x)
node mutation-dpi.cjs                    # the same, with the control arm flipped: MUST go red

# (b) login demo (SDL2 window; close it to end, or set ASC_NO_OPEN=1)
node build-and-run.cjs                   # -> air-uidemo/uidemo.txt + uidemo-shot.png

# (c) the SAME login view on AIR (needs the AIR SDK; AIRSDK_HOME not set by default)
AIRSDK_HOME=/path/to/AIRSDK node build-air.cjs
AIRSDK_HOME=/path/to/AIRSDK node run-adl.cjs        # writes ui-demo-air.txt, exits 0
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

The **fifth page (Catalog)** is where the widgets that had no page of their own
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

`air-gallery/gallery-page{0..4}.png` are the gallery's five pages; the tour's
hand-computed columns (`colA 24,132,320,374` / `colB 356,132,320,374`) are derived from
700 − 2×24 = 652 content width, two `flexGrow:1` columns and a 12 gap.

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
