#!/usr/bin/env python3
"""OPS-01a's smoke test: `scripts/devnet_deploy.py` on the node `with-node.sh` started. From the
repository root, after the Cairo build:

    scripts/with-node.sh python3 scripts/tests/devnet_deploy_smoke.py

It deploys, reads `Instances.instance_state` for the instance the JSON names and asserts the entered
state (the id, chunks revealed, the member: the adventurer, INSIDE, on a tile), runs the script again and
asserts it refuses and writes nothing, checks the JSON holds no private key, and that `check_url` refuses
the non-local URL forms.

OPS-01b: it reads the adventurer's build back from the chain (`Hub.adventurer`'s build and belt words)
and checks it equals what the JSON's `build` key says was set. The default run is checked on this node
(an empty build). Then the same test runs once more on a node of its own (`with-node.sh`, `--full`), where
the script is run with `--build full`: the build key, the build read back, and the pack: after the entry the
JSON says what the pack kept, and on the chain the adventurer leaves, `set_build` accepts the belt twice over
(the pack holds twice the belt), refuses one more than that, and enters a second time with the same belt.
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
EMPTY_BUILD = 255 << 168
BUILD, BELT = 2, 3  # the words of `Hub.adventurer`: core, place, build, belt, equipped, name
HUB_GATE_BACK = 2


def logs():
    return os.environ.get("WITH_NODE_LOG_DIR", os.path.join(ROOT, ".with-node"))


def check_build(node, dep, mode):
    """The JSON's `build` key, and the adventurer's build read back from the chain equal to it."""
    build = dep["build"]
    assert build["mode"] == mode, build
    assert len(build["bar"]) == 8 and all(isinstance(s, int) for s in build["bar"]), build
    words = node.view("persistent", dep["contracts"]["hub"], "adventurer", dep["adventurer_id"])
    assert words[0] == 6 and len(words) == 7, words  # a span: its length, then the six words
    words = words[1:]
    bar = sum(skill << (16 * slot) for slot, skill in enumerate(build["bar"]))
    assert words[BUILD] == bar + EMPTY_BUILD + LIVE, (hex(words[BUILD]), build)
    belt = build["belt"]
    assert len(belt) <= 4
    expected = sum(b["item"] << (32 * lane) for lane, b in enumerate(belt)) \
        + (sum(b["count"] << (8 * lane) for lane, b in enumerate(belt)) << 128)
    assert words[BELT] == expected + LIVE, (hex(words[BELT]), belt)
    return words


def check_full(dep, node):
    """`--build full`: the ids in the key, the pack on the chain, a second entry with the same belt."""
    build = dep["build"]
    check_build(node, dep, "full")
    assert build["belt"], "an empty belt"
    for kind in build["belt"]:
        funded = [p["count"] for p in build["pack"] if p["item"] == kind["item"]]
        kept = [p["count"] for p in build["pack_after_entry"] if p["item"] == kind["item"]]
        assert funded == [2 * kind["count"]], (kind, build["pack"])
        assert kept and kept[0] >= kind["count"], f"no second entry in the pack: {build}"
    assert build["dropped"].get("regeneration_potion"), "the dropped parts are not named"
    assert all(name in build["skills_wanted"] or name in build["dropped"]
               for name in ("instant_attack", "activation_skill", "trap", "regeneration_skill"))
    # on the chain: out of the instance (the belt's reserve comes back), the pack holds twice the belt
    hub, instances = dep["contracts"]["hub"], dep["contracts"]["instances"]
    adventurer = dep["adventurer_id"]
    node.import_account()
    node.invoke(instances, "leave", dep["instance_id"], adventurer, 0, HUB_GATE_BACK)
    item, count = build["belt"][0]["item"], build["belt"][0]["count"]

    def belt_of(n):
        return item + (n << 128)

    node.invoke(hub, "set_build", adventurer, EMPTY_BUILD, belt_of(2 * count), 0)  # twice the belt
    try:
        node.invoke(hub, "set_build", adventurer, EMPTY_BUILD, belt_of(2 * count + 1), 0)
    except RuntimeError:
        pass
    else:
        raise AssertionError("the pack holds more than twice the belt")
    node.invoke(hub, "set_build", adventurer, EMPTY_BUILD, belt_of(count), 0)
    from_hub = node.view("persistent", hub, "adventurer", adventurer)[1:]
    assert from_hub[BELT] == belt_of(count) + LIVE
    second = devnet_deploy.entered(node.invoke(hub, "enter", adventurer, 1), instances)
    assert second != dep["instance_id"], "no second instance"
    print("devnet_deploy smoke (--build full): ok")
    print(json.dumps(build, indent=2))


def full():
    """On a node of its own (started by `main`): the script with `--build full`, and its checks."""
    with tempfile.TemporaryDirectory() as tmp:
        out = os.path.join(tmp, "deployment.json")
        script = os.path.join(ROOT, "scripts", "devnet_deploy.py")
        subprocess.run([sys.executable, script, "--build", "full", "--out", out], cwd=ROOT, check=True)
        with open(out) as f:
            dep = json.load(f)
    node = devnet_deploy.Node(dep["node_url"], dep["account"], os.environ["NODE_ACCOUNT_PRIVATE_KEY"],
                              logs())
    check_full(dep, node)


def main():
    if sys.argv[1:] == ["--full"]:
        return full()
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

    node = devnet_deploy.Node(dep["node_url"], dep["account"], "unused", logs())
    check_build(node, dep, "empty")
    assert dep["build"]["belt"] == [] and dep["build"]["pack"] == [], dep["build"]
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
    # VIEW-01: then the roster's pages (a span), the goblins (a span, 4 felts each: entity, derived,
    # state, timers), and the location's width, height and level_min, the last three felts
    at = 6 + state[5] + 1 + words
    at += 1 + state[at]
    goblins = state[at]
    at += 1 + 4 * goblins
    assert len(state) == at + 3, f"the view's tail: {state[at:]}"
    width, height = state[at], state[at + 1]
    assert 1 <= width <= 15 and 1 <= height <= 15, (width, height)
    assert all(state[at - 4 * goblins + 4 * g] >= 8 for g in range(goblins)), "an unloadable goblin"
    assert dep["adventurer_id"] == 1
    for k in ("node_url", "chain_id", "commit", "account", "classes", "contracts"):
        assert dep[k], k
    # FIX-02b: the goblin loader's class, `set_play_class` key 6 (`play_class::GOBLINS`)
    assert dep["classes"].get("goblins_library"), "no GoblinsLibrary"
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
    # a node of its own for `--build full`: its log directory apart, so node.log is not overwritten
    with tempfile.TemporaryDirectory() as tmp:
        env = {**os.environ, "WITH_NODE_LOG_DIR": os.path.join(tmp, "node")}
        subprocess.run([os.path.join(ROOT, "scripts", "with-node.sh"), sys.executable,
                        os.path.abspath(__file__), "--full"], cwd=ROOT, env=env, check=True)


main()
