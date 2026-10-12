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
- **The screen** (`ChainScreen.tsx`), minimal in this lot: "adventurer N in instance M", or the
  refusal's line over the sandbox.

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
