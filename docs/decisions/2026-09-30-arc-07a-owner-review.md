# D-167: the owner's review of `quiver_quest` 0.2.0 (ARC-07a); unit tests beside their code

| | |
|---|---|
| Reviewed | `bal7hazar/quiver` at `24fb49e`: `packages/quest/src/store.cairo`, `models/`, `README.md` ([#20](https://github.com/bal7hazar/quiver/pull/20)) |
| By | The owner, 2026-09-30, recorded by the `[Fable 5.1]` project manager |
| Follows | D-143, D-147 |

## The owner's verdict

**The structure is clean and close to the target the owner had in mind.** Two remarks:

1. **Why are there new models, and models gone, against the Arcade repository's** (`Definition`,
   `Progression`, `Completion`, …)? The answer is written, not guessed: `quiver` commits a short
   mapping, Arcade's models and events → `quiver_quest` 0.2.0's, one line each with the reason
   (D-131's API at gate A-G1, D-135's bounds, the native storage without a world, the indexer's
   needs), and what was dropped and why. The owner reads it and may reverse a difference.
2. **Unit tests live in the same file as the code they test**, so that whoever changes the
   implementation sees its tests; not in separate files, unless a performance reason is shown.
   The owner's remark holds for **every Cairo library of every project**: raised to the Overseer
   for the other project managers.

## Decided

- **ARC-07a is accepted.** ARC-07b (`quiver_achievement` 0.2.0) and ENG-R1 (the game's contracts
  on the pattern) start. The owner is shown ENG-R1's first lot (the first on the game's code) and
  ARC-07b (the first under the test rule); after those, the project manager checks the
  organisation lens itself unless the owner asks for more.
- **The rule of tests, docs/CAIRO.md §2**: the unit tests of a module (its functions, its packing,
  its checks, its oracles) are in that module's file, under `#[cfg(test)] mod tests`; what needs a
  deployed contract or several packages (integration, the gas benchmarks of an entrypoint, the
  parity tables) stays in `tests/`. Applied from the next lot in every repository of the project
  (ARC-07b, ENG-R1, CBT-02c, the library's M1-T3 onward); existing files move their tests when a
  lot touches them, not by a migration of their own. A performance reason to keep a test apart is
  written above it. The gas tooling (`scripts/gas_budgets.py`, `scripts/gas.py`) must read budgets
  in `src/` as well: checked by the first lot that applies the rule.

## What would reverse it

The owner's reading of the mapping (a model brought back); a measured compile-time cost of tests in
`src/` that the owner judges too high.
