# The owner's review of ARC-06's reference model

| | |
|---|---|
| Reviewed | `bal7hazar/quiver` at `bd701ff`: `packages/quest/src/models/definition.cairo`, `store.cairo`, `models/index.cairo`, `events/`; [#19](https://github.com/bal7hazar/quiver/pull/19) |
| By | The owner, 2026-09-29, recorded by the `[Opus 5.5]` project manager |
| Follows | D-143 (docs/CAIRO.md §7) |

## The owner's remarks

1. **The `logic/` folder disappears.** What it holds goes to the layers of CAIRO.md §7: stored
   structs and their packing to `models/`, value types to `types/`, what belongs to no entity to
   `helpers/`, still scoped in traits.
2. **Emitting a model's event is optional**: when the indexer does not need a piece of
   information, its model is not tracked and its writes emit nothing. The choice is made where the
   information is consumed, so a package must let its consumer leave a model untracked; known at
   compile time, at no cost on the path of a write.

## What follows

- ARC-07 (both packages as 0.2.0) starts with these two points in its brief. Its brief states how
  a consumer of a package chooses which models are tracked, and the cost of the choice; the
  project manager checks it before the launch.
- The first lot of ARC-07 is shown to the owner, as ARC-06 was.
- CAIRO.md §7 is amended by the same pull request as this file.
