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
  never a mismatch, in these cases: the mirror reaches what it does not mirror (`NotMirrored`), a Move
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
  sheet (a goblin's caste or skill, a bar's skill: `... not in content`), and for a carrier that
  mixes a `TILE` target with an entity one (client/sim's `MIXED`, from `ActionLibrary` or in a
  goblin's carrier of `TickLibrary`'s step 1 or 2). It predicts the fast path (no living goblin in
  the window, no combat) and every segment of combat: the three classes behind the seam are
  client/sim's own, `trapTrigger` (CLI-02g-D, CLI-10e), `actionAct` (CLI-02g-E, CLI-10g) and
  `tickTicks` (CLI-02g-F, CLI-10j), so a combat action followed by ticks (goblins awake, a member
  activating, a living goblin in the window) and a goblin's step onto a trap predict as well.
  (client/sim's `EDGE`, a Move off the window's edge, is unreachable from `run`.) Given content that lacks a
  sheet the segment reads is a `grimworld.mirror-failure`, not a silent `NotMirrored`. The
  reconciliation compares the goblin sets both ways.
- `assembleContent(view, record, ground?)` (`content.ts`, CLI-10d, CLI-10f) assembles that content as `PlayLibrary`
  does (`play`'s first `bundle` and `GoblinsTrait::goblins`, goblins.cairo): the members' bar skills, belt items and
  held effects' skills, the castes of the view's goblins (the derived ones first) and the skills
  of those castes and of the stored goblins' effects it does not hold yet, then the skills of the
  unused terrain traps (`object::TRAP`, `param` ≠ 0) of `ground`, the features of the area's chunks
  (`featuresAround`), as `GoblinsLibrary` reads them (FIX-02b); a trap skill the registry lacks
  stops the real batch `Invalid`, and the mirror raises `NotMirrored`. Each read by one
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
state before them, in a world with no goblin; `src/preview/recorded-goblins.ts`: the same in a world
whose view lists one goblin, with the Registry records read; no key). No unit test touches the network.

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
batches and 10 assemblies of the content (the number of `Registry.record` calls and the time).
`PREVIEW_RECORD=<file>` writes a recording in their form, with the records read and the seed's
castes, skill and potion, which the decoders' unit test checks against
`contracts/seed/test-region.json`. The world is drawn from the deployment's entropy, so it
differs from run to run: the run prints one line saying whether the mirror predicted
(`mirror: predicted ...` or `mirror: <reason> ...`, the reason as the mirror gives it), and the
assertions that depend on the world (a Wait plays 1 with `Stop.None`, one Move direction is
illegal) hold only where the world observed allows them. CI runs it as the `client-node` job.

## The chain play mode (`src/chain/`, CLI-11, D-273)

The sandbox stays the default. `?chain=<node url>` plays on a local node instead
(`docs/briefs/CLI-11-chain-play.md`). `App.tsx` reads only the parameter; the mode itself is loaded
with a dynamic `import()`, so the sandbox's bundle carries no starknet.js.

### The mode, the target and the account (CLI-11a)

- **The switch** (`params.ts`). The value must be an `http:` or `https:` URL, with no user
  information, on this machine (`127.0.0.1`, `localhost`, `[::1]`). Anything else leaves the sandbox
  on screen with one line, "chain mode refused: <reason>", and writes one `grimworld.chain-refused`
  record to the console. The reason names the rule, never the value, so no credential of a refused
  URL is written anywhere. No key, account or address ever comes from the URL.
- **The deployment** (`network.ts`, `src/dev/serveDeployment.ts`). The development server answers
  `/deployment.json` with the known fields of the file `GRIMWORLD_DEPLOYMENT` names (the keyless
  JSON of `scripts/devnet_deploy.py --out`), rebuilt, never the file verbatim, and prints the link
  to open. Anything but a 200 whose body has the deployment's shape is "no deployment": the
  production site, which answers its `index.html` for any path, therefore always shows the sandbox.
  The deployment's `node_url` must equal `?chain=` as written, and the node's chain id the
  deployment's.
- **The one refusal** (`assertTestChain`). The node's chain id must be `SN_SEPOLIA`, which
  starknet-devnet 0.10 reports (`SN_MAIN` is refused by name, any other id too), and the node must
  answer `devnet_getPredeployedAccounts`, which only the local node does. It runs before any read
  of the game, and again before every send and every funding: `network.ts` is the only file of
  `chain/` that builds the burner's chain and funder, and it hands them out guarded. A unit test
  holds that.
- **The burner** (`setup.ts`). `createBurnerProvider` as FND-05 built it, its key in
  `localStorage` (`grimworld.account`). The node's pre-funded account 1 funds it with 100 STRK, its
  key read from the node and held in memory only (account 0 is the deployment's). The burner gets
  an adventurer of its own: `restore` reads the Hub's and Instances' views and sends only what is
  missing (`register` with `create_adventurer`; `create_adventurer`; `travel` when its hub is not
  gate 1's source; `set_build` before every `enter`; `enter`), each its own execution, so a reload
  or a failed step resumes from the views. `enter` alone enters again after an instance closes.
- **The screen** (`ChainScreen.tsx`): CLI-11a made it minimal ("adventurer N in instance M", or the
  refusal's line over the sandbox); CLI-11c draws the instance (below). The refusal is unchanged.

starknet-devnet 0.10 answers a browser's cross-origin requests (`access-control-allow-origin: *`,
checked by CLI-11a), so the page talks to the node directly, with no proxy. To play, from the
repository root, after the classes are built:

```
scripts/with-node.sh bash -c 'python3 scripts/devnet_deploy.py --out "$PWD/.with-node/deployment.json" &&
  GRIMWORLD_DEPLOYMENT="$PWD/.with-node/deployment.json" pnpm --filter @grimworld/app dev'
```

and open the printed link, `/?chain=http://127.0.0.1:<port>`.

The node test `src/chain/chain.node.test.ts` runs after the preview's, on the same node, one file
after the other (`test:node:preview`, CI's `client-node` job). It makes the burner a player, restores
it from a second provider on the same storage without sending anything, closes the instance with
`Instances.travel_back`, and enters the same adventurer again (`set_build`, then `enter`). It prints
what each execution cost. It reads `GRIMWORLD_DEPLOYMENT`, or `.with-node/deployment.json` at the
repository's root while that file's node answers. The whole run on a fresh node, after the classes
are built: `pnpm --filter @grimworld/app test:node:devnet`; against a deployment already made:
`test:node:chain`.

Three things the account and the guard do that a developer meets (review t-0236, deferred notes):

- `assertTestChain` makes two RPC calls (`starknet_chainId` and `devnet_getPredeployedAccounts`)
  before every send and every funding, and fails closed on any RPC error: a node that stops
  answering sends nothing.
- `?chain=` must be the link `serveDeployment` prints. It is compared with the deployment's
  `node_url` as written, so `localhost` in place of `127.0.0.1`, or a trailing slash, is refused as
  "deployment of another node".
- A refusal of the guard reaches the screen as `AccountError` with the cause `ChainRefused`, and the
  panel shows the guard's own line. A send never goes through `Opened.rpc`: every execution is the
  guarded provider's.

### The batch and its preview (CLI-11b)

The batch of the chain mode and the three stages of its preview, as logic with no screen. CLI-11c
(below) draws them.

- `batch.ts` holds the planned actions and applies where a batch ends. It counts nothing itself:
  10 actions is the encoding's bound, and the chain's stops come from the preview. `Stop.Weight`
  makes the batch full, and the action that did not fit opens the next one. `Stop.Invalid` drops
  the refused action and every one after it. `Stop.Sequence` and `Stop.Version` keep every action
  and read the state again. A defeat or a closing ends the instance. After a send, the steps of a
  tapped path that did not play are dropped. One exception: after a weight stop, the action that
  did not fit is kept even when it is a path's step, so a lone step of a path can open the next
  batch; the path's later steps are dropped.
- `stages.ts` (`createStages`) is the model the panel reads. Stage 1 is the mirror, run at every
  input. Stage 2 is `previewBatch`, run 300 ms after the last input and at once on `send()` (`B`).
  Each batch takes a request number, and an older answer is discarded. `send()` waits for the
  simulation of the exact batch shown. One batch is in flight at a time, and no input is taken
  until it settles. Stage 3 is the sent batch, beside the simulation it was sent on. `install(state)`
  (entering again) is refused while a batch is in flight or the state is being read. A read that
  fails leaves the batch unpreviewed until the next input or `B`.
- `send.ts` (`sendBatch`) awaits the injected `assertChain` before `execute`, so a mainnet chain id
  sends nothing, whoever built the account provider. It sends the preview's two calls and waits for
  them to settle. Then it reads the trace through the same `extractOutcome`, and reconciles it with
  the same prediction. A sent outcome that differs from the simulated one is logged as one
  `grimworld.sent-differs` record, with the fields that differ and both outcomes. The state after
  is the trace's view. The region and the content version are read at the receipt's block hash
  (`createReader({ block: { blockHash } })`).
- Past a send, `sendBatch` never throws. A send whose status, trace, receipt or state after cannot
  be read is `unread`, and the model reads the state again. It drops the actions that played,
  counted from the sequence's move. When that count cannot be known, because the read fails, the
  execution has not settled, or the move is more than the batch, the whole plan is dropped. The
  panel then says "sent, result unreadable", never that the batch was not sent, so `B` never plays
  the same actions twice. One consequence (review t-0237): after an `unread` send, `recover` drops
  every path step of the rest, including an unfit one that `afterSend` would have kept; a send that
  settled with the sequence unmoved keeps the whole plan.
- "No funds" is the provider's refusal with RPC code 54, `INSUFFICIENT_ACCOUNT_BALANCE`, and
  nothing else. It was observed on starknet-devnet 0.10.0 through starknet.js 10.8.0 (`RpcError`,
  the `cause` of the burner's `AccountError("refused")`), from an account drained below the fee:
  "Account balance is smaller than the transaction's maximal fee (calculated as the sum of each
  resource's limit x max price)". Code 53, "The transaction's resources don't cover validation or
  the minimal transaction fee", came from bounds set too low or priced past the balance from a
  funded account. It says the bounds, not the funds, so it reads as a plain refusal. No message is
  read.

### The chain screen (CLI-11c)

`ChainScreen.tsx` draws what 11a and 11b hold. `?chain=` opens the sandbox's own renderer on the
instance the chain holds, and a panel under it. Nothing on the map speaks of the chain; the panel is
a developer's tool and says "batch", "simulated" and "sent".

- **The world** (`world.ts`, §6.2). `chainWorld` builds a `SandboxWorld` from the view and the
  region: a revealed chunk's tiles from its walls, an unrevealed chunk as the sandbox's unrevealed
  kind, a void chunk as wall over water, the members from their state words (tile and facing at
  bits 32–55) and the goblins from theirs (bits 0–23, AI state at 24–31, caste at 64–79; the dead
  are left out). The sight, the camera and the explored tiles are the sandbox's. The map is
  mounted again only when a new chain state is installed (the start, each sent batch, entering
  again); between two sends stage 1 is a layer of ghost markers over it: one ring per move of the
  batch, and the tile and facing the mirror predicts for the adventurer. With no prediction, the
  panel says "not mirrored: <reason>" in the mirror's words, and the map shows the rings only.
- **Inputs** (`ChainController.ts`, §4.1). A tap on a floor tile far away is one `move` per step of
  the wiring's path, planned on the world, from the tile where the batch's moves end; a tap on a
  neighbour, or a step key (`Q W E A S D`, the arrows), is one `move`; `Space` is `wait`; `R` then a
  step key is a `turn`; a first tap on a goblin selects it (the sandbox's arcs), a second one is
  `attack` on its entity. The controller decides no legality: the preview says how far the batch
  plays. `L` and the Fate actions do nothing, with one line. `sandbox/wiring.ts` exports the three
  helpers the path needs (`planPath`, `tileToward`, `directionBetween`), so it stays the only
  importer of `placeholders.ts`.
- **Keys** (`input/keys.ts`). A table of its own, `CHAIN_BINDINGS`, read on the instance screen
  before `BINDINGS`: `Space`, `R`, `B` (send) and `N` (enter again, once the instance closed). The
  sandbox's own screens leave these commands to the page, and its key help does not list them.
- **The panel** (`ChainPanel.tsx`, §5). The batch, then the three stages as each becomes known: the
  mirror's at once, the simulation's 300 ms after the last input and at once on `B`, the sent
  batch's beside it; the fields where the mirror, the simulation or the sent outcome differ; one
  line (a refusal, "no funds", "the instance closed"). `B` sends only after the simulation of the
  exact batch shown has answered. `describe` is the whole of what it says, as data.
- **Not in part 1** (§6.3): no optimistic display, no rewind, no kept actions, no recovery beyond a
  fresh read.

To see it work, in a node that lives for one command, after the classes are built:
`pnpm --filter @grimworld/app verify:chain`. `verify-chain.mjs` deploys, opens `?chain=`, plays a
Wait with `Space`, sends it with `B`, checks the three stages (the sent outcome equal to the
simulated one, no field differing) and that no log, page or URL holds the burner's key, and
captures the panel at each stage into `VERIFY_SHOTS_DIR`.
