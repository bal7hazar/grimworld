# D-183: The build-root rule for class hashes

| | |
|---|---|
| Decided by | project manager, 2026-10-02, aligned with Slingfall; recorded by the project manager |

## Decided

CI's checkout path is the reference root. A class hash is pinned from CI only, with the root recorded beside it. Declared classes come from CI's artefact of a push to main (FND-12).

## Why

SPK-13b: the absolute build path enters the closure type names of Sierra ids (upstream cairo#10358, fix #10359 not yet in a released Scarb), so class and Sierra hashes depend on the build root. Gas and felt sizes do not.

## What would reverse it

A released Scarb carrying cairo#10359: first adoption is a pin event for every declared class, then the rule can relax.

## Sources

[#283](https://github.com/bal7hazar/grimworld/pull/283) (SPK-13b, c97e2fc), [#290](https://github.com/bal7hazar/grimworld/pull/290) (OPERATIONS, 6662cb6), [#291](https://github.com/bal7hazar/grimworld/pull/291) (FND-12, f1a0b41)
