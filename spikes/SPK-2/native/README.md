# SPK-2 part 2 — the same worst cases as native contracts (ADR-0007)

A Scarb package on the root toolchain (Scarb 2.19.4, snforge 0.61.0, sncast, starknet-devnet 0.10.0; `.tool-versions` is a copy of the root's). Two contracts:
- `Hub` (persistent): quests, brewing, `enter`;
- `Instances` (ephemeral): tick, queue, `open`, `leave` → `Hub.apply_results`.

State lives in contract storage, packed by hand (`src/models.cairo`). The pure logic (`alchemy`, `board`, `fate`, `fixtures`, `rules`, `tables`) is copied unchanged from part 1; `check.sh` verifies the copies.

From the repository root:

```
spikes/SPK-2/native/check.sh                                                   # the copies are identical
scripts/lock.sh scarb --manifest-path spikes/SPK-2/native/Scarb.toml build
cd spikes/SPK-2/native && snforge test > snforge-test-output.txt               # 31 tests, budgets
cd spikes/SPK-2/native && snforge test test_systems --trace-components contract-name gas > snforge-trace.txt
python3 spikes/SPK-2/native/summarize_trace.py spikes/SPK-2/native/snforge-trace.txt > spikes/SPK-2/native/snforge-summary.md
scripts/with-node.sh python3 spikes/SPK-2/native/devnet.py > spikes/SPK-2/native/devnet-output.txt
python3 spikes/SPK-2/prices.py > spikes/SPK-2/native/prices-output.txt
python3 spikes/SPK-2/native/money.py > spikes/SPK-2/native/money-output.txt   # side by side with part 1
```

Budgets are refreshed with `python3 ../set_budgets.py <snforge output>` from this folder.
