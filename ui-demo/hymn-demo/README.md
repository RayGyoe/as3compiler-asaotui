# hymn-demo — a pixel-for-pixel port of `hymnbook`

A native Windows window, drawn by `asaotui` widgets, compiled by `as3compiler` AOT.
The reference app is the Rust/GPUI `hymnbook` (Faith Tabernacle Hymn Book, 1000 hymns,
239 with tunes). **This port is silent**: the transport runs a real clock over the tune's
length, the section map tracks it, and the UI says `SILENT` where audio would be — but no
sound is produced. Nothing else is faked: search, filters, selection, the drawer, the
palette swap, the follow-scroll and the word wrap are all live.

```
node ../run-hymn.cjs              # build + run + capture
node ../run-hymn.cjs --build-only
node ../run-hymn.cjs --keep       # leave the window up
```

`ASC_CC` defaults to `clang`; Windows links `-ld3d12 -ld3dcompiler` from `run-hymn.cjs`.

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
| `hymn.done` | +80 | `followFrom`/`followTo`: the reader really followed the verse |

`hymn-rects-*.txt` is the numeric assertion channel: the absolute solved rect of every
landmark plus a scan for nodes that escape their parent. Read it before believing a
screenshot — the vision pass cannot see a 2pt gap, the rects can.

## Layout rules this demo depends on

- **Wrapped text is measured, never autosized.** `scrollView` demands a content height
  before layout runs, and an autosized paragraph only knows its height *during* layout.
  `HymnWrap` wraps with a scratch `TextField.textWidth` (the renderer's own metric) and
  every line is given an explicit `Length.px`.
- **Pills are measured, not flexed.** `plate()` sizes itself from the same
  `HymnWrap.width()` call the lyrics use; a row's text is a shrinkable flex item, so a
  45pt box with 45pt of text in it means nothing was ever measured.
- **The lyric column is capped at 780 and centred.** With the drawer away the reader is
  1200pt wide; without the cap the eye runs the width of the window (measured: 855px of
  dead space on the right because the text hugged the left edge). `rDoc` is the scroll
  child (card width, total height) and `rMeasure` is the 780pt column inside it.
- **Every chrome field is written explicitly.** Kit base styles are merged *under* the
  refinement (`Theme.resolve`: control default → override → inherited `text.*` → node),
  so a forgotten `background` inherits white and a forgotten `borderWidths` inherits
  `0xCCCCCC`.
- **`Edges` two-element arrays are `[horizontal, vertical]`**, not `[top/bottom, left/right]`.
