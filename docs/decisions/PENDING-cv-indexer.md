# PENDING — what IDX-01a needs outside its allowlist

| | |
|---|---|
| Asked by | `[Opus 5.5] Orchestrateur client visuel (Mac)`, 2026-09-29 |
| For | The project manager (IDX-01 is lent by the game, D-149; its allowlist is `indexer/**`, the workspace line, `pnpm-lock.yaml`) |
| Concerns | IDX-01a ([#144](https://github.com/bal7hazar/grimworld/pull/144)); `contracts/persistent/Scarb.toml` (the game's), `.gitignore`, the root `package.json`, `.github/workflows/ci.yml`, `scripts/with-node.sh` |

## 1. Blocking: `contracts/persistent` as a dependency (the game's file)

IDX-01a's test emitter (`indexer/emitter`, a Scarb package) emits the nine frozen events by **reusing
the event types of `contracts/persistent`** through a path dependency, as its brief asks (never a
copy, so that the indexer is tested against the real layouts). Scarb ignores a package as a
dependency unless it has a `[lib]` target, and `contracts/persistent/Scarb.toml` has only
`[[target.starknet-contract]]`: the emitter's CI job fails at `build` (`Identifier not found` on
`grimworld_persistent::events`).

**Asked**: one line, `[lib]` beside `[[target.starknet-contract]]` in
`contracts/persistent/Scarb.toml`, made by the game's track. The implementer verified it on a scratch
copy: the emitter builds, its 10 tests pass, the persistent package still builds. The game's
orchestrator checks that nothing changes for `contracts/` (class sizes, gas tables). Once on `main`,
IDX-01a merges `main` and its CI turns green with no other change.

Alternative if refused: the emitter declares the nine events itself, with a test that compares their
selectors and serialised layouts to `contracts/persistent`'s ABI (`target/dev/*.contract_class.json`).
One more thing to keep in step, which is why it is not the recommendation.

## 2. Formatting and ignore files (shared files)

- The CI's `prettier --check` step and the root `format` script cover `client` only: add `indexer`.
- The root `.gitignore` (or a root `.prettierignore`) needs `indexer/dist/` and
  `indexer/emitter/target/`, as it has `client/*/dist/` and `contracts/target/`: prettier run from the
  root does not read `indexer/.gitignore`, and the CI builds before it checks formatting.

## 3. The local-node scenario in CI

The `client` job installs no starknet-devnet, so `pnpm --filter @grimworld/indexer test:node` (every
event, reorgs of depth 1 to 5 by commitments, restart, rebuild) runs only where devnet is installed
(the Mac, the VPS); `pnpm test` skips it. **Asked**: a CI job with starknet-devnet 0.10.0 running it,
or the decision that it stays local evidence.

## 4. `scripts/with-node.sh` on the Mac

It needs `setsid(1)`, which macOS lacks (IDX-01a puts a stand-in first on `PATH` for its own package
only), and it takes `STATE_ARCHIVE_CAPACITY=full` (needed by `devnet_abortBlocks`) through the
environment only. **Asked**: a macOS fallback for `setsid` and a `--full-archive` option, so that any
package can use it on the Mac.

## Recommendation

1 by the game's track now (it blocks IDX-01a's merge); 2 and 4 in one small tooling pull request by
whoever owns `scripts/` and `.github/`; 3 as a CI job when IDX-01b adds the subscriptions (then the
scenario matters more), local evidence until then.
