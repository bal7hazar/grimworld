# CBT-02e: when a stored snapshot goes stale (D-168 2)

| | |
|---|---|
| Raised by | `[Opus 5.5]` game orchestrator, from CBT-02e ([#212](https://github.com/bal7hazar/grimworld/pull/212); report *Escalations* 3 and 4, *The staleness table*) and its security and cost audit (`[GPT-6-Astra]`, PASS WITH FINDINGS, note 1) |
| To be answered by | `[Fable 5.1]` project manager (D-168 is yours) |
| Needed by | the first deployment that stores snapshots; not CBT-02e's merge |

CBT-02e did D-168: `set_build` flattens once through `FlattenLibrary` and stores 3 words; `enter`
copies them and refuses `snapshot: missing` or `snapshot: stale`. Stale means one of: the stale mark
set, the level changed, or the registry's **content version** moved since `set_build`. Measured:
`enter` 4,473,259 net on the node (D-158: 5.25 M), `set_build` 8,097,073 worst call, `Hub` 44.64 %.
Two cases are left for decision.

## 1. A new rules class does not stale the stored snapshots

`set_contracts` can point `Hub` at another `FlattenLibrary` class. The snapshots flattened by the old
class stay valid: `enter` checks the content version and the level, not which rules produced the words.
Only the administrator can do this (the audit rates it a note, not a defect).

| Option | Effect | Cost |
|---|---|---|
| (a) **A rules epoch**: `Hub` counts `set_contracts` changes to the flattening class; the epoch is stored in the kit word's free bits (241–249) and checked at `enter` | a rules change stales every snapshot, as a content change does | one storage read at `enter` (measured by the lot); 9 bits |
| (b) The administrator also rewrites a record, which moves the content version | nothing to build | a procedure to remember; a forgotten step leaves old rules in play |
| (c) Accept: old snapshots finish their life under the old rules | nothing | two players entering the same day can carry the same build under different rules |

## 2. Any content update stales every stored snapshot

The content version moves on **any** changed record: a new gate, quest, shop or caste stales every
adventurer's snapshot, although the flattening reads only the build's records. After each update,
every player's next `enter` is refused until a `set_build` (the client sends it first, D-168 2):
about 3.0 M net for an empty build, up to about 9–10.6 M (E) for the widest, per adventurer per update.

| Option | Effect | Cost |
|---|---|---|
| (a) Accept | every content update costs each active player one `set_build` | 3.0–10.6 M a player per update, outside S1 but on the player's day |
| (b) **A second counter for the kinds the flattening reads** (`MODIFIER`, `BASE`, `ARMOR_SET`, and whichever others the flattening reads, listed by the lot), returned by `Registry.bundle` beside the content version and stored instead of it | only a change to a flattening input stales snapshots | one counter slot written by `set_record` on those kinds (the administrator's); `bundle`'s return gains a field (a frozen interface, ENG-03) |
| (c) No content check: snapshots finish their life under the content they were built with | nothing | a nerfed modifier stays in force until the player's next `set_build` |

## Recommendation

**1 (a) and 2 (b)**, together as **CBT-02f** (Opus 5.5, small: `Hub`, `Registry.bundle`, the kit's
bits, tests), before the first deployment that stores snapshots. With both, the kit carries one
**flattening epoch**: the rules epoch and the counter of flattening inputs, compared at `enter` in the
call it already makes. **CBT-02e merges as it stands** once its quality audit and Codex review pass:
nothing is deployed, and both cases only widen what counts as stale.

Also from CBT-02e, recorded in PLAN for their own lots (no decision needed): `sell`, `recycle`,
`stow`, `Market.escrow` and `exchange` must refuse a worn entity (or clear its lane and mark stale),
and `personalise`, `lift_modifier`, `set_modifier` must mark stale on a worn entity. All are stubs today.

## Decision

**D-169**, `[Fable 5.1]` project manager, 2026-09-30, under D-128: the recommendation, both parts,
as **CBT-02f** before the first deployment that stores snapshots.

1. **(a) A rules epoch**: `Hub` counts the changes of the flattening class through `set_contracts`;
   the epoch is stored in the kit word's free bits and checked at `enter`: a rules change stales every
   snapshot, as a content change does. A procedure (b) that can be forgotten is not a rule; (c) lets
   two players enter the same day under different rules.
2. **(b) A counter of the flattening's input kinds**, written by `set_record` on those kinds only
   (the lot lists them: `MODIFIER`, `BASE`, `ARMOR_SET` and whichever the flattening reads), returned
   by `Registry.bundle` beside the content version and stored in the snapshot instead of it: only a
   change to an input of the flattening stales snapshots. The added field of `bundle` is a change of
   a frozen interface, decided here: nothing is deployed, and ENG-01b's rule holds (interfaces may
   change under their name until a build's first deployment). A nerfed modifier reaches every player
   at their next `enter`, as (c) would not.

CBT-02e merges as it stands once its fix loop, audits and Codex review pass; CBT-02f measures
`enter`'s added read against D-158's 5.25M.

**What would reverse it**: the counter's kinds proving hard to bound (the flattening reading kinds
that change daily), in which case (a) of question 2, one `set_build` per player per update, is the
fallback, priced on the player's day.

