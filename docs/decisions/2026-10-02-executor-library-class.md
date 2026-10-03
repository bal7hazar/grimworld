# D-198: the executor in its own library class

| | |
|---|---|
| Decided by | project manager, 2026-10-02; the per-hit cost submitted to the owner; recorded by the project manager |

## Decided

CBT-05a's executor lives in its own library class (ExecutorLibrary), one library call per carrier.

## Why

No rework fits it in TickLibrary under the 81,920-felt class limit (measured: 111,571 felts with the executor in one class). The call's cost: a goblin weapon hit through the class costs 2,094,071 L2 gas, measured (2a49f47), against 784,188 in one class; a later design lot (only the carrier's sheets across the call, snapshot words split out of the actors) may lower it and is a PLAN row. The cost feeds R-2 (D-184), whose threshold waits for ENG-07.

## What would reverse it

A lot that fits the executor in one class, or the owner's word on the cost.

## Sources

[CBT-05a brief](../briefs/CBT-05a-executor.md), D-184, D-197
