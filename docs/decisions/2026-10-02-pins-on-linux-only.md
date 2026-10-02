# D-182: Pins generated and checked on Linux only

| | |
|---|---|
| Decided by | project manager, 2026-10-02; recorded by the project manager |

## Decided

A pin of a hash, of class bytes or of a size is generated and checked on Linux only. The Mac runs tests; a Mac/Linux difference is reported with both figures.

## Why

SPK-13 found the class hash differing between Mac and VPS on the same CASM; one platform must be the reference.

## What would reverse it

A fixed build root that makes the platforms agree (D-183), proven by a measurement on both.

## Sources

OPERATIONS ([#280](https://github.com/bal7hazar/grimworld/pull/280), merged 4669d98)
