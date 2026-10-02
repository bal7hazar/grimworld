> Archived by the orchestrator of track CV on 2026-10-02 from the thread report `grimworld-cv/t-0011` (PR #252, head reviewed `a2e98a5`, reviewer model Claude Opus 5.5, review of 2026-10-02). Documentation only; the review's own text follows unchanged.

## Report

Model: claude-opus-5-5 (Opus 5.5)

### Verdict
PASS WITH FINDINGS

The t-0010 minor is fixed. README and the report now state the 7 of 51 artefacts that differ between the Mac and the VPS as two open groups, in the same terms: (a) persistent/Registry and (b) `logic_integrationtest.test`. The tables and the manifest at `90b4974f` back this. The issue draft's new wording is accurate in substance and names no project. Two notes, neither blocking.

### Revision
a2e98a5027d7936d8d8b1a418bef063481e441f4 (= PR #252 head, OPEN, 33 files; all checks SUCCESS except `indexer-node` SKIPPED), compared with origin/main. I read the fix loop as `git diff 6238e46..a2e98a5`.

### t-0010 finding, status at a2e98a5
| Was | Status | Where |
|---|---|---|
| minor: `logic_integrationtest.test` was said to embed `grimworld_persistent`, so one source was hidden | Fixed. Group (b) is stated apart: no Registry in its build, no dependency on `grimworld_persistent`, "at least two independent sources, both open" | README l.242-251; report l.32 |

### Check against the tables (one-thread series, contracts target)
- Group (a), 6 artefacts:
  - `persistent_Registry` and its copies `persistent_integrationtest_Registry.test` and `persistent_unittest_Registry.test`: Mac text `dc86e41df9bb` / hash `0x04e885bd251a` (builds-mac l.229, 239, 245); VPS `654665be9dce` / `0x0001621259ac` (builds-vps l.156, 166, 172).
  - `grimworld_persistent`: Mac `0628c324dba9` (l.252), VPS `9d63b9603dd6` (l.191-195).
  - `persistent_integrationtest.test`: Mac `b6ed0ee49459` (l.253), VPS `359277459a52` (l.196-200).
  - `persistent_unittest.test`: Mac `804829433083` (l.254), VPS `98342246dafa` (l.201-205).
  - Both test builds list a Registry class, as the text says.
- Group (b): `logic_integrationtest.test`, Mac `f77be9a5c282` (l.250), VPS `02764e4e3ffb` (l.181-185). Its two classes, `FlattenLibrary` and `TickLibrary`, are equal on both machines (Mac l.222-223, VPS l.149-150). `logic_unittest.test` (`c0fe8883079d`) and `grimworld_logic` (`8520ec2c7172`) are equal.
- `git show 90b4974f:contracts/logic/Scarb.toml`: the dependencies are origami_hexmap and starknet, and the dev-dependencies are snforge_std and assert_macros. There is no `grimworld_persistent`, as the text says.
- Total: 7 differ, 44 equal. README and the report agree word for word on the groups and the hashes they quote.

### Findings
| # | Severity | Location | Finding | Evidence or failing scenario | Suggested fix |
|---|---|---|---|---|---|
| 1 | note | README l.162; report l.85, l.110 | Short summaries outside the detailed paragraph still speak of "the Registry difference" as the one open cross-machine fact ("stays open for the Registry difference", "the Registry difference leaves them open"). They are not false, since the Registry is the only class whose hash differs and l.40/l.158 speak of class hashes. But a reader of only these lines would miss source (b). The detailed paragraphs, which the cause-finding task will read, are correct. | `git grep -n Registry a2e98a5 -- spikes/SPK-13/README.md docs/reports/SPK-13-compiler-determinism.md` | Optional: "the cross-machine differences (Registry and `logic_integrationtest`) leave them open". |
| 2 | note | issue-draft.md l.219-223 | "some artefacts (one contract class and some test builds)" leaves out the `grimworld_persistent` program, the package's own Sierra program. It differs too, and it is neither a contract class nor a test build. The CASM claim is limited to "the contract class's CASM", which is right: only the Registry has a CASM column, sha `9eaca75f52b3` on both machines. The draft is unfiled and is offered as an observation, so this does not mislead a fix. | builds-mac l.252 vs builds-vps l.191-195 (`0628c324dba9` / `9d63b9603dd6`) | Optional: "(one contract class, one library program and some test builds)". |

### Coverage
- Read: the fix-loop diff `6238e46..a2e98a5` in full; the one-thread contracts series row by row (builds-mac l.204-254, builds-vps l.131-205); `contracts/logic/Scarb.toml` at `90b4974f`; the previous review t-0010.
- Ran, besides those reads: `git grep` of README, the report, issue-draft and the brief for the cross-machine and Registry statements; `gh pr view 252` for the head, the file count and the checks.
- Issue draft: `git grep -i` for grimworld, hexx, bal7hazar, registry, persistent, glam, arcade, cartridge, /home/ and /Users/ found nothing. The only reference is "a larger private project". I filed nothing.
- Not checked: the logic integration-test sources, i.e. what in them differs across machines (that is the cause-finding task's work). I ran no build. I did not re-verify `collect.py`, `class_hash.py`, `sierra-dump`, `diffs/` or the compiler-source claims; they are unchanged since the t-0006 and t-0009 reviews.
- My first compound shell command was refused (don't-ask mode). I re-ran its parts as single commands.

Verdict: PASS WITH FINDINGS (two notes)
