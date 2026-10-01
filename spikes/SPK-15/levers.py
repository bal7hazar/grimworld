#!/usr/bin/env python3
"""SPK-15: the levers' table, from the measured pairs (D) and the figures the brief cites (C).

    python3 spikes/SPK-15/levers.py spikes/SPK-15/snforge-test-output-1.txt [...-2.txt]

Every per-tick figure is at the worst tick inside a batch of 10 (CBT-02d's basis); "E" marks a
figure derived here by arithmetic from measured terms, never measured whole. S1 counts 300 ticks
(SPK-1 §5: 100 fights, 36 queues of 5 and 20 other actions near goblins, one tick an action); its
dollars are cost-budget.md §2's: 1 M L2 gas = $0.000881.
"""
import re
import sys

runs = []
for path in sys.argv[1:]:
    gas = {}
    for line in open(path):
        m = re.match(r"\[PASS\] \S+::(\w+) \(.*l2_gas: ~(\d+)\)", line)
        if m:
            gas[m.group(1)] = int(m.group(2))
    runs.append(gas)
for run in runs[1:]:
    assert run == runs[0], "the runs differ (D-154): report both"
g = runs[0]


def pair(name, base):
    return g[name] - g[base]


# --- Cited (C) ---
TARGET = 1_469_435
CBT02D = 3_447_872  # ENG-01 §9.2, CBT-02d fix loop 1
CBT04 = 2_368_590  # 16 × 108,100 + 7 × 76,820 + 9 × 11,250
CBT03A = 693_750  # 15 × 46,250
NOW = CBT02D + CBT04 + CBT03A
REP = 1_065_651
HIT = 46_250  # CBT-03a's one hit (the brief's line: 693,750 / 15)
PREDICATES = 11_250  # CBT-04's predicate set
CALL = 3_324_580  # CBT-02d: the library call, every list at its bound
CONTENT = 578_004  # a tick's share of the content, once a batch
MAP = 1_106_666  # LIB-05 M1-T9b, the map library's worst tick (window 64,234; flood 22,746 a layer)
FLOOD_LAYER = 22_746
FLOOD_15 = 364_878  # LIB-05: the flood at 15 layers
REP_FIXED = 184_105 * 10 + 240_840 * 10  # CBT-02d: the representative's load, store, call, content a call
WINDOW_4 = 64_234
BATCH = 10
TICKS_S1 = 300
USD_PER_GAS = 0.000881 / 1e6

# --- Measured (D) ---
words_main = pair("test_pair_words_bound_main", "test_words_bound_fixture")
words_lazy = pair("test_pair_words_bound_lazy", "test_words_bound_fixture")
rep_main = pair("test_pair_words_representative_main", "test_words_representative_fixture")
rep_lazy = pair("test_pair_words_representative_lazy", "test_words_representative_fixture")
touch_main = pair("test_pair_touch_main", "test_touch_main_fixture")
touch_lazy = pair("test_pair_touch_lazy", "test_touch_lazy_fixture")
index = pair("test_pair_index", "test_index_fixture")
awake_main = max(
    pair("test_pair_awake_main_formed", "test_awake_main_fixture"),
    pair("test_pair_awake_main_kept", "test_awake_main_kept_fixture"),
)
awake_single = max(
    pair("test_pair_awake_single_formed", "test_awake_lazy_fixture"),
    pair("test_pair_awake_single_kept", "test_awake_lazy_kept_fixture"),
)
scan = pair("test_pair_selection_scan", "test_selection_fixture")
single = pair("test_pair_selection_single", "test_selection_fixture")
m_cbt04 = pair("test_pair_member_cbt04_apply", "test_member_base")
m_given = pair("test_pair_member_cbt04_apply_given", "test_member_base")
m_kit = pair("test_pair_member_part_infliction", "test_member_base")
m_in_place = pair("test_pair_member_in_place", "test_member_base")
m_knock = pair("test_pair_member_knock", "test_member_base")
m_split = pair("test_pair_member_split", "test_member_base")
m_hot = pair("test_pair_member_hot", "test_member_base")
g_cbt04 = pair("test_pair_goblin_cbt04_apply", "test_goblin_base")
g_in_place = pair("test_pair_goblin_in_place", "test_goblin_base")
hit_end = pair("test_pair_executor_goblin_hit", "test_executor_fixture")
hit_guarded = pair("test_pair_executor_goblin_hit_guarded", "test_executor_hit_guarded_fixture")
guard = pair("test_pair_executor_guard", "test_executor_gather_fixture")
bomb_each = pair("test_pair_executor_bomb_each", "test_executor_fixture")
bomb_flushed = pair("test_pair_executor_bomb_flushed", "test_executor_fixture")
entry = pair("test_pair_executor_entry", "test_executor_entry_fixture")
awake_ticks = {n: pair(f"test_pair_design_awake_{n}", f"test_design_awake_{n}_fixture") for n in (8, 6, 4, 0)}
rep_ticks = {n: pair(f"test_pair_design_representative_{n}", f"test_design_representative_{n}_fixture") for n in (8, 6, 4)}
window_main = {n: pair(f"test_pair_design_window_{n}_main", f"test_design_window_{n}_fixture") for n in (100, 60, 40)}
window_lazy = {n: pair(f"test_pair_design_window_{n}_lazy", f"test_design_window_{n}_fixture") for n in (100, 60, 40)}

# --- The counts of a worst tick (CBT-04's and CBT-03a's, ENG-01 §9.2) ---
AWAKE = 8
MEMBER_APPS = 16  # 2 a goblin carrier
GOBLIN_APPS = 7  # the member's one carrier
HITS = 15  # 8 goblins and a bomb's 7
ENTRIES = AWAKE * 4 + 7  # a goblin carrier: its skill's 3 and its held effect's 1; the member's 7
CONTENT_ENTRIES = 38 * 3 + 4  # every skill's 3 entries and the 4 potions'

# --- The engineering levers, per tick at the worst ---
l1 = (words_main - words_lazy) // BATCH
l1_rep = (rep_main - rep_lazy) // BATCH
correction = MEMBER_APPS * (m_cbt04 - m_given) - m_kit  # the member's kit read once a carrier
cbt04_measured = CBT04 - correction
l2 = MEMBER_APPS * (m_given - m_knock) + GOBLIN_APPS * (g_cbt04 - g_in_place)
exec_naive = (
    AWAKE * (hit_end - HIT)
    + (bomb_each - GOBLIN_APPS * (HIT + g_cbt04) - m_kit)
    + ENTRIES * entry
)
exec_levered = (
    guard
    + AWAKE * (hit_guarded - HIT)
    + (bomb_flushed - GOBLIN_APPS * (HIT + g_cbt04) - m_kit)
    + CONTENT_ENTRIES * entry // BATCH
)
l3 = exec_naive - exec_levered
l4 = awake_main - awake_single


def m(x):
    return f"{x:,}"


def s1(x):
    gas = x * TICKS_S1
    return f"{gas / 1e6:,.1f} M (${gas * USD_PER_GAS:.3f})"


print("## The measured pairs used\n")
for k, v in [
    ("load and store, main / lazy (bound words)", f"{m(words_main)} / {m(words_lazy)}"),
    ("load and store, main / lazy (representative words)", f"{m(rep_main)} / {m(rep_lazy)}"),
    ("a frozen goblin touched, main / lazy", f"{m(touch_main)} / {m(touch_lazy)}"),
    ("the content's index", m(index)),
    ("perception over 100, main / lazy single pass (worst of formed, kept)", f"{m(awake_main)} / {m(awake_single)}"),
    ("the selection alone, 8 scans / one pass", f"{m(scan)} / {m(single)}"),
    ("member: CBT-04 / source given / kit read / in place / knock / 1–4 / 1–3", f"{m(m_cbt04)} / {m(m_given)} / {m(m_kit)} / {m(m_in_place)} / {m(m_knock)} / {m(m_split)} / {m(m_hot)}"),
    ("goblin: CBT-04 / in place", f"{m(g_cbt04)} / {m(g_in_place)}"),
    ("a goblin's hit end to end / guarded / the guard", f"{m(hit_end)} / {m(hit_guarded)} / {m(guard)}"),
    ("a bomb on 7, each / flushed", f"{m(bomb_each)} / {m(bomb_flushed)}"),
    ("an entry decoded", m(entry)),
    ("the costliest tick at 8 / 6 / 4 / 0 awake", " / ".join(m(awake_ticks[n]) for n in (8, 6, 4, 0))),
    ("load and store at 100 / 60 / 40 goblins, main", " / ".join(m(window_main[n]) for n in (100, 60, 40))),
    ("the same, lazy", " / ".join(m(window_lazy[n]) for n in (100, 60, 40))),
]:
    print(f"- {k}: {v}")

print("\n## Engineering levers (per tick, worst inside a batch of 10)\n")
print(f"- CBT-04's line re-measured: {m(CBT04)} -> {m(cbt04_measured)} (−{m(correction)})")
print(f"- L1 frozen goblins as words: −{m(l1)}; representative {m(-l1_rep)} (a cost); S1 ceiling {s1(l1)}")
print(f"- L2 applications in place, by condition: −{m(l2)}; S1 ceiling {s1(l2)}")
print(f"- L3 the executor: naive {m(exec_naive)} (E) -> levered {m(exec_levered)} (E): −{m(l3)}; S1 ceiling {s1(l3)}")
print(f"- L4 perception: {m(awake_main)} -> {m(awake_single)}: −{m(l4)}; S1 ceiling {s1(l4)}")

basis_now = CBT02D + cbt04_measured + CBT03A
basis_after = basis_now - l1 - l2
print(f"\n- The brief's basis (CBT-02d + CBT-04 + CBT-03a): {m(NOW)} cited; {m(basis_now)} re-measured "
      f"({basis_now / TARGET:.2f}x) -> {m(basis_after)} with L1 and L2 ({basis_after / TARGET:.2f}x)")
full_naive = basis_now + exec_naive + awake_main + MAP
full_after = basis_after + exec_levered + awake_single + MAP
print(f"- Everything counted (+ executor, perception, the map): {m(full_naive)} ({full_naive / TARGET:.2f}x) "
      f"-> {m(full_after)} ({full_after / TARGET:.2f}x)")

print("\n## Design levers (per tick, after the engineering levers)\n")
walker = (MAP - WINDOW_4 - FLOOD_15) // AWAKE
per_goblin_carrier = 2 * m_knock + PREDICATES + HIT + (hit_guarded - HIT)
for n in (6, 4):
    fewer = AWAKE - n
    d = (awake_ticks[8] - awake_ticks[n]) + fewer * per_goblin_carrier + fewer * walker
    print(f"- awake {AWAKE} -> {n}: tick −{m(awake_ticks[8] - awake_ticks[n])} (D), carriers −{m(fewer * per_goblin_carrier)} (E), "
          f"walkers −{m(fewer * walker)} (E): −{m(d)}; S1 ceiling {s1(d)}")
cap1 = AWAKE * m_knock
print(f"- one application on the member a goblin carrier (16 -> 8): −{m(cap1)} (E); S1 ceiling {s1(cap1)}")
per_target = HIT + g_in_place + (bomb_flushed - GOBLIN_APPS * (HIT + g_cbt04) - m_kit) // GOBLIN_APPS
print(f"- a carrier's targets 7 -> 3 (FX-35's bomb): −{m(4 * per_target)} (E, {m(per_target)} a target); S1 ceiling {s1(4 * per_target)}")
slope_main = (window_main[100] - window_main[40]) // 60
slope_lazy = (window_lazy[100] - window_lazy[40]) // 60
per_key = single // 100
win = 20 * slope_lazy // BATCH + WINDOW_4 // 2 + 5 * FLOOD_LAYER + 20 * per_key
print(f"- window 4 -> 2 chunks and flood 15 -> 10 layers: 20 goblins fewer in the call (−{m(20 * slope_lazy // BATCH)} lazy, "
      f"−{m(20 * slope_main // BATCH)} main), assembly −{m(WINDOW_4 // 2)} (E), flood −{m(5 * FLOOD_LAYER)}, "
      f"perception −{m(20 * per_key)} (E): −{m(win)}; S1 ceiling {s1(win)}")
fixed = words_lazy + CALL + CONTENT * BATCH
for n in (5, 8, 10, 20):
    print(f"- {n} ticks a batch: the per-call part {m(fixed // n)} a tick ({'+' if n < 10 else '−'}{m(abs(fixed // n - fixed // 10))} against 10)")


# --- The table: (lever, kind, worst, representative, cost in code, frozen interfaces, lots) ---
rows = [
    ("CBT-04's line re-measured (not a lever: the member's kit read once a carrier, not once an application)", "measure", correction, 0, "none", "none", "CBT-04 (its ENG-01 row)"),
    ("L1 frozen goblins kept as words", "engineering", l1, l1_rep, "`load`/`store` and perception over words; the index kept for the call", "`load`'s contract with perception (ENG-07); no stored layout", "ENG-07 (with perception)"),
    ("L2 an application in place, by condition", "engineering", l2, 0, "one inlined function a condition kind; the executor dispatches", "none (CBT-04's results kept)", "CBT-04 fix or CBT-05"),
    ("L3 the executor: the member's guard once a tick, a carrier's goblins flushed once, entries with the sheets", "engineering", l3, 0, "CBT-05's design; entries decoded into the sheets", "the call's content (`Sheets` grows by the entries)", "CBT-05"),
    ("L4 perception: one-pass selection, AI states kept at load", "engineering", l4, None, "the selection and the AI states (with L1)", "none", "ENG-07"),
]
for n in (6, 4):
    fewer = AWAKE - n
    d = (awake_ticks[8] - awake_ticks[n]) + fewer * per_goblin_carrier + fewer * walker
    rows.append((f"D1 awake {AWAKE} -> {n} (design/02, D-133, D-141)", "design", d, rep_ticks[8] - rep_ticks[n], "a constant", "`MAX_AWAKE`", "ENG-07; design/02"))
rows.append(("D2 one application on the member a goblin carrier (design/19 §5.14, §8)", "design", cap1, 0, "a check in the executor", "none", "CBT-05; design/19"))
rows.append(("D2' a carrier's targets 7 -> 3 (FX-35's bomb, `DISC_1`)", "design", 4 * per_target, 0, "content (a smaller shape)", "none", "CNT-01; design/19"))
map_part = WINDOW_4 // 2 + 5 * FLOOD_LAYER
rows.append(("D3 window 4 -> 2 chunks, flood 15 -> 10 layers (design/18)", "design", win, map_part, "the window's constants", "ENG-01's goblin bound (`MAX_GOBLINS`)", "ENG-07, LIB-05; design/18"))
rows.append(("D4 20 ticks a batch instead of 10 (design/02's weight)", "design", fixed // 10 - fixed // 20, REP_FIXED // 10 - REP_FIXED // 20, "a constant", "the batch's 40 M (ENG-01 §10.1)", "ENG-07; design/02"))

print("\n## The table\n")
print("| Lever | Kind | Worst tick | Representative tick | S1 (representative × 300) | S1 if every tick were the worst | Cost in code | Frozen interfaces | Lots |")
print("|---|---|---:|---:|---:|---:|---|---|---|")
for name, kind, worst, rep, code, frozen, lots in rows:
    rep_cell = "not measured" if rep is None else (f"−{m(rep)}" if rep >= 0 else f"+{m(-rep)}")
    s1_rep = "—" if rep is None else (f"−{s1(rep)}" if rep >= 0 else f"+{s1(-rep)}")
    print(f"| {name} | {kind} | −{m(worst)} | {rep_cell} | {s1_rep} | −{s1(worst)} | {code} | {frozen} | {lots} |")
