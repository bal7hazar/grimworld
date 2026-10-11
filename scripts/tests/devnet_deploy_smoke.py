#!/usr/bin/env python3
"""OPS-01a's smoke test: `scripts/devnet_deploy.py` on the node `with-node.sh` started. From the
repository root, after the Cairo build:

    scripts/with-node.sh python3 scripts/tests/devnet_deploy_smoke.py

It deploys, reads `Instances.instance_state` for the instance the JSON names and asserts the entered
state (the id, chunks revealed, the member: the adventurer, INSIDE, on a tile), runs the script again and
asserts it refuses and writes nothing, checks the JSON holds no private key, and that `check_url` refuses
the non-local URL forms.
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
    word = state[6 + state[5] + 1]  # `MemberState`: adventurer 0-31, x 32-39, y 40-47, status 56-63
    assert word % (1 << 32) == dep["adventurer_id"], hex(word)
    assert (word >> 56) % 256 == 0, f"status is not INSIDE: {hex(word)}"  # member::INSIDE
    assert ((word >> 32) % 256, (word >> 40) % 256) != (0, 0), hex(word)
    assert dep["adventurer_id"] == 1
    for k in ("node_url", "chain_id", "commit", "account", "classes", "contracts"):
        assert dep[k], k
    secret = os.environ["NODE_ACCOUNT_PRIVATE_KEY"].lower().removeprefix("0x").lstrip("0")
    assert secret and secret not in json.dumps(dep).lower(), "the JSON holds the private key"
    for bad in ("http://127.0.0.1@evil.example:80", "http://evil.example\\@127.0.0.1:80",
                "http://127.0.0.1:80@evil.example", "http://localhost:80", "https://127.0.0.1:80",
                "http://127.0.0.1", "http://user@127.0.0.1:80"):
        try:
            devnet_deploy.check_url(bad)
        except SystemExit:
            continue
        raise AssertionError(f"check_url accepted {bad}")
    devnet_deploy.check_url(dep["node_url"])
    print("devnet_deploy smoke: ok")
    print(json.dumps(dep, indent=2))


main()
