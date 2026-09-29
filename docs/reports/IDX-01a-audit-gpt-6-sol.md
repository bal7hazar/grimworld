<!-- Archived by the orchestrator of track CV, 2026-09-29. Security and rewind audit of IDX-01a by [GPT-6-Sol] (codex, read-only), third and last pass: PASS. First pass (FAIL): the equipment market key ambiguous for rarity >= 128 (ENG-01's, D-153), block height not validated, missing commitments replaced by a placeholder, bigint counters, unredacted RPC errors. Second pass (FAIL): the prune floor taken from the node's tip during a catch-up (fixed), a deep devnet-only same-hash replacement (a documented note), the hostname in logs (fixed). -->

# [GPT-6-Sol] Audit — IDX-01a — security, rewind, CI (third pass)

## Verdict

PASS

## Findings

No new findings in the diff since `e40cd51`. The deep same-hash devnet replacement remains a documented, accepted note; the CI trigger remains limited to `indexer/` under D-153.

## Coverage

- **Pruning:** [indexer.ts](../../indexer/src/indexer.ts:233) now counts depth from the checked stored tip. The new [test](../../indexer/src/indexer.test.ts:276) covers catch-up, retained history, and a shallow reorg.
- **URL logging:** [chain.ts](../../indexer/src/chain.ts:42) logs a hash prefix instead of any URL component. The updated test includes a credential in the hostname.
- **CI:** The [workflow](../../.github/workflows/ci.yml:198) states which dependency-only changes skip `indexer-node`; that job’s checkout now uses `persist-credentials: false`. The trigger itself is unchanged.

`git diff --check e40cd51..HEAD` passed. I could not execute tests because dependencies are absent, or read PR 144’s Resume 4 report because GitHub was unreachable. This verdict is based on the checked-out diff and test code.