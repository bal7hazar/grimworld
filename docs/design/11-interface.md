# 11 — Interface

> **Changed by [ADR-0006](../architecture/ADR-0006-chunked-maps.md)**: the room view becomes a camera following the adventurer on a large map, with pinch and pan; the layout zones below are unchanged.
>
> Status: **Draft v0.2** — sizes are initial values, to be settled by the client spike
> (SPK-6) on real phones. v0.2: played actions sent in batches, what the player sees of them (D-133, DES-21).

## Rules

| # | Rule |
|---|---|
| I-1 | **Designed for a phone held in portrait, used with one thumb.** Desktop is the same interface with more room around it |
| I-2 | **One tap, one action**, and the result is drawn at once. The chain catches up behind |
| I-3 | **Nothing on screen speaks of the chain** (pillar 7) |
| I-4 | **Everything the rules use is visible**: facing, arcs, ranges, activation in progress, recharges, who is awake |
| I-5 | **A mistaken tap must be hard to make and cheap to notice**: an action cannot be undone once played, sent or not |
| I-6 | Touch targets are at least 40 points wide |
| I-7 | The screen is still between two actions: no animation that is not information, idle animations apart |

## Screen in an instance, portrait

```
┌──────────────────────────────┐
│ ♥ 312/480   ⚡ 18/25    ☰    │  status: health, energy, menu
│ [bleeding 4] [stance 2]      │  conditions and effects, with ticks left
├──────────────────────────────┤
│                              │
│                              │
│           the room           │  9 × 17 hexes, whole room visible
│        (hex grid, actors)    │
│                              │
│                              │
├──────────────────────────────┤
│ target: Shaman lv 7  ♥ ▓▓▓░  │  selected target, its activation if any
├──────────────────────────────┤
│ [1] [2] [3] [4]    ↻ turn    │  skills 1–4, turn
│ [5] [6] [7] [8]    ⏸ wait    │  skills 5–8, wait
│ (a)(b)(c)(d)   queue: 3 ▸▸▸  │  belt, queue
└──────────────────────────────┘
```

| Zone | Height | Content |
|---|---|---|
| Status | ~10% | Health, energy, adrenaline for Vanguards, conditions and effects with their remaining ticks |
| Room | ~58% | The whole room, never scrolled |
| Target | ~6% | The selected actor: caste, level, health, what it is activating and in how many ticks |
| Actions | ~26% | Skill bar, belt, turn, wait, queue. Within reach of the thumb |

## Acting

| To | Do | Feedback before acting |
|---|---|---|
| **Move** | Tap a free tile | The path is drawn, with its cost in ticks. Tiles where the path would be interrupted are marked |
| **Attack** | Tap a goblin in range | The arc you would strike from is shown: front, flank or back |
| **Approach and attack** | Tap a goblin out of range | Path to the best reachable tile, then the attack |
| **Use a skill** | Tap the skill, then the target or tile | Range and area are highlighted; tiles out of line of sight are greyed |
| Use a skill on self | Tap the skill twice | — |
| **Turn** | Tap ↻, then a neighbouring tile | The three tiles you would cover |
| **Wait** | Tap ⏸ | — |
| **Inspect** | Long press on anything | Caste, level, statistics, skills known, state |
| Cancel a selection | Tap outside | — |

### Confirmation (I-5)

| Action | Default |
|---|---|
| Move, attack | Played on the tap |
| Skill | Played when the target is tapped: the skill tap was the first step |
| Anything that would end in an obvious loss: walking into a trap seen, leaving a room while engaged, starting an activation that a goblin in range can interrupt | A warning mark on the preview; still one tap |
| Leaving the instance, travelling back | Asked twice |

A setting turns on "tap twice to confirm" for every action.

## The queue

A **planned queue** only: the steps of a path to a far tile, not yet walked. Actions already
played are never shown as queued ([02-core-loop](02-core-loop.md#planned-queues-and-played-batches-d-133)).

| | |
|---|---|
| What is queued | The steps of a path the adventurer has not walked yet |
| Shown as | Ghost markers on the room and a counter |
| Walked | One step at a time, drawn as it is played; each step walked is played and cannot be cancelled |
| Stops by itself | When a rule says so ([02-core-loop](02-core-loop.md#the-planned-queue-and-its-stop-conditions)): the remaining steps fade out and the reason is said in one line ("a skirmisher noticed you") |
| Cancel | Tap the counter: the steps not yet walked fade out |

## What the rules need to show

| Rule | Shown as |
|---|---|
| Facing | A wedge on the actor's tile, pointing to its front tile |
| Arcs of the selected goblin | Its back tile and rear-side tiles tinted when you can reach them |
| Asleep / alerted / engaged / fleeing | A small mark over the goblin |
| Activation | A ring that fills tick by tick around the caster, with the skill's icon; on the adventurer too |
| Interruptible now | The ring is highlighted when one of your ready skills can interrupt it |
| Recharge | The skill icon darkened, with the number of ticks left |
| Not enough energy | The icon's cost in red |
| Flank, critical | A distinct hit mark and number colour |
| Remains, veins, chests, collectors | Icons on tiles; remains glow by the best thing a goblin of that caste can drop |
| Entrances | Arrows on the border, with the name of what is behind when known |

## The chain, unseen

| Situation | The player sees | Never |
|---|---|---|
| Actions played, not yet sent or not yet confirmed | Nothing: they are drawn as they are played | A spinner per action, a counter of actions waiting |
| A batch sent more than 3 seconds ago and not yet confirmed | A discreet "saving…" in the status zone | "Pending", "transaction", "batch" |
| The batch filling is full while the one sent is not confirmed ([02](02-core-loop.md#when-a-batch-leaves)) | "saving…" stays; the next tap waits until it goes | A dialog |
| A reward being drawn (loot, identification, brewing) | The reveal animation, which lasts as long as needed | A loading bar |
| The chain disagrees with what was drawn (a rewind) | The room snaps to the true state; the actions dropped fade out as ghost markers along where they went; one line: "the world corrected itself". The selection is cleared; nothing is replayed | An error code, a count of actions lost |
| Network down (the node cannot be reached) | Play goes on until the batch filling is full; then "Connection lost. Your expedition is safe." Play is suspended until the actions are confirmed | Anything about nodes or fees |
| Before a reward is drawn, a gate or travelling back | The action starts at once (the walk to the remains, the gate animation); the draw waits behind it for the actions before it to be confirmed | A wait before the tap is taken |
| The app closes with actions not sent | At the next launch the instance is read, then opens where the player left it; the actions still valid are sent behind it. Until the instance is read, the room is shown still, with "saving…" | — |
| The window is about to reach a part of the map not yet read (after a launch on another device) | The step waits with "saving…" until it is read | A loading bar |
| …and the chain moved meanwhile (the adventurer played on another device) | The room shows the chain's state; the actions whose results are unchanged stay; if some were dropped, one line: "your last steps were lost" | Where they were lost, or why |
| The same adventurer played on another device while a batch was being sent | The room shows the chain's state; the actions still valid on it stay, the others fade out; one line: "the world corrected itself" only if something was dropped | A conflict dialog |
| Actions that could not be saved after the retries (a batch that failed down to one action) | The room snaps to the true state, with one line: "your last steps were lost" | An error code |
| A reorg undid more than the actions being saved: a reward, a gate, the instance itself | The true state, whatever it is: an earlier moment of the instance, another instance, or the hub; a reward gone from the inventory. One line: "the world corrected itself" | An explanation of why |
| First launch | Name of the adventurer, profession, play | Wallet, address, key, gas, sign, token, network, block, mint |

## Hubs

Hubs have no geometry (D-03): they are **illustrated screens with places to tap**.

```
┌──────────────────────────────┐
│ Town A            gold 1 240 │
├──────────────────────────────┤
│                              │
│    illustration of the town  │   present adventurers walk by
│    with its buildings        │   (decor; tap one to inspect)
│                              │
├──────────────────────────────┤
│ Guild    Smith     Enchanter │
│ Trainer  Armorer   Alchemist │
│ Market   Vault     Gate  ▸   │
└──────────────────────────────┘
```

| Screen | Content |
|---|---|
| Guild | Board: quests, contracts, the day's Rifts; rank and merit; titles |
| Trainer | Skills to buy; **build editor**: 8 skills, attributes, belt |
| Smith, armorer, enchanter, alchemist | One task per screen, the item on the left, the result on the right |
| Market | Search, cheapest lot per size, average price; my lots |
| Vault | Shared storage; move to and from the pack |
| Gate | The map: where to go, what the build is, a last check before leaving |

The build editor shows, before leaving, what the chosen bar cannot do (no heal, no
condition removal, nothing at range): a reminder, never a block.

## Desktop

| | |
|---|---|
| Layout | The portrait column in the centre, unchanged. Left panel: character sheet and build. Right panel: combat log and target details |
| Mouse | Click is tap; right click is inspect; hover shows previews |
| Keyboard | `Q W E A S D` for the six directions, `1`–`8` skills, `Z X C V` belt, `Space` wait, `R` turn, `Esc` cancel |
| Window narrower than 700 points | The phone layout |

## Accessibility

| | |
|---|---|
| Colour | Never the only carrier of a meaning: arcs, rarity and states also have a shape or a letter |
| Text | Scales with the system setting |
| Motion | Idle animations can be turned off, which also saves battery |
| Time | No action is ever timed by the clock |

## Open

| # | Question |
|---|---|
| UI-1 | Room of 9 × 17: large enough for the fights we want? Decided with SPK-6 and the first playable |
| UI-2 | Landscape on phones: supported, or portrait only? Recommendation: portrait only for the first version |
| UI-3 | Combat log on phones: a drawer, or only the last line? |
