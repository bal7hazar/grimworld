#!/usr/bin/env python3
"""SPK-15: every pair's difference from snforge's outputs (D-154: two clean builds, each run once).

    python3 spikes/SPK-15/summarize.py spikes/SPK-15/snforge-test-output-1.txt [...-2.txt]

Prints, for each pair `test_pair_X` against its base, the difference of snforge's totals in each
run, and whether the runs agree. The bases are named below (`BASES`).
"""
import re
import sys

BASES = {
    "test_pair_member_": "test_member_base",
    "test_pair_goblin_": "test_goblin_base",
    "test_pair_words_bound_": "test_words_bound_fixture",
    "test_pair_words_representative_": "test_words_representative_fixture",
    "test_pair_touch_main": "test_touch_main_fixture",
    "test_pair_touch_lazy": "test_touch_lazy_fixture",
    "test_pair_selection_": "test_selection_fixture",
    "test_pair_index": "test_index_fixture",
    "test_pair_executor_gather_guarded": "test_executor_guarded_fixture",
    "test_pair_executor_goblin_hit_guarded": "test_executor_hit_guarded_fixture",
    "test_pair_executor_guard": "test_executor_gather_fixture",
    "test_pair_executor_gather": "test_executor_gather_fixture",
    "test_pair_executor_entry": "test_executor_entry_fixture",
    "test_pair_executor_": "test_executor_fixture",
    "test_pair_design_awake_8": "test_design_awake_8_fixture",
    "test_pair_design_awake_6": "test_design_awake_6_fixture",
    "test_pair_design_awake_4": "test_design_awake_4_fixture",
    "test_pair_design_awake_0": "test_design_awake_0_fixture",
    "test_pair_design_representative_8": "test_design_representative_8_fixture",
    "test_pair_design_representative_6": "test_design_representative_6_fixture",
    "test_pair_design_representative_4": "test_design_representative_4_fixture",
    "test_pair_design_window_100_": "test_design_window_100_fixture",
    "test_pair_design_window_60_": "test_design_window_60_fixture",
    "test_pair_design_window_40_": "test_design_window_40_fixture",
}


STATES = ("formed", "kept_end", "kept_start", "replaced")


def base_of(name):
    # Perception (fix loop 1): `test_pair_perc_<rep>[_<selection>]_<state>` against
    # `test_perc_<rep>_<state>_fixture`.
    if name.startswith("test_pair_perc_"):
        rep = name[len("test_pair_perc_"):].split("_")[0]
        state = next(s for s in STATES if name.endswith("_" + s))
        return f"test_perc_{rep}_{state}_fixture"
    # The longest matching prefix names the base.
    best = None
    for prefix, base in BASES.items():
        if name.startswith(prefix) and (best is None or len(prefix) > len(best[0])):
            best = (prefix, base)
    return best[1] if best else None


runs = []
for path in sys.argv[1:]:
    gas = {}
    for line in open(path):
        m = re.match(r"\[PASS\] \S+::(\w+) \(.*l2_gas: ~(\d+)\)", line)
        if m:
            gas[m.group(1)] = int(m.group(2))
    runs.append(gas)

names = sorted(n for n in runs[0] if n.startswith("test_pair_"))
for name in names:
    base = base_of(name)
    diffs = [run[name] - run[base] for run in runs]
    agree = "same" if len(set(diffs)) == 1 else "differ"
    print(f"{name:45} {' / '.join(f'{d:>10,}' for d in diffs)}  ({agree}; base {base})")
