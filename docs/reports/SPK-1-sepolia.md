# [Opus 5.5] SPK-1 — Latency and cost on Sepolia

## Summary
SPK-2's native contracts (`spikes/SPK-2/native/`, unchanged) are now deployed on Starknet Sepolia
(0.14.4). They were measured from the owner's Sepolia account. Hub is
`0x98e5e98dd076c62ad0f89c2931d29be06a227a4ef2901b42e33a1bb5015300`, Instances is
`0x408dbc81e3d39ef65ee9393464f2dee3cce13df43f9e65edda07d4c63393a84` (`spikes/SPK-1/sepolia.json`).
The findings are in `docs/research/SPK-1-sepolia.md`. Pull request:
https://github.com/bal7hazar/grimworld/pull/45 (CI green; not merged).

- **Latency**, measured as the first positive receipt response (70 transactions, receipt polled
  every 250 ms):
  - pre-confirmed: p50 **1,265 ms**, p95 **2,774 ms**, max 3,019 ms. These are upper bounds; no
    valid lower bound was recorded (fix loop 1, finding 3).
  - ADR-0001's **p95 ≤ 3 s is met**. **p50 ≤ 1 s is not decided by this sampling**: the tick
    gives 1,020 ms and the cheap action 1,267 ms, both within one poll interval plus a round trip
    (about 410 ms) of 1 s.
  - Accepted on L2: p50 3,764 ms, p95 4,517 ms, max 4,765 ms.
- **Meter: Sierra gas.** Evidence in research §3:
  - the game calls are within 2–18 % of snforge's Sierra-gas figures, and 0.79–0.87× devnet's
    VM-resource figures for compute-heavy calls;
  - the figures are not rounded (devnet's are multiples of 40,000);
  - the classes are Sierra 1.9.3 (game) and 1.7.0 (account).
- **Mixed evidence against the local node:**
  - slightly below it on the heavy actions: worst tick 5,129,938 L2 gas on Sepolia against
    5,156,800 on devnet (0.995×), queues near goblins 0.88–0.93×;
  - above it on the light ones: exploring queue, enter and leave 1.15–1.29×. Under Sierra gas the
    non-game remainder is heavier: validation 392,815, fee transfer 455,360, account execute about
    207,000.
- **Expedition at today's mainnet prices, zero tip: $0.874 (S1), $0.685 (S2)**, against $0.925 and
  $0.702 on devnet's receipts at the same prices (0.945×, 0.976×). **Verdict: the $0.50 threshold
  fails, at 1.37× to 1.75×.** The tip paid (0.1 Gfri) adds $0.0041 (S1) and $0.0032 (S2).
- **D-129's reversal condition ("Sepolia figures at or above the local ones") is not met.**
  Sepolia is slightly below the local figures on the expeditions and the tick, and above them on
  the light actions. That mixed evidence goes to the project manager (Escalations).
- **Non-game remainder** (receipt minus the game call), observed for these actions and this
  account: 1.34M–1.62M L2 gas (3.0M for enter). It is not a universal floor.
- **Sent: 105 transactions, 72.22 test STRK** (balance 305.13 → 232.91). The two declares alone
  cost 55.68 STRK.

## Files changed
- `spikes/SPK-1/package.json`, `pnpm-lock.yaml`: starknet.js 10.8.0, installed in the spike folder only (`node_modules/` is ignored).
- `spikes/SPK-1/lib.mjs`: variables by name, redaction of every output and error, chain-id guard, `User-Agent`, and a sender with a transaction cap, 250 ms receipt polling and stop on revert.
- `spikes/SPK-1/probe.mjs`, `probe-output.txt`: read-only network, account and price probe.
- `spikes/SPK-1/deploy.mjs`, `deploy-output.txt`, `deploy-output-run1.txt`, `sepolia.json`: declare, deploy, link and hub setup (7 transactions).
- `spikes/SPK-1/measure.mjs`, `measure-output.txt`: the measured run (98 transactions: receipts, bounds, tips, block prices, timing, traces).
- `spikes/SPK-1/latency.py`, `latency-output.txt`: percentiles.
- `spikes/SPK-1/prices-output.txt`: `spikes/SPK-2/prices.py` output, unchanged, with the owner's endpoint redacted.
- `spikes/SPK-1/money.py`, `money-output.txt`: SPK-2's money method on Sepolia's receipts beside devnet's, plus the meter and fixed-part tables.
- `spikes/SPK-1/check_secrets.py`: the AC-4 scan (prints counts and coverage only; `--log` required since fix loop 1).
- `spikes/SPK-1/redacted.py` (fix loop 1): runs a command and redacts its output in memory before writing it.
- `spikes/SPK-1/test_redaction.py`, `test_guard.py` (fix loop 1): local tests with synthetic or empty values, no network.
- `spikes/SPK-1/README.md`: how to run the spike.
- `docs/research/SPK-1-sepolia.md`: the research note.

## Commands run
- `pnpm --dir spikes/SPK-1 install --ignore-workspace` → `+ starknet 10.8.0`, 61 packages from the local store.
- `scripts/lock.sh scarb --manifest-path spikes/SPK-2/native/Scarb.toml build` → `Finished dev profile`.
- `node spikes/SPK-1/probe.mjs` → `"chain":"SN_SEPOLIA","spec":"0.10.2","starknet_version":"0.14.4","account_class":{"sierra":"1.7.0","compiler":"2.11.2"},"strk_balance":305.129714554142`.
- `node spikes/SPK-1/deploy.mjs` (first run) → `TypeError: acc.waitForTransaction is not a function`. The Hub declare had been sent; the fix was to use `provider.waitForTransaction`.
- `node spikes/SPK-1/deploy.mjs` (second run) → the Hub declare found on chain (777,647,155 L2 gas, 16.72 STRK); Instances declared (1,820,714,035 L2 gas, 38.96 STRK); 2 deploys, 2 links, setup_hub, all `SUCCEEDED`; `"transactions":7, "fee_strk":55.947`.
- `node spikes/SPK-1/measure.mjs` → 98 transactions, all `SUCCEEDED`; `"balance_delta_strk":16.273, "strk_balance":232.909`.
- `python3 spikes/SPK-1/latency.py` (first version) → `Both measured sets (70) | 1,265 | 2,774 | 3,019 | 1,017 | 3,764 | 4,517 | 4,765 | 0 missed`. The fourth column was a "lower bound", withdrawn in fix loop 1 (finding 3).
- `python3 spikes/SPK-2/prices.py` → mainnet L2 gas 21,345,234,918 fri, block 15,594,144, 20:49:58Z; STRK $0.04125403 (CoinGecko, 20:50:07Z).
- `python3 spikes/SPK-1/money.py` → `S1 | 158 | 0.874 | 0.925 | 0.945 | 1.75 | 12.15 Gfri`; `S2 | 146 | 0.685 | 0.702 | 0.976 | 1.37 | 15.54 Gfri`; total `105` transactions, `72.2203` STRK.
- `python3 spikes/SPK-1/check_secrets.py` → `checked 20 texts for 3 variables: 0 occurrences`, after redacting one line of `prices-output.txt` (see Deviations).
- `gh pr checks 45 --watch --interval 30` → all 10 checks pass: discover, tooling, client, cairo × 7.

## Cost
| Entrypoint or algorithm | Before (devnet, SPK-2) | After (Sepolia) | Budget | Note |
|---|---:|---:|---:|---|
| Worst tick under D-127, tx L2 gas | 5,156,800 | 5,129,938 | — | 20 identical receipts; 832 L1 data gas on both |
| Queue of 10 moves, 8 goblins | 20,128,000 | 17,676,853 | — | |
| Queue of 5 moves | 11,662,400 | 10,315,319 | — | |
| Queue of 1 move | 5,201,920 | 4,818,251 | — | |
| Exploring queue, 10 moves | 2,248,000 | 2,816,505 | — | |
| Enter | 3,425,280 | 3,927,367 | — | L1 data gas 640 → 768 |
| Leave | 1,576,320 | 2,030,065 | — | |
| Expedition S1 / S2 ($, same prices) | 0.925 / 0.702 | 0.874 / 0.685 | 0.50 | 1.75× / 1.37× |

No Cairo was changed, and no test or budget moved.

## Acceptance criteria
- [x] **AC-1**: `latency-output.txt`, research §2. p50/p95/max of the first positive receipt response to pre-confirmed and to accepted, for the 20 ticks, the 50 enter/leave and all 70, against ADR-0001: p95 met; p50 not decided by this sampling.
- [x] **AC-2**: every measured action's receipt is in `measure-output.txt` (resource bounds, tip, fee, L2 gas, L1 data gas, L1 gas, block prices), with traces for the first of each. The meter applied is Sierra gas; the evidence is in `money-output.txt` and research §3.
- [x] **AC-3**: `money-output.txt` and research §5: S1/S2 on Sepolia beside devnet at the same prices. Verdict stated plainly: $0.50 does not hold (1.37×–1.75×).
- [x] **AC-4**:
  - at measurement time, `check_secrets.py` found 0 occurrences in `git log -p origin/main..HEAD`, `spikes/SPK-1/`, the research note and this report. Fix loop 1 widened it to `git log -p --all` plus the required log and report; it can only run with the real values, so it is the orchestrator's to run (see Fix loop 1, finding 5);
  - `deploy.mjs` and `measure.mjs` call `requireSepolia()` before anything else;
  - 105 transactions and 72.22 STRK are reported in research §7.

## Deviations from the brief
- **Queues of 5 and of 1 move measured too** (2 setups, 2 transactions). SPK-2's S1 and S2 need them, and the brief asks for SPK-2's method.
- **The cheap action is enter and leave, alternating** (25 each). The brief did not name the cheap action; these two are cheap, repeatable and in its list.
- **20 board resets** (`setup_board 31`) run before the 20 ticks, so every tick runs on the same capped board. They are setup transactions, not latency samples. They cost 10.1 STRK in total, more than the measured transactions (6.18 STRK).
- **The first deploy run crashed after sending the Hub declare.** The second run found the declare on chain and counted it; nothing was sent twice. The first run's output is kept as `deploy-output-run1.txt`.
- **One line of `prices-output.txt` was redacted.** The owner's endpoint is a bare public URL that `spikes/SPK-2/prices.py` also polls, so it appeared once in that output.
- **Not measured on Sepolia**, because they are outside the brief's list: goblins packed per instance (S3/S4), the serpentine queue (S5), and hub actions, so there is no cost per day.

## Escalations
- **AC-4 over the full history.** The owner's `STARKNET_RPC_URL` value is identical to one of the public endpoints already committed on `main` in `spikes/SPK-2/prices.py` (and SPK-2's prices outputs). This branch's history (`origin/main..HEAD`) contains no value. A `git log -p` over the whole repository shows that URL, as a public endpoint listed by SPK-2. If the orchestrator treats the endpoint as sensitive, SPK-2's files are outside my allowlist.
- **Decision for the project manager (D-129 #4), on mixed evidence.** The $0.50 threshold fails on Sepolia's receipts (1.37×–1.75×). D-129's reversal condition, "Sepolia figures at or above the local ones", is **not met**:
  - the expeditions are slightly below the local figures (S1 0.945×, S2 0.976×), and so is the worst tick (0.995×);
  - the queues near goblins are below them (0.88×–0.93×);
  - the light actions are above them (exploring queue 1.25×, enter 1.15×, leave 1.29×).
  
  The local node overstated computation and understated each transaction's non-game remainder (observed 1.34M–1.62M L2 gas for this account). The weighing is the project manager's.

## Open questions
1. **p50 to pre-confirmed** is undecided at this sampling. The first positive receipt response came at 1.02–1.27 s from the VPS through one endpoint (160 ms to answer a submission). Is ADR-0001's 1 s target meant at the RPC or at the player? A later run recording [request start, response arrival, status] per poll (now in `lib.mjs`), with finer polling or a WebSocket subscription, would decide it.
2. **The non-game remainder depends on the account class.** 0.6M of it is validation and `__execute__`. SPK-9 should measure it with the MVP's burner class and a paymaster.
3. **`enter`'s first unattributed residual is 1.91M** against 0.25–0.53M for the other actions. It is the only action that writes new storage keys; this is an inference from one case. If confirmed, ENG-01 should reuse instance slots rather than allocate new keys.

## Fix loop 1

This loop answers the `[GPT-6-Astra]` audit of PR 45 (FAIL: four majors, three minors). It ran
**without the Sepolia account**: the variables were empty, and nothing was sent to any network. The
measurements stand unchanged. Redaction was tested with synthetic values only, set inside the
local test scripts.

Commits (new, on the same branch, no force-push):
- `6e5f866`: findings 1, 2 and 5;
- `28924fd`: findings 3, 6 and 7 in the scripts;
- `cdd274c`: the research note and README brought in line.

CI: `gh pr checks 45 --watch --interval 30` → all 10 checks pass (discover, tooling, client, cairo × 7; runs 36484377661 and 36484377649 on `cdd274c`).

### Finding 1 (major): redaction did not cover startup
**Fix.**
- **`lib.mjs` reads nothing at import.** `configure()` checks presence, then checks the address
  and key against `^0x[0-9a-fA-F]{1,64}$` and the URL as http(s). Each refusal names the variable,
  never its value. Only after that does it compute `BigInt` forms, install the redaction and
  create the provider.
- **`check_secrets.py`** validates the same way before `int(value, 16)`.
- **Price collection goes through a new wrapper**, `spikes/SPK-1/redacted.py OUTPUT -- COMMAND`.
  It captures the command's stdout and stderr in memory and redacts both before anything is
  written. SPK-2's files are untouched.
- **The README** now documents that wrapper instead of `prices.py > file`.

**Command:** `python3 spikes/SPK-1/test_redaction.py`

**Real output (excerpt):**
```
PASS probe.mjs (lib.mjs configure), malformed key: exit 2 (expected 2), synthetic value occurrences in stdout+stderr: 0
    stderr: STARKNET_PRIVATE_KEY is not a 0x-prefixed hex felt (value not shown); nothing is sent
PASS probe.mjs (lib.mjs configure), malformed address: exit 2 (expected 2), synthetic value occurrences in stdout+stderr: 0
PASS probe.mjs (lib.mjs configure), malformed URL: exit 2 (expected 2), synthetic value occurrences in stdout+stderr: 0
    stderr: STARKNET_RPC_URL is not an http(s) URL (value not shown); nothing is sent
PASS check_secrets.py, malformed key: exit 2 (expected 2), synthetic value occurrences in stdout+stderr: 0
    stdout: STARKNET_PRIVATE_KEY: not a 0x-prefixed hex felt (value not shown)
PASS check_secrets.py, malformed address: exit 2 ... occurrences in stdout+stderr: 0
PASS check_secrets.py, malformed URL: exit 2 ... occurrences in stdout+stderr: 0
    file: 7 lines, synthetic value occurrences: 0; placeholders: ['<ACCOUNT>', '<KEY>', '<RPC_HOST>', '<STARKNET_RPC_URL>']
PASS redacted.py, well-formed values: exit 0 (expected 0), synthetic value occurrences in stdout+stderr: 0
    file: 6 lines, synthetic value occurrences: 0; placeholders: ['<ACCOUNT>', '<KEY>', '<RPC_HOST>', '<STARKNET_RPC_URL>']
PASS redacted.py, malformed key: exit 0 (expected 0), synthetic value occurrences in stdout+stderr: 0
...
all passed
```
The redaction test's printer emits the URL, its host, the address as padded hex, unpadded hex and
decimal, and the key as hex and decimal (or the malformed key literally), to stdout and stderr.
None of it survives in the file, stdout or stderr.

Two first attempts of the test failed on artifacts of the test itself, not of the tools:
- the well-formed case also printed the malformed-key string, which contains "synthetic", a
  fragment of the synthetic URL;
- the leak counter also counted the `GIT_DIR` path.

Both were fixed in the test; the tools' outputs held no value in either run.

### Finding 2 (major): the documented redirection defeated the repeat-run guard
**Fix.**
- **The scripts write their own output files.** `measure.mjs` and `deploy.mjs` no longer rely on
  `>` redirection.
- **A guard runs first.** `guardOutput()` runs before `configure()` and before any network call,
  and refuses (exit 4) if the output file exists, whether the run finished or not. `deploy.mjs`
  also refuses if `sepolia.json` exists.
- **Exclusive creation.** The file is then created with `openSync(path, "wx")`.
- **Recovery needs a flag.** `--recover-incomplete` keeps an existing file as evidence (renamed
  `*.incomplete-<timestamp>`) and starts again.
- **The README** documents the new commands and warns against `>`.
- **Tests only.** `SPK1_OUT_DIR` lets the tests use a temporary folder.

**Command:** `python3 spikes/SPK-1/test_guard.py`. The `STARKNET_*` variables are forced empty, so
getting past the guard would end in `configure()` with exit 2.

**Real output:**
```
PASS measure.mjs, second invocation on the committed output (sha256 51a794f742287df5 before, 51a794f742287df5 after): exit 4
    measure-output.txt exists: a run has already started (complete or not); nothing is sent. After an incomplete run, pass --recover-incomplete to keep the file (renamed) and start again
PASS measure.mjs, empty output of an incomplete run: exit 4
PASS measure.mjs --recover-incomplete: kept ['measure-output.txt.incomplete-2026-09-28T21-07-36-902Z'], new output created: False: exit 2
    --recover-incomplete: measure-output.txt kept as /tmp/tmpw6k7o4dg/measure-output.txt.incomplete-2026-09-28T21-07-36-902Z
    STARKNET_NETWORK is not set: launch with --with-sepolia; nothing is sent
PASS measure.mjs, fresh folder: past the guard, stopped by configure(): exit 2
PASS deploy.mjs, existing deploy-output.txt: exit 4
PASS deploy.mjs, committed sepolia.json: exit 4
all passed
```
What this shows:
- the refusal of a second invocation comes from the guard (exit 4 and its message), not from the
  empty variables (exit 2);
- the committed measurement is unchanged (same sha256).

### Finding 3 (major): invalid latency lower bounds
**Fix.**
- **`latency.py` no longer reports lower bounds.** It names the metric "first positive receipt
  response" latency and treats the figures as upper bounds.
- **A threshold is only decided outside the sampling uncertainty.** A figure within one poll
  interval plus the median round trip (250 + 160 = 410 ms) above a threshold is "not decided".
- **Future runs record what a bound needs.** `lib.mjs`'s poller now records every poll as
  [request start, response arrival, status]. The status became true after the last negative
  request's start and before the first positive response's arrival.
- **The research note** (§1, §2, summary, open question 1) and this report were rewritten to
  match.

**Command:** `python3 spikes/SPK-1/latency.py > spikes/SPK-1/latency-output.txt`

**Real output (excerpt):**
```
| Worst tick under D-127 (attack) | 20 | 1,020 | 2,770 | 2,781 | 3,529 | 4,267 | 4,514 | 0 | 164 |
| Both measured sets (70) | 70 | 1,265 | 2,774 | 3,019 | 3,764 | 4,517 | 4,765 | 0 | 160 |
  Worst tick under D-127 (attack): p50 1,020 ms, not decided (20 ms above, within the sampling uncertainty); p95 2,770 ms, met (the observed upper bound is within the threshold)
  Cheap action: enter and leave, alternating: p50 1,267 ms, not decided (267 ms above, within the sampling uncertainty); p95 2,774 ms, met (the observed upper bound is within the threshold)
  Both measured sets (70): p50 1,265 ms, not decided (265 ms above, within the sampling uncertainty); p95 2,774 ms, met (the observed upper bound is within the threshold)
```

### Finding 4 (major): D-129's reversal condition declared met
**Fix.** The research note's summary and §5, this report's summary and its escalation now say:
- the $0.50 threshold fails;
- D-129's condition ("at or above the local ones") is **not met**;
- Sepolia is slightly below local on the expeditions (0.945×, 0.976×) and the tick (0.995×), and
  above on the light actions (1.15×–1.29×);
- that mixed evidence goes to the project manager, without a verdict on the condition.

No command: text only (`cdd274c`, and this file).

### Finding 5 (minor): the secret scan
**Fix.** `check_secrets.py` now:
- scans `git log -p --all` and fails on a git error;
- requires `--log` (the agent's log) and the report, and fails if one is missing;
- prints its coverage (every input read, with its size);
- states in its docstring that binary contents are not scanned.

**Command:** `python3 spikes/SPK-1/test_redaction.py`, the last three cases, with synthetic values.

**Real output:**
```
PASS check_secrets.py, values in the log: exit 1 (expected 1), synthetic value occurrences in stdout+stderr: 0
    stdout: FOUND STARKNET_ACCOUNT_ADDRESS in /tmp/tmpw9rus71_/agent.log: 1
    stdout: FOUND STARKNET_PRIVATE_KEY in /tmp/tmpw9rus71_/agent.log: 1
PASS check_secrets.py, missing required inputs: exit 1 (expected 1), synthetic value occurrences in stdout+stderr: 0
PASS check_secrets.py, git fails (GIT_DIR points nowhere): exit 1 (expected 1), synthetic value occurrences in stdout+stderr: 0
    stdout: git log -p --all failed (exit 128): fatal: not a git repository: '/tmp/tmpw9rus71_/no-repo'
```
(In those cases the scan also reports `test_redaction.py` itself, which holds the synthetic
values. That is expected, and the real values are not there.)

**Not run with the real values:** the variables are empty in this loop. With them,
`python3 spikes/SPK-1/check_secrets.py --log <log>` is the orchestrator's to run. Over `--all` it
should report the endpoint's value in SPK-2's committed files on `main`, as escalated above. It is
not in any SPK-1 commit: the one occurrence in `prices-output.txt` was redacted before its first
commit.

### Finding 6 (minor): the "floor" of a transaction
**Fix.**
- **The column is renamed.** `money.py` and the research note §4 call it the "non-game remainder"
  (receipt minus game call), observed for these actions and this account, and not a universal
  floor.
- **The residuals are labelled as unattributed**: "trace total minus invocations" and "receipt
  minus trace total", the latter expected to be calldata, signature and events, not verified.
- **The derived budget is qualified.** A game call averaging at most 516,497 L2 gas under equal
  allocation holds only for this account class and transactions like these.

**Command:** `python3 spikes/SPK-1/money.py > spikes/SPK-1/money-output.txt`

**Real output (last line):**
```
Equal-allocation reference: $0.50 / 300 = $0.001667 per action = 1,854,492 L2 gas with 832 L1 data gas (zero tip). Observed non-game remainder, for these actions and this account only: 1,337,995 to 3,000,155 L2 gas (0.72× to 1.62× the reference). If every transaction carried at least the smallest observed remainder, the game's own call could average at most 516,497 L2 gas under equal allocation. That derived budget holds only for this account class and transactions like these, not as a protocol floor.
```

### Finding 7 (minor): the tip
**Fix.**
- **The formula is checked on every receipt.** `money.py` checks actual fee = L2 gas × (block L2
  price + tip) + L1 data gas × data price + L1 gas × L1 price.
- **The zero-tip assumption is stated** for the projections, and the tip's effect is computed.
- **The research note** (§5 and summary) and this report say the same.

**Command:** the same `money.py` run.

**Real output:**
```
Fee formula with the tip: actual fee = L2 gas × (block L2 price + tip) + L1 data gas × data price + L1 gas × L1 price. It reproduces the fee to the fri on 103 of 103 invoke receipts. The tip was 0.1 Gfri per L2 gas (starknet.js recommended); it cost 0.0766 STRK of the run's fees.
The dollar projections above assume a ZERO tip at mainnet prices. At the tip this run paid (0.1 Gfri):
| S1 worst case everywhere | 986,667,736 | 0.874 | +0.0041 | 0.878 |
| S2 mixed (2/3 of the moves exploring) | 772,898,140 | 0.685 | +0.0032 | 0.688 |
```
The money figures are otherwise unchanged: S1 $0.874, S2 $0.685, 105 transactions, 72.2203 STRK.
