# DES-06 — Caste sheets, and the per-source bounds of every statistic

> D-159: slot 2. D-157 G first: the bounds are a prerequisite of production snapshots (CBT-02,
> ENG-07). A design document in its own pull request.

## Agent
Title: `[Opus 5.5] DES-06 caste sheets` · Profile: implement · Branch: `docs/des-06-caste-sheets`

## Goal
After this task the game has **(1) a per-source bound for every statistic** an actor can carry (signed
where it can be negative), so that the snapshot's sums are bounded by design and CBT-01's validators
can prove them; and **(2) the caste sheets** of the MVP's goblins in the shape CBT-01 froze: health and
armor per caste, skill list, priority list, boss phases, with initial values BAL-01 tunes.

## Context
- **D-157** (`docs/decisions/2026-09-29-cbt-01-escalations.md`): **G**, sums no document bounds (health,
  energy, regeneration bonuses across sources); the recommendation: a per-source bound per statistic,
  signed where negative; CBT-01's validators and the snapshot's flattening then prove them. Also **A**
  (attribute ids: a global id in content, a build-local index in the snapshot; design/03 names **26**
  attributes), **B**, **C**, **D** (which slot types carry which effects; rune identity).
- **design/19** (the catalogue and its bounds, §7 the state and its fit), **CBT-01's code and report**
  (the `CASTE` record's fields: the sheet's shape; the validators' current bounds; the snapshot's
  field widths), design/03 (stats by level and profession), design/05 (the bestiary: castes, packs,
  bosses), design/04 (the goblin AI and its priorities), design/15 (equipment's sources of bonuses),
  design/07 (potions), design/17 (Rifts' bosses).
- CONTEXT §5 (the glossary: new terms are listed in the report for the project manager).

## Scope
- In:
  - **The bounds first** (a section of its own, usable by CBT-02 and CBT-01's validators before the
    sheets): for every statistic of design/19 §7 (health, energy, regeneration, armor, and the others
    it lists), the maximum each source can add (the build, each equipment slot, each rune, each
    potion, each condition or effect, each passive), signed where a source can subtract, and the
    total that follows; checked against the snapshot's field widths (a total that does not fit is an
    escalation with its cost).
  - **The caste sheets**: every caste of design/05 in CBT-01's `CASTE` shape, with initial values and
    their reasoning (from design/03's adventurer at the same level), its skills from design/19's
    catalogue, its priority list (design/04's AI), and the bosses' phases.
  - Where the documents are silent (a value, a rule), an escalation (question, options,
    recommendation), never a decision.
- Out: balance tuning (BAL-01), code (the validators and the flattening use the bounds in CBT-01's
  follow-ups and CBT-02), seed records (CNT-01).
- Allowlist: a new `docs/design/20-castes.md` (or design/05's amendment: say which and why), small
  cross-references in `docs/design/*.md`, `REPORT.md`.

## Acceptance criteria
- [ ] AC-1 Every statistic of design/19 §7 has per-source bounds and a total, signed where negative,
      and each total fits its snapshot field or is escalated.
- [ ] AC-2 Every caste of design/05 has a sheet in CBT-01's shape, its values reasoned, its skills from
      the catalogue.
- [ ] AC-3 Nothing the documents leave open is decided without an escalation.

## Audits
Design and consistency: **`[GPT-6-Astra]`** (the bounds bind the snapshot's capacity).

## Report
`REPORT.md` as in `docs/briefs/COMMON.md` §7: the bounds table, the sheets, the escalations with
options and recommendations.
