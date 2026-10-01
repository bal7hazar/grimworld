# CLI-03c — Hubs and the transitions to and from an instance, on fixed data

Written by the orchestrator of track CV, `[Opus 5.5] Orchestrateur CV (client visuel)`, on
2026-10-01, from **D-178** (`docs/decisions/2026-10-01-cli-03b-hubs.md`: the owner tested CLI-03a's
sandbox and asks for the hubs). D-178 and PLAN call this task CLI-03b; that ID is already the merged
sandbox-path lot (#163, `docs/briefs/CLI-03b-sandbox-path.md`, its reports), so it runs as **CLI-03c**.

## Agent
Title: `[Opus 5.5] CLI-03c hubs` · Profile: implement · Branch: `cv/cli-03c-hubs` · Machine: the Mac,
`nexus run --class browser --require browser --require playwright` (a real Chrome, through Playwright,
for the visual checks)

## Goal

After this task the sandbox opens on a **hub**, not only on a room. The owner can walk the whole loop
on fixed data, on a phone's viewport and on a desktop window:

1. **The town**: an illustrated screen with places to tap, the adventurers present as decor, the row of
   services.
2. **The outpost**: the same screen, smaller, with fewer services.
3. **The Gate screen**: where this hub's gates lead, the build and the belt, a last check.
4. **Hub → instance**: choosing a gate, the entry moment, then CLI-03a's renderer on the entry chunk.
5. **Instance → hub**: by a hub gate, by `travel_back`, or by defeat; a closing report screen, then the
   hub.

Nothing in it decides a rule. What design/11 leaves open is drawn so that **the owner decides by eye**,
then written into design/11 by this lot.

## Context

- **D-178** in full: the table *In*, the *Out*, the design rule (open points decided by the owner's eye,
  one line each in design/11). If `docs/decisions/2026-10-01-cli-03b-hubs.md` is not yet at your base
  (the project manager's pull request), this brief holds everything it decides for this task.
- **The mandate's §6, binding** ([ORCH-client-visual](ORCH-client-visual.md)):
  - no rule in `client/app` except in `client/app/src/sandbox/placeholders.ts`, each function marked
    `PLACEHOLDER until CLI-02`;
  - the renderer's input is a view state;
  - a tap produces an **intent**, never a result;
  - rendered on demand, no render loop;
  - no randomness and no clock in anything `client/sim` will decide.
- **The specification**:
  - design/11 *Hubs*: the sketch, the table of screens, the build editor's reminder.
  - design/11 *Rules* (I-1…I-7) and *Desktop*.
  - design/01: Town and Outpost, which services each has, hub gates, map travel.
  - design/09: Region 1 is 1 town and 1 outpost; hubs list the adventurers present (from the indexer
    later; fixed data here).
  - design/10: `Buildings/` for hubs; Pawn as a possible hub figure.
- **The transitions**:
  - design/02 *Expedition lifecycle*, *Entering* (the entry draw, ADR-0002), *Ending an expedition*
    (returned through a hub gate or by `travel_back`; defeated; what is kept), the belt on defeat
    (D-141, E-15).
  - D-148: a gate is used by standing on its anchor tile.
  - design/07 for loot.
  - design/02 *The client's copy of the instance*, *The first chunk*: the entry is a Fate action sent
    alone, and the instance opens on the entry chunk.
- **Fixed data**:
  - ENG-03's seed, `contracts/seed/test-region.json` and its README: region 1, the town (location 1, a
    hub without a map), the zone (location 2: meadow, levels 1–3, entered at chunk 0, tile 105), the
    dungeon's two floors (3, 4), gates 1–5 (1 town → zone, 2 zone → town anchored there: hub gates;
    3, 4 the dungeon's links; 5 a floor gate).
  - The seed has **no outpost**. The outpost is a fixture of `client/app` (design/01's Outpost B,
    "limited services", its gate back to the zone).
  - The fixtures copy what they need from the seed into `client/app`. A test reads
    `contracts/seed/test-region.json` and fails if a copied field differs, so the copy cannot drift.
- **The sandbox as merged**: `client/app/src/sandbox/` (`Sandbox.tsx`, `controller.ts`, `session.ts`,
  `wiring.ts`, `world.ts`, `params.ts` with `?fixture=`, `fixtures/`), `render/`, `input/`.
  - Its reports: CLI-03a's, CLI-03b's, and `docs/reports/CLI-03a-browser-check.md`, which shows how a
    Playwright run on the Mac drove Chrome against `pnpm --filter @grimworld/app dev`.
  - The imports test (`sandbox/imports.test.ts`) guards where rules may live.
- **Art (D-73)**:
  - The pack's buildings are **single still images**, not strips: `Buildings/{Blue,Red,Yellow,Purple,Black}
    Buildings/{Castle,Barracks,Archery,Monastery,Tower,House1,House2,House3}.png` and `Buildings/Others/`
    (Barn, Church, Cottage, Farm, Forge, Fortress, …).
  - `tools/art` (`manifest.toml`, `artpipe/`, `build.py`, its README) packs only animated strips of
    square cells today.
  - Your worktree has **no `assets` submodule**. The atlas is served in development from
    `GRIMWORLD_ART_OUT` or the checkout's `tools/art/out/` (`client/app/src/dev/serveArt.ts`), and
    without it the sandbox draws shapes.

## Scope

- **In**:
  1. **Hub screens**:
     - A hub view (town and outpost) after design/11's sketch: the hub's name and the gold line at the
       top, the illustration in the middle, the services below.
     - The illustration is a set of buildings placed on a ground, each a place to tap. A building's
       tap and its service entry lead to the same screen.
     - Present adventurers walk by as decor (fixed positions or a fixed path; a tap inspects them by
       name, profession and level). No movement rule.
     - Each service (Guild, Trainer, Smith, Armorer, Enchanter, Alchemist, Market, Vault) opens a
       **titled stub screen with a back**, and Gate opens the Gate screen.
     - The outpost shows fewer services. Which ones is open in design/01: show your proposal (for
       example Guild board, Trainer, Vault, Gate), make it a single constant, and leave it to the
       owner's eye.
  2. **The Gate screen**: the gates of this hub from the fixed data (the town's gate 1 to the meadow
     zone, with its levels; the outpost's gates), the build and belt summary of a fixture adventurer,
     design/11's reminder of what the bar cannot do (a reminder, never a block), and a "leave" control
     that emits the intent `enter gate g`.
  3. **Hub → instance**:
     - The entry moment: a short, skippable screen for the entry draw's wait (design/02: the entry is a
       Fate action sent alone). On fixed data it completes at once or after a fixed delay, with no
       randomness.
     - Then the instance opens with CLI-03a's renderer on the entry chunk of the gate's destination.
       For the seed's zone that is chunk 0, tile 105, through a fixture of the room built like the
       sandbox's fixtures.
  4. **Instance → hub**:
     - (a) Standing on a hub gate's anchor (D-148) offers to leave; its intent is `leave`.
     - (b) A `travel_back` control, behind a confirmation (design/11 I-5).
     - (c) Defeat, simulated by a sandbox control ("defeat now", clearly a debug control).
     - Each one shows a **closing report** before the hub: returned or defeated, experience, loot,
       quest progress, the belt's potions credited back (D-141). It uses fixed figures, nothing
       computed.
     - The hub reached is the gate's hub, or the last hub visited on defeat and `travel_back`
       (design/02's table), resolved by a placeholder.
  5. **Navigation and layout**:
     - A small state machine of screens: hub, service, gate, entry, instance, report. Its transitions
       are driven by intents, and the fixed data answers them.
     - `?fixture=` keeps working for rooms, and new values open a hub (`?hub=town`, `?hub=outpost`) or
       the whole loop.
     - Portrait 375 × 812 and a desktop window, after design/11 *Desktop*.
     - Rendered on demand, as the sandbox is.
  6. **Buildings in the atlas** (only what the owner needs to see them):
     - `tools/art` learns a **still** sprite role: a single image, no animation, anchored at its base,
       native size. Manifest entries for the town's buildings (one colour set, the owner's choice
       later; take Blue).
     - The pipeline's tests run on synthetic images, as the existing ones do.
     - The client draws a building from the atlas when it is present, and a labelled shape otherwise.
     - You cannot build the atlas yourself: say in the report how the owner builds it on the Mac to see
       the buildings.
  7. **design/11's Hubs section**:
     - Add one line for each point this lot had to decide that design/11 leaves open: the outpost's
       services, the entry moment, the report's content, how present adventurers move, and where the
       buildings stand.
     - Mark each line **"proposed, the owner's eye"** until the owner confirms it.
     - Nothing else in design/11 changes.
- **Out**:
  - Any rule: legality of a gate, requirements, experience, loot, travel. These come from fixed data or
    `placeholders.ts`.
  - The chain and accounts (CLI-01; `client/app/src/account/**` and `chain.ts` are not yours).
  - The real service screens (CLI-06, CLI-07) and the world map between hubs (CLI-08).
  - `client/sim`, `contracts/`.
- **Allowlist**:
  - `client/app/**` except `client/app/src/account/**` and `client/app/src/chain.ts` and their tests;
    `client/app/package.json` and `pnpm-lock.yaml` for rendering, input and development dependencies
    only, each addition named in the pull request.
  - `tools/art/**` (point 6).
  - `docs/design/11-interface.md`, its *Hubs* section only.
  - Anything else is an escalation.

## Interfaces

- **Intents**, the only outputs of input: `open service s`, `open gate screen`, `enter gate g`, `leave`,
  `travel back`, `close report`, `inspect adventurer a`. They are typed in one module.
- **The fixed data's answers** live in the sandbox's fixtures and `placeholders.ts`. CLI-03 replaces
  them with `client/sim` and the chain.
- **The hub view state** is a type of `client/app` beside `render/view.ts`: buildings, places, present
  adventurers, services. The renderer draws it, as the room's view state is drawn.

## Acceptance criteria

- [ ] AC-1 The town and the outpost render on 375 × 812 and on a desktop window, with buildings from the
      atlas when present and labelled shapes otherwise. Every place and service can be tapped and leads
      to its screen, and back returns.
- [ ] AC-2 The Gate screen lists the hub's gates from the fixed data (a test pins it to the seed), with
      the build and belt summary and the reminder. "Leave" emits `enter gate g`.
- [ ] AC-3 Hub → instance: the entry moment, then the room on the entry chunk of the gate's
      destination, with the sandbox's renderer and input unchanged in behaviour.
- [ ] AC-4 Instance → hub by each of the three ways, each through the closing report, to the hub
      design/02 names.
- [ ] AC-5 No rule outside `placeholders.ts`: the imports test extended to the hub modules; every tap
      yields an intent (unit tests).
- [ ] AC-6 On demand: nothing is drawn on a hub screen once input stops (a test, as for rooms).
- [ ] AC-7 `tools/art` packs a still building (tests on synthetic images); its README says how.
- [ ] AC-8 design/11 *Hubs* carries one line for each open point decided by this lot, marked proposed,
      and nothing else in design/11 changed.
- [ ] AC-9 Visual check on the Mac through Playwright and Chrome: the loop walked on both viewports
      (town → gate → entry → room → leave → report → town; outpost; travel back; defeat). Real output
      in the report; screenshots stay on the Mac (D-73: shapes only may leave it).
- [ ] AC-10 `pnpm --filter @grimworld/app test`, `lint`, `typecheck`, `build`, `prettier --check client
      indexer`, the art pipeline's tests: pass. CI green.

## Rules of this run

- **Nothing of the pack leaves the Mac (D-73)**: no image, atlas or screenshot in a commit, the pull
  request, an issue or a comment. A screenshot that shows only shapes may be described, never
  uploaded.
- **Playwright**: if no Playwright is in the workspace, add `playwright-core` for the run only and
  revert it before you commit, as `docs/reports/CLI-03a-browser-check.md` did, or add it as a named
  development dependency of `client/app` if you keep a script. Start and stop the dev server inside one
  foreground command, and kill only its recorded process group.
- Foreground only. Wait for CI in the foreground (`gh pr checks <n> --watch --interval 30`). Never merge.
- Pull request: title `[Opus 5.5] CLI-03c hubs and transitions on fixed data`. The body says
  **"Audit: none (D-177: the owner sees the lot)"**, names every dependency added, and lists the open
  points proposed in design/11.

## Report

`REPORT.md` as in `docs/briefs/COMMON.md` §7, header `[Opus 5.5] CLI-03c — hubs and transitions`:
- the summary and the pull request's URL;
- the files changed;
- the screens and their intents;
- the open points proposed in design/11;
- the Playwright run, with its commands and real output;
- **what the owner should look at, and how**: the URLs or parameters, and how to build the atlas with
  the buildings on the Mac;
- the commands refused by the profile;
- deviations, escalations, open questions.
