# SPK-2 — Cost spike

Report: `docs/research/SPK-2-cost.md`.

## Part 1 — the Dojo baseline

This folder (outside `native/`) is **part 1, the Dojo baseline** (Dojo 1.8 on Cairo 2.13), not the toolchain of the game. Its tools are pinned in its own `.tool-versions` (scarb 2.13.1, starknet-foundry 0.51.2, sozo 1.8.7, katana 1.7.1, torii 1.8.16) and are not installed by `scripts/setup-toolchain.sh` (ADR-0007, D-123). Install them from this folder with `asdf install`, as for `spikes/SPK-5/`.

```
spikes/SPK-2/locked.sh sozo test --manifest-path spikes/SPK-2/Scarb.toml   # from this folder: asdf picks the pins
spikes/SPK-2/with-katana.sh bash run.sh > katana-output.txt              # from the repository root
```

`with-katana.sh` and `locked.sh` are copies of those of `spikes/SPK-5/` (`scripts/with-katana.sh` was removed by SPK-5b).

## Part 2 — native contracts

`native/` is a Scarb package on the root toolchain (Cairo 2.19, snforge 0.61, sncast, starknet-devnet). It carries its own `.tool-versions`, a copy of the root's, so that asdf does not pick part 1's pins from this folder. It measures the same worst cases without Dojo. See `native/README.md`.
