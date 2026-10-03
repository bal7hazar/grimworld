# D-200: class-size rule of ENG-01 §1.3, two named exceptions; the goblin hit accepted

| | |
|---|---|
| Decided by | project manager (class sizes) and owner (the hit's cost), 2026-10-02; recorded by the project manager |

## Decided

50 % of the 81,920-felt class limit stays the default (ENG-01 §1.3). Two named exceptions:

- ExecutorLibrary: at most 80,420 felts (the protocol limit less 1,500 of margin; 80,122 measured at f1a33f4).
- TickLibrary: at most 75 % (61,440 felts).

They keep room for CBT-05b and ENG-07. Growth beyond them needs a new decision. The cost-lowering design lot (only the carrier's sheets across the call) is how room is won back.

The owner accepted the goblin weapon hit through ExecutorLibrary, about 2.1M L2 gas (2,103,191 measured at f1a33f4), for the MVP. Their words: "Ok pour le coup de Goblin à 2M1 de gas" (OK for the goblin hit at 2.1M gas).

## Why

No rework fits the executor under 50 % (D-198). The measured hit feeds R-2 and goes with ENG-07.

## What would reverse it

The class sizes: a later measure, or the owner. The hit's acceptance: the owner's word.

## Sources

D-198, D-184, ENG-01 §1.3, CBT-05a brief.
