# Owner review, round 2 — 2026-09-28

## Answered

| # | Question | Owner's answer |
|---|---|---|
| Q-06 | Client technology | **PixiJS + Capacitor accepted**, subject to the phone spike (SPK-6). The owner's experience is with Phaser, not PixiJS |
| Q-15 | Machine and accounts | Ideation on the owner's Mac (session account bal7hazar). **Implementation starts with a new project-manager session on the VPS**, account bal7hazar. On both machines the `claude` CLI is, or must be, logged in as **claude-b7r**; `codex` is available. A bootstrap prompt for the VPS session is to be written before implementation starts |
| Q-13 | Asset licence | *Tiny Swords* by Pixel Frog, https://pixelfrog-assets.itch.io/tiny-swords. Use and modification allowed in personal and commercial projects; credit welcome, not required; **no redistribution, resale or repackaging, even modified** |
| Q-16 | Merges and deployments | The orchestrator merges and **deploys to Sepolia autonomously**; credentials are in the session's settings environment. Mainnet: see below |

## Consequences recorded

- `assets/` is never committed to this repository, modified or not (`.gitignore`). Sprites
  derived from the pack (the generated goblin sheets) follow the same rule. The game ships
  them packed in atlases inside the app, which is use, not redistribution. Contributors and
  agents get the pack from the owner, outside git. Pixel Frog is credited in the game.
- Commissioned assets will need their own licence terms, agreed with the artist, before
  they are stored anywhere.

## Still open

| # | Question | Recommendation |
|---|---|---|
| Q-17 | Mainnet deployments and mainnet registry writes: does the orchestrator need an explicit go from the owner each time? | Yes: they spend real funds and cannot be undone. Sepolia stays autonomous |
| D-04, D-41, D-50, D-52, D-61, D-31, D-80 | Design decisions listed in `CONTEXT.md` §6 as Proposed | Accept |
| Q-12 | No caster sprite in the pack: commission one for the Arcanist, or ship the Cleric instead? | Commission one if possible; else Cleric |
