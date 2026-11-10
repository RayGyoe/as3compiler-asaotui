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
| `hymn.done` | phase 4 | `followFrom`/`followTo` (the reader followed the verse) and the audio trace |
| `hymn-selftest.txt` | load | `hymnbook`'s fourteen ported tests + the tune/note join, as a gate |

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
