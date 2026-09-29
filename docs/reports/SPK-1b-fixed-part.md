# [Opus 5.5] SPK-1b — The fixed part of a transaction, with the MVP's kind of account

## Summary
The session ran as Claude Opus 5.5 (`claude-opus-5-5`), the model the brief names.

New in this task: `spikes/SPK-1b/` and `docs/research/SPK-1b-fixed-part.md`. Four cases were
measured on Sepolia on 2026-09-28, 10 transactions each (5 × `enter`, `leave`), on SPK-1's
deployed contracts, every transaction traced:

- **A**, the owner's account: reproduces SPK-1 to the unit.
- **B**, an OpenZeppelin `AccountUpgradeable` v3.0.0 burner sending directly. Its class
  `0x01d1777db36cdd06dd62cfde77b1b6ae06412af95d57a13dc40ac77b8a702381` (Cairo 2.13.1, SNIP-9 v2)
  was already declared on Sepolia.
- **C**, the burner through a relayer of our own: SNIP-9, with the owner's account paying.
- **D**, the burner through AVNU's public SNIP-29 paymaster, which needed no key (default fee mode).

**Verdict: D-133's reversal condition is not met.**
- The burner's fixed part is 717,435 L2 gas against 1,087,585 for the owner's account: 1.5×
  smaller. Its non-game remainder on `leave` is 977,915 against 1,348,065: 1.38× smaller.
- The measured verdict is 1.52×. Beyond it, an estimate: the fee transfer (455,360) is paid
  whatever the account, so an account costing nothing would reach about 2.23× (2.39× holding only
  the fee transfer). The assumptions are stated in note §1 and §5 (fix loop 1).
- Paymasters make it larger: C is 1.77× the reference, D is 3.35×.
- **Recommended on cost:** the OZ burner sending directly, with no paymaster in the path of play.
- A minimal burner was not justified (at best about 160k saved), so none was written or declared.

Pull request: https://github.com/bal7hazar/grimworld/pull/51 (CI green; not merged).

## Files changed
- `spikes/SPK-1b/lib.mjs`: SPK-1's lib copied, its safety unchanged. Added `redactAlso` (burner
  key), `makeBudget` (60 transactions and 40 STRK over every script, `ledger.jsonl`), `maxFee`, the
  invocation tree in traces, and an exported `poll`.
- `spikes/SPK-1b/measure.mjs`: the run (A, funding, deploy, B, C, D); 35 transactions before it stopped.
- `spikes/SPK-1b/measure-d.mjs`: the rest of D, resumed from the recorded outputs; the adventurer given back; the burner's STRK returned.
- `spikes/SPK-1b/measure-output.txt`, `measure-d-output.txt`, `measure-d-output.txt.incomplete-*`: receipts and traces, redacted; the incomplete attempts are kept.
- `spikes/SPK-1b/ledger.jsonl`: every transaction sent (44).
- `spikes/SPK-1b/analyse.py` → `analyse-output.txt`: the table, the splits, the money.
- `spikes/SPK-1b/classes.mjs`, `class-at.mjs`: read-only probes of account classes.
- `spikes/SPK-1b/summary.py`, `tree.py`, `selectors.json`: reading aids.
- `spikes/SPK-1b/check_secrets.py`: SPK-1's check, adapted. It also covers the burner key,
  checks that its file is ignored and untracked, and adds `--range` and `--by-commit`.
- `spikes/SPK-1b/test_redaction.mjs`: the burner-key redaction, with synthetic values.
- `spikes/SPK-1b/README.md`, `.gitignore`, `package.json`, `pnpm-lock.yaml`: as SPK-1's; the burner key file is ignored.
- `docs/research/SPK-1b-fixed-part.md`: the note.

## Commands run
- `node spikes/SPK-1b/classes.mjs <hashes>` (read only). Declared on Sepolia with SNIP-9 v2:
  - OZ v0.20.0 `0x02b31e19…` (Cairo 2.9.1);
  - OZ v1.0.0 `0x05b4b537…` (2.9.4);
  - OZ v2.0.0 `0x07fa9379…` (2.11.4);
  - OZ v3.0.0 `0x01d1777d…` (2.13.1).

  OZ v4.0.0 `0x0342f3c6…` is not declared. The owner's class `0x3957f9f5…` is Braavos. OZ
  hashes per release are from each tag's `docs/.../utils/_class_hashes.adoc`.
- `curl … paymaster_isAvailable` to `https://sepolia.paymaster.avnu.fi`, with no key: `true`.
- `node spikes/SPK-1b/measure.mjs` stopped after 35 transactions (exit 1). AVNU's
  `paymaster_buildTransaction` answered "not the owner" for the second D `leave`: its simulation
  did not yet see the `enter` accepted a block earlier. Nothing was sent for it.
- `node spikes/SPK-1b/measure-d.mjs` stopped on a script error (it picked a log line instead of
  the receipt) before any send.
- `node spikes/SPK-1b/measure-d.mjs --recover-incomplete` sent 1 `leave`. It then stopped
  client-side on "Gas token price is too high": the paymaster's second quote was above the first,
  so nothing was signed.
- `node spikes/SPK-1b/measure-d.mjs --recover-incomplete` finished with exit 0: 8 transactions,
  the ledger at 44 transactions and 3.6938 STRK. One build refusal was retried after 3 s.
- `python3 spikes/SPK-1b/analyse.py > spikes/SPK-1b/analyse-output.txt` (`leave`, L2 gas):
  - A: receipt 2,030,065, remainder 1,348,065, fixed part 1,087,585;
  - B: 1,659,915 / 977,915 / 717,435;
  - C: 3,068,685 / 2,386,685 / 1,587,885;
  - D: 5,174,800 / 4,514,320 / 3,654,080. One D variant: 4,274,320 (validate 320,000).
- `node spikes/SPK-1b/class-at.mjs …`: AVNU's relayers are class `0x1a736d6e…`, Sierra 1.2.0,
  compiler 2.0.0; its forwarder is Sierra 1.7.0, compiler 2.16.0.
- `node spikes/SPK-1b/test_redaction.mjs`: all passed (4 forms redacted; a malformed key is
  refused without its value).
- `python3 spikes/SPK-1b/check_secrets.py --log …/logs/SPK-1b.log --by-commit` (over `--all`):
  10 occurrences of `STARKNET_RPC_URL`, all in commit `bdc0b57` (SPK-2, #25, on `origin/main`),
  in `spikes/SPK-2/prices*.txt` and `prices.py`. SPK-1's note predicted this.
- `python3 spikes/SPK-1b/check_secrets.py --log …/logs/SPK-1b.log --range origin/main..HEAD`:
  `checked 24 texts for 4 variables: 0 occurrences; 0 required inputs missing`. It was run again
  with this report as `--report`: see AC-3.
- `gh pr checks 51 --watch --interval 30`: all 10 checks pass.

## Cost
| Entrypoint or algorithm | Before | After | Budget | Note |
|---|---|---|---|---|
| — | — | — | — | No Cairo in this task |

Sepolia:
- **44 transactions** (cap 60), planned before sending. None was repeated.
- **Receipt fees: 3.6938 STRK.** AVNU's relayers paid 1.3629 of it.
- **The owner's money spent: 3.9654 STRK** (cap 40): the receipts the owner and the burner paid,
  plus 1.6346 STRK the burner paid AVNU.
- The burner still holds 0.0988 STRK.

## Acceptance criteria
- **AC-1**: `docs/research/SPK-1b-fixed-part.md` §3, from `analyse-output.txt`, with receipts and
  traces in `measure-output.txt` and `measure-d-output.txt`. It gives the non-game remainder of
  each case (validate, the account's execution, fee transfer, game call, both residuals, and the
  difference from 1.09M with its reasons in §4), beside A measured again the same day: identical
  to SPK-1.
- **AC-2**: note §1 and §5. The reversal condition is not met, stated plainly. On cost, the MVP's
  account is the OZ `AccountUpgradeable` v3.0.0 burner sending directly, with no paymaster in the
  path of play.
- **AC-3**:
  - `check_secrets.py`, adapted to the burner key, finds 0 occurrences in `origin/main..HEAD`,
    the spike folder, the note, this report and the log. It also confirms the key file is ignored
    and untracked.
  - `requireSepolia()` runs before any send in `measure.mjs` and `measure-d.mjs`.
  - The count (44) and the cost (3.69 STRK in receipts, 3.97 STRK of the owner's money) are in
    note §6 and here.

## Deviations from the brief
- **Case D was added**, as the brief allows: AVNU's public paymaster needed no account or key. It
  also cost the owner's money, via the burner's payment to AVNU.
- **The minimal burner was not written**: the numbers do not justify it (note §5).
- **The owner's account called `setup_hub(burner)`** so the burner could play adventurer 3, then
  `setup_hub(owner)` to give it back. These are state writes through an existing admin entrypoint,
  not a change to the deployed contracts; I took that as within scope.
- **The run was split in two scripts.** `measure-d.mjs` resumed case D after the first script
  stopped, within the same plan of 44.

## Escalations
None.

## Open questions
1. AVNU's sponsored mode, and any paymaster with a modern relayer class, were not measured: the
   first needs a key. D's relayer class, Sierra 1.2.0, appears to meter the whole transaction by
   steps (round figures; the game call is 3% lower). That is an inference.
2. The first residual rises by 538,320 on `leave` through an outside execution. It is attributed
   to the SNIP-9 nonce's new storage key by inference, as `enter`'s was in SPK-1.
3. Whether OZ v3.0.0's class hash is declared on mainnet was not checked.

## Fix loop 1

The [GPT-6-Astra] audit found three majors and three minors. This session ran **without the
Sepolia account**: nothing was sent to any network, the measurements stand, and every test uses
offline stubs and synthetic values. Commits on the same branch, no force-push:
- `43ef555`: majors 1 and 2;
- `f10070e`: major 3;
- `67d1a80` and `5bf6ce3`: minor 5 (the second untracks a `__pycache__` the first had committed);
- `177efc5`: minors 4 and 6.

### 1 (major): the ledger counted a transaction only after its receipt and trace
- **Fix** (`lib.mjs`: `makeLedger`, `tracked`, `makeSender`, `receiptOrNull`):
  - A transaction is **reserved** in `ledger.jsonl` before `submit()`: one slot and its maximum
    cost. Its **hash** is written as soon as `submit()` returns, before any receipt is asked for,
    and it is **settled** after the receipt.
  - An entry reserved and neither settled, voided nor kept is **unresolved**. It counts at its
    maximum, and `reserve` refuses everything while one exists.
  - `reconcile` must run first:
    - with a hash, it settles the entry from the receipt, or leaves it unresolved while the
      receipt cannot be read;
    - without a hash, it voids the entry if the payer's nonce did not move past the reserved one,
      and otherwise keeps it at its maximum;
    - a paymaster entry without a hash is kept.
  - `measure.mjs` and `measure-d.mjs` reconcile before sending anything, and stop if anything
    stays unresolved.
- **Test**: `node spikes/SPK-1b/test_ledger.mjs`, offline. A stubbed `fetch` stands in for the
  RPC, and a stub account counts broadcasts; the real sender, poll, describe and ledger run.
  ```
  ok   1a the send fails after its broadcast
  ok   1b the broadcast is counted: 60 transactions
  ok   1c its hash is in the ledger, unresolved
  ok   1d it counts at its maximum fee (100 × 10 fri)
  ok   1e a second send is refused before any broadcast
  ok   1f the hash was written before the receipt was asked for
  ok   2a a new run refuses to reserve while the entry is unresolved
  ok   2b reconcile while the receipt cannot be read: still unresolved
  ok   2c reconcile once the receipt is there: settled at the receipt's fee
  ok   2d the cap still holds: 60 transactions, the next is refused
  ok   2e broadcasts over the whole scenario: 1
  ok   3a the send fails while collecting the trace
  ok   3b unresolved with its hash
  ok   3c reconcile cannot settle while the trace fails
  ok   3d reconcile settles once it can
  ok   4a nonce unchanged: void (blocked before reconcile, then void)
  ok   4b nonce moved: kept at its maximum (blocked before reconcile, then kept)
  ```
  Case 1 is the auditor's fault: a ledger at 59 entries and a failure after the broadcast. It now
  gives exactly one broadcast, and the second send is refused before `execute`.

### 2 (major): the spending cap added AVNU's receipt fee, not what the burner paid
- **Fix**:
  - The ledger keeps the **receipt's fee** (whoever paid it) and **the owner's money spent** apart.
    The cap is 40 STRK of spending, with unresolved entries counted at their maximum.
  - A paymaster reservation is settled against **the payer's net STRK transfers in the receipt**
    (`netTransfer`: what the burner sent minus AVNU's refund). If none can be read, the
    reservation is kept as the spending.
  - The run's ledger was rewritten into this format by `migrate_ledger.py`; the original is kept as
    `ledger-v1.jsonl`. For each of the 10 AVNU transactions, the net transfers read from the
    receipt must equal the balance change measured in the run, or the migration stops.
- **Commands and output**:
  ```
  $ python3 spikes/SPK-1b/migrate_ledger.py
  44 transactions migrated; receipt fees 3.6938 STRK; the owner's money spent 3.9654 STRK (AVNU receipts 1.3629 replaced by the burner's payments 1.6346)
  $ node spikes/SPK-1b/test_ledger.mjs   (continued)
  ok   5a settled: receipt fee 50 (the relayer's), spent 300 (700 sent, 400 refunded)
  ok   5b the totals keep them apart
  ok   5c the spending cap counts the burner's payment, not the receipt fee: 300 + 750 > 1000 is refused
  ok   5d no transfer from the burner in the receipt: the reservation (600) is kept as the spending
  ok   6 the committed ledger: 44 transactions, fees 3.6938 STRK, spent 3.9654 STRK, 0 unresolved
  all passed
  ```

### 3 (major): errors were cut before redaction
- **Fix**: `excerpt(value, n)` redacts the whole text, then cuts it. It is used by `rpcRaw`
  (non-JSON answers, previously `text.slice(0, 300)` inside `safe`) and by `measure-d.mjs`'s
  build-refusal line (previously `String(...).slice(0, 200)` before `emit`).
- **Test**: `node spikes/SPK-1b/test_redaction.mjs`. Every protected value, in each of its forms,
  is put across the cut at every offset from 4 characters. It goes through `excerpt` and through
  `rpcRaw` with a stubbed non-JSON answer. The old order (cut, then redact) runs on the same inputs
  to show the test catches the leak. A static check also finds no script cutting an error or a
  response before redaction.
  ```
  ok   boundary STARKNET_RPC_URL: 54 cuts, 0 leak through excerpt, 0 through rpcRaw (cut-then-redact would leak 38)
  ok   boundary STARKNET_ACCOUNT_ADDRESS: 70 cuts, 0 leak through excerpt, 0 through rpcRaw (cut-then-redact would leak 70)
  ok   boundary STARKNET_PRIVATE_KEY: 70 cuts, 0 leak through excerpt, 0 through rpcRaw (cut-then-redact would leak 70)
  ok   boundary BURNER_KEY: 85 cuts, 0 leak through excerpt, 0 through rpcRaw (cut-then-redact would leak 85)
  ok   boundary: the four protected values were covered
  ok   no script cuts an error or a response before redaction (none)
  all passed
  ```

### 4 (minor): the 2.2× floor and the 160,000 saving are estimates
- **Fix** (note §1 and §5, `analyse.py`):
  - The verdict rests on the measured **1.52×** (fixed part) and **1.38×** (remainder).
  - The rest are called **estimates**, with their assumptions stated: the fee transfer does not
    depend on the account; the first residual stays as in B; the second residual is unattributed
    and varies (A 32,600, B 32,600, C 26,600, D 0).
  - The figures:
    - with the second residual as in B: 487,960, which A's fixed part is **2.23×**;
    - holding only the fee transfer: **2.39×**;
    - a minimal burner, if it cost what OZ's `is_valid_signature` costs (67,765: an OZ figure, not
      a lower bound), would save **161,710**: 17% of B's remainder (the note said 16% before: a
      rounding error) and 10% of its receipt; at zero cost, 229,475 (23%).
- **Output** (`python3 spikes/SPK-1b/analyse.py > spikes/SPK-1b/analyse-output.txt`):
  ```
  The measured verdict: A's account's fixed part is 1.52× B's; A's non-game remainder is 1.38× B's (leave).
  ESTIMATES, not measurements (fix loop 1): what no account would remove, on leave. Assumptions: the fee transfer (455,360) is the STRK token's, whatever the account; the first residual stays as in B (260,480); the second residual is UNATTRIBUTED and varies (A 32,600, B 32,600, C 26,600, D 0).
  - An account costing nothing to validate and execute, the second residual as in B: fixed part 487,960; A's is 2.23× it
  - The same, holding only the fee transfer (the optimistic case): 455,360; A's is 2.39× it
  - The non-game remainder of leave with such an account: 748,440; A's (1,348,065) is 1.80× it
  - A minimal burner: the OZ burner's validation and own execution are 229,475. If a minimal account cost what OZ's is_valid_signature costs (67,765: an OZ figure, not a lower bound), it would save 161,710 (17% of B's remainder, 10% of its receipt); at zero cost, 229,475 at most (23% of the remainder)
  ```

### 5 (minor): `check_secrets.py` passed with an empty burner inventory
- **Fix**: the inventory must be a JSON object that holds the expected burner (`oz`). Each entry
  must be exactly `{"private_key": a nonzero felt}`. Anything else fails with exit 2 and a
  value-free message; a JSON parse error does not echo the content.
- **Test**: `python3 spikes/SPK-1b/test_check_secrets.py` runs in a throwaway git repository with
  synthetic values. Against the new check:
  ```
  ok   a valid inventory, nothing leaked: exit 0 (expected 0), key not shown
  ok   an empty inventory: exit 2 (expected 2), key not shown
  ok   the expected burner missing: exit 2 (expected 2), key not shown
  ok   an entry without private_key: exit 2 (expected 2), key not shown
  ok   an entry with an extra field: exit 2 (expected 2), key not shown
  ok   a key that is not a felt: exit 2 (expected 2), key not shown
  ok   a zero key: exit 2 (expected 2), key not shown
  ok   a list, not an object: exit 2 (expected 2), key not shown
  ok   not JSON: exit 2 (expected 2), key not shown
  ok   a valid inventory, the key leaked in the spike folder: exit 1 (expected 1), key not shown
  ok   a valid inventory, the key file tracked by git: exit 1 (expected 1), key not shown
  all passed
  ```
  The same cases against the check before the fix (`python3 spikes/SPK-1b/test_check_secrets.py
  <the previous check_secrets.py>`) give `7 failed`. That includes `an empty inventory: exit 0
  (expected 2)`, the auditor's finding.

### 6 (minor): the measured differences, and D's variant
- **Fix**:
  - Note §4 now gives the differences against A measured today: **−370,150** for B, +500,300 for
    C and +2,566,495 for D. `analyse-output.txt` prints them beside those against SPK-1's rounded
    1.09M (−372,565, +497,885, +2,564,080).
  - Note §3: D's differing `leave` saves **240,000 = 80,000 less validation + 160,000 less first
    residual**.
- **Output**:
  ```
  - B burner direct: remainder 977,915 = 0.73× A's; account's fixed part 717,435 = 0.66× A's (1,087,585), A's is 1.52× it; difference from A measured today: -370,150 (from SPK-1's rounded 1.09M: -372,565)
  The D leave that differs (0x34ee11cbc6…): 240,000 less remainder = 80,000 less validation + 160,000 less first residual (+ 0 elsewhere)
  ```

### Secrets, and the CI
- `check_secrets.py` cannot run in this session: the account's variables are empty. It exits with
  `STARKNET_RPC_URL: not set`, as designed.
- The burner key is still in the worktree's ignored file. I scanned for it alone (hex and decimal
  forms) over `git log -p origin/main..HEAD`, the spike folder, the note, this report and the log:
  `burner key: 0 occurrences in 29 texts`. The new files hold synthetic values only.
- `gh pr checks 51 --watch --interval 30`: all 11 checks pass (the 10 before plus `cairo
  (spikes/SPK-7)`, which is new on main).

### Not changed
- The measurements, the verdict and the recommendation are unchanged.
- `measure.mjs` and `measure-d.mjs` were moved onto the fixed ledger but not run again: their
  output guards refuse, and this session has no account. Only the offline tests exercise the new
  path.
- The PR description still says "at most 2.2× smaller"; the note and this report supersede it.
