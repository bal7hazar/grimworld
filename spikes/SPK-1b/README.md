# SPK-1b — the fixed part of a transaction, with the MVP's kind of account

The same cheap action as SPK-1 (`enter` then `leave`) on SPK-1's deployed contracts, sent four
ways: from the owner's account (the reference), by an OpenZeppelin burner directly, by the burner
through a relayer of our own (SNIP-9), and by the burner through AVNU's public SNIP-29 paymaster.
The findings are in `docs/research/SPK-1b-fixed-part.md`.

`lib.mjs` is SPK-1's, copied with its safety unchanged: variables by name only, the chain-id guard,
the redaction, the send cap, the repeat-run guard. Added to it:
- `redactAlso`, which adds the burner's key to the redaction;
- `makeBudget`, the brief's caps over every script (60 transactions, 40 STRK), kept in `ledger.jsonl`;
- the full invocation tree in the trace.

| File | What |
|---|---|
| `classes.mjs` | Read only: account classes declared on Sepolia, their versions and SNIP-9 support |
| `class-at.mjs` | Read only: the class of a contract (AVNU's relayers and forwarder) |
| `measure.mjs` → `measure-output.txt` | The run: A, the burner's funding and deployment, B, C, and D until it stopped (35 transactions) |
| `measure-d.mjs` → `measure-d-output.txt` | The rest of D, then the adventurer given back and the burner's STRK returned (9 transactions). It resumes from what the outputs record. `*.incomplete-*` are its earlier attempts, kept |
| `ledger.jsonl` | Every transaction sent: hash, label, type, fee (44) |
| `analyse.py` → `analyse-output.txt` | The table: SPK-1 §4's attribution per case, the splits, the money |
| `summary.py`, `tree.py`, `selectors.json` | One line per receipt; one trace's invocation tree with entry point names |
| `check_secrets.py` | AC-3: SPK-1's check, which also covers the burner key and checks that its file is ignored and untracked |
| `test_redaction.mjs` | The burner key's redaction, with synthetic values only |

The burner's key lives in `burners.secret.json`: ignored by git, mode 0600, never printed.

From the repository root, in a session launched with `--with-sepolia`:

```
pnpm --dir spikes/SPK-1b install --ignore-workspace
node spikes/SPK-1b/measure.mjs          # writes measure-output.txt; refuses if it exists
node spikes/SPK-1b/measure-d.mjs        # writes measure-d-output.txt; refuses if it exists
python3 spikes/SPK-1b/analyse.py > spikes/SPK-1b/analyse-output.txt
python3 spikes/SPK-1b/check_secrets.py --log <agent log>
node spikes/SPK-1b/test_redaction.mjs   # no network
```

Never redirect the output of the sending scripts with `>`. The balance is the owner's money.
