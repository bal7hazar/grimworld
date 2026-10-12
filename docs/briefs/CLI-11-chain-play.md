# CLI-11 — The chain play mode, with the batch preview

**Status: CLI-11a and CLI-11b can start against this brief; CLI-11c waits for both; CLI-11d and
CLI-11e wait for what §9 names.** Written by a thread of track CV on 2026-10-12, under D-273 (the
project manager's ruling of 2026-10-12). This lot is the design and the split into lots; it writes no
code. Nothing here decides a game rule: the chain decides, client/sim mirrors it, and this mode shows
both (mandate `docs/briefs/ORCH-client-visual.md` §6).

## Agent

Proposed per lot in §8. No pin, gas table or budget is involved. Every lot runs on the VPS or the
Mac; the node tests need `starknet-devnet` and the built classes, so they run where
`scripts/with-node.sh` works (both machines, FND-09).

## Context

**What CLI-11 takes over.** PLAN.md's CLI-01 is "client shell in Capacitor: account provider with a
burner implementation, chain access through starknet.js, subscription to the indexer". CLI-11 takes
its browser part: the burner, the chain access, and play on chain. The indexer subscription stays
with CLI-01 (IDX-01 is still todo), and so does Capacitor (D-152, suspended by D-199). Nothing in
CLI-11 needs the indexer: design/02 _The client's copy of the instance_ already says that the client
simulates only over state it reads from the chain, never from the indexer (ADR-0007).

**What exists on main.**

- The batch preview, `client/app/src/preview/` (CLI-10a to CLI-10j, D-257). `previewBatch` builds
  the multicall `[Instances.play(…), Instances.instance_state(id)]`, simulates it with
  `createRpcSimulator`, reads the outcome with `extractOutcome`, and reconciles it with client/sim's
  mirror (`mirrorOf`, `reconcile`). `createReader` reads `instance_state`, `instance_region`,
  `placement`, `content_version` and Registry records. `assembleContent` builds the mirror's content.
  The node test `src/preview/preview.node.test.ts` previews a Wait, sends the same two calls, and
  checks that the real result equals the preview. CI runs it as the `client-node` job. **No screen
  shows any of it.**
- The account module, `client/app/src/account/` (FND-05, FND-08, ADR-0005). `createBurnerProvider`
  keeps a key in `localStorage` under `grimworld.account` (`STORAGE_KEY`). `createStarknetChain` is
  the burner's chain on starknet.js; the module is the only importer of the library. `createNodeFunder`
  funds a burner on the local node, and refuses anything else. `createServiceFunder` asks FND-08's
  funding service (`services/funder/`, not hosted anywhere yet).
- `client/app/src/chain.ts`, `createProvider(nodeUrl)`. Its comment says "Nothing calls it yet". It
  imports starknet.js outside `src/account/`, which ADR-0005 §1 forbids for new code.
- The game screen walks the local sandbox (`client/app/src/sandbox/`): fixed worlds, rules stood in
  by `sandbox/placeholders.ts`, imported only through `sandbox/wiring.ts` and `sandbox/loop/machine.ts`
  (`sandbox/imports.test.ts` checks it). `App.tsx` renders `<Sandbox />` and nothing else.
- `scripts/devnet_deploy.py` (OPS-01a, `docs/devnet-deploy.md`) deploys and seeds the game on a local
  `starknet-devnet`, then registers the node's first pre-funded account, creates adventurer 1, sets an
  empty build and enters gate 1. Its JSON (`--out`) holds `node_url`, `chain_id`, `commit`,
  `account` (an address, no key), `classes`, `contracts` (`registry`, `tx_hash_fate`, `hub`,
  `instances`), `adventurer_id`, `instance_id` and `slot`. `scripts/with-node.sh` starts a node on a
  free port for the length of one command.

**Fixed by D-273.** These are given, not defaults of this brief, and are not reopened here.

- The sandbox stays the default. The chain mode sits behind `?chain=<node url>`.
- The batch preview is shown before sending, and the chain's result after.
- Local devnet first, then Sepolia once track game deploys there. A production network is out of
  scope: it would be an owner act.
- No key is committed, logged, or put in a URL or a query string.
- The burner is for devnet and test networks only.
- The site build ships no node URL or account by default.
- D-273 is reversed if game's Sepolia deployment comes first and changes the target, or if the owner
  sets another order.

## 1. Goal and scope

A developer starts a local node with the game deployed, opens the app with `?chain=<node url>`, and
plays the instance on chain: moves, turns, waits and weapon attacks, gathered into a batch. Before
the batch is sent, the screen shows the mirror's prediction, then the node's simulation. After it is
sent, the screen shows the chain's result and draws the state the chain holds.

**In part 1 (CLI-11a to CLI-11c, devnet):** the mode and its target, the burner on devnet, an
adventurer of the burner's own, the batch from Move, Turn, Wait and Attack, the three stages of the
preview, the send, the state read back and drawn.

**Later (CLI-11d, CLI-11e):** skills, belt items and interactions; Sepolia.

**Out of CLI-11, by design:** the player's optimistic display, rewind, kept actions and recovery
(CLI-03, design/02 _What CLI-03 must do_); design/02's automatic send triggers (CLI-03); Fate actions,
gates, travelling back and the hub loop on chain; the indexer (CLI-01, IDX-01); a production network
(an owner act, D-273).

## 2. Mode and target

### 2.1 The switch

**Default.** `App.tsx` reads `?chain=`. Absent or empty, it renders the sandbox exactly as today.
Present, it loads the chain mode with a dynamic `import()` from a new folder,
`client/app/src/chain/` (new), so the sandbox's bundle neither grows nor loads starknet.js. The old
`client/app/src/chain.ts` and `chain.test.ts` are deleted by CLI-11a: nothing imports them, the name
would clash with the folder, and its starknet.js import breaks ADR-0005 §1.

The value of `chain` must be an `http:` or `https:` URL without user information (`user:pass@`).
In part 1 its host must be the machine itself (`127.0.0.1`, `localhost`, `[::1]`), as
`createNodeFunder`'s own check requires. Anything else shows the sandbox with one line in its debug
panel: "chain mode refused: <reason>". The mode reads no other parameter that could carry a secret:
no key, no account and no address comes from the URL.

**Why.** D-273 fixes the parameter. A dynamic import keeps the default path what it is today. The
user-information rule closes the one way a credential could ride in the node URL itself.

**Reversed if** CLI-11e widens the host rule for a public Sepolia endpoint (https, no credentials,
§2.4), or if CLI-03 makes chain play the default mode.

### 2.2 How the deployment's addresses reach the app

**Default.** In part 1, from the development server. A new middleware in `client/app/vite.config.ts`
(`apply: "serve"`, the pattern `devArt` uses) answers `GET /deployment.json` with the file named by
the environment variable `GRIMWORLD_DEPLOYMENT`. That is the JSON `scripts/devnet_deploy.py --out`
writes, and it holds no key. The handler is a new `client/app/src/dev/serveDeployment.ts`, tested as
`serveArt.ts` is. When the variable is set, the server prints the link to open:
`/?chain=<node_url>`. A developer runs, from the repository root, after the classes are built:

```
scripts/with-node.sh bash -c 'python3 scripts/devnet_deploy.py --out "$PWD/.with-node/deployment.json" &&
  GRIMWORLD_DEPLOYMENT="$PWD/.with-node/deployment.json" pnpm --filter @grimworld/app dev'
```

The chain mode fetches `/deployment.json`, then checks three things before any other request. The
deployment's `node_url` must equal `?chain=`, because a deployment's addresses exist only on its own
node. The node's `starknet_chainId` must equal the deployment's `chain_id`. And §2.3 must pass.

**Why.** The file already exists and is keyless. Four contract addresses in a URL would be long and
easy to get wrong. The ports of `with-node.sh` change at every run, so nothing could be committed for
devnet. And D-154 makes class hashes differ by machine, so the addresses cannot be predicted either.

**Reversed if** a shareable link is wanted (a `?deployment=<url>` parameter that names a keyless
file), or when CLI-11e adds Sepolia, whose addresses are public and committed (§2.4).

### 2.3 How the build refuses a mainnet chain id

**Default.** Every build carries one refusal, `assertTestChain(chainId, endpoint)` in
`client/app/src/chain/network.ts` (new). It runs before the first read, simulation, funding or send,
and again before each send. It accepts exactly `SN_SEPOLIA` (`0x534e5f5345504f4c4941`), which is also
the id that starknet-devnet 0.10 reports. It refuses `SN_MAIN` (`0x534e5f4d41494e`) by name, and any
other id. In part 1 it also requires that the node answers `devnet_getPredeployedAccounts`, a method
of the local node only. A refusal leaves the sandbox on screen with one line in the debug panel, and
nothing is signed. The burner's signatures are bound to the chain id the account reads, so an
execution signed on a test network is invalid on mainnet whatever happens after the check. There is
no build flag that lifts the refusal.

**Why.** A check in the code holds in every build, the site's included. A build-time switch would be
one more way to get it wrong. A check before each send catches a node that changes behind the same
URL; FND-08's service does the same at each funding.

**Reversed if** the owner opens a production network. That is the owner's act (D-273), and it would
take a decision and a lot of its own.

### 2.4 What the production site shows

**Default.** The sandbox, exactly as today. The site's build (`tools/site/deploy-site.sh`, `vite
build`) has no development server, so it has no `/deployment.json`, and the app holds no default
node URL, address or account. `?chain=` on the site therefore finds no deployment. It shows the
sandbox with the line "chain mode: no deployment". In part 1 nothing on the site can reach a node.

From CLI-11e on, Sepolia's addresses are committed in `client/app/src/chain/networks.ts` (new in
CLI-11e): public, keyless, and recorded with their class hashes and commit (D-154). Then
`?chain=<a public Sepolia endpoint>` on the site would play on Sepolia. Whether the site may do
that is the project manager's go, given in CLI-11e's task. Until that go, CLI-11e enables Sepolia
only under the development server.

**Why.** D-273 says the site ships no node URL or account by default. One build for every target
keeps the refusal of §2.3 the only gate.

**Reversed if** the project manager wants the site to keep the chain mode out of its bundle entirely
(a build-time define that drops the dynamic import).

## 3. The account

### 3.1 The burner on devnet

**Default.** The chain mode uses `createBurnerProvider` with `createStarknetChain({ nodeUrl, accountClass:
LOCAL_ACCOUNT_CLASS })` and `createNodeFunder`, all as they are on main. The funder's address and key
are the node's second pre-funded account, index 1. They are read at run time from the node's own
`devnet_getPredeployedAccounts`, held in memory only, never stored, logged, displayed, or put in a URL
or the deployment file. Index 0 stays the deployment's own account, which `scripts/devnet_deploy.py`
and `preview.node.test.ts` send from, so their nonces never race. The amount is 100 STRK
(10^20 fri), a constant of `client/app/src/chain/setup.ts` (new).

**Why.** Every part of it exists, is audited (FND-05) and refuses anything but the local node. The
node publishes these keys itself (docs/devnet-deploy.md), so nothing secret enters the repository.

**Reversed if** the predeployed accounts change in a devnet bump; the index is then a constant to
move.

### 3.2 Its storage

**Default.** `localStorage`, under `grimworld.account`, as FND-05 keeps it: the key, the binding
(chain id and account class) and the address. Storage is per origin, so the development server's
burner and the site's never meet. starknet-devnet and Sepolia report the same chain id, so a key may
be bound to both. The burner's address then differs by class, and `prepare` deploys and funds it
again after a node restart (FND-05's fix loop 1, F-3). Losing the storage loses the account
(ADR-0005 §3). On a test network, that is accepted.

**Why.** It is ADR-0005's stage A as built. A test network needs nothing stronger.

**Reversed if** Sepolia playtests need a key that survives clearing the browser's data. That would be
a change to ADR-0005, not to CLI-11.

### 3.3 When the burner has no funds

**Default.**

- **Devnet.** The burner gets 100 STRK when its account is deployed. There is no top-up in part 1. A
  send refused for its fee shows "no funds" in the panel, and play stops. The developer restarts the
  node: a new node has lost the account, so the next session deploys and funds it again.
- **Sepolia (CLI-11e).** FND-08's service funds a key once (`200 repeated` afterwards, with no new
  funds). A burner that runs dry stops in the same way, with the same line. A new burner needs a
  cleared storage.

**Why.** A devnet lives as long as one `with-node.sh` command. CLI-11a's node test reports what its
batches cost, which shows whether 100 STRK lasts a session; that figure is not measured yet. On Sepolia, the service's caps (one funding a key, 50 a day)
are FND-08's audited answer to a drain. A top-up path would reopen that audit.

**Reversed if** a devnet session runs dry in practice (CLI-11a then adds a `devnet_mint` top-up,
devnet only), or if the project manager wants top-ups on Sepolia (FND-08's caps, its decision).

### 3.4 The burner's own adventurer

**Default.** The burner never plays the deployment's adventurer: the node's account 0 controls it,
and `play` reverts "not controller". On first use, `setup.ts` makes the burner a player of its own,
through Hub entrypoints that any caller may use, in three executions:

1. `Hub.register` and `Hub.create_adventurer(name, 1)`, in one execution;
2. `Hub.set_build(id, EMPTY_BUILD, 0, 0)`, with the empty bar `scripts/devnet_deploy.py` uses;
3. `Hub.enter(id, 1)` alone, because the entry draws Fate (design/02).

On every later session it restores the adventurer from views alone: `Hub.account_of(address)`, then
`Hub.account(id)` for the adventurer, then `Instances.placement(adventurer)` for the instance. An
adventurer placed nowhere is entered again through gate 1. A step that fails leaves what was done in
place, and the next session resumes from the views.

**Why.** No key of the deployment is ever needed in the browser. The views make a reload resume
without any state kept beside the key.

**Reversed if** track game says a burner's adventurer must be made another way, or gate 1 stops being
the start hub's gate into the test zone in `scripts/devnet_deploy.py`. After a defeat or a closing,
see §9, Q-1.

## 4. The batch from the player's inputs

### 4.1 Inputs to actions

**Default.** Actions are `PlayAction`s of `client/app/src/preview/actions.ts`. Directions use the
chain's numbering, 0 East to 5 South-East, which the sandbox's `Facing` already uses. Part 1 maps:

| Input                                                                     | Action                                                                 |
| ------------------------------------------------------------------------- | ---------------------------------------------------------------------- |
| Tap on a floor tile                                                       | One `move` per step of the wiring's path to it, up to the batch's room |
| A step key (`Q W E A S D`, arrows), or a tap on a neighbour               | One `move`                                                             |
| `Space` (design/11 _Desktop_)                                             | `wait`                                                                 |
| `R`, then a step key (design/11 _Desktop_)                                | `turn` to that direction                                               |
| A tap on the goblin already selected (the first tap selects it, as today) | `attack` on its entity                                                 |

The path is planned by the sandbox's wiring on a world built from the chain's state (§6.2). That
keeps `placeholders.ts` behind `wiring.ts`, and `imports.test.ts` unchanged. The planner follows the
batch's own moves geometrically, tile after tile, and never decides legality: the preview says how
far the batch plays.

Skills (`1`–`8`), belt items (`Z X C V`) and interactions wait for CLI-11d. `L` (leave) and the Fate
actions do nothing in the chain mode in part 1, with one line in the panel.

**Why.** These are design/11's own gestures and keys. `input/keys.ts` already reserves `Space` (Wait) and `R` (Turn) on the instance screen, with no command yet. The deployment's adventurer has an empty bar
and no belt, so skills and items could not be tested on it anyway. Attacking on a second tap keeps
the sandbox's first tap (select, show the arcs) and follows I-5.

**Reversed if** CLI-05's skill bar and targeting exist (they then carry skills and items), or if the
owner wants design/11's "tap a goblin in range attacks it" at the first tap.

### 4.2 Where a batch ends

**Default.** The client counts as the contract does, through client/sim. It never sets a limit of
its own.

- **10 actions:** `MAX_ACTIONS`, the encoding's bound. An 11th input waits.
- **The chain's stops,** weight 10 and E-16's 16 goblin records, with E-1's first record and a
  reveal's 2 a chunk (D-141). client/sim's `admit` and `runSegment` compute them in the mirror. Where
  the mirror does not predict (a reveal, `NotMirrored`), the simulation's `BatchPlayed` tells instead.
  An action that the preview shows unplayed for `Stop.Weight` is **kept planned**: it opens the next
  batch (design/02, E-16). Actions after an `Illegal` stop are dropped, because design/02 says an
  invalid action drops the rest.
- **Defeat** ends the batch and the instance (§6.3).
- After each sent batch, the steps of a path not played yet are dropped. The player taps again.

**Why.** design/02 and ENG-07b: "the client must count both exactly as the contract does, or its
batch preview runs past where the chain stops". client/sim already holds those counts against the
vector tables. Dropping the rest of a path after a send stands in for design/02's stop conditions of
the planned queue, which are CLI-03's.

**Reversed if** CLI-03 brings the planned queue's stop conditions and design/02's filling batch.

### 4.3 When it is sent

**Default.** On a key: `B` (the batch), or the "Send" button of the chain mode's panel. One batch is
in flight at a time, and no input is taken while it is. A full batch (10 actions, or a preview
stopped at `Stop.Weight`) takes no more input until it is sent.

**Why.** D-273 wants the preview seen before sending. design/02's automatic triggers (5 s idle,
full, before a Fate action, background, the end of a fight, defeat) would race the reading, and they
are CLI-03's. `B` is bound on no screen of `input/keys.ts`.

**Reversed if** CLI-03 brings the automatic triggers. A lot may also add `?send=auto` (send when
full or after 5 s idle) before CLI-03, if the owner asks to play without the key.

## 5. The preview shown

**Default.** The chain mode's panel has three stages, each shown as soon as it is known, and the map
draws the first.

1. **The mirror, at once.** On each input, `mirrorOf(state)` runs client/sim's segment on the whole
   batch, synchronously. The panel shows the actions played, the stop, the clock and the defeat. The
   map shows the batch's moves as the planned queue's ghost markers, and the adventurer's predicted
   last tile and facing as a ghost. With no prediction, the panel says "not mirrored: <reason>", in
   the mirror's own words, and the map shows the markers only.
2. **The simulation.** `previewBatch` with `createRpcSimulator` runs 300 ms after the last input, and
   at once on `B`. The panel shows its outcome (played, stop, kills, reveals, defeat, a revert's
   reason) and its `mismatches`. Only the answer to the latest batch is shown: an older answer is
   discarded by a request number. `B` sends only after the simulation of the exact batch shown has
   answered, so the preview is always seen before sending.
3. **The sent batch.** `execute` with the same two calls (§6.1), then `status` until `succeeded` or
   `failed`. Then `starknet_traceTransaction` is read through the same `extractOutcome`, and the
   result is reconciled with the same prediction. The panel shows it beside stage 2.

**On a mismatch, the chain wins.** The map draws the chain's state after the batch (§6), never the
mirror's. A field where the mirror differs from the chain is logged as one `grimworld.parity` record
by `consoleParityLog`, as `reconcile` already does (D-257). Where the sent outcome differs from the
simulated one, something moved between the preview and the send; that is logged as one
`grimworld.sent-differs` record (new, the chain mode's own log, with both outcomes). The panel says
which fields differ. Nothing is retried or replayed.

**The panel's words.** The panel is a developer's tool behind a URL parameter. It may say "batch",
"sent" and "simulated". design/11's I-3 ("nothing on screen speaks of the chain") governs the
player's screen, which CLI-03 builds. The HUD and the map say nothing of the chain.

**Why.** It is D-257's order: the instant mirror, then the exact simulation, and the chain wins. It
also shows on screen what CLI-10b proves in its node test, that the real result equals the preview.

**Reversed if** CLI-03 makes chain play the player's mode. The panel then goes behind `panel=1`, and
the player sees only design/11's "saving…" and "the world corrected itself".

## 6. The state read back

### 6.1 What is sent, and where the state after comes from

**Default.** The sent execution makes the preview's own two calls, `[play, instance_state]`. The
state after is the `instance_state` of the sent transaction's trace, decoded by `decodeInstanceView`.
It is the state of that very execution, so it is never assembled from reads at different blocks. The
region is read once the batch has succeeded, with `instance_region` pinned to the receipt's block
hash. That needs `createReader`'s `block` widened from a tag to a block hash: a small change to
`client/app/src/preview/read.ts` in CLI-11b. The sequence and the content version of the next batch
come from that view (`header.sequence`) and from `Registry.content_version`.

**Why.** It is the multicall CLI-10b's node test already sends and checks. `extractOutcome` reads it
as it is. design/02's "never install a state built from reads at different blocks" holds for the view
by construction.

**Against it, said plainly.** design/02 _What CLI-03 must do_, item 4, asks for one call per
transaction. On devnet the view's extra cost is nothing. **Reversed** for Sepolia if CLI-11e measures
the view's gas as more than a few percent of a batch, or if the project manager upholds item 4 for
chain play. Then only `play` is sent, and `instance_state` is read pinned to the receipt's block hash,
like the region.

### 6.2 How it is drawn

**Default.** `client/app/src/chain/world.ts` (new) builds a `SandboxWorld` from the view and the
region:

- the terrain from each revealed chunk's walls (`unpackWalls`), with the unrevealed chunks as wall
  and the void ones as void;
- the members from their state words, a reader of the tile and facing (new, held by a test on a
  recorded view);
- the goblins of the view, through client/sim's `loadGoblin`.

The renderer, the camera, sight and the explored tiles (CLI-03n) are the sandbox's own. The map
redraws only when a new chain state is installed: at the start, and after each sent batch.

### 6.3 Where part 1 stops

Part 1 has none of the following; each belongs to CLI-03:

- **No optimistic display.** Between two sends, the map shows the last chain state, plus stage 1's
  ghosts.
- **No rewind.** The map shows the chain's state after, with no fading and no line.
- **No kept actions.** A reload loses an unsent batch and reads the chain again.
- **No recovery.** There is no rebroadcast, no reorg handling and no half-size retry. A `failed` or
  `unknown` execution is shown in the panel, and play resumes from a fresh read.
- **No second batch filling while one is in flight.**

A defeat or a closed instance shows "the instance closed". Part 1 stops there (§9, Q-1).

## 7. Testing

**Default.**

- **Unit tests,** faked as the preview's are. They use a fake `Simulator`, a fake `Reader`, a fake
  `BurnerChain` and `Funder`, and the recorded traces and views of `src/preview/recorded.ts` and
  `recorded-goblins.ts`. No unit test touches the network. They cover:
  - the parameters (§2.1) and the deployment checks (§2.2);
  - the mainnet refusal (§2.3);
  - the setup's calls and its restore from views (§3.4);
  - the mapping of inputs (§4.1) and the ends of a batch (§4.2);
  - the panel's three stages and the discarding of a stale answer (§5);
  - the world built from a recorded view and region (§6.2).
- **A node test** on devnet, as CLI-10b's: `client/app/src/chain/chain.node.test.ts` (new), skipped
  without `GRIMWORLD_DEPLOYMENT`. A burner funded by account 1 registers, creates, builds and enters.
  It previews a Wait and a short Move batch, sends them, and checks that:
  - the sent outcome equals the simulated one;
  - the state after equals the trace's view;
  - a second provider on the same storage restores the same adventurer and instance without
    registering again.

  It runs under the same command as `test:node:preview`. CLI-11a adds its file to that script in
  `client/app/package.json`, so CI's `client-node` job runs it with no workflow change: that job's
  `client_node` paths already cover `client/app/`.

- **By hand:** `client/app/verify-chain.mjs` (new in CLI-11c), headless and one browser at a time,
  run inside `scripts/with-node.sh`. It opens `?chain=`, plays a Wait with `Space` and `B`, and
  captures the panel's three stages.

Memory: the preview's node test peaks at 235 MB RSS (AGENTS.md). The new one runs under the same
heap cap, `--max-old-space-size=512`, and its peak is measured in CLI-11a's report.

**Why.** It is the pattern CLI-10 established, and the CI job already exists.

**Reversed if** the `client-node` job's 30-minute timeout gets tight. The chain test then gets a
script and a job of its own, which is a workflow change and needs its own grant.

## 8. Lots

In every lot, the test commands are AGENTS.md's for `client/app`:
`pnpm --filter @grimworld/app test`, `lint` and `typecheck`, plus the node test where named. Every
lot adds its part of a "The chain play mode" section to `client/app/README.md`.

### CLI-11a — the mode, the target and the account

**Profile:** `impl-opus`. It handles keys and the network boundary, so a review by another model is
wanted.

**Allowlist:**

- `client/app/src/chain/{params,network,setup,ChainScreen}.ts(x)` (new) and their tests;
- `client/app/src/chain/chain.node.test.ts` (new);
- `client/app/src/dev/serveDeployment.ts` (new) and its test;
- `client/app/vite.config.ts` and `client/app/src/App.tsx`;
- `client/app/src/chain.ts` and `chain.test.ts` (deleted);
- `client/app/package.json` (the `test:node:preview` script);
- `client/app/README.md`.

**What it builds:** §2 and §3. `ChainScreen` is a minimal screen in this lot: it shows "adventurer N
in instance M" or the refusal's line.

**Acceptance:**

- the unit tests of §7 for §2 and §3;
- the node test's setup and restore steps, green in `client-node`;
- `?chain=` with a non-loopback host, with user information, or on `SN_MAIN` (faked) refuses, and
  nothing is sent;
- without `?chain=`, the app is the sandbox, and the sandbox's tests are unchanged.

It first checks that starknet-devnet 0.10 answers a browser's cross-origin requests. If it does not,
the development server proxies the node at `/node`, forwarding only to the deployment's `node_url`,
and the lot says so.

### CLI-11b — the batch and its preview, without a screen

**Profile:** `impl-opus`. The batch's ends must count exactly as the contract does.

**Allowlist:**

- `client/app/src/chain/{batch,stages,send}.ts` (new) and their unit tests;
- `client/app/src/preview/read.ts` (`block` takes a block hash) and its test;
- `client/app/README.md`.

**What it builds:** §4.2 and §4.3 as logic, §5's three stages as a model (no drawing), and §6.1.

**Acceptance:**

- unit tests for 10 actions;
- unit tests for a `Stop.Weight` action kept planned and an `Illegal` stop dropping the rest;
- unit tests for a stale simulation discarded, `B` waiting for the simulation, and the sent outcome
  reconciled;
- a unit test for `grimworld.sent-differs` logged.

Its node steps (preview, send, equal) go into `chain.node.test.ts` after CLI-11a has merged (merge
`origin/main`).

### CLI-11c — the chain screen

**Profile:** `impl-sonnet`. The design is fixed by §4.1, §5 and §6.2.

**Allowlist:**

- `client/app/src/chain/{world,ChainController,ChainPanel}.ts(x)` (new) and their tests;
- `client/app/src/chain/ChainScreen.tsx`;
- `client/app/src/input/keys.ts` (commands for the reserved `Space` and `R`, `R` then a step key, and
  `B`, on the chain screen) and its test;
- `client/app/src/sandbox/wiring.ts`, only to export what the path's directions need from the
  placeholders, keeping it their only importer;
- `client/app/verify-chain.mjs` (new) and its `package.json` script;
- `client/app/README.md`.

**Acceptance:**

- the world built from `recorded-goblins.ts` draws its adventurer and goblin where the view puts
  them;
- each input of §4.1 gives its action (controller tests with fakes);
- `verify-chain.mjs` captures the three stages of a Wait.

### CLI-11d — skills, belt items, interactions (later)

**Profile:** `impl-sonnet`. The inputs of design/11 _Acting_ for skills, items and interaction.

**Waits for:** CLI-05's skill bar and targeting, and a deployment with a non-empty build (§9).

### CLI-11e — Sepolia (later)

**Profile:** `impl-opus`.

**What it builds:**

- `client/app/src/chain/networks.ts` (new): Sepolia's public addresses, their class hashes and
  commit (D-154), checked at start with `starknet_getClassHashAt`;
- the funder by `createServiceFunder`;
- a keyless https endpoint;
- the measurement of §6.1's reversal.

**Waits for:** game's Sepolia deployment and the funding service hosted and funded (§9).

### Order and parallel work

CLI-11a and CLI-11b run **in parallel**, on disjoint files. They share only `client/app/README.md`,
each in its own subsection, which merges cleanly. CLI-11b's node steps land after CLI-11a. CLI-11c
starts when both have merged. CLI-11d and CLI-11e are independent of each other, and each waits for
what it names.

## 9. What CLI-11 needs from others

**From track game:**

- **Q-1.** After a defeat or a closing, what must a burner's adventurer do to enter again: `travel`,
  a hub action, or nothing? Part 1 stops at "the instance closed" until this is answered.
- For CLI-11d: a deployment whose adventurer has skills and belt items, as an option of
  `scripts/devnet_deploy.py`.
- For CLI-11e: the Sepolia deployment (OPS-01), with a committed record of its addresses, class
  hashes and commit.

**From the project manager:**

- Record D-273 in CONTEXT.md.
- The devnet exception to design/02's "one call per transaction" in §6.1, or its refusal.
- For CLI-11e, the go on whether the site may play on Sepolia (§2.4).

**From the owner (reserved acts, CLI-11e only):** hosting FND-08's funding service on a public
network with a funding key, and funding that key from the owner's Sepolia balance (OPS-01, FND-08).
Part 1 (CLI-11a to CLI-11c) needs no act of the owner.
