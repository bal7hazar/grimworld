# @grimworld/indexer

The indexer of Grim World (D-130; IDX-01a): one Node 24 process that follows a Starknet node over
JSON-RPC 0.10, decodes the nine events frozen by ENG-01 (`Hub`: AdventurerLocated, TitleDisplayed,
TrialPassed, DungeonCleared, RankReached; `Market`: LotPosted, LotClosed, TradeOpened, TradeClosed)
and keeps them in SQLite tables whose rows are versioned by block (`_from`, `_to`). It is never a
source of simulation state (D-133): everything in it is rebuilt from the chain.

```
INDEXER_RPC_URL=<url> node src/main.ts run     --hub <address> --market <address> --from <block> --db <file> [options]
INDEXER_RPC_URL=<url> node src/main.ts rebuild --hub <address> --market <address> --from <block> --db <file> [options]
```

(`pnpm build` emits `dist/main.js`, the same program.)

| Option                                       | Default                      |                                                                                                                                                                                        |
| -------------------------------------------- | ---------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `--from <block>`                             | required                     | **The deployment block of the two contracts.** A database remembers the block it was built from; `run` on it with another configuration and `rebuild --from` another block are refused |
| `--db <file>`                                | required                     | The SQLite file (WAL: also `-wal`, `-shm`)                                                                                                                                             |
| `--port`, `--host`                           | 0 (any free port), 127.0.0.1 | `GET /head`, `GET /stats`                                                                                                                                                              |
| `--poll <ms>`                                | 1000                         | Wait when idle or after a failed step; at least 1                                                                                                                                      |
| `--batch <blocks>`                           | 100                          | Blocks applied per step; at least 1                                                                                                                                                    |
| `--depth <blocks>` or `l1`                   | `l1`                         | History kept below the tip (`l1`: down to the last block accepted on L1). A reorg below it halts                                                                                       |
| `--recheck <blocks>`, `--recheck-every <ms>` | 10, 10000                    | The last blocks below the tip read again, at most that often: `recheck` header reads each time (1 call per second on average at the defaults)                                          |
| `--lot-count`, `--trade-count`               | 0                            | The contracts' counters at the block before `--from`: 0 at deployment, which is the only supported start (below)                                                                       |
| `--rpc <url>`                                | `INDEXER_RPC_URL`            | Prefer the environment: argv is visible to every user of the machine                                                                                                                   |

The RPC URL may carry a provider's key: it is never logged. A URL that is not http(s) is refused
at start without printing it; node and transport errors are logged by method and code only.

## States (R1, R2)

`loading` until the stored tip has been checked and served; `rewinding` from a divergence until the
fork point is served again; `halted` for good on an undecodable event of the two contracts, a gap in
the lot or trade ids, a close of a lot or trade that is not open, or a node that went back below the
kept history. In those states every answer is 503 with the state and no rows. Every answer, errors
included, carries `head {number, hash, commitments}`, the served block (null while none is).

## Assumptions and limits

- **A block is its hash AND its commitments.** starknet-devnet 0.10.0 gives a replacement block the
  hash of the block it replaced. An accepted block without its four commitments, or of another
  height than asked, is refused (the step is retried).
- **Rarity < 128 in the equipment market key.** ENG-01's key is `2^40 + base × 2^16 + requirement ×
2^8 + rarity × 2 + identified`: rarity has 7 bits, and a rarity of 128 or more would be the same
  key as `requirement + 1` (`src/events.ts`, `decodeMarketKey`). Escalated to the project manager.
- **A start after deployment is not supported.** Lot and trade ids come from counters; `--lot-count`
  and `--trade-count` would seed them, but a `LotClosed` or `TradeClosed` of a lot or trade opened
  before `--from` halts (no event gives what was open then). A later start would need the open lots
  and trades read from the views at that block (`lot`, `trade`, `lot_count`, `trade_count`), once
  the market implements them (RWD-10).
- **`LotClosed { sold: false }`** is a withdrawal or a return after expiry: the tables keep `sold`.
- Pre-confirmed blocks are never indexed.

## Tests

- `pnpm test`: unit tests against a fake node (no network).
- `pnpm test:node`: the local-node scenario under `scripts/with-node.sh` with
  `STATE_ARCHIVE_CAPACITY=full` (on macOS through `test-node/bin/setsid`); it needs the emitter's
  artifacts in `emitter/target/dev/` (`scarb --manifest-path emitter/Scarb.toml build`, which needs
  `[lib]` in `contracts/persistent/Scarb.toml`).
