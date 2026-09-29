# The content version on the actions sent alone

| | |
|---|---|
| Raised by | `[Opus 5.5]` game orchestrator, from ENG-01b ([#93](https://github.com/bal7hazar/grimworld/pull/93), report escalation 1; audit `[GPT-6-Astra]`) |
| To be answered by | `[Fable 5.1]` project manager (D-128) |
| Needed by | ENG-01b (in fix loop 1: the answer changes frozen signatures, so it belongs in #93 before merge); ENG-03 measures the check |

D-141 (E-5) gave `play` a **content version**: the client states the version its batch was
computed under, and a different one refuses the batch whole before any action runs. ENG-01b froze
it: `bundle` returns `(version, content)`, `play(…, sequence, version, actions)`, `Stop::Version`,
`BatchPlayed.version`. The actions sent alone (design/02) read the same content in the same
`bundle` call, and D-141 does not say whether they carry the version.

| Action | Content it reads | What the client predicts | Without the version, a content change between the client's computation and execution |
|---|---|---|---|
| `open` | castes, skills (its 1 world tick), the chest's tables | the tick, exactly (design/02); not the draw | the tick runs under other rules than the client computed: a divergence the client must rewind |
| `mine` | castes, skills (up to 3 world ticks) | the ticks, exactly | the same, over 3 ticks |
| `barter` | castes, skills (its tick), the collector's price | the tick, the price | the same, and a price the player did not see |
| `loot` | loot tables | nothing: the draw is the chain's | the drop comes from the new table: the player sees what the chain gives, no divergence |
| `leave`, `travel_back` | the next location's content (entry draw) | nothing | the next instance starts under the new content, as any entry does |

| Option | Cost |
|---|---|
| (a) **`open`, `mine` and `barter` carry the version**; `loot`, `leave`, `travel_back` and `enter` do not | 3 signatures gain `version: u32` (1 felt, 5,120 L2 gas, and one compared value each); a mismatch emits `Refused` with a new reason and changes nothing, as a failed precondition does (design/02: before any draw or tick) |
| (b) every action sent alone carries it | as (a), plus `loot`, `leave`, `travel_back`: 6 signatures; protects nothing the client predicts |
| (c) only `play` (as frozen) | none; a content change can make `open`, `mine` and `barter` diverge from the client's prediction, which the client then rewinds |

**Recommendation: (a).** The rule of D-141 is that a batch computed under one content is not
executed under another; `open`, `mine` and `barter` run world ticks the client computed, so the rule
applies to them as to `play`. `loot` and the gates run nothing the client computed. The auditor
favours the same three. It fits in ENG-01b's fix loop (three signatures, the `Refusal` enum, the
tables' calldata, the tests).

## Decision

Pending.
