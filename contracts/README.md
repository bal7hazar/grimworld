# contracts

The Dojo package `grimworld` (Scarb 2.13.1, `dojo` 1.8.0, Cairo 2.13; the pins are in
`.tool-versions` at the root, run `scripts/setup-toolchain.sh` if a tool is missing).

## Layout

```
src/
  systems.cairo     thin contracts: entrypoints, access control, nothing else
    systems/persistent.cairo, ephemeral.cairo
  components.cairo  game logic, reusable across systems
  store.cairo       single access point to the models
  models.cairo      state and invariants per model
    models/persistent.cairo, ephemeral.cairo
  types.cairo       enums dispatching to elements
  elements.cairo    one file per content behaviour
  helpers.cairo     pure functions: bitmap, packer, seeder, math
  registries.cairo  content as data
tests/              snforge tests, each with a gas budget (docs/CAIRO.md §2)
```

Cairo has no `mod.cairo`: a module is a file, and its submodules sit in the folder of the same
name, which appears with the first file that goes in it (`models/persistent/adventurer.cairo`).

## The two domains

Two Dojo namespaces, never mixed ([ADR-0001](../docs/architecture/ADR-0001-execution-layer.md),
*Keeping the exit open*):

| Domain | Namespace | Holds |
|---|---|---|
| Persistent | `grimworld` | adventurer, inventory, progress, registries |
| Ephemeral | `grimworld_instance` | instance state |

The rule: **no model mixes fields of both domains**. The ephemeral domain reads a snapshot of the
adventurer taken at entry and writes to the persistent one only through the results interface.

## Build and test

From the repository root, always through the build lock:

```
scripts/lock.sh sozo build --manifest-path contracts/Scarb.toml
scripts/lock.sh sozo test --manifest-path contracts/Scarb.toml
```

`sozo` runs the `scarb` and `snforge` of `.tool-versions`. Every test carries
`#[available_gas(l2_gas: N)]` with `N = ceil(1.05 × measured)`.
