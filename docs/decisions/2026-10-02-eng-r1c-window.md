# D-189: ENG-R1c takes the first free window

| | |
|---|---|
| Decided by | project manager, 2026-10-02; recorded by the project manager |

## Decided

ENG-R1c takes the first window with no lot in `contracts/logic/src` and never delays ENG-05 or ENG-07.

## Why

R-2 (D-184) needs ENG-07's measurement; ENG-R1c must not move it.

## What would reverse it

A change of the order of ENG-05, ENG-07 or of the lots touching `logic/src`.

## Sources

[#288](https://github.com/bal7hazar/grimworld/pull/288) (dea790f)
