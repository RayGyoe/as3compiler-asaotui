# `probes/style-fromany/` — is the style layer's `fromAny` TOTAL on both runtimes?

**Question.** The style layer used to split every entry point in two:

```as3
Size.fromAny(o:Object)      // scalars
Size.fromArray(a:Array)     // arrays
```

…and `StyleRefinement.from` branched at every call site
(`o.size is Array ? Size.fromArray(o.size as Array) : Size.fromAny(o.size)`).

That split was not stylistic. An `Array` put into an **`Object`-typed parameter** used to lose its
identity in our AOT — `is Array` was constant-folded to `false`, and the `is Length` / `is Fill` test
on the next line read the array header as a vtable and killed the process with `0xC0000005`
(**G14**, see [`compiler-gaps.md`](../../compiler-gaps.md)).

G14 was fixed in as3compiler **阶段二百五十三** (`54bda6d`, v0.4.217). The split was then **reverted**:
`fromAny` dispatches the array form itself. `fromArray` is kept as an *explicit* entry point, because a
gradient stop list really is an array and the typed parameter is what will make `a.length` safe the day
gradients land.

**This probe measures the revert instead of trusting it.** One command, both runtimes:

```sh
cd asaotui && node probes/style-fromany/run.cjs
```

| arm | toolchain |
|---|---|
| AOT | our compiler → native `.exe` |
| AIR | `mxmlc` → `adl` (AIR SDK 51.4.1) — the reference |

**19 cases.** Both arms are compared against answers **hand-derived from the code in
`kit/asaot/ui/style/*.as`** (`expect.json` → `truth`, with a per-case `_derivation`), so
"AIR is the reference" is itself a measured claim rather than a slogan.

What the cases cover:

| group | cases | what it pins |
|---|---|---|
| the **mechanism** | 15 | an array literal handed to an `Object`-typed parameter, then `is Array` — the exact thing G14 broke |
| `Size` | 1, 2, 3, 4, 19 | array `[w,h]` / scalar / one-element / `null` / a `Length` passthrough (`pct(0.5)` → `50%`) |
| `Edges` | 5, 6, 7 | `[h,v]` → `hv(h,v)` / `[t,r,b,l]` / scalar |
| `Corners` | 8, 9 | `[tl,tr,br,bl]` / one-element |
| `LengthEdges` | 10, 11 | `[h,v]` with `Length` per side / `"auto"` |
| `Fill` | 12, 13, 14 | an array is a gradient → `null` / scalar → opaque solid / a `Fill` passthrough |
| end-to-end | 16, 17, 18 | through `StyleRefinement.from`, where every value arrives as a **dynamic `o.<field>` read** — the real caller |

**A short line count is a crash, not a pass.** Each driver appends its line *immediately*, so the case
that dies stops the run; the runner fails on the missing tail and names the last id reached.

## Teeth

```sh
cd asaotui && node probes/style-fromany/mutation.cjs
```

| mutation | expectation |
|---|---|
| `M1` drop `Size.fromAny`'s array branch | cases 1, 3, 16 go red |
| `M2` swap the `[h,v]` pair in `Edges.fromArray` | case 5 goes red |
| `M3` hard-code the mechanism itself (`isArrayInObjectSlot` → `false`) | case 15 goes red |
| `M4` swap the `[h,v]` sides in `LengthEdges.fromArray` | case 10 goes red |

**4/4 caught**, and every file is restored in `finally` with a **sha256 byte-for-byte comparison** — a
mutation run that left the library subtly altered would be worse than no mutation at all.

`M3` is the important one: case 15 is the whole premise of the revert, so a mutation that makes it
unfalsifiable must be caught. If the mechanism were not real, every other case would still pass (the
array would simply reach `null`) and the probe would be green for the wrong reason.

## Files

| file | role |
|---|---|
| `StyleCases.as` | the single case table — both drivers call it, so both arms ask *identical* questions |
| `AotMain.as` | AOT driver (top-level script) → `style-fromany-aot.txt` |
| `AirMain.as` | AIR driver (document class) → `style-fromany-air.txt` |
| `app.xml` | `adl` descriptor (`<visible>false</visible>`) |
| `expect.json` | hand-derived `truth` + `label` + per-case `_derivation` |
| `run.cjs` | one command, both arms, one report → `style-fromany-results.txt` |
| `mutation.cjs` | proves `run.cjs` can go red → `style-fromany-mutation.txt` |

Notes measured while building this:

- `new File(".")` is an `ArgumentError #2004` under `adl` — the AIR arm anchors on
  `File.applicationDirectory.nativePath` (which under `adl app.xml` **is** this directory).
- `adl.exe` has no console on Windows, hence the result file.
- `ASC_SKIP_AIR=1` runs the AOT arm alone (useful for a quick loop; the gate never sets it).
