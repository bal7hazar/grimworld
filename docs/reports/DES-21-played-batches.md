# [Opus 5.5] DES-21 — Played actions sent in batches

## Summary
design/02 now states the whole rule of D-133 and design/11 says what the player sees of it.
The model that ran is Opus 5.5, as the brief names. PR: https://github.com/bal7hazar/grimworld/pull/49

- **Planned queue vs played batch** are told apart in one table and one sentence: "a queue is a plan the client walks; a batch is what was walked, sent". **This departs from design/02 v0.4 and from D-133's table** ("planned queue: sent at once"). The client, not the contract, now walks a planned queue and evaluates its stop conditions. Each step it walks is a played action and joins the batch, so a queue sits inside a batch and may straddle two. The reasons: every stop condition is a function of state the client computes exactly (D-40, D-111), the stop conditions protect the player and not the game, and it saves a second entrypoint and per-step checks on chain. The conditions themselves are kept.
- **Size**: each action has a weight, `max(1, world ticks) + 2 × chunks revealed`, and a batch's weight is at most 10. The bound is **40,000,000 L2 gas**: 10 × 3,564,913 (the worst tick's game call on Sepolia, SPK-1 §4; 3,303,993 native on devnet, SPK-2 §9.2) + 1,617,995 (the non-game remainder of a queue of 10, SPK-1 §4) = 37.3M, plus a margin. If the next action would pass the bound, the batch leaves first. The weight counts ticks rather than actions because a 3-tick action is three worst ticks.
- **When a batch leaves**: when it is full; before a Fate action, a gate or travelling back (those are sent alone, after the batch before them is confirmed); after 5 s without input; when the app goes to the background; at the end of a fight (no goblin awake); on defeat. Only one batch is in flight at a time, and at most 20 actions are ahead of the chain.
- **Actions played and not yet sent** are written to the device before they are drawn, sent at the next launch if the sequence still matches, and dropped otherwise. D-05's "any device" row is amended to match.
- **The chain's answer**: a new `Instance.sequence` field. A batch whose sequence does not match runs nothing. Otherwise the batch stops at the first invalid action without reverting. A `BatchPlayed` event is read from the receipt, and a batch that never landed is retried safely. A **rewind drops up to 20 actions**, not "up to a batch" as in D-133's first answer: the batch being filled is played on top of the one in flight.
- **Co-op**: the check is strict on the instance's sequence, and the co-op design may choose a lenient check instead. The MVP keeps the door open under M-1, M-2, M-5 and M-6.
- **Security** table: taking an action back, computing or reordering batches off-chain, holding actions back, replaying, ignoring stop conditions, steering chunk entropy, putting a Fate action in a batch, gas abuse. Batching does not change what the transaction-hash provider allows.
- **Entrypoint** `play(instance_id, adventurer_id, sequence, actions[1..10])`: an action enum, the `BatchPlayed` fields, and a `sequence` argument added to the Fate and gate entrypoints. It comes with an ENG-01 list (7 items) and a CLI-03 list (8 items).

## Files changed
- `docs/design/02-core-loop.md`: v0.5. The old section "Action batching and interruption" is replaced by "Planned queues and played batches (D-133)", which covers the rule, the entrypoint and the two task lists. The simulation budget row and D-05's table row are updated.
- `docs/design/11-interface.md`: v0.2. I-5 now reads "once played". Confirmation now says "played on the tap". The queue section covers planned queues only. "The chain, unseen" gains rows for unsent actions, the 20-action limit, the rewind, a network loss, the wait before a Fate action, and the app closing.

## Commands run
- `git push -u origin HEAD`: new branch pushed.
- `gh pr create …`: https://github.com/bal7hazar/grimworld/pull/49
- `gh pr checks 49 --watch --interval 30`: "no checks reported on the 'docs/des-21-played-batches' branch". The CI does not seem to run on a docs-only change. No green run exists to show.

## Cost
| Entrypoint or algorithm | Before | After | Budget | Note |
|---|---|---|---|---|
| — | — | — | — | No Cairo |

## Acceptance criteria
- AC-1: the brief's points 1–9 are answered in design/02: 1 in "What a batch holds", 2 in "Size", 3 in "When a batch leaves", 4 in "Actions played and not yet sent", 5 in "The chain's answer", 6 in "Two adventurers", 7 in "Security and fairness", 8 in "Entrypoints", 9 in the two task lists. What the player sees is in design/11. D-133's first answers:
  - size 10: kept;
  - leave triggers: kept, with fight end, defeat and the 5 s figure added;
  - kept on the device: kept;
  - no take-back: kept;
  - rewind "up to a batch": replaced by 20, with the reason;
  - the planned queue "sent at once": replaced by client-walked, with the reason.
- AC-2: the entrypoint's arguments, action variants, bounds (1–10 actions, weight ≤ 10), event fields and stop reasons are all stated. The gas bound is 40M, with its sources in SPK-1 and SPK-2.
- AC-3: the security table names 8 ways to try and why each gains nothing or is closed (the sequence closes replay; the encoding closes Fate in a batch). It also has a paragraph on the transaction-hash provider.
- AC-4: I checked design/02's queue section (rewritten), design/04's tick and goblin AI (unchanged, and a batch runs the same ticks), ADR-0001 (the chain is authoritative, the client can rewind), ADR-0002 rules 3 and 5 (Fate alone) and M-1…M-6. The wording changes this needs outside my allowlist are listed below.

## Deviations from the brief
- **The planned queue moves to the client.** This is a design choice inside point 1, with its reason; D-133 had the planned queue sent at once.
- **The rewind limit is 20 actions**, not one batch (the reason is in design/02).
- **The weight of a revealed chunk is 2**, and that figure is provisional. The cost of generating a chunk has not been measured, and ENG-01 must replace the figure.

## Escalations
1. **CONTEXT §5, glossary**:
   - "Queue" ("several actions submitted in one transaction") now contradicts the design. Proposed: **Queue**: actions planned in advance (a path), walked by the client, which stops them on design/02's conditions.
   - **Batch**: played actions sent in one transaction.
   - **Played / planned**.
   - **Rewind**: the client takes the chain's state and drops the actions after the difference.
   - **Sequence**: the count of actions an instance has executed.
   - **Weight**: an action's share of a batch's bound.
2. **ADR-0001**, decision point 3 "Action queue": add "played actions travel in batches (D-133, design/02)".
3. **ADR-0002**, rule 3 "Fate actions end an action queue": change to "end a batch, and a planned queue".
4. **ADR-0006**:
   - line 64, "A reveal is a Fate action… the queue stops": this describes option A. Under the decided option C (D-111) a reveal is computed and can ride in a batch.
   - line 271, "The queue stops when a new chunk is revealed": true of planned queues only, and now evaluated by the client.
5. **design/07** line 33 ("Looting always ends an action queue") and **design/18** line 39: add "and a batch". **design/09**, the Client row: "action queue" becomes "played batches".
6. **D-05** is amended in design/02: actions played but not yet sent are lost when the adventurer is resumed on another device. The decision log may want to record this.
7. **The 40M bound depends on SPK-7** (the worst tick) **and SPK-1b** (the fixed part). If either figure moves, the bound is recomputed from the same formula. The weight rule does not change.

## Fix loop 1

The `[GPT-6-Astra]` audit was a FAIL, with 6 major and 3 minor findings. All of them are fixed in commit `ea4f3d7` on PR #49, touching design/02 and design/11 only. Each line below says what changed and where.

- **F-1 (major)**
  - design/02 *Size*: 40M is now a **target**, not a proven bound. Each figure's source says what it leaves out: SPK-2 §1's omissions, SPK-1 §4's remainder being observed rather than a maximum, and the unmeasured chunk weight.
  - The same section now says what the client does if a batch runs out of resources: it resubmits the same actions in smaller batches (F-5).
  - ENG-01 item 6 is to prove the bound before the weights are frozen: full action execution, ticks, reveals and their new storage, events, validation, the account's overhead, and the cost of rejecting the first invalid action.
- **F-2 (major)**
  - design/02: the bound and the equivalence are now stated **per invocation**, and the triggers as **our client's**.
  - *Security* has a new paragraph, "One transaction is not one invocation", and a multicall row: composing calls in one transaction gives nothing that consecutive transactions would not.
  - The Fate row now says "nothing new in the MVP", where it said "impossible". The MVP's hash provider is the accepted, pre-existing weakness of ADR-0002.
  - New version-1 rule: the provider must not draw from anything the same transaction can steer.
  - The gas row: a sponsor's limit counts gas, not transactions. ENG-01 item 5 adds a multicall equivalence test.
- **F-3 (major)**: design/02 *The chain's answer* has a new paragraph, "What a matching sequence proves": the count, not the history. In the MVP this is accepted as optimistic divergence, found by reconciling. The cost of a check bound to the history (one Poseidon hash per action and one felt written per invocation) or to the state (far more hashing on every batch) is stated, and the choice is left to co-op or version 1. The co-op table points to it.
- **F-4 (major)**
  - design/02 *When a batch leaves* now says two batches (weight 20) bound speculation, not rollback.
  - A new *Reorgs* paragraph: a reorg can undo any depth, including Fate draws, gates and the instance itself. The client drops its predictions and shows the canonical state. The 20-action rewind ceiling is removed.
  - design/11 has a new reorg row. CLI-03 item 7.
- **F-5 (major)**
  - design/02: "does not revert" now applies only to invalidity in the game, with enough resources.
  - A new receipt table covers three statuses:
    - **succeeded**: reconcile;
    - **reverted**: fresh nonce, half-size batches, a single action never retried, rewind and tell the player;
    - **not found**: same nonce, 5 times over about 60 s, then suspend.
  - design/11 has a new row for actions that could not be saved. CLI-03 items 4 and 5.
- **F-6 (major)**
  - design/02 has a new *Reconciling* list of 5 steps: read `BatchPlayed`, then read the views at the receipt's block (or at the pre-confirmed block), then compare field by field, then rewind on any difference. No state commitment is stored on chain.
  - A *Views* row in the entrypoints table lists what ENG-01 must expose, readable at a block. ENG-01 item 7, CLI-03 item 6.
- **F-7 (minor)**: design/02 has a new sequence table:
  - `enter` creates the instance at 0 and takes no sequence;
  - each action that runs adds 1;
  - a gate closes the instance and enters the next one in the same invocation, at sequence 0 with a new id taken from its event.
  - A mismatch on `play` is reported in `BatchPlayed` (stop `Sequence`, carrying the current sequence).
  - A new `Refused` event is emitted by Fate and gate entrypoints on a mismatch or a failed precondition.
  - Every precondition is checked before `fate(domain)`, and the draw and the consumption happen in one invocation (rule 5).
  - ENG-01 items 1 and 3 are rewritten; the entrypoint block lists the Fate, gate and `enter` signatures.
- **F-8 (minor)**: design/02, design/11 (the backpressure row and the network row) and CLI-03 item 2 now say the trigger is "the batch filling is full while the one sent is not confirmed", not "20 actions".
- **F-9 (minor)**: design/02 *Actions played and not yet sent*: the loss is bounded in actions and weight (two batches, weight 20), not in seconds. I added no maximum age, and the section gives the reason: it would only split batches still filling, paying the fixed part again, without lowering the bound in actions. D-05's amendment in design/02 is reworded to match.

### Escalations added by fix loop 1
8. **ADR-0001, reorg and rollback**: add "A reorg can undo confirmed actions to any depth, including Fate draws, gates and the entry into an instance. The client drops every prediction and recovers to the canonical state. Its speculation (two batches ahead of the chain) is not a bound on rollback." The *Consequences* line about rewinds should point to design/02 *The chain's answer*.
9. **ADR-0001, abuse**: "silent rate limits per account" must count gas, not transactions, since one transaction can carry several batches.
10. **ADR-0002, multicall**: add to the rules:
    - "A transaction may compose several calls. In the MVP, the transaction-hash provider can be steered by any call in the same transaction; this is the accepted weakness above.
    - From version 1, the provider must not draw from anything the same transaction can steer: neither its hash or calldata, nor state written by an earlier call of the same transaction."
    - Rule 3 would read "our client submits a Fate action alone". The guarantee comes from the new rule, not from the transaction's shape.
11. **ADR-0002, rule 5**: add "every precondition of a Fate action is checked before drawing".

## Fix loop 2

The `[GPT-6-Astra]` re-audit resolved F-1 to F-5 and F-7 to F-9; three majors remained. All three are fixed in commit `2a02b72` on PR #49, touching design/02 and design/11 only.

- **F-6 (major)**
  - design/02 *Reconciling*: the client now reads **one snapshot**, a single `instance_state(instance_id)` call. The call is pinned to the receipt's block hash once the block is accepted, or made at `pre_confirmed` before that.
  - A new table compares the snapshot's `sequence` with `BatchPlayed`'s sequence after the batch:
    - **equal**: compare field by field, rewind on a difference;
    - **greater**: later actions ran, so the client adopts the snapshot and does not report a divergence;
    - **smaller**: the read is stale, so the client reads again.
  - A state built from several reads is never installed.
  - The *Views* row became the *View* row: one aggregate call covering the instance, the adventurers in it, the goblins of their windows, and the occupancy and terrain of the chunks those windows overlap. Chunks outside the windows come from the indexer for display and are never compared. ENG-01 item 7 and CLI-03 item 6 are rewritten.
- **F-10 (major)**
  - design/02 *Fate*: the claim that version 1 closes the problem is withdrawn. The security row now says "version 1 must close it".
  - The version-1 paragraph now states a **requirement**:
    - attempt-stable draws, for example a request committed in one transaction and fulfilled in a later one;
    - no re-roll through a conditional abort;
    - the permitted call composition stated;
    - the earlier rule kept: the provider does not draw from anything the same transaction can steer.
  - The MVP ruling is unchanged (hash provider, accepted weakness). The requirement is listed as escalation 12.
- **F-11 (major)**
  - design/02 receipt table: **not found** is now an unknown outcome, not a free nonce. The client keeps the transaction's identity and rebroadcasts the same signed transaction 5 times over about 60 s.
  - A new table, "When a transaction stays not found", decides by the account's nonce and one snapshot:
    - **nonce moved and the batch ran**: reconcile;
    - **nonce moved and something else ran**: drop the batch, play the kept actions again on the snapshot, and keep only those still valid with the same result;
    - **nonce did not move**: resubmit;
    - **node unreachable**: only then show "connection lost".
  - CLI-03 item 5 is rewritten.
  - design/11: the network row is scoped to an unreachable node. A new row covers another device playing while a batch was being sent.

### Escalations added by fix loop 2
12. **ADR-0002, version 1**: add as requirements on the provider and the account design:
    - "Fate draws are attempt-stable: the same attempt cannot be retried for a new value (for example, a request committed in one transaction and fulfilled in a later one, the result bound to the request).
    - A transaction that aborts after seeing its draw does not re-roll it.
    - The calls allowed to share a transaction with a Fate call are stated."

    This comes on top of escalation 10's rule, which it does not replace: the provider does not draw from anything the same transaction can steer. The MVP's hash provider stays the accepted weakness.
13. **ADR-0001** (the optimistic client): "The client installs chain state only from one snapshot, read in one call pinned to a block hash or to `pre_confirmed`. A not-found transaction is an unknown outcome, decided by the account's nonce and a snapshot."

## Fix loop 3

The `[GPT-6-Astra]` re-audit resolved F-6 and F-10; two majors remained. Both are fixed in commit `6247949` on PR #49, touching design/02 and design/11 only.

- **F-11 (major)**
  - design/02 receipt table: after the rebroadcasts, the client asks once more for the receipt and its events. If the outcome is still unknown, it **recovers**.
  - The decision table ("When a transaction stays not found") is replaced by a **Recovering** procedure that uses only observable facts:
    1. read the account's nonce from the account, pinned to one accepted block;
    2. read one coherent snapshot at the same block;
    3. adopt the snapshot without saying which transaction ran;
    4. re-simulate in order every action not seen confirmed; keep the prefix whose results match what the player saw, renumbered from the snapshot's sequence and sent with the nonce read; drop the rest from the first mismatch and rewind.
  - A second table shows that the same steps cover every case: the batch ran, it reverted, the nonce was taken by something else, or nothing was included.
  - "Only a node that cannot be reached is shown as a lost connection" is kept.
  - Recovery is also used for the "greater sequence" case of *Reconciling* and at every launch. For that, the kept record now stores the result the player saw after each action.
  - CLI-03 items 5, 6 and 8 are rewritten. design/11: the "chain moved" row now keeps the actions whose results are unchanged.
- **F-12 (major)**
  - design/02 has a new section, *The client's copy of the instance*. It holds every revealed chunk (terrain, occupancy, objects, remains) and every goblin, frozen or awake, with its full state.
  - The copy is read pinned to one accepted block hash. Several calls at that block form one coherent state: `instance_state` plus a new paged view, `instance_region(instance_id, chunk range)`.
  - The whole instance is read at launch, on another device and after a reorg, before play resumes.
  - After a confirmed batch, once its block is accepted, the client re-reads the regions the batch's windows crossed.
  - Speculation runs only over state the copy holds. Before the window reaches a chunk the copy lacks, the client reads that chunk and play waits.
  - The indexer is removed as a source of simulation state (ADR-0007). It stays for display and as an optional early signal of a reorg. The views row no longer sends chunks outside the windows to the indexer.
  - ENG-01 item 8: `instance_region`, with a **restart** test (the whole instance read by regions at one block equals the contract's state) and a **window-crossing** test (a frozen goblin reads back with the state it had when it left the window).
  - CLI-03 items 7, 8 and 12 cover the copy, restart and window crossing.
  - design/11: new rows for the launch read and for waiting while a part of the map is read.

### Escalations added by fix loop 3
14. **ADR-0001 / ADR-0007** (the optimistic client): "The client simulates only over a copy of the instance read from the chain, pinned to one block; the indexer is never a source of simulation state. Recovery after an unknown outcome uses only the account's nonce and a snapshot at one block, and keeps only the actions whose results are unchanged." This extends escalation 13.
15. **CONTEXT §5**: add "copy of the instance" and "recovery" to the new glossary words of escalation 1, if the orchestrator wants them as terms.

## Fix loop 4

This loop was an exception authorised by the project manager, limited to F-13 and F-14 of the last re-audit. I merged `origin/main` (for D-134) as `17cd176` with `git merge`, not a rebase. The fix is commit `2f8c9c8` on PR #49, touching design/02 and design/11 only; nothing else changed.

- **F-14 (major)**
  - design/02 *The client's copy*: the "Crossing into a chunk" row now points to a new table of **three kinds of chunk**:
    - **revealed**: read, pinned to one accepted block; a missing one is read before the window reaches it, and play waits;
    - **not yet revealed**: generated by the client in the speculative overlay under D-111, and checked by reconciliation; never read, never waited for;
    - **void** (D-134): a constant wall, with no read and no wait.
  - A new sentence on **the first chunk**: the entry draw is a Fate action sent alone, so the client waits for it and predicts nothing before it.
  - A new paragraph says **how the views tell the kinds apart**. `instance_state` now returns the instance's **revealed set** and the location's id, and the outline and void margin come from the registry. `instance_region` returns each chunk's kind, with data for revealed chunks only. Both view rows are updated.
  - ENG-01 item 8 adds a **reveal** test (the generated chunk equals the client's, and the revealed set gains it) and a **boundary** test (void chunks assembled with no storage access, reported as void).
  - CLI-03 item 12 adds the three-kind rule, reveal and boundary tests, and waiting for the entry draw.
  - design/11: the "not yet read" row is limited to explored chunks. It never applies at the unexplored edge or at a location's edge.
- **F-13 (minor)**: design/02 *Recovering*, "The batch ran" row: this case now leads to the conservative loss. The first action replays to a different result, so it and every action after it are dropped. The auditor's two-`Wait` example is given (both dropped). I added no rule to keep an unconfirmed suffix.

No new escalations.

## Open questions
- **The 5 s idle timer** is an initial value. Playtest telemetry on mean batch size should tune it.
- ~~A state digest in `BatchPlayed`~~: settled by the F-6 ruling. There is no commitment on chain; the client reads views at the receipt's block.
- **The retry figures** (5 resends over about 60 s; halving on a revert) are initial values for CLI-03 to tune.
- **Knocked down**: design/04 says the adventurer "cannot act". I wrote "acting while knocked down" as invalid. Whether `Wait` is the one allowed action during a knock-down is design/04's to say.
