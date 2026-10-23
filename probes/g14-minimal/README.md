# `probes/g14-minimal/` — the handoff package for G14

Smallest program that shows the `Object`-slot Array bug, run on **both** runtimes:

```
node probes/g14-minimal/run.cjs
```

```
--- our AOT (exit 3221225477)                        --- AIR 51.4.1 (reference)
    is Array  = false     (AIR: true)                   is Array  = true     (AS3 rule: true)
    (never got here)                                    is Marker = false     (AS3 rule: false)
    (never got here)                                    REACHED THE END (no crash)
```

Exit codes: **0 = the bug is reproduced** (that is what this package is for),
**1 = not reproduced** (somebody fixed it — then update the three registries the
output names), **2 = harness failure** (build broke, or the AIR reference itself
disagreed with the AS3 rule).

| file | role |
|---|---|
| `ReproAot.as` | our arm — two `is` questions, evidence appended one line at a time so a buffered stdout cannot eat the line that proves how far it got |
| `Marker.as` | the `is` target; any user class does, it only has to have its own vtable |
| `ReproAir.as` | the same two questions on real AIR (`mxmlc` + `adl`); writes a file because Windows `adl.exe` has no console |
| `app.xml` | AIR descriptor (`visible=false`) |
| `run.cjs` | one command: build both, run both, compare, decide the exit code |

The write-up — root cause with the three `src/` sites, the two fix leads, and what
our gates will do when it is fixed — is
[`reviews/handoff-g14-to-compiler-2026-10-23.md`](../../reviews/handoff-g14-to-compiler-2026-10-23.md).
The full 26-case matrix (and its mutation proof) is in
[`../obj-array-identity/`](../obj-array-identity/); the library-level nail is
`ui-demo/CheckUi.as` section 8.

**This probe never runs inside `tools/gates.cjs`** — it is a message to another
repo, not a regression nail, and it deliberately *fails* (exit 1) when the compiler
is fixed. The gate that watches our side is `obj-array-identity`.