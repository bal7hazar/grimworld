# D-181: Merges without the owner after a review

| | |
|---|---|
| Decided by | owner, 2026-10-02; recorded by the project manager |

## Decided

After a review by another model that does not oppose it and green checks, a pull request is merged without the owner: by its thread on the orchestrator's `Merge the PR: review <verdict> at <sha>`, or by the coordinator that started the review, with the standard's exact command. A merge without review goes through the thread only.

## Why

The owner was the bottleneck of every merge; the review by another model is the gate (D-175, D-177), and the exact command pinned to a sha cannot merge anything else.

## What would reverse it

The owner withdrawing the rule, or a merged PR that a review should have stopped (then the owner merges again).

## Sources

nexus #58, #59 (the Nexus project's issues; not in this repository)
