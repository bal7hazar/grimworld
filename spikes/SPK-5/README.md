# SPK-5 — Dojo spike

This spike is the Dojo baseline (Dojo 1.8 on Cairo 2.13), not the toolchain of the game: its tools are pinned in its own `.tool-versions` and are not installed by `scripts/setup-toolchain.sh` (ADR-0007, D-123). Install them from this folder (`asdf install`, with the `sozo`, `katana` and `torii` plugins of `dojoengine`).

It runs with its own copy of the node wrapper (`scripts/with-katana.sh` was removed by SPK-5b), from the repository root, at the world's known address:

```
spikes/SPK-5/with-katana.sh --torii --world 0x042f7321b765bf46d69dbc620cc63f56fd1d2d9008a6337f4b8167d57684a277 bash run.sh 42
```

The wrapper and `run.sh` go to this folder first (so asdf selects these pins) and call `sozo` directly, without `scripts/lock.sh`.
