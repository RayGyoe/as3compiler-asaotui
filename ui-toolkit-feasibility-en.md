# Our own UI library: what GPUI is worth borrowing

> **Status: evaluation (not implemented, no version number)**. Same precedent as
> [`rust-text-backend.md`](as3compiler/docs/en/rust-text-backend.md): work out what should and should not be done
> before deciding whether to schedule it. This document only makes the technical ruling — it
> implements nothing, and all it adds to `TODO.md` is one **unscheduled pending-items** section
> (it consumes no stage number and no version bump).
>
> (Location: the workspace root, alongside the `talkmed-meeting-aot-*.md` analysis reports.)
>
> **One-line conclusion: yes, it is worth borrowing — but the goal is not "build GPUI again".**
> Borrow its **authoring model** and four things — layout, element identity, data flow, keyboard
> and focus. Do **not** borrow "rebuild the whole element tree every frame" (that runs head-on
> into this project's GC memory red line), and do not borrow its renderer or its text layer
> (the two we already have were calibrated value-by-value against `adl`; replacing them means
> redoing that calibration).
>
> **Implementation path (decided by the user on 2026-10-22)**: this UI library is a **pure AS3**
> implementation (already landed and accepted on three toolchains — see [`seam/`](seam/),
> [`layout-check/`](layout-check/), [`diff-check/`](diff-check/), [`air-check/`](air-check/)).
> Any native path that would require modifying the host compiler (`as3compiler/`) — e.g. inlining
> Yoga for layout — is **shelved**; missing low-level support is merely **logged** in
> [`compiler-gaps.md`](compiler-gaps.md), and **the compiler code is not touched**. Therefore every
> passage below that mentions a Yoga built-in class or `emit.ts`/`build.ts` changes should be read
> as an **option kept for the record**.
> (Note: the measurement figures in §7 predate installing the local WASI toolchain, so a few
> "not measurable on this machine" wordings there are stale — see the Chinese `README.md`.)

---

## 1. Ask the question correctly first: which layer are we missing?

"UI library" covers three layers that can be sold separately. GPUI has all three; we have the
bottom two and a half:

| Layer | What it is | GPUI | Us | Ruling |
|---|---|---|---|---|
| **L1 renderer backend** | rasterization / GPU pipeline, primitives, layers, masks, font atlas | its own GPU pipeline (Metal / D3D / Blade) + the `scene.rs` primitive table | **two already**: `flash.display` → Skia (CPU/GPU), `flash.display3D` → Metal / D3D12 / WebGL (Starling 2.x runs end to end) | **Do not borrow.** A third pipeline is duplicated work |
| **L2 display tree and input** | retained tree, transforms, hit testing, event dispatch, text layout | element tree (the `Drawable`/`ElementDrawPhase` machine in `gpui-src/crates/gpui/src/element.rs:315-348`) + Taffy + `text_system.rs` | **already there**: `DisplayObject` tree, three-phase events, hit testing by *drawn* region, focus + Tab traversal (AIR-aligned), SkParagraph text | **Only automatic layout is missing**; focus/Tab exist but their **shape is limited** (flat scan, 64-object cap, rescanned from scratch on every keypress, no grouping), and shortcuts are still raw `keyCode` |
| **L3 widgets and authoring model** | declarative API, state hoisting, theming, widget set, actions/keymap, accessibility | **this is the core value** | **completely absent** (not one Button/Slider/List in 219 examples) | **Borrow this layer, rewritten in AS3** |

So the real question is not "should we copy GPUI", it is:

> **Fill in L3; reuse L1/L2 as they are, and extend L2 only in one blank (automatic layout) and
> two shapes (Tab order, shortcuts).**

---

## 2. What GPUI actually looks like (facts, with sources)

### 2.1 Lifecycle: the entire element tree is rebuilt every frame

`gpui-src/crates/gpui/src/element.rs:10-14` says it plainly:

> Elements are constructed by calling `Render::render()` on the root view of the window,
> which recursively constructs the element tree from the current state of the application;
> they are laid out by Taffy and painted to the screen by their own `Element::paint()`.
> **"Before the start of the next frame, the entire element tree and any callbacks they have
> registered with GPUI are dropped and the process repeats."** (the quoted sentence runs from the
> end of `element.rs:13` into `:14`.)

That is the **immediate half** of what GPUI calls "hybrid immediate and retained" (`gpui-src/crates/gpui/README.md:3`): the tree is
*re-described* every frame. The **retained half** has two parts: ① the **entity** owned by `App`
(application state, alive across frames); ② `Element::PrepaintState` (`element.rs:17` in the module docs, `:59` for the associated type) — the
**transient UI state** that is "too simple and voluminous to store in every view that needs it"
(hovered or not, scroll offset), kept across frames by the element itself.

### 2.2 The four-pass pipeline

`Element` (`element.rs:52-105`; `request_layout`/`prepaint`/`paint` at `:74`/`:84`/`:96`) is only four things, and the boundaries are sharp:

| Pass | What it does | Our equivalent today |
|---|---|---|
| `Render::render()` | **describe** the element tree from current state | none (users hand-write `new Sprite()` + `addChild`) |
| `request_layout` | hand the style to the layout engine (Taffy), get a `LayoutId` back | **none** |
| `prepaint` | second pass once layout is known: compute **measure**, collect transient state, build hit areas | none (`getBounds` is computed after the fact) |
| `paint` | record primitives into `Scene` | `as_render_object` / `as_render_object_content` (`src/emit.ts:22235` / `:22477`) |

**`prepaint` is the single most valuable pass to copy**: it splits "measure and stash" out of
"draw". The ugly measure-then-place loop that recurs throughout the Flash ecosystem (change a
property, trigger a layout, read a size back) exists precisely because there is no such pass.

### 2.3 `Style` and Taffy

- `Style` (`style.rs:180-322`) is a **flat value table of 38 entries** (counted field by field): `display` / `visibility` /
  `overflow` + `scrollbar_width` + `allow_concurrent_scroll` + `restrict_scroll_to_axis` /
  `position` + `inset` / `size` + `min_size` + `max_size` + `aspect_ratio` /
  `margin` + `padding` + `border_widths` / `align_items` + `align_self` + `align_content` +
  `justify_content` + `gap` / `flex_direction` + `flex_wrap` + `flex_basis` + `flex_grow` +
  `flex_shrink` / `background` + `border_color` + `border_style` + `corner_radii` + `box_shadow` +
  `text` + `mouse_cursor`, plus the six the panel does not list separately: `opacity` / `grid_cols` /
  `grid_rows` / `grid_location` / `debug` / `debug_below`. **11 fields are marked `#[refineable]`**
  (`overflow` / `inset` / `size` / `min_size` / `max_size` / `margin` / `padding` / `border_widths` /
  `gap` / `corner_radii` / `text`), and they take part in **inheriting refine** (parent style → child
  refinement, `derive(Refineable)`) — that mechanism *is* the theming system.
- The layout engine is **Taffy** (`taffy.rs:31` `TaffyLayoutEngine`, `:62` `request_layout`,
  `:187` `compute_layout`, `:345` `layout_bounds`), implementing **web-standard flexbox (and
  grid)**: the `Style → taffy::style::Style` conversion starts at `taffy.rs:439` and maps field by
  field with nothing smuggled in.
- Sizes have a clear three-way split: `AbsoluteLength` / `DefiniteLength` / `Length` (auto), carried
  together with `rem_size` and `scale_factor` (`:436`) — **logical units and device pixels are two
  ends of one conversion chain**, which is isomorphic to the lesson our own `ASC_render_scale` /
  `as_bake_scale` (`src/emit.ts:21797`) and device-ratio work taught us.

### 2.4 Data flow: `App` owns the state, `Context` has `notify`

`_ownership_and_data_flow.rs` opens with: "every model or view in the application is actually owned
by a single top-level object called the `App`". The chain is `App` → `Entity<T>` → `Context<T>`
(`gpui-src/crates/gpui/src/app/context.rs`), and `Context<T>` provides:

- `notify()`: tell the window "I changed, redraw" (**not** a direct call into paint) — `context.rs:221` (`App`'s
  same-named method at `app.rs:3164`);
- `observe()` / `subscribe()`: tell me when another entity changes (cross-object subscription) — `context.rs:64` / `:94`;
- `emit(event)`: broadcast a custom event outwards — `context.rs:780`.

The point is that **notify is the finest granularity and is raised by the object that changed**,
rather than "someone changed something, so redraw the whole tree".

### 2.5 Input: actions / key contexts / keymap / focus / tab order

- **Mouse**: `div().on_click(...)`; **keyboard**: you must bind an **action**
  (`docs/key_dispatch.md`). An action is a type; the keymap is **JSON**, matched by **key context**
  (`div().key_context("menu")`) and then dispatched to the action. **Keyboard mapping is therefore
  data, not code** — changeable at runtime, user-customizable, switchable by focus context.
  (GPUI's `key_dispatch.rs` is **2216 lines / ~85 KB** and `keymap.rs` **1135 lines / ~44 KB** — the
  latter is ~2169 lines together with its submodules `keymap/context.rs` (891) and `keymap/binding.rs`
  (143). **Note**: it is *not* GPUI's second-largest module — `window.rs` is 9979 lines, `elements/div.rs`
  5789, `geometry.rs` 4020, all larger; it sits around tenth (by lines: `window.rs` 9979 > `elements/div.rs` 5789 >
  `geometry.rs` 4020 > `platform.rs` 3907 > `app.rs` 3888 > `elements/list.rs` 3638 > `profiler/journal.rs` 3540 >
  `gestures.rs` 2331 > `profiler.rs` 2225 > `key_dispatch.rs` 2216).
- **Focus**: `FocusHandle` / `FocusId` (`window.rs:543` / `:339`); **Tab order** is `TabStopMap` (`tab_stop.rs:11-23`):
  `insertion_history: Vec<TabStopOperation>` (`Insert` / `Group` / `GroupEnd`) plus a `SumTree`
  maintaining the order (`tab_stop.rs:11-23`: `TabStopMap` at `:11`, the three ops at `:19-23`). Note **`Group`**: the tab order can be
  **group-scoped** (cycling inside a dialog), it is not one global chain.

### 2.6 Accessibility: AccessKit

`_accessibility.rs` states it integrates [AccessKit] (`_accessibility.rs:15`), with two capabilities (`:22-24`): exposing the current UI
state to assistive technology, and responding to actions requested by assistive technology (voice
control pressing "that button"). Identity comes from `ElementId` / `GlobalElementId` (`_accessibility.rs:30`;
`GlobalElementId` is defined at `element.rs:220`).

### 2.7 Rendering: `Scene` is a primitive table

`scene.rs:222-230`: the `Primitive` enum variants = `Shadow` / `Quad` / `Path` / `Underline` /
`MonochromeSprite` / `SubpixelSprite` / `PolychromeSprite` / `Surface`; `:478-495` is `PrimitiveBatch` — the per-type
`Range`s (`Shadows(Range)`, `Quads(Range)`, `Paths(Range)`, …) — plus `Scene.primitive_bounds: BoundsTree<ScaledPixels>`
(`scene.rs:43`, the index module being `bounds_tree.rs`) as the spatial index. **Note**: `StartLayer(Bounds)` is a
`PaintOperation` (`scene.rs:214-216`), not a `Primitive` variant; there is also `PrimitiveKind` (`:202-211`).
**"The GPU only knows the primitive table, not the element tree"** — that is its renderer-backend seam.

---

## 3. What we have on our side (item by item, with evidence)

| Capability | Do we have it? | Evidence |
|---|---|---|
| retained display tree (parent/child, depth, transform matrices, masks, nine-slice) | **yes** | `DisplayObjectContainer_addChild` `src/emit.ts:10607`; render walk `as_render_object` `:22235` / `as_render_object_content` `:22477`; axis-aligned bounding-box specialization `as_do_extents` `emit.ts:21464` (falls back to `as_bounds_xform` `:21168` when rotated) |
| the present chain, in one line | **yes** | `Stage_showWindow` (`src/emit.ts:23979`) → `as_skia_surface_show_window[_gpu]` (`src/runtime.ts:9194`) → `sk_pump_frame` (`vendor/window_glue.cc:758`) / `sk_window_show` (`:1751`) → per-window `on_redraw` = `ASC_window_on_redraw` (`src/emit.ts:23621`) → `ASC_window_render` (`:23197`) → `as_render_object(canvas, stage)` (`:23304`) → Skia → `present_frame` (`vendor/window_glue.cc:496`) |
| control of per-frame repaint cost | **yes** (finer than GPUI) | `ASC_AUTO_BAKE_FRAMES 3` + a recursive **content fingerprint** auto-bakes stable subtrees into `_cache_image`, `emit.ts:21749-21764`; `cacheAsBitmap` takes the same bake path; bake resolution is 1:1 with the destination CTM (`as_bake_scale` `emit.ts:21797`), capped at 4M px (`AS_BAKE_MAX_PIXELS` `:21769`) |
| window-level invalidation | **yes** | `WinCtx.dirty` `vendor/window_glue.cc:387`; **only dirty windows re-rasterize** `:809-820`; one application-wide frame clock dirties **every visible window** `:775-800` |
| pixel-level dirty rectangles | **no** | `as_show_redraw_regions` only records and never paints; the comment says outright "this render walk has no AIR-style region list" (`src/runtime.ts:177-188`, the key comment at `:178`) |
| three-phase events (capture/target/bubble) | **yes**, calibrated against `adl` | `as_disp_target` `src/emit.ts:10043-10070` (defined at `:10052`, including the measured convention that "a capture listener on the target itself never runs in AIR") |
| hit testing | **yes**, by **drawn region** rather than child bounding boxes | `as_pick_hit_local` `src/emit.ts:15998` → `as_obj_region_hit_local` `:16043` → `as_obj_hit_local` `:15961` (forward declarations `:15872`/`:15873`) |
| GPU render path | **yes** | `vendor/stage3d_glue.mm` / `stage3d_d3d.cc` / `stage3d_webgl.cc` / `metal_glue.mm` / `d3d_glue.cc`; Starling 2.x end to end (`examples/air-starling-demo/`, an external fixture) |
| text layout (including measurement) | **yes** | the SkParagraph route ([`flash-text.md`](as3compiler/docs/en/flash-text.md) / [`skia.md`](as3compiler/docs/en/skia.md)); measurement `as_tf_paragraph` `src/emit.ts:18493` → `TextField_get_textWidth`→`as_skia_textlayout_max_width` `:18796` / `TextField_get_textHeight`→`as_skia_textlayout_height` `:18808`; the lowest-level advance primitive `sk_text_measure` `vendor/skia_text_glue.cc:308` |
| **automatic layout (flexbox/grid/constraints)** | **no** | `grep -riE "flexbox\|yoga\|taffy\|layout_engine"` on `src/*.ts` returns nothing; x/y/width/height are always written by user code |
| **focus / Tab traversal** | **yes, and calibrated against `adl`** | `as_focus_obj` (a permanent GC root; `gc_mark_ptr` at `emit.ts:5686`) `src/emit.ts:10782`; `as_set_focus` `:10827` (bubbling focusOut/focusIn + caret-blink restart); `as_tab_scan` `:10860` + `as_focus_tab` `:10881` (Tab/Shift+Tab wrap both ways, `tabEnabled` filter, first/last when nothing is focused, keyUp delivered to the new focus) |
| ↑ but the Tab order's **shape** is limited | **yes** | ① every Tab **rescans the whole tree from scratch** (`as_tab_scan`, depth-first, recording display ordinals); ② a hard cap of **64 focusable objects**, past which "Tab simply stops moving" (the code comment says so, `emit.ts:10857`; `tabs[64]` and the cap argument at `:10884-10886`); ③ **no grouping** (no notion of cycling inside a dialog/modal); ④ `tabIndex` is only initialized to `-1` and takes no part in ordering (`emit.ts:10548`) — the order is display-list pre-order |
| **actions / keymap (configurable shortcuts)** | **no** | the keyboard is only `SDL_KEYDOWN` → raw `keyCode` events (`vendor/window_glue.cc:1360`); no contexts, no binding table, no user customization |
| **touch / gestures** | **class yes, input no** | the `TouchEvent` class is complete (`src/emit.ts:11987-12018`, stage 93), but the window backend **forwards no touch events at all** (`grep FINGER\|TOUCH` on `window_glue.cc`: nothing), and `Multitouch.maxTouchPoints` is always `0` (`:10333`) |
| **accessibility** | **no** (the whole `flash.accessibility` package is absent) | `grep -rn "flash.accessibility\|AccessibilityProperties\|AccessibilityImplementation" src/*.ts` finds **nothing**; `grep -rin "accessibility" src/*.ts` hits only one unrelated comment (`src/emit.ts:26272`, about the `ACCESSIBILITY` marker in a visibility test); `Keyboard.isAccessible` (`emit.ts:14848`) and `SoundMixer.areSoundsInaccessible` (`:12981`) are spelled differently and are one-off implementations, so they do not constitute the `flash.accessibility` surface |
| **widget set** | **no** | no Button/Slider/List/ScrollBar/Tooltip among the 219 `examples/*.as`; `lib/` holds no `.as` library either (only the ANE host C/H) |
| IME / composition input | **yes** | `SDL_TEXTEDITING` / `SDL_TEXTINPUT` → the marked-text channel (`vendor/window_glue.cc:1421` / `:1440`), stage 135 |
| window capability surface | **yes, and broad** | `NativeWindow` has **43** members (23 getter properties + 16 instance methods + 4 static constants, `src/symbols.ts:1783-1894`; plus 11 setters, paired by name with the getters): activate/minimize/maximize/restore/orderInFrontOf/globalToScreen/listOwnedWindows… |
| display/interaction/event examples | **39** top-level `.as` files (plus **12** subdirectories such as `textfield/`, `air-starling-demo/`, `shmup-stage3d/`) | `examples/` |

**The estate in one sentence**: the heavy lifting of L1/L2 is already done, and it is closer to AS3
semantics than GPUI is (hit testing by drawn region, the capture-phase convention, the 1:1 pixel
bake convention and Tab traversal are all calibrated against `adl`). **What we are missing is all of
L3, plus one blank in L2 (automatic layout) and two shape debts (Tab order, shortcuts).**

---

## 4. Ruling item by item

> The GPUI source locations in this section's parentheticals are relative to the workspace
> `asaotui/`; repeated `style.rs`/`element.rs` etc. drop the prefix, whose full form is
> `gpui-src/crates/gpui/src/<file>` (submodules like `app/context.rs` likewise).

### 4.1 Worth borrowing **directly** (concept and shape as-is, implementation rewritten in AS3)

| # | What in GPUI | Why it is worth borrowing | How it lands here |
|---|---|---|---|
| B1 | **declarative `render()` describing a tree** (`gpui-src/crates/gpui/src/element.rs:10-14`) | kills the whole class of "hand-written addChild/removeChild leaks one place and you get a memory/visual leak" bugs | an AS3-side `render():Node`; the node tree lives in the `asaot.ui` namespace |
| B2 | **`Style` as a flat value table + `refine` inheritance** (`style.rs:180-322`; 11 `#[refineable]` fields drive the inheritance) | theme/style reuse; avoids AIR's "every widget reads a theme static table itself" | a `Style` class + `refine(parent)`; copy the `AbsoluteLength` / `Length`(auto) three-way split |
| B3 | **the `prepaint` pass (measure and stash separated from draw)** (`element.rs:84-95`) | the only structural fix for the Flash-style measure/arrange loop | `measure()` → `arrange()` → `paint()` |
| B4 | **transient state separated from application state (`PrepaintState`)** (`element.rs:59`) | hover/scroll/pressed belong to the **widget**, not to the business object | an `ElementState` table keyed by node key |
| B5 | **`notify()`-style finest-granularity redraw signal** (`app/context.rs:221`) | replaces "dispatch a custom event and hope somebody knows what to repaint" | an `Observable` + one **central redraw scheduler**, wired into the existing `WinCtx.dirty` |
| B6 | **actions + key context + JSON keymap** (`docs/key_dispatch.md`; `key_dispatch.rs` 2216 lines + `keymap.rs`/`keymap/` 2169 lines) | keyboard mapping becomes **data**: runtime-changeable, context-switchable, user-customizable | an `ActionRegistry` + context strings + a keymap JSON; the first thing users migrating AIR apps will actually notice |
| B7 | **Tab order as an incrementally maintained, groupable tree** (`TabStopMap`: `Insert`/`Group`/`GroupEnd` + `insertion_history` + `SumTree`, `tab_stop.rs:11-23`) | we do have Tab traversal, but it is **flat, rescanned from scratch on every keypress, hard-capped at 64 focusable objects, and ungrouped** (see §3). A real UI that exceeds 64 focusables has Tab stop working entirely, and in-dialog cycling is impossible | add a `FocusChain` on top of the existing `as_focus_obj`/`as_focus_tab`: group enter/exit push/pop, incrementally maintained order; treat `as_tab_scan`'s 64 cap as a **known boundary** to re-evaluate (not something to quietly raise) |
| B8 | **the "GPU only knows the primitive table, not the element tree" renderer seam** (`scene.rs:222-230` primitive table + `bounds_tree.rs` spatial index) | makes the widget layer **backend-agnostic**: one Skia path, one Stage3D path, one body of widget code | three seams: `NodeTree` / `LayoutEngine` / `Renderer` (see §6) |

### 4.2 Must be **adapted before borrowing**

| # | GPUI's approach | Why it cannot be copied | Adaptation |
|---|---|---|---|
| R1 | **rebuild the whole tree every frame** (`element.rs:10-14`) | see §5: it runs head-on into the GC red line, and our tree is already retained | **keyed reconcile**: node path/key → reuse the old node, and only write back what changed |
| R2 | **layout delegated to Taffy (Rust)** (`taffy.rs:31` `TaffyLayoutEngine`) | wrong language; but flexbox's semantic complexity is real, and **writing our own would violate AGENTS.md §0 ("do not take a detour because it is hard")** | make the layout engine an **opaque seam** (same precedent as the 15-function seam in `rust-text-backend.md`): link **Yoga** first (C API, MIT, compiles to wasm), and have AS3 know only the seam, so the engine can be swapped wholesale later |
| R3 | **Rust's type system carrying the API shape** (`IntoElement` / `impl Trait` / `cx` under ownership rules; `element.rs:52` the `Element: IntoElement` trait) | AS3 has none of these; imitating them hard produces an awkward API | rewrite with AS3 idioms: interfaces + closures + vtable dynamic dispatch; `render()` returns `Node`, not a generic |

### 4.3 Explicitly **not borrowing**

| # | What in GPUI | Why not |
|---|---|---|
| N1 | its own GPU render pipeline (Blade / Metal / D3D backends + primitive shaders) | we already have two (Skia and Stage3D), and Stage3D is an AIR-alignment surface (`Context3D.profile`, `#3683`/`#3684` and more are all in the tables). A third pipeline only adds a new category of "the two renderers disagree". **(This `gpui-src` checkout contains only `crates/{gpui,gpui_macros,refineable,util}`; the platform render backends are not in it. The backend facts are `gpui-src/crates/gpui/README.md:31` (macOS→Metal) and `:43` (Windows→Win32/DirectWrite).)** |
| N2 | `text_system.rs` (its own shaping/font atlas/subpixel anti-aliasing; `text_system.rs` is 1505 lines plus the `text_system/` submodule) | our SkParagraph route is calibrated **value-by-value against `adl`** (`skia.md` §8; `rust-text-backend.md` §9 already ran the numbers on swapping engines: the only case that balances is "mobile target + hard size constraint"). A UI library must never introduce a second text convention |
| N3 | hot reload / inspector / profiler (`hot_reload.rs` 248 lines / `inspector.rs` 271 lines / `profiler.rs` 2225 lines ≈ 80 KB, plus `profiler/journal.rs` 3540 lines and `profiler/hang.rs` 1865 lines) | tempting, but these are **developer tools**, a different problem from "give AS3 users a widget set"; revisit once the widget layer is stable |
| N4 | `gestures.rs` (2331 lines / ~96 KB of pinch/rotate/double-tap/long-press recognition) | its **input source does not exist here** (the window backend forwards no touch). The order has to be "wire up input first", not "write recognizers first" |

---

## 5. The single most important ruling: why "rebuild every frame" cannot be copied

This is the one trade-off in this evaluation that would **change the architecture**, so it deserves
its own argument.

**GPUI can rebuild every frame because it runs on Rust: the tree is a batch of cheap structs that is
returned wholesale when the scope exits.** We cannot, for hard reasons written into AGENTS.md:

1. **The GC red line**: `gc_step()` advances only a fixed budget of mark/sweep slices per frame
   (GC-4 incremental), whose design goal is "a single-frame pause of O(budget), not O(heap)"; and it
   explicitly forbids **"producing temporary allocations that enter the arena on a per-frame or
   per-loop hot path"** (the precedent is `as_disp_key` leaking ~39 KB/s silently, stage 56).
   A 200-node interface rebuilt at 60 fps is 12,000 node objects plus strings and arrays per second,
   every round of which has to enter the GC heap to be marked and swept — while our arena is
   **bump-only, never returned** (`as_alloc`), and the genuinely reclaimable path (`gc_alloc`) has to
   be paid for out of the incremental marking budget.
2. **More to the point: rebuilding buys nothing.** Our display tree **is already retained**; a
   `DisplayObject` pointer *is* a stable node identity, and changing a property changes one field.
   Under that premise, "rebuild then drop" is **more expensive** than "diff the old and new
   descriptions" — what we would be throwing away is identity we get for free.
3. **GPUI's immediate half solves Rust's problem** (state scattered in many places, needing
   deduplication, needing update code written by hand), and that item is not on our list at all:
   AS3 users hand-writing `addChild` do not suffer from "it is not declarative", they suffer from
   "there is no layout, there are no widgets, and shortcuts cannot be configured".

**Conclusion**: borrow the immediate **way of writing** (`render()` describing a tree), not its
**way of executing** (rebuilding each frame). Land it as a **keyed reconciler**:

```as3
// The description is declarative, the nodes are retained: the same key reuses the old node
// (along with its hover/scroll state)
override public function render():Node {
  return box({ direction: "column", gap: 8, padding: 12 }, [
    text(this.title, { style: Style.body }),
    button("OK", { key: "ok", onClick: this.onOk }),
    list({ items: this.rows, itemKey: function (r:*):String { return r.id; } }),
  ]);
}
```

`key` plus `index` together form the node identity (the AS3 version of `GlobalElementId`): the same
identity **reuses the same node object** between this frame and the last, and only the parts of the
description that **actually changed** are written back (change a style → mark dirty → re-lay-out and
repaint only that subtree). That keeps the benefit of being declarative (B1) without paying the
cost of a full per-frame allocation (avoiding the §5 red line).

---

## 6. The shape we should aim at: `asaot.ui` and three seams

**The namespace is a hard constraint**: every new API goes into its **own namespace** (`asaot.ui.*`;
do not touch `flash.*`). AGENTS.md §1.5 requires that "an enhancement must never rewrite any
AIR-defined behaviour", and `flash.*` is the surface calibrated value-by-value against `adl`;
putting widgets into `flash.ui`/`flash.display` would destroy the decidability of "isomorphic with
AIR".

Three seams (all following the "opaque seam" precedent in `rust-text-backend.md`) — but the
**`LayoutEngine` seam is drawn at the AS3 interface layer**, not at the C-function layer (why is
explained right after the table):

```
        asaot.ui (plain AS3 sources, compiled by our own compiler — dogfooding)
                │
   ┌────────────┼──────────────────────────────┐
   │            │                              │
NodeTree    LayoutEngine (AS3 interface)      Renderer seam
(retained    ├── As3LayoutEngine (pure AS3 flexbox subset, mxmlc→adl runnable)
  + keyed     └── NativeLayoutEngine (built-in → 30 as_ui_yg_* opaque C functions → Yoga)
    reconcile)   both behind one interface; injection point in UiApp
                                    │
                                    └─ opaque C seam (30 as_ui_yg_*; visible only to the native built-in)
```

The in-repo precedents for these seams, and why each must be a seam (the first two are seams; the
third is the switch mechanism that makes a seam cost nothing):

| Seam | Precedent | Why it must be a seam |
|---|---|---|
| `LayoutEngine` | `docs/en/rust-text-backend.md` §1.1 (the 15-function opaque seam for the text glue) | the seam is drawn at the **AS3 interface layer** (`asaot.ui.LayoutEngine`, pure `.as`): the widget layer depends only on the interface, so **the whole library (layout included) compiles under mxmlc and runs on `adl`**, giving us the most valuable lever — ".as source, mxmlc→adl vs AOT→native, value by value". Two implementations: `As3LayoutEngine` (pure AS3 flexbox subset, the adl side) and `NativeLayoutEngine` (a built-in forwarding to the inner **30** `as_ui_yg_*` C functions → Yoga). flexbox's semantic complexity (intrinsic sizing, wrapping, percent vs auto, min/max, baseline) does not justify writing our own; but the interface must be independent of the engine so it can be replaced wholesale later. **The seam is lighter than expected** (proved by the U1 prerequisite measurement): Yoga is **19 `.cpp` files plus one `-I <repo>`**, with **no CMake generation step** (`CMakeLists` only produces `yogaConfig.cmake`, unrelated to the headers) |
| `Renderer` | the text-backend split + the multiple `stage3d_*` backends | lets one body of widget code run on Skia (correctness, wasm with no GPU fallback) *and* on Stage3D (performance); without it we are locked onto one path forever |
| build-manifest switch | conditional linking of `swc-paths` / `sqlite` (linked only if referenced) + `--features` | a build that uses no UI must pay **zero**: this project's consistent attitude to size (`size-optimization.md`, and the 19.43 MB → 6.05 MB of `rust-text-backend.md` §3/§10) |

**Why the seam is drawn at the AS3 interface layer (not the C-function layer)**: AS3 has **no FFI
at present** (`enhancements.md` E11, un-scheduled), so a plain AS3 source cannot call a C function ⇒
the native implementation can only be "**a built-in class implementing a pure-AS3 interface**". And
once the interface is pure `.as`, the widget layer depends only on the interface ⇒ **the whole
library (layout included) compiles under `mxmlc` and runs on `adl`**, yielding the most valuable
acceptance lever: "the same `.as` source, `mxmlc`→`adl` versus our AOT→native, compared value by
value". The inner C seam (`as_ui_yg_*`) still exists, but is demoted from "the seam AS3 can see" to
an implementation detail of `NativeLayoutEngine`. The contract skeleton is in `asaotui/seam/`.

**Trade-offs (stated honestly)**:
- **AIR has no flexbox concept at all** ⇒ layout's acceptance reference is **not `adl`** but the
  **W3C flexbox spec / a browser** (Yoga is implemented to the web standard). This does not violate
  AGENTS.md §1.5: layout is an **enhancement** (AIR has no counterpart), and an enhancement has no
  AIR reference by definition. `adl` is used only to exercise the AS3 orchestration and the AS3
  semantics of the `As3LayoutEngine` subset.
- **Cost**: we must maintain **a pure AS3 flexbox** (a subset), and two implementations carry a
  **drift risk** ⇒ **differential testing** is mandatory: for one input, both engines' rectangles
  must be **equal item by item** (tolerance `EPS=0.01`), or the test is red.
- **Prerequisite**: the whole native path assumes the new mode "**a built-in class implementing a
  user `.as` interface**" holds (mechanically it should, but there is **no precedent yet**; it is
  being probed now). If it fails, the fallback is "built-in static methods + an AS3 adapter compiled
  only in AOT builds", and the last resort is the C-function seam with direct built-in classes (see
  `u1-implementation-plan.md` §4).

---

## 7. Staged proposal (numbers pending, continuing after the current end of the roadmap)

> Numbers are taken from the last section of `TODO.md` (the last stage section in this repository's
> `TODO.md` is **stage 231**, `v0.4.202 → v0.4.203`; stage 232 and above have **zero** matches in
> `TODO.md`). **But `git log` already contains commits for stages 232–237** (at the time of writing
> HEAD was `f688094`, and it was still moving), i.e. `TODO.md` lags the
> commit series; U1's number and version must be re-checked once that in-flight series lands (see
> [`u1-implementation-plan.md`](u1-implementation-plan.md) §1). Acceptance for every stage follows AGENTS.md §2.7: **one `examples/*.as`
> sample plus assertion-based regression**; unit groups go in `test/unit/` (negative cases and
> structural invariants can only be pinned there), end-to-end goes in `test/examples.ts`.

| Stage | Content | Key decision | Acceptance artefact |
|---|---|---|---|
| **U1 layout base** | `asaot.ui.LayoutEngine` (**a pure AS3 interface**) + the **already implemented** pure AS3 `As3LayoutEngine` (flexbox subset); **equal value-by-value across three toolchains**: our AOT / Yoga (C, the differential counterpart) / AIR. *The native built-in → Yoga route is a **shelved** option kept for the record (see [`compiler-gaps.md`](compiler-gaps.md))* | **pure AS3 implemented and accepted**; the native prerequisite measurement is **Go (conditional)** (native delta ≈ **92 KiB**, wasm ≈ **120 KiB**, commit pin `843dba8`) but requires compiler changes ⇒ shelved | [`layout-check/`](layout-check/) (our AOT, 16/16) + [`diff-check/`](diff-check/) (the same frozen spec fed to Yoga and to the AS3 engine) + [`air-check/`](air-check/) (`mxmlc`→`adl`, 16/16); the reference is W3C flexbox / a browser (AIR has no flexbox) |
| **U2 element identity + state hoisting** | keyed reconciler, an `ElementState` table, the `measure/arrange/paint` three passes | reuse rather than rebuild; **pointer-level reuse** for unchanged subtrees | `unit: ui/reconcile`, pinned on the **emitted C**: two frames with the same description allocate no new node; changing one property re-lays-out only that subtree |
| **U3 data flow and redraw scheduling** | `Observable` + `notify()`, wired to the existing `WinCtx.dirty` | must not bypass the window backend's dirty semantics (it is the *only* entry point for "repaint dirty windows only") | `examples/ui-notify.as`: changing one field triggers exactly one redraw; a frame with no change redraws **nothing** |
| **U4 base widgets** | `Box`/`Text`/`Button`/`Image`/`ScrollView`/`List` (virtualized)/`Checkbox`/`Radio`/a `TextField` wrapper | every widget must **declare role/name/value** (leaving the shape for future a11y); the `TextField` wrapper must sit *outside* the existing SkParagraph channel and **must not** open a second text convention | one sample per widget; the virtualized list pins "only visible items are instantiated" |
| **U5 keyboard-first and focus shape** | `ActionRegistry` + key context + keymap JSON; `FocusChain` (grouping, in-modal cycling); re-evaluate `as_tab_scan`'s **64-focusable cap** | **do not rebuild the focus model**: reuse the existing `as_focus_obj`/`as_focus_tab` and its `adl` conventions, change only "where the order comes from and who is on the chain"; before raising the cap, first measure what `adl` does with >64 tabbables (never guess) | `examples/ui-keymap.as`: the same action bound to different keys in two contexts; Tab cycles inside a modal without escaping; Tab still reaches everything with >64 tabbables |
| **U6 backfilling the AIR baseline: `flash.accessibility.*`** | `Accessibility` / `AccessibilityProperties` / `AccessibilityImplementation` / `ISearchableText` / `ISimpleTextSelection` | this is **AIR-has-it, we-do-not** ⇒ a **legacy debt** (not an enhancement); already logged as **G2** in [`compiler-gaps.md`](compiler-gaps.md) (per the user's 2026-10-22 instruction the compiler is not edited directly); only if it gets scheduled does it go into the `遗留待开发` table; align the API and semantics first, and make the **platform bridge (Windows UIA / macOS NSAccessibility) a separate project** | an API shape checked value-by-value against `adl` + a unit group; while the bridge is unimplemented, **report loudly**, never pretend silently |
| **U7 (optional) real-app acceptance** | rebuild a real screen with `asaot.ui` (e.g. the talkmed-meeting login page) | dogfooding is the only real acceptance for this library: it exercises the AS3 subset, text, events and GC at once | a two-sided comparison record against `adl` |

**U1's prerequisite measurement: done (2026-10-22), conclusion Go (conditional)** — full text in
[`measurements/u1-yoga-precheck.md`](measurements/u1-yoga-precheck.md).

- **Size**: Yoga pin = commit `843dba8619420992e492bbb4b3d2f63d9ad6c683` (`main`, newer than the latest tag `v3.2.1`). Under the best configuration (`-Oz -DNDEBUG -ffunction-sections -fdata-sections -fno-exceptions`), the **post-link delta** is native **≈ 92.0 KiB (94,208 B)** and wasm (emcc 3.1.44) **≈ 120.3 KiB (123,180 B)** — a **rounding error** against this project's MB-scale GUI builds (text draw 6.05 MB).
- **It is not a risk**: §8 used to list "size" as the first risk; the measurement **refutes that assumption** (precheck §7, first row).
- **wasm compilability**: emscripten (the `--package web` backend) **compiles and links with zero errors**; strict `clang --target=wasm32-wasip1` is **not measurable on this machine (no sysroot)**.
- **DCE compatibility**: the COFF counterpart is `-ffunction-sections -fdata-sections` + `/OPT:REF` (`-Wl,--gc-sections` is silently ignored by `lld-link`), and the unreferenced Yoga **was measured to be strippable**; macOS `-Wl,-dead_strip` is **not measurable on this machine**.
- **Two CI blockers (not measurable locally, pending CI; either red ⇒ fall back to the AS3 subset, boundary in precheck §6.4)**: ① on a CI with `WASI_SDK_HOME`, `clang --target=wasm32-wasip1` compiles and links Yoga, and the wasm delta ≤ 192 KiB; ② on macOS arm64, under `-Wl,-dead_strip`, `yoga_one` is clearly smaller than `yoga_min`.
- **Two corrected old claims**: the seam needs **no CMake / no generation step at all** (19 `.cpp` + one `-I`); `-DYG_NDEBUG` is an **empty switch** (zero references in the source), so turning asserts off relies on `-DNDEBUG` alone.
- **One new risk (absent from the old edition)**: under `__EMSCRIPTEN__`, `YG_EXPORT` carries `__attribute__((used))` ⇒ on the `--package web` path Yoga's public C API is force-kept/force-exported, so wasm DCE is weaker than native (see the §8 risk table).

---

## 8. Cost, risk and guardrails

| Risk | Concrete shape | Guardrail |
|---|---|---|
| **size** (**measured: a rounding error, < 3%**) | ~~Yoga plus the widget layer entering the binary is a risk~~ ⇒ **the measurement refutes it**: a full flexbox+grid engine costs a native **92 KiB** / wasm **120 KiB** delta (commit pin `843dba8`, see [`measurements/u1-yoga-precheck.md`](measurements/u1-yoga-precheck.md) §3.2/§3.3), < 3% of an MB-scale GUI build. **But this hard gate must stay:** | **a build that uses no UI must pay zero** — manifest switch + link-only-if-referenced (same `usesFlashData`/`usesTextEngine` pattern as sqlite / the text glue), with `-O2`/`-dead_strip` stripping unreferenced Yoga from `main` (strippable on COFF as measured; macOS pending CI); if over budget, fall back to an AS3 subset |
| **`used` weakens web-side DCE under `__EMSCRIPTEN__`** (**new risk, absent from the old edition**) | On the emcc path (`--package web`) `__EMSCRIPTEN__` is defined, where `yoga/YGMacros.h`'s `YG_EXPORT` = `__attribute__((visibility("default"), used))` ⇒ Yoga's public C API is **force-kept and lands in the export table** (measured: `wasm_yoga_min.wasm`'s export table is full of `YGNodeStyleSet*`), so DCE is weaker than native; `-sEXPORTED_FUNCTIONS` **cannot** prevent it (limiting exports to `_start` made the artifact **larger**, with the YG symbols still present). native / `--target wasm32-wasip1` (clang, no `__EMSCRIPTEN__`) **do not have this problem**. | Already **counted** in the §7 wasm delta (120 KiB); at U1 implementation pick one: accept that size, or **suppress `used`** when compiling Yoga in the glue layer (a local `YG_EXPORT` override / `-fvisibility` combination) — an implementation detail, see [`u1-implementation-plan.md`](u1-implementation-plan.md) §3. |
| **two CI blockers unverified** (**new risk, absent from the old edition**) | The strict wasip1 compile+link (this machine has no WASI sysroot, and `src/build.ts:1322` currently **throws outright for C++ sources under `--target wasm`**) and macOS `-Wl,-dead_strip` (this machine has no ld64) are both **unmeasurable locally**, so they can only wait on CI (arm64 macOS). **No CI result is invented.** | Make them **CI pre-checks before landing**: either red ⇒ fall back to the AS3-side flexbox subset (boundary in precheck §6.4); use the fallback path in `u1-implementation-plan.md` §4 (the seam API and the sample survive; only the engine implementation is swapped) |
| **two UI stacks to maintain** | `flash.display` (AIR-aligned, must not move a single value) and `asaot.ui` (new) coexist indefinitely | namespace isolation; the widget layer **only calls** display's public behaviour and never adds to or rewrites `flash.*` semantics |
| **layout semantic correctness** | flexbox edges (percent + auto, min-content, wrap + gap, baseline) are easy to get "looking right"; and **AIR has no flexbox concept**, so layout **has no `adl` reference** | use an engine rather than writing our own (native goes through Yoga, R2); AS3 sees only the interface; **the reference is the W3C flexbox / a browser** (not `adl`); both implementations must agree under differential testing |
| **drift between the two layout implementations** (**new risk**) | a pure AS3 subset and Yoga are **two** implementations, and their edges (percent, gap, auto, min/max) will diverge ⇒ the same input yields different rectangles | **differential testing is a hard requirement**: the native build links both, runs the same input through each and compares item by item (`EPS=0.01`); red ⇒ fix; see `seam/README.md` §3.2 |
| **a built-in class implementing a user `.as` interface** | the native path's prerequisite: `NativeLayoutEngine` must `implements:['asaot_ui_LayoutEngine']`, referencing the user interface `asaot.ui.LayoutEngine` — the interface vtable and the conformance check both walk the whole table including built-ins, but there was **no precedent** | **verified 2026-10-22**: a positive run reached `x=120` and `s is ISizable=true`, and the negative control (an unimplemented member) failed with `does not implement method 'bogus' of interface 'probe_ISizable'` — see [`reviews/probe-builtin-implements-user-iface-2026-10-22.md`](reviews/probe-builtin-implements-user-iface-2026-10-22.md). The architecture therefore **needs no fallback**; `u1-implementation-plan.md` §4 is kept for reference only; **never silently** |
| **GC and frame budget** | any "allocation per frame" eats the incremental GC budget | U2's reuse is a **hard requirement, not an optimization**; `unit: ui/reconcile` pins "the same description allocates no new nodes" as an invariant |
| **accessibility is deep water** | AccessKit is one dependency line on the Rust side; on our side it is two models (Windows UIA and macOS NSAccessibility), and **AIR itself is weak here** | do the **AIR baseline (U6)** first (API shape and semantics); the platform bridge is a separate project and reports loudly while unimplemented |
| **do not become "Feathers again"** | widgets are a bottomless pit (Feathers/Starling is measured in years) | build **only the widgets a real screen uses**; U7's real app decides the list — no "general-purpose widget set" |
| **touch input is missing** | scrolling/dragging in the widget layer is unthinkable on touch devices | explicitly list "the window backend forwards touch events" as an **input prerequisite** for U4/U5, rather than starting with gesture recognition |

---

## 9. Explicitly out of scope (to stop scope creep)

- No new GPU render pipeline (N1); no text-engine swap (N2).
- No hot reload / inspector / profiler (N3); no gesture recognition (N4 — the input source does not
  even exist).
- The widget layer does not go into `flash.*`; no AIR-defined behaviour is changed "for convenience".
- No "general-purpose widget set" — only the widgets a real screen uses.
- This evaluation adds one "UI toolchain pending items" section at the end of `TODO.md`
  (from `TODO.md:14086`, immediately after `### 增强待做`): **no stage number, no version bump**; a stage number and a version bump are only consumed once
  implementation starts. (Note: that section itself copies the pre-correction `src/emit.ts:10850` line
  number and the old `grep accessibility` wording; **`as3compiler/TODO.md` is out of scope for this
  correction**, so this document's §3 measurements are authoritative.)

---

## 10. References

- GPUI home <https://gpui.rs/>; the local checkout `asaotui/gpui-src/` (`zed-industries/zed`, `main`@`54478042`, nightly):
  `crates/gpui/README.md:3` (self-described `hybrid immediate and retained`), `src/element.rs`
  (the `Element` four passes `:52-105`, the drop-the-tree semantics `:10-14`, the `Drawable`/`ElementDrawPhase` machine `:315-348`),
  `src/taffy.rs` (the layout seam `:31`/`:62`/`:187`/`:345`/`:439`), `src/style.rs` (the `Style` value table `:180-322` and refine),
  `src/scene.rs` (the primitive table `:222-230` and the batches `:478-495`), `src/bounds_tree.rs` (the spatial index),
  `src/tab_stop.rs` (tab order `:11-23`), `src/_accessibility.rs` (AccessKit `:15`),
  `src/_ownership_and_data_flow.rs` and `docs/contexts.md` (entity/notify; `src/app/context.rs:221` for `notify`),
  `docs/key_dispatch.md` (actions + keymap), `src/key_dispatch.rs` 2216 lines / `src/keymap.rs` 1135 lines.
  (Note: the local checkout contains only `crates/{gpui,gpui_macros,refineable,util}`; the platform render backends are not in it.)
- Related documents in this repository: [`skia.md`](as3compiler/docs/en/skia.md) (renderer backend and the 1:1 pixel
  convention), [`rust-text-backend.md`](as3compiler/docs/en/rust-text-backend.md) (the precedent for opaque seams and
  the two size cuts), [`flash-text.md`](as3compiler/docs/en/flash-text.md) (text measurement and `autoSize`),
  [`gc.md`](as3compiler/docs/en/gc.md) (incremental marking, write barriers, the per-frame safe point),
  [`size-optimization.md`](as3compiler/docs/en/size-optimization.md) (the size levers),
  [`enhancements.md`](as3compiler/docs/en/enhancements.md) (how enhancements are judged and the named switches).
- AIR reference (the API shape of `flash.accessibility`):
  <https://airsdk.dev/reference/actionscript/3.0/flash/accessibility/package-detail.html>
- Yoga (a flexbox implementation with a C API, the U1 candidate): <https://github.com/facebook/yoga>