<!-- Archived by the orchestrator of track CV, 2026-09-29. Security and reorgs audit of IDX-01b by [GPT-6-Sol] (codex, read-only), third and last pass: PASS. Pass 1 (FAIL): write backpressure ignored during a snapshot, Q3 loading every sale in memory, a cache read fresh after the stream ended. Pass 2 (FAIL): the shared page cache unbounded, one failing sink stopping resnapshots, the schema version. All fixed. -->

# [GPT-6-Sol] Audit — IDX-01b — security and reorgs (third pass)

## Verdict

PASS

## Findings

None in the diff since the second pass.

## Coverage

The shared page cache now releases pages as readers advance, clears completed or closed snapshots, and evicts under a byte cap. Tests cover sequential topics and eviction while a reader lags. Writes in `status()` and `rewound()` now use the isolated write path; a throwing sink is dropped while healthy streams resnapshot. Stream positions also check block identity, with a test for a missed rewind at the same height.

Schema 3 is refused before the new SQL is prepared, and `rebuild` can recreate an older database; both paths have tests. Change frames are split into groups of at most 1,000 with the block `head` last. A new test confirms that a block served during a spread snapshot follows `reset-end`, with the snapshot pages still read at their original block.

This was a read-only review. Vitest is absent from the worktree, so I inspected the tests but could not run them. `git diff --check` passed; the worktree is unchanged.