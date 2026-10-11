#!/usr/bin/env python3
"""OPS-01a's smoke test: `scripts/devnet_deploy.py` on the node `with-node.sh` started. From the
repository root, after the Cairo build:

    scripts/with-node.sh python3 scripts/tests/devnet_deploy_smoke.py

It deploys, reads `Instances.instance_state` for the instance the JSON names and asserts the entered
state (the id, chunks revealed, a member standing on a tile), then runs the script again and asserts it refuses.
"""
import json
import os
import subprocess
import sys
import tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, os.path.join(ROOT, "scripts"))
import devnet_deploy  # noqa: E402

LIVE = 1 << 250


def main():
    with tempfile.TemporaryDirectory() as tmp:
        out = os.path.join(tmp, "deployment.json")
        script = os.path.join(ROOT, "scripts", "devnet_deploy.py")
        subprocess.run([sys.executable, script, "--out", out], cwd=ROOT, check=True)
        with open(out) as f:
            dep = json.load(f)
        again = subprocess.run([sys.executable, script, "--out", out + ".2"], cwd=ROOT,
                               capture_output=True, text=True)
    assert again.returncode == 1 and "already has a deployment" in again.stderr, again.stderr
    assert not os.path.exists(out + ".2")

    node = devnet_deploy.Node(dep["node_url"], dep["account"], "unused",
                              os.environ.get("WITH_NODE_LOG_DIR", os.path.join(ROOT, ".with-node")))
    state = node.view("ephemeral", dep["contracts"]["instances"], "instance_state",
                      dep["instance_id"])
    # `InstanceView`: id, header, entropy, revealed, quotas, the task words (a span), the members'
    # words (a span, `MemberState` first)
    assert state[0] == dep["instance_id"], state
    assert dep["slot"] == dep["instance_id"] >> 32
    assert state[3] > LIVE, "no chunk revealed"
    words = state[6 + state[5]]
    assert words > 0, "no member in the instance"
    word = state[6 + state[5] + 1]  # the first member's word: x at bits 32-39, y at 40-47
    assert ((word >> 32) % 256, (word >> 40) % 256) != (0, 0), hex(word)
    assert dep["adventurer_id"] == 1
    for k in ("node_url", "chain_id", "commit", "account", "classes", "contracts"):
        assert dep[k], k
    assert "private" not in json.dumps(dep).lower()
    print("devnet_deploy smoke: ok")
    print(json.dumps(dep, indent=2))


main()
