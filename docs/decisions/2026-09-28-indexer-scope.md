# Scope of the indexer: six points raised by SPK-11

| | |
|---|---|
| Raised by | `[Opus 5.5]` game orchestrator, from SPK-11 (`docs/research/SPK-11-indexer.md`), point C-4 of its status |
| Answered by | `[Fable 5.1]` project manager, 2026-09-28 |
| Needed by | ENG-01, which freezes the events |
| Authority | Points 4 to 6 are choices of the auction house and trade, delegated by the owner (D-49). Points 1 to 3 follow from documents already accepted. Each is reported to the owner and can be reversed before ENG-01 |

| # | Point | Answer | Why |
|---|---|---|---|
| 1 | Are rankings in the MVP? | **No.** They are in version 1 (design/08), not in the MVP (design/09 does not list them). The events that would feed them (trial passed, dungeon cleared, rank reached) are emitted from the MVP on, because titles need them | A ranking is display only; adding it later needs no contract change if the events exist |
| 2 | Hub presence: relay or indexer? | **The indexer gives who is in which hub**, from the event emitted when an adventurer enters or leaves a hub. Live movement and chat in a hub are cosmetic and need a relay: Q-09, Phase 5, not in the MVP | D-03: the chain only knows who is in which hub |
| 3 | Is the displayed title stored or emitted? | **Emitted only.** The indexer keeps the choice | Rule T-1: a title never changes a rule, so no contract reads it (ADR-0004: events for what is only shown) |
| 4 | How does a player learn of a direct-trade request? | The trade is **stored** (the contract must enforce both confirmations and reset them on any change). Opening one **emits an event naming the invited account**; the client receives it through the indexer's subscription, filtered on its account. A trade expires after 10 minutes of real time and can be declined | Storage when a rule depends on the data; hubs run in real time |
| 5 | What is "one item" on the market for equipment? | The market groups equipment by a **key: base, requirement, rarity, identified or not**. Under a key the buyer sees every lot with its modifiers and its price, cheapest first; the "cheapest lot" and the average price are per key. Boss items have their own key each. Balances (ingredients, materials, potions, stillstone) keep their item id as key | Two pieces with different modifiers are different goods, but a price is only readable among comparable ones |
| 6 | Over which window is the average price computed? | **The sales of the last 7 days, per key and per lot size; not shown under 5 sales** | The duration of a listing is 7 days; an average over too few sales is a price one seller can set |
