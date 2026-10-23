# probes/reach-freefn -- is `--air-app`'s reachability closure sound?

**Verdict: it WAS a leak, not a superset — and it is FIXED (阶段二百四十九).**

This probe is kept as a **regression pin**. It was written when the default
`--air-app` face dropped classes first discovered by a "forced file" (a file
carrying free functions / module-level statements): such a class was emitted but
never expanded, so its superclass and its referenced classes were pruned. That was
`compiler-gaps.md` **G13**, and every widget in `asaotui/kit` is reached through a
lowercase factory free function, so it hit on every demo.

| | before the fix | after the fix |
|---|---|---|
| `tools/reach-dump.cjs` closure | kept **3/5**, edges 1 | kept **5/5**, edges 3 |
| `--air-app` default face | `unknown superclass 'Base' of 'p_Leaf'` | build + link + run, exit 0 |
| gallery demo (`ui-demo`) | `unknown superclass 'Control' of 'asaot_ui_AvatarNode'`, 76/96 sources | **94/97 sources**, `RESULT: PASS` |

## One command

```
node probes/reach-freefn/run.cjs        # exit 0 iff the closure stays sound
node probes/reach-freefn/mutation.cjs   # proves the assertions have teeth
```

`run.cjs` measures three things and asserts all of them:

| # | measurement | expected |
|---|---|---|
| 1 | `tools/reach-dump.cjs` closure dump (no compilation, ~1 s) | kept **5/5**, nothing dropped |
| 2 | arm A: `--air-app app.xml --main-class p.Main` (the plain default face) | **builds + links + runs to exit 0** |
| 3 | arm B: the same `+ --all-sources` | still builds + runs (the escape hatch must not rot) |

Arm A succeeding **is** the assertion now. If the closure regresses, arm A goes
back to `unknown superclass 'Base' of 'p_Leaf'` and `run.cjs` goes red.
`ui-demo`'s runners deliberately do **not** pass `--all-sources`: the default face
is what must keep working.

Raw outputs of the original (pre-fix) measurements: `run-2026-10-23.txt`,
`mutation-2026-10-23.txt`.

## The five files

```
src/p/Main.as    document class; names NO type at all, only calls make()
src/p/Fac.as     free function make():Leaf -- the ONLY thing that makes this file special
src/p/Leaf.as    class Leaf extends Base  +  constructor does `new Helper()`
src/p/Base.as    Leaf's superclass
src/p/Helper.as  named only from Leaf's ctor
```

`Main` must not name `Leaf`: a single `var l:Leaf;` would put `Leaf` into the
**main** loop's queue, where it is expanded like any other class — which is how the
pre-fix defect could be hidden by an unrelated edit. Post-fix that no longer makes
any difference, so `mutation.cjs` cannot use it as its mutation any more (an input
change can no longer produce the defect); it mutants the **compiler** instead, one
mutant per load-bearing half of the fix:

| mutant | what it undoes |
|---|---|
| **M1** | the forced-files' non-class pass: `enqueue(n)` → `reachable.add(n)` (mark without expanding) |
| **M2** | moves the two forced-file passes back **below** the drain loop (seeds nothing drains) |

Both must make `run.cjs` go red, and both are reverted in a `finally` with a
**hash check** — a harness that leaves a mutant behind would poison every later
run.

> ⚠️ **Shared-worktree hazard**: `mutation.cjs` writes into
> `as3compiler/src/reach.ts`, so it must not run while another session is editing
> that file — the restore step would clobber their in-flight edit with the copy
> this script read at start. It refuses to run if the file is missing its anchors,
> but it cannot detect a concurrent writer by design. Run it on a quiet tree.

## The mechanism, in `src/reach.ts` (pre-fix shape)

```
while (queue.length > 0) { ...drain... }          // <-- the only expansion loop, ended here

// "A forced file is kept whole, so every class it declares is kept with it."
for (...) enqueue(d.fqn);                          // pushes onto the queue -- but nothing drains it now

// "Now walk the forced files' non-class code too: a module statement or free
//  function can reference classes of its own, and it is emitted either way."
for (...) { ...; for (const n of next) reachable.add(n); }   // marked reachable, never expanded

const kept = files.filter(...);                    // <-- what actually compiled
```

The fix hoists every seed **above** the drain loop and turns the second pass's
`reachable.add(n)` into `enqueue(n)`. The invariant the module needs is: *every
reachable class gets its references collected*, regardless of which pass
discovered it.
