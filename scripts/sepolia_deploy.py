#!/usr/bin/env python3
"""OPS-02a: deploys the game on Sepolia from the class files of a CI artefact, and writes the record.
From the repository root, with the account in the environment (OPERATIONS §7, used by name):

    python3 scripts/sepolia_deploy.py --commit <sha on main>        # or --artifact-run <run id>
    python3 scripts/sepolia_deploy.py --commit <sha> --dry-run      # everything but the transactions

The variables `STARKNET_NETWORK`, `STARKNET_RPC_URL`, `STARKNET_ACCOUNT_ADDRESS`, `STARKNET_PRIVATE_KEY`
are read by name. **No value of any secret `STARKNET_*` variable (the RPC URL, the account address, the key)
is printed, logged or written**, nor any part of one: every
message names the variable only, and what `sncast` or the RPC echo back (an error carries the URL or the
address) goes through `Redactor` before it is printed or logged. (`STARKNET_NETWORK` is a public name: it is not redacted.
An RPC URL whose secret part is shorter than 12 characters is not supported. Nor is a secret number glued
to another hex run: `0x<address><key>`, `ab<address>`, a decimal form glued to more digits. The token regex
takes the whole run, which equals neither number, so it is not hidden.) The record holds no RPC URL and no
account. The key goes to `sncast` through a 0600 file (`O_EXCL`, deleted in a `finally`) and the accounts
file it writes lives in a private temporary folder that is removed in a `finally`: never a command line.
The account's address is public: it may appear on a `sncast` command line (in `ps`), and it is never
printed, logged or written. The URL (it may carry an API key, and `ps` shows command lines) reaches `sncast` the same way: an
`snfoundry.toml` (0600) in that folder, where `sncast` runs; no `--url` is ever passed.

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
     A rate-limited RPC read is retried with a backoff; an `sncast` call that failed on a rate limit is
     sent again only if the deployer's nonce, read before and after, did not move (OPS-03); `--pace`
     waits between transactions. The retry lines name the variable, never the URL.
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
import signal
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.parse

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import devnet_deploy as dd  # noqa: E402  the deployment order, the seed and the node, shared

REPO = "bal7hazar/grimworld"  # every `gh` call names it: the artefact is this repository's, whatever the checkout's remote
NAME = "ops02a"
CHAIN = "SN_SEPOLIA"
VARIABLES = ("STARKNET_NETWORK", "STARKNET_RPC_URL", "STARKNET_ACCOUNT_ADDRESS", "STARKNET_PRIVATE_KEY")
REFUSED = ("--give-build", "--credit-only", "--build", "--deployment", "--account", "--key-env",
           "--adventurer", "--salt")
RECORDS = os.path.join(ROOT, "deployments", "sepolia")
# OPS-03: the RPC's rate limit. A read is retried with an exponential backoff (BACKOFF * 2^k, capped at
# BACKOFF_CAP seconds) and at most TRIES tries in all; then the run fails as before.
TRIES, BACKOFF, BACKOFF_CAP = 6, 1.0, 30.0
PACE = 1.0  # seconds between two transactions: each costs about six RPC calls (nonce twice, chain id, fee
#             estimate, send, receipt polls); a free tier allows a few calls per second, one transaction per
#             second keeps under it, and the 30-odd transactions of a full run take half a minute more
RATE_LIMITED = re.compile(r"request too fast|cu limit|rate.?limit|too many requests|-32011|\b429\b", re.IGNORECASE)
# What sncast 0.64 prints when the RPC refuses a call (seen 2026-10-15, run 2): `Error: Failed to fetch
# chain_id` then `JSON-RPC error: code=-32011, message="cu limit exceeded; Request too fast per second ..."`.
# The text only decides whether the nonce check is worth trying, never whether a transaction was submitted:
# a -32011 can arrive after the node accepted the transaction (PM ruling, OPS-03).
# The node refuses a resend whose nonce it has already used: Starknet's INVALID_TRANSACTION_NONCE (code 52,
# "Invalid transaction nonce"); sncast 0.64 echoes the node's message. Only a resend is read this way.
NONCE_REFUSED = re.compile(r"invalid transaction nonce|invalid.?nonce|code=52\b", re.IGNORECASE)
SUBMITTING = ("declare-from", "declare", "deploy", "invoke")
FOUND_TRIES, FOUND_WAIT = 20, 3.0  # looking for the transaction an accepted-but-failed call left
KINDS = {dd.REGION: "region", dd.LOCATION: "location", dd.GATE: "gate", dd.ITEM: "item",
         9: "skill", 8: "caste", 7: "pack", 6: "spawn_table"}


class Redactor:
    """Hides the value of each STARKNET_* variable (and the forms an echo may take) in a text. The URL
    is hidden whole and by its parts (host, path, query, a long path segment: an API key sits in one),
    the address and the key by their number whatever the padding, with or without 0x, in hex or decimal.
    One pass is one case-insensitive alternation, the longest value first, so a replacement is never cut by
    another value; a placeholder already written is left alone. A number glued to another value
    (`5e47a1d0c0ffee1234<value>`) is not delimited in the first pass, so the passes repeat until the text
    stops changing (at most MAX_PASSES): a text redacted twice is the same.
    The bound, reasoned: pass 1 hides every value; pass 2 hides the numbers that pass 1's placeholders newly
    delimited; so at most 2 passes change the text and the third sees it stable. Each pass only adds
    placeholders, so a result capped at MAX_PASSES is never less redacted than one pass.
    STARKNET_NETWORK is not redacted: it is a public name ("sepolia"), not a secret, and a short value
    would garble every line of the log.
    Limit: an RPC URL whose secret part (a path, query or `;params` segment) is shorter than 12 characters
    is not supported: a shorter piece is not hidden when it is echoed alone (a lower floor would hide
    words of the record such as "starknet").
    Limit: a secret number glued to another hex run (`0x<address><key>`, `ab<address>`, a decimal form glued
    to more digits) is not hidden: TOKEN takes the whole run, which equals neither number."""

    MAX_PASSES = 4
    PLACEHOLDER = r"<STARKNET_[A-Z_]+>"
    TOKEN = r"(?<![0-9a-zA-Z])(?P<prefix>0[xX])?0*(?P<digits>[0-9a-fA-F]+)(?![0-9a-zA-Z])"  # a hex number, 0x or not

    def __init__(self, environ):
        self.names, self.numbers = {}, []  # the lower-case value -> the variable; (number, variable)
        for name in VARIABLES:
            value = environ.get(name, "")
            if not value or name == "STARKNET_NETWORK":
                continue
            self.names.setdefault(value.lower(), name)
            if name == "STARKNET_RPC_URL":
                parts = urllib.parse.urlparse(value)
                pieces = [parts.netloc, parts.hostname or "", parts.path.strip("/"), parts.query,
                          parts.username or "", parts.password or ""]
                pieces.append(parts.params)
                pieces += [p for p in re.split(r"[/?&=;]", parts.path + ";" + parts.params + "?" + parts.query)
                           if len(p) >= 12]
                for piece in pieces:
                    if len(piece) >= 4:
                        self.names.setdefault(piece.lower(), name)
            if name in ("STARKNET_ACCOUNT_ADDRESS", "STARKNET_PRIVATE_KEY"):
                try:  # with or without 0x, leading zeros or not; also as a decimal number
                    number = int(value[2:] if value[:2] in ("0x", "0X") else value, 16)
                    self.numbers.append((number, name))
                    if len(str(number)) >= 8:
                        self.names.setdefault(str(number), name)
                except ValueError:
                    pass
        values = sorted(self.names, key=lambda v: -len(v))  # the longest first at a position
        self.pattern = re.compile("|".join([f"(?P<placeholder>{self.PLACEHOLDER})"]
                                           + [f"(?P<value>{'|'.join(map(re.escape, values))})"] * bool(values)
                                           + [f"(?P<token>{self.TOKEN})"]), re.IGNORECASE)

    def replace(self, match):
        if match.group("placeholder"):
            return match.group(0)
        if match.group("value"):
            return f"<{self.names[match.group('value').lower()]}>"
        # a number: 0x0abc, 0xabc, 0x000...abc, or without 0x (8 hex digits or more)
        prefix, digits = match.group("prefix"), match.group("digits")
        for number, name in self.numbers:
            if (prefix or len(digits) >= 8) and int(digits, 16) == number:
                return f"<{name}>"
        return match.group(0)

    def __call__(self, text):
        text = str(text)
        for _ in range(self.MAX_PASSES):
            again = self.pattern.sub(self.replace, text)
            if again == text:
                break
            text = again
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

    def __init__(self, url, address, key, logs, files, redact, say=lambda text: None, pace=0.0,
                 backoff=BACKOFF, sleep=time.sleep, tag="pre_confirmed"):
        super().__init__(url, address, key, logs)
        self.files = files
        self.redact = redact
        self.say = say
        self.pace, self.backoff, self.sleep, self.tag = pace, backoff, sleep, tag
        self.submitted = 0  # the transactions sent so far: the pace waits between two of them
        # The URL may carry an API key and `ps` shows a command line: `sncast` reads it from the
        # `snfoundry.toml` of its working folder (a private folder, 0600 file, removed with `logs`).
        self.home = os.path.join(logs, "sncast")
        os.makedirs(self.home, mode=0o700, exist_ok=True)
        descriptor = os.open(os.path.join(self.home, "snfoundry.toml"), os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
        with os.fdopen(descriptor, "w") as handle:
            handle.write(f"[sncast.default]\nurl = {json.dumps(url)}\n")
        # asdf's shim picks `sncast` by the .tool-versions of the working folder
        shutil.copy(os.path.join(ROOT, ".tool-versions"), self.home)

    def wait_time(self, attempt):
        return min(self.backoff * 2 ** (attempt - 1), BACKOFF_CAP)

    @staticmethod
    def rate_limit_kind(error):
        """"HTTP 429", "JSON-RPC -32011", "rate limit" for a rate-limit answer, else None."""
        if isinstance(error, urllib.error.HTTPError):
            return "HTTP 429" if error.code == 429 else None
        if isinstance(error, dd.RpcError) and error.code == -32011:
            return "JSON-RPC -32011"
        return "rate limit" if RATE_LIMITED.search(str(error)) else None

    def rpc(self, method, params):
        """An RPC read retried when the answer is a rate limit (a read changes nothing). Each retry prints
        the variable, the kind, the try and the wait: never the URL."""
        for attempt in range(1, TRIES + 1):
            try:
                return super().rpc(method, params)
            except (urllib.error.HTTPError, dd.RpcError) as error:
                kind = self.rate_limit_kind(error)
                if kind is None or attempt == TRIES:
                    raise
                wait = self.wait_time(attempt)
                self.say(f"STARKNET_RPC_URL: {kind}, try {attempt} of {TRIES}, waiting {wait:g} s")
                self.sleep(wait)

    def account_nonce(self):
        """The deployer's nonce at `pre_confirmed` (Starknet 0.14 / RPC 0.9 replaced `pending` with it; a 0.9
        node refuses `pending`). It moves as soon as the node accepts a transaction; `latest` moves only
        when a block holds it, so after an accepted-but-failed call it would still read the old value.
        (The devnet rehearsal reads `latest`: a devnet mines at once, so it is the same value and needs
        no support for `pre_confirmed`.) The read alone is not what keeps a transaction from being sent
        twice: every send carries the reference nonce (`attempts`), so a second copy is refused by the node."""
        return int(self.rpc("starknet_getNonce", {"block_id": self.tag, "contract_address": self.address}), 16)

    def sncast_cwd(self, package):
        return self.home

    def sncast_args(self, args):
        """Drops `--url <url>`: the profile above holds it."""
        args = list(args)
        while "--url" in args:
            at = args.index("--url")
            del args[at:at + 2]
        return args

    def sncast(self, package, *args, account=True):
        submits = account and any(a in SUBMITTING for a in args[:4])
        if submits and self.submitted:
            self.sleep(self.pace)
        before = len(self.sent)
        out = self.attempts(package, args, account, submits)
        if submits:
            self.submitted += 1
        for tx in self.sent[before:]:
            self.say(f"transaction {tx}")
        return out

    def attempts(self, package, args, account, submits):
        """`sncast`, again when it failed on a rate limit and the account's nonce shows that no
        transaction was accepted. One reference nonce is read before the first send and every send
        carries it (`--nonce`), so a second copy can only be refused by the node (an invalid nonce),
        never accepted, even if the node takes the first copy after our check. After a failure the
        nonce is read again and compared with the reference: unchanged, resend; reference + 1, the node
        took the transaction: wait for it and take it as the call's result; anything else, an
        unclassified error, an unreadable nonce, the tries spent: stop as before. The error text is
        never the proof; it only decides whether to try the check."""
        words = [a for i, a in enumerate(args[:5]) if not a.startswith("--") and not a.startswith("0x")
                 and not (i and args[i - 1] == "--account")]  # the account's name is not part of the call's
        what = " ".join(words)
        reference = self.account_nonce() if submits else None
        sent = [*args, "--nonce", hex(reference)] if submits else list(args)
        for attempt in range(1, TRIES + 1):
            try:
                return super().sncast(package, *sent, account=account)
            except RuntimeError as error:
                kind = self.rate_limit_kind(error)
                if kind is None and attempt > 1 and NONCE_REFUSED.search(str(error)):
                    kind = "nonce refused"  # the resend met the first copy: the node has it
                if kind is None or attempt == TRIES:
                    raise
                if not submits:  # nothing to send: a read, a hash, an import
                    self.retry_line(kind, attempt)
                    continue
                try:
                    after = self.account_nonce()
                except Exception as read:
                    raise RuntimeError(f"sncast {what}: failed ({kind}) and the nonce could not be read "
                                       f"to tell whether it was sent: stopping ({read})") from error
                if after == reference and kind != "nonce refused":
                    self.retry_line(kind, attempt)
                    continue
                if after == reference:  # only a refused resend gets here: a copy is pending, not visible yet
                    raise RuntimeError(f"sncast {what}: the resend was refused for its nonce {reference} but "
                                       f"the nonce still reads {after}: a copy is pending and not yet "
                                       f"visible: stopping") from error
                if after != reference + 1:
                    raise RuntimeError(f"sncast {what}: failed ({kind}) and the nonce went from {reference} "
                                       f"to {after}: stopping") from error
                return self.accepted(what, args, reference, kind)
        raise AssertionError("unreachable")

    def retry_line(self, kind, attempt):
        wait = self.wait_time(attempt)
        self.say(f"STARKNET_RPC_URL: sncast {kind}, nothing submitted, try {attempt} of {TRIES}, waiting {wait:g} s")
        self.sleep(wait)

    def accepted(self, what, args, nonce, kind):
        """The call failed but the node accepted its transaction (the nonce advanced): find it by
        (sender, nonce), wait for its receipt and rebuild what sncast would have printed. If it cannot
        be had reliably, stop, saying which call."""
        try:
            tx = self.find_transaction(nonce)
            receipt = self.wait_receipt(tx["transaction_hash"])
            out = f"Transaction Hash: {tx['transaction_hash']}\n"
            if "declare-from" in args or "declare" in args:
                out += f"Class Hash: {tx['class_hash']}\n"
            elif "deploy" in args:
                out += f"Contract Address: {self.deployed(receipt, args)}\n"
        except Exception as error:
            raise RuntimeError(f"sncast {what}: failed ({kind}) after the node accepted its transaction "
                               f"(nonce {nonce}) and the result could not be had: {error}: stopping") from error
        self.say(f"sncast {what}: failed ({kind}) but the node accepted it (nonce {nonce}): "
                 f"took transaction {tx['transaction_hash']}")
        sent = re.search(r"Transaction Hash:\s*(0x[0-9a-fA-F]+)", out)
        self.sent.append(sent.group(1))
        return out

    def find_transaction(self, nonce):
        """The deployer's transaction with that nonce, in the pre-confirmed block or the blocks from the latest
        down to ten before the first latest seen. It matches on (sender, nonce): that assumes nothing
        else sends from the deployer's account during the run."""
        anchor = None
        for attempt in range(FOUND_TRIES):
            blocks = [{"block_id": "pre_confirmed"}]
            try:
                latest = self.rpc("starknet_blockNumber", {})
                anchor = latest if anchor is None else anchor
                blocks += [{"block_id": {"block_number": n}} for n in range(latest, max(anchor - 10, -1), -1)]
            except dd.RpcError:
                pass
            for block in blocks:
                try:
                    txs = self.rpc("starknet_getBlockWithTxs", block)["transactions"]
                except dd.RpcError:
                    continue
                for tx in txs:
                    if tx.get("type") in ("INVOKE", "DECLARE") and "sender_address" in tx \
                            and int(tx["sender_address"], 16) == int(self.address, 16) \
                            and int(tx["nonce"], 16) == nonce:
                        return tx
            self.sleep(FOUND_WAIT)
        raise RuntimeError("no transaction of the account with that nonce in the pre-confirmed or latest blocks")

    def wait_receipt(self, tx):
        for _ in range(FOUND_TRIES * 4):
            try:
                receipt = self.rpc("starknet_getTransactionReceipt", {"transaction_hash": tx})
            except dd.RpcError as error:
                if error.code != 29:  # TXN_HASH_NOT_FOUND: not there yet
                    raise
            else:
                if receipt.get("execution_status") == "REVERTED":
                    raise RuntimeError(f"transaction {tx} reverted: {receipt.get('revert_reason')}")
                if receipt.get("finality_status") in ("ACCEPTED_ON_L2", "ACCEPTED_ON_L1"):
                    return receipt
            self.sleep(FOUND_WAIT)
        raise RuntimeError(f"transaction {tx} not accepted in time")

    def deployed(self, receipt, args):
        """The address of the `ContractDeployed` event (data: address, deployer, unique, class hash, ...)
        whose class hash is the call's `--class-hash`."""
        class_hash = int(args[args.index("--class-hash") + 1], 16)
        selector = dd.storage_key("ContractDeployed")
        for event in receipt.get("events", []):
            data = event["data"]
            if event["keys"] and int(event["keys"][0], 16) == selector and len(data) > 3 \
                    and int(data[3], 16) == class_hash:
                return data[0]
        raise RuntimeError("no ContractDeployed event of that class in the receipt")

    def is_declared(self, class_hash):
        try:
            self.rpc("starknet_getClass", {"block_id": "latest", "class_hash": class_hash})
            return True
        except dd.RpcError as error:
            if error.code == 28:  # CLASS_HASH_NOT_FOUND
                return False
            raise

    def declare(self, package, name):
        """A class the chain has already (an unchanged class keeps its hash; a retry meets it) is not
        declared again: sncast 0.64 errors on it. The hash is computed from the artefact's file."""
        path = self.files[(package, name)]
        class_hash = hex(int(dd.field("Class Hash", super().sncast(
            package, "utils", "class-hash", "--sierra-file", path, account=False)), 16))  # as declare prints it
        if self.is_declared(class_hash):
            self.say(f"{name}: already declared, class {class_hash}")
            return class_hash
        out = self.sncast(package, "--account", self.name, "--wait", "declare-from", "--url", self.url,
                          "--sierra-file", path)
        declared = dd.field("Class Hash", out)
        if int(declared, 16) != int(class_hash, 16):
            raise RuntimeError(f"{name}: declared class {declared} is not the file's {class_hash}")
        self.say(f"{name}: declared class {declared}")
        return declared

    def deploy(self, package, class_hash, *calldata):
        address = super().deploy(package, class_hash, *calldata)
        self.say(f"deployed class {class_hash} at {address}")
        return address


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


def read_sncast_version(log):
    """`sncast --version`, read before the first transaction; a failed or empty answer stops the run."""
    try:
        out = subprocess.run(["sncast", "--version"], capture_output=True, text=True, cwd=ROOT)
    except OSError as error:
        log.die(f"sncast --version: {error.strerror}")
    version = out.stdout.strip()
    if out.returncode != 0 or not version.startswith("sncast"):
        log.die(f"sncast --version failed or empty (exit {out.returncode}): nothing sent")
    return version


def gh(command, *args):
    out = subprocess.run(["gh", *command.split(), "-R", REPO, *args], cwd=ROOT, capture_output=True, text=True)
    if out.returncode != 0:
        raise RuntimeError(f"gh {command}: {out.stderr.strip()[-500:]}")
    return out.stdout


def find_run(args, log):
    """The CI run the classes come from: `--artifact-run`, or the newest successful push run of
    `--commit` on main. Refused unless its event is `push` and its branch `main`."""
    run = args.artifact_run
    if run is None:
        if not re.fullmatch(r"[0-9a-f]{40}", args.commit):
            log.die("--commit is the full 40-hex sha of a commit on main")
        runs = json.loads(gh("run list", "--workflow", "ci.yml", "--branch", "main", "--event", "push",
                             "--commit", args.commit, "--status", "success", "--limit", "5",
                             "--json", "databaseId"))
        if not runs:
            log.die(f"no successful push run of ci.yml on main for commit {args.commit}")
        run = runs[0]["databaseId"]
    info = json.loads(gh("run view", str(run), "--json", "event,headBranch,headSha,url,workflowName,"
                                                           "conclusion"))
    if not info["url"].startswith(f"https://github.com/{REPO}/actions/runs/"):
        log.die(f"run {run}: not a run of {REPO}")
    if info["conclusion"] != "success":
        log.die(f"run {run}: conclusion {info['conclusion']!r}, not 'success'")
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
        gh("run download", str(run), "-n", name, "-D", folder)
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
    parser.add_argument("--pace", type=float, default=PACE, metavar="SECONDS",
                        help=f"wait this long between two transactions, against the RPC's rate limit "
                             f"(default {PACE:g}; --devnet-rehearsal uses 0)")
    parser.add_argument("--backoff", type=float, default=BACKOFF, help=argparse.SUPPRESS)  # the smoke's
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
    if args.devnet_rehearsal and os.path.abspath(args.out).startswith(RECORDS + os.sep):
        log.die("--out is under deployments/sepolia: a rehearsal's record is never written there")
    missing = [name for name in VARIABLES if not environ.get(name)]
    if missing:
        log.die(f"{', '.join(missing)}: not set")
    url = environ["STARKNET_RPC_URL"]
    try:  # with or without 0x: sncast gets 0x<hex>; the redactor knows both forms
        address = hex(int(environ["STARKNET_ACCOUNT_ADDRESS"], 16))
        key = hex(int(environ["STARKNET_PRIVATE_KEY"], 16))
    except ValueError:
        log.die("STARKNET_ACCOUNT_ADDRESS or STARKNET_PRIVATE_KEY: not hex")
    check_endpoint(url, args.devnet_rehearsal, log)
    if args.pace < 0 or args.backoff < 0:
        log.die("--pace: not a number of seconds, 0 or more")
    pace = 0.0 if args.devnet_rehearsal else args.pace

    logs = tempfile.mkdtemp(prefix="sepolia-deploy-")  # 0700: the accounts file holds the key
    try:
        node = SepoliaNode(url, address, "unused", logs, {}, redact, log.say, pace=pace, backoff=args.backoff,
                           tag="latest" if args.devnet_rehearsal else "pre_confirmed")
        chain = check_chain(node, args.devnet_rehearsal, log)
        sncast_version = read_sncast_version(log)
        run_id, info = find_run(args, log)
        name, root, files = download(run_id, info, os.path.join(logs, "artefact"), log)
        node.files = files
        log.say(f"artefact {name} (run {run_id}, commit {info['headSha']}), built at {root['root']} "
                f"with Scarb {root['scarb']}")
        plan = needed_classes()
        log.say(f"plan: declare {len(plan)} classes from the artefact, deploy Registry, TxHashFate, Hub, "
                f"Instances; set_zone_checks first, set_contracts, set_play_class keys 0-"
                f"{len(dd.PLAY_CLASSES) - 1} (GoblinsLibrary last), then {len(dd.seed_records())} seed records")
        log.say(f"pace: {pace:g} s between transactions" + (" (rehearsal)" if args.devnet_rehearsal else ""))
        if args.dry_run:
            log.say("--dry-run: nothing sent")
            return 0
        nonce = int(node.rpc("starknet_getNonce", {"block_id": "latest", "contract_address": address}), 16)
        log.say(f"STARKNET_ACCOUNT_ADDRESS: nonce {nonce}")
        descriptor_path = os.path.join(logs, "key")
        descriptor = os.open(descriptor_path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
        try:
            with os.fdopen(descriptor, "w") as handle:
                handle.write(key)
            node.sncast("persistent", "account", "import", "--url", url, "--name", node.name,
                        "--type", args.account_type, "--address", address,
                        "--private-key-file", descriptor_path)
        finally:
            os.remove(descriptor_path)
        try:
            core = dd.deploy_core(node, address)
            log.say("classes: " + ", ".join(f"{k} {v}" for k, v in core["classes"].items()))
            log.say("contracts: " + ", ".join(f"{k} {core[k]}" for k in ("registry", "fate", "hub", "instances")))
            dd.write_seed(node, core["registry"])
            count, fee, unit = totals(node)
        except BaseException:  # what was sent so far, so that a retry knows what exists
            try:
                count, fee, unit = totals(node)
                log.say(f"stopped after {count} transactions, fees so far {fee} {unit}", error=True)
            except BaseException:
                log.say(f"stopped after {len(node.sent)} transactions (fees unreadable)", error=True)
            raise
        record = {
            "network": "Starknet Sepolia" if not args.devnet_rehearsal else "devnet rehearsal",
            "rehearsal": args.devnet_rehearsal, "chain_id": chain, "commit": info["headSha"],
            "artefact": {"run": info["url"], "name": name},
            "build_root": {k: root[k] for k in ("root", "commit", "scarb", "os") if k in root},
            "classes": core["classes"],
            "contracts": {"registry": core["registry"], "tx_hash_fate": core["fate"], "hub": core["hub"],
                          "instances": core["instances"]},
            "seed": {"records": len(dd.seed_records()), "ids": seed_ids()},
            "tools": {"sncast": sncast_version},
            "transactions": count, "total_fee": {"amount": str(fee), "unit": unit},
        }
        text = json.dumps(record)
        # The redactor itself is the check: the record must come out of it unchanged (STARKNET_NETWORK is
        # not redacted: the record holds the name legitimately, chain id and network).
        if redact(text) != text:
            raise RuntimeError("the record would hold the value of a STARKNET_* variable: not written")
        path = args.out or os.path.join(
            RECORDS, f"{datetime.datetime.now(datetime.timezone.utc):%Y-%m-%d}-{info['headSha'][:7]}.json")
        write_record(path, record)
        log.say(f"{count} transactions, total fee {fee} {unit}; record {os.path.basename(path)}")
        return 0
    finally:
        shutil.rmtree(logs, ignore_errors=True)


def terminate(signum, frame):
    """SIGTERM/SIGHUP end the run through the `finally` that removes the temporary folder (URL, key)."""
    raise SystemExit(128 + signum)


def main(argv, environ=os.environ):
    args = parse(argv)
    for number in (signal.SIGTERM, signal.SIGHUP):
        signal.signal(number, terminate)
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
