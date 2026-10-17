#!/usr/bin/env python3
"""GATE-1a's smoke test: `scripts/sepolia_play.py --devnet` against the node `with-node.sh` started, end to end
(nothing here goes near Sepolia). From the repository root, after the classes are built
(`scripts/lock.sh --heavy scarb --manifest-path contracts/Scarb.toml build`):

    scripts/with-node.sh python3 -I scripts/tests/sepolia_play_smoke.py

  * the board: the batch word against `lifecycle_probe.py`'s encoding, the hex steps and distances, the
    newest deployment record (by date, then by `artefact.run`);
  * the refusals, each with its message and nothing sent: a local URL without `--devnet`, a remote URL with
    it, `--devnet` without `--out`, an `--out` under docs/reports, a Sepolia record with `--devnet`;
  * the bookkeeping, on stubs: a reverted transaction and one whose call failed without a hash (the nonce
    moved) stay in the record, the reverted one marked with its fee;
  * the views at `pre_confirmed` (Sepolia's tag) and at `latest` agree with `sncast call` on the devnet;
  * three faults injected after `enter` (a `ValueError` in the crossing, an `OSError` from every view, a
    `KeyboardInterrupt`, which goes on after): the run exits 1 or raises and still writes its record, every transaction the account sent, why, and where the
    adventurer is (inside its instance, read from the chain; or unknown, and why);
  * `scripts/devnet_deploy.py` deploys on the node, then the play runs from the second predeployed account:
    `--dry-run` sends nothing; the run exits 0 (a run that goblins stop, its record `"completed": false`,
    is followed by one from the next account, another draw, up to three) and the record says the member entered at least two chunks
    besides the entry one, ended in the town (read back from `Hub.adventurer` and `Instances.placement`),
    and holds every transaction the account sent (its nonce moved by their count; each hash's receipt is
    the account's and its fee the record's); the Markdown summary is beside it;
  * no value of any `STARKNET_*` variable, in any form, appears in stdout, stderr, the log, the record or
    the summary: the runs carry the node's real URL, address and key (and a sentinel network), the refusals
    the sentinels of `sepolia_deploy_smoke.py`.
"""
import json
import os
import subprocess
import sys
import tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, os.path.join(ROOT, "scripts"))
sys.path.insert(0, os.path.join(ROOT, "scripts", "tests"))
import devnet_deploy  # noqa: E402
import sepolia_deploy_smoke as deploy_smoke  # noqa: E402  the sentinels and the forms a leak takes
import sepolia_play as play  # noqa: E402

SCRIPT = os.path.join(ROOT, "scripts", "sepolia_play.py")
FAKE = deploy_smoke.FAKE
# A draw that stops (goblins block a corridor through 8 batches of Waits) was 1 in 9 in GATE-1a's devnet
# measures (VPS, 2026-10-17): all three stopping is about 1 in 700 if the draws are independent.
TRIES = 3


class Run:
    """One run of the script: its exit code, stdout, stderr, log file and the sentinel check."""

    def __init__(self, env_values, *args):
        self.logs = tempfile.mkdtemp(prefix="smoke-play-logs-")
        env = {k: v for k, v in os.environ.items()
               if not (k.startswith("STARKNET_") or k.startswith("NODE_") or k in ("RPC_URL", "WITH_NODE_LOG_DIR"))}
        env.update(env_values)
        env["WITH_NODE_LOG_DIR"] = self.logs
        out = subprocess.run([sys.executable, "-I", SCRIPT, *args], cwd=ROOT, env=env, capture_output=True, text=True)
        self.code, self.stdout, self.stderr = out.returncode, out.stdout, out.stderr
        log = os.path.join(self.logs, "sepolia-play.log")
        self.log = open(log).read() if os.path.exists(log) else ""
        self.values = env_values
        assert os.listdir(self.logs) in ([], ["sepolia-play.log"]), os.listdir(self.logs)
        self.no_leak(self.stdout, self.stderr, self.log)

    def no_leak(self, *texts):
        for name, value in self.values.items():
            if name == "STARKNET_NETWORK":  # a public name
                continue
            for form in deploy_smoke.forms(name, value):
                for text in texts:
                    assert form not in text, f"{name} leaked as {form!r} in:\n{text[:800]}"

    def refused(self, message):
        assert self.code != 0, (self.stdout, self.stderr)
        assert message in self.stderr, f"{message!r} not in stderr:\n{self.stderr}"


def check_board():
    # the probe's encoding (`lifecycle_probe.py`'s `batch`), for the ten directions it can take
    moves = [0, 1, 2, 3, 4, 5, 0, 3, 5, 2]
    word = len(moves)
    for i, d in enumerate(moves):
        word += (d * 8) << (4 + 24 * i if i < 5 else 128 + 24 * (i - 5))
    assert play.batch(moves) == word
    assert play.batch([play.WAIT, 3]) == 2 + (2 << 4) + ((3 * 8) << 28)  # a Wait is kind 2
    for bad in ([], [6], [0] * 11, ["run"]):
        try:
            play.batch(bad)
        except ValueError:
            continue
        raise AssertionError(f"batch({bad}) was accepted")
    for tile in ((0, 7), (5, 8), (16, 3), (20, 20)):
        for d in range(6):
            n = play.step(*tile, d)
            assert play.distance(tile, n) == 1, (tile, d, n)
            assert play.step(*n, (d + 3) % 6) == tile, (tile, d)  # the opposite direction comes back
    assert play.chunk_of((0, 7)) == 0 and play.chunk_of((15, 0)) == 1 and play.chunk_of((3, 16)) == 15
    assert play.tile_of(0, 105) == (0, 7) and play.tile_of(16, 0) == (15, 15)
    folder = tempfile.mkdtemp(prefix="smoke-play-records-")
    for name, run in (("2026-10-15-aaaaaaa", 9), ("2026-10-16-bbbbbbb", 3), ("2026-10-16-ccccccc", 5),
                      ("2026-10-14-ddddddd", 99)):
        with open(os.path.join(folder, f"{name}.json"), "w") as handle:
            json.dump({"artefact": {"run": f"https://github.com/x/y/actions/runs/{run}"}}, handle)
    assert os.path.basename(play.newest_record(folder)) == "2026-10-16-ccccccc.json"
    assert os.path.basename(play.newest_record()).startswith("2026-"), "no record in deployments/sepolia"


class Quiet:
    def say(self, text, error=False):
        pass


def check_bookkeeping():
    """`Play.invoke` keeps a transaction that reverted (`sncast` gave its hash, then the call failed) and one
    whose call failed without a hash while the nonce moved (found by nonce); `fees` marks a reverted one and
    counts its fee; `where` and the summary say where the adventurer is."""
    class Node:
        address = "0x1"

        def __init__(self, mode):
            self.mode, self.nonce, self.sent = mode, 5, []

        def account_nonce(self):
            return self.nonce

        def invoke(self, *_):
            self.nonce += 1
            if self.mode == "reverted":
                self.sent = self.sent + ["0xaa"]
                raise RuntimeError("enter reverted: out of gas")
            raise RuntimeError("sncast failed after the node took it")

        def find_transaction(self, nonce):
            assert nonce == 5, nonce
            if self.mode == "lost":
                raise RuntimeError("no transaction of the account with that nonce")
            return {"transaction_hash": "0xbb"}

        def rpc(self, method, params):
            if method == "starknet_getTransactionByHash":
                return {"sender_address": "0x1"}
            reverted = params["transaction_hash"] == "0xaa"
            return {"actual_fee": {"amount": hex(7 if reverted else 3), "unit": "FRI"},
                    "execution_status": "REVERTED" if reverted else "SUCCEEDED", "revert_reason": "out of gas"}

    contracts = {"hub": "0x2", "instances": "0x3", "registry": "0x4"}
    for mode, step in (("reverted", ("enter (gate 1)", "0xaa")), ("unreported", ("enter (gate 1)", "0xbb")),
                       ("lost", ("enter (gate 1)", None, "nonce moved, hash unknown"))):
        game = play.Play(Node(mode), Quiet(), contracts, 2)
        try:
            game.invoke("enter (gate 1)", "0x2", "enter", 1, 1)
        except RuntimeError:
            pass
        else:
            raise AssertionError("the failed call did not raise")
        assert game.steps == [step], (mode, game.steps)
    steps = [("a", "0xaa"), ("b", "0xbb"), ("c", None, "nonce moved, hash unknown")]
    transactions, total = play.fees(Node("reverted"), steps, str)
    assert transactions[0]["reverted"] is True and transactions[0]["fee"] == "7" and "reverted" not in transactions[1]
    assert all(t["sender"] == "account" for t in transactions[:2]), transactions
    assert transactions[2] == {"what": "c", "hash": None, "sender": None, "fee": None, "unit": None,
                               "error": "nonce moved, hash unknown"}, transactions[2]
    assert total == {"amount": "10", "unit": "FRI", "missing": 1}, total
    assert play.total_of({"FRI": 3, "WEI": 4}, 0) == {"amounts": {"FRI": "3", "WEI": "4"}}
    # the record phase: a leak in a message leaves a minimal record of the hashes; an interrupt while the
    # fees are read leaves every fee null; either way the record is written
    folder = tempfile.mkdtemp(prefix="smoke-play-phase-")

    def build(transactions, total):
        return {"gate": "GATE-1 (D-308)", "network": "devnet", "script_commit": "0" * 40, "completed": False,
                "deployment": {"name": "d", "commit": "0" * 40}, "adventurer_id": 1, "instance_id": 2,
                "gates": {"in": {"id": 1, "source": 1, "destination": 2}}, "chunks_crossed": [],
                "final_location": {"kind": "instance", "instance": 2}, "hits": [], "stopped": "SECRETVALUE echoed",
                "transactions": transactions, "total_fee": total, "started": "s", "finished": "f", "seconds": 0}
    leak = lambda text: str(text).replace("SECRETVALUE", "<STARKNET_RPC_URL>")
    assert play.record_phase(Node("reverted"), steps[:2], leak, build, os.path.join(folder, "a.json"), Quiet()) is None
    minimal = json.load(open(os.path.join(folder, "a.json")))
    assert minimal == {"gate": "GATE-1 (D-308)", "completed": False, "minimal": True,
                       "transactions": [{"hash": "0xaa"}, {"hash": "0xbb"}]}, minimal
    assert "SECRETVALUE" not in open(os.path.join(folder, "a.md")).read()

    class Interrupted(Node):
        def rpc(self, method, params):
            raise KeyboardInterrupt

    interrupt = play.record_phase(Interrupted("x"), steps[:2], str, build, os.path.join(folder, "b.json"), Quiet())
    assert isinstance(interrupt, KeyboardInterrupt), interrupt
    written = json.load(open(os.path.join(folder, "b.json")))
    assert [t["hash"] for t in written["transactions"]] == ["0xaa", "0xbb"], written
    assert all(t["fee"] is None and t["error"] == "fee not read: KeyboardInterrupt" for t in written["transactions"])
    assert play.place_text({"kind": "instance", "instance": 9}) == "left inside instance 9"
    assert play.place_text({"kind": "unknown", "why": "OSError: x"}) == "unknown: OSError: x"
    assert play.where(play.Play(Node("x"), Quiet(), contracts, 2), str)["kind"] == "unknown"


def injected(values, deployment, logs, name, patch):
    """A run in this process with `patch` applied to `Play` (a fault after `enter`), then undone. Returns the
    exit code, the record and its summary, checked for leaks."""
    saved = {k: getattr(play.Play, k) for k in patch}
    for k, v in patch.items():
        setattr(play.Play, k, v)
    record_path = os.path.join(logs, f"{name}.json")
    environ = {**{k: v for k, v in os.environ.items() if not k.startswith(("STARKNET_", "NODE_"))}, **values,
               "WITH_NODE_LOG_DIR": tempfile.mkdtemp(prefix="smoke-play-logs-")}
    try:
        code = play.main(["--devnet", "--deployment", deployment, "--out", record_path], environ)
    except KeyboardInterrupt:
        code = "interrupted"
    finally:
        for k, v in saved.items():
            setattr(play.Play, k, v)
    text, markdown = open(record_path).read(), open(record_path[:-5] + ".md").read()
    log = open(os.path.join(environ["WITH_NODE_LOG_DIR"], "sepolia-play.log")).read()
    Run.no_leak(type("R", (), {"values": values})(), text, markdown, log)
    return code, json.loads(text), markdown


def check_faults(values_a, values_b, values_c, deployment, logs, probe, dep):
    """Review t-0273, finding 1: an error that is not the script's own, after `enter`, still writes the
    record with every transaction sent and where the adventurer is."""
    def cross(self):
        raise ValueError("injected after enter")
    code, record, markdown = injected(values_a, deployment, logs, "fault-value", {"cross": cross})
    address = values_a["STARKNET_ACCOUNT_ADDRESS"]
    assert code == 1 and record["completed"] is False, record
    assert record["stopped"] == "ValueError: injected after enter", record["stopped"]
    assert len(record["transactions"]) == nonce(probe, address) == 4, record["transactions"]
    assert record["transactions"][-1]["what"] == "enter (gate 1)"
    instance = probe.view("ephemeral", dep["contracts"]["instances"], "placement", record["adventurer_id"])
    assert instance[2] == 1 and record["final_location"] == {"kind": "instance", "instance": instance[0]}, record
    assert f"left inside instance {instance[0]}" in markdown, markdown

    enter = play.Play.enter

    def broken(self, gate):
        enter(self, gate)

        def view(*_, **__):
            raise OSError("injected: the node went away")
        self.node.view = view
    code, record, markdown = injected(values_b, deployment, logs, "fault-os", {"enter": broken})
    assert code == 1 and record["stopped"] == "OSError: injected: the node went away", record
    assert len(record["transactions"]) == nonce(probe, values_b["STARKNET_ACCOUNT_ADDRESS"]) == 4
    assert all(t["fee"] for t in record["transactions"]) and int(record["total_fee"]["amount"]) > 0
    assert record["final_location"]["kind"] == "unknown" and "OSError" in record["final_location"]["why"]
    assert "unknown: OSError" in markdown, markdown

    def interrupt(self):  # review t-0274: an interrupt after enter writes the record, then goes on
        raise KeyboardInterrupt
    code, record, markdown = injected(values_c, deployment, logs, "fault-interrupt", {"cross": interrupt})
    assert code == "interrupted", f"the interrupt did not propagate: {code}"
    assert record["completed"] is False and record["stopped"].startswith("KeyboardInterrupt"), record
    assert len(record["transactions"]) == nonce(probe, values_c["STARKNET_ACCOUNT_ADDRESS"]) == 4
    assert record["final_location"]["kind"] == "instance", record["final_location"]


def check_views(values, dep, logs):
    """Review t-0274: the views read at the node's tag, `pre_confirmed` on Sepolia. The devnet answers a
    `starknet_call` at `pre_confirmed` as at `latest`, and both as `sncast call` does."""
    url, address = values["STARKNET_RPC_URL"], values["STARKNET_ACCOUNT_ADDRESS"]
    answers = []
    for tag in ("latest", "pre_confirmed"):
        node = play.PlayNode(url, address, "unused", tempfile.mkdtemp(prefix="smoke-play-view-"), {}, str, tag=tag)
        answers.append((node.view("persistent", dep["contracts"]["registry"], "content_version"),
                        node.view("persistent", dep["contracts"]["hub"], "account_of", int(dep["account"], 16)),
                        node.view("ephemeral", dep["contracts"]["instances"], "placement", 1)))
    sncast = devnet_deploy.Node(url, address, "unused", logs, name="views")
    assert answers[0] == answers[1] == (
        sncast.view("persistent", dep["contracts"]["registry"], "content_version"),
        sncast.view("persistent", dep["contracts"]["hub"], "account_of", int(dep["account"], 16)),
        sncast.view("ephemeral", dep["contracts"]["instances"], "placement", 1)), answers


def check_refusals(real, deployment, logs):
    local = {**FAKE, "STARKNET_RPC_URL": "http://127.0.0.1:9/sentinelapikey7788"}
    Run(local, "--dry-run").refused("a local node runs only with --devnet")
    Run(FAKE, "--devnet", "--deployment", deployment, "--out", os.path.join(logs, "x.json")).refused(
        "--devnet runs against a local node only")
    Run(real, "--devnet", "--deployment", deployment).refused("--devnet needs --deployment")
    Run(real, "--devnet", "--deployment", deployment, "--out", os.path.join(ROOT, "docs", "reports", "x.json")
        ).refused("never written there")
    sepolia = play.newest_record()
    Run(real, "--devnet", "--deployment", sepolia, "--out", os.path.join(logs, "y.json")).refused(
        "--devnet plays a devnet deployment")
    missing = {k: v for k, v in real.items() if k != "STARKNET_PRIVATE_KEY"}
    Run(missing, "--devnet", "--deployment", deployment, "--out", os.path.join(logs, "z.json")).refused(
        "STARKNET_PRIVATE_KEY: not set")


def nonce(node, address):
    return int(node.rpc("starknet_getNonce", {"block_id": "latest", "contract_address": address}), 16)


def main():
    check_board()
    check_bookkeeping()
    print("sepolia_play_smoke: board ok")
    url = os.environ["NODE_URL"]
    logs = tempfile.mkdtemp(prefix="smoke-play-")
    deployment = os.path.join(logs, "deployment.json")
    deployed = subprocess.run([sys.executable, os.path.join(ROOT, "scripts", "devnet_deploy.py"), "--out", deployment],
                              cwd=ROOT, capture_output=True, text=True)
    assert deployed.returncode == 0, deployed.stderr[-3000:]
    dep = json.load(open(deployment))
    probe = devnet_deploy.Node(url, dep["account"], "unused", logs, name="smoke")
    predeployed = probe.rpc("devnet_getPredeployedAccounts", {})
    accounts = predeployed[1:1 + TRIES]  # the deployer is the first; the faults take the two after these
    real = [{"STARKNET_NETWORK": FAKE["STARKNET_NETWORK"], "STARKNET_RPC_URL": url,
             "STARKNET_ACCOUNT_ADDRESS": a["address"], "STARKNET_PRIVATE_KEY": a["private_key"]}
            for a in predeployed[1:4 + TRIES]]
    print(f"sepolia_play_smoke: deployed (commit {dep['commit'][:7]})")

    check_refusals(real[0], deployment, logs)
    assert nonce(probe, accounts[0]["address"]) == 0, "a refusal sent a transaction"
    print("sepolia_play_smoke: refusals ok, nothing sent, no value leaked")

    record_path = os.path.join(logs, "play.json")
    dry = Run(real[0], "--devnet", "--deployment", deployment, "--out", record_path, "--dry-run")
    assert dry.code == 0 and "--dry-run: nothing sent" in dry.stdout and "plan:" in dry.stdout, dry.stderr
    assert nonce(probe, accounts[0]["address"]) == 0 and not os.path.exists(record_path), "--dry-run sent or wrote"

    check_views(real[0], dep, logs)
    check_faults(real[TRIES], real[TRIES + 1], real[TRIES + 2], deployment, logs, probe, dep)
    print("sepolia_play_smoke: faults after enter recorded, with every transaction and the place")

    # The world is drawn at the entry: a draw whose goblins stop the run (no route, health below half) is
    # recorded as stopped, and another adventurer (another draw) plays; one of TRIES must reach the hub.
    for attempt, values in enumerate(real[:TRIES], 1):
        record_path = os.path.join(logs, f"play-{attempt}.json")
        run = Run(values, "--devnet", "--deployment", deployment, "--out", record_path)
        print(run.stdout)
        if run.code == 0:
            break
        stopped = json.load(open(record_path))
        assert stopped["completed"] is False and stopped["stopped"] in run.stderr, (stopped, run.stderr)
        run.no_leak(open(record_path).read(), open(record_path[:-5] + ".md").read())
        print(f"sepolia_play_smoke: run {attempt} stopped ({stopped['stopped']}); another adventurer plays")
    assert run.code == 0, run.stderr
    address = values["STARKNET_ACCOUNT_ADDRESS"]
    text, markdown = open(record_path).read(), open(record_path[:-5] + ".md").read()
    run.no_leak(text, markdown)
    assert "127.0.0.1" not in text and "127.0.0.1" not in markdown, "the node's URL is in the record"
    record = json.loads(text)
    assert record["completed"] is True and record["devnet"] is True and record["chain_id"] == "SN_SEPOLIA", record
    assert record["deployment"] == {"name": "deployment", "commit": dep["commit"],
                                    "contracts": {k: dep["contracts"][k] for k in ("registry", "hub", "instances")}}
    # crossed: at least two chunks besides the entry one, each entry recorded in order
    entry = play.chunk_of(play.tile_of(*record["gates"]["in"]["arrival"]))
    chunks = [c["chunk"] for c in record["chunks_crossed"]]
    assert len(set(chunks) - {entry}) >= 2, chunks
    assert chunks[-1] == entry, f"the member did not come back to the entry chunk: {chunks}"
    # ended in the town: the record, and the chain
    town = record["gates"]["out"]["destination"]
    assert record["final_location"] == {"kind": "hub", "location": town} and town == record["gates"]["in"]["source"]
    adventurer = record["adventurer_id"]
    place = probe.view("persistent", dep["contracts"]["hub"], "adventurer", adventurer)[2]
    assert (place >> 64) & 0xFFFF == town and (place >> 96) & 0xFF == 0, hex(place)
    assert probe.view("ephemeral", dep["contracts"]["instances"], "placement", adventurer)[2] == 0
    # every transaction: the account's nonce moved by their count, each receipt is the account's
    txs = record["transactions"]
    assert len(txs) == nonce(probe, address), (len(txs), nonce(probe, address))
    whats = [t["what"] for t in txs]
    assert whats[:4] == ["register", "create_adventurer", "set_build", "enter (gate 1)"], whats
    assert whats[-1] == "leave (gate 2)" and all(w.startswith("play") for w in whats[4:-1]), whats
    total = 0
    for t in txs:
        tx = probe.rpc("starknet_getTransactionByHash", {"transaction_hash": t["hash"]})
        receipt = probe.rpc("starknet_getTransactionReceipt", {"transaction_hash": t["hash"]})
        assert int(tx["sender_address"], 16) == int(address, 16) and receipt["execution_status"] == "SUCCEEDED"
        assert int(receipt["actual_fee"]["amount"], 16) == int(t["fee"]), t
        assert t["sender"] == "account", t  # checked against the chain just above
        total += int(t["fee"])
    assert record["total_fee"] == {"amount": str(total), "unit": txs[0]["unit"]} and total > 0, record["total_fee"]
    assert record["seconds"] >= 0 and record["started"] <= record["finished"]
    for hit in record["hits"]:  # a goblin's hit is recorded and not answered: no attack in any batch
        assert hit["health"][1] < hit["health"][0] and len(hit["tile"]) == 2, hit
    assert f"Adventurer: {adventurer}" in markdown and "Final location" in markdown, markdown
    # a second run would overwrite the record: refused, nothing sent
    before = nonce(probe, address)
    Run(values, "--devnet", "--deployment", deployment, "--out", record_path).refused("never overwritten")
    assert nonce(probe, address) == before
    print(f"sepolia_play_smoke: played: adventurer {adventurer}, chunks {chunks}, {len(txs)} transactions, "
          f"fee {total} {txs[0]['unit']}")
    print(markdown)


if __name__ == "__main__":
    main()
