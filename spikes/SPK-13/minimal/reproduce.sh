#!/usr/bin/env bash
# SPK-13: the reproduction of issue-draft.md, as it is pasted there. N clean builds of the minimal
# program; for each, the sha256 of the Sierra file and the function(s) that hold `withdraw_gas`
# (read from the JSON: the statement indices of the `withdraw_gas` invocations, against each
# function's entry point). A second argument sets RAYON_NUM_THREADS.
#
#   spikes/SPK-13/minimal/reproduce.sh N [threads]
set -euo pipefail
cd "$(dirname "$0")"
for _ in $(seq "$1"); do
  scarb clean
  if [ -n "${2:-}" ]; then RAYON_NUM_THREADS=$2 scarb build >/dev/null; else scarb build >/dev/null; fi
  python3 - <<'PY'
import hashlib, json
raw = open("target/dev/spk13_minimal.sierra.json", "rb").read()
p = json.loads(raw)
wg = {l["id"]["id"] for l in p["libfunc_declarations"] if l["long_id"]["generic_id"] == "withdraw_gas"}
funcs = sorted((f["entry_point"], f["id"]["debug_name"]) for f in p["funcs"])
at = [i for i, s in enumerate(p["statements"])
      if "Invocation" in s and s["Invocation"]["libfunc_id"]["id"] in wg]
holders = [max(f for f in funcs if f[0] <= i)[1] for i in at]
print(hashlib.sha256(raw).hexdigest()[:16], "withdraw_gas in:", ", ".join(holders))
PY
done
