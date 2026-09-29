# ENG-03: quiver's ids, the cost of reading content, the writer's cost, where a location's quotas are

| | |
|---|---|
| Raised by | `[Opus 5.5]` game orchestrator, from ENG-03 ([#106](https://github.com/bal7hazar/grimworld/pull/106), report *Escalations* 1–4; audit `[GPT-6-Astra]`: FAIL on F-1, which is escalation 1; **no security finding**) |
| To be answered by | `[Opus 5.5]` project manager (D-128); 1 and 4 change ENG-01 §3.5's frozen allocation, 2 and 3 are above D-144's +10 % |
| Needed by | ENG-03's merge (1 blocks it); ENG-05 (4); ENG-06 and ENG-07 (2) |

ENG-03 implemented `Registry` (the administrator's writes, the content version, the reads), the
layouts of `REGION`, `LOCATION`, `GATE` and `OUTLINE`, and a test region as seed data. Figures are
snforge L2 gas (M) or transactions at §10's prices (D).

## 1. The parent of `TASK` and `QUEST` (audit F-1, blocking the merge)

ENG-01 §3.5 makes them composite kinds whose id must name "quiver's task or quest". `Registry` holds
no quiver address, so it cannot check; ENG-03 accepts any non-zero id.

| Option | Cost |
|---|---|
| (a) **Accept the administrator's id**; §3.5 amended; the check that every `TASK` and `QUEST` names an existing quiver id belongs to the content pipeline (the seed and deployment scripts, OPS-01) | none on chain; a record with a wrong id is inert (no quest reaches it) |
| (b) `Registry` gets quiver's address and calls it on each such write | one call per admin write; a dependency of the persistent domain's registry on quiver's component, which lives in `Hub` (GLD-02) |
| (c) make them sequential | quiver hands out its own ids (D-131): the two would have to be mapped |

**Recommendation: (a).** Only the administrator writes; the chain gains nothing it can enforce
cheaply, and the pipeline that writes both sides is where a mismatch is found.

## 2. `bundle` costs about 36,000 L2 gas a slot read, on the expedition's path

§10 priced the content read as one call (C ≈ 0.12–0.14 M) whatever it returned. Measured: `bundle`
of 1 three-part record 140,800; of 10, 1,109,380; of 32 (its bound, 97 reads) 3,477,020. Every
`play`, `open`, `mine` and `barter` reads its content through `bundle`. How many records an
invocation needs is ENG-07's (the castes and skills in the window): at 10 records, about +1 M a
batch, **about +30 M (≈ $0.026) on S1's 30 batches**, against a target it already misses ($0.556).

**Recommendation:** accept the per-slot price as measured. ENG-06 and ENG-07 count their `bundle`
reads at 36,000 a slot in their worst cases and **keep the records an invocation reads to what its
ticks use** (one record per caste and skill present, not a fixed set); S1 is re-estimated with ENG-07's
measurement. If it is then a lever, the next one is a narrower read (single parts), not a mirror of
content in `Instances` (E-5's option (b), rejected by D-141).

## 3. `set_record` costs more than §10 (above D-144's +10 %)

| Case | §10 | Measured (D) | Difference |
|---|---:|---:|---|
| A new 3-part record | 3,165,279 | 3,488,899 | +10.2 % |
| A changed 3-part record | 1,058,019 | 1,357,957 | +28 % (the compare of every part, the version raised) |

Only the administrator pays it, when content changes; no player transaction does.

**Recommendation:** accept as measured.

## 4. How an instance finds a location's `QUOTAS` record

`QUOTAS` (kind 5) is sequential, and no `LOCATION` field names it. ENG-05 needs a rule. `LOCATION`'s
part 1 is full (15 set pieces of 16 bits).

| Option | Cost |
|---|---|
| (a) **`QUOTAS` becomes composite, its id the location's id** (one record per location, parent `LOCATION`), as `OUTLINE` is keyed by its location | no field; the lookup is the location id, read in the same `bundle`; kind 5's allocation in §3.5 and `content::is_sequential` change |
| (b) a `QUOTAS` id field in `LOCATION` | a set piece less in part 1, or a third part (+1 slot a read) |

**Recommendation: (a)**, done in ENG-03's fix loop so that ENG-05 starts on it.

## Decision

By the project manager on 2026-09-29, under D-128 (**D-145**; source: the project manager's message
to the game orchestrator of that day): **the four recommendations are accepted.**

| # | Decision |
|---|---|
| 1 | Quiver's `TASK` and `QUEST` ids are the administrator's; ENG-01 §3.5 amended (in ENG-03); checking that a quiver id exists is the content pipeline's (OPS-01) |
| 2 | `bundle`'s read, about 36,000 L2 gas a slot on the expedition's path, is accepted as measured, **with two conditions for ENG-06 and ENG-07**: read only the records their ticks use; and **measure where the 36,000 goes** (the call between contracts against the read itself) before the weights are frozen: if the call is most of it, a batch reads its records in one call. The figure and its +$0.026 join the levers of [ENG-01's escalations](2026-09-29-eng-01-escalations.md) |
| 3 | `set_record`'s overrun is accepted: the administrator pays it, not the player |
| 4 | `QUOTAS` is keyed by its location's id (composite, parent `LOCATION`), in ENG-03's fix loop |
