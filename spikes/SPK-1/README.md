# SPK-1 — latency and cost on Sepolia

SPK-2's native contracts (`spikes/SPK-2/native/`, unchanged) run on Sepolia, from the owner's
Sepolia account. The findings are in `docs/research/SPK-1-sepolia.md`.

The scripts use starknet.js 10.8.0, installed here only (`node_modules/` is ignored). The account
comes as four variables, used **by name only**: `STARKNET_NETWORK`, `STARKNET_RPC_URL`,
`STARKNET_ACCOUNT_ADDRESS`, `STARKNET_PRIVATE_KEY`.
- `lib.mjs` redacts the endpoint, the address and the key from every output and every error.
- Every script that sends a transaction first calls `requireSepolia()`, which stops unless the
  RPC answers `SN_SEPOLIA`.
- Every request carries a usual `User-Agent`.

| File | What |
|---|---|
| `lib.mjs` | Shared module: variables, redaction, chain-id guard, RPC, and the sender. The sender tracks its own nonce, has a hard cap on transactions, polls receipts every 250 ms, and stops on any revert |
| `probe.mjs` → `probe-output.txt` | Read only: chain, spec, prices, the account's class, balance, tip |
| `deploy.mjs` → `deploy-output.txt`, `sepolia.json` | Declares and deploys Hub and Instances, links them, sets up the hub: 7 transactions. `deploy-output-run1.txt` is the first run, which stopped after sending the Hub declare; the second run found that declare on chain and counted it |
| `measure.mjs` → `measure-output.txt` | The measured run: 98 transactions, one JSON line each (receipt, transaction as signed, block prices, latency, traces) |
| `latency.py` → `latency-output.txt` | p50, p95 and max to pre-confirmed and to accepted on L2 |
| `prices-output.txt` | `spikes/SPK-2/prices.py`, unchanged. Its line for the owner's endpoint is redacted |
| `money.py` → `money-output.txt` | SPK-2's money method on Sepolia's receipts, side by side with devnet's. Also the meter and the fixed part of a transaction |
| `check_secrets.py` | AC-4: counts occurrences of the variables' values in the branch's history, this folder, the research note and the report. It prints only counts |

From the repository root, in a session launched with `--with-sepolia`:

```
pnpm --dir spikes/SPK-1 install --ignore-workspace
scripts/lock.sh scarb --manifest-path spikes/SPK-2/native/Scarb.toml build
node spikes/SPK-1/probe.mjs > spikes/SPK-1/probe-output.txt
node spikes/SPK-1/deploy.mjs > spikes/SPK-1/deploy-output.txt      # refuses if sepolia.json exists
node spikes/SPK-1/measure.mjs > spikes/SPK-1/measure-output.txt    # refuses if the output is not empty
python3 spikes/SPK-1/latency.py > spikes/SPK-1/latency-output.txt
python3 spikes/SPK-2/prices.py > spikes/SPK-1/prices-output.txt    # then redact the owner's endpoint line
python3 spikes/SPK-1/money.py > spikes/SPK-1/money-output.txt
python3 spikes/SPK-1/check_secrets.py
```

The deploy and measure scripts refuse to run twice: the balance is the owner's money.
