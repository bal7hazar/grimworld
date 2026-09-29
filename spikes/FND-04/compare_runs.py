"""Compare two runs of trace.py, ignoring the order in which the RPC lists a state diff.

    git show <commit>:spikes/FND-04/traces.jsonl | python3 compare_runs.py traces.jsonl
"""
import json
import sys


def canon(d):
    d = json.loads(json.dumps(d))
    d["receipt"].pop("event_keys", None)
    d["receipt"].pop("event_data", None)
    for c in d["state_diff"]["storage"]:
        for e in c["entries"]:
            if e["key"].startswith("strk-key-"):
                e["key"] = "strk"
        c["entries"].sort(key=json.dumps)
    d["state_diff"]["storage"].sort(key=lambda c: c["contract"])
    d["state_diff"]["nonces"].sort()
    return d


old = [canon(json.loads(line)) for line in sys.stdin]
new = [canon(json.loads(line)) for line in open(sys.argv[1])]
diff = [i for i, (a, b) in enumerate(zip(old, new)) if a != b]
print(f"records {len(old)} / {len(new)}; differing once the order is ignored: {len(diff)} {diff[:10]}")
