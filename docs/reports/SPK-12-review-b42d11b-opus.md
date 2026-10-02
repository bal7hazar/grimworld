> Archived by the orchestrator of track CV on 2026-10-02 from the thread report `grimworld-cv/t-0008` (PR #257, head reviewed `b42d11b`, reviewer model Claude Opus 5.5, review of 2026-10-02). Documentation only; the review's own text follows unchanged.

## Report

Model: Claude Opus 5.5

### Verdict
PASS WITH FINDINGS

(One note, which does not block the merge. All four findings of t-0007 are fixed. Every new figure recomputes from `cost.py`, `cost-output.txt` and `prove-output.txt`. The note and the archived report agree except for the one range in the note's Summary that finding 1 describes.)

### Revision
b42d11b20947430d68e332cc855af59c38025783, compared with main. Fix loop 3 (`05a9745..b42d11b`) changes only `docs/research/SPK-12-client-proving.md` and `docs/reports/SPK-12-client-proving.md`. `git diff --stat 903c38f..b42d11b` also lists only these two files, so the code has not changed since 903c38f.

### Findings
| # | Severity | Location | Finding | Evidence or failing scenario | Suggested fix |
|---|---|---|---|---|---|
| 1 | note | note Summary, line 24 | The Summary puts representative segments under the floor at "14–20 s". §3 (line 247) and the report (line 74) both say "14–18 s". The 20 s comes from representative:100, which has 547,353 steps. §3 (line 250) counts that segment as "above the floor, from 0.55 M". The headline range of 14–31 s is the same in all three places, so no conclusion changes. | `prove-output.txt` run1: representative:1 13.69–14.77 s, representative:10 17.0–18.09 s. Run2: representative:100 18.94–19.74 s, at 547,353 steps. | Write "14–18 s" in the Summary. |

### Verification of t-0007's findings
1. **F + G bound: fixed** in note §7 point 1 (line 455) and report point 1 (line 46). I recomputed it from `cost.py`: segments = F + G + 1 at 79,472,160 each, and `shared` = 6,863,259 + 2.9 M·F + 3,667,902·G.
   - F + G = 6, G = 0: 556,305,120 + 24,263,259 = **580.6 M**.
   - F + G = 6, G = 6: 556,305,120 + 28,870,671 = **585.2 M**.
   - F + G = 7, G = 0: 635,777,280 + 27,163,259 = **662.9 M**. This is the tie against 663.0 M.
   - F + G = 7, G = 1: **663.7 M**. G = 7: **668.3 M**. Both lose.
   - F + G ≥ 8: the 9 segments alone come to 715.2 M, which loses.
   - Every figure in the text matches.
2. **The floor as a range: fixed.**
   - The floor reads 14–31 s and 3.6–3.9 GiB. In `prove-output.txt` the segments under 0.5 M steps run 13.69 s (representative:1) to 30.61 s (busy:40, run2), and their RSS runs 3.56 GiB (run7) to 3.89 GiB (busy:40, run7).
   - On one thread: 37–78 s and 3.0–3.7 GiB. Run8 gives 37.40–78.11 s and 2.97–3.68 GiB.
   - The 140 k-step line is now marked E ("not run"). It names its nearest measured segments: representative:10 at 17–18 s and worst:1 at 23–26 s, which match run1.
   - The §4 table row is now "representative, 1 tick (22,918 steps)".
3. **"7 segments": fixed.** The text now says "F + G + 1 segments".
4. **Commands: fixed.**
   - The block points to each run's header in `prove-output.txt`. Headers run1 to run8, including run6a and run6b, are present.
   - The block adds `(cd spikes/SPK-12 && snforge test)`. `spikes/SPK-12/Scarb.toml` exists, and its `[scripts] test = "snforge test"`. Both `snforge-test-output-1.txt` and `-2.txt` exist.

### The new figures, recomputed
- **Phone time, 19–87 s:** `cost-output.txt` gives 19–42 s for the floor and 35–87 s for busy:40. The formula is T1 / (A2·A3) with T1 from run8.
- **Battery, 2.7–12.3 %:** `cost-output.txt` gives 2.7–5.9 % for the floor and 5.0–12.3 % for busy:40. The figure a proof, 0.20–0.95 %, matches too.
- **The 8 % crossing:**
  - 13 proofs cross 8 % when one proof takes 0.08 / 13 × 12.7 Wh × 3,600 = 281.4 J.
  - At 5 W, that is **56.3 s**.
  - 56.3 s falls inside busy:40's 35–87 s and above the floor's 42 s, as the text says.
- **Memory on the phone, 3.0–3.9 GiB:** this matches run8 for one thread and run7 for six.
- **Fight-heavy, 12–32 %:** this is unchanged and matches `cost-output.txt` (12.1–32.2 %).
- **The note and the report:** they give the same figures on the floor, the phone, the battery, the crossing and the F + G bound. The one exception is finding 1.
- **Leftover wording:** `git grep` over both docs and `spikes/SPK-12/README.md` finds no remaining "about 14 s", "any segment" or "no gate" claim. The one "no gate" left (note line 42) describes the F = 5, G = 0 row, which is correct.

### Coverage
- **Read:**
  - the whole fix-loop-3 diff (`git diff 05a9745..b42d11b`);
  - the previous review t-0007;
  - `cost.py`, `cost-output.txt` and `prove-output.txt` in full;
  - the report's *Key figures* to *Commands run*;
  - the note's §3 thread table and floor lines.
- **Recomputed:** all of the figures above, by hand from `cost.py`'s constants.
- **Code:** I did not reread it, because it has not changed since 903c38f. I relied on t-0001's review of it.
- **Not run:** `cost.py`, `prove.py`, `scarb` and `snforge`. The two `cat` and `git ls-tree` commands were refused, so I used Read and `git grep` instead. I did not check the PR's CI status. The Mac measurements could not be reproduced from the VPS.

Verdict: PASS WITH FINDINGS
