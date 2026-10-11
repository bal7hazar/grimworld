# @grimworld/app

The client shell. The client as a whole is described in [`../README.md`](../README.md).

## The batch preview (`src/preview/`, CLI-10a, D-257)

Before a batch is sent, the client simulates it on the node and shows the chain's own result. Later,
client/sim's mirror predicts it instantly and the simulation checks the prediction. The simulation
is exact for `play`: it draws no Fate.

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
- `predict` is client/sim's `runSegment` on the same state. The app does not depend on
  `@grimworld/sim` yet. Its `Ran` and `Action` fit `Prediction` and `PlayAction` as they are.

The tests fake the node with traces shaped by starknet-specs v0.8 (`src/preview/fixtures.ts`). No
test touches the network. Part 2 (CLI-10b) runs the preview on starknet-devnet and records a real
trace.
