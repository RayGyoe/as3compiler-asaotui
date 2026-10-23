# probes/g12-ab — the A/B that closed G12

G12 was filed as "a ~134 KB byte-buffer allocation makes the next heap allocation
hang". It never was a runtime defect: the witness declared three script-scope
containers **below** `stage.showWindow(...)`, whose initializers therefore never ran,
so `aFresh` was `null` and `aFresh.push(1)` threw `TypeError #1009`. The timer
callback died before re-arming itself, the frame loop kept running, and the log
stopped -- which reads exactly like a hang when stderr is discarded.

Full write-up: `../../reviews/probe-g12-2026-10-23.md`.

## The three variants

Each file is a complete `Main.as` for `probes/array-scope` with exactly one change
from the version that was buggy when G12 was filed.

| file | change | measured result |
|---|---|---|
| `nobuf.as` | the `bigBuf.length = 134400` line removed (no big allocation anywhere) | log still stops at `churn 8 enter`, stderr `Uncaught exception: Error #1009`, **zero** `GCT_BYTES >= 128 KB` allocations observed ⇒ the big buffer is irrelevant |
| `fixed.as` | the three containers (`aBuf`, `aFresh`, `bigBuf`) moved **above** `showWindow`, buffer unchanged | `step 10 -> DONE`, done file `PASS` ⇒ the buffer never was the problem |
| `trycatch.as` | original order kept, `aFresh.push(1)` wrapped in `try/catch` that logs the error | logs `PUSH THREW: 1009 ...`, then `TICK THREW: 1009 ...` ⇒ the failing object is `aFresh` itself |

`nobuf.as` is the decisive one: it removes the alleged cause and the symptom is
identical. `fixed.as` and `trycatch.as` then name the real cause.

## How to run one

Copy the variant over the witness and run the tool from `asaotui/`:

```bash
cp probes/g12-ab/nobuf.as probes/array-scope/Main.as
PATH="/c/Users/rayle/Desktop/as3compiler-aot/temp/ccbin:$PATH" node tools/repro-array-scope.cjs
```

`tools/repro-array-scope.cjs` now forwards stderr and reports
`REPRODUCED (uncaught)` instead of a bare "the process hung", so this class of
misreading cannot recur silently. The header of `probes/array-scope/Main.as` also
records the setup-order rule.