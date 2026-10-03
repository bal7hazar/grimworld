Archived at the merge of #305, 33dc4e5.

## Report

Model: Sonnet 5.5

### Summary
- `scripts/setup-toolchain.sh`: the starknet-devnet version check now runs on the very file whose pinned sha256 was just verified (system binary, or `asdf where` install), not on a PATH lookup. Cause of the failure: the hash check used `asdf where`, the version check used PATH (`exit 127`).
- `scripts/with-node.sh` failed for the same reason (`command -v starknet-devnet`): it now falls back to `asdf where starknet-devnet <pin from .tool-versions>`, read-only, and starts the node by that path.
- `spikes/SPK-15/Scarb.lock` regenerated through `scripts/lock.sh` on Scarb 2.20.1 (hexx 0.1.0-rc.1 replaces origami_hexmap 1.8.0 in the lock).

### Files changed
`scripts/setup-toolchain.sh`, `scripts/with-node.sh`, `spikes/SPK-15/Scarb.lock`. Head `f3e5f24a78f30afae203ff8b071f4fb99d6d6188`.

### Commands run
- `scripts/setup-toolchain.sh` before: ended `starknet-devnet: expected version 0.10.0, exit 127 ... command not found`. After: ends `starknet-devnet    sha256 4e2e6479…167c` then `starknet-devnet    starknet-devnet 0.10.0`, exit 0.
- `scripts/with-node.sh python3 contracts/tools/lifecycle_probe.py --expect contracts/tools/lifecycle-stream-before.json`: exit 0, last line `{"stream": "equal", "transactions": 85, "events": 38, "hub_keys": 97}`.
- `scripts/lock.sh scarb --manifest-path spikes/SPK-15/Scarb.toml build`: finished, lock rewritten.
- `cd spikes/SPK-15 && ../../scripts/lock.sh snforge test`: `Tests: 122 passed, 0 failed, 0 ignored, 0 filtered out`.

### Acceptance criteria
1 setup-toolchain green: shown above. 1 with-node starts the node: probe above. 2 lock regenerated via lock.sh, committed, tests pass: shown above. Other scripts: no other script uses starknet-devnet (grep of `scripts/*.sh`).

### Deviations from the task
- `scripts/prepush.sh` is not on main yet (FND-13 #303 not merged), so it was not run.
- The PR has no CI checks reported at the time of writing (`gh pr checks 305`: none reported yet).

### Escalations
None.

## Next
Review the PR
Check CI on #305 once it reports
