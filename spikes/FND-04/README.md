# FND-04 — the slots our transactions change, and the budgets

Reads only. No account, no key, no transaction on Sepolia; nothing here can send one.
Results: [docs/research/FND-04-slots.md](../../docs/research/FND-04-slots.md) and
[docs/architecture/cost-budget.md](../../docs/architecture/cost-budget.md).

| File | What it is |
|---|---|
| `rpc.py` | A JSON-RPC client that refuses every method outside an explicit list of read methods, with a usual `User-Agent` |
| `trace.py` | Reads the trace, receipt and body of the 149 Sepolia transactions of SPK-1 and SPK-1b (hashes from their outputs and ledger), and each changed slot's value at the block before. Redacts the owner's account address before writing and fails if it would be written. Resumable |
| `traces.jsonl` | Its raw output, one redacted record per transaction |
| `compare_runs.py` | Compares two reads, ignoring the order of a state diff's lists (a second read reproduced all 149 records) |
| `devnet_trace.py` | On the local node: walks every block from genesis and reports the slots each of SPK-2's native entrypoints changes (new, overwritten, zeroed). The transactions are those of SPK-2's unchanged `devnet_measure.py` on the throwaway node |
| `devnet-output.txt` | Its raw output (the harness lines name the local node's throwaway accounts) |
| `analyse.py` → `slots-output.txt` | The tables of the research note: every group of transactions, the decomposition of the first residual, the controlled pairs, the fit, SPK-1 §4 rebuilt, the local node's slots |
| `budget.py` → `budget-output.txt` | The arithmetic of the cost budget, each figure marked measured, derived or estimated |

From the repository root:

```
python3 spikes/FND-04/trace.py                  # public Sepolia endpoint, reads only
scripts/with-node.sh bash -c 'python3 spikes/SPK-2/devnet_measure.py > .with-node/spk2.jsonl; python3 spikes/FND-04/devnet_trace.py .with-node/spk2.jsonl' > spikes/FND-04/devnet-output.txt
python3 spikes/FND-04/analyse.py > spikes/FND-04/slots-output.txt
python3 spikes/FND-04/budget.py > spikes/FND-04/budget-output.txt
```

The endpoint: of the four Sepolia endpoints of `spikes/SPK-2/prices.py`, only publicnode's
returns a trace's state diff (RPC 0.10.2).
