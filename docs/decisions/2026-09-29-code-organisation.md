# The organisation of Cairo code — the owner's rule, 2026-09-29 (D-143)

| | |
|---|---|
| Decided by | The owner, on reading the code of `quiver` |
| Written in | docs/CAIRO.md §7 and §8 |
| Binds | Every Cairo repository of the programme: the game, `quiver`, `hexx-cairo` |

## What the owner found

The rewrite of the Arcade packages in `quiver` kept their behaviour and met their cost caps,
but not their shape: a folder `logic/` of files full of free functions
(`definition_new`, `held_remove`, `batch_merge`, `schedule_is_active`), raw felts and
bit offsets where Arcade has models, types, events, a store, and methods scoped in traits.
The game's contracts follow the layering in part (models with `StorePacking`, a store)
but keep free functions in their helpers and packing.

The project manager checked costs, audits and publication, and did not check the shape of
the code against the owner's patterns. That is corrected by §8 of docs/CAIRO.md, a lens
every audit now applies.

## The rule, in short

1. The layering of Arcade: `models/`, `events/`, `types/`, `helpers/`, a store, a component
   or systems.
2. Functions scoped in traits and impls, with short names: `Definition::new()`, not
   `definition_create()`.
3. Every stored entity is a model, a struct that converts into its storage and, when the
   indexer tracks it, into its event.
4. The store emits the event of a tracked model on each write, as a Dojo world does, without
   the world's cost at run time.

## What follows (decided by the project manager under D-128)

| # | Task | Why this order |
|---|---|---|
| 1 | **ARC-06**, in `quiver`: the mechanism of §7 (model, storage, tracked event, store), its cost measured against a hand-written write, and a **reference implementation on one model**, Opus 5.5, audited by `[GPT-6-Sol]` on the organisation lens and `[GPT-6-Astra]` on cost | Everything else is written after it. The quiver track is idle: its slot is free |
| 2 | **The owner reviews that one model** before anything else is reworked | It is the owner's taste. A day of rework on a pattern the owner then rejects costs more than one look |
| 3 | **ARC-07**, in `quiver`: `quiver_quest` and `quiver_achievement` rewritten on the pattern, as **0.2.0**. Behaviour, tests, gas caps and storage layouts kept, unless the pattern needs another layout, measured | 0.1.0 is published and stays on the registry: a publication cannot be undone. No consumer uses it yet: the game embeds the packages at GLD-02, which will depend on 0.2.0 |
| 4 | **ENG-R1**, in the game: the contracts written so far brought to §7 (helpers and packing scoped, the tracked models emitting through the store) | After the pattern; tasks running now (ENG-03, ENG-04) scope their functions from today and adopt the store's events when ARC-06 lands |
| 5 | `hexx-cairo` | The mirror of `hexx` is already methods on types (`Hex::distance_to`); the engine taken over and the extensions follow §7 from the next task. It stores nothing: the model and event rules do not apply |

## Review by the owner (2026-09-29)

The owner accepts the rule and the order above. **The owner reviews the next iterations of
code on the pattern**: the reference model of ARC-06, then the first lots of ARC-07 and
ENG-R1, until there is nothing left to say on the work. From then the project manager
checks the organisation lens itself and the tracks go on without the owner's review.
