# `probes/vec-vs-arr/` — `Vector.<T>` vs `Array`, measured on **both** runtimes

```
node probes/vec-vs-arr/run.cjs        # build both arms, measure, assert the claim
node probes/vec-vs-arr/mutation.cjs   # 2/2, files restored byte-for-byte
```

`N = 1,000,000`, best of 5, `getTimer()` ms. Two independent runs agree to ±1–3 ms.

| benchmark | our AOT | AIR 51.4.1 (`adl`) |
|---|---|---|
| `Array` fill+sum (`push` + index read) | 11 | 36 |
| `Vector.<int>` fill+sum | **2** | 33 |
| `Vector.<Number>` fill+sum | **2** | 41 |
| `Array` prealloc (`a.length=N` + index write) | 5 | 20 |
| `Vector.<int>` prealloc (`new Vector.<int>(N)` + index write) | **1** | **3** |

**Ratio: our AOT `Vector.<int>`/`Array` = 0.18x, `Vector.<Number>`/`Array` = 0.18x. AIR = 0.92x / 1.14x.**

## Same body, two toolchains

`BenchCore.as` holds every loop, the same `N`, and the same timing primitive; only the
`run()` entry file differs (`BenchAot.as` vs `BenchAir.as`). So a difference between the two
columns is a **runtime** difference, not a harness difference. If both arms ran our code the
comparison would be worthless.

## The mechanism is in the generated C, not inferred

The probe writes its generated C next to itself (`bench-aot.exe.c`; generated C is **not**
committed — see the caveat below, rebuild before reading it). It shows the lowering:

```c
typedef struct { void (*mark)(void*); int* data; int length; int capacity; bool fixed; } as_vector_int;

// Vector.<int>: monomorphized, raw int elements
v = as_vector_int_new();
while (i < N) { as_vector_int_push(v, i); i++; }          // no boxing
s = s + ((double)as_vector_int_get(v, k));                // returns int, no tag dispatch
v = as_vector_int_new_sized(N, false);                    // new Vector.<int>(N)

// Array: one boxed as_value per cell
a = as_array_new();
while (i < N) { as_array_push(a, as_v_num((double)i)); i++; }   // as_value per cell
s = s + as_v_to_number(as_array_get(a, k));                     // unbox per cell
```

So the 5–6x is **not** "Vector is magic" — it is **"no boxing"**. `as_vector_int` is contiguous
`int*`; `as_array` is contiguous **16-byte tagged** `as_value` plus a tag build/tear per access.

> Caveat found the hard way: `bench-aot.exe.c` on disk after a mutation run is the *mutated*
> artifact, and reading it made `Vector.<int>` look like `as_array` (which would have
> *falsified* the mechanism). The numbers were fine; the file was stale. Rebuild before you
> read a generated artifact — this is why the gate rebuilds rather than reusing outputs.

## Why AIR shows almost no difference — and the one row that matters

AVM2's JIT already specialises `Array`, so both types land in the same ballpark (33–41 ms).
But the **prealloc row** is the interesting one: AIR's `Vector.<int>` is **3 ms** with
`new Vector.<int>(N)` + index writes (vs its own `Array` at 20 ms, **6.7x**), while
`new Vector.<int>()` + `push` costs 33 ms. In other words **AIR's Vector win comes entirely
from avoiding the growth path**, whereas ours is fast both ways (growth is already amortized).

That contrast is the finding, which is why the AIR arm is reported and **not asserted**.

## The claim the gate actually defends

The AOT arm must keep `Vector.<int>` at **≤ 0.5x** `Array` on fill+sum (at least 2x faster).
The margin is deliberately loose (measured 0.18x): the gate is not a benchmark, it is a
**regression nail on the lowering**. If `Vector.<T>` is ever silently lowered to `as_array`,
gains an extra copy, or gets a function call per element read, the ratio climbs towards 1 and
the gate fires with the number in the message.

`mutation.cjs` proves it can fire:

- **M1** — lower the claim to an impossible `0.001x`; the claim branch must go red (proves the
  ratio is asserted, not merely printed).
- **M2** (the strong one) — make the `Vector.<int>` row **actually run on an `Array`** by
  changing one line of `BenchCore.as` (`new Vector.<int>()` → `[]`). The measured ratio
  collapses and the gate fires. If the number were a constant, this mutation would not move it.

## Practical rules for the library

The actionable version of this lives in
[`CONTRIBUTING-widget.md` §4c](../../CONTRIBUTING-widget.md) (choice of collection, interplay
with the per-frame zero-allocation rule in §5). Short form: prefer `Vector.<T>` for persistent
typed containers, preallocate when the length is known, keep `Array` for heterogeneous /
dynamic / sparse data, and **do not rewrite existing small `Array` uses** — the 5–6x is a
million-element effect, invisible at the tens-of-items scale the layout and style layers work
at.