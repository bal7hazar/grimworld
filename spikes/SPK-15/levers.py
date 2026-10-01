#!/usr/bin/env python3
"""SPK-15: the levers' table, from the measured pairs (D) and the figures the brief cites (C).

    python3 spikes/SPK-15/levers.py spikes/SPK-15/snforge-test-output-1.txt [...-2.txt]

Every per-tick figure is at the worst tick inside a batch of 10 (CBT-02d's basis); "E" marks a
figure derived here by arithmetic from measured terms, never measured whole. S1 counts 300 ticks
(SPK-1 §5: 100 fights, 36 queues of 5 and 20 other actions near goblins, one tick an action); its
dollars are cost-budget.md §2's: 1 M L2 gas = $0.000881.

Fix loop 1: each engineering lever is priced alone against "everything counted" (the brief's basis,
CBT-05's executor, ENG-07's perception, the map library and the hooks' writes to frozen goblins),
L1 and L4 also together and each given the other (finding 1); perception at the worst of four
states on every representation (finding 4); the hooks' writes counted (finding 5); the batch's
ticks at the worst recomputed with the per-call part paid once and the batch's writes (finding 2).
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
CBT02D = 3_447_872  # ENG-01 §9.2, CBT-02d fix loop 1 (load and store's share inside, main's)
CBT04 = 2_368_590  # 16 × 108,100 + 7 × 76,820 + 9 × 11,250
CBT03A = 693_750  # 15 × 46,250
NOW = CBT02D + CBT04 + CBT03A
REP = 1_065_651
HIT = 46_250  # CBT-03a's one hit (the brief's line: 693,750 / 15)
PREDICATES = 11_250  # CBT-04's predicate set
CALL = 3_324_580  # CBT-02d: the library call, every list at its bound
CONTENT = 578_004  # a tick's share of the content, once a batch
MAP = 1_106_666  # LIB-05 M1-T9b, the map library's worst tick
FLOOD_LAYER = 22_746
FLOOD_15 = 364_878  # LIB-05: the flood at 15 layers
WINDOW_4 = 64_234  # LIB-05: the window assembled from 4 chunks
REP_FIXED = 184_105 * 10 + 240_840 * 10  # CBT-02d: the representative's load, store, call, content
ENG01_PERCEPTION = 4_663_510  # ENG-01 §9.2: main's selection at its maximum
HOOK_TOUCHES = 6  # ENG-01 §9.2 (CBT-02d escalation 3): frozen goblins a hook writes, an action
BATCH_CAP = 40_000_000  # design/02, ENG-01 §10.1
# ENG-01 §10.1's worst branch (64 keys, initialised) is 47,336,950 with 10 ticks as measured alone
# at 4.29 M each: its part outside the ticks (the batch's writes, calldata, events) is E.
BATCH_WRITES = 47_336_950 - 10 * 4_290_000
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
STATES = ("formed", "kept_end", "kept_start", "replaced")
FIXTURE_OF = {
    "main": "main",
    "decoded_scan": "decoded",
    "decoded_single": "decoded",
    "lazy_scan": "lazy",
    "lazy_single": "lazy",
}
perc = {}
for rep, fixture in FIXTURE_OF.items():
    perc[rep] = {st: pair("test_pair_perc_" + rep + "_" + st, "test_perc_" + fixture + "_" + st + "_fixture") for st in STATES}
worst = {rep: max(v.values()) for rep, v in perc.items()}
perc_main = max(worst["main"], ENG01_PERCEPTION)
perc_l4 = worst["decoded_single"]
perc_l1 = worst["lazy_scan"]
perc_l1l4 = worst["lazy_single"]
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
bomb_flushed_3 = pair("test_pair_executor_bomb_flushed_3", "test_executor_fixture")
entry = pair("test_pair_executor_entry", "test_executor_entry_fixture")
awake_ticks = {n: pair("test_pair_design_awake_%d" % n, "test_design_awake_%d_fixture" % n) for n in (8, 6, 4, 0)}
rep_ticks = {n: pair("test_pair_design_representative_%d" % n, "test_design_representative_%d_fixture" % n) for n in (8, 6, 4)}
window_main = {n: pair("test_pair_design_window_%d_main" % n, "test_design_window_%d_fixture" % n) for n in (100, 60, 40)}
window_lazy = {n: pair("test_pair_design_window_%d_lazy" % n, "test_design_window_%d_fixture" % n) for n in (100, 60, 40)}

# --- The counts of a worst tick (CBT-04's and CBT-03a's, ENG-01 §9.2) ---
AWAKE = 8
MEMBER_APPS = 16  # 2 a goblin carrier
GOBLIN_APPS = 7  # the member's one carrier
ENTRIES = AWAKE * 4 + 7  # a goblin carrier: its skill's 3 and its held effect's 1; the member's 7
CONTENT_ENTRIES = 38 * 3 + 4  # every skill's 3 entries and the 4 potions'

# --- The terms of everything counted, per worst tick ---
correction = MEMBER_APPS * (m_cbt04 - m_given) - m_kit  # the member's kit read once a carrier
cbt04_measured = CBT04 - correction
basis = CBT02D + cbt04_measured + CBT03A
exec_naive = AWAKE * (hit_end - HIT) + (bomb_each - GOBLIN_APPS * (HIT + g_cbt04) - m_kit) + ENTRIES * entry
exec_levered = (
    guard
    + AWAKE * (hit_guarded - HIT)
    + (bomb_flushed - GOBLIN_APPS * (HIT + g_cbt04) - m_kit)
    + CONTENT_ENTRIES * entry // BATCH
)
hooks_main = HOOK_TOUCHES * touch_main
hooks_l1 = HOOK_TOUCHES * touch_lazy
everything = basis + exec_naive + perc_main + MAP + hooks_main

# --- Each engineering lever: its saving on everything counted ---
l1_words = (words_main - words_lazy) // BATCH
l1_perc = perc_main - perc_l1  # negative: the 8 scans over words cost more
l1_hooks = hooks_main - hooks_l1
l1 = l1_words + l1_perc + l1_hooks
l2 = MEMBER_APPS * (m_given - m_knock) + GOBLIN_APPS * (g_cbt04 - g_in_place)
l3 = exec_naive - exec_levered
l4 = perc_main - perc_l4
l1l4 = l1_words + (perc_main - perc_l1l4) + l1_hooks
l1_given_l4 = l1l4 - l4
l4_given_l1 = l1l4 - l1
l1_rep = (rep_main - rep_lazy) // BATCH
all_eng = everything - correction * 0 - l1l4 - l2 - l3


def m(x):
    return f"{x:,}"


def sv(x):
    if x == 0:
        return "0"
    return f"−{m(x)}" if x > 0 else f"+{m(-x)}"


def s1(x):
    gas = x * TICKS_S1
    if gas == 0:
        return "0"
    sign = "−" if gas > 0 else "+"
    return f"{sign}{abs(gas) / 1e6:,.1f} M ({sign}${abs(gas) * USD_PER_GAS:.3f})"


print("## The measured pairs used\n")
for k, v in [
    ("load and store, main / L1 (bound words)", f"{m(words_main)} / {m(words_lazy)}"),
    ("load and store, main / L1 (representative words)", f"{m(rep_main)} / {m(rep_lazy)}"),
    ("a frozen goblin a hook touches, main / L1", f"{m(touch_main)} / {m(touch_lazy)}"),
    ("the content's index", m(index)),
    ("the selection alone, 8 scans / one pass", f"{m(scan)} / {m(single)}"),
    ("member: CBT-04 / source given / kit read / in place / knock / 1–4 / 1–3", f"{m(m_cbt04)} / {m(m_given)} / {m(m_kit)} / {m(m_in_place)} / {m(m_knock)} / {m(m_split)} / {m(m_hot)}"),
    ("goblin: CBT-04 / in place", f"{m(g_cbt04)} / {m(g_in_place)}"),
    ("a goblin's hit end to end / guarded / the guard", f"{m(hit_end)} / {m(hit_guarded)} / {m(guard)}"),
    ("a bomb on 7, each / flushed; on 3, flushed", f"{m(bomb_each)} / {m(bomb_flushed)}; {m(bomb_flushed_3)}"),
    ("an entry decoded", m(entry)),
    ("the costliest tick at 8 / 6 / 4 / 0 awake", " / ".join(m(awake_ticks[n]) for n in (8, 6, 4, 0))),
    ("the representative tick at 8 / 6 / 4", " / ".join(m(rep_ticks[n]) for n in (8, 6, 4))),
    ("load and store at 100 / 60 / 40 goblins, main", " / ".join(m(window_main[n]) for n in (100, 60, 40))),
    ("the same, L1", " / ".join(m(window_lazy[n]) for n in (100, 60, 40))),
]:
    print(f"- {k}: {v}")

print("\n## Perception over 100 candidates, by state (D)\n")
print("| Representation | " + " | ".join(STATES) + " | Worst |")
print("|---|" + "---:|" * (len(STATES) + 1))
for rep in FIXTURE_OF:
    print(f"| {rep} | " + " | ".join(m(perc[rep][st]) for st in STATES) + f" | **{m(worst[rep])}** |")
print(f"\nMain's worst taken as {m(perc_main)} (measured {m(worst['main'])}; ENG-01 {m(ENG01_PERCEPTION)}).")

print("\n## Everything counted, per worst tick (as it stands)\n")
for k, v in [
    ("the brief's basis, CBT-04 re-measured", basis),
    ("CBT-05's executor, naive (E)", exec_naive),
    ("ENG-07's perception", perc_main),
    ("the map library (C)", MAP),
    (f"the hooks' writes to frozen goblins, {HOOK_TOUCHES} (C count, D each)", hooks_main),
    ("**everything counted**", everything),
]:
    print(f"- {k}: {m(v)} ({v / TARGET:.2f}x)")

print("\n## Engineering levers, each priced on everything counted\n")
print(f"- CBT-04's line re-measured: {m(CBT04)} -> {m(cbt04_measured)} ({sv(correction)}), a measure")
print(f"- L1 alone: load and store {sv(l1_words)}, perception {sv(l1_perc)}, hooks {sv(l1_hooks)}: **{sv(l1)}** (without the hooks {sv(l1_words + l1_perc)})")
print(f"- L2 alone: **{sv(l2)}**")
print(f"- L3 alone: naive {m(exec_naive)} -> levered {m(exec_levered)}: **{sv(l3)}** (E)")
print(f"- L4 alone: perception {m(perc_main)} -> {m(perc_l4)}: **{sv(l4)}**")
print(f"- L1 and L4 together: **{sv(l1l4)}**; L1 given L4 {sv(l1_given_l4)} (without the hooks {sv(l1_given_l4 - l1_hooks)}); L4 given L1 {sv(l4_given_l1)}")
print(f"- All four: {m(everything)} -> {m(all_eng)} ({all_eng / TARGET:.2f}x)")
basis_after = basis - l1_words - l2
print(f"- The brief's basis alone: {m(NOW)} cited, {m(basis)} re-measured ({basis / TARGET:.2f}x) -> {m(basis_after)} with L1's load and store and L2 ({basis_after / TARGET:.2f}x)")

print("\n## Design levers (per worst tick, after the engineering levers)\n")
walker = (MAP - WINDOW_4 - FLOOD_15) // AWAKE
per_goblin_carrier = 2 * m_knock + PREDICATES + hit_guarded
d1 = {}
for n in (6, 4):
    fewer = AWAKE - n
    d1[n] = (awake_ticks[8] - awake_ticks[n]) + fewer * per_goblin_carrier + fewer * walker
    print(f"- awake {AWAKE} -> {n}: tick {sv(awake_ticks[8] - awake_ticks[n])} (D), carriers {sv(fewer * per_goblin_carrier)} (E), walkers {sv(fewer * walker)} (E): **{sv(d1[n])}**")
cap1 = AWAKE * m_knock
cap1_at4 = 4 * m_knock
print(f"- one application on the member a goblin carrier (16 -> 8): {sv(cap1)} (E); at 4 awake (8 -> 4) {sv(cap1_at4)}")
per_target = (bomb_flushed - bomb_flushed_3) // 4
bomb_fixed = bomb_flushed_3 - 3 * per_target
d2p = 4 * per_target
print(f"- a carrier's targets 7 -> 3: {m(per_target)} a target (D: the 7- and 3-target bombs), fixed part {m(bomb_fixed)}: **{sv(d2p)}**")
slope_main = (window_main[100] - window_main[40]) // 60
slope_lazy = (window_lazy[100] - window_lazy[40]) // 60
per_key = single // 100
win = 20 * slope_lazy // BATCH + WINDOW_4 // 2 + 5 * FLOOD_LAYER + 20 * per_key
print(f"- window 4 -> 2 chunks, flood 15 -> 10 layers: call {sv(20 * slope_lazy // BATCH)} (L1; main {sv(20 * slope_main // BATCH)}), assembly {sv(WINDOW_4 // 2)} (E), flood {sv(5 * FLOOD_LAYER)}, perception {sv(20 * per_key)} (E): **{sv(win)}**")
combo = all_eng - d1[4] - cap1_at4 - d2p - win
print(f"- 4 awake, one application a carrier, 3 targets, the smaller window and flood (D4 excluded: no batch of 10 holds a worst tick): {m(combo)} ({combo / TARGET:.2f}x) (E)")

print("\n## A worst batch against 40 M (per-call part once a batch)\n")
per_call = words_lazy + CALL + CONTENT * BATCH
per_call_main = words_main + CALL + CONTENT * BATCH
for label, total, call in [("as it stands", everything, per_call_main), ("after L1–L4", all_eng, per_call), ("and the design levers", combo, per_call)]:
    tick = total - call // BATCH
    n = 0
    while (n + 1) * tick + call + BATCH_WRITES <= BATCH_CAP:
        n += 1
    print(f"- {label}: a tick {m(tick)} without the per-call part {m(call)}; batch writes {m(BATCH_WRITES)} (E): **{n} worst tick{"" if n == 1 else "s"}** fit 40 M ({m(n * tick + call + BATCH_WRITES)})")
rep_fixed_20 = REP_FIXED // 10 - REP_FIXED // 20

# --- The table ---
rows = [
    ("CBT-04's line re-measured (the member's kit read once a carrier, not once an application)", "measure", correction, 0, "none", "none", "CBT-04"),
    ("**L1 alone**: frozen goblins kept as words, perception's 8 scans over words", "engineering", l1, l1_rep, "`load`, `store`, perception over words; the index kept for the call", "**`load`'s contract with perception** (ENG-07)", "ENG-07"),
    ("**L2** an application in place, by condition", "engineering", l2, 0, "one inlined function a condition kind", "none", "CBT-04's fix loop or CBT-05"),
    ("**L3** the executor: the guard once a tick and updated at every effect write, a carrier's goblins flushed once, entries with the sheets", "engineering", l3, 0, "CBT-05's design", "the call's content (`Sheets` gains the entries)", "CBT-05"),
    ("**L4 alone**: perception's one-pass selection on main's goblins", "engineering", l4, None, "the selection", "none", "ENG-07"),
    ("L1 given L4 (L1 and L4 together less L4 alone)", "engineering", l1_given_l4, l1_rep, "as L1", "as L1", "ENG-07"),
    ("L1 and L4 together", "engineering", l1l4, None, "both", "as L1", "ENG-07"),
]
for n in (6, 4):
    rows.append((f"D1 awake {AWAKE} → {n}", "design", d1[n], rep_ticks[8] - rep_ticks[n], "a constant", "`MAX_AWAKE`", "ENG-07; design/02, D-133, D-141"))
rows.append(("D2 one application on the member a goblin carrier", "design", cap1, 0, "a check in the executor", "none", "CBT-05; design/19 §5.14, §8"))
rows.append(("D2′ a carrier's targets 7 → 3 (FX-35's bomb)", "design", d2p, 0, "content", "none", "CNT-01; design/19 §9, FX-35"))
rows.append(("D3 window 4 → 2 chunks, flood 15 → 10 layers", "design", win, WINDOW_4 // 2 + 5 * FLOOD_LAYER, "the window's constants", "`MAX_GOBLINS`", "ENG-07, LIB-05; design/18"))

print("\n## The table\n")
print("| Lever | Kind | Worst tick | Representative tick | S1 (representative × 300) | S1 if every tick were the worst | Cost in code | Frozen interfaces | Lots |")
print("|---|---|---:|---:|---:|---:|---|---|---|")
for name, kind, w, rep, code, frozen, lots in rows:
    rep_cell = "not measured" if rep is None else sv(rep)
    s1_rep = "—" if rep is None else s1(rep)
    print(f"| {name} | {kind} | {sv(w)} | {rep_cell} | {s1_rep} | {s1(w)} | {code} | {frozen} | {lots} |")
print(f"| D4 20 ticks a batch instead of 10 (average case only: at the worst no batch holds 10 ticks) | design | not applicable | {sv(rep_fixed_20)} | {s1(rep_fixed_20)} | — | a constant | the batch's 40 M (ENG-01 §10.1) | ENG-07; design/02 |")
