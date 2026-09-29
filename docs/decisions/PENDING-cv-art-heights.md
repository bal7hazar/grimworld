# PENDING — the heights of D-146 are not the pack's

| | |
|---|---|
| Asked by | `[Opus 5.5] Orchestrateur client visuel (Mac)`, 2026-09-29 |
| For | The project manager, `[Opus 5.5] Chef de projet Grim World`; the final sizes are the owner's eye (D-146 §5) |
| Concerns | D-146 §5 (question ART-1, answered provisionally), ART-02 ([#134](https://github.com/bal7hazar/grimworld/pull/134)) |

## What was found

D-146 says: every sprite at the height of the pack's unit of its build, **78, 94 or 128 px**. ART-02
measured the pack's own units with one rule (the idle pose, feet to the top of the head, weapons
excluded; median of the frames): **none of them is 78, 94 or 128**.

| Pack unit | Height (px) | | Pack unit | Height (px) |
|---|---|---|---|---|
| Warrior (Vanguard) | 87 | | Spear Goblin (Skirmisher) | 70 |
| Archer (Warden) | 88 | | Torch Goblin (Slinger, placeholder) | 67 |
| Monk (Cleric) | 67 | | Hex Shaman | 70 |
| Pawn | 72 | | Minotaur | 119 |
| Lancer | 75 | | Troll | 209 |

The generated goblin sheets (runt, shaman, hobgoblin) are drawn about twice as large: 147, 153 and
177 px.

ART-02 kept D-146's numbers, so every sprite is resampled, **the pack's hand-drawn heroes included**:
Vanguard ×1.08, Warden ×1.07, Cleric ×1.40, by a non-integer area filter snapped back to each
sprite's palette. The pipeline makes each height one line of `tools/art/manifest.toml`.

## Options

| | What | For | Against |
|---|---|---|---|
| A | Keep 78 / 94 / 128 (as ART-02 builds them) | D-146 as written; even sizes per build | The pack's crisp pixel art is resampled by non-integer factors (the Cleric ×1.40); ADR-0003 wants pixel art at integer multiples |
| B | **The pack's original units at their native height, untouched; only the generated sheets are scaled down to the pack's scale** (runt to the small goblins' 67–70, shaman to about the heroes' 87, hobgoblin to the Minotaur's 119) | No resampling of hand-drawn art; the generated sheets join the pack's scale, which is what "the pack's unit" suggests | Heights are uneven within a build (the Monk is 67, shorter than the Spear Goblin's 70: "a basic goblin never taller than a hero" needs the Cleric as an exception, or a tolerance) |

**Recommendation: B**, then the owner's eye on CLI-03a's sandbox, where the scale per caste can be
tried live. It is one edit of `manifest.toml` (heights per sprite, no resampling for the original
strips), no code.

## What would reverse it

The owner preferring even heights per build (A), or other sizes on the sandbox.
