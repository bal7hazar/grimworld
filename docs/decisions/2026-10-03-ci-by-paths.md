# D-206: CI runs a test job only when its files changed

| | |
|---|---|
| Decided by | project manager, 2026-10-02, on the owner's request; recorded by the project manager |

## Decided

A test job runs only when its files changed. A docs-only PR runs no test. One always-running summary job keeps `gh pr checks` answering. Quiver: ARC-18 (#52, merged). hexx-cairo: LIB-04g (#100, merged). grimworld: FND-18, in progress.

## What would reverse it

The owner's word, or a missed regression traced to a skipped job.

## Sources

quiver #52, hexx-cairo #100.
