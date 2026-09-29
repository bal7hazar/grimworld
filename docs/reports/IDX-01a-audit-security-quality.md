<!-- Archived by the orchestrator of track CV, 2026-09-29. Security, determinism, quality (and, from the second pass, the CI change as tooling) audit of IDX-01a by [Opus 5.5], third and last pass: PASS. First pass (PASS WITH FINDINGS): a malformed request target crashing the server; a false permanent halt under devnet's same-hash quirk; the RPC URL in logs; ancestors never re-checked; --batch/--poll 0 spinning; counters parsed as Number; rebuild --from later than deployment; head missing on errors; unbounded rewinds; missing tests. All fixed; the equipment market key's rarity >= 128 ambiguity went to D-153. -->

# [Opus 5.5] Audit — IDX-01a — security, determinism, quality, CI (third pass)

This pass covers pull request 144 at head `6f65490`: the one commit since my second pass (`e40cd51`),
"fix loop 2" (Resume 4).
- **Diff:** `.github/workflows/ci.yml`, `indexer/README.md`, `indexer/src/{chain,indexer}.ts`, and
  their tests.
- **Scope:** the findings the orchestrator accepted on the second pass, and whether the diff adds
  anything new.

## Verdict

**PASS**

- **Accepted findings:** all five are fixed: GPT-6-Sol 1 and 3, and my N1 (the comment only), N2
  and N3. Each code fix has a test that fails on the previous code.
- **Documentation-only decisions:** GPT-6-Sol 2 and the rest of my N1 are documented as decided.
- **New:** the diff adds no new finding, and I found no blocker or major issue outside it.
- **CI:** every check of the head commit is `SUCCESS`, including `client` (lint, typecheck, test,
  build, prettier on `client` and `indexer`) and `indexer-node` (starknet-devnet 0.10.0,
  `test:node`).

## Findings

### Accepted findings of the second pass, re-checked

| Finding | Decision | Status | Evidence |
|---|---|---|---|
| [GPT-6-Sol] 1: the prune floor was taken from the node's tip | accepted | **Fixed** | `indexer.ts` `prune()` now takes `floor = checked − depth` for a block depth (`l1` unchanged), still clamped to `min(stored, checked)`. During a catch-up, the last `--depth` blocks the indexer holds stay rewindable. **Test** `indexer.test.ts:276`: a node with 1 000 blocks, depth 20, batch 100. After the second step `lowest` is 80. The old code gave `min(1000−20, 100, 100) = 100`, so the assertion fails on it. A reorg of blocks 99…1000 then rewinds to 98. On the old code 98 had been pruned, so it would have halted with "below the kept history". The tables as of block 1000 then equal a fresh indexer's. |
| [GPT-6-Sol] 2: a deep replacement under empty same-hash devnet blocks | downgraded to a note | **Documented** | "RESIDUAL, DEVNET ONLY" in the header of `indexer.ts`, and in the README's rules. Both state what a real network does instead (the tip's hash changes). This agrees with my second-pass residual on #4. |
| [GPT-6-Sol] 3: the hostname in logs | accepted | **Fixed** | `redact()` is now `rpc <first 8 hex of sha256(url)>`, and no part of the URL appears. `main.ts:156` is the only place it is logged (checked by grep). Node and transport errors were already reduced to the method and a code. Eight hex digits of a hash cannot reveal a key: they are 32 bits against many possible preimages, and they only tell two configurations apart. **Test** `chain.test.ts:102`: a key in the host, the path, the query and the user part, a local URL, and non-URLs. None of `SECRET`, `example`, `127.0.0.1`, `5050` or `http` appears, and labels are stable and distinct. The previous `redact` kept the host, so this test fails on it. The scenario's parsing of the logs does not rely on the old wording: it reads `serving on http://127.0.0.1:<port>`, the server's own address. |
| [Opus 5.5] N1: the CI trigger is narrower than the job's dependencies | sent to the project manager; only the misleading comment fixed | **Comment fixed** | The `indexer-node` comment now says the job runs only when `indexer/` changes or the base is unknown. It lists what it does not run for (`.tool-versions`, `setup-toolchain.sh`, `with-node.sh`, `contracts/persistent`, the workflow) and says such a change is only checked at the next change under `indexer/`. The `pins` comment no longer claims that a devnet bump alone fails. The trigger itself is unchanged, which is outside this pull request's grant (D-153). |
| [Opus 5.5] N2: the tarball's hash is pinned in one place only | accepted | **Fixed (documented)** | The env comment says the tarball's sha256 is pinned in the workflow only. It names where the binary's lives (`setup-toolchain.sh`, `starknet-devnet:0.10.0:amd64`) and says a devnet bump edits both files and `.tool-versions`. The values are unchanged, and `pins` still cross-checks the binary hash. |
| [Opus 5.5] N3: `persist-credentials` | accepted | **Fixed** | `persist-credentials: false` on the `indexer-node` checkout. That job makes no later git call, so nothing needs the token. `discover` keeps it, since it needs it for `git fetch` of the base. The token is `contents: read` either way. |

### New findings

None.

## Coverage

**Read:** the full diff `e40cd51..6f65490`, together with:
- the surrounding `step()` and `prune()` in `indexer.ts`;
- every use of `rpcUrl`, `redact` and `host` in `indexer/src` (grep);
- the scenario's parsing of the logs (`run-indexer.ts`, `scenario.node.test.ts`);
- the `indexer-node` job as a whole.

**For both code fixes, I traced whether the new test would fail on the previous code:**
- the prune floor: `lowest` would be 100, not 80, and the reorg to 98 would halt;
- `redact`: the host would appear.

**Commands:** none were run locally. In the earlier passes every `pnpm --filter @grimworld/indexer`
command was refused with "This command requires approval" in this session. The evidence is the PR's
CI on head `6f65490` (`gh pr view 144`), where every check is `SUCCESS`: `discover`, `tooling`, every
`cairo (…)` job including `indexer/emitter`, `client` and `indexer-node`.
