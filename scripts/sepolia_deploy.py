#!/usr/bin/env python3
"""OPS-02a: deploys the game on Sepolia from the class files of a CI artefact, and writes the record.
From the repository root, with the account in the environment (OPERATIONS §7, used by name):

    python3 scripts/sepolia_deploy.py --commit <sha on main>        # or --artifact-run <run id>
    python3 scripts/sepolia_deploy.py --commit <sha> --dry-run      # everything but the transactions

The variables `STARKNET_NETWORK`, `STARKNET_RPC_URL`, `STARKNET_ACCOUNT_ADDRESS`, `STARKNET_PRIVATE_KEY`
are read by name. **No value of any of them is printed, logged or written**, nor any part of one: every
message names the variable only, and what `sncast` or the RPC echo back (an error carries the URL or the
address) goes through `Redactor` before it is printed or logged. The record holds no RPC URL and no
account. The key goes to `sncast` through a 0600 file (`O_EXCL`, deleted in a `finally`) and the accounts
file it writes lives in a private temporary folder that is removed in a `finally`: never a command line.

What it does, in order, and nothing is sent before step 3:
  1. refuses `--give-build`, `--credit-only` and the other options of the devnet script (D-280's gold
     harness is a devnet tool, never used here);
  2. reads the four variables; the URL must not be a local one (`--devnet-rehearsal` is the one way to
     run against a local node, and it accepts only `http://127.0.0.1:<port>` and a devnet that answers
     `devnet_getPredeployedAccounts`, because a devnet reports Sepolia's chain id);
  3. asks the RPC for `starknet_chainId` and stops unless it is `SN_SEPOLIA` (OPERATIONS §7);
  4. finds the CI run (`--artifact-run`, or the newest successful push run of `--commit`), refuses a run
     whose event is not `push` or whose branch is not `main`, downloads `contract-classes-<sha>` with
     `gh run download` and checks its `build-root.json` (the commit is the run's) and the class files;
  5. prints the plan; `--dry-run` stops here;
  6. declares (`sncast declare-from --sierra-file`: the artefact's file, never a local build), deploys
     and registers in OPERATIONS §7's order (`devnet_deploy.deploy_core`, shared with the devnet script:
     `set_zone_checks` first, the play classes with `set_play_class`, GoblinsLibrary as key 6 last), then
     writes the seed's records (`write_seed`). No adventurer is created, nothing is credited.
  7. counts the transactions and their fees (from the receipts), prints the totals and writes
     `deployments/sepolia/<YYYY-MM-DD>-<short sha>.json` (a rehearsal needs `--out`).

The log is `$WITH_NODE_LOG_DIR/sepolia-deploy.log` (default `./.with-node/`, gitignored): the printed
lines, redacted, with the class hashes and addresses as they are declared (so a stopped run says what
exists on chain).
"""
import argparse
import datetime
import glob
import ipaddress
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import urllib.parse

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import devnet_deploy as dd  # noqa: E402  the deployment order, the seed and the node, shared

NAME = "ops02a"  # no "sepolia" in a message: a STARKNET_NETWORK of that value would be redacted in it
CHAIN = "SN_SEPOLIA"
VARIABLES = ("STARKNET_NETWORK", "STARKNET_RPC_URL", "STARKNET_ACCOUNT_ADDRESS", "STARKNET_PRIVATE_KEY")
REFUSED = ("--give-build", "--credit-only", "--build", "--deployment", "--account", "--key-env",
           "--adventurer", "--salt")
RECORDS = os.path.join(ROOT, "deployments", "sepolia")
KINDS = {dd.REGION: "region", dd.LOCATION: "location", dd.GATE: "gate", dd.ITEM: "item",
         9: "skill", 8: "caste", 7: "pack", 6: "spawn_table"}


class Redactor:
    """Hides the value of each STARKNET_* variable (and the forms an echo may take) in a text. The URL
    is hidden whole and by its parts (host, path, query: an API key sits in one), the address by its
    number whatever the padding, the key by its number too."""

    def __init__(self, environ):
        self.exact, self.numbers = [], []
        for name in VARIABLES:
            value = environ.get(name, "")
            if not value:
                continue
            self.exact.append((value, name))
            if name == "STARKNET_RPC_URL":
                parts = urllib.parse.urlparse(value)
                pieces = [parts.netloc, parts.hostname or "", parts.path.strip("/"), parts.query,
                          parts.username or "", parts.password or ""]
                pieces += [p for p in re.split(r"[/?&=]", parts.path + "?" + parts.query) if len(p) >= 8]
                self.exact += [(p, name) for p in pieces if len(p) >= 4]
            if name in ("STARKNET_ACCOUNT_ADDRESS", "STARKNET_PRIVATE_KEY"):
                try:
                    self.numbers.append((int(value, 0), name))
                except ValueError:
                    pass
        self.exact.sort(key=lambda pair: -len(pair[0]))  # the longest first: the URL before its host

    def __call__(self, text):
        text = str(text)
        for value, name in self.exact:
            text = text.replace(value, f"<{name}>")
        for number, name in self.numbers:  # 0x0abc, 0xabc, 0x000...abc: one number
            text = re.sub(r"0[xX]0*([0-9a-fA-F]+)",
                          lambda m, n=number, v=name: f"<{v}>" if int(m.group(1), 16) == n else m.group(0),
                          text)
        return text


class Log:
    """Every line printed goes through the redactor and into the log file."""

    def __init__(self, redact, path):
        self.redact = redact
        os.makedirs(os.path.dirname(path), exist_ok=True)
        descriptor = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_APPEND, 0o600)
        self.file = os.fdopen(descriptor, "a")

    def say(self, text, error=False):
        text = self.redact(text)
        print(f"{NAME}: {text}", file=sys.stderr if error else sys.stdout, flush=True)
        self.file.write(f"{NAME}: {text}\n")
        self.file.flush()

    def die(self, text):
        self.say(text, error=True)
        raise SystemExit(1)


class SepoliaNode(dd.Node):
    """The devnet script's `Node` on a remote URL, declaring from the artefact's files."""

    check_url = staticmethod(lambda url: None)  # this script checks the URL itself (`check_endpoint`)

    def __init__(self, url, address, key, logs, files, redact):
        super().__init__(url, address, key, logs)
        self.files = files
        self.redact = redact

    def declare(self, package, name):
        out = self.sncast(package, "--account", self.name, "--wait", "declare-from", "--url", self.url,
                          "--sierra-file", self.files[(package, name)])
        return dd.field("Class Hash", out)


def is_local(url):
    host = urllib.parse.urlparse(url).hostname or ""
    if host == "localhost" or host.endswith(".localhost"):
        return True
    try:
        address = ipaddress.ip_address(host)
    except ValueError:
        return False
    return address.is_loopback or address.is_unspecified or address.is_private or address.is_link_local


def check_endpoint(url, rehearsal, log):
    """The URL, before any call: remote and https for Sepolia, `http://127.0.0.1:<port>` for the rehearsal."""
    if rehearsal:
        if urllib.parse.urlparse(url).hostname not in ("127.0.0.1",) or not is_local(url):
            log.die("--devnet-rehearsal runs against a local node only: STARKNET_RPC_URL is not local")
        try:
            dd.check_url(url)
        except SystemExit as error:
            log.die(f"--devnet-rehearsal: {error}")
    else:
        if is_local(url):
            log.die("STARKNET_RPC_URL is a local URL: a local node runs only with --devnet-rehearsal")
        if urllib.parse.urlparse(url).scheme != "https":
            log.die("STARKNET_RPC_URL is not an https URL")


def check_chain(node, rehearsal, log):
    """OPERATIONS §7: the chain id first, and nothing is sent unless it is SN_SEPOLIA. The rehearsal must
    also be a devnet (it answers `devnet_getPredeployedAccounts`); a Sepolia run must not be one."""
    try:
        chain = dd.chain_of(node)
    except Exception as error:
        log.die(f"STARKNET_RPC_URL: no chain id ({node.redact(error)})")
    if chain != CHAIN:
        log.die(f"STARKNET_RPC_URL: chain id {chain!r}, not {CHAIN!r}: nothing sent")
    try:
        node.rpc("devnet_getPredeployedAccounts", {})
        devnet = True
    except Exception as error:
        devnet = False
        reason = node.redact(error)
    if rehearsal and not devnet:
        log.die(f"--devnet-rehearsal: STARKNET_RPC_URL is not a starknet-devnet ({reason})")
    if devnet and not rehearsal:
        log.die("STARKNET_RPC_URL answers devnet_getPredeployedAccounts: a devnet runs only with "
                "--devnet-rehearsal")
    log.say(f"STARKNET_RPC_URL: chain id {chain}")
    return chain


def gh(*args):
    out = subprocess.run(["gh", *args], cwd=ROOT, capture_output=True, text=True)
    if out.returncode != 0:
        raise RuntimeError(f"gh {' '.join(args[:3])}: {out.stderr.strip()[-500:]}")
    return out.stdout


def find_run(args, log):
    """The CI run the classes come from: `--artifact-run`, or the newest successful push run of
    `--commit` on main. Refused unless its event is `push` and its branch `main`."""
    run = args.artifact_run
    if run is None:
        if not re.fullmatch(r"[0-9a-f]{40}", args.commit):
            log.die("--commit is the full 40-hex sha of a commit on main")
        runs = json.loads(gh("run", "list", "--workflow", "ci.yml", "--branch", "main", "--event", "push",
                             "--commit", args.commit, "--status", "success", "--limit", "5",
                             "--json", "databaseId"))
        if not runs:
            log.die(f"no successful push run of ci.yml on main for commit {args.commit}")
        run = runs[0]["databaseId"]
    info = json.loads(gh("run", "view", str(run), "--json", "event,headBranch,headSha,url,workflowName,"
                                                           "conclusion"))
    if info["event"] != "push" or info["headBranch"] != "main":
        log.die(f"run {run}: event {info['event']!r} on branch {info['headBranch']!r}, not a push to "
                "main (OPERATIONS §7: the artefact of a push to main, never a pull request's)")
    if info["workflowName"] != "ci":
        log.die(f"run {run}: workflow {info['workflowName']!r}, not 'ci'")
    if args.commit and info["headSha"] != args.commit:
        log.die(f"run {run} is commit {info['headSha']}, not {args.commit}")
    return run, info


def download(run, info, folder, log):
    """`gh run download` of `contract-classes-<sha>`; returns the class files and `build-root.json`."""
    name = f"contract-classes-{info['headSha']}"
    try:
        gh("run", "download", str(run), "-n", name, "-D", folder)
    except RuntimeError as error:
        log.die(f"run {run}: no artefact {name} ({error})")
    with open(os.path.join(folder, "build-root.json")) as handle:
        root = json.load(handle)
    if root.get("commit") != info["headSha"] or not root.get("root") or not root.get("scarb"):
        log.die(f"{name}: build-root.json does not hold the run's commit, a root and a Scarb version")
    files = {}
    for package, klass in needed_classes():
        found = glob.glob(os.path.join(folder, "**", f"grimworld_{package}_{klass}.contract_class.json"),
                          recursive=True)
        if len(found) != 1:
            log.die(f"{name}: {len(found)} files for grimworld_{package}_{klass}, expected one")
        files[(package, klass)] = found[0]
    return name, root, files


def needed_classes():
    """The (package, class) pairs `deploy_core` declares: read from a stub run of it, never listed twice."""
    class Names:
        def __init__(self):
            self.pairs = []

        def declare(self, package, name):
            self.pairs.append((package, name))
            return "0x1"

        def deploy(self, *_):
            return "0x2"

        def invoke(self, *_):
            return {}

    names = Names()
    dd.deploy_core(names, "0x3")
    return names.pairs


def seed_ids():
    ids = {}
    for kind, rid, _ in dd.seed_records():
        ids.setdefault(KINDS.get(kind, str(kind)), []).append(rid)
    return ids


def parse(argv):
    parser = argparse.ArgumentParser(
        prog="python3 scripts/sepolia_deploy.py",
        description="Deploys the game on Sepolia from a CI artefact of a push to main (OPERATIONS §7). "
                    "The account is read from STARKNET_NETWORK, STARKNET_RPC_URL, STARKNET_ACCOUNT_ADDRESS "
                    "and STARKNET_PRIVATE_KEY, by name; no value is ever printed.",
        epilog="Refused outright: " + ", ".join(REFUSED) + " (the devnet script's options; the gold harness "
               "of D-280 is for a local devnet only).")
    source = parser.add_mutually_exclusive_group(required=True)
    source.add_argument("--artifact-run", type=int, help="the id of the CI run (a push to main)")
    source.add_argument("--commit", help="the full sha of a commit on main: its newest successful push run")
    parser.add_argument("--dry-run", action="store_true",
                        help="download, check and print the plan; send nothing")
    parser.add_argument("--devnet-rehearsal", action="store_true",
                        help="run against a local starknet-devnet (http://127.0.0.1:<port>) instead of "
                             "Sepolia; the only way the script runs on a local node; needs --out")
    parser.add_argument("--out", help="the record's path (default deployments/sepolia/<date>-<sha>.json; "
                                      "required with --devnet-rehearsal)")
    parser.add_argument("--account-type", choices=("oz", "argent", "braavos"), default="oz",
                        help="the account's class, as sncast names it (default oz)")
    for option in REFUSED:
        parser.add_argument(option, nargs="?", const=True, help=argparse.SUPPRESS)
    return parser.parse_args(argv)


def write_record(path, record):
    text = json.dumps(record, indent=2) + "\n"
    os.makedirs(os.path.dirname(os.path.abspath(path)), exist_ok=True)
    with open(path, "x") as out:  # never over an earlier record
        out.write(text)


def totals(node):
    """The number of transactions `sncast` sent and the sum of their fees, from the receipts."""
    fee, units = 0, set()
    for tx in node.sent:
        paid = node.rpc("starknet_getTransactionReceipt", {"transaction_hash": tx})["actual_fee"]
        fee += int(paid["amount"], 16)
        units.add(paid["unit"])
    if len(units) > 1:
        raise RuntimeError(f"fees in several units: {sorted(units)}")
    return len(node.sent), fee, (units.pop() if units else "FRI")


def run(args, log, redact, environ):
    refused = [o for o in REFUSED if getattr(args, o[2:].replace("-", "_")) not in (None, False)]
    if refused:
        log.die(f"{', '.join(refused)}: refused (the devnet script's option; D-280's gold harness is "
                "never used on Sepolia)")
    if args.devnet_rehearsal and not args.out:
        log.die("--devnet-rehearsal needs --out: a rehearsal's record must not land in deployments/sepolia")
    missing = [name for name in VARIABLES if not environ.get(name)]
    if missing:
        log.die(f"{', '.join(missing)}: not set")
    url, address = environ["STARKNET_RPC_URL"], environ["STARKNET_ACCOUNT_ADDRESS"]
    try:
        int(address, 16)
    except ValueError:
        log.die("STARKNET_ACCOUNT_ADDRESS: not a hex address")
    check_endpoint(url, args.devnet_rehearsal, log)

    logs = tempfile.mkdtemp(prefix="sepolia-deploy-")  # 0700: the accounts file holds the key
    try:
        node = SepoliaNode(url, address, "unused", logs, {}, redact)
        chain = check_chain(node, args.devnet_rehearsal, log)
        run_id, info = find_run(args, log)
        name, root, files = download(run_id, info, os.path.join(logs, "artefact"), log)
        node.files = files
        log.say(f"artefact {name} (run {run_id}, commit {info['headSha']}), built at {root['root']} "
                f"with Scarb {root['scarb']}")
        plan = needed_classes()
        log.say(f"plan: declare {len(plan)} classes from the artefact, deploy Registry, TxHashFate, Hub, "
                f"Instances; set_zone_checks first, set_contracts, set_play_class keys 0-"
                f"{len(dd.PLAY_CLASSES) - 1} (GoblinsLibrary last), then {len(dd.seed_records())} seed records")
        if args.dry_run:
            log.say("--dry-run: nothing sent")
            return 0
        nonce = int(node.rpc("starknet_getNonce", {"block_id": "latest", "contract_address": address}), 16)
        log.say(f"STARKNET_ACCOUNT_ADDRESS: nonce {nonce}")
        descriptor_path = os.path.join(logs, "key")
        descriptor = os.open(descriptor_path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
        try:
            with os.fdopen(descriptor, "w") as handle:
                handle.write(environ["STARKNET_PRIVATE_KEY"])
            node.sncast("persistent", "account", "import", "--url", url, "--name", node.name,
                        "--type", args.account_type, "--address", address,
                        "--private-key-file", descriptor_path)
        finally:
            os.remove(descriptor_path)
        core = dd.deploy_core(node, address)
        log.say("classes: " + ", ".join(f"{k} {v}" for k, v in core["classes"].items()))
        log.say("contracts: " + ", ".join(f"{k} {core[k]}" for k in ("registry", "fate", "hub", "instances")))
        dd.write_seed(node, core["registry"])
        count, fee, unit = totals(node)
        record = {
            "network": "Starknet Sepolia" if not args.devnet_rehearsal else "devnet rehearsal",
            "rehearsal": args.devnet_rehearsal, "chain_id": chain, "commit": info["headSha"],
            "artefact": {"run": info["url"], "name": name},
            "build_root": {k: root[k] for k in ("root", "commit", "scarb", "os") if k in root},
            "classes": core["classes"],
            "contracts": {"registry": core["registry"], "tx_hash_fate": core["fate"], "hub": core["hub"],
                          "instances": core["instances"]},
            "seed": {"records": len(dd.seed_records()), "ids": seed_ids()},
            "transactions": count, "total_fee": {"amount": str(fee), "unit": unit},
        }
        text = json.dumps(record)
        leaked = [n for v, n in redact.exact if v in text and n != "STARKNET_NETWORK"]  # a name, equal to the chain id's
        if leaked:
            raise RuntimeError(f"the record would hold the value of {leaked[0]}: not written")
        path = args.out or os.path.join(
            RECORDS, f"{datetime.datetime.now(datetime.timezone.utc):%Y-%m-%d}-{info['headSha'][:7]}.json")
        write_record(path, record)
        log.say(f"{count} transactions, total fee {fee} {unit}; record {os.path.basename(path)}")
        return 0
    finally:
        shutil.rmtree(logs, ignore_errors=True)


def main(argv, environ=os.environ):
    args = parse(argv)
    redact = Redactor(environ)
    log = Log(redact, os.path.join(environ.get("WITH_NODE_LOG_DIR", os.path.join(os.getcwd(), ".with-node")),
                                   "sepolia-deploy.log"))
    try:
        return run(args, log, redact, environ)
    except SystemExit:
        raise
    except BaseException as error:  # an echo of the URL or the address is redacted before it is shown
        log.say(f"failed: {type(error).__name__}: {error}", error=True)
        return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
