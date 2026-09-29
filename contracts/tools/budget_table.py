#!/usr/bin/env python3
"""ENG-01: the budget of every entrypoint, derived from its enumerated key set
(docs/architecture/ENG-01-interfaces.md §9.3, §10, §10.1). Fix loop 2 (F-2, F-3, F-4): every row's
new / overwritten counts are the sums of the physical keys listed with it, and its gas is computed
here, not by hand.

    L2 gas = F + computation + C × calls + N × new + O × overwritten + events

Prices (cost-budget.md §1, FND-04; this task's probes):
    F = 816,939 (floor of a burner transaction), N = 453,524 (new slot), O = 32,072 (overwritten),
    C = 136,000 (a call between contracts: 117,910 in snforge × 1.157, E),
    B = 65,648 (an event of 4 data felts: GoblinKilled, LotPosted: 56,740 in snforge × 1.157, E),
    S = 46,336 (an event of 1-2 data felts: 40,048 in snforge × 1.157, E).
Computation figures are estimates (E), named with each row.

    python3 contracts/tools/budget_table.py          §10's table and §10.1's figures
    python3 contracts/tools/budget_table.py --keys   §9.3's key sets
"""

F, N, O, C, B, S = 816_939, 453_524, 32_072, 136_000, 65_648, 46_336
TICK_ALONE, TICK_SHARED = 3_564_913, 1_705_764
WINDOW_LOW, WINDOW_HIGH = 65_224, 720_000

# A key list is [(name, count, cold_is_new, init_is_new, init_count)]: cold = the keys never
# written, init = every key already written. `True` in the third field: the key is new when cold.


def tally(keys):
    cold_n = sum(c for _, c, cold_new, _, _ in keys if cold_new)
    cold_o = sum(c for _, c, cold_new, _, _ in keys if not cold_new)
    init_n = sum(i for _, _, _, init_new, i in keys if init_new)
    init_o = sum(i for _, _, _, init_new, i in keys if not init_new)
    return (cold_n, cold_o), (init_n, init_o)


def gas(compute, calls, n, o, events):
    return F + compute + C * calls + N * n + O * o + events


def k(name, count, cold_new=False, init_new=False, init_count=None):
    """A key set: `count` keys when cold, `init_count` (default `count`) when initialised."""
    return (name, count, cold_new, init_new, count if init_count is None else init_count)


# The standalone actions' world part, their own union (not play's cap), per tick: 8 goblins act +
# 6 hit (the widest MVP area) = 14 goblins, 2 words each; the window's 4 chunks; the member's 4
# transient words; roster pages: compact appends and swap removals can touch all 4.
def tick_world(ticks, goblins):
    new_roster = min(4, (goblins + 14) // 15)  # roster pages first used by `goblins` more entries
    return [
        k("goblin words", 2 * goblins, True, False),
        k("chunk features (window)", 4),
        k("member state, timers, effects, recharges", 4),
        k("header, entropy", 2),
        k("roster pages, first used", new_roster, True, False),
        k("roster pages, others", 4 - new_roster),
    ]


HUB_LOOT_BOSS = [
    k("balance pages (3 items)", 3, True, False),
    k("pack gold", 1, True, False),
    k("item bases (3 drops, always new)", 3, True, True),
    k("next_item", 1),
    k("pack list pages, appended", 2, True, False),
    k("core (pack_lanes, experience)", 1),
    k("account counter (Scavenger)", 1, True, False),
    k("quiver held quests", 4),
]
HUB_LOOT_ORDINARY = [
    k("balance pages (2 ingredients)", 2, True, False),
    k("pack gold", 1, True, False),
    k("core", 1),
    k("account counter", 1, True, False),
    k("quiver held quests", 4),
]

ROWS = [
    # name, computation, calls, events, keys, basis
    ("`enter` (with `create`)", 1_450_000, 4, 2 * S, [
        k("placement, header, entropy, revealed, quotas", 5, True, False),
        k("member words (8: state from the snapshot, empty timers, effects, recharges, snapshot, controller)", 8, True, False),
        k("entry chunk: terrain, features", 2, True, False),
        k("task pages ⌈t/4⌉, t = 16", 4, True, False),
        k("next_slot (written at the first entry only)", 1, False, False, 0),
        k("hub: place", 1),
        k("hub: belt reserve, pack pages", 4),
        k("hub: core (pack_lanes)", 1),
    ], "checks, snapshot, entry draw, first chunk's generation 0.39–0.45 M (SPK-7, M); calls: instances, registry ×2, fate"),
    ("`enter_rift`", 1_550_000, 5, 2 * S, None, "`enter` + the day's board (first action of the day: its draw)"),
    ("`leave`, `travel_back`", 600_000, 1, 2 * S, [
        k("header, placement, member state", 3),
        k("hub: place, core", 2),
        k("hub: belt credit, pack pages", 4),
    ], "the closing report; `InstanceClosed`, `AdventurerLocated`"),
    ("`leave` through a gate", 1_900_000, 3, 2 * S, [
        k("placement, header, entropy, revealed, quotas", 5),
        k("member state, timers, effects, recharges: initialised for clock 0 (F-12)", 4),
        k("entry chunk of the next location", 2, True, False),
        k("hub: place, core (Moved)", 2),
    ], "the next entry draw and generation; snapshot, controller and task words unchanged"),
    ("`loot`, a boss (3 items)", 500_000, 3, 0, [
        k("header, entropy, goblin state", 3),
        k("roster: a swap removal (hole page, last page)", 2),
    ] + HUB_LOOT_BOSS, "0 world ticks; calls: registry, fate, hub"),
    ("`loot`, ordinary remains", 500_000, 3, 0, [
        k("header, entropy, goblin state", 3),
        k("roster: a swap removal", 2),
    ] + HUB_LOOT_ORDINARY, "as above"),
    ("`open`, goblins near (1 tick, then a draw)", 500_000 + TICK_ALONE + WINDOW_HIGH, 3, 14 * B,
     tick_world(1, 14) + HUB_LOOT_BOSS, "one tick as alone (SPK-1, M) and its window; ≤ 14 `GoblinKilled` (traps); the draw branch"),
    ("`open`, no goblin near", 800_000, 3, 0, [
        k("header, entropy, member state, the chest's features", 4),
    ] + HUB_LOOT_ORDINARY, "a quiet tick 0.30 M"),
    ("`mine`, goblins near (3 ticks, own union)", 200_000 + 3 * (TICK_ALONE + WINDOW_HIGH), 2, 42 * B,
     tick_world(3, 42) + [
        k("hub: stillstone page", 1, True, False),
        k("hub: core, quiver held quests", 5),
     ], "3 ticks, 42 goblins (3 × 14), ≤ 42 `GoblinKilled`; completion branch"),
    ("`mine`, goblins near, with the invocation cap of 16 (E-16)", 200_000 + 3 * (TICK_ALONE + WINDOW_HIGH), 2, 16 * B,
     tick_world(3, 16) + [
        k("hub: stillstone page", 1, True, False),
        k("hub: core, quiver held quests", 5),
     ], "the same, 16 goblins"),
    ("`mine`, no goblin near", 900_000, 2, 0, [
        k("header, entropy, member state, the vein's features", 4),
        k("hub: stillstone page", 1, True, False),
        k("hub: core, quiver", 5),
    ], "3 quiet ticks"),
    ("`barter`, goblins near (1 tick)", 400_000 + TICK_ALONE + WINDOW_HIGH, 3, 14 * B,
     tick_world(1, 14) + [
        k("hub: price pages", 2),
        k("hub: the item given, its base", 1, True, True),
        k("hub: next_item", 1),
        k("hub: pack list page", 1, True, False),
        k("hub: core", 1),
        k("hub: the tick's Open report, quiver", 4),
     ], "calls: registry, hub `barter`, hub `report`"),
    ("`barter`, no goblin near", 700_000, 3, 0, [
        k("header, member state", 2),
        k("hub: price pages", 2),
        k("hub: item base", 1, True, True),
        k("hub: next_item, core", 2),
        k("hub: pack list page", 1, True, False),
    ], ""),
    ("`register`", 200_000, 0, 0, [
        k("account_of, account owner, account record", 3, True, True),
        k("next_account", 1),
    ], "once per address"),
    ("`set_account_owner` (7 adventurers inside)", 200_000, 7, 0, [
        k("owner, account_of[old] (zeroed, E-19)", 2),
        k("account_of[new]", 1, True, True),
        k("each inside: its member's controller", 7),
    ], ""),
    ("`create_adventurer`", 300_000, 1, 0, [
        k("adventurer: 6 words", 6, True, True),
        k("next_adventurer, account record", 2),
        k("account list page, appended", 1, True, False),
    ], "the profession (registry)"),
    ("`delete_adventurer`", 200_000, 0, 0, [
        k("core, account record", 2),
        k("account list: a swap removal", 2),
    ], "pack empty: `pack_lanes` 0, pack lists empty"),
    ("`set_build`", 300_000, 1, 0, [k("build, belt, equipped", 3)], "skills and bases (registry)"),
    ("`travel`", 100_000, 0, S, [k("place", 1)], "`AdventurerLocated`"),
    ("`display_title`", 50_000, 0, S, [], "event only (T-1)"),
    ("`accept_quest`", 400_000, 1, 0, [
        k("quiver held record", 1, True, False),
        k("known skills page (skills given at acceptance)", 1, True, False),
    ], "the quest (registry)"),
    ("`abandon_quest`", 300_000, 0, 0, [k("quiver held record", 1)], ""),
    ("`accept_contract`", 300_000, 1, 0, [k("quiver held record", 1, True, False)], "the day's pool (registry)"),
    ("`claim_quest`", 600_000, 1, 2 * S, [
        k("core", 1),
        k("pack gold, balance page, pack list page, known skills page, counter", 5, True, False),
        k("reward item base", 1, True, True),
        k("next_item, quiver 2", 3),
    ], "`RankReached`, `TrialPassed`"),
    ("`claim_title`", 400_000, 0, 0, [k("quiver's claim record", 1, True, True)], ""),
    ("`buy_skill`", 200_000, 1, 0, [
        k("known skills page", 1, True, False),
        k("pack gold", 1),
    ], "the trainer (registry)"),
    ("`buy`, equipment", 300_000, 1, 0, [
        k("item base", 1, True, True),
        k("pack list page", 1, True, False),
        k("gold, next_item, core", 3),
    ], "the offer (registry)"),
    ("`sell`, equipment", 300_000, 1, 0, [
        k("pack gold (first income)", 1, True, False),
        k("item base, pack list: a swap removal (2), core", 4),
    ], "the value (registry)"),
    ("`craft`", 300_000, 1, 0, [
        k("item base", 1, True, True),
        k("pack list page", 1, True, False),
        k("material pages 2, gold, next_item, core", 5),
    ], "the offer (registry)"),
    ("`recycle`", 300_000, 1, 0, [
        k("item base, pack list: a swap removal (2), core", 4),
        k("material pages", 2, True, False),
    ], "the base's materials (registry)"),
    ("`personalise`", 300_000, 1, 0, [
        k("item base, stillstone page, gold, core (the last stone: pack_lanes)", 4),
    ], "the fee (registry)"),
    ("`identify`", 350_000, 2, 0, [
        k("item mods (they come to exist)", 1, True, True),
        k("item base (IDENTIFIED), gold", 2),
    ], "calls: registry, fate"),
    ("`lift_modifier`, with a stone", 350_000, 1, 0, [
        k("component base and mods", 2, True, True),
        k("pack list page", 1, True, False),
        k("item mods, next_item, stillstone page, core (last stone), gold", 5),
    ], "the modifier (registry)"),
    ("`lift_modifier`, without (destroyed)", 350_000, 2, 0, [
        k("component base and mods", 2, True, True),
        k("item base, pack list: a swap removal (2), next_item, gold", 5),
    ], "calls: registry, fate"),
    ("`set_modifier`, with a stone", 350_000, 1, 0, [
        k("returned component: base and mods", 2, True, True),
        k("item mods, consumed component base, pack list pages 2, next_item, stillstone page, core, gold", 8),
    ], ""),
    ("`brew`, a new pair", 500_000, 2, 0, [
        k("grimoire state and pairs", 2, True, False),
        k("potion page", 1, True, False),
        k("ingredient pages 2, core", 3),
    ], "calls: registry (book), fate"),
    ("`buy_hint`", 350_000, 2, 0, [
        k("grimoire state, stillstone page, core (last stone)", 3),
    ], "calls: registry, fate"),
    ("`stow`, to the vault (8 + 8)", 400_000, 0, 0, [
        k("vault list pages, appended", 2, True, False),
        k("vault balance pages", 8, True, False),
        k("vault gold", 1, True, False),
        k("item bases 8, pack list pages 4, pack pages 8, pack gold, core", 22),
    ], ""),
    ("`stow`, to the pack (8 + 8)", 400_000, 0, 0, [
        k("pack balance pages", 8, True, False),
        k("pack list pages, appended", 2, True, False),
        k("pack gold", 1, True, False),
        k("vault list pages: 8 swap removals (8 hole pages + the tail's 2)", 10),
        k("vault balance pages 8, item bases 8, vault gold, core", 18),
    ], ""),
    ("`post_lot`, a balance", 300_000, 4, B, [
        k("lot (a new id)", 1, True, True),
        k("seller page k (the 4th lot: page 1)", 1, True, False),
        k("escrow page", 1, True, False),
        k("lot_count, open_lot_count, seller page 0 (count), pack page, vault gold (fee), account record, core", 7),
    ], "calls: hub seller, escrow, gold; registry (key)"),
    ("`post_lot`, equipment", 300_000, 4, B, [
        k("lot", 1, True, True),
        k("seller page k", 1, True, False),
        k("lot_count, open_lot_count, seller page 0, item base, pack list: a swap removal (2), vault gold, account record", 8),
    ], ""),
    ("`buy_lot`", 300_000, 3, S, [
        k("seller's vault gold", 1, True, False),
        k("buyer's vault page or vault list page", 1, True, False),
        k("lot, open_lot_count, seller pages: a swap removal (hole, last, page 0), buyer's gold, escrow page or item base, account record", 8),
    ], "calls: seller, gold, release"),
    ("`withdraw_lot`, `return_lot`", 300_000, 2, S, [
        k("vault page or vault list page", 1, True, False),
        k("lot, open_lot_count, seller pages 3, escrow page or item base, account record", 7),
    ], ""),
    ("`open_trade`", 300_000, 1, S, [
        k("trade head (a new id)", 1, True, True),
        k("trade_count", 1),
    ], ""),
    ("`set_trade_side`", 200_000, 1, 0, [
        k("the side's 2 words", 2, True, False),
        k("head", 1),
    ], ""),
    ("`confirm_trade`, the swap (7 + 7)", 800_000, 1, S, [
        k("pack list pages appended, 2 a side", 4, True, False),
        k("balance pages credited, 2 a side", 4, True, False),
        k("pack gold credited, a side", 2, True, False),
        k("head, item bases 14, pack list removals 4 a side, balance pages debited 4, cores 2", 29),
    ], ""),
    ("`confirm_trade` (first), `decline_trade`, `cancel_trade`", 100_000, 1, S, [k("head", 1)], ""),
    ("`Registry.set_record`", 50_000, 0, 0, [
        k("parts", 3, True, True),
        k("last_ids", 1, True, False),
    ], "administration"),
    ("admin setters, `upgrade`", 100_000, 0, 0, [k("addresses", 4)], "administration"),
]


def rift_keys():
    enter = next(r for r in ROWS if r[0].startswith("`enter` "))[4]
    return enter + [k("the account's board", 1, True, False)]


def rows():
    out = []
    for name, compute, calls, events, keys, basis in ROWS:
        if keys is None:
            keys = rift_keys()
        (cn, co), (inn, io) = tally(keys)
        out.append((name, compute, calls, events, (cn, co), (inn, io),
                    gas(compute, calls, inn, io, events), gas(compute, calls, cn, co, events), basis))
    return out


def m(value):
    return f"{value / 1e6:.2f} M"


def keys_table():
    print("| Entrypoint | Keys written (count; **N** new when cold; **N!** new every time) | Cold N / O | Initialised N / O |")
    print("|---|---|---|---|")
    for name, _, _, _, keys, _ in ROWS:
        if keys is None:
            keys = rift_keys()
        parts = []
        for kname, count, cold_new, init_new, init_count in keys:
            mark = " **N!**" if init_new else (" **N**" if cold_new else "")
            shown = f"{count}" if init_count == count else f"{count} cold, {init_count} after"
            parts.append(f"{kname} ({shown}){mark}")
        (cn, co), (inn, io) = tally(keys)
        print(f"| {name} | {' · '.join(parts) if parts else 'none'} | {cn} / {co} | {inn} / {io} |")


def main():
    import sys
    if "--keys" in sys.argv:
        keys_table()
        return
    print("| Entrypoint | Computation (E) | Calls | Events | Initialised: N / O → L2 | Cold: N / O → L2 | Basis |")
    print("|---|---:|---:|---:|---|---|---|")
    for name, compute, calls, events, cold, init, g_init, g_cold, basis in rows():
        print(f"| {name} | {m(compute)} | {calls} | {events:,} | {init[0]} / {init[1]} → **{g_init:,}** "
              f"| {cold[0]} / {cold[1]} → **{g_cold:,}** | {basis} |")

    print("\n§10.1 — a batch of weight 10, the cap of E-16 (16 goblins), no reveal:")
    words = {"goblin words (16 × 2)": 32, "chunk features (union of windows)": 9,
             "roster pages (swap removals touch all 4)": 4, "header, entropy": 2,
             "member transient words": 4, "hub report (core, quiver 4)": 5}
    total_words = sum(words.values())
    for name, count in words.items():
        print(f"  {name}: {count}")
    events = 16 * B + 2 * S  # kills, Defeated, BatchPlayed
    for label, tick in (("alone", TICK_ALONE), ("shared", TICK_SHARED)):
        low = F + 10 * tick + 10 * WINDOW_LOW + O * total_words + 2 * C + events
        high = low + 10 * (WINDOW_HIGH - WINDOW_LOW)
        print(f"  ticks {label}: {total_words} words; {low:,} to {high:,}")
    print(f"  cap 24 instead of 16: +{16 * O:,} (16 more words overwritten)")
    print(f"  cold, the 32 goblin words and 2 roster pages new: +{34 * (N - O):,}")
    # One action that cannot be split: 3 ticks, 42 goblins, cold.
    words3 = 84 + 4 + 4 + 2 + 4 + 5
    base3 = F + 3 * (TICK_ALONE + WINDOW_HIGH) + 2 * C + 42 * B + 2 * S
    print(f"  one 3-tick action alone, 42 goblins: initialised {base3 + O * words3:,}; "
          f"cold (84 goblin words + 3 roster pages new) {base3 + O * (words3 - 87) + N * 87:,}; "
          f"with one word per goblin (E-1 b) cold {base3 + O * (words3 - 45 - 3) + N * (42 + 3):,}")


if __name__ == "__main__":
    main()
