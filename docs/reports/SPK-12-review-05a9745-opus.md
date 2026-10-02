> Archived by the orchestrator of track CV on 2026-10-02 from the thread report `grimworld-cv/t-0007` (PR #257, head reviewed `05a9745`, reviewer model Claude Opus 5.5, review of 2026-10-02). Documentation only; the review's own text follows unchanged.

## Report

Model: Claude Opus 5.5

### Verdict
PASS WITH FINDINGS

(Two minors, two notes. The four findings of the previous review (t-0001, at 903c38f) are fixed. Every figure in the archived report matches the note and the committed outputs, but the report carries over two wrong claims from the note: the first was written in fix loop 2 and the second predates the PR's fix loops. Neither changes the recommendation, which is to keep L2 batches.)

### Revision
05a974551344b7310dd6a27b1746d1803a53ecc2, compared with main (merge-base read with `git diff origin/main...HEAD`). The PR has 22 files. Fix loop 2 (`903c38f..05a9745`) touches `docs/research/SPK-12-client-proving.md` (+12/−4) and adds `docs/reports/SPK-12-client-proving.md` (137 lines). Every file is inside `spikes/SPK-12/**`, `docs/research/` or `docs/reports/`. Nothing is in `contracts/` or `client/`.

### Findings
| # | Severity | Location | Finding | Evidence or failing scenario | Suggested fix |
|---|---|---|---|---|---|
| 1 | minor | note §7 point 1 (line 446); report *The result* point 1 (line 46) | The claim "proofs win S1 only with no gate and about 6 or fewer Fate actions" is false. In `cost.py` a gate adds a segment just as a Fate action does (`segments = fate + gates + 1`), so the bound is on F + G, not on F with G = 0. Fix loop 2 rewrote this sentence (the previous finding 3) but kept the old "no gate" condition, and the archived report repeats it to the owner. | With `cost.py`'s constants, F = 5, G = 1 gives 7 segments × 79,472,160 = 556,305,120, plus `shared(5, 1)` = 4,513,259 + 2,350,000 + 14,500,000 + 3,667,902 = 25,031,161. That is 581.3 M against 663.0 M, so proofs win with one gate. F = 0, G = 6 gives 556.3 + 22.9 = 579.2 M, which also wins. At F + G = 7 the case G = 0 ties (662.9 M) and any G ≥ 1 loses (F = 6, G = 1: 663.7 M). | Write "only when Fate actions and gates together are about 6 or fewer (F + G ≤ 6; 7 with no gate is a tie)", in both the note and the report. |
| 2 | minor | note Summary (line 23), §3 (lines 243–244, 274), §4 table (line 303); report *Key figures* (line 73) | The rule "about 14 s and 3.6 GiB for any segment under ~0.5 M steps" contradicts the note's own measurements. Several segments under 0.5 M steps take 17–31 s, and that time depends on the segment's content (busy/worst cases use 578–582 Poseidon calls against 115), not only on its step count. Line 274 labels "a segment of 23 representative ticks, ~140 k steps: about 14 s (M)" as measured, but that segment was never run. The phone figures for the floor (19–42 s, 2.7–5.9 % of the battery for 13 proofs) rest on the 1-tick run alone. | `prove-output.txt`, all 12 threads: worst:1 (128,172 steps) 23.46/25.93 s; busy:10 (247,686) 26.13/25.39 s; busy:40 (423,740) 26.9/30.61 s; representative:10 (70,663) 17.0/18.09 s. Only representative:1 (22,918) is about 14 s. The note's §4 table also gives busy:40 (0.42 M steps) its own T1 of 70.8–78.1 s, twice the floor's 37.4 s, right under the row that says "any segment under ~0.5 M steps". With busy-like segments, `cost-output.txt` gives 13 proofs 5.0–12.3 % of the battery, which crosses SPK-6's 8 %. | Restate the floor as a range: about 14–18 s for representative segments and 23–31 s for worst/busy ones under 0.5 M steps (M). Drop the "(M)" on the 140 k-step line, or mark it E. Give the S1 battery figure as 2.7–12.3 % (floor to busy:40). |
| 3 | note | note §7 point 1, the parenthesis | "`shared(F, 0)` and 7 segments at 79,472,160 each" holds only for F = 6. The 662.9 M figure at F = 7 uses 8 segments. | 8 × 79,472,160 + `shared(7, 0)` (27,163,259) = 662,940,539. With 7 segments the total would be 583.5 M. | Write "F + 1 segments". This goes away if finding 1 is fixed. |
| 4 | note | report *Commands run* (lines 125–131) | The block lists only run1's `prove.py` command. The *Key figures* table also uses run3 (2,600 ticks), run6a/6b (4,500 ticks, `--params …canonical_without_pedersen.json`) and the thread runs 7–8 (`--threads 6`, `--threads 1`). The snforge runs behind `snforge-test-output-*.txt` are missing too. | `prove-output.txt` headers run2 to run8 each name their own command line. | List the run2 to run8 commands, or point to `prove-output.txt`'s headers, and add the snforge command. |

### Verification of the previous review's findings (t-0001)
1. The parenthesis "36.3 M": fixed. It now reads "(43.2 M)" in the note (line 160), in the report (line 102) and in `cost-output.txt` ("proofs: shared L2 txs 43.2 M" for F = 10, G = 2).
2. The as-it-stands worst tick over 40 M: fixed in three places: the note Summary (lines 45–47), a sentence under the fight-heavy table (lines 151–153) and §7 point 2. The report marks it "notional" in point 2 and in its table. 816,939 + 19,675,090 + 20,873,867 + 4,436,950 = 45,802,846 > 40,000,000.
3. "5 or fewer Fate actions": the figures are fixed. 581 M at F = 6 (7 × 79,472,160 + 24,263,259 = 580,568,379) and 662.9 M at F = 7 are right. The condition is still wrong (findings 1 and 3).
4. The archive: fixed. `docs/reports/SPK-12-client-proving.md` is in the PR and matches the note's pointer (line 80). No `REPORT.md` pointer remains, checked with `grep` over the note and `spikes/SPK-12/README.md`.

### The archived report against the note and the outputs, figure by figure
- Proving table: every step count, wall time, RSS and proof size in the 1-, 10- (busy), 2,600- and 4,500-tick rows matches `prove-output.txt` runs 1, 3, 6a and 6b.
- 1.08–1.26 MB: the smallest proof is 1,076,280 bytes (representative:10) and the largest 1,255,743. Verification 0.19–0.58 s: the extremes are worst:1 run 2 and representative:1 run 1. The 2,700-tick case stops under `canonical_small` (run4). "Six threads are as fast as twelve" holds against run7 versus runs 1–2.
- 115–121 L2 gas a step, 79,472,160 ($0.070), 46 / 66 / 680 ticks a proof: these match `cost-output.txt` and the note's §3.
- S1 table (498.2 / 1,076.3 / 2,066.3 M; $0.439 / $0.948 / $1.820; 0.75× / 1.62× / 3.12×), fight-heavy table (13,784.1 M $12.144, 10,826.3 M $9.538, 0.078× / 0.099×), break-even 39 / 55 / 2 / 3 at 2,066,003 L2 gas: all match `cost-output.txt`.
- Phone: 19–42 s, 3.0–3.6 GiB, 2.7–5.9 %, 12–32 %: these match `cost-output.txt`'s phone table and the note's §4 (but see finding 2).
- References e9b8cef, 2a8304d, f8810c5, 467d5c6: the same as the note's header (line 9). The deviation D-64 → D-111 and the questions Q1–Q6 match the note (lines 80 and 481–486); the report leaves out the note's "why" column, which is acceptable.
- The byline `[Opus 5.5]` matches the note's Author line.

### Coverage
- Read: the whole fix-loop-2 diff; the archived report in full; the note's §3–§4 and the lines it changed; `cost.py`, `cost-output.txt` and `prove-output.txt` in full; the previous review t-0001. I recomputed findings 1–3 by hand from `cost.py`'s constants.
- The code (`segment.cairo`, its tests, `prove.py`) did not change since 903c38f (`git diff --stat 903c38f..05a9745` lists only the two docs). I relied on t-0001's code review and did not reread it.
- Not run: a compound `git fetch` command was refused, so I read `origin/main` as fetched before, and the PR's head is this worktree's HEAD (05a9745). `scarb`, `snforge`, `cost.py` and `prove.py` were not run. The Mac measurements and slingfall at f8810c5 could not be checked from the VPS.

Verdict: PASS WITH FINDINGS
