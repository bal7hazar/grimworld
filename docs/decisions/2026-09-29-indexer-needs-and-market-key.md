# D-153: the indexer's needs from the game; the equipment market key

| | |
|---|---|
| Asked by | Track CV's orchestrator: `PENDING-cv-indexer.md` (#145, IDX-01a #144 blocked) and `PENDING-cv-market-key.md` (#146) |
| Decided by | The owner, 2026-09-29, recorded by the `[Opus 5.5]` project manager |

## 1. The indexer (IDX-01)

| | Who |
|---|---|
| **Blocking**: a `[lib]` target beside `[[target.starknet-contract]]` in `contracts/persistent/Scarb.toml`, so that the indexer's test emitter reuses the event types ENG-01 froze. **One source of truth: no copy of the events in the emitter.** The contract's target does not change; class sizes and gas are checked all the same. Track CV checked it on a copy: the emitter compiles, its 10 tests pass, `persistent` still compiles | The game's orchestrator, **first in its queue** |
| Later: a small package of the event types, on which the contract and the indexer depend | To consider; not now |
| `scripts/with-node.sh`: a fallback without `setsid` for macOS, and a `--full-archive` option | The game's orchestrator, which owns the script |
| The prettier step of CI, the root `format` script and `.gitignore` (`indexer/dist/`, `indexer/emitter/target/`), changed for the indexer | Track CV, **in IDX-01's pull request** |
| A CI job with starknet-devnet running `test:node`, triggered only by changes under `indexer/` | Track CV, in IDX-01's pull request; a CI change gets the tooling lens (S Q) |

## 2. The equipment market key (option A, strengthened)

The key is ambiguous for a rarity of 128 or more.

- **The key's format does not change**: the event ENG-01 froze stays frozen.
- **The contract refuses every rarity that is not one of the design's values** (common, fine,
  superior, rare, boss; design/15), not only the values from 128.
- A test covers the refusal, including 128, the value that collided.
- **By the game's track, before RWD-10** (in RWD-06, where an item's rarity is first written).
- The indexer decodes under this assumption, written in a comment and its README; nothing else
  changes on its side.
