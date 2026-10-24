# probes/g16-ternary-null — `cond ? null : X` loses the value

Registered as **G16** in [`../../compiler-gaps.md`](../../compiler-gaps.md); **FIXED in the
compiler at stage 266 (v0.4.230)**. This directory is the measurement that found it, and now the
tripwire on the fix: the gate demands that the AOT deviation set be EXACTLY the registered set --
which is empty -- so any case that starts collapsing again turns the gate red.

```bash
cd asaotui
node probes/g16-ternary-null/run.cjs        # one command, both runtimes
node probes/g16-ternary-null/mutation.cjs   # 4/4 -- proves run.cjs can go red
```

`run.cjs` exits **0** when our AOT agrees with AIR on every case, **1** when they disagree (and
prints the table), **2** when a build/parse failed. Two arms, one command: the AOT arm is our
compiler, the AIR arm is `mxmlc` → `adl` 51.4.1 from `$AIRSDK_HOME`. `expect.json` holds the
**hand-derived** AS3 rule and must agree with AIR independently of our AOT — that is what makes
the reference a measurement instead of an assumption.

## What it measures

AS3 says `cond ? a : b` is `a` when `cond` is true and `b` otherwise. A null literal in the THEN
slot is just a value. Our compiler instead collapses the whole conditional to a constant of the
result type whenever the condition is false:

| result type | AIR | ours |
|---|---|---|
| reference (`Bitmap`/`Object`/property/array element/`{}` slot/`bitmapData`/call) | the object | **`null`** |
| `Number` | `42` | **`0`** |
| `Boolean` | `true` | **`false`** |
| `int` | `7` | **`0`** |
| `String` | `hi` | `hi` (immune) |

Before the fix, 12 of the 17 cases deviated. 11/12/13 are controls (they pass), and 2 showed the
failure was tied to *which* branch holds the null literal, not to ternaries meeting null at all.
The table above is the REGISTERED (pre-fix) behaviour; all four result rows now agree.

## Root cause (pinned 2026-10-23; fixed at stage 266)

1. `src/emit.ts:28915-28937` `unifyType` — with `a` (the **THEN** branch) typed `null` and `b`
   typed `object`/`int`/`bool`, every rule misses (the numeric set at `:28932` does not contain
   `'null'`) and the fallback `:28936 return a;` types the **entire conditional** as `null`.
2. `src/emit.ts` `convert` (`:33985-33997`, `:34057`) — an expression whose static type is `null`
   is emitted as the *constant* `NULL`/`0.0`/`0`/`false`, so the branch that really runs at runtime
   is discarded.

The two lines predict all 12 deviations **and** the 5 passes (including "String is immune", which
is `unifyType:28920`'s explicit string rule firing before the fallback). Suggested direction:
give `unifyType` a null-vs-reference/numeric/bool family rule, mirroring the string rule; fixing
only `convert` would preserve the value but leave the conditional's static type wrong.

## The kit workaround, and its removal (2026-10-24)

While the gap was live, `kit/asaot/ui/kind/ImageWidget.as` spelled `o == null ? null : Bitmap(o)`
as an if/return (case 13 here: both arms agree), and `table.as` / `breadcrumb.as` /
`pagination.as` spelled the same shape as if/else. All four are back to the ternary now that the
type rule is fixed; the three `if (opts.x != null)` OPTION guards in `combo` / `datePicker` /
`virtualList` stayed, because they are idiomatic guards and not this shape. See
[`reviews/revisit-g16-g22-workarounds-2026-10-24.md`](../../reviews/revisit-g16-g22-workarounds-2026-10-24.md).
