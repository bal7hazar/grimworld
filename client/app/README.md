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
- **The burner's build** (CLI-11d2, devnet only). With a `--build full` deployment (its `build`
  key), `set_build` carries that build instead of the empty bar. No view reads the known skills or
  the pack yet, so its refusal is the probe: refused, the devnet harness (D-280) funds the pack and
  the gold as `scripts/devnet_deploy.py`'s `fund_pack` does (the adventurer enters with the empty
  bar; the node's account 0, which must be the deployment's own, points `Hub.instances` at itself
  for one Open report that credits the gold and twice the belt, points it back in a `finally` and
  reads the storage back; the adventurer travels back), each bar skill is bought (a known one is
  refused and skipped), and `set_build` is sent again. The kit exists only on the local node,
  through the same guard; without a `build` key, the empty bar.
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
after the other (`test:node:preview`, CI's `client-node` job, on a `--build full` deployment since
CLI-11d2, so its full-build tests run there). It makes the burner a player (with the build bought
through the harness, and checked on its bar and belt), restores
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
  `attack` on its entity. The map hears of a goblin tap only through `mapTap`: its selection (the
  arcs) stays in step with the controller's, and it is never told to select a goblin next to the
  adventurer that it would turn toward, since the map draws the chain's facing. `↑`/`↓` take their
  side from the last planned move or turn. Taps do nothing while a batch is in flight. The controller decides no legality: the preview says how far the batch
  plays. `L` and the Fate actions do nothing, with one line. `sandbox/wiring.ts` exports the three
  helpers the path needs (`planPath`, `tileToward`, `directionBetween`), so it stays the only
  importer of `placeholders.ts`.
- **Keys** (`input/keys.ts`). A table of its own, `CHAIN_BINDINGS`, read on the instance screen
  before `BINDINGS`: `Space`, `R`, `B` (send) and `N` (enter again, once the instance closed). The
  sandbox's own screens, and the editor's walk, leave these commands to the page, and its key help
  does not list them.
- **The panel** (`ChainPanel.tsx`, §5). The batch, then the three stages as each becomes known: the
  mirror's at once, the simulation's 300 ms after the last input and at once on `B`, the sent
  batch's beside it; the fields where the mirror, the simulation or the sent outcome differ; one
  line (a refusal, "no funds", "the instance closed"; the controller's own note, such as "no path",
  gives way to a new line of the stages and is cleared by `B`; a guard refusal on `N` shows the
  guard's line). Once a send settles, the simulation it was sent on stays beside the sent result. `B` sends only after the simulation of the
  exact batch shown has answered. `describe` is the whole of what it says, as data.
- **Not in part 1** (§6.3): no optimistic display, no rewind, no kept actions, no recovery beyond a
  fresh read.

To see it work, in a node that lives for one command, after the classes are built:
`pnpm --filter @grimworld/app verify:chain`. `verify-chain.mjs` deploys (`--build full`), opens
`?chain=`, plays a Wait with `Space`, sends it with `B`, checks the three stages (the sent outcome
equal to the simulated one, no field differing) and that no log, page or URL holds the burner's
key, and captures the panel at each stage into `VERIFY_SHOTS_DIR`.

### Skills and belt items on chain (CLI-11d)

`?chain=` also draws the combat screen's elements over the map, fed by the state read back
(`docs/briefs/CLI-05-combat-ui.md` §4.4, §7.2, §9): the skill bar and the belt under the map, the
target zone over them, the log in a panel (desktop) or its last line (phone).

- **The state** (`world.ts`, `ChainController.ts`). `combatWorldOf` loads the mirror's words, the
  batch's content and the ground on the window's board (`combat/fromWords.ts`). It reads the state
  **after the batch planned so far** (the prediction's words and `Prediction.ground`), so the bar,
  the belt, the chips and the aim follow the plan: a potion in the batch is already gone from its
  slot, a skill in it already recharges. The `CombatController` is made again at each change of
  the batch; with no content, or the controlled member not 0, there is no combat view.
- **Inputs.** A tap on a slot, `1`–`8`, `Z X C V`, arms it; the second tap on a self-addressed slot,
  a tap on a marked goblin or tile, or `F` then `Enter`, plays it: one `skill` action (an entity or a
  tile, `x + 256 y`) or one `item` action on an entity. `Esc` disarms. `Wait` and `Turn` on the bar
  are `Space` and `R`.
- **Refused before the batch** (§4.4). The mirror is run on the planned actions plus the new one; an
  `Illegal` at the new action is one line ("Not enough energy.", "Out of reach.", "None left.", …),
  the slot stays armed and the batch is unchanged. A slot that is not ready (recharging, empty belt,
  no adrenaline) says its line on the tap and is not armed. Where the mirror cannot say
  (`NotMirrored`), the action is added and the simulation decides. A tap on a gate, a chest or a
  lever says "Not available yet." and adds no `interact` (`objectAt`: the chunk's objects that are
  no trap).
- **The log** (§7.2). The predicted lines of the batch come from `combat/log.ts`'s `batchLines` on
  the runs of each prefix (`Prefixes`, through `record.ts`'s wrapper of the native classes), kept
  per action so an input adds only its own. After a send, the lines of the played actions are
  confirmed when the sent result matches the prediction, and struck with "The world corrected
  itself" when it does not. A refusal is a muted line of its own status, `refused`, which no send
  confirms or strikes, kept in input order after the lines of the actions planned before it
  (CLI-11d2). Entering again clears the log.
- **Names** (`combat/names.ts`, Q-1): a copy of the table `contracts/seed/README.md` keeps under
  "Names for the client"; `names.test.ts` reads that table, so the copy follows it. An unknown id is
  "Skill 12".
- **Known gaps.** (1) The development server's `/deployment.json` (`src/dev/serveDeployment.ts`)
  serves only the deployment's known fields, and the `build` key is not one of them: in the
  browser the burner's bar stays empty until it is, and `verify:chain` fails at its skill step
  (the node test reads the file directly, and carries the build). (2) The map's overlay draws its reach from the
  sandbox's stand-in (`wiring.ts`'s `combatAim`), not from `targeting.ts`: the controller's aim,
  which plays, is the exact one. (3) The harness points `Hub.instances` at account 0 for one
  report: another burner entering on the same node in that moment is refused, and a page closed
  between the two `set_contracts` leaves the Hub so until the node restarts (devnet only). A setup
  stopped inside the harness's instance plays that instance once, with the empty bar.

`verify:chain` also checks the bar (eight slots), the belt (four), a tap on an empty slot, the log's
line for the Wait predicted and then confirmed, and, when the bar holds a skill, that skill armed,
played and its lines confirmed.

## Combat UI (`src/combat/`, CLI-05)

The combat screens' model, written first without a screen (CLI-05a; the brief is
[`docs/briefs/CLI-05-combat-ui.md`](../../docs/briefs/CLI-05-combat-ui.md)). It decides no rule:
client/sim's loaders build the world, and every figure is read by client/sim's own function
(`energy`, `glyphs`, `memberRecharge`, `aim`, `spot`, `held`, …), exported from
`client/sim/src/index.ts` for this.

- **`state.ts`**: `CombatState`, what the screens read: the bar (each slot's sheet, state and ticks),
  the belt, the gauges, the activation, the chips, the goblins (health, mark, activation, chips),
  the traps, the clock.
- **`fromWords.ts`**: a `CombatState` from `MirrorWords`, the content and the ground on the window's
  board, through `loadWorld(words, indexSheets(content))`.
- **`bar.ts`**: a slot's state in `act`'s order (§2.2): not now (knocked down, or activating), empty,
  unavailable (a carrier R-44 refuses), wrong weapon, recharging, short of adrenaline, short of
  energy, ready; the belt's (§3).
- **`targeting.ts`**: an armed slot's addressing, the tiles `aim` accepts, the tiles in range it
  refuses (out of sight; for a trap, where `spot` finds no place), and the tiles a carrier's shapes
  touch with the actors they take (§4.1–§4.3).
- **`refusal.ts`**: §4.4's lines, and the one line a tap on a slot that is not ready says.
- **`chips.ts`**: conditions and held effects as letter chips with `deadline − clock` (§6.1).
- **`overlay.ts`**: `CombatOverlay`, what the map draws (`ViewState.combat`): CLI-05c fills it,
  CLI-05d draws it.
- **`record.ts`** and **`log.ts`**: the combat log (§7). The runs on a batch's prefixes are cached
  (`Prefixes`), two consecutive ones compared give an action's lines, and each tick-class call is
  replayed one tick at a time with the native `tickTicks` to say who struck whom. A change it cannot
  attribute is one joint line and a `grimworld.log-unattributed` record; a replay that differs from
  its call is a `grimworld.log-replay` record. `CombatLog` keeps the last 100 lines.
- **`fixture.ts`**: the sandbox's fixed fight (§9), at rest and with Wren activating, for CLI-05c's
  `?combat=fight`.

The log's strikers in a tick (review t-0256 of #476, accepted): a target read at the tick's start,
the attack cap, and a goblin Engaged then Fleeing within one tick are cases the replay may not
attribute to one goblin; each falls back to the joint line and its `grimworld.log-unattributed`
record, never to a wrong striker.

**The screen in the sandbox (CLI-05c).** `?combat=fight` opens the instance screen on the fixed
fight (`fixture.ts` at rest; `?combat=activating`, Wren activating Charge), on the `edge` fixture
with the fight's actors (`sandbox/wiring.ts`'s `fightWorld`). The sandbox stays the default.

- **`SkillBar.tsx`**, **`Belt.tsx`**: two rows of four slots with Wait and Turn at their right, and
  the belt's four under them, each at least 44 CSS px, framed by the pack's `square_blue` (pressed
  while armed) or a plain bordered square; a monogram on its kind's ground, a flask drawn by code,
  the keys on desktop, the costs and counts on dark badges (`chrome/contrast.ts`'s `SLOT_TEXT`), one
  state per slot (§2.2) never by colour alone. A long press or a right click inspects a slot.
- **`ChipRow.tsx`**: the letter chips with their figures, in the status band (`Hud`) and the target
  zone; **`TargetZone.tsx`**: the selected goblin (its caste, a small red bar from the pack's
  `bar_small_fill_health`, its mark, chips and activation in words), at a fixed height;
  **`CombatLog.tsx`**: the desktop's right panel (12 lines, scrolling back) and the phone's last
  line with its drawer.
- **Step keys while armed.** A step key is a tap on the adjacent hex, so while a slot is armed it
  acts as that tap: on an empty hex it disarms the slot (a `TILE` slot previews the hex), on a
  goblin it plays or says why. It does not walk. `Esc` or a second tap on the slot also disarm. A
  `TILE` slot takes a tap on a tile whatever stands on it; `targeting.ts` decides if it is in reach.
- **`controller.ts`**: arming (§2.4, §3), §4.1's choices (a marked actor, a `TILE` slot's preview
  then play, `F` / `Shift+F` and `Enter`) and `Esc` (an inspection, then the armed slot, before the
  walk and the selection). It decides no rule: `CombatRules.aim` and `play` are given, in the
  sandbox by the placeholders (`aimInRange` for the range of §4.3, `spendCosts` and `startRecharge`
  for §9's playing), on chain by CLI-11d. Its tests use fakes.
- The session carries the screen's state and armed slot to `toView`, which sets `ViewState.combat`
  (`combatOverlay`); CLI-05d draws it on the map.

`pnpm --filter @grimworld/app verify:combat --shots <folder>` (add `--plain` for no art) checks the
screen in a browser at 1440 × 900 and 375 × 812 and takes its shots: at rest, at the lowest zoom
(with a crop of the hobgoblin's ring), Charge armed, Wren activating. The shots are never committed
or posted (D-73).
