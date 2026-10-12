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

SEED-02 (D-275, D-280): in `--full` the bar read back from the chain holds the four skills the JSON names
(the instant attack, the activation skill, the trap and the REGENERATION skill), the belt holds both potions
and `build.dropped` is empty; `Hub.instances` read from the chain's storage is the `Instances` address again
after the gold harness; the second entry carries the whole bar and belt. Before any node, the gold step's own
checks run on a stub node: it refuses a chain id that is not a local devnet's, a node that is not a devnet and
a non-local URL, and sends nothing then; on a devnet it credits exactly the four skills' price, restores
`Hub.instances` and fails when the read-back is not the `Instances` address. The Keccak behind the storage
key is checked against a known selector.

SMOKE-CI (D-290): the potion words of the seed (`seed_records.item` and `regeneration_item`) are compared with
`SEED_HEAL` and `SEED_REGEN`, parsed from `contracts/logic/src/types/action.cairo`; the job `devnet-smoke` of
`.github/workflows/ci.yml` runs this file.
"""
import json
import os
import re
import subprocess
import sys
import tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, os.path.join(ROOT, "scripts"))
sys.path.insert(0, os.path.join(ROOT, "contracts", "tools"))
import devnet_deploy  # noqa: E402

LIVE = 1 << 250
EMPTY_BUILD = 255 << 168
BUILD, BELT = 2, 3  # the words of `Hub.adventurer`: core, place, build, belt, equipped, name
HUB_GATE_BACK = 2


def logs():
    return os.environ.get("WITH_NODE_LOG_DIR", os.path.join(ROOT, ".with-node"))


class Stub:
    """A node that answers a chain id and records what is sent (no process, no network)."""

    def __init__(self, chain, devnet=True, url="http://127.0.0.1:5050", stored="0x2"):
        self.chain, self.devnet, self.url, self.stored = chain, devnet, url, stored
        self.address, self.sent = "0xacc", []

    def rpc(self, method, params):
        if method == "starknet_chainId":
            return "0x" + self.chain.encode().hex()
        if method == "devnet_getPredeployedAccounts":
            if not self.devnet:
                raise RuntimeError("Method not found")
            return []
        if method == "starknet_getStorageAt":
            assert params["key"] == hex(devnet_deploy.storage_key("instances")), params
            return self.stored
        raise AssertionError(method)

    def invoke(self, contract, function, *calldata):
        self.sent.append((function, calldata))
        events = [{"from_address": "0x2", "keys": ["0x1", "0x5"], "data": ["0x1", "0x2", "0x3"]}]
        return {"events": events}


def refused(call, *args):
    try:
        call(*args)
    except SystemExit as error:
        return str(error)
    raise AssertionError("not refused")


def check_gold_harness():
    """D-280's three conditions, on stub nodes: the chain-id refusal, the restore and its read-back,
    and the amount."""
    devnet_deploy.check_url("http://127.0.0.1:5050")
    assert devnet_deploy.assert_local_devnet(Stub("SN_SEPOLIA")) == "SN_SEPOLIA"
    for chain in ("SN_MAIN", "SN_GOERLI", "", "SN_SEPOLIA_X"):
        message = refused(devnet_deploy.assert_local_devnet, Stub(chain))
        assert "local devnet only" in message and "chain id" in message, message
    assert "devnet only" in refused(devnet_deploy.assert_local_devnet, Stub("SN_SEPOLIA", devnet=False))
    refused(devnet_deploy.assert_local_devnet, Stub("SN_SEPOLIA", url="https://sepolia.example"))
    # the refusal comes before any transaction: the step sends nothing on a chain that is not a devnet
    main_net = Stub("SN_MAIN")
    refused(devnet_deploy.fund_pack, main_net, "0x1", "0x2", "0x3", "0x4", "0x5", 1, [(1, 4)],
            devnet_deploy.GOLD)
    assert main_net.sent == [], main_net.sent
    # the amount is the four skills at D-277's prices, no margin
    assert devnet_deploy.SKILL_PRICES == (50, 60, 70, 80) and devnet_deploy.GOLD == 260
    # on a devnet: enter, the account as `instances`, the report with the gold, the real `Instances`
    # back, leave; and `Hub.instances` read back is checked
    node = Stub("SN_SEPOLIA", stored="0x2")
    devnet_deploy.fund_pack(node, "0x1", "0x2", "0x3", "0x4", "0x5", 1, [(1, 4)], devnet_deploy.GOLD)
    steps = [(function, calldata[0] if function == "set_contracts" else None)
             for function, calldata in node.sent]
    assert steps == [("enter", None), ("set_contracts", "0x3"), ("report", None),
                     ("set_contracts", "0x3"), ("leave", None)], steps
    sent = {i: calldata for i, (_, calldata) in enumerate(node.sent)}
    assert sent[1][1] == "0xacc" and sent[3][1] == "0x2", "the account, then the real Instances"
    report = sent[2]
    assert report[4] == devnet_deploy.GOLD, report  # Results.gold: instance, [1, adventurer], xp, gold
    # the restore is checked even when the report fails, and a wrong read-back fails the run
    wrong = Stub("SN_SEPOLIA", stored="0xacc")
    try:
        devnet_deploy.fund_pack(wrong, "0x1", "0x2", "0x3", "0x4", "0x5", 1, [(1, 4)],
                                devnet_deploy.GOLD)
    except RuntimeError as error:
        assert "not restored" in str(error), error
    else:
        raise AssertionError("a Hub.instances that was not restored passed")
    assert wrong.sent[-1][0] == "set_contracts", "no restore attempted"

    class Failing(Stub):
        def invoke(self, contract, function, *calldata):
            if function == "report":
                self.sent.append((function, calldata))
                raise RuntimeError("report reverted")
            return super().invoke(contract, function, *calldata)

    failing = Failing("SN_SEPOLIA", stored="0x2")
    try:
        devnet_deploy.fund_pack(failing, "0x1", "0x2", "0x3", "0x4", "0x5", 1, [(1, 4)],
                                devnet_deploy.GOLD)
    except RuntimeError as error:
        assert "report reverted" in str(error), error
    else:
        raise AssertionError("a reverted report passed")
    assert [f for f, _ in failing.sent] == ["enter", "set_contracts", "report", "set_contracts"]
    assert failing.sent[-1][1][1] == "0x2", "the real Instances restored after a failed report"
    # Keccak-256 (the original padding), behind the storage key: `transfer`'s selector
    assert devnet_deploy.storage_key("transfer") == \
        0x83afd3f4caedc6eebf44246fe54e38c95e3179a5ec9ea81740eca5b482d12e
    assert devnet_deploy.keccak256(b"").hex() == \
        "c5d2460186f7233c927e7db2dcc703c0e500b653ca82273b7bfad8045d85a470"
    # SEED-02 fix loop 1, SMOKE-CI (D-290): the potions' entries carry filter ALLIES (bit 91), the words
    # `action.cairo`'s `test_seed_potions_drunk` drinks. They are parsed from the Cairo constants, so a seed
    # drift (or an edit of the test's words) fails here, in CI.
    from seed_records import item, regeneration_item, POTION
    check_potion_words(item(POTION)[0], regeneration_item()[0], cairo_potion_words())
    print("devnet_deploy smoke (gold harness, stub nodes): ok")


ACTION_CAIRO = os.path.join(ROOT, "contracts", "logic", "src", "types", "action.cairo")
ALLIES = 1 << 91  # the filter bit of a potion's entry: the source is its own ally


def cairo_potion_words():
    """`SEED_HEAL` and `SEED_REGEN` of action.cairo (the drink test's hard-coded words), parsed."""
    with open(ACTION_CAIRO, encoding="utf-8") as f:
        text = f.read()
    words = {}
    for name in ("SEED_HEAL", "SEED_REGEN"):
        found = re.findall(rf"const {name}: u128 = (0x[0-9a-fA-F_]+);", text)
        assert len(found) == 1, f"{name} not found once in {ACTION_CAIRO}: {found}"
        words[name] = int(found[0].replace("_", ""), 16)
    return words


def check_potion_words(heal, regen, cairo):
    """The seed's potion entries (`seed_records.item` word 0 >> 128, 120 bits) against the Cairo constants,
    and the ALLIES bit (91) set in both."""
    mask = (1 << 120) - 1
    for name, seed in (("SEED_HEAL", heal), ("SEED_REGEN", regen)):
        word = seed >> 128 & mask
        assert word == cairo[name], f"{name}: seed {word:#x}, action.cairo {cairo[name]:#x}"
        assert word & ALLIES, f"{name} {word:#x}: bit 91 (ALLIES) is clear"


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
    """`--build full`: the ids in the key, the bar read back, the pack on the chain, a second entry
    with the same bar and belt."""
    build = dep["build"]
    words = check_build(node, dep, "full")
    assert build["belt"], "an empty belt"
    for kind in build["belt"]:
        funded = [p["count"] for p in build["pack"] if p["item"] == kind["item"]]
        kept = [p["count"] for p in build["pack_after_entry"] if p["item"] == kind["item"]]
        assert funded == [2 * kind["count"]], (kind, build["pack"])
        assert kept and kept[0] >= kind["count"], f"no second entry in the pack: {build}"
    # `pack_after_entry` is derived by the script (no pack view): the chain checks below are the proof
    assert build["derived"] == ["pack_after_entry"], build
    # SEED-02: nothing dropped, the four skills on the bar (read back from the chain by `check_build`)
    assert build["dropped"] == {}, build["dropped"]
    skills = build["skills"]
    assert list(skills) == ["instant_attack", "activation_skill", "trap", "regeneration_skill"], skills
    assert build["bar"][:4] == list(skills.values()) and build["bar"][4:] == [0] * 4, build["bar"]
    assert len(set(skills.values())) == 4 and all(skills.values()), skills
    on_chain = [(words[BUILD] >> (16 * slot)) % (1 << 16) for slot in range(8)]
    assert on_chain == build["bar"], on_chain
    assert build["gold"] == 260, build["gold"]  # the four skills at D-277's prices, nothing over
    items = [b["item"] for b in build["belt"]]
    assert len(items) == 2 and items[0] != items[1], build["belt"]  # healing and REGENERATION potions
    # D-280: the harness gave `Hub.instances` back to the real `Instances`
    hub, instances = dep["contracts"]["hub"], dep["contracts"]["instances"]
    assert devnet_deploy.hub_instances(node, hub) == int(instances, 16), "Hub.instances not restored"
    assert devnet_deploy.hub_instances(node, hub) != int(dep["account"], 16)
    # on the chain: out of the instance (the belt's reserve comes back), the pack holds twice the belt
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
    # the bar's skills are known: the same bar and the whole belt go back, and the adventurer enters again
    bar = devnet_deploy.build_word(build["bar"])
    belt = devnet_deploy.belt_word([(b["item"], b["count"]) for b in build["belt"]])
    node.invoke(hub, "set_build", adventurer, bar, belt, 0)
    from_hub = node.view("persistent", hub, "adventurer", adventurer)[1:]
    assert from_hub[BUILD] == bar + LIVE and from_hub[BELT] == belt + LIVE
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
    check_gold_harness()
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
