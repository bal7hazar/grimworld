> Archived by the orchestrator of track CV on 2026-10-02 from the thread report `grimworld-cv/t-0001` (PR #257, head reviewed `903c38f`, reviewer model Claude Sonnet 5.5, review of 2026-10-02). Documentation only; the review's own text follows unchanged.

## Report

Model: Claude Sonnet 5.5

### Verdict
PASS WITH FINDINGS

(One minor, three notes. All five fixes of the previous review hold. The one minor is a figure introduced by fix 2's own rewrite; no table, script or output figure is affected.)

### Revision
903c38f63d368f10572ab15d0957cf8eb88dabfc (read with `git show` and `git diff 4c2b25c...903c38f`, not checked out), compared with main at 4c2b25c. The PR adds 22 files, all under `spikes/SPK-12/**` and `docs/research/SPK-12-client-proving.md`: inside the brief's allowlist, nothing in `contracts/` or `client/`.

### Findings
| # | Severity | Location | Finding | Evidence or failing scenario | Suggested fix |
|---|---|---|---|---|---|
| 1 | minor | `docs/research/SPK-12-client-proving.md` §2, break-even table, first row (line 154) | The parenthesis gives the wrong total for the transactions taken out of the 663 M. The row says "`enter`, `leave`, the central reading's 10 Fate actions and 2 gates (36.3 M)". Those four items sum to 43.2 M, and 36.3 M is the Fate actions and gates alone, without `enter` and `leave`. The row's own result (2,066,003 and 39 ticks) uses 43.2 M, so the text contradicts its result. This is fix 2's own rewrite, in the arithmetic the previous review asked to be made consistent. | `cost.py`: `shared(10, 2)` = 4,513,259 + 2,350,000 + 10 × 2,900,000 + 2 × 3,667,902 = 43,199,063, and `cost-output.txt` prints "proofs: shared L2 txs 43.2 M" for F=10, G=2. (663,000,000 − 43,199,063) / 300 = 2,066,003, the figure in the table. 36.3 M = 29,000,000 + 7,335,804 only. | Write "(43.2 M)". |
| 2 | note | §2, fight-heavy rows; Summary; §7 point 2 | The "as it stands" worst tick alone costs 45.8 M, above the 40 M batch limit. SPK-15's table (README, *A worst batch against 40 M*) says a 40 M batch holds 0 such ticks as it stands. The 13,784 M / $12.14 batched figure and "a worst tick sent alone costs 36–46 M" therefore price a transaction D-172's own limit would not let through; only the "with L1–L4" figure (35.9 M, under 40 M) is sendable. The note calls it "the bound of a pathological expedition", but never says that the as-it-stands case does not fit one batch. | 816,939 + 19,675,090 + 20,873,867 + 4,436,950 = 45,802,846 > 40,000,000. | One sentence at the table: the as-it-stands figure is a notional price, since no batch holds that tick (SPK-15). |
| 3 | note | §7 point 1 | "proofs win S1 only if it has 5 or fewer Fate actions and no gate" reads as a threshold, but 5 is only the modelled case. With no gate, segments F+1: 79.47 (F+1) + 6.86 + 2.9 F < 663 holds for F ≤ 6 (F = 6: 580.6 M; F = 7 ≈ 663 M, the tie). | Recomputed from `cost.py` constants. | "about 6 or fewer", or "at 5 (the modelled case)". |
| 4 | note | note header and §1 | The pointer to the archived report now reads `docs/reports/SPK-12-client-proving.md`, which is not in this PR (the 22 files above). That fixes the dead `REPORT.md` pointer provided the archive lands with or right after the merge (objective 2 of the track's brief says "archive"). | `git diff --name-only 4c2b25c...903c38f` lists no `docs/reports/` file. | Archive the report in the same step as the merge. |

### Verification of the five previous findings
1. Pointer to the never-committed `REPORT.md` and the D-64 → D-111 deviation: fixed. D-111 is stated as the owner's later decision, the note models reveals inside segments, and the report pointer is the archive path (finding 4). Holds.
2. The 37-tick break-even including Fate and gate transactions: fixed in the figures. The row is now 39 ticks (2,066,003 a tick), and the old 2,187,122 / 37 are kept as a lower bound. I recomputed 79,472,160 / 2,066,003 = 38.5 → 39; /1,469,435 = 54.08 → 55; /45,802,846 → 2; /35,943,656 → 3; and the F=5, G=0 row (2,138,789, 38). All hold. The parenthetical total is wrong (finding 1).
3. The phone-time formula: fixed. low = T1/(0.8 × 2.5) = T1/2.0 and high = T1/(0.5 × 1.8) = T1/0.9. 37.40/2.0 = 18.7 → 19 and 37.53/0.9 = 41.7 → 42; 70.77/2.0 = 35 and 78.11/0.9 = 87; 65 × 2.62–3.14 = 170–204 s → 85–227 s. T1/T6 ratios 37.40/14.27 = 2.62 and 78.11/24.90 = 3.14. Holds.
4. The slope of 11–14 s per million steps: recomputed from the measurement rows above the 0.55 M floor (19.3 s at 0.55 M): 13.4 s/M at 5.3 M, 12.9 s/M at 10.6 M, 10.9–12.5 s/M at 13.8 M, 13.3 s/M at 23.8 M. The stated range holds. Memory 1.5 GiB/M: 21 GiB / 13.78 M = 1.52. Holds.
5. The fight-heavy battery total: 13 × 0.93 % = 12.1 % and 13 × 2.48 % = 32.2 % (85 s × 5 W / 45,720 J, 227 s × 5 W / 45,720 J). The "12–32 %" is correct, and 12.7 Wh × 3,600 = 45,720 J.

### Other arithmetic recomputed from `cost.py` and its output (all match)
- Per-proof settle: 77,321,760 + 420 × 5,120 = 79,472,160 L2 gas, $0.070; 75 M = $0.066.
- S1 rows: 6, 13, 25 segments → 498.2 M / 1,076.3 M / 2,066.3 M; 0.75× / 1.62× / 3.12×; $0.439 / $0.948 / $1.820 against $0.584.
- Fight-heavy: 300 × 45,802,846 + 43.2 M = 13,784.1 M ($12.144) and 300 × 35,943,656 + 43.2 M = 10,826.3 M ($9.538); 13 × 79.47 M + 43.2 M = 1,076.3 M; the ratios 0.078× and 0.099×.
- Ticks a proof holds: 46, 66 and 680. A 23-tick segment is about 506 M virtual gas, so one proof a segment holds.
- L2 gas a step: 121, 115 and 116 (64.0 M / 529,871; 15.27 M / 132,336; 35.90 M / 308,390). Worst tick in steps: 20,873,867 / 115 = 181 k, per call 171 k, 23 ticks about 4.35 M steps.
- The SPK-15 inputs in `cost.py` (19,675,090; 20,873,867; 15,882,120; 14,807,647; 4,436,950) match `spikes/SPK-15/README.md` at 0f4b571.

### Code review of the spike (`segment.cairo`, `tests/test_segment.cairo`, `prove/prove.py`)
- `segment` deserialises the words and the content, refuses trailing felts, and binds IN_HASH, CONTENT_HASH, rules, ticks, OUT_HASH, clock and defeated in the public header; `prove.py` compares the verifier's VERIFICATION_OUTPUT to the `scarb execute` header, so the claim "output = header" is checked, not assumed.
- `run` splits ticks into u8 runs of at most 255 and stops after a defeat; the chaining and defeat tests assert what they name. Minor observation, not a finding: with `ticks = 0` the rules are not validated (`segment(…, rules = 7, 0)` returns a header), because the assert is inside the loop; irrelevant to a spike.
- `prove.py`: `ru_maxrss` scaled by platform (bytes on macOS, KiB on Linux) correctly; no secret, no network write, no proof file committed.

### Coverage
- Read: the whole diff against the merge-base (22 files); the research note in full; `cost.py`, `cost-output.txt`, `segment.cairo`, `test_segment.cairo`, `prove.py`; the brief on main; SPK-15's README at 0f4b571. Arithmetic recomputed by hand from the committed constants and measurement tables.
- Not run: the head was not checked out. `git fetch` and `git checkout` were refused to this run, and compound shell commands were refused, so I read the revision with single `git show` / `git diff` commands, which do not need a checkout. `scarb build`, `snforge test` and `prove.py` were not run; the committed clean runs (`snforge-test-output-1.txt`, `-2.txt`, `prove-output.txt`) were taken as given, and I did not audit the M figures against a rerun. The Mac measurements, the stwo-cairo build and the slingfall references (`f8810c5`) could not be checked from this run. I had no access to `prove-output.txt` content beyond what the note quotes.
