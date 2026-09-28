# contracts

The game's Starknet contracts: plain Cairo 2.19 (Scarb 2.19.4, snforge 0.61), **no Dojo**
([ADR-0007](../docs/architecture/ADR-0007-native-starknet.md)): there is no world, no `sozo`, no
Torii and no namespace, so no `dojo` package or `dojo_dev.toml` here. The pins are in
`.tool-versions` at the root; run `scripts/setup-toolchain.sh` if a tool is missing.

## Layout

A Scarb workspace of three packages. A workspace rather than one package because the domains must
not mix (neither contract package depends on the other, so neither can import the other's models),
because each
contract class is built and sized on its own (ADR-0007, *Class size*), and because the pure logic
is used by tests and by the client without a contract.

```
Scarb.toml            workspace: members, shared versions and dependencies
logic/                grimworld_logic: the rules, pure, no storage (state in, state out)
  src/tick.cairo        the rules of a tick will live here
  tests/                origami_hexmap 1.8.0 runs on Cairo 2.19
persistent/           grimworld_persistent: contract Persistent (adventurer, inventory, progress, registries)
ephemeral/            grimworld_ephemeral: contract Ephemeral (instance state)
```

Both contract packages have the same layering ([ADR-0007](../docs/architecture/ADR-0007-native-starknet.md),
*The layering is kept*), each module a file with a one-line doc comment and no game code:

```
src/
  systems.cairo     contracts: entrypoints, access control, nothing else
    systems/persistent.cairo (or ephemeral.cairo): the placeholder contract
  components.cairo  Starknet components: game logic reusable across contracts
  store.cairo       single access point to storage
  models.cairo      storage structs: layout, packing, invariants
  types.cairo       enums dispatching to elements
  elements.cairo    one file per content behaviour
  helpers.cairo     pure functions: bitmap, packer, seeder, math
  registries.cairo  content as data
tests/              snforge tests that declare and deploy the contract, each with a gas budget
```

Cairo has no `mod.cairo`: a module is a file, and its submodules sit in the folder of the same
name, which appears with the first file that goes in it (`models/adventurer.cairo`).

Each contract has one placeholder view, `version() -> felt252`, no storage and no access control:
access control, the results interface and the storage layouts are ENG-01's, frozen with the
security lens.

## The two-contract rule

Two contracts, never mixed ([ADR-0007](../docs/architecture/ADR-0007-native-starknet.md),
[ADR-0001](../docs/architecture/ADR-0001-execution-layer.md), *Keeping the exit open*):

| Domain | Package and contract | Holds |
|---|---|---|
| Persistent | `grimworld_persistent`, `Persistent` | adventurer, inventory, progress, registries |
| Ephemeral | `grimworld_ephemeral`, `Ephemeral` | instance state |

**No storage struct mixes fields of both domains** (there are none yet). The ephemeral contract
reads a snapshot of the adventurer taken at entry and writes to the persistent one only through
one dispatcher call carrying the list of results.

## Build and test

From the repository root, always through the build lock (Scarb 2.19: `--manifest-path` comes
before the subcommand):

```
scripts/lock.sh scarb --manifest-path contracts/Scarb.toml build
cd contracts && snforge test          # the machine's shim takes the heavy lock
```

One package: `cd contracts/persistent && snforge test`. Every test carries
`#[available_gas(l2_gas: N)]` with `N = ceil(1.05 × measured)`; the tests of the contracts include
the declare and the deploy of the class.
