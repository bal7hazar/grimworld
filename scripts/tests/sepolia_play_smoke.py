#!/usr/bin/env python3
"""GATE-1a's smoke test: `scripts/sepolia_play.py --devnet` against the node `with-node.sh` started, end to end
(nothing here goes near Sepolia). From the repository root, after the classes are built
(`scripts/lock.sh --heavy scarb --manifest-path contracts/Scarb.toml build`):

    scripts/with-node.sh python3 -I scripts/tests/sepolia_play_smoke.py

  * the board: the batch word against `lifecycle_probe.py`'s encoding, the hex steps and distances, the
    newest deployment record (by date, then by `artefact.run`);
  * the refusals, each with its message and nothing sent: a local URL without `--devnet`, a remote URL with
    it, `--devnet` without `--out`, an `--out` under docs/reports, a Sepolia record with `--devnet`;
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
    print("sepolia_play_smoke: board ok")
    url = os.environ["NODE_URL"]
    logs = tempfile.mkdtemp(prefix="smoke-play-")
    deployment = os.path.join(logs, "deployment.json")
    deployed = subprocess.run([sys.executable, os.path.join(ROOT, "scripts", "devnet_deploy.py"), "--out", deployment],
                              cwd=ROOT, capture_output=True, text=True)
    assert deployed.returncode == 0, deployed.stderr[-3000:]
    dep = json.load(open(deployment))
    probe = devnet_deploy.Node(url, dep["account"], "unused", logs, name="smoke")
    accounts = probe.rpc("devnet_getPredeployedAccounts", {})[1:1 + TRIES]  # the deployer is the first
    real = [{"STARKNET_NETWORK": FAKE["STARKNET_NETWORK"], "STARKNET_RPC_URL": url,
             "STARKNET_ACCOUNT_ADDRESS": a["address"], "STARKNET_PRIVATE_KEY": a["private_key"]} for a in accounts]
    print(f"sepolia_play_smoke: deployed (commit {dep['commit'][:7]})")

    check_refusals(real[0], deployment, logs)
    assert nonce(probe, accounts[0]["address"]) == 0, "a refusal sent a transaction"
    print("sepolia_play_smoke: refusals ok, nothing sent, no value leaked")

    record_path = os.path.join(logs, "play.json")
    dry = Run(real[0], "--devnet", "--deployment", deployment, "--out", record_path, "--dry-run")
    assert dry.code == 0 and "--dry-run: nothing sent" in dry.stdout and "plan:" in dry.stdout, dry.stderr
    assert nonce(probe, accounts[0]["address"]) == 0 and not os.path.exists(record_path), "--dry-run sent or wrote"

    # The world is drawn at the entry: a draw whose goblins stop the run (no route, health below half) is
    # recorded as stopped, and another adventurer (another draw) plays; one of TRIES must reach the hub.
    for attempt, values in enumerate(real, 1):
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
