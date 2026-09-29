# D-150: what the game's slots take while the engine chain waits

| | |
|---|---|
| Asked by | `[Opus 5.5]` game orchestrator, after ENG-06's merge (#120): ENG-05 and ENG-02 wait for the map library's release (LIB-05), ENG-07 for ENG-05, ENG-R1 for ARC-07 |
| Decided by | `[Opus 5.5]` project manager, 2026-09-29, under D-128 |

## Decided

1. **First slot: DES-04, then CBT-01, pulled forward from Phase 2.** CBT-01 freezes the combat
   interfaces (actor stats, the skill, effect and caste schemas); ENG-07's tick needs them, and they
   need neither the library nor quiver. But the effect schema is DES-04's closed catalogue and its
   resolution order, still `todo`: **DES-04 is written first** (the orchestrator with Opus 5.5,
   design lens), as a design document in its own pull request, then CBT-01 freezes the interfaces
   from it. Of DES-06 CBT-01 takes the **shape** of a caste sheet only; its values stay DES-06's.
   A rule DES-04 cannot settle from design/03 and design/04 is decided by the project manager
   (D-128) and reported to the owner.
2. **Second slot: FND-08, the burner's funder on a public network** (FND-05's escalation, the
   game's STATUS): a service of the game behind the `Funder` port, tested on the local node; needed
   before any play on Sepolia, so before M2. Security lens with `[GPT-6-Astra]` (it moves funds,
   test tokens only). A deployment to Sepolia, if the task needs one, follows OPERATIONS §7's grant.
3. **Then `set_build`** (design/03's build, CBT-08's first part), after CBT-01; it also measures the
   belt's worst case (D-148).
4. **Not now**: the Rift board and `enter_rift`, loot and the Fate actions. They are Phases 4 and 5
   and would freeze interfaces the tick has not yet exercised.

## What would reverse it

The map library's release landing first (ENG-05 and ENG-02 take the slots back); DES-04 raising a
question only the owner can answer (it waits; the slot takes `set_build`'s preparation or FND-08).
