# hymn-demo — a pixel-for-pixel port of `hymnbook`

A native Windows window, drawn by `asaotui` widgets, compiled by `as3compiler` AOT.
The reference app is the Rust/GPUI `hymnbook` (Faith Tabernacle Hymn Book, 1000 hymns,
239 with tunes). **This port sounds.** The tunes are the corpus' own MIDI note data
(soprano/alto/tenor/bass, one track each, real onsets and durations), synthesised here
into PCM and played through `flash.media` — so the melody, the parts and the timing are
the hymn's, and only the timbre is this port's. Nothing is faked: search, filters,
selection, the drawer, the palette swap, the follow-scroll, the word wrap, the transport
and the audio are all live. What is *not* the reference's is listed under [Audio](#audio)
by name.

```
node ../run-hymn.cjs              # build + run + capture
node ../run-hymn.cjs --build-only
node ../run-hymn.cjs --keep       # leave the window up
```

`ASC_CC` defaults to `clang`; Windows links `-ld3d12 -ld3dcompiler` from `run-hymn.cjs`.

### Opening the exe by hand gives you a normal app, not a test rig

The capture plan in `HymnMain.onFrame` is **opt-in by file**: it only runs when a file
named `auto-tour` sits next to the executable. `run-hymn.cjs` creates that marker before
the launch and deletes it on the way out (every exit path, including failures), so

```
HymnApp.exe        # double-click: hymn 1, dark palette, drawer open, silent, nothing written
```

and the demo cannot start playing at you the moment you open it. Why a file and not a
flag: AS3 has no `getenv` (the descriptor has no slot for one either), and a second
executable would be two binaries that can drift — the thing you look at and the thing the
gate measures have to be the same binary. With the marker absent the frame handler still
does the two things it *must* do — load the corpus on frame 1 (`G45`) and `model.tick()`
— and returns before phase 0, so the splash still fades and nothing is captured.

## Keys

The window takes the keyboard the way the reference does, and the capture plan drives it
through `stage.dispatchEvent` (a real `KeyboardEvent` up the window's own path), not by
calling the handler:

| key | what it does |
|---|---|
| `↓` / `↑` | step the *visible* list (filtered list, not the 1000), clamped — the first and last hymn do not wrap |
| `Ctrl+B` | slide the library away / back |
| `↓` / `↑` in the search field | belong to the field: while a `WidgetFocus` holds focus the list does not move |

Stepping is a selection change (`model.stepHymn`), so it re-arms the follow flag exactly
like a click does: the reader scrolls to the new hymn's first verse. `hymn.done` carries
both halves as numbers — `keys=ctrlB false->true (restored false) fieldGuard 3->3
down,down 3->9 of 239 reveal=2`: the drawer really closed and reopened, three arrow
presses in the field left the selection at verse 3, and two presses outside it moved the
selection from hymn 4 to 9 in the *filtered* list (239 ranks, not 1000 numbers).

### Clicks are a different channel, and its arity is part of the contract

A synthetic tap is **not** a `MouseEvent`: `UiApp` listens for `TouchEvent.TOUCH_*` and
`PointerRouter` turns a begin/end pair on the same point into a press plus a click, so
the plan dispatches `TOUCH_BEGIN`/`TOUCH_END` on the stage with `localX/localY`
(`stageX/stageY` are derived and this runtime reports `0.0` for both).

And a handler's **arity is part of the contract**: the kit calls `onClick()` with no
arguments (`UiNode.as:490`) and `onChange(v)` with exactly one. This demo shipped
sixteen `onClick: function (e:Object)` handlers, so AVM2 threw
`Error #1063: Argument count mismatch on Function/anonymous(). Expected 1, got 0.` on
every click — theme, window buttons, rows, segments, play — the frame guard swallowed it,
and nothing in the run noticed, because every beat called a model verb directly. Two
things now stand against that:

- `tools/callback-arity.cjs` grades the kit's invocations **and** this demo's
  declarations (270 of them), and `run-hymn.cjs` runs it before the build, so a wrong
  arity fails the run with a file and a line instead of a silent no-op.
- the plan taps real nodes and grades the *effect*: `taps theme+ plus+ row+` with
  `palette light->dark->light size 19->21->19 rowSel 9->13`. Those three numbers cannot
  move unless `onClick` ran, so a `#1063` shows up as a diff instead of a console line.

## Where the pixels come from

Every structural number is copied from the Rust source, not from the screenshot — a
screenshot measurement cannot tell 12 from 14 once antialiasing is in play.

| from | constant | value |
|---|---|---|
| `app.rs` | window | 1280×820 |
| `ui/mod.rs` | page padding / gap | 12 / 12 |
| `titlebar.rs` | titlebar height | 52 |
| `library.rs` | panel width / row height / tile | 380 / 68 / 42 |
| `player.rs` | player height | 100 |
| `reader.rs` | line height | `round(size * 1.62)` |
| `reader.rs` | lyric measure / text width | 780 column − 2×40 padding = 700 |
| `reader.rs` | `A−` / `A+` step | 2.0 |
| `ui/mod.rs` | card radius (sides / player) | 24 / 26 |

Two of those are traps that cost a rebuild each (both measured, both now regression
numbers in `hymn-rects-*.txt`):

- **A stadium is `h/2`, never `999`.** `PaintKit.drawBox` calls
  `Graphics.drawRoundRect(0, 0, w, h, r * 2, r * 2)`, and Flash clamps that *ellipse
  diameter* to the box — `r = 999` on a 69×30 pill becomes a 69-wide, 30-tall ellipse and
  the caps bow out. `plate()` clamps `radius` to `h / 2`.
- **A single-edge border does not exist.** The painter uses one line width for the whole
  rectangle (`borderWidths.top`), so `borderWidths: [0,0,0,2]` draws nothing. The amber
  verse rule is therefore an absolutely positioned 2pt child (`VERSE_RULE`).

## What the captures prove

`HymnMain.onFrame` runs a capture plan; each step is driven by the app's own verbs, so a
picture is evidence for a behaviour and not just for the first frame's paint.

| file | phase | what it proves |
|---|---|---|
| `hymn-splash.png` | frame 40 | the splash: logo tile, title, subtitle, 1100ms loader |
| `hymn-page.png` + `-rects-page.txt` | frame 130 | the page as it opens (hymn 1, no tune) |
| `hymn-tuned.png` + `-rects-tuned.txt` | +20 | a tuned hymn: section map, voice pills, transport |
| `hymn-light.png` + `-rects-light.txt` | +30 | drawer slid away + light palette (also re-installs the kit's) |
| `hymn-dark2.png` + `-rects-dark2.txt` | tap beat | light **back to dark** through a real tap on the titlebar sun — the direction the plan's own switch never takes, and the one whose ink used to stay behind |
| `hymn.done` | phase 4 | `followFrom`/`followTo` (the reader followed the verse), the audio trace, the key walk and the tap beat |
| `hymn-selftest.txt` | load | `hymnbook`'s fourteen ported tests + the tune/note join, as a gate |

`hymn-rects-*.txt` is the numeric assertion channel: the absolute solved rect of every
landmark plus a scan for nodes that escape their parent. Landmarks carry the block kind
suffix, so `bk1v` is hymn 1's second *verse* and `bk1c` the chorus in the position where a
verse would be (`MISSING` is the honest answer for the kind that hymn does not have).
Read it before believing a screenshot — the vision pass cannot see a 2pt gap, the rects
can.

The `palette` line in each dump is the resolved background of eight landmarks, plus
`/same` or `/new` for whether the diff baseline and the fresh resolve share one `Fill`
object. It exists because a screenshot cannot say *which half* of a theme switch broke: a
resolve that keeps the old refinement is fixed in the style layer, a paint that never ran
on a fresh resolve is not. On 2026-11-12 the light capture came out with dark panels and
light-theme ink while this line already reported `reader=16777215` — the resolver was
right and the frame was stale, which is why the runner gates the PIXELS too.

### Mid-song the reader has a second colour state

A palette switch is not the only thing that moves the reader body's contrast. While a tune
plays, `blockView` puts the sounding block's style at full opacity and every other block on
`VERSE_DIM` / `CHORUS_DIM` — upstream's `Focus::Dim => view.opacity(DIMMED)` with
`DIMMED = 0.42`, which is also what `HymnTheme.DIM` holds. The faded styles are
`withPatch(opacity)` copies, not a second hand-written field list, so geometry is
bit-identical and only opacity differs; stopped, nothing is faded (a page you are reading is
not "not yet reached"), which is why `hymn-page.png` / `-tuned.png` / `-light.png` are byte
identical before and after the fade landed.

The beacon carries the assertion: `dim=<current>/<neighbour>`, read from the nodes'
`resolved.opacity`, so a regression that hands the whole reader one style reads `1.00/1.00`
or `0.42/0.42` there. `hymn-playing.png` is the same claim as pixels.

### A theme switch has TWO colour channels, and the ink is the one left behind

The fills switch in the style layer; a text run does not. `PaintKit.measureField` ends with
`field.setTextFormat(f)` — it has to, because `defaultTextFormat` only affects text assigned
*after* it — and a **run outranks `TextField.textColor`**: the paint pass reads the run's
colour and only falls back to `textColor` when the field has no runs at all. So a
colours-only repaint that wrote `textColor` (which is exactly what the widgets did) moved
nothing on screen.

Measured on 2026-11-13 (the user's report: "click the top-right switch, dark is broken"):
after light→dark, **86 of 86 text nodes** had `resolved.text.color` = the new palette,
`tf.textColor` = the new palette, and `tf.getTextFormat().color` = the **old** one. The
reader body, the brand title and every row title were `#14161C` on `#121419`. Run-free
widgets (Input/TextArea, which deliberately paint through `defaultTextFormat` + `textColor`)
never showed it — that asymmetry is what pointed at the run.

Fix: `PaintKit.applyInk(n, field, color)` writes **both** channels — `textColor` and, when
the colour actually changed, a whole-range `setTextFormat` carrying it. Steady state costs
one uint compare. All thirteen widgets that paint a measured label go through it
(`Text`, `Card`, `Checkbox`, `Radio`, `Switch`, `Slider`, `RangeSlider`, `Progress`,
`Badge`, `Chip`, `Avatar`, `Tabs`, `Tooltip`). The harness caught the defect and now proves
the fix: `hymn-dark2.png` went 205106 B (every run stale) → 285073 B (ink present).

### The palette canary (`run-hymn.cjs`)

After the beacon, `run-hymn.cjs` decodes `hymn-page.png`, `hymn-light.png` and
`hymn-dark2.png` and checks five things per palette: the window background at 6,6, the
reader panel at 1240,110 (right of the toolbar, above the title, valid with or without the
drawer), the luma range of the reader title band, and the luma range of the **brand band**
top-left — both must *flip* between palettes. Anything else is `[hymn] PALETTE FAILED` with
the pixel and the expected hex.

The brand band is scanned separately because it is the one run that never moves and never
re-measures: it is what separates "the whole text layer kept the old palette" from "one
label is off". That check is not hypothetical — it is the one that fired on the light→dark
capture, and it stayed red until `PaintKit.applyInk` landed.

That gate exists because a theme switch can fail where no model-side beacon can see it:
both the model and `node.resolved` hold the new palette while the painted frames still
carry the old fills. Measured once (the 121430 B light capture against the usual
~177800 B). That one has not reproduced, so for the fills the gate is evidence rather than
a fix — if it fires, keep the PNG and the dump, they name the node. The **ink** half of the
same gate did catch a real, reproducible defect (see the section above).

## Layout rules this demo depends on

- **Wrapped text is measured, never autosized.** `scrollView` demands a content height
  before layout runs, and an autosized paragraph only knows its height *during* layout.
  `HymnWrap` wraps with a scratch `TextField.textWidth` (the renderer's own metric) and
  every line is given an explicit `Length.px`.
- **Pills are measured, not flexed.** `plate()` sizes itself from the same
  `HymnWrap.width()` call the lyrics use; a row's text is a shrinkable flex item, so a
  45pt box with 45pt of text in it means nothing was ever measured.
- **The wrap measure and the box must be the same number, spelled out.** `HymnWrap.lines()`
  breaks at 700pt, so the column that holds the lines is `Length.px(700)`
  (`HymnTheme.lines(w)`) and not `flexGrow: 1, flexBasis: 0`. A flex-derived width is
  whatever the solver has left over after distribution, so the boxes and the wrap can
  disagree by a few points with nothing in the source to point at.
- **A block's key includes its kind (`bk1v` / `bk1c`).** Verse and chorus boxes differ in
  every measurable way (chorus: `borderWidths: 1`, `gap: 10`, `padding: 22`; verse:
  `padding-left: 12` only). Reuse is keyed on identity, and a style only carries the
  fields it *names* — so handing hymn B's verse the node hymn A built as a chorus keeps
  the chorus' border and gap. Measured on hymn 4 before the fix: block 1 came out 132 tall
  (130) with the gutter 1pt in and a 10pt hole before the lines — exactly `1` + `10` —
  while `node.resolved` read `borderWidths: null, gapX: NaN` for it and for its
  neighbours. The suffix is not cosmetic; it is what makes the two different widgets.
- **The lyric column is capped at 780 and centred.** With the drawer away the reader is
  1200pt wide; without the cap the eye runs the width of the window (measured: 855px of
  dead space on the right because the text hugged the left edge). `rDoc` is the scroll
  child (card width, total height) and `rMeasure` is the 780pt column inside it.
- **A text node draws its line at the TOP of its box, so the box is the only vertical
  control.** `TextWidget.placeRun` sets `tf.y = insetY - TEXT_GUTTER` and has no vertical
alignment of any kind: a 12pt run in a 25pt box hangs from the ceiling with all the slack
below it. Every label in this app states its box (`a null height solves to zero`), so
`txt()` and `plate()` add `padding-top = (box − HymnWrap.lineHeight(family, size, bold))/2`
and let the run sit in the middle. Measured before the fix on the `HYMN 1` badge: 4 device
px above the ink, 26 below (DPR 1.5), i.e. 7pt high — the same 7pt showed on the chips, the
verse discs, `A−`/`A+`, the voice pills and the player's clock. After: 13/17 (≤1.5pt, the
font's own descent asymmetry, which the Rust oracle shows too at 9/10).
- **Every chrome field is written explicitly.** Kit base styles are merged *under* the
  refinement (`Theme.resolve`: control default → override → inherited `text.*` → node),
  so a forgotten `background` inherits white and a forgotten `borderWidths` inherits
  `0xCCCCCC`.
- **`Edges` two-element arrays are `[horizontal, vertical]`**, not `[top/bottom, left/right]`.
## Text and wording come from the corpus, not from a rewrite

Titles, bodies and verse numbering are used **verbatim**. `HymnBook`'s verse splitter is
the Rust one ported line for line (≤2 digits, then `.` / `)` / whitespace; a **line-leading**
dynamic `f ` / `p ` / `mf ` is split off, which is exactly what `split_dynamic` does — it
requires the mark to come first and a capitalised word to follow). An `f` **inside** a line
is left alone, because upstream leaves it alone: `hymns.ndjson` hymn 4 verse 4 reads
`From death's dread sting Thy servants free, f That we may live…`, and the reference prints
that `f` too. So a line like hymn 4's third — `…triumph won;` O let the
song of praise be sung:` — keeps the backtick it has **in `hymns.ndjson` itself** (18 of
the 1000 bodies contain one). That is fidelity, not a rendering bug: the reference prints
the same character from the same string. The same rule explains the `,…` inside hymn 1's
chorus (`Hail,…, all hail,…!`) and the `e-cho` hyphenation upstream already carries.

Labels are the reference's exact strings: `All 1000` / `With tune 239`, `TUNE` badge on a
tuned row, `Parts: Soprano · Alto · Tenor · Bass` (the separator is `" · "`), the left
clock `0:00`, the right clock the tune's own length and `–:––` when there is no tune
(hymn 1 says `No tune yet` under the title instead), and `Experimental tune` where a
missing device would leave a `No audio device` in the same slot.

## Audio

The chain, bottom up: `HymnNotes.as` (239 tunes, 58 652 notes, centiseconds, generated
from the corpus' MIDI by `hymn-data.cjs`) → `HymnSynth.render()` (additive wavetable,
organ drawbars `[1, .55, .35, .28]` or flute `[1, .12]`, 22.05 kHz mono float32, peak
normalised to 0.85 so muting a part changes the mix and not the loudness) →
`Sound.loadPCMFromByteArray` → `vendor/audio_glue.c` (miniaudio: WASAPI / DirectSound /
WinMM). The bar's clock is the model's; the sound is started at a millisecond offset and
then left alone.

| the reference does | this port does |
|---|---|
| rustysynth + `TimGM6mb.sf2` (6 MB GM SoundFont) | wavetable synthesis in AS3, no SoundFont |
| a 1.2 s reverb tail (`TAIL` in `synth.rs`) | dry signal, no tail |
| one render per section, the arrangement being the mixer | one render per (tune, parts, instrument); the section map is only a clock |
| MIDI velocity from the file | the corpus is uniform anyway (measured: every note is velocity 80) |

**What it costs.** ~25 ms to render one 37 s pass (measured 21–40 ms), on the UI thread,
3.29 MB of PCM per image, held for the process (the glue mallocs PCM images and never
frees them; its table holds 64, and the 65th registration throws `#2068` — measured, and
written up as `compiler-gaps.md` G46; this app stops one step short at 56 and says so).
A render happens on a tune's first play and on a voice or
instrument change, so `regs` in the beacon counts them — and the `seek3` beat
below shows a re-render plus a seek landing on 15.10 s of a 15.11 s clock.

**Measured, not assumed.** `hymn.done` carries a four-beat trace of the two clocks side
by side: the model's frame count, and the device's own `SoundChannel.position`.

```
play   dev=0.51 model=0.52 regs=1 stat=playing 1111|Organ
muteS  dev=0.72 model=0.73 regs=2 stat=playing 0111|Organ
flute  dev=0.92 model=0.95 regs=3 stat=playing 0111|Flute
seek3  dev=15.12 model=15.11 regs=3 stat=playing 0111|Flute
```

A silent transport would advance the model and leave `dev` at −1 (no channel) or flat.
And "the mix callback ran" still does not prove anything reached the endpoint, so the
endpoint was recorded with WASAPI loopback (`temp/audloop.exe`) while the app played:
peak 0.0151, RMS 0.0044, dominant 220 Hz. The same endpoint fed a full-scale 440 Hz WAV
returns peak 0.0091 — this host's digital output is attenuated, and the app sits 1.6×
above a full-scale source through it. With `ASC_AUDIO_NULL=1` (the glue's dummy backend,
a test switch) the same loopback records peak 0.000000 while the beacon still says
`playing`: the status string is the runtime's report, the loopback is the ear. Production
builds never set that variable, and the glue keeps the dummy backend out of its default
list for exactly this reason.

`SILENT` used to be printed where the instrument sits. That slot now reads
`Experimental tune` (the reference's own wording) when a device answered, and
`No audio device` when the build or the machine has none — `SoundMixer.areSoundsInaccessible()`
and a `play()` that returns null are what flip it, not a constant.

**One corpus divergence, named.** `abc2mid.py` writes a tune's `length` as the *verse*
part when a hymn has `verse_lines` but no `Chorus:` label, while the MIDI it emits still
holds every phrase. One tune in 239 hits that branch: 631, 17.455 s of metadata against
28.35 s of music. Upstream advances its section map on the shorter number while the
notes keep sounding; this port takes the MIDI's own end, so the clock and the sound
agree. `HymnTunes.as` says which tune and by how much in its header, and
`HymnSelfTest` fails the run if any note ever outlasts its tune again.
