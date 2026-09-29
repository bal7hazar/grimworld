# [GPT-6-Astra] Audit — PR 170 (CBT-08a) — security, quality, organisation

## Verdict

**PASS WITH FINDINGS**

Re-audited `8152fc6f19d412b7a109ea3db7a1558a8231519b`, including the changes since `342b57a`.

**F-1 is deferred; F-2 is closed. No new blocking finding.** No reachable player-controlled ownership or equipment-cache bypass was found. The cache introduces a creation-time invariant, recorded below as F-3.

D-158 and the F-1 deferral were verified on `origin/main` at `b5407cf`; this checkout’s decision file still says “Pending”.

## Findings

Final disposition of every finding:

| # | Severity | Status | Location | Finding / evidence | Suggested fix or follow-up |
|---|---|---|---|---|---|
| F-1 | minor | **Deferred — non-blocking** | `origin/main:PLAN.md:190`, commit `b5407cf` (#173) | ENG-R1 now explicitly includes “`set_build`’s new storage access behind the store.” The direct accesses remain, under this recorded deferral. | Complete the store separation in ENG-R1. |
| F-2 | note | **Closed** | [ENG-01 §3.3](/home/claude/projects/grimworld/.claude/worktrees/cli-AUD-170/docs/architecture/ENG-01-interfaces.md:401), [§3.5](/home/claude/projects/grimworld/.claude/worktrees/cli-AUD-170/docs/architecture/ENG-01-interfaces.md:538) | The document now freezes ItemBase’s slot/hands nibbles and BASE’s two-byte prefix. Code agrees. The BASE model explicitly warns that its packer zeros future fields. | No remaining action for F-2. |
| F-3 | note | **Creation-time invariant; no current exploit** | [ItemBase constructor](/home/claude/projects/grimworld/.claude/worktrees/cli-AUD-170/contracts/persistent/src/models/item.cairo:39), [equipment validation](/home/claude/projects/grimworld/.claude/worktrees/cli-AUD-170/contracts/persistent/src/systems/hub.cairo:541) | `new(base, record, …)` copies the supplied record but cannot prove that it belongs to `base`. `set_build` trusts the cached fields. If a two-handed base were stored with `slot=1, hands=1`, equipping it with an off-hand would pass. **No production item writer currently makes this state reachable.** | Every future creator must fetch and validate the BASE identified by the item, then derive the cache from it. Test mismatched records and omitted fields when those creators land; calling this constructor alone does not establish identity. |

## Coverage

**Item creation and reachability.** Repository-wide inspection found no production write to the `items` map. Buying, crafting, quest rewards, loot and barter remain stubs. `Hub.report` rejects nonempty equipment before settlement; an existing refusal test covers this. Instances currently emits empty equipment results.

The equipment fixtures now use `ItemBaseTrait::new(base, @base_record(base), …)` with matching fixture records. The constructor correctly copies both fields. Direct struct construction and defaults remain possible internally, so the constructor is a convention rather than an enforced creation boundary.

**Reading the cache.** Ownership, identification and component checks precede cached-slot validation. Slot zero fits no lane; lane zero with `hands=2` rejects any off-hand. These checks execute even when the bar and belt are empty and no registry call occurs. Calldata supplies entity IDs, not their cached metadata.

Consequently, a caller cannot manufacture a mismatch through `set_build`; however, **`set_build` does not detect an already-stored mismatch with BASE**. F-3 states the precise limit of the security conclusion.

**Layouts.** ItemBase’s existing fields end at bit 119. Slot occupies 120–123 and hands 124–127, completing the low limb without overlapping ownership or `LIVE`. Both packer inputs are bounded below 16. Tests pin the literal offsets, maximum nibble values, overflow refusals, constructor copying and round trips.

BASE retains slot at 0–7, hands at 8–15 and two parts. Its valid slot/hands values fit the narrower ItemBase fields. `set_build` performs **zero BASE reads**.

**Raised layout-test budget.** The recorded measurement rises from **325,140 to 350,080**, an increase of **24,940 (+7.67%)**. The revised budget, **367,584**, equals `ceil(350,080 × 1.05)`. The changed pack/unpack work and additional fields provide a concrete reason for the raise; the source annotation and report disclose it. This is not presented as a variance-only increase.

**D-158 figures.** Subtracting **189,141** from the committed node receipts reproduces:

| Belt case | Net L2 | D-158 target | Headroom |
|---|---:|---:|---:|
| Later `enter` | 5,233,259 | 5,250,000 | 16,741 |
| Second belted `enter` | 5,153,259 | 5,250,000 | 96,741 |
| `leave` to hub | 3,073,259 | 3,100,000 | 26,741 |
| `travel_back` | 2,868,139 | 2,900,000 | 31,861 |

All four remain within their targets.

The `set_build` belt-only receipt gives **2,422,059 net (+21.1% over 2.0M)**. The full-fixture estimate correctly gives:

`2,611,200 + (2,960,731 − 1,442,690) − 189,141 = 3,940,100 net`

That is **+97.0%**, still an estimate rather than a node measurement. The isolated-part sum, **3,177,311**, also reproduces. The unexplained **160,000** node increase is disclosed, not explained by evidence. These figures remain project-manager escalations, not audit findings.

**Earlier coverage stands**, subject to replacing runtime BASE validation with the creation-time invariant above: adventurer ownership and hub lock; bar membership, professions, duplicates, elite and empty slots; attribute tables and primary-attribute exclusion; potion ownership and summed counts; equipment ownership, identification, components and duplicates; packed-word bounds and the three-word write set. No new page or lane bypass was identified.

**Verification limits.** `git diff --check` passed. All 22 fix-loop report rows match the committed budget table. The foreground `snforge` attempt failed during Scarb metadata because its lockfile could not be opened on the read-only filesystem. Runtime execution, CI and node measurements remain implementer-reported; source, fixtures and recorded arithmetic were independently checked.

No files were changed and no command remains pending.