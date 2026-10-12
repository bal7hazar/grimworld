# CLI-05 — The combat UI: skill bar, belt, targeting, telegraphs, conditions, combat log

**Status: CLI-05a and CLI-05b can start against this brief; CLI-05c and CLI-05d wait for CLI-05a;
CLI-11d waits for CLI-05c, CLI-05d and track game's SEED-02.** Written by a thread of track
CV on 2026-10-12. This lot is the design and the split into lots; it writes no code. Nothing here
decides a game rule: the chain decides, client/sim mirrors it, and the combat UI shows both (mandate
`docs/briefs/ORCH-client-visual.md` §6). Every decision below has a default, the reason for it, and
what would reverse it. None needs a reserved act of the owner.

## Agent

Proposed per lot in §10. No pin, gas table or budget is involved: every lot is client-side. The
sandbox lots run on the VPS or the Mac; the chain lot needs `starknet-devnet` and the built classes,
so it runs where `scripts/with-node.sh` works (both machines, FND-09).

## Context

### CLI-04 is done in substance

PLAN.md's CLI-04 is "Client simulation of combat + parity vectors". client/sim now computes a whole
played segment on the real world, with every class it calls ported and checked against track game's
vector tables:

- CLI-02g-A (#428), the segment's codecs and the class seam, on RV-02's `segment2.jsonl` (#425);
- CLI-02g-B1 (#431), the goblin's load, the shared tick functions and `SignedTrait`;
- CLI-02g-C (#443) and CLI-02g-D (#444), the body operations, the effect entry and the trap path, on
  RV-03a's tables (#440);
- CLI-02g-E (#450), the action class `ActionTrait::act`, on RV-03b's `act.jsonl` (#447);
- CLI-02g-F (#459), the tick class `TickLibrary::ticks` with the goblin AI, on RV-03c's tick table
  (#456);
- CLI-10j (#461) runs the batch preview on that native tick class, and CLI-02h (#471) follows R-44.

So CLI-04's two halves, the combat simulation and its parity vectors, exist. What PLAN's CLI-04
named and is not there is BAL-01's headless runner, which is its own row. **Proposed status cell for
CLI-04:** "done in substance by CLI-02g-A to F (#428, #431, #443, #444, #450, #459), on track game's RV-02 and RV-03
tables; CLI-10j (#461) runs the preview on it (CLI-05 brief, 2026-10-12)". This lot writes it.

### What main has

**The rules, in client/sim** (`client/sim/src/`):

- The action is `Action` (`segment/serde.ts`): `move`, `turn`, `wait`, `attack{entity}`,
  `skill{slot, target}`, `item{slot, entity}`, `interact{tile}`, with `Target = {tile, value}`. The
  bar has 8 slots (0–7) and the belt 4 (0–3). client/app's copy is `PlayAction`
  (`client/app/src/preview/actions.ts`).
- A skill's or an item's target is checked by `aim` (`action.ts`), from `addressing` (`executor.ts`):
  an attack skill addresses a foe within the weapon's range; any other skill takes its first entry's
  addressing and the skill's range; a potion its one entry's. Reach is `reach` (`window.ts`):
  distance and line of sight.
- The refusals are `Illegal` (`segment/serde.ts`): `Clock`, `Absent`, `Knocked`, `Turned`,
  `Instant`, `Empty`, `Belt`, `Recharging`, `Energy`, `Adrenaline`, `Target`, `Reach`, `Trap`,
  `Kind`, `Blocked`. `act` (`action.ts`) checks a skill in this order: `Empty`, `Kind`, `Instant`,
  `Recharging`, `Adrenaline`, `Energy`, `Target` or `Reach`, `Trap`; an item: `Empty`, `Belt`,
  `Target` or `Reach`. A refusal leaves the state unchanged.
- Addressings `SELF 0`, `FOE 1`, `ALLY 2`, `TILE 3` (`executor.ts`, `target`); shapes `SINGLE`,
  `RING_1`, `DISC_1`, `DISC_2`, `DISC_3` (`window.ts`, `shapes`). The contracts refuse `DISC_2` and
  `DISC_3` (`'carrier: area after the MVP'`) and allow `DISC_1` on potions only
  (`contracts/logic/src/types/effect.cairo`, `assert_carrier`). **So a skill of the MVP is `SINGLE`
  or `RING_1`, and only a potion can be a `DISC_1`.**
- R-44 (D-271, D-272, CARRIER-01 #460, client/sim CLI-02h #471): a carrier's non-`TRAP` entries never
  mix `TILE` with `FOE` or `ALLY`, and no `SELF` entry comes before the addressed one. The contracts
  refuse such a skill when it is written; client/sim throws `NotMirrored` on one.
- A member's activation is `act_slot`, `act_target`, `act_tile`, `act_deadline`
  (`segment/words.ts`); a goblin's is `act_slot` (0–3 a caste skill, 254 recovering, 255 none),
  `act_target`, `act_deadline` (`segment/goblin.ts`), with no tile. Recharges are deadlines per bar
  slot; conditions are deadlines (Bleeding, Poison, Burning, Crippled, Knocked down); held effects are
  four slots on a member and one on a goblin (`Held`: carrier, charges, potion, deadline, rank), with
  `MAX_CLOCK` for an effect that lasts by charges only (BLOCK, oils).
- A run returns `Ran = {words, ground, done}`; `Done` holds `played`, `illegal`, `heavy`, `changed`
  (the goblins with records) and `undo`. **There is no per-hit record**: no damage, arc or effect is
  output by client/sim.
- `client/sim/src/index.ts` exports `loadGoblin`, `reach`, `range`, `shapes`, `Illegal`,
  `NotMirrored`, `runSegment` and the codecs. It does **not** export a member's `load`
  (`segment/words.ts`), `target`, `condition`, `kind`, `addressing` or `aim`.

**The chain's events.** `BatchPlayed`, `Refused`, `GoblinKilled` (entity, caste, tile, `by` always
0), `ChunkRevealed`, `Defeated`, `InstanceClosed` (`contracts/ephemeral/src/events.cairo`).
**There is no hit, damage or condition event.** `extractOutcome` (`client/app/src/preview/trace.ts`)
reads them from a transaction's trace into `Played`.

**The client** (`client/app/src/`):

- `input/keys.ts`: `BINDINGS` reserves, on the instance screen, `1`–`8` (`Digit1`–`Digit8`) for the
  skills, `Z X C V` (`KeyZ`, `KeyX`, `KeyC`, `KeyV`) for the belt, `Space` and `R`, with no command.
  `CHAIN_BINDINGS` gives `Space`, `R`, `B` and `N` commands in the chain mode. `ZOOM_CHARS` and
  `matches()` make a `Digit*` code whose character is `+`, `-` or `=` a zoom: **AZERTY's `6` key,
  `Digit6`, prints `-` and zooms out** (TASKS, from review t-0100 of #346).
- `sandbox/`: fixed worlds, rules stood in by `sandbox/placeholders.ts`, imported only through
  `sandbox/wiring.ts` and `sandbox/loop/machine.ts` (`sandbox/imports.test.ts`). The adventurer's
  sheet is `ADVENTURER` (`sandbox/fixtures/hubs.ts`): Wren, Vanguard, a bar of five named skills and
  three empty slots, a belt of Healing potion ×3 and Antidote ×1, health, energy and adrenaline as
  "PLACEHOLDER until CLI-04". The bar and belt appear only as text, in `SheetSummary`
  (`sandbox/loop/screens.tsx`).
- CLI-03l's HUD: `sandbox/loop/Hud.tsx` and its pure model `sandbox/loop/hudModel.ts` (portrait,
  health, energy, the Vanguard's adrenaline), from the chrome's `Bar`, `Portrait` and `Icon`
  (`chrome/Chrome.tsx`). CLI-03l left to CLI-05 the conditions row, the target zone, the skill bar and
  belt, the activation ring, the hit marks and the combat log's look.
- `render/`: `ViewState` (`render/view.ts`) and `overlayPlan` / `drawOverlay` (`render/shapes.ts`)
  draw the sight's dimming, the selected goblin's rear-side and back arcs, path ghosts and the
  selected tile. No range, area or activation is drawn.
- `chain/`: CLI-11a–c play Move, Wait, Turn and Attack behind `?chain=`; `ChainController`,
  `ChainPanel` (whose `actionText` already writes `skill`, `item` and `interact`), `createStages`
  with the mirror (`mirrorOf`, `predict` in `preview/`), the simulation and the sent stage.
  `MirrorWords` (`preview/reconcile.ts`) is the members' and goblins' packed words: the only
  client-side source of health, conditions, effects, recharges and activations.

**The art.** The atlas (`tools/art/manifest.toml`, built into the git-ignored `tools/art/out/`,
never committed: D-73) has, for the UI: the chrome's papers, buttons and ribbons, `round_blue` and
`square_blue` (the small buttons, packed but not loaded by the client), and CLI-03l's bars, portraits,
`icon_sword` and cursors. It has **no skill, potion or condition icon, no tile highlight and no hit
effect**; the pack's `Particle FX/` is not in the manifest (design/10 _Icons_: "the pack has few skill
icons").

**Track game.** SKILL-01 (#472) added `Hub.buy_skill`. SEED-02 (running) adds an activation skill, a
trap skill and a REGENERATION skill and potion to the seed. `scripts/devnet_deploy.py --build full`
(OPS-01b, on main) leaves the bar empty and the belt at healing potion ×2 today; once SEED-02 lands
it puts four skills on the bar and a belt of healing potion ×2 plus a REGENERATION potion. The
registry's `Skill` and `Item` records hold **no name** (`contracts/logic/src/models/index.cairo`),
and none is planned (Q-1).

## 1. Scope

**In CLI-05:** the instance screen's combat elements, in the sandbox first, then in the chain mode:
the skill bar, the belt, targeting, the activation ring (telegraphs), conditions and held effects,
the target zone and the combat log. Design/11's _Acting_ and _What the rules need to show_ are the
specification; this brief fills what they leave open.

**Not in CLI-05:** the hub's build editor and trainer (CLI-06); design/11's "approach and attack" by
a far tap, already the sandbox's; the hit effects of the pack's `Particle FX/` (an art lot, §8); the
optimistic display, rewind and recovery (CLI-03, design/02); a game rule of any kind.

## 2. The skill bar

### 2.1 Layout and slots

**Default.** Eight slots in two rows of four, under the room, as design/11's portrait screen draws
them, with `Wait` and `Turn` at the rows' right. Each slot is at least 44 CSS px square (I-6's 40
points, with the bar's frame), so the two rows fit a 375 px wide phone with the turn and wait
buttons. On desktop the same column is used (design/11 _Desktop_). A slot shows, from the top:

- the skill's icon, or its placeholder (§8);
- its key, `1`–`8`, in a corner, on desktop only;
- its cost: energy as a figure; adrenaline as `icon_sword` and the number of strikes;
- its state (§2.2).

An empty slot is a dimmed frame with nothing in it; a tap or its key does nothing and says nothing.

**Why.** Design/11 draws exactly this; two rows of four keep each slot thumb-sized on a phone.

**Reversed if** the owner's look at the sandbox capture (CLI-05c) asks for one row of eight on
desktop, or the phone's first real test (D-199 suspended it) shows the rows too low.

### 2.2 A slot's state

**Default.** A slot is in exactly one state, decided in this order, which is the order `act`
refuses a skill (so the state shown is the refusal the player would get). "Not now" is checked
first, as `act` checks `Knocked` before `Empty` (`client/sim/src/action.ts`, `act`); Empty is listed
first below only because an empty slot looks the same in either order:

| State               | When                                                        | Shown as                                                                   |
| ------------------- | ----------------------------------------------------------- | -------------------------------------------------------------------------- |
| Empty               | no skill in the slot                                        | dimmed frame                                                               |
| Not now             | the adventurer is knocked down, or activating another skill | the whole bar dimmed; while activating, the ring on the activating slot    |
| Activating          | this slot's skill is the activation in progress             | a ring filling around the slot, and the ticks left as a figure             |
| Wrong weapon        | an attack skill whose weapon is not held (`Kind`)           | the icon greyed, a crossed-sword mark                                      |
| Recharging          | the slot's recharge deadline is not reached (`Recharging`)  | the icon darkened, the ticks left as a large figure (design/11)            |
| Short of adrenaline | `Adrenaline`                                                | the strikes figure in red, underlined                                      |
| Short of energy     | `Energy`                                                    | the energy figure in red, underlined (design/11: "the icon's cost in red") |
| Ready               | none of the above                                           | full colour                                                                |

`Instant` (one instant skill per tick) is not a slot state: it depends on the batch, and the
refusal before the batch says it (§4.4). Colour is never the only carrier (design/11
_Accessibility_): red figures are also underlined, the greyed weapon slot has its mark, recharges
show a number.

The figures come from client/sim, never from client/app's own arithmetic: the energy cost of a slot
is client/sim's `energy` (`action.ts`, with Fieldcraft and a glyph's discount), and the ticks left
are read from the stored deadline and the clock by one function of the combat model (§10, CLI-05a).
The two kinds of deadline are read differently, as client/sim reads them:

- **A recharge** is running while `clock < recharge` (`act`'s `Recharging` check, `action.ts`). The
  slot shows `recharge − clock`, and is ready when the clock reaches the deadline.
- **An activation** shows `act_deadline − clock`, the ticks until it resolves.
- **A condition or held effect** is held while `clock <= deadline` (`held` in `segment/tick.ts`;
  `degeneration` and `effect_pips` read it the same way). Its chip shows `deadline − clock + 1`, the
  ticks it still acts, so it reads 1 on its last tick, and it disappears once the clock passes the
  deadline (§6.1).

**Why.** Following `act`'s order means the bar never promises a skill the action class refuses.
Using client/sim's cost keeps one source of truth (mandate §6).

**Reversed if** client/sim's `act` changes its order (the state order follows it), or the owner
wants several states shown at once (for example recharging and short of energy).

### 2.3 Keys, and the AZERTY question (D-284)

**Decided by the project manager (D-284, 2026-10-12), on this brief's proposal.** No digit key ever
zooms. `Digit1` to `Digit8` are the skills in an instance and the services in a hub, on every
layout. Zoom keeps `Minus` and `Equal` by code, AZERTY's `)` and the numeric keypad's minus. D-284 is
reversed if a layout leaves zoom with no reachable key.

**Default, as built by CLI-05b.**

- Skills are read **by position**: `Digit1`–`Digit8` and `Numpad1`–`Numpad8`, on the instance screen
  only. The belt is `KeyZ`, `KeyX`, `KeyC`, `KeyV` by position (AZERTY's `W X C V`), as `keys.ts`
  already reserves them.
- **A digit key never zooms.** Removing `ZOOM_CHARS`' exception in `matches()` is not enough: the
  zoom row comes before the skills row in `BINDINGS` and its `{ key: "-" }`, `{ key: "+" }` and
  `{ key: "=" }` matches are read by character, so `Digit6` with key `-` would still zoom. **The
  guard moves into the zoom row's character matches:** a press whose `code` is a `Digit*` never
  matches them. So AZERTY's `6` key, which prints `-`, is skill 6 in an instance and service 6 in a
  hub.
- **Zoom keeps a key on every layout**, by position as well as by character: zoom in is the key `+`,
  the key `=`, the code `Equal` and `NumpadAdd`; zoom out is the key `-` (not from a digit code), the
  code `Minus` and `NumpadSubtract`. On AZERTY, zoom out is then the `)` key (code `Minus`, where
  QWERTY has `-`) or the numeric keypad's `−`; zoom in is `=` (code `Equal`).
- The key help (`?`) lists the skills and belt keys on the instance screen, and the zoom keys as
  "`+` / `−` (the keys right of `0`)".
- Modifiers, repeat and composition stay refused, as today.

**What it changes of CLI-03k.** design/11 _Desktop_'s row "Keyboard, outside combat (CLI-03k)" is a
project manager's decision of 2026-10-03; D-284 amends its zoom and service keys. CLI-05b edits that
row in its own PR, citing D-284, and rewrites the two tests of `client/app/src/input/keys.test.ts`
that held the old behaviour: "AZERTY: the key printed - (Digit6) zooms out, the unshifted digit row
keeps its services" and "the combat keys are reserved: nothing on an instance, listed as reserved".

**Why.** CLI-03k already reads every position key by `event.code`, so the digits follow. Making
the zoom yield only "in combat" would give one key two meanings on one screen depending on state,
which design/11 _Desktop_'s "each key the tap or button it stands for" and `keys.test.ts`'s "every
bound key has one meaning per screen" both refuse. The code `Minus` is the same physical key as
QWERTY's `-`, so zoom stays where a QWERTY player expects it and gains a key on AZERTY.

**Reversed if** a layout leaves zoom with no reachable key (D-284), or the owner, on a real AZERTY
keyboard, wants `-` to zoom (then the instance's skill 6 moves to `Numpad6` only).

### 2.4 Taps

**Default.** A tap on a ready slot **arms** it: the slot is outlined and targeting starts (§4). A
second tap on the armed slot: for a skill addressed to `SELF`, plays it; for any other, disarms it.
A tap on another slot arms that one instead. A tap on a slot that is not ready says its state in one
line ("Recharging: 3 ticks", "Not enough energy") and arms nothing. A long press (right click on
desktop) inspects the skill: name, kind, costs, activation, recharge, range, what it does in words.

**Why.** Design/11 _Acting_: "Tap the skill, then the target or tile"; "Use a skill on self: tap
the skill twice"; I-5's "the skill tap was the first step".

**Reversed if** the "tap twice to confirm" setting (design/11 _Confirmation_) is built: it then adds
a confirmation after the target, not before.

## 3. The belt

**Default.** Four slots in one row under the bar, `Z X C V` on desktop, at least 44 px each:

- a slot with a potion shows its icon (placeholder, §8) and its **count** as a figure in the corner;
- a slot whose count is 0 shows the icon greyed and `0` (the potion is still the slot's: the belt is
  fixed for the expedition, design/02 and D-141);
- a slot with no item is a dimmed frame, like the bar's empty slot.

**Using one.** A tap or the key arms it like a skill (§2.4). A potion addressed to the adventurer
(`SELF`, or `ALLY` while playing alone) is played by a second tap or a second press; one addressed
to another target is aimed as a skill is (§4). A belt use costs 1 tick and has no energy or recharge
(design/04, `action.ts`'s `item`), so the only states are "has some", "none left" (`Belt`) and
"not now" (knocked down or activating).

**Why.** design/11 draws the belt as four buttons `(a)(b)(c)(d)`; the count is what the player
spends. Keeping an emptied slot visible tells the player what they brought.

**Reversed if** the owner wants an emptied slot to vanish, or the belt to grow beyond four (a
contract change: `Illegal.Belt` and the 4 lanes of the belt word).

## 4. Targeting

### 4.1 By addressing

The addressing is **read from client/sim**, never re-derived: `addressing` (`executor.ts`) gives, for
an attack skill, a foe at the weapon's range, and for any other carrier its first entry's target and
the skill's or potion's range. R-44 guarantees that this first entry is the one the action is aimed
by. CLI-05a exports `addressing` and the `target` constants from `client/sim/src/index.ts` (new
exports).

**Default:**

| Addressing | Armed, the map shows                                                                   | The target is chosen by                                                                 | The action                                              |
| ---------- | -------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------- | ------------------------------------------------------- |
| `SELF`     | the shape around the adventurer (a `RING_1` skill: the six tiles)                      | a second tap on the slot or its key, or a tap on the adventurer                         | `skill{slot, target: {tile: false, value: own entity}}` |
| `FOE`      | the range; every goblin in reach marked as a target                                    | a tap on a marked goblin; or `F` / `Shift+F` to cycle them, nearest first, then `Enter` | `skill{slot, target: {tile: false, value: entity}}`     |
| `ALLY`     | the range; every member in reach marked (alone: the adventurer only)                   | a tap on a marked member; the slot twice when alone                                     | as `FOE`, on the member's entity                        |
| `TILE`     | the range; the shape under the pointer (desktop) or under the last tapped tile (phone) | a tap on a tile in reach; the first tap previews, a second tap on the same tile plays   | `skill{slot, target: {tile: true, value: tile}}`        |

A potion is aimed the same way, and played as `item{slot, entity}`: `Item` carries an entity, and
the potion's own entry decides where it lands (`action.ts`, the item arm).

`Esc`, a tap outside the room or a tap on the armed slot (for a non-`SELF` skill) disarms. `Esc`'s
order (design/11 _Desktop_) becomes: the key help, the confirmation, an inspection, **an armed slot**,
the planned walk, the selection.

**Why.** design/11 _Acting_ gives taps for each case. A `TILE` skill is played on a second tap
because a phone has no hover to show the area first (I-5: "a mistaken tap must be hard to make");
a `FOE` goblin is already a precise target. `F` already cycles places on these screens (CLI-03k); in
an instance with a slot armed it cycles targets instead, so no new key is taken.

**Reversed if** the owner finds the `TILE` second tap slow (it then plays on the first tap, with the
area shown on hover only on desktop), or a target kind beyond these four appears.

### 4.2 By shape

**Default.** Armed, the map shows the tiles a carrier would touch, by its entries' shapes:

- `SINGLE`: the target's tile, outlined;
- `RING_1`: the six tiles around the centre, tinted, the centre not;
- `DISC_1` (potions only): the centre and its six neighbours, tinted.

Actors the shape takes (the carrier's filter: foes or allies) get a small target mark. `DISC_2` and
`DISC_3` are not drawn: the contracts refuse them (§Context), so no content has one; if one ever
reached the client, client/sim's `near` would not compute it either and the slot would be shown as
"not available" (§4.4).

**Why.** Design/11: "Range and area are highlighted". The filter mark tells the player who is hit,
since there is no friendly fire (design/19 §2.3).

**Reversed if** the contracts allow `DISC_2` or `DISC_3` (FX-21 decides their line of sight first).

### 4.3 The range shown

**Default.** The tiles at distance ≤ range **and** in line of sight from the adventurer are tinted;
the tiles at distance ≤ range but out of sight are drawn greyed with a thin cross (design/11 _Acting_:
"tiles out of line of sight are greyed"). Range 1 shows the six neighbours. In the chain mode, the
test is client/sim's `reach` on the board the mirror builds (`segmentBoard`); in the sandbox, the
placeholders' `distance` and `tilesInSight` stand in, as every rule there does.

**A TRAP skill** narrows the tint further: a tile in reach is tinted only if client/sim's `spot`
(`trap.ts`) finds a place for the trap there (walkable, no actor on it, its chunk's ground with a free
slot); the others in reach are greyed like tiles out of sight.

**Why.** It is the exact rule `aim` applies (`Illegal.Reach` is distance and line of sight), and for
a trap the rule `act` adds (`Illegal.Trap` when `spot` finds nothing), so a tinted tile is a tile the
action class accepts.

**Reversed if** the line-of-sight rule changes (design/04, D-174): the drawing follows `reach`.

### 4.4 What is refused before the batch

**Default.** In the chain mode, when a skill or item action is confirmed, the controller runs the
mirror on the planned actions **plus** the new one (`predict`, as `createStages` already does at
each input). If the mirror stops at the new action with `done.illegal` set, the action is **not
added**: the slot stays armed and one line says why. If the mirror cannot say (`NotMirrored`, for
example after a reveal), the action is added and the simulation stage decides, as CLI-11 does today.

The lines, in words the player reads (I-3: nothing about the chain):

| `Illegal`                              | Line                                                                           |
| -------------------------------------- | ------------------------------------------------------------------------------ |
| `Knocked`                              | "You are knocked down."                                                        |
| `Instant`                              | "Only one instant skill between two ticks."                                    |
| `Empty`                                | (nothing: an empty slot is never armed)                                        |
| `Belt`                                 | "None left."                                                                   |
| `Kind`                                 | "Needs its weapon." (an attack skill only: `interact` is never offered, below) |
| `Recharging`                           | "Recharging: N ticks."                                                         |
| `Energy`                               | "Not enough energy."                                                           |
| `Adrenaline`                           | "Not enough adrenaline."                                                       |
| `Target`                               | "Not a valid target."                                                          |
| `Reach`                                | "Out of reach."                                                                |
| `Trap`                                 | "A trap cannot go there."                                                      |
| `Clock`, `Absent`, `Turned`, `Blocked` | not reachable from a skill or an item tap; logged as a parity record if seen   |

**`interact` is not available.** On main the mirror and the contract both refuse every `interact`
with `Illegal.Kind` (`client/sim/src/segment.ts`, `run`; `contracts/logic/src/types/action.cairo`,
`act`). The client offers no interaction until a game lot implements it: a tap on a gate, a chest or a
lever shows "Not available yet." and adds nothing to the batch, so `Kind` never reaches the player
from an interaction.

A slot whose skill client/sim cannot mirror (`NotMirrored`, `unported.MIXED`: a carrier R-44 refuses)
is shown as "not available" and cannot be armed. The contracts refuse such a skill when it is
written, so on main this cannot happen; the state exists so that the screen never guesses.

In the sandbox, the bar's states (§2.2) and the range (§4.3) are the only refusals; the placeholders
grow no rule beyond them.

**Why.** The mirror is already run at every input on the planned actions; the check is that same
run once the new action is appended (§7.2's cost), and it gives exactly the refusal the chain would
give. Refusing before the batch keeps a batch from
stopping on `Stop.Invalid` for a mistake the client could see (I-5).

**Reversed if** the per-input run proves too slow on a phone (then the slot states and the range
alone refuse, and the rest is left to the simulation stage), or design/11's "tap twice to confirm"
setting asks for a warning instead of a refusal.

## 5. Telegraphs: activations in progress

**Default.**

- **A goblin activating** (`act_slot` 0–3): a ring around its tile that fills tick by tick from the
  activation's start to its deadline, the skill's placeholder icon over its head, and the **ticks
  left** as a figure on the ring. Its target is shown by a thin line from the goblin to the target
  actor, ending on a target mark. A skill with a `RING_1` entry centred on itself (a shout) tints
  its ring of tiles faintly. In the target zone (§6.2): "Overhead Smash — 2 ticks, on you".
- **Interruptible now** (design/11): the ring is highlighted when a ready slot of the bar holds a
  skill that can interrupt (an `INTERRUPT` entry, or a Knocked down condition) and the goblin is in
  its reach.
- **A goblin recovering** (`act_slot` 254): nothing on the map; "recovering" in the target zone.
- **A stored deadline already passed** (a lapsed activation, design/19 §5.2) is read as none, as
  views and the client must.
- **The adventurer activating**: the same ring around the adventurer, the slot's ring on the bar
  (§2.2), and the target line to its target or the tinted area on its tile. **In the sandbox only:**
  in the chain mode the adventurer's activation resolves within its own action and is never at rest
  between inputs (§9).

**Why.** design/11 _What the rules need to show_: "a ring that fills tick by tick around the
caster, with the skill's icon; on the adventurer too", and the interruptible highlight. The line to
the target answers "on whom", which the ring alone does not.

**Reversed if** the owner's look at the capture finds the target lines cluttered with several
goblins activating (they then show only for the selected goblin).

## 6. Conditions, held effects and the target zone

### 6.1 Conditions and effects

**Default.** A condition or held effect is a **chip**: a letter on a coloured ground, and the ticks
left as a figure. The letter carries the meaning; the colour repeats it.

| Shown                                                     | Letter                | Figure                                                              | Read from                              |
| --------------------------------------------------------- | --------------------- | ------------------------------------------------------------------- | -------------------------------------- |
| Bleeding                                                  | `B`                   | ticks left                                                          | the condition's deadline               |
| Poison                                                    | `P`                   | ticks left                                                          | the condition's deadline               |
| Burning                                                   | `F`                   | ticks left                                                          | the condition's deadline               |
| Crippled                                                  | `C`                   | ticks left                                                          | the condition's deadline               |
| Knocked down                                              | `K`                   | ticks left                                                          | the condition's deadline               |
| REGENERATION                                              | `R`                   | ticks left, and `+n`/`−n` pips                                      | the held effect (`effect_regen`)       |
| BLOCK                                                     | `▣`                   | charges left (`×2`), and ticks left unless it lasts by charges only | the held effect's charges and deadline |
| Any other held effect (ARMOR, EVADE, MOVEMENT, a stance…) | the carrier's initial | ticks left, or charges                                              | the held effect                        |

- **On the adventurer**: the chips sit in the status band, under the bars (design/11's
  `[bleeding 4] [stance 2]` row), conditions first, then effects, in slot order.
- **On a goblin**: on the map, a goblin with any condition shows its letters only, small, under its
  feet (at most three, then `+`); the figures are in the target zone. A goblin's one held effect shows
  there too.
- The ticks shown are `deadline − clock + 1`: a condition or effect is held while
  `clock <= deadline` (§2.2), so a chip reads 1 on its last tick and never 0.
- An effect that lasts by charges only (`MAX_CLOCK`) shows its charges and no ticks.
- Knocked down also lays the actor's sprite flat (rotated) until the pack has the pose (design/10
  _Missing animations_).

**Why.** design/11 asks for "conditions and effects, with ticks left" in the status zone, and
_Accessibility_ asks for a letter or shape beside colour. Figures on every goblin would crowd the
map; the target zone has room for them.

**Reversed if** the owner wants the goblins' figures on the map, or an icon set for conditions comes
(§8): the icon then replaces the letter, the figure stays.

### 6.2 The target zone

**Default.** Between the room and the bar (design/11's _Target_ zone, about 6 % of the height): the
selected actor's portrait or caste name, its health as a small bar with figures, its mark (asleep,
alerted, engaged, fleeing), its chips with figures, and its activation in words ("Overhead Smash — 2
ticks, on you"). Nothing selected: the zone is empty, not collapsed, so the bar does not move.

**Why.** design/11 draws it; keeping the zone's height fixed keeps the bar under the thumb.

**Reversed if** the owner's look at the capture prefers the zone to collapse when empty.

## 7. The combat log

### 7.1 What a line says

**Default.** One line per thing that happened, in plain words, newest last:

- the adventurer's action: "You used Cleave on the skirmisher", "You drank a Healing potion",
  "You waited", with the arc of a weapon hit or attack skill ("from behind: critical", "from the
  flank") as the arc preview showed it before the action;
- a health change per actor and per action: "The skirmisher lost 31 health", "You gained 12 health";
- a condition gained or ended: "You are bleeding (5 ticks)", "The runt is no longer poisoned";
- an effect held or ended: "Brace: 2 blocks", "Brace ended";
- an activation started, resolved or interrupted: "The hobgoblin starts Overhead Smash (3 ticks)",
  "You interrupted the shaman";
- a trap triggered, a goblin killed, the adventurer defeated, the instance closed;
- a refusal before the batch (§4.4), in its own muted style.

A goblin is named by its caste, with a number when two of the same caste are awake ("the second
runt").

### 7.2 Where a line comes from

Neither client/sim nor the chain gives per-hit records (§Context). Track game confirmed (2026-10-12)
that no combat event is planned: an event would cost gas (D-144) and change ENG-01's frozen events.
So the log is computed on the client, from the mirror, at two grains.

**Default.**

1. **Per action: the difference of two states.** The words after action `k` are the end of the
   mirror's run on the batch's first `k` actions. This is sound because `SegmentTrait::run`
   (`client/sim/src/segment.ts`, `run`) plays each action and then its `n` ticks inside the same
   loop turn (`ticks(world, rules, n)`), so the state after the loop's turn `k` depends only on the
   state before the batch and actions 1 to `k`. A run on a prefix therefore ends where the full run
   stood after action `k`. **The prefixes are cached:** appending an action leaves the earlier
   prefixes unchanged, so an input adds one run, the run on the whole batch, which `createStages`
   already makes; §4.4's check on the planned actions plus the new one is that same run. The
   comparison gives the action's own lines: health, conditions, held effects, activations,
   `killed`, `defeated`.
2. **Per tick: hits attributed by replay.** Inside an action, the goblins act during its ticks. To
   say who struck whom, the model replays each call of the tick class **one tick at a time**:
   - the mirror's run is made through a recording wrapper of the native `Classes`, which keeps each
     `ticks` call's input (`TicksCall`: words, content, board, level, ground, `n`);
   - each recorded call is replayed as `n` calls of client/sim's native `tickTicks` with `n = 1`,
     chained (the words and ground out of one are the input of the next); `tickTicks` is
     deterministic on the words, board, ground and `n`;
   - for each tick, the change of each actor's health, minus what step 3 gives it (its regeneration
     and its conditions, read with client/sim's `degeneration` and `effect_pips`), is attributed to
     the goblin that acted in that tick on it: an activation resolved, or an attack (its recovery or
     recharge set). Its arc is client/sim's `arc` from the positions before the tick, which gives
     the flank and critical marks of a goblin's hit;
   - ticks played on the fast path (no goblin in the window: no class call) need no attribution;
   - a tick the replay cannot attribute (two goblins that both struck one actor in one tick, or a
     change no goblin's act explains) gets one line naming the goblins together, and a record
     `grimworld.log-unattributed` with the call's input, so the case goes to track game with
     figures.
3. **The segment's records.** `Done` gives where the batch stopped (`played`, `illegal`, `heavy`);
   the ground before and after (`Ran.ground`: a trap placed, or gone from its tile) gives "a trap
   was placed" and "a trap was triggered".
4. **The chain's events in the trace.** `extractOutcome`'s `Played` gives `GoblinKilled`,
   `ChunkRevealed`, `Defeated` and `InstanceClosed`, and the stop. When the sent stage reconciles,
   the lines of the actions the chain played are **confirmed**; if the chain differs, the chain
   wins: the predicted lines of the dropped actions are struck and one line says "The world
   corrected itself" (design/11 _The chain, unseen_).

A line is predicted (drawn in a lighter tone, with no mark that speaks of the chain) until it is
confirmed.

**Cost per input.** With the prefixes cached, an input costs the one mirror run `createStages`
already makes, plus `n` one-tick replays for each tick-class call of the new action (`n` is the
action's ticks, at most the batch's weight left). The one-tick calls are the same work as the
recorded call, split. **Not measured yet:** CLI-05a measures, on the tick table's heaviest row
(`contracts/logic/vectors/`), the time of one input with and without the replay, and reports both.

**Why.** Diffing decoded words and replaying native ticks needs no new rule and no contract change,
and it reads exactly what the mirror and the chain agree on.

**Reversed if:**

- the measured cost of an input with the replay is above one frame (16 ms) on the Mac's browser:
  the replay then runs after the input is drawn, and the action's lines appear when it ends;
- `n` one-tick calls do not give the words of one call of `n` on some row (CLI-05a's acceptance):
  that row goes to track game with its figures, and the replay is off until it is answered;
- the per-action prefix runs and the full run disagree (the soundness above is wrong): the log
  falls back to one line per batch;
- track game ever adds per-hit records or combat events: the log reads them instead.

### 7.3 How many lines, and where

**Default.** The log keeps the **last 100 lines** in memory for the instance, lost on a reload and
cleared on entering a new instance. On desktop it is the right panel (design/11 _Desktop_), showing
the last 12 lines and scrolling back. On a phone, the last line sits under the target zone, and a tap
on it opens a drawer with the rest (design/11's UI-3, answered here as its recommendation for the
client; the design document's row stays open for the owner).

**Why.** 100 lines cover several fights without growing; the phone keeps its room for the map.

**Reversed if** the owner answers UI-3 otherwise, or a fight's log routinely passes 100 lines.

## 8. Art

The pack has no skill, potion or condition icons (design/10 _Icons_). Every element below uses what
the atlas has, or a named placeholder drawn by code, so the screens work before an icon set exists.

| Element                                       | Asset                                                                                                                                              | Placeholder (no asset, or without the atlas)                                                                                     |
| --------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------- |
| A bar or belt slot's frame                    | `square_blue` (packed; added to the client's loaded entries, regular and pressed)                                                                  | a bordered square in the chrome's colours (the plain look)                                                                       |
| A skill's icon                                | none in the pack                                                                                                                                   | **a monogram**: the skill's two initials in Pixelify Sans, on a ground by skill kind (attack, spell, stance, shout, trap, other) |
| A potion's icon                               | none in the pack                                                                                                                                   | **a flask outline** drawn by code, filled by the potion's effect (heal, regeneration, other), with its initials                  |
| Adrenaline cost                               | `icon_sword`                                                                                                                                       | `⚔`, as CLI-03l does                                                                                                             |
| Energy cost                                   | none (CLI-03l found no lightning icon)                                                                                                             | the figure alone, in the energy colour                                                                                           |
| Condition and effect chips                    | none in the pack                                                                                                                                   | **a letter chip** (§6.1)                                                                                                         |
| The bar's and belt's backing                  | `wood` (the chrome's nine-slice)                                                                                                                   | the dark panel                                                                                                                   |
| The target zone                               | `paper_dark`; the pack's `Swords` plates are not packed yet                                                                                        | the dark panel                                                                                                                   |
| The target's health bar                       | CLI-03l's `Bar`, small, with a red fill (`bar_small` with a new `bar_small_fill_health` entry: the pack's small fill, already red, not recoloured) | the plain bar                                                                                                                    |
| The combat log                                | `paper` for the desktop panel                                                                                                                      | the plain panel                                                                                                                  |
| The activation ring, range, area, target line | drawn by code in the overlay, like the arcs                                                                                                        | the same                                                                                                                         |
| Hit marks and numbers                         | not in this brief: the pack's `Particle FX/` is not in the manifest                                                                                | none: the log carries the numbers                                                                                                |

The `Swords` plates, the pack's state glyphs made for skill buttons (`4`, `5`, `ActionPoint` in
regular, pressed and disabled) and `Particle FX/` are the natural assets of a later art lot; this
brief does not need them. **Decided:** a monogram, a flask and letters, because they stay readable
at 44 px and need nothing from the pack. **Reversed when** an icon set is commissioned (design/10's
plan: about 40 skills, 5 conditions, 12 potions) or packed: the icon then replaces the placeholder,
slot by slot, with no layout change.

## 9. Where it runs

**Default.**

| Lot     | The sandbox (`?combat=fight`, fixed data)                                                                                                                                           | The chain mode (`?chain=`)                                                                                                                                      |
| ------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| CLI-05a | nothing visible (the model and its tests)                                                                                                                                           | nothing visible                                                                                                                                                 |
| CLI-05b | the new keys, in the key help                                                                                                                                                       | the same keys, given to the chain screen with no command yet                                                                                                    |
| CLI-05c | the bar in every state of §2.2, the belt with a count, an emptied slot and an empty slot, the chips, the target zone, the log with fixed lines; arming a slot and choosing a target | nothing                                                                                                                                                         |
| CLI-05d | the range, the areas, the activation rings and target lines, the goblins' letters, on the same fixture                                                                              | nothing                                                                                                                                                         |
| CLI-11d | unchanged                                                                                                                                                                           | the bar, belt and targeting on the deployment's adventurer, refusals before the batch, the goblins' telegraphs and the chips from the mirror, the log from §7.2 |

**The adventurer's own activation is shown in the sandbox only.** In the chain mode it is never at
rest: `SegmentTrait::run` plays an action's `n` ticks in the same loop turn as the action
(`client/sim/src/segment.ts`, `run`), so an activation started by the adventurer has resolved before
the next input, and an activation that does not fit the weight is not kept (`Done.heavy`). A goblin's
activation does rest between inputs (its deadline passes the batch's end), so the goblins' telegraphs
are shown in both modes. The adventurer's ring could be seen in the chain mode only if a later lot
draws an action's ticks one by one (§7.2's replay gives the states); none is planned.

**The sandbox's fixture** has one home, `client/app/src/combat/fixture.ts` (new, CLI-05a); CLI-05c's
`?combat=fight` reads it, and `sandbox/fixtures/` is not touched. Wren keeps `ADVENTURER`'s bar
(Cleave, Shield bash, Charge, Taunt, Second wind, three empty slots), given costs, recharges and
kinds (Q-4); the belt as today plus an emptied slot. Wren is bleeding (4 ticks), holds a
REGENERATION, and holds a BLOCK effect with 2 charges and 6 ticks: Shield bash is given the BLOCK
entry in the fixture, so the chip comes from a skill on Wren's bar. A hobgoblin beside Wren
activates Overhead Smash on Wren (2 ticks left), a shaman casts Mend Kin on a runt, a skirmisher is
poisoned. The bar shows at once one slot ready, one recharging, one short of energy, one short of
adrenaline, one with the wrong weapon and three empty. Activating dims the rest of the bar (§2.2),
so a second state of the fixture has Wren activating Charge, for its own shot.

**In the sandbox, playing a skill** spends its placeholder costs, starts its placeholder recharge
and adds one log line; it applies no effect. These two placeholders join `sandbox/placeholders.ts`,
marked as the file's others are. The sandbox stays the default; `?combat=` changes only the fixture.

**Why.** The owner sees the whole UI on fixed data first, in every state, without a node, the way
CLI-03l's HUD was shown. The chain lot then changes only the source of the data.

**Reversed if** the owner wants the chain mode shown first, or the sandbox's placeholders start to
grow rules beyond costs and recharge (then the sandbox runs client/sim instead).

## 10. The lots

Each lot's commands are run from the repository's root, one at a time. On the VPS a Node run's heap
is capped as AGENTS.md says (measured peaks: client/app's tests 487 MB, client/sim's 701 MB); the
command is written here without that prefix.

### CLI-05a — the combat model, without a screen

**Profile:** `impl-opus`. Every figure must read exactly what client/sim stores.

**Allowlist:**

- `client/app/src/combat/` (new), each file with its unit test:
  - `state.ts`: the `CombatState` the screens read (the adventurer's bar with each slot's sheet,
    recharge and state, belt, gauges, activation, conditions and held effects; the goblins' health,
    mark, activation, conditions and held effect; the traps on the ground; the clock);
  - `fromWords.ts`: a `CombatState` from `MirrorWords`, the content and the ground. The `World` is
    built by client/sim's own loader, `loadWorld(words, indexSheets(content))` (`segment/world.ts`'s
    `world` and `segment/words.ts`'s `sheets`, exported below), never by client/app;
  - `bar.ts` (§2.2's state of a slot), `targeting.ts` (§4.1–§4.3: the addressing, the reach set, a
    TRAP skill's `spot` set, the shape's tiles, the actors marked), `refusal.ts` (§4.4's lines),
    `chips.ts` (§6.1);
  - `overlay.ts`: `CombatOverlay`, what the map draws (the range, its greyed tiles, the area, the
    target marks, the goblins' activations with their ticks and targets, the condition letters, the
    knocked-down actors), from a `CombatState` and the armed slot;
  - `record.ts`: the recording wrapper of the native `Classes` (§7.2);
  - `log.ts`: §7.2's lines (the cached prefixes, the one-tick replay and its attribution) and §7.3's
    100 lines;
  - `fixture.ts`: §9's fixed fight, both states;
- `client/app/src/render/view.ts`: one optional field, `ViewState.combat?: CombatOverlay`, nothing
  drawn;
- `client/sim/src/index.ts`, new exports only:
  - `segment/world.ts`: `world` as `loadWorld`, and the type `World`;
  - `segment/words.ts`: `load` as `loadMember`, `sheets` as `indexSheets`, the held-effect decoder
    `held(effects, slot)` as `heldEffect` (so that it does not collide with `segment/tick.ts`'s
    `held`), and the types `Member` and `Sheets`;
  - `executor.ts`: `addressing`, `target`, `filter`;
  - `action.ts`: `aim`, `energy`, `glyphs`, `weapon_required`, `belt_count`, `mixed`;
  - `body/member.ts`: `recharge` as `memberRecharge`;
  - `segment/tick.ts`: `held`, `degeneration`, `effect_pips`;
  - `trap.ts`: `spot`;
  - `combat.ts`: `condition`; `effect.ts`: `kind`;

  if another function proves needed to read a figure without re-deriving it, it is exported from
  its own file the same way and named in the report;

- `client/app/README.md`, a "Combat UI" subsection.

**Acceptance:**

- `fromWords` decodes the members and goblins of a row of RV-03c's tick table
  (`contracts/logic/vectors/`) to the health, conditions, held effects and activations client/sim's
  loaders give;
- every state of §2.2, each by a unit test, and the order of states equal to `act`'s refusals: for
  each `Illegal` a slot state names, a test runs client/sim's `actionAct` on the same words and gets
  that refusal;
- targeting: a `SELF`, a `FOE`, an `ALLY` and a `TILE` carrier, a `RING_1` and a `DISC_1` potion,
  each by a test; a tile out of sight is in the range's greyed set and refused by `aim` with
  `Reach`; a TRAP skill's tinted tiles are exactly those `spot` accepts, and an occupied tile in
  reach is refused with `Trap`;
- the ticks shown of a condition (`deadline − clock + 1`), of a recharge (`recharge − clock`) and of
  an activation, at the deadline and one tick before and after, each against client/sim's own reading
  (`held`, `act`'s `Recharging`);
- `log.ts`:
  - **the last prefix's words equal the full run's**, on every action of a batch of 10 built from
    the act and tick tables' rows;
  - the prefix cache is keyed by the base words and the action list: a changed base (a send, a
    reveal, a state read again) or an action removed empties it, and a test shows each;
  - for every row of the tick table, `n` chained calls of `tickTicks` with `n = 1` give the words
    and ground of one call with `n`; a row where they differ is reported to track game with its
    figures, not skipped;
  - a goblin's hit attributed to it with its arc, a kill, a condition gained and ended, an
    activation started and interrupted, a trap triggered; two goblins striking in one tick give the
    joint line and the `grimworld.log-unattributed` record;
  - the 101st line drops the first;
  - the measured time of one input, with and without the replay (§7.2), in the report;
- `pnpm --filter @grimworld/app test`, `pnpm --filter @grimworld/app lint`,
  `pnpm --filter @grimworld/app typecheck` and `pnpm --filter @grimworld/sim test` pass.

### CLI-05b — the combat keys (D-284)

**Profile:** `impl-sonnet`. §2.3 and D-284 fix the design.

**Allowlist:**

- `client/app/src/input/keys.ts`: new commands `skill{slot}` for `Digit1`–`Digit8` and
  `Numpad1`–`Numpad8` and `belt{slot}` for `KeyZ X C V` on the instance screen (the reserved rows
  become bindings); `ZOOM_CHARS`' exception in `matches()` removed and the digit guard put on the
  zoom row's character matches; zoom by the codes `Equal` and `Minus` and the characters; `cycle`
  and `go` kept on the instance screen for §4.1's targets;
- `client/app/src/input/keys.test.ts`: the two tests §2.3 names, rewritten, and the new cases;
- `client/app/src/editor/keys.test.ts`, only if the game's table it checks against changes;
- `client/app/src/sandbox/loop/KeyHelp.tsx`, the help's rows;
- `client/app/verify-keys.mjs`: **adds** AZERTY presses (it presses `Equal` and `Minus` today, no
  AZERTY case);
- `docs/design/11-interface.md`: the row "Keyboard, outside combat (CLI-03k)", its zoom and service
  keys as D-284 says, citing D-284.

**Acceptance:**

- AZERTY's `Digit6` with key `-` is skill 6 on the instance screen and service 6 in a hub; `Minus`
  with key `)` zooms out; `Equal` zooms in; `NumpadSubtract` and `NumpadAdd` still zoom;
- QWERTY's `-` and `=` still zoom; `Digit1`–`Digit8` and `Numpad1`–`Numpad8` give their skill,
  `KeyZ` to `KeyV` their belt slot, on the instance screen only;
- "every bound key has one meaning per screen" still passes;
- the screens that do not handle `skill` and `belt` yet ignore them (the sandbox's and the chain's
  instance screens), so nothing changes until CLI-05c;
- design/11's row matches the bindings and cites D-284;
- `pnpm --filter @grimworld/app test`, `pnpm --filter @grimworld/app lint`,
  `pnpm --filter @grimworld/app typecheck` pass; `pnpm --filter @grimworld/app verify:keys` passes
  where a browser runs.

### CLI-05c — the combat screen in the sandbox (DOM and plumbing)

**Profile:** `impl-opus`. A design for the owner's eye.

**Allowlist:**

- `client/app/src/combat/` (new files): `SkillBar.tsx`, `Belt.tsx`, `Chips.tsx`, `TargetZone.tsx`,
  `CombatLog.tsx`, `controller.ts` (arming, §2.4, §3, §4.1's choices and `Esc`) and its test;
- **the plumbing, this lot only:** `client/app/src/sandbox/Sandbox.tsx`, `sandbox/controller.ts`,
  `sandbox/session.ts` and their tests, carrying the `CombatState` and the armed slot from the
  screen to the session; `sandbox/wiring.ts`, for `toView` to set `ViewState.combat` from
  `combatOverlay` (CLI-05a) and to re-export §9's two placeholders;
- `client/app/src/sandbox/loop/InstanceScreen.tsx`, `Hud.tsx` (the chips row), `hudModel.ts` and its
  test;
- `client/app/src/sandbox/params.ts` and its test (`?combat=`);
- `client/app/src/sandbox/placeholders.ts` and its test (§9's two placeholders);
- `client/app/src/chrome/load.ts`, `Chrome.tsx`, `contrast.ts` and their tests (`square_blue`,
  `bar_small_fill_health`);
- `tools/art/manifest.toml` (`bar_small_fill_health`: the pack's small fill, `SmallBar_Fill.png`,
  which is already red, **not recoloured**), `tools/art/tests/test_build.py` (its set of `ui`
  entries), `tools/art/README.md` (its list of entries), and `tools/art/check` if it pins the
  entries;
- `client/app/verify-combat.mjs` (new) and its `package.json` script `verify:combat`. The script
  takes its options as **arguments**, not variables: `--shots <folder>` writes the shots there, and
  `--plain` serves no art (the plain look);
- `client/app/README.md`, its "Combat UI" subsection.

**Acceptance:**

- with `?combat=fight`, the bar shows each state of §2.2, the belt §3's three kinds of slot, the
  status band Wren's chips, the target zone the hobgoblin's activation when it is selected, and the
  log its lines;
- arming: a tap and a key arm a slot; a `SELF` skill plays on the second tap; `Esc` disarms in
  §4.1's order; a slot not ready says its line and arms nothing (controller tests with fakes);
- the shots, at 1440×900 and 375×812, of the screen at rest, a slot armed on a `FOE` skill, and
  Wren activating, with the art and in the plain look, written into the thread's library folder,
  never committed or posted (D-73), by these two commands:
  - `pnpm --filter @grimworld/app verify:combat --shots <the thread's library folder>`
  - `pnpm --filter @grimworld/app verify:combat --shots <the thread's library folder> --plain`
- `pnpm --filter @grimworld/app test`, `pnpm --filter @grimworld/app lint`,
  `pnpm --filter @grimworld/app typecheck` pass; `tools/art/.venv/bin/python -m unittest discover -s
tools/art/tests` passes where the venv exists;
- **for the owner's eye**: the shots go to the orchestrator, who shows them to the project manager.

### CLI-05d — the combat overlay on the map

**Profile:** `impl-opus`. Drawing on the map, for the owner's eye.

**Allowlist:**

- `client/app/src/render/shapes.ts` (`overlayPlan`, `drawOverlay`) and `render/renderer.ts`, with
  their tests: drawing `ViewState.combat` (the range and its greyed tiles, the area, the target
  marks, the activation rings with their ticks and target lines, the interruptible highlight, the
  goblins' letters, a knocked-down actor laid flat);
- `client/app/verify-combat.mjs`, its map shots, **only after CLI-05c has merged** (merge
  `origin/main`).

**Acceptance:**

- `overlayPlan` tests: a `FOE` skill's range with an out-of-sight tile greyed, a `RING_1` on self,
  a `DISC_1` potion, a goblin's ring at 3, 2 and 1 tick left, the interruptible highlight, a target
  line, three letters and a `+`;
- the shots of `verify:combat` (the two commands of CLI-05c) show the range and the hobgoblin's ring
  and line;
- `pnpm --filter @grimworld/app test`, `pnpm --filter @grimworld/app lint`,
  `pnpm --filter @grimworld/app typecheck` pass.

### CLI-11d — skills and belt items on chain

CLI-11's brief (§8) names this lot and left its allowlist and acceptance to CLI-05: they are here.

**Profile:** `impl-sonnet`. The design is fixed by this brief and CLI-11's. Interactions, which
CLI-11's brief put in CLI-11d, are left out: `interact` is not available on main (§4.4), and they
wait for a game lot that implements it.

**Waits for:** CLI-05c and CLI-05d merged, and track game's SEED-02. OPS-01b's
`scripts/devnet_deploy.py --build full` is on main; today it leaves the bar empty and the belt at
healing potion ×2, because the seed has no skill a player can learn and no REGENERATION potion (the
script's header). Once SEED-02 lands, `--build full` puts four skills on the bar (an attack, an
activation, a trap and a REGENERATION skill) and a belt of healing potion ×2 plus a REGENERATION
potion, their ids under the deployment JSON's `build` key. (CLI-11's brief §8 says "two heals and
one REGENERATION": the same belt.)

**Allowlist:**

- `client/app/src/chain/ChainController.ts`, `ChainScreen.tsx`, `ChainPanel.tsx`, `world.ts` and their
  tests: the combat screen's elements fed by `fromWords`, the skill and item actions, §4.4's refusal
  before the batch, and "Not available yet." on a tapped gate, chest or lever (§4.4);
- `client/app/src/chain/stages.ts` and its test, only to run the mirror through `record.ts`'s
  wrapper for §7.2 and to confirm the log's lines at the sent stage;
- `client/app/src/preview/reconcile.ts` and its test, only for `Prediction` to carry the run's
  `ground` (§7.2);
- `client/app/src/combat/names.ts` (new, Q-1) and its test;
- `client/app/src/chain/chain.node.test.ts`: a skill, a potion and a refused skill on the full build;
- `client/app/verify-chain.mjs`: a skill armed and played, the log after the send;
- `client/app/README.md`, the chain mode's subsection.

**Acceptance:**

- each input of §4.1 on the deployment's four skills and two belt slots gives its action
  (controller tests with fakes);
- a skill on recharge, a potion with none left and a target out of reach are refused before the
  batch with §4.4's line, and the batch is unchanged;
- a tap on a gate, a chest or a lever says "Not available yet." and adds no `interact` to the batch;
- after a send, the log's predicted lines are confirmed, or struck with "The world corrected itself"
  when the chain differs (a test with a fake trace);
- `names.ts` names every skill and item id of the deployment's `build` key from SEED-02's table
  (Q-1);
- `pnpm --filter @grimworld/app test`, `pnpm --filter @grimworld/app lint`,
  `pnpm --filter @grimworld/app typecheck` pass; `pnpm --filter @grimworld/app test:node:devnet`
  passes where the node runs (classes built, as AGENTS.md's `client/app` row says);
- `pnpm --filter @grimworld/app verify:chain` captures a skill played and the log.

### Order and parallel work

- **CLI-05a and CLI-05b run in parallel**: CLI-05a owns `client/app/src/combat/`'s model files,
  `render/view.ts`'s one field and `client/sim/src/index.ts`; CLI-05b owns `input/keys.ts`, its test,
  the key help, `verify-keys.mjs` and design/11's row. CLI-05b does not touch `client/app/README.md`.
- **CLI-05c and CLI-05d start when CLI-05a has merged, and run in parallel**: CLI-05c owns the DOM,
  all the plumbing (`Sandbox.tsx`, `sandbox/controller.ts`, `sandbox/session.ts`, `wiring.ts`),
  the sandbox's loop, the chrome and `tools/art/`; CLI-05d owns `render/shapes.ts` and
  `render/renderer.ts`. CLI-05a's `ViewState.combat` field is their contract: CLI-05c fills it,
  CLI-05d draws it. They share only `verify-combat.mjs`, which CLI-05c creates and CLI-05d extends
  only after CLI-05c's merge. CLI-05c also needs CLI-05b's commands to bind its keys: if CLI-05b has
  not merged, CLI-05c binds the taps first and the keys after merging `origin/main`.
- **Captures for the owner's eye:** CLI-05c and CLI-05d (`verify:combat`), shown together once both
  have merged. CLI-11d's capture is for the orchestrator and the project manager.
- **CLI-11d** starts when CLI-05c, CLI-05d and track game's SEED-02 have merged.

## 11. Open questions, each with its default

- **Q-1, skill and potion names on chain. Answered by track game (2026-10-12):** no names on chain,
  and none planned. SEED-02 adds to `contracts/seed/README.md` a table of the seed's skill and item
  ids with their names. **Decided:** CLI-11d's `client/app/src/combat/names.ts` (new) reads or copies
  that table, with "Skill 12" for an id it does not know. **Reverse:** the project manager wants
  names in the content.
- **Q-2, design/11's UI-3** (the log on phones). **Decided** for the client as §7.3 says; the design
  row stays open. **Reverse:** the owner's answer.
- **Q-3, per-hit lines and the arcs of goblins' hits. Answered by track game (2026-10-12):** no event
  route (D-144's gas; ENG-01's frozen events). **Decided:** §7.2's one-tick replay with the native
  `tickTicks` attributes the hits; a case it cannot attribute goes to track game with its figures.
  **Reverse:** track game adds per-hit records.
- **Q-4, the sandbox fixture's numbers** (costs, recharges, kinds of Wren's five skills). **Decided:**
  CLI-05a takes them from design/03's starter skills where named, and marks the rest as placeholders.
  **Reverse:** CNT-01's seed.

## 12. What CLI-05 needs from others

- **Track game:** SEED-02 (its skills, its REGENERATION potion and its table of names) for CLI-11d.
  No contract change and no event (Q-3). The one-tick replay's cases it cannot attribute, and any row
  where `n` one-tick calls differ from one call of `n`, go to track game with their figures.
- **The project manager:** D-284 (2026-10-12) decided the keys of §2.3. It amends the project
  manager's decision of 2026-10-03 recorded in design/11 _Desktop_ ("Keyboard, outside combat
  (CLI-03k)"); CLI-05b edits that row, citing D-284. Nothing else to decide for CLI-05a to CLI-05d.
- **The owner:** no reserved act. The owner's eye on CLI-05c and CLI-05d's shots, through the project
  manager.
