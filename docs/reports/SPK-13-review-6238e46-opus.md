> Archived by the orchestrator of track CV on 2026-10-02 from the thread report `grimworld-cv/t-0010` (PR #252, head reviewed `6238e46`, reviewer model Claude Opus 5.5, review of 2026-10-02). Documentation only; the review's own text follows unchanged.

## Report

Model: claude-opus-5-5 (Opus 5.5)

### Verdict
PASS WITH FINDINGS

The three findings of t-0009 are fixed. The count of 7 of 51 artefacts that differ, with 44 equal, is confirmed. One new minor: the text says the three test files that differ all "embed" the `grimworld_persistent` program. That is wrong for `logic_integrationtest.test`. The `grimworld_logic` package does not depend on `grimworld_persistent`, and its test build contains no Registry class. So the cross-machine difference has at least two independent sources, not one. The issue draft's "one program" understates it for the same reason.

### Revision
6238e462b69ed2b750034c75784303507272f98e (= PR #252 head, 33 files, all checks SUCCESS except `indexer-node` SKIPPED), compared with origin/main. I read the fix loop as `git diff 9d21082 6238e46`.

### Previous findings (t-0009), status at 6238e46
| # | Was | Status | Where |
|---|---|---|---|
| 1 | minor: `persistent_unittest.test` missing from the differing list | Fixed. All 7 are listed, with "the other 44" | README l.242-246; report l.32 |
| 2 | note: the hash tools differ | Fixed. "starkli on the Mac, `class_hash.py` on the VPS, but the Sierra text sha256 differs too" | README l.246-248; report l.32 |
| 3 | note: "independent of paths" | Fixed. "the thread-order drift is independent of paths" | issue-draft l.233 |

### Recount (one-thread series, contracts target)
Mac `builds-mac.txt` l.204-254 and VPS `builds-vps.txt` l.131-205: 51 artefacts on each side (43 classes, 8 programs/test files).
- Classes: only `persistent_Registry`, `persistent_integrationtest_Registry.test` and `persistent_unittest_Registry.test` differ (text `dc86e41df9bb` / `654665be9dce`, hash `0x04e885bd251a` / `0x0001621259ac`; Mac l.229, l.239, l.245; VPS l.156, l.166, l.172). The other 40 classes have the same text and class hash.
- Programs and test files: `grimworld_persistent` (`0628c324dba9` / `9d63b9603dd6`), `persistent_integrationtest.test` (`b6ed0ee49459` / `359277459a52`), `persistent_unittest.test` (`804829433083` / `98342246dafa`) and `logic_integrationtest.test` (`f77be9a5c282` / `02764e4e3ffb`) differ. `ephemeral_integrationtest.test`, `ephemeral_unittest.test`, `grimworld_logic` and `logic_unittest.test` are equal.
- Total: 3 + 4 = **7 differ, 44 equal**. The implementer's count is right, and README and the report state it the same way.

### Findings
| # | Severity | Location | Finding | Evidence or failing scenario | Suggested fix |
|---|---|---|---|---|---|
| 1 | minor | README.md l.244-246; report l.32; issue-draft.md l.219 | The text says `logic_integrationtest.test` "embeds" the `grimworld_persistent` program and so differs because of Registry. It cannot embed it. At the measured commit `90b4974`, `contracts/logic/Scarb.toml` has no dependency or dev-dependency on `grimworld_persistent` (only origami_hexmap, starknet, snforge_std, assert_macros). The logic test build declares no Registry class: its only classes are `logic_integrationtest_FlattenLibrary.test` and `logic_integrationtest_TickLibrary.test`, both equal across the machines. So a second, independent source differs between the Mac and the VPS: something in the logic integration tests. This weakens the README's framing that the open fact is "the Registry class" and its copies. It will also mislead the Registry cause-finding task the PM plans to start after the merge, which would look only at Registry. The issue draft's "one program of a larger private project" understates it in the same way. | `git show 90b4974f:contracts/logic/Scarb.toml`; builds-mac.txt l.222-223, l.250; builds-vps.txt l.149-150, l.181-185. `logic_unittest.test` and the `grimworld_logic` program are equal (Mac l.249, l.251; VPS l.180, l.186-190), so the difference is specific to the logic integration-test build. | README and report: list `logic_integrationtest.test` apart, as differing although it contains no Registry and its package does not depend on `grimworld_persistent`, with the source of that difference open too. Issue draft l.219: "some artefacts (one contract class and some test builds) of a larger private project". It names no project either way. |

### Coverage
Read: the fix-loop diff `9d21082..6238e46` in full. The two one-thread contracts series row by row (Mac l.204-254, VPS l.131-205), plus the Mac clean and fresh-cache series and the VPS 4-thread series for the same artefacts. The issue draft l.205-234. The previous review t-0009.
Ran: `git grep` of the three documents for the cross-machine statements. `git show 90b4974f:contracts/logic/Scarb.toml`. `gh pr view 252` for the head and the checks.
Issue draft: `git grep -i` for grimworld, hexx, bal7hazar, registry, persistent, /home/, /Users/ found nothing. The only reference is "a larger private project", with no name. The draft is not filed and I filed nothing.
Not checked: the logic integration-test sources (whether some test there pulls a persistent type by path). The manifest shows no such dependency, so I did not look further. I ran no build. I did not re-verify `collect.py`, `class_hash.py`, `sierra-dump`, `diffs/` or the compiler-source claims, which are unchanged since t-0006 and t-0009. A first compound shell command was refused (don't-ask mode); I re-ran its parts as single commands.

Verdict: PASS WITH FINDINGS (one minor)
