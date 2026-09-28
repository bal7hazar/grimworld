> **Closed (2026-09-28): sending is retired.** The measurements are done and audited; the
> sending scripts refuse as their first statement (audit of PR 51, findings 1 and 7, on their
> crash-recovery path). Read-only scripts (`analyse.py`, the probes) still run.

# SPK-1b — the fixed part of a transaction, with the MVP's kind of account

The same cheap action as SPK-1 (`enter` then `leave`) on SPK-1's deployed contracts, sent four
ways: from the owner's account (the reference), by an OpenZeppelin burner directly, by the burner
through a relayer of our own (SNIP-9), and by the burner through AVNU's public SNIP-29 paymaster.
The findings are in `docs/research/SPK-1b-fixed-part.md`.

`lib.mjs` is SPK-1's, copied with its safety unchanged: variables by name only, the chain-id guard,
the redaction, the send cap, the repeat-run guard. Added to it:
- `redactAlso`, which adds the burner's key to the redaction;
- `makeLedger` and `tracked`, the brief's caps over every script (60 transactions, 40 STRK of the
  owner's money), kept in `ledger.jsonl`. Since fix loop 1:
  - every transaction is reserved before it is submitted, its hash written as soon as it is known,
    then settled with the receipt's fee and the owner's spending apart;
  - an unresolved entry blocks every send until `reconcile`;
- `excerpt`, which redacts a text whole before cutting it (fix loop 1);
- the full invocation tree in the trace.

| File | What |
|---|---|
| `classes.mjs` | Read only: account classes declared on Sepolia, their versions and SNIP-9 support |
| `class-at.mjs` | Read only: the class of a contract (AVNU's relayers and forwarder) |
| `measure.mjs` → `measure-output.txt` | The run: A, the burner's funding and deployment, B, C, and D until it stopped (35 transactions) |
| `measure-d.mjs` → `measure-d-output.txt` | The rest of D, then the adventurer given back and the burner's STRK returned (9 transactions). It resumes from what the outputs record. `*.incomplete-*` are its earlier attempts, kept |
| `ledger.jsonl` | Every transaction sent (44): reservation, hash, settlement (receipt fee and the owner's spending apart). Rewritten from `ledger-v1.jsonl` (the run's own, one row per receipt) by `migrate_ledger.py` |
| `test_ledger.mjs` | Offline, with a stubbed RPC: failures after the broadcast, while reading the receipt and while tracing, and before any hash; recovery and reconciliation; paymaster settlement; the committed ledger |
| `analyse.py` → `analyse-output.txt` | The table: SPK-1 §4's attribution per case, the splits, the money |
| `summary.py`, `tree.py`, `selectors.json` | One line per receipt; one trace's invocation tree with entry point names |
| `check_secrets.py` | AC-3: SPK-1's check, which also covers the burner key and checks that its file is ignored and untracked. It validates the burner inventory and requires the expected burner |
| `test_check_secrets.py` | Inventories that must fail (empty, missing burner, bad fields, not a felt, zero, not JSON), a leak and a tracked key file, in a throwaway repository with synthetic values |
| `test_redaction.mjs` | The burner key's redaction, and every protected value across a cut, with synthetic values only |

The burner's key lives in `burners.secret.json`: ignored by git, mode 0600, never printed.

From the repository root, in a session launched with `--with-sepolia`:

```
pnpm --dir spikes/SPK-1b install --ignore-workspace
node spikes/SPK-1b/measure.mjs          # writes measure-output.txt; refuses if it exists
node spikes/SPK-1b/measure-d.mjs        # writes measure-d-output.txt; refuses if it exists
python3 spikes/SPK-1b/analyse.py > spikes/SPK-1b/analyse-output.txt
python3 spikes/SPK-1b/check_secrets.py --log <agent log>
node spikes/SPK-1b/test_redaction.mjs && node spikes/SPK-1b/test_ledger.mjs && python3 spikes/SPK-1b/test_check_secrets.py   # no network
```

Never redirect the output of the sending scripts with `>`. The balance is the owner's money.
