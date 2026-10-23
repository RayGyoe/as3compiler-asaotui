# `probes/obj-array-identity/` — does an `Array` in an `Object`-typed slot keep its identity?

**Yes in AIR. No in our AOT — and four of the wrong answers are `0xC0000005`.**

One command, both runtimes:

```
node probes/obj-array-identity/run.cjs        # 26 cases, AOT + AIR, ~60 s
node probes/obj-array-identity/mutation.cjs   # 4/4, every file restored by hash
```

Registered as **G14** in [`compiler-gaps.md`](../../compiler-gaps.md); the write-up with the
mechanism read out of the generated C is
[`reviews/probe-g14-object-slot-array-identity-2026-10-23.md`](../../reviews/probe-g14-object-slot-array-identity-2026-10-23.md).

## Why this probe exists

The style layer deliberately splits every entry point into a scalar form and an array form
(`Size.fromAny(o:Object)` / `Size.fromArray(a:Array)`, and the same for `Edges`, `Corners`,
`LengthEdges`, `Fill`). That split looked like a *stale workaround* — the kind of thing that
should be collapsed now that the compiler has moved on. Before touching it, we asked the
compiler what it actually does. It does this:

```c
// var o:Object = [1,2,3];
o = (Object*)(as_array_make(...));          // a BARE array pointer into an Object slot
if (false) { ... }                          // o is Array        -> constant-folded FALSE
as_is(o, &Marker_vt)                        // o is Marker       -> reads the array header
                                            //                      as a vtable => 0xC0000005
as_v_obj_val(o)                             // o as Array        -> NULL (tag is not 4)
as_dyn_get(o, "length", 0)                  // o.length          -> undefined
as_str_from_bool(false)                     // ...but typeof o   -> "object"  (correct!)
```

So the split is **load-bearing**, not stale: `fromAny` opens with `o is Length` / `o is Fill`
against *user* classes, which is the crashing form. And `Fill.fromAny` contains
`if (o is Array) return null;` — which the compiler emits as `if (false)`. A guard that
cannot fire is worse than no guard, because it reads like protection.

## Layout

| file | role |
|---|---|
| `Cases.as` | **single source of truth** for the 26 cases (what gets stored, what is asked) |
| `CaseAot.as` | AOT driver; picks ONE case by `select.txt`, appends one line to `out.txt`, exits |
| `CaseAir.as` | AIR document class; runs all 22 in one process, writes `objarr-air.txt` |
| `Marker.as` | a trivial user class — the target of the dangerous `is` |
| `app.xml` | AIR descriptor (unused knobs still present, kept minimal) |
| `expect.json` | the **hand-written AS3 rule** (`truth`) + the documented AOT deviations |
| `run.cjs` | builds both arms, runs every case, compares, reports |

**One process per case on the AOT arm is not a stylistic choice.** Cases 3/12/19/21 kill the
process, so a single-process driver would lose the remaining answers. The runner records
`exit 0xC0000005` as the value `(crashed)` and keeps going — a crash is data here, not a
harness failure.

## The two arms are checked differently

- **AIR is the reference, and that is itself measured.** `expect.json`'s `truth` block is the
  rule written out by hand from AS3 semantics; the AIR arm must match it on all 26 cases.
  If AIR ever disagrees, the probe says so *before* it compares anything to our AOT — a
  reference that was never validated is just a second opinion.
- **Our AOT is compared to AIR**, and the differences must be **exactly** the documented set
  (ids `1, 3, 12, 15, 16, 19, 21`). A new deviation is red; a deviation that quietly
  disappears is **also** red, and the message says it may be a real fix (`GAP-CHANGED`) so the
  next person updates the registry instead of "reproducing" it.

## What the 26 cases separate

The matrix deliberately crosses three things that look alike but behave differently:

- **the declared type** of the slot (`Object` / `*` / `Array` / `Number` / a real class)
- **the value** stored (array, number, string, boolean, class instance, `null`)
- **the question** asked (`is Array`, `is Marker`, `as Array`, `length`, `typeof`, arithmetic)

What falls out (see the table in `compiler-gaps.md` G14 for the full reading):

- **`Number`/`String`/`Boolean` in an `Object` slot: everything correct.** They get boxed
  (`as_number_new` / `as_string_new` / `as_boolean_new`), so identity survives.
- **`Array` in an `Object` slot: identity destroyed** — no boxing happened. The `*` slot
  survives `is Array` but still dies on `is <userClass>`.
- **`Array` declared `Array`: all correct.** So the gap is about *the slot*, and it is
  specific to `Array` — not a general "Object slots lose identity".

That distinction is the whole point: it says the fix belongs at the boxing decision, not in
every `is` in the library.

## Teeth

`mutation.cjs` runs four mutations against the checker's own inputs and requires the specific
red for each — flip one AS3 rule (the AIR/reference check must fire), drop a documented
deviation, invent one, truncate the case list so ids 16/19/21 never run. All four go red, and
`expect.json` is restored **byte-identically** (verified by hash, printed in the output).