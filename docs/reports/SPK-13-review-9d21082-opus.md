> Archived by the orchestrator of track CV on 2026-10-02 from the thread report `grimworld-cv/t-0009` (PR #252, head reviewed `9d21082`, reviewer model Claude Opus 5.5, review of 2026-10-02). Documentation only; the review's own text follows unchanged.

## Report

Model: claude-opus-5-5 (Opus 5.5)

### Verdict
PASS WITH FINDINGS

The major and both minors of the previous review (t-0006, at d0c0788) are fixed. The Registry Mac/VPS difference is now an open fact in README.md, the report and issue-draft.md, and no claim remains that a game class hash is reproducible across machines. One new minor: the list of artefacts that differ between the machines leaves one out (`grimworld_persistent_unittest.test`). Two notes.

### Revision
9d2108275eeffde9ea2fb32c084bda1a4df89b8d (= PR #252 head, 33 files), compared with origin/main. Fix loop read as `git diff d0c0788..9d21082` (README.md, docs/reports/SPK-13-compiler-determinism.md, issue-draft.md).

### Previous findings (t-0006), status at 9d21082
| # | Was | Status | Where |
|---|---|---|---|
| 1 | major: platform claimed irrelevant for the game; remedy "rebuilt by anyone" | Fixed. "Plays no part in the race, shown for two artefacts only"; Registry stated as an open fact with the right figures; hypotheses rows for platform and path no longer say "refuted" for the game; remedy 1 now says cross-machine rebuild "not shown"; CI match restated as sizes, not hashes | README l.9, l.37-40, l.158, l.162, l.231-246, l.257-260, l.279-282; report l.13, l.23, l.32, l.82-88, l.106-110 |
| 2 | minor: "27,092 comes from the lock's four threads" | Fixed: "consistent with", and the CI/4-vCPU mismatch is stated as open | README l.247-252; report l.41-44, l.88 |
| 3 | minor: "every one-thread build" | Fixed: "of the targets run (the consumer, on the Mac and the VPS)" | README l.270; report l.41-42 |
| 4 | note: report outside the allowlist | Unchanged, as expected (the archive the orchestrator asked for) | — |
| 5 | note: issue draft read as measured on x86_64 | Fixed: "recorded … from the library's own records, not from a run for this issue" | issue-draft l.41-43 |

Figures of the new text checked against the tables: Mac Registry text `dc86e41df9bb`, hash `0x04e885bd251a` (builds-mac.txt l.117, l.229, and per build l.582-1794, tool starkli). VPS text `654665be9dce`, hash `0x0001621259ac` (builds-vps.txt l.73, l.156, and per build l.506-965, tool class_hash.py). Sierra 10,665, CASM 24,611 and CASM sha256 `9eaca75f52b3` are equal. Each machine has one text in all its series (Mac 12-thread clean 10/10 files=1, fresh-cache, one-thread; VPS 4 and 1 thread). Same commit `90b4974f` and the same `Scarb.lock` `213a10ce…` (env-vps-contracts.txt l.4-5 = builds-mac.txt l.38-39). The program `grimworld_persistent` differs (`0628c324dba9` / `9d63b9603dd6`), and so do `persistent_integrationtest.test` (`b6ed0ee49459` / `359277459a52`) and `logic_integrationtest.test` (`f77be9a5c282` / `02764e4e3ffb`). I compared all 43 classes of the one-thread series row by row (Mac l.204-246, VPS l.131-173). Only Registry and its two `.test` copies differ. All others have equal text and class hashes.

### Findings
| # | Severity | Location | Finding | Evidence or failing scenario | Suggested fix |
|---|---|---|---|---|---|
| 1 | minor | README.md l.242-243; report l.32 ("the `grimworld_persistent` program and two test files"); issue-draft l.219 (indirectly) | The list of artefacts that differ between the Mac and the VPS is incomplete. `grimworld_persistent_unittest.test` also has a different text on the two machines, and each machine is stable on its own value. So four artefacts differ, not three. The open fact will reach the project manager and the game track as stated, so its scope should be exact. The previous review also missed it. | Mac `804829433083` in clean, fresh-cache and one-thread (builds-mac.txt l.142, l.193, l.254). VPS `98342246dafa` in 5 clean and 5 one-thread builds (builds-vps.txt l.126-130, l.201-205). Same size (73,970) and `withdraw_gas` (230). | Add `persistent_unittest.test` to the list in the README and in the report ("three test files"). The issue draft says "one program" and needs no change. |
| 2 | note | README l.237-246; report l.32 | The paragraph lists what is equal on the two machines (commit, lock, Scarb version) but not that the class hashes come from different tools: starkli on the Mac, `class_hash.py` on the VPS (the `hash_tool` column). The text sha256 differs as well, so the hash tool does not explain the difference, and Hub, Market and the other classes match across the two tools. A reader trying to find the cause would still want to know this. | builds-mac.txt l.582 `starkli`; builds-vps.txt l.506 `class_hash.py`. | Optional: one clause saying the text sha256 differs too, so the hash tool is ruled out. |
| 3 | note | issue-draft.md l.232-233 | "this one is independent of paths" refers to the race, which is correct. The section added at l.217-224 leaves the cause of the second observation open, and the path is one of the candidates (README l.162, l.245). If the issue is filed, a reader may apply that sentence to both observations. | issue-draft l.217-224, l.233. | Optional, when it is filed: "the thread-order drift is independent of paths". |

### Coverage
Read: the fix-loop diff in full; README.md l.185-309; issue-draft.md l.185-234 and the fix-loop hunk at l.38-43; the diff of the archived report; the previous review t-0006.
Checked by `grep` against the committed tables: every Registry row on both machines, the summary rows of all 51 one-thread contracts artefacts on both machines, the three series of the four test and program artefacts, and the environments of the contracts target on both machines.
Scanned: README, the report and the issue draft for the remaining cross-machine claims ("reproducib", "rebuil", "platform", "anyone", "byte-identical"). None claims cross-machine reproducibility of a game class hash. The issue draft for project and repository names (grimworld, hexx, bal7hazar, Registry, persistent, home paths): the only match is "a larger private project", with no name. The whole PR diff for secrets and absolute home paths: none.
`gh pr view 252` confirms the head and the 33 files.
Not done: one awk pipeline was refused in this session (don't-ask mode), so I made the class-by-class comparison by reading the two grep outputs instead of with a script. I ran no build. I did not re-verify the compiler-source claims, `collect.py`, `class_hash.py`, `sierra-dump` or the `diffs/`. The pre-existing figures (HexxGenerators, minimal) were checked in t-0006 and are unchanged by this fix loop.

Verdict: PASS WITH FINDINGS (one minor, two notes)
