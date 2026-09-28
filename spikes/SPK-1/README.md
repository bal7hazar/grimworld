# SPK-1 — latency and cost on Sepolia

SPK-2's native contracts (`spikes/SPK-2/native/`, unchanged) run on Sepolia, from the owner's
Sepolia account. The findings are in `docs/research/SPK-1-sepolia.md`.

The scripts use starknet.js 10.8.0, installed here only (`node_modules/` is ignored). The account
comes as four variables, used **by name only**: `STARKNET_NETWORK`, `STARKNET_RPC_URL`,
`STARKNET_ACCOUNT_ADDRESS`, `STARKNET_PRIVATE_KEY`.
- **Validation before anything can echo a value.** `lib.mjs` reads nothing at import. A script
  calls `configure()`, which checks the variables with errors that never contain a value (a
  malformed key, address or URL is named, not shown). Only then does it install the redaction of
  the endpoint, the address and the key on every console output and every error.
- **The chain id first.** Every script that sends a transaction calls `requireSepolia()` before
  anything else on the network, and stops unless the RPC answers `SN_SEPOLIA`.
- **A usual `User-Agent`** on every request.
- **No second run.** The sending scripts write their own output file, created exclusively (no
  shell redirection). A repeat-run guard runs before `configure()` and before any network call:
  if the output file exists, whether the run finished or not, the script refuses.
  `--recover-incomplete` keeps an incomplete file (renamed with a timestamp) and starts again.

| File | What |
|---|---|
| `lib.mjs` | Shared module: variables, redaction, chain-id guard, RPC, and the sender. The sender tracks its own nonce, has a hard cap on transactions, polls receipts every 250 ms, and stops on any revert |
| `probe.mjs` → `probe-output.txt` | Read only: chain, spec, prices, the account's class, balance, tip |
| `deploy.mjs` → `deploy-output.txt`, `sepolia.json` | Declares and deploys Hub and Instances, links them, sets up the hub: 7 transactions. `deploy-output-run1.txt` is the first run, which stopped after sending the Hub declare; the second run found that declare on chain and counted it |
| `measure.mjs` → `measure-output.txt` | The measured run: 98 transactions, one JSON line each (receipt, transaction as signed, block prices, latency, traces) |
| `latency.py` → `latency-output.txt` | p50, p95 and max to pre-confirmed and to accepted on L2 |
| `redacted.py` → `prices-output.txt` | Runs `spikes/SPK-2/prices.py` (unchanged) and redacts its stdout and stderr in memory before writing anything. The committed `prices-output.txt` predates the wrapper: it was redacted by hand after being written (fix loop 1) |
| `money.py` → `money-output.txt` | SPK-2's money method on Sepolia's receipts, side by side with devnet's. Also the meter, the non-game remainder of a transaction, and the tip |
| `check_secrets.py` | AC-4. Counts occurrences of the variables' values in `git log -p --all`, this folder, the research note, the report and the agent's log (`--log`, required). It prints only counts and its coverage, and fails on a git error or a missing required input |
| `test_redaction.py` | Synthetic values only. Malformed values give value-free errors, `redacted.py` leaks nothing, and `check_secrets.py` detects values, missing inputs and git failures |
| `test_guard.py` | Empty variables. The repeat-run guards refuse (exit 4) before `configure()` would (exit 2) |

From the repository root, in a session launched with `--with-sepolia`:

```
pnpm --dir spikes/SPK-1 install --ignore-workspace
scripts/lock.sh scarb --manifest-path spikes/SPK-2/native/Scarb.toml build
node spikes/SPK-1/probe.mjs > spikes/SPK-1/probe-output.txt
node spikes/SPK-1/deploy.mjs      # writes deploy-output.txt and sepolia.json; refuses if either exists
node spikes/SPK-1/measure.mjs     # writes measure-output.txt; refuses if it exists
python3 spikes/SPK-1/latency.py > spikes/SPK-1/latency-output.txt
python3 spikes/SPK-1/redacted.py spikes/SPK-1/prices-output.txt -- python3 spikes/SPK-2/prices.py
python3 spikes/SPK-1/money.py > spikes/SPK-1/money-output.txt
python3 spikes/SPK-1/check_secrets.py --log <agent log>
python3 spikes/SPK-1/test_redaction.py && python3 spikes/SPK-1/test_guard.py   # no network
```

Never redirect the output of `deploy.mjs` or `measure.mjs` with `>`. The shell would create or
truncate the file before Node starts, and the guard would then see a started run. The balance is
the owner's money.
