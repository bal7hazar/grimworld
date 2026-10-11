# @grimworld/app

The client shell. The client as a whole is described in [`../README.md`](../README.md).

## The batch preview (`src/preview/`, CLI-10a, D-257)

Before a batch is sent, the client simulates it on the node and shows the chain's own result.
client/sim's mirror predicts it instantly where it can, and the simulation checks the prediction. The
simulation is exact for `play`: it draws no Fate. On starknet-devnet (CLI-10b) the real result of a
sent batch equals its preview.

- `previewBatch(input, { simulator, predict?, log? })` builds the multicall
  `[Instances.play(…), Instances.instance_state(id)]` and simulates it. It reads the outcome from
  the trace (`BatchPlayed`, the kills, the reveals, the defeat, the closing, and the `InstanceView`
  after the batch) and reconciles it with the mirror. It returns `{ chain, mirror, mismatches }`.
- A batch holding a Fate action (loot, open, mine, barter, entry) is refused before anything is
  simulated. So is a batch that does not encode.
- A `play` that panics comes back as `chain.kind === "reverted"`, with its reason. It is not an
  exception.
- `createRpcSimulator({ nodeUrl, sender })` calls `starknet_simulateTransactions` with
  `SKIP_VALIDATE` and `SKIP_FEE_CHARGE` on `pre_confirmed`. The transaction is unsigned and needs no
  prompt. It speaks JSON-RPC itself: starknet.js stays inside `src/account/` (ADR-0005).
- The chain wins. A field that differs from the mirror's is a parity bug, logged as one
  `grimworld.parity` record (the console for now). There is no prediction (`not-mirrored`), and
  never a mismatch, in these cases: the mirror reaches an unported class (`NotMirrored`), a Move
  reveals a chunk in the mirror, the batch is refused at admission or before its first segment, or
  the play reverts. Any other error of the mirror is no prediction either, logged as one
  `grimworld.mirror-failure` record. The fields not compared, and why, are listed in
  `reconcile.ts`.
- `predict` is client/sim's `runSegment` on the same state: `mirrorOf(state)` (`mirror.ts`) builds
  the segment as `PlayLibrary` does before its first `SegmentLibrary` call, from the view
  (`instance_state`: the words, the goblins a batch loads first, derived ones included, and the
  location's `width`, `height` and `level_min`, VIEW-01 / D-263), the region's chunks
  (`instance_region`), the controlled member (`placement`) and the content. It gives no prediction
  for the view's `UNLOADABLE` marker (a goblin cannot load: the chain refuses the batch), for an
  empty goblin list where the roster or a pack of the area holds some (no `PlayLibrary` set), for
  several members while goblins are listed, where no content is given and the segment reads a
  sheet (a goblin's caste or skill, a bar's skill: `... not in content`), and on any call to
  `TickLibrary`, `ActionLibrary` or `TrapLibrary`, which client/sim does not port yet: it predicts
  the fast path (no goblin awake in the window, no combat, no trap). Given content that lacks a
  sheet the segment reads is a `grimworld.mirror-failure`, not a silent `NotMirrored`. The
  reconciliation compares the goblin sets both ways.
- `assembleContent(view, record)` (`content.ts`, CLI-10d) assembles that content as `PlayLibrary`
  does (`play`'s first `bundle` and `goblins`, play.cairo): the members' bar skills, belt items and
  held effects' skills, the castes of the view's goblins (the derived ones first) and the skills
  of those castes and of the stored goblins' effects it does not hold yet, each read by one
  `Registry.record(kind, id)` and decoded as the Cairo `SkillSheet`, `PotionSheet` and
  `CasteSheet` `read` do. A record the registry lacks is skipped, as `exists` skips it. It needs no
  pack template: the view's goblins carry their caste. Two rounds of reads, each at once.
- `createReader({ nodeUrl })` (`read.ts`) reads those views over `starknet_call`.
- The default bounds (every price 0, an L2 gas amount) are accepted by starknet-devnet 0.10.0, and so
  are bounds all 0: under `SKIP_FEE_CHARGE` it does not bound the execution by them.
- The chain does not tell a batch refused before its first segment from one whose first action is
  illegal (the same `BatchPlayed`, the same state). A first action the chain refuses and the mirror
  accepts is therefore not reported.

The unit tests fake the node with traces shaped by starknet-specs v0.8 (`src/preview/fixtures.ts`),
and with traces recorded on starknet-devnet (`src/preview/recorded.ts`: a Wait, a revert, and the
state before them; no key). No unit test touches the network.

The node test (`src/preview/preview.node.test.ts`, its own script, never in `pnpm test`) runs on the
game that OPS-01a's `scripts/devnet_deploy.py` deploys. From the repository root, after the classes
are built (`scripts/lock.sh --heavy scarb --manifest-path contracts/Scarb.toml build`):

```
scripts/with-node.sh bash -c 'python3 scripts/devnet_deploy.py --out "$PWD/.with-node/deployment.json" &&
  GRIMWORLD_DEPLOYMENT="$PWD/.with-node/deployment.json" pnpm --filter @grimworld/app test:node:preview'
```

It previews a Wait with the mirror, sends the same two calls, and checks that the real trace's
outcome and the state after equal the preview. It also checks a revert (`not controller`), an
admission refusal, the bounds and the account's two calls, and it times 10 simulations of a few
batches, and 10 assemblies of the content (the number of `Registry.record` calls and the time).
`PREVIEW_RECORD=<file>` rewrites `recorded.ts` (with the records read, and the seed's castes, skill
and potion, which the decoders' unit test checks against `contracts/seed/test-region.json`). The world is drawn from the deployment's
entropy, so it differs from run to run: the run prints one line saying whether the mirror predicted
(`mirror: predicted ...` or `mirror: <reason> ...`, the reason as the mirror gives it), and the assertions that depend
on the world (a Wait plays 1 with `Stop.None`, one Move direction is illegal) hold only where the
world observed allows them. CI runs it as the `client-node` job.
