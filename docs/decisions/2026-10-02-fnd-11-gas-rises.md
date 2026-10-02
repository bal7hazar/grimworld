# D-191: FND-11's gas rises on Scarb 2.20.1 accepted

| | |
|---|---|
| Decided by | project manager, 2026-10-02, under D-144; recorded by the project manager |

## Decided

FND-11's gas rises on Scarb 2.20.1 are accepted: the cause is the compiler (D-180), the tick benchmarks fall, and no single call on the expedition path is near a limit (costliest first `enter` 9,488,400, 23.7 % of the 40M batch bound). The further rises of `create`, `leave`, `travel_back`, `create_adventurer`, `travel` (+2.5 to +4.7 %) are accepted on the same ground.

## Why

D-144 lets the project manager accept a rise on the expedition's path when the design or the compiler explains it.

## What would reverse it

A call found crossing the per-transaction cap or the batch bound, or a later compiler undoing the rise (re-measure).

## Sources

[#293](https://github.com/bal7hazar/grimworld/pull/293) (FND-11; open when this was written)
