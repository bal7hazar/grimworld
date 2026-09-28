# 10 — Art direction

> Status: **Draft v0.1**

## Direction

| | |
|---|---|
| Style | Pixel art, rich: 64 × 64 base tile, characters drawn in 192 × 192 frames |
| View | Top-down three-quarter, characters seen from the side |
| Reference pack | *Tiny Swords* by Pixel Frog (free public pack), in the submodule `assets` (private repository) |
| Plan | Prototype with the free pack; commission original assets from the same artist once the game proves itself |
| Priority platform | **Mobile**, portrait |

## What the pack contains (inventory of `assets/`, 2026-09-28)

| Folder | Content | Use in Grim World |
|---|---|---|
| `Units/` | Warrior, Archer, Lancer, Monk, Pawn, in 5 colours | Adventurers |
| `Enemy Pack/` | 20+ creatures, including Torch Goblin, Spear Goblin, Hex Shaman, Troll, Gnoll | Goblin castes |
| `Enemy Pack/Goblin Slayer Pack/` | 8 goblin castes as generated concepts and raw animation sheets (common, hobgoblin, shaman, champion, lord, paladin, priest, rider). Not yet transparent sprites | Goblin castes, after clean-up |
| `Buildings/` | Castle, Barracks, Archery, Monastery, Tower, Houses, in 5 colours | Hubs |
| `Terrain/` | **Square** 64 × 64 tileset (grass, cliffs), decorations (bushes, rocks), water | Ground and obstacles |
| `UI Elements/` | Banners, bars, buttons, icons, papers, avatars | Interface |
| `Particle FX/` | Dust, fire, explosion, splash | Skill and hit effects |

## Mapping to the design

### Professions

| Profession | Sprite | Note |
|---|---|---|
| Vanguard | Warrior | Attack ×2, Guard, Idle, Run |
| Warden | Archer | |
| Cleric | Monk | Has a Heal animation |
| **Arcanist** | **None** | No caster sprite in the pack (Q-12) |
| Gravecaller, Beguiler | None | Post-MVP, to commission |
| — | Lancer, Pawn | Unused; Pawn can serve as hub NPC |

### Castes (MVP)

| Caste | Candidate sprite |
|---|---|
| Runt | Torch Goblin, or generated *common* |
| Skirmisher | Spear Goblin |
| Slinger | To make: the pack's slinger is a gnome, not a goblin |
| Shaman | Hex Shaman, or generated *shaman* |
| Hobgoblin (boss) | Generated *hobgoblin*, or Troll as placeholder |

## Constraints the design puts on art

### Hex grid with a square tileset

The map is hexagonal ([02-core-loop](02-core-loop.md#map)); the pack's terrain is a square
autotile and its cliffs cannot outline hex walls. For the prototype:

| Element | Rendering |
|---|---|
| Ground | One continuous textured ground per biome, not tiled per hex |
| Grid | Hex outline overlay, subtle, stronger on reachable tiles |
| Walls | One **obstacle object** per wall tile (rock, bush, tree, stump), drawn from `Terrain/Decorations` |
| Border ring | Dense obstacles; entrances are gaps |

A true hex tileset is part of the first commission.

### Facing

Sprites face right and are mirrored to face left. With **pointy-top** hexes every one of
the six directions has a left or right component, so the mirror always matches the
direction of travel: East, North-East, South-East show the right-facing sprite; the three
others show the mirrored one.

The sprite alone cannot tell North-East from South-East, and
[arcs](04-combat.md#facing-and-arcs-d-41) are central to combat, so facing is shown by the
interface:

- a wedge on the actor's tile pointing to its front tile;
- the back tile of the selected foe highlighted when it is reachable;
- a distinct hit effect for flank and critical strikes.

### Missing animations

| Missing | Needed by |
|---|---|
| Hurt, Death | Every actor. Prototype: flash and fade, plus the pack's "dead" extras where they exist |
| Cast / activation pose | Telegraphed skills (interrupt gameplay) |
| Knocked down | Condition |
| Asleep | Goblin state |

### Icons

The pack has few skill icons. Skills, conditions, ingredients and potions need an icon
set: about 40 skills, 5 conditions, 10 ingredients and 12 potions for the MVP.

## Licence and provenance

Pack: *Tiny Swords* by Pixel Frog, https://pixelfrog-assets.itch.io/tiny-swords.

| The licence says | Consequence |
|---|---|
| Free to use in personal and commercial projects, and to modify | The game may ship with these sprites and with sprites derived from them |
| Credit not required but welcome | Pixel Frog is credited in the game and in the README |
| **No redistribution, resale or repackaging, even if modified** | Neither the pack nor anything derived from it is committed to this repository (D-73). `assets/` is ignored by git |

Rules:

- The pack lives in the private repository `tiny-swords`, attached to this one as the
  submodule `assets`. This repository holds a pointer to a commit, not the files, so
  nothing is redistributed. Whoever has no access to the private repository can still
  clone and build everything except the art.
- `tiny-swords` must stay private.
- The client ships sprites **packed into atlases** inside the app bundle, not as the
  pack's original files and folders.
- The generated goblin sheets are derived from the pack's Troll: same rule. They are also
  machine-generated prototypes; whether to ship them or have the artist redraw them is the
  owner's call at the first commission.
- The folder and files refer to *Goblin Slayer*. Names from the manga must not reach the
  game, the repository or the store listing (CONTEXT §8); sprites are renamed after our
  castes when they are packed.
- Commissioned assets need their own licence terms, agreed with the artist, before they
  are stored anywhere.
