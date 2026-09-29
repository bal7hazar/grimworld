<!-- Archived by the orchestrator of track CV, 2026-09-29. Security, determinism and quality audit of IDX-01b by [Opus 5.5], third and last pass (PASS WITH FINDINGS; one low: a test gap). Earlier passes: an error answer accepted by the client as fresh (non-200), implicit subscription continuity, nominal bounds, per-subscription snapshots, Q2's unbounded work, a live connection not guarded, the rewind clear untested, no CORS or keep-alive; then an unbumped schema version, unbounded block chunks, a missing test of a block served mid-snapshot. All fixed. -->

# [Opus 5.5] Audit — IDX-01b — security, determinism, quality (third pass)

Pull request 154 at head `1bf9fe0` ("fix loop 2"). This pass covers only the diff since my second pass (`dc3b450`):

- `indexer/src/subscriptions.ts`
- `indexer/src/store.ts`
- `indexer/src/main.ts`
- their tests
- `indexer/README.md`

It uses the same lenses as before: SECURITY, DETERMINISM, QUALITY. Outside the diff I report only a blocker or a
major finding, and I found none.

## Verdict

**PASS WITH FINDINGS**

- My three second-pass findings (N1–N3) are fixed and tested.
- The other items of the fix loop are correct, and each has a test that would fail if its behaviour broke:
  - the shared page cache, bounded in bytes, with eviction
  - writes isolated in `status()` and `rewound()`
  - a resnapshot when a head's block is replaced at the same height
- The spread snapshot still guarantees that a client never sees a mix of two states (argument below).
- The one new finding is a Low gap in the tests. It does not block the merge.

## Second-pass findings: fixed and tested

| # | Second-pass finding | Fix | Test (would fail if broken) |
|---|---|---|---|
| N1 | Schema changed while the version stayed `"2"` | `SCHEMA_VERSION = "3"` (`store.ts:69`). The `Store` constructor reads `meta.schema` before creating or preparing anything, and throws `SchemaMismatch` (read-only databases included). `main.ts` prints it and exits with code 2. `rebuild` checks `--from` through a read-only `Store.peek`, then drops every table whatever the schema, then creates schema 3. | `store.test.ts` "refuses a database of another version when it is opened, before anything is prepared" and "`rebuild` drops every table whatever the schema"; `main.test.ts` "run on a database of another schema version". |
| N2 | One block's changes were a single chunk with no size limit, so a reader that kept up could be dropped | `chunks()` splits a block's `remove` and `add` frames into chunks of at most `page` (1 000). Only the block's last chunk carries its `head` and moves `subscription.head`, so the client still applies the whole block at its head. | "Opus N2": 3 000 lots in one block, a reader that keeps up and a 300 KiB cap. The test checks there are exactly 3 writes, no drop, one head, and that each write is below the cap while the whole block is above it. |
| N3 | No test for a block served while a snapshot is spread | — | "Opus N3" (`page: 2`, `sliceMs: 0`). Block 2, which posts lot 6 and closes lot 3, is served after the first page of a snapshot at block 1. The test checks that all pages are block 1's (`1,2,3,4,5`), that `reset-end` carries head 1, and that block 2's `remove 3`, `add 6` and head then follow. It also checks that the cache is never at head 1 with block 2's rows. If the pages were read at `served`, the page lots would be `1,2,4,5` and the test would fail. |

## The other items of the fix loop

**Byte-bounded shared page cache.**

- *Joining an entry.* An entry is keyed by topic, block identity and a sequence number. A new snapshot joins an
  entry only while its page 0 is still held (`joinable`). `release()` frees pages only below the lowest position of
  the entry's readers. So a joining reader never meets a freed page, and `texts[page]!` is safe.
- *A single reader* releases each page as soon as it has written it: its page text is captured before the release.
  Such an entry holds nothing between steps, and a blocked single reader holds nothing either.
- *Entry lifetime.* An entry is dropped as soon as no snapshot reads it: at `reset-end`, when its subscriber closes
  or is dropped, and on a rewind or a state other than `ok`.
- *Past `pagesMaxBytes`* (default 64 MiB), `bound()` evicts the other entries first, least recently used first. Then
  it detaches the slowest readers of the current entry, never the reader asking. A reader whose entry was evicted or
  who was detached starts again with a fresh `reset-begin`. The client drops its partial copy at that frame, so no
  mix can occur.
- *Tests.* "GPT 1" ×2 check that nothing accumulates across topics, that a lone reader holds at most its current
  page, that the cap plus one page is respected, and that the detached reader ends with a complete copy (100 rows)
  after a second `reset-begin`.

**Isolated writes.**

- `write()` wraps `sink.write`, `buffered()` and `onDrain` in a try/catch. A throw drops that subscription only,
  whichever path made the write: a step, `rewound()`, `status()`, the keep-alive tick, or `open()`.
- `status()` and `rewound()` iterate over a copy of the subscription set, and `reset()` does not touch any sink.
- `drop()` and `close()` guard `destroy()`.
- *Test.* "GPT 2": a sink throws on the rewind's write, and the other two receive `status`, `rewind`, a new snapshot,
  and a fresh cache.

**Resnapshot on a change of a block's identity at the same height.**

- Both the snapshot position and the head are checked by `current()`, which compares against the served block or
  `store.block(number)` with `sameBlock`: hash and commitments, not only the number.
- A missing row means the block is below `lowest`, which is checked first.
- *Test.* "GPT 2" disables `rewound` and `status` on the hub, replaces block 2 at the same height, and expects exactly
  `reset-begin`, `reset-page`, `reset-end` at the new commitments.

**Frames of 1 000:** see N2 above.

**Bounds in `write()`.**

- A step writes at most one page, or `page` frames plus a head: about 300 KB at worst for lots, with a 66-hex
  `modifiers` and 20-digit prices.
- After a refused write, the subscription waits for `drain`. A reader that keeps up therefore holds at most the
  socket's high-water mark plus one step, below the 512 KiB `maxBuffered`.

**The spread snapshot, re-checked after the changes.**

- The pages are still read at the snapshot's block, and nothing but its pages and `reset-end` is written to that
  stream in between.
- The snapshot now also restarts if its block's identity changes, or if its pages are evicted or it is detached.
  Every restart begins with `reset-begin`, which empties the client's staging copy.
- A rewind or a non-`ok` state still leaves the snapshot and writes `rewind` or `status` into the stream.
- So a client still never becomes ready on pages of two blocks.

**Security and determinism lenses.**

- No new SQL takes input from a client.
- The `DROP TABLE "${name}"` of `rebuild` quotes names read from the database's own `sqlite_master`, and runs only
  under the `rebuild` command.
- Only `Date.now()` for stall and keep-alive timing: no rule reads the clock.

## Findings

| # | Severity | Location | Finding | Evidence / failing scenario | Suggested fix |
|---|---|---|---|---|---|
| T1 | Low (tests) | `indexer/src/subscriptions.ts:89-102, 697-715` | `planBlocks` is new in this diff and no test covers it. It limits a change range to 100 blocks and chains ranges through intermediate heads read from `store.block(number)`. By reading, the behaviour is right: the last chunk of each range always carries its `to` head, and the next range starts from it. But no test serves more than `planBlocks` blocks at once to a subscription with a head (`grep planBlocks` finds only `subscriptions.ts`). | An off-by-one at the boundary would pass the suite: one of the two ranges' `to` blocks would be skipped or sent twice, or an intermediate head would lack its changes. That can happen when the indexer catches up by more than 100 blocks while a subscription holds a copy, which is exactly when it matters. | Add a test with `planBlocks: 2` (or 3) that serves 7 blocks at once, with changes on the key in several of them, including both sides of a range boundary. Assert the heads in order with no gaps or repeats, and that the final cache equals `/lots`. |

## Coverage

**Commands run (worktree root, at `1bf9fe0`):**

- `pnpm install --frozen-lockfile`: done.
- `pnpm test`: indexer 10 files, 119 tests passed; client/app 126 passed, 1 skipped; client/sim 8 passed.
- `pnpm lint`: clean.
- `pnpm typecheck`: clean, including the browser-only client configuration.
- `pnpm build`: clean.

**Not run:**

- `pnpm test:node`: not in my allowed command forms. I relied on the green CI.
- `prettier --check`: not in my allowed command forms.
- Sepolia: never used.

**Read in full:** `subscriptions.ts` as of this head, and the new tests of `subscriptions.test.ts` ("fix loop 2",
including the `Reader` sink).

**Read as diffs:** `store.ts` (the schema check, `peek`, `rebuild`, `parseConfig`) and `main.ts` (the `rebuild` order,
`SchemaMismatch` exit). I checked the store and main tests by name and scope.

**Checked by reasoning**, each against the code, with the test named above where one exists:

- the invariants of the page cache: `release`, `joinable`, `evict`, `bound`
- the position checks: `current()`, `lowest`
- the chunk split and the head at a block's last chunk
- the planning in ranges, whose boundary has no test (T1)
