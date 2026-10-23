# `probes/g11-nondeterminism/` — closing `compiler-gaps.md` G11

G11 was registered as **"the same source, built twice, produced different C — the code
generator is nondeterministic"**, and it was called the most serious gap found, because
every probe and demo in this workspace could then fail at random with errors pointing at
generated code nobody wrote. The retry loop in both demo runners came from it.

**It is not a gap.** The two builds differed because **the compiler itself changed in
between**: another session on this machine was rewriting the C-identifier naming at the
time. All the artifacts below are from 2026-10-23 ~04:00 +0800.

## The timeline (mtime of the artifacts on disk, not recollection)

| when (`+0800`) | artifact | what it shows |
|---|---|---|
| 04:00:10 | `temp/gapprobe/nc-bind2.c` | the compiler session's own probe: `struct Date { double time__; }` + `offsetof(Date, time__)` while the hand-written body says `o->_time` → **does not compile** |
| 04:00:19 | `probes/array-scope/cc.txt` | **my** failing build: 19 real errors + clang's `too many errors emitted` sentinel, hazard set **identical** to the line above |
| 04:00:50 | `temp/gapprobe/nc-bind3.c` | `Date` repaired → **1** error left (`socket`) |
| 04:01:34 | `temp/gapprobe/nc-bind4.c` | everything agrees → **0** errors, and it links (`nc-bind4.exe`) |
| **04:24:34** | commit `721e12f` (阶段二百四十七) | the naming rewrite lands: reserved-name table machine-generated, file scope moves to a `__` **suffix**, and `cIdent` is deliberately left alone so struct fields keep agreeing with the hand-written built-in bodies |
| 05:11:26 | `probes/array-scope/Main.c` | my rebuild on the committed tree: `double _time;`, props `offsetof(Date, _time)` — consistent, builds |

Two facts fall out of that table:

1. **The failure existed for 84 seconds and decayed monotonically (20 → 1 → 0 errors).**
   A generator that "sometimes misspells a field" does not converge like that; a human
   edit does. The commit at 04:24:34 is the edit, and it says in its own message why the
   final design refuses the intermediate state (`cIdent` **deliberately** not changed).
2. **My failing build sits 9 seconds after the compiler session's own failing artifact
   and 24 minutes before the commit that fixed it.** Not a coincidence, and not a
   property of the generator.

## The three artifacts, kept because `temp/` gets cleaned

| file | size | clang (this tree) | kind |
|---|---|---|---|
| `artifact-1-struct-time__.c` | 2 574 303 B | 19 errors, **truncated** (clang's `-ferror-limit` is 20) | `Date._time`, `TextField.___restrict`, `ServerSocketConnectEvent.socket` |
| `artifact-2-struct-socket-1-error.c` | 2 574 267 B | 1 error | `ServerSocketConnectEvent.socket` |
| `artifact-3-consistent.c` | 2 574 236 B | 0 errors | — |

All three are `nc-bind{,2,3,4}.c` from the compiler session's probe, copied byte-for-byte.
They are **not** used as a fixture oracle for the generator: they are used because they
are the only surviving record of the failing state, and because they let the probe show
that its instrument (clang) *distinguishes* the broken state from the fixed one.

## What the measurement now asserts

```
node probes/g11-nondeterminism/run.cjs
```

| part | assertion |
|---|---|
| **A** | the compiler tree is printed: `HEAD`, `src/` **content hash**, tracked modifications, untracked files. Dirty vs `HEAD` is **context**, not a verdict — determinism is a property of a *generator revision*, so what matters is that the revision's bytes do not move while we build (checked after B) |
| **B** | **5 builds** of the same program, same command, same tree, with the **input hash** recorded before and after and the **`src/` content hash sampled around *every single build*** ⇒ exactly **one** distinct generated C (`3698965 B`, `sha256/16 = f0ac0ff461e604bf`). Sampling per build rather than once at the two ends is load-bearing: an edit that is put in place and **reverted** inside the window leaves both endpoints identical, so an endpoint pair cannot tell "the generator is unstable" from "a build caught someone's mutant". The compiler session's own mutation harness (`as3compiler/temp/g14/mutate.cjs`) does exactly write-mutant / run / restore-original-bytes, and it produced a false red here on 2026-10-23 |
| **C** | spelling tripwire on the fresh C: `Date._time` / `TextField.___restrict` / `ServerSocketConnectEvent.socket` must agree in the **struct**, in the **props table** and in the **hand-written body literal** — the three places G11 disconnected |
| **D** | the three artifacts must report the expected clang errors **and** decay monotonically (the trend, not just the values) |
| **E** | the hazard set in my failing log must equal the hazard set in artifact-1 — the cross-check that ties the two artifacts together |

Evidence is **appended** to `run-<date>.txt` (never overwritten: an earlier green must not
be erasable by a later red).

### Three verdicts, because there are three different situations

| exit | verdict | when |
|---|---|---|
| `0` | **PASS** | all five measurements green **and** the `src/` content hash was stable across them. On a dirty-but-stable tree the PASS names the content hash and says so: determinism is certified *for that revision*, not for the commit |
| `3` | **INCONCLUSIVE** | all measurements green but the compiler source **moved mid-run** — including a move confined to one build (the per-build samples catch it; the endpoint pair does not) — a green would pin a tree we never saw, a red would blame this workspace for someone else's edit. The gate reports this as a loud `[SKIP]` and counts it separately |
| `1` | **FAIL** | a measurement actually came out wrong (several hashes **with no contaminated build**, a spelling disagreement, artifacts not decaying, a missing/incorrect hazard set) |

## Teeth

```
node probes/g11-nondeterminism/mutation.cjs      # 10/10
```

| mutation | what it changes | what must go red |
|---|---|---|
| **M1** | the *healthy* artifact-3: rename only the struct field `_time` → `time__` | clang must report `no member named '_time'` — this is G11's exact shape, made from the good file in one token |
| **M2** | artifact-3's props entry → `offsetof(Date, nope)` | clang must name `nope` (with M1: the checker reads both the struct side and the props side of the file) |
| **M3** | one string literal in `Main.as` | the generated C's hash **must change** — otherwise "5 identical hashes" could be a constant, i.e. a vacuous equality |
| **M4** | `run.cjs`'s own expectation for artifact-3 (0 → 1 error) | the gate must fail with a `FAIL: artifact-3-consistent.c` line |
| **M5** | `ASC_G11_FORCE_SKIP=1` (the generator *pretends* to have moved mid-run) | the gate must report **INCONCLUSIVE with exit 3** and must **not** print `PASS:` — otherwise a test hook could launder an unmeasured run into a green |
| **M6a** | `ASC_G11_FORCE_ITER=1` (the generator *pretends* to have moved **during** build 1) | same: exit 3, with build 1 named as the contaminated one |
| **M6b** | `distinctVerdict()` driven directly: 2 distinct outputs with 0 vs 1 contaminated build | with 0 contaminated it must still read `THE GENERATOR IS NONDETERMINISTIC` **and** raise the failure; with 1 it must say "NOT evidence of nondeterminism" and raise nothing. Without this half, "skip whenever the hashes differ" would satisfy M6a while silently retiring the only measurement here that can detect a genuinely nondeterministic generator |

Every watched file is restored in `finally` and verified by sha256; the mutants are
deleted. Nothing here writes to the compiler repo — the whole point of G11 is that the
compiler tree must stay clean.

## Things this exercise changed outside the probe

* **Both demo runners no longer retry the build.** They print the compiler tree state
  instead (`ui-demo/air-run.cjs::compilerTree`). A retry hid the cause *and* would disguise
  a real defect as "succeeded on attempt 2".
* **The old advice is withdrawn.** `CONTRIBUTING-widget.md` §4 used to say "just re-run the
  build". It now says: look at `git -C ../as3compiler status --porcelain` first.
* **The measurement's validity criterion got sharper.** The first version failed the probe
  whenever the tree differed from `HEAD` — which on this box means "always red while the
  other session works", i.e. a coin flip, and a gate nobody can trust. The criterion is now
  *"did the generator revision move during the measurement"*, which is both stricter about
  the thing that matters and immune to someone else's uncommitted work.
* **…and sharper again, because the endpoint pair had a hole.** On 2026-10-23 08:45 (+0800)
  this gate printed a red — `distinct hashes: 2 of 5  -> THE GENERATOR IS NONDETERMINISTIC`,
  one build 82 B shorter than the other four — while its own `src/` hash was *identical*
  before and after. Both readings were true and the conclusion was still wrong: the compiler
  session was running its G14 mutation harness (`as3compiler/temp/g14/mutate.cjs`) at that
  moment, and that harness writes a mutant, runs the unit group, then **writes the original
  bytes back** (hashing them to prove it). A before/after pair cannot see an edit that is
  reverted inside the window — and *revert-in-place is the guarantee the harness makes*.
  12 clean re-runs afterwards produced 1 hash. Fix: sample `src/` around **every** build and
  attribute the difference to the move (exit 3, `[SKIP]`) instead of to the generator. The
  attribution itself is now a mutation target (M6b), so "skip whenever the hashes differ" —
  which would retire the only real nondeterminism detector here — cannot pass.

## On this machine, the tree really is being edited concurrently

While this probe was being written, section **A** observed the compiler tree go from clean
(`?? icudtl.dat` only) at 21:56 UTC to **four tracked modifications** (`src/air-app.ts`,
`src/index.ts`, `src/reach.ts`, `test/unit/reach.ts`) at 22:03 UTC — another session's
work on the *next* stage. That is not an excuse invented for this document; it is the
mechanism, caught in the act, and it is why A is part of the measurement instead of a
footnote.