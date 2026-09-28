# SPK-2 — Cost spike

Report: `docs/research/SPK-2-cost.md`.

## Part 1 — the Dojo baseline

This folder (outside `native/`) is **part 1, the Dojo baseline** (Dojo 1.8 on Cairo 2.13), not the toolchain of the game. Its tools are pinned in its own `.tool-versions` (scarb 2.13.1, starknet-foundry 0.51.2, sozo 1.8.7, katana 1.7.1, torii 1.8.16) and are not installed by `scripts/setup-toolchain.sh` (ADR-0007, D-123). Install them from this folder with `asdf install`, as for `spikes/SPK-5/`.

```
spikes/SPK-2/locked.sh sozo test --manifest-path spikes/SPK-2/Scarb.toml   # from this folder: asdf picks the pins
spikes/SPK-2/with-katana.sh bash run.sh > katana-output.txt              # from the repository root
```

`with-katana.sh` and `locked.sh` are copies of those of `spikes/SPK-5/` (`scripts/with-katana.sh` was removed by SPK-5b).

## Fix loop 1 — both sides on one node and one account

```
python3 spikes/SPK-2/adversarial.py > spikes/SPK-2/adversarial-output.txt           # the adversarial boards
scripts/with-node.sh python3 spikes/SPK-2/devnet_measure.py > spikes/SPK-2/devnet-output.txt
python3 spikes/SPK-2/prices.py > spikes/SPK-2/prices-fixloop1-output.txt
python3 spikes/SPK-2/money_devnet.py > spikes/SPK-2/money-devnet-output.txt       # the decision-grade tables
```

`devnet_measure.py` does four things on starknet-devnet:
- declares and deploys `account/` (OpenZeppelin account 4.0.1 compiled with Cairo 2.19);
- deploys the native contracts, built with Cairo 2.19 and with Cairo 2.13 (`native213/`);
- migrates this Dojo world with sozo;
- sends every measured transaction of both sides through that one account, recording receipts and traces.

`native/meter_check.py` (with `part1` from this folder) sets snforge's two metering modes against devnet's figures.

## Part 2 — native contracts

`native/` is a Scarb package on the root toolchain (Cairo 2.19, snforge 0.61, sncast, starknet-devnet). It carries its own `.tool-versions`, a copy of the root's, so that asdf does not pick part 1's pins from this folder. It measures the same worst cases without Dojo. See `native/README.md`.
