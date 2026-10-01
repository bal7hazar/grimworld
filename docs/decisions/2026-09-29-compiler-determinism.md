# D-154: builds of the same sources that differ (Scarb 2.19.4)

| | |
|---|---|
| Raised by | `[Opus 5.5]` map library orchestrator, `bal7hazar/hexx-cairo` #37 (M1-T1c), REPORT.md *Fix loop 1* |
| Decided by | `[Opus 5.5]` project manager, 2026-09-29, under D-128 |

## The facts (the library's)

Four builds of the same sources gave four hashes of the compiled test files; one measured 0.22 to
0.62 % more gas on 42 tests, all through `Digger::dig` (taken over from `origami_hexmap`
unchanged). In CI three times (+0.5 to +1.3 %); once a Starknet contract of the library's fixture
compiled to 27,101 Sierra felts instead of 27,092, then back. Toolchain, actions, runner, cache
identical; nothing in the code found that can vary. **Inferred, not proved**: Scarb 2.19.4's
compiler is not deterministic on some code.

## Why it matters

A contract whose Sierra differs between two builds of one commit may have another class hash: the
declared class may not be rebuildable from the tagged source. Gas budgets on code that reaches the
digger (the map generator, SPK-7's figures, ENG-05) can flake.

## Decided

1. **N-3 (M1-T4a) keeps the library's slot**: the library's release is on the game's critical path
   (ENG-02, ENG-05) and the flake does not block it: its gate stays exact, a gas-only mismatch is
   re-run once and every occurrence is recorded with its artefacts.
2. **The diagnostic is SPK-13, lent to track CV on the Mac** (D-149: a spike without Sepolia; the
   Mac has room): reproduce, keep a good and a bad Sierra, diff them, minimise to a small program;
   check whether it also occurs **on the game's contracts** (class hash of `contracts/` built
   several times) and across the two machines. Allowlist: `spikes/SPK-13/**`, its brief and
   report; `hexx-cairo` is read from a clone at a named commit. Research profile plus builds;
   `[GPT-6-Sol]` reviews the minimisation.
3. **A public issue to `starkware-libs/cairo`** is prepared by SPK-13 as a file; filing it is the
   owner's go (outward, in the owner's name).
4. Meanwhile, **every deployment records the class hash it declared and the commit**, so that a
   later rebuild can be compared (OPS-01; the game's orchestrator for any deployment before it).

## What would reverse it

SPK-13 finding the cause in our code or our cache (then it is a fix, not a compiler report); the
flake reaching the game's CI often enough to stall merges (then budgets get a stated tolerance on
the paths through the digger, decided on SPK-13's figures).

## D-164 (2026-09-30): the gate when the drift blocks a merge

`hexx-cairo` #49 (M1-T2): CI built `HexxGenerators` at 27,101 Sierra felts on both attempts, the
committed snapshot and two clean local builds of the same commit give 27,092; CASM equal; the sixth
occurrence, always the same second value; the pull request does not touch the class.

**Option (B)**, `[Fable 5.1]` project manager, under D-128: the class-size snapshot records **the two
observed builds** of that class, both exact (27,092 and 27,101 Sierra felts, CASM 49,375), each with
the commit and the run that observed it; **any third value fails**. It is a narrow exception, not a
tolerance; no merge with a red check; no rule of repeated re-runs (a re-run that always gives the
same other value proves nothing). It is reverted to one value when SPK-13 explains the difference.
**A fact for SPK-13**: the CI runner always gives one value and the local machine always the other:
the difference follows the build environment (compiler binary, cache, platform), not chance; SPK-13
compares the CI runner's toolchain with the VPS's and the Mac's.

## D-164 extended to the gas gate (2026-10-01)

Twice on 2026-10-01, in CI runs on changes with no Cairo code (`hexx-cairo` #61 run 36809041479,
#70 run 36836722836), the same 40 rows of `Digger::dig` and the facade's `open_with_*` measured
+0.22 % to +1.94 % against `gas/takeover_tests.snap`: the same second build the VPS gives; other
runs give the snapshot exactly. **Decision** (`[Fable 5.1]` project manager, under D-128): the same
rule as the class-size gate. A file `gas/takeover_tests.builds` holds, per row, the exact second
observed value, cited by the run that observed it; the gate accepts the snapshot's value or that
exact value, nothing in between, and any third value fails. A new line needs the project manager's
decision; the file goes when SPK-13 finds the cause. Task **LIB-04d** (Sonnet 5.5). No tolerance:
the two builds are two programs, both measured exactly.
