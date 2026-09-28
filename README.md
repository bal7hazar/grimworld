# Grim World

A fully on-chain, tick-based heroic-fantasy RPG on Starknet.

You are an adventurer of the Guild, lowest rank. Take a contract from the board, choose
eight skills, walk out of the gate alone. Beyond the walls, **the world only moves when
you do** — and every goblin in it is waiting for your next step.

> **Status**: design phase. No playable build yet.

## What makes it different

- **Player-owned time.** No action, no tick. Leave an expedition for a week and resume it
  on the same step.
- **Build over grind.** Low level cap, eight skill slots, attributes to spread. Power is a
  choice made in town.
- **One enemy, many faces.** Only goblins; their caste tells you how afraid to be.
- **Deterministic tactics, random rewards.** What you do resolves exactly as predicted;
  what you find is decided by verifiable randomness.
- **A world that grows sideways.** New towns, zones, skills and quests are data.

## Documents

| Document | Purpose |
|---|---|
| [CONTEXT.md](CONTEXT.md) | Start here: pillars, stack, glossary, decisions, open questions |
| [docs/CAIRO.md](docs/CAIRO.md) | Cairo engineering rules: test-driven, gas budgets, order of preference, types |
| [OPERATIONS.md](OPERATIONS.md) | Roles, model policy, how to launch / resume / close agents, audits, merge rules |
| [STATUS.md](STATUS.md) | Live dashboard, rewritten at every check-in (dated) |
| [PLAN.md](PLAN.md) | Phases, tasks, milestones, gates, risks |
| [docs/decisions/](docs/decisions/) | One file per decision; `PENDING-*.md` for the owner's open questions |
| `docs/briefs/`, `docs/reports/`, `docs/research/` | Task briefs, archived agent reports, research (from Phase 0) |
| [docs/design/](docs/design/00-vision.md) | Game design documents |
| [docs/lore/](docs/lore/00-premise.md) | The world and its story |
| [docs/architecture/](docs/architecture/ADR-0001-execution-layer.md) | Architecture decision records |

## Stack (proposed)

Starknet mainnet · native Cairo contracts (no Dojo) · `origami_hexmap` · our own indexer · Cartridge Controller and
vRNG · TypeScript client (PixiJS, Capacitor), mobile first.
See [ADR-0001](docs/architecture/ADR-0001-execution-layer.md) and
[ADR-0003](docs/architecture/ADR-0003-client.md).

Language: chat with the owner in French; every document, brief, commit and pull request
in English.

## Credits

Prototype art: *Tiny Swords* by [Pixel Frog](https://pixelfrog-assets.itch.io/tiny-swords).
The assets are not part of this repository: their licence forbids redistribution. The
`assets` submodule points to a private repository; the game's code builds without it.

## License

See [LICENSE](LICENSE).
