# [Opus 5.5] IP check — ART-00 — asset pipeline

Required audit of ART-00 (PLAN: "IP check"), by the game orchestrator, on
[PR #12](https://github.com/bal7hazar/grimworld/pull/12), 2026-09-28.

## Verdict
PASS

## Checks
| Check | Result |
|---|---|
| No image, audio, font or atlas file in the diff | None (`gh pr diff 12 --name-only`); the CI step "no asset file committed (D-73)" passed |
| Nothing derived from the pack committed | Outputs go to `tools/art/out/`, ignored by `tools/art/.gitignore`; the committed files are code, a manifest, a requirements file, a Node check package, a README and `CREDITS.md` |
| No name from the manga | `grep -i slayer` over the diff: nothing. The generated sheets' folder is resolved in code (the subfolder of `Enemy Pack` holding `Animated/Raw`), never named; the pipeline itself fails if the name appears under `tools/art` |
| Submodule | The `assets` pointer is unchanged (CI step "assets pointer unchanged") |
| Credit | `CREDITS.md` credits *Tiny Swords* by Pixel Frog with the licence's terms |
| Scope | Only `tools/art/**` and `CREDITS.md` |

## Open, for the owner (not blocking)
- ART-1: display scale per caste (the generated goblins are about twice the pack's units).
- ART-2: the slinger placeholder is the Torch Goblin.
