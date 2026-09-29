# [GPT-6-Astra] Audit — PR 82 (SPK-4) — determinism, parity

## Verdict

**PASS**

At **42f4e27c0c59439da78456509a491e5f25fc0010**, all seven findings are resolved. No new regressions found within the audited scope.

## Findings

Severity below records the original finding; none remains open.

| # | Severity | Status | Location | Evidence / verification | Suggested fix |
|---|---|---|---|---|---|
| 1 | major | **Resolved** | [board.cairo:88](/home/claude/projects/grimworld/.claude/worktrees/cli-AUD-82/spikes/SPK-4/cairo/logic/src/board.cairo:88) | Cairo and TypeScript both freeze ring occupants and mask destinations to the interior. Generated masks agree exactly. Regenerated vectors contain **1,799 ring-origin cases, zero movements**, and **2,565 interior movements, zero ring destinations**. The three ring mutants are caught by **1,053 / 69 / 1,528** vectors. | None |
| 2 | major | **Resolved** | [exec.cairo:21](/home/claude/projects/grimworld/.claude/worktrees/cli-AUD-82/spikes/SPK-4/cairo/logic/src/exec.cairo:21) | Both implementations explicitly panic with `exec: empty case`. All **11 empty-input vectors** agree, including their panic payloads. Removing the mirror’s check is detected by all 11 through panic-data differences. | None |
| 3 | major | **Resolved** | [replay.ts:32](/home/claude/projects/grimworld/.claude/worktrees/cli-AUD-82/spikes/SPK-4/ts/replay.ts:32) | Executed positional-file checks: supplied fixture replays **200** vectors; missing and empty files exit **2**; wrong expectation exits **1**, identifying vector **118**. | None |
| 4 | major | **Resolved** | [main.rs:66](/home/claude/projects/grimworld/.claude/worktrees/cli-AUD-82/spikes/SPK-4/vm/runner/src/main.rs:66), [browser_bench.py:102](/home/claude/projects/grimworld/.claude/worktrees/cli-AUD-82/spikes/SPK-4/vm/browser_bench.py:102), [scarb_sample.py:88](/home/claude/projects/grimworld/.claude/worktrees/cli-AUD-82/spikes/SPK-4/vm/scarb_sample.py:88) | Failure paths now propagate nonzero status for the identified discrepancies, errors, browser timeout and incomplete verification. Independently executed native checks: full corpus exits **0**; wrong expectation and empty corpus each exit **1**. Reviewed browser/Scarb negative-run evidence in “Fix loop 1”; committed negative fixture changes exactly one expectation. | None |
| 5 | minor | **Resolved** | [replay.ts:43](/home/claude/projects/grimworld/.claude/worktrees/cli-AUD-82/spikes/SPK-4/ts/replay.ts:43), [bench-core.mjs:28](/home/claude/projects/grimworld/.claude/worktrees/cli-AUD-82/spikes/SPK-4/vm/js/bench-core.mjs:28) | Both now separate initialization, executable loading, first-input serialization and first execution. Files and the first parsed vector precede timing; preparation of the complete corpus follows first execution. The research replaces the contaminated startup figures. | None |
| 6 | minor | **Resolved** | [research:31](/home/claude/projects/grimworld/.claude/worktrees/cli-AUD-82/docs/research/SPK-4-parity.md:31) | Full-tick TypeScript performance and Poseidon parity are explicitly **not measured**. The recommendation rests on the measured primitives; the eight-call calculation is explicitly an illustrative estimate, and neither option claims a measured full tick. | None |
| 7 | minor | **Resolved** | [research:211](/home/claude/projects/grimworld/.claude/worktrees/cli-AUD-82/docs/research/SPK-4-parity.md:211) | Committed sample contains **173 successes and 27 panics**, matching the seeded selection and corpus outcomes. Independently replayed WebAssembly: all 200 outcomes agree; all **173 successful step comparisons differ by exactly 3**. Inspected executable confirms entrypoints at offsets **0/6** and the documented `ap += 3`, `call rel 4`, `jmp rel 0` wrapper. | None |

## Coverage

Reviewed the fix commit, implementation report, changed implementations and harnesses, regenerated tables/vectors, committed Scarb sample, negative fixtures and revised research.

Independent checks:

- **TypeScript:** 10,000 vectors, 1,308 panics, **zero output or panic-data differences**.
- **Mutations:** **20/20 caught**, with every count matching the research. Executed transformations in memory because the normal harness writes temporary files.
- **Native VM:** 10,000 vectors, **zero divergences**, plus successful negative checks.
- **Node WebAssembly:** zero divergences through both `step` and **1,309 batch runs**; committed sample fully agrees.
- **Generation consistency:** inputs exactly match `cases(10000, 4)`; damage tables and interior masks match their generator.

Native/WebAssembly checks used existing artifacts in the implementation worktree after checking the corresponding source files against this checkout. Browser execution and Scarb regeneration were not rerun because they write files; their fixes were assessed from source and the recorded negative-run evidence.

No files changed; no network used.