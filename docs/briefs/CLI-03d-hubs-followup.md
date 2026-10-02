# CLI-03d — Hubs follow-up: the arrival rule, the review's notes, the owner's choices

**Status: waits for the owner's test of CLI-03c; the parameters are filled from it.** Until the table
in *Parameters for the owner* carries the owner's answers, only the fixed scope (§1 and §2) may start.

Written by the orchestrator of track CV on 2026-10-02, from the follow-up in
`docs/handover/orchestrator-cv-2026-10-01.md` (§CLI-03c, *Follow-up, after the owner's test*), the
review `docs/reports/CLI-03c-review-sonnet.md` and design/11 *Hubs*. CLI-03c merged as #270.

## Agent

Profile: `impl-sonnet` (the fixed scope is small and mechanical; the parameters are constants and fixture
edits). Take `impl-opus` only if the owner's answers reshape a screen. Branch: `cv/cli-03d-hubs-followup`.
Machine: the VPS for everything except AC-7, which needs a real Chrome through Playwright: the Mac, as
CLI-03c did (`--machine mac`, repo `/Users/bal7hazar/git/grimworld`). Pins are not involved.

## Goal

After this task the hubs loop of CLI-03c behaves as the owner chose, and its two known rough edges are
closed:

1. **The arrival rule** no longer offers to leave the instance the moment the adventurer arrives on a
   hub gate's anchor.
2. **The review's two notes** are answered by tests.
3. **The five open points** of design/11 *Hubs* take the owner's values, and their lines lose
   "proposed, the owner's eye".

Nothing in it decides a game rule (mandate §6 holds as in CLI-03c).

## Context

- CLI-03c's brief `docs/briefs/CLI-03c-hubs.md` (the loop, the screens, the intents), its review, and
  D-178 (`docs/decisions/2026-10-01-cli-03c-hubs.md`: open points are decided by the owner's eye, one
  line each in design/11).
- The mandate `docs/briefs/ORCH-client-visual.md` §6, binding: no rule in `client/app` except in
  `client/app/src/sandbox/placeholders.ts`, each function marked `PLACEHOLDER until CLI-02`; a tap
  produces an intent; rendered on demand; no randomness or clock where `client/sim` will decide.
- D-148: a gate is used by standing on its anchor tile. The seed's return gate (gate 2, zone → town) is
  anchored in the zone; arriving on it is the design, not a bug. **No seed change.**
- D-73: nothing of the art pack in a commit, pull request, issue, comment or report; shapes only.
- D-177: no audit unless an exception applies (see *Review*).

## Fixed scope (decided)

### 1. The arrival rule (project manager, 2026-10-01)

The client offers to leave an instance by a hub gate **only when** the adventurer steps onto a gate
tile after having left it, or through the Gate button; **never on arrival**.

- The state machine (`client/app/src/sandbox/loop/machine.ts`) knows whether the adventurer has left
  the gate's anchor since arriving. It records a flag from the walk events (`listenToWalk`), not from a
  clock. The test of "on a gate tile" stays `hubGateAt` in `placeholders.ts`; the machine adds no rule
  of its own.
- The Gate button (an explicit tap) offers to leave whatever the tile, with the confirmation I-5 gives.
- Review note 3 of CLI-03c (an entry tile that is itself a hub gate's anchor) is the same case: the
  rule above rewrites it. Cover it by a test with a fixture whose entry tile is a gate anchor.
- design/11: **one line** under *Hubs* stating the rule, only if the owner agrees (see the table).

### 2. The CLI-03c review's notes

- **Note 1, the imports test's regex.** `client/app/src/sandbox/imports.test.ts` guards "no tile is
  compared to an anchor" with a one-line regex that cannot see a comparison split over two lines.
  Replace it with a check anchored on imports: which modules import `sameTile` and `hubGateAt`, against
  an allow-list (`InstanceScreen`, `Loop`, `screens`, `machine`, `placeholders`). Keep the test failing
  on a seeded violation (write it first, show it red, then green).
- **Note 2, the strips' atlas output.** Add a test in `tools/art` with synthetic strips plus a still
  that asserts the strips' frame placements and their cells are identical with and without the still.
  The review observed that the last page's bytes can change when a still lands on it: state in the test
  what is pinned (frame rectangles of the strips) and what is not (page size).

## Parameters for the owner

The five points design/11 *Hubs* marks "proposed, the owner's eye". The default is CLI-03c's behaviour.
The owner's answers are filled in from their test; an empty "Owner's choice" means the default stands.

| Point | Default (CLI-03c) | If the owner picks otherwise | Owner's choice |
|---|---|---|---|
| Outpost's services | Guild (board), Trainer, Vault, Gate; one constant `OUTPOST_SERVICES` | Edit the constant (add or drop Smith, Armorer, Enchanter, Alchemist, Market); the outpost's buildings follow it; the hub test counts the services | _to fill_ |
| Entry moment | "Through the gate, to …", 1.2 s on fixed data, Skip button | Another delay (the default of `?entry=`); no screen at all (the loop goes straight to the room); Skip removed. The entry draw's wait is real on chain later: keep the screen's contract (it ends when told) | _to fill_ |
| Closing report | Returned or Defeated, how, the hub reached; experience, loot, quest progress, belt potions back; one button to the hub | Add or remove a block (for example: gold, time spent, the build used); change the order; a one-line report instead of a screen. Fixed figures only, nothing computed | _to fill_ |
| Adventurers as decor | Standing still at fixed spots near the road; a tap shows name, profession, level; nothing drawn between taps | They walk a fixed path (a clocked animation: on demand rendering must hold, so frames are drawn only while it plays and stop at the end), or are removed from the hub | _to fill_ |
| Where the buildings stand | Town: Guild at the back, Trainer, Enchanter; Smith, Armorer, Alchemist, Market along the road; Vault and the Gate in front. Outpost: Guild and Trainer at the back, Vault and the Gate in front | Move a building: edit the hub fixtures' positions (`fixtures/hubs.ts`); a tap target never overlaps another at 375 × 812 (a test) | _to fill_ |
| The arrival rule (fixed scope §1) | Offered on arrival (the CLI-03c behaviour) | The rule of §1 is the project manager's decision; the owner confirms it, or asks to keep arrival offers. If the owner keeps them, §1 is dropped and the review's note 3 stands | _to fill_ |

Rule for the implementer: each answer is a constant, a fixture value or a label, never a branch of
logic. If an answer needs logic that is not in `placeholders.ts`, stop that part and escalate it.

## Scope

- **In**:
  1. The arrival rule (§1) and its tests.
  2. The two review notes (§2).
  3. The owner's answers in the table, applied to the constants and fixtures.
  4. design/11 *Hubs*: update the five lines (and add the arrival-rule line if agreed) so each states
     the decided value; remove "proposed, the owner's eye" from a line only when the owner's choice is
     recorded in the table. A line the owner has not answered keeps its mark.
  5. The Playwright check (see *Open question*).
- **Out**:
  - Any rule: legality of a gate, requirements, experience, loot, travel (`placeholders.ts` or
    `client/sim`).
  - The chain and accounts (`client/app/src/account/**`, `client/app/src/chain.ts`).
  - The real service screens (CLI-06, CLI-07), the world map (CLI-08), a new art role.
  - `client/sim`, `contracts/` (including the seed).
- **Allowlist**:
  - `client/app/**` except `client/app/src/account/**` and `client/app/src/chain.ts` and their tests;
    `client/app/package.json` and `pnpm-lock.yaml` only for the Playwright dependency below, once the
    project manager has answered.
  - `tools/art/**`, only the test of §2 note 2 (no change to the pipeline's behaviour).
  - `docs/design/11-interface.md`, its *Hubs* section only, only for lines the owner decides.
  - `docs/reports/` for this lot's report.
  - Anything else is an escalation.

## Interfaces

- **Intents** are unchanged (`open service s`, `open gate screen`, `enter gate g`, `leave`,
  `travel back`, `close report`, `inspect adventurer a`). The arrival rule changes **when `leave` is
  offered**, not its type.
- **The walk event**: the machine reads the adventurer's tile from the controller's `listenToWalk`
  callback, as CLI-03c does. The new state is "left the anchor since arriving" (a boolean in the
  instance screen's state, reset on each arrival).
- **`hubGateAt(gates, location, tile)`** (`placeholders.ts`) is the only function that says a tile is a
  hub gate's anchor. Unchanged.

## Acceptance criteria

- [ ] AC-1 Arriving on a hub gate's anchor (a fixture whose entry tile is that anchor) does not offer to
      leave; stepping off and back on does; the Gate button offers it from any tile. Unit tests on the
      machine.
- [ ] AC-2 With the seed's real fixtures nothing else changes: the CLI-03c machine tests that do not
      concern arrival pass unmodified.
- [ ] AC-3 The imports test no longer relies on a one-line regex; a seeded violation split over two
      lines fails it (shown red in the report, then removed).
- [ ] AC-4 A `tools/art` test pins that the strips' frames are identical with and without stills (on
      synthetic images).
- [ ] AC-5 Each answered row of the table is applied; the unanswered rows keep CLI-03c's behaviour. A
      test per applied constant or fixture (services count, entry delay, report blocks, decor spots,
      building positions, no overlap of tap targets at 375 × 812).
- [ ] AC-6 design/11 *Hubs* carries the decided lines, "proposed, the owner's eye" kept only on
      unanswered rows; nothing else in design/11 changed (`git diff` restricted to the section).
- [ ] AC-7 (Mac, only if the Playwright check is kept: see below) the loop is walked on 375 × 812 and a
      desktop window: town → gate → entry → room → leave → report → town, outpost, travel back, defeat,
      and the arrival case (arrive on the gate anchor: no offer). Real output in the report; no
      screenshot leaves the Mac (D-73: shapes only may be described).
- [ ] AC-8 `pnpm --filter @grimworld/app test`, `lint`, `typecheck`, `build`, `prettier --check client
      indexer`, the art pipeline's tests pass. CI green.

## Verification

- On the VPS: the commands of AC-8, and the art pipeline's tests (`tools/art`, its README says how).
- On the Mac, if the browser check is part of the lot: `pnpm --filter @grimworld/app dev`, then the
  Playwright script against it. Start and stop the dev server inside one foreground command and kill
  only its recorded process group. The atlas with the stills is built on the Mac (`GRIMWORLD_ART_OUT`),
  never committed. The VPS has the pack but runs no browser for this lot.
- A change of constants or fixtures only needs the Mac check once, at the end.

## Open question for the project manager

**Commit `client/app/verify-cli03c.mjs` (a Playwright check) with `playwright-core` as a named
development dependency of `client/app`, or keep it local?**

- The previous orchestrator recommended committing it: the loop's visual check is then repeatable by
  CLI-03 and later lots, and `docs/reports/CLI-03a-browser-check.md` and CLI-03c's run stop being
  one-off recipes. It stays untracked on the Mac's CLI-03c worktree today.
- Cost: one development dependency (named in the pull request, `pnpm-lock.yaml` changes), a script CI
  does not run (it needs a real Chrome and the atlas), so it can rot; it would be renamed
  `verify-hubs.mjs` and kept out of `pnpm test`.
- The brief proceeds on **commit it** unless the project manager says otherwise before the lot starts.
  If the answer is "keep local", AC-7 is run with the dependency added for the run only and reverted
  before the commit, as CLI-03a did.

## Review

Review by a model other than the implementer, on the pull request's head (`review`, Sonnet, if the
implementer is Opus; `review-opus` if Sonnet). No audit (D-177: the owner sees the lot), unless the
implementer adds a dependency beyond `playwright-core` or touches a path outside the allowlist, in which
case the orchestrator decides.

## Rules of this run

- Nothing of the pack leaves the Mac or the VPS pack folder (D-73).
- Foreground only. Wait for CI in the foreground. Never merge unless prompted with the exact line.
- `gh` is not logged in on the Mac: a Mac thread commits and pushes; the pull request is opened from
  the VPS.
- Pull request: title `[<model>] CLI-03d hubs follow-up`. The body names every dependency added, lists
  the rows of the table applied and those left at their default, and says "Audit: none (D-177)".

## Report

`REPORT.md` as in `docs/briefs/COMMON.md` §7: the summary and the pull request's URL; the files changed;
which rows of the table were applied (with the owner's answer) and which stayed default; the red-then-
green of AC-3; the Playwright run with its commands and real output; the commands refused by the
profile; deviations, escalations, open questions.
