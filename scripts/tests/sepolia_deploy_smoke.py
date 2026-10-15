#!/usr/bin/env python3
"""OPS-02a's smoke test: `scripts/sepolia_deploy.py` against the node `with-node.sh` started, as a
`--devnet-rehearsal` (nothing here goes near Sepolia). From the repository root:

    scripts/with-node.sh python3 scripts/tests/sepolia_deploy_smoke.py

It needs `gh` (read access to the repository's Actions):
  * the rehearsal: the newest successful push run of `main` that holds a `contract-classes-<sha>` artefact
    is downloaded by the script (`--artifact-run`), declared from its files, deployed in §7's order, and
    the record is checked against the chain: the class hash of each contract, the transaction count equal
    to the account's nonce, a fee, `Registry.last_id` for the seed's kinds, `Hub.account_of`, and
    `Instances.placement` (one view per contract; `TxHashFate` has none, its class is read instead);
  * `--dry-run` sends nothing (the account's nonce stays 0);
  * the refusals, each with its message and nothing sent: a pull request's run, `--give-build` (and the
    other options of the devnet script), a chain id that is not `SN_SEPOLIA` (a stub RPC), a local URL
    without `--devnet-rehearsal`, a remote URL with it, a devnet reached without it, a variable missing;
  * OPS-03, on stubs (no `gh`, no node): a read answered 429 or -32011 twice is retried with the backoff and
    each retry prints one line without the URL; the tries are bounded; any other error is not retried; an
    `sncast` rate-limit error is retried only when the deployer's nonce did not move (it is read before and
    after); when it moved the call is not resent and the accepted transaction is taken as the result (or the
    run stops, naming the call); an error that is no rate limit is never retried; `--pace` waits between
    transactions;
  * no value of any `STARKNET_*` variable, in any form (raw, an address padded or not, the URL's host and
    path), appears in stdout, stderr, the log file, the record or the files left behind: the rehearsal runs
    with the node's real URL, address and key (and a sentinel network), the refusal runs with sentinels,
    and a stub RPC whose errors echo all four values proves the redaction on the error path.
"""
import http.server
import json
import os
import re
import subprocess
import sys
import tempfile
import threading

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, os.path.join(ROOT, "scripts"))
import devnet_deploy  # noqa: E402
import sepolia_deploy  # noqa: E402

SCRIPT = os.path.join(ROOT, "scripts", "sepolia_deploy.py")
VARIABLES = sepolia_deploy.VARIABLES
FAKE = {"STARKNET_NETWORK": "sentinel-network-a1b2c3",
        "STARKNET_RPC_URL": "https://rpc.sentinel-host-9c1d.example/v3/sentinelapikey7788",
        "STARKNET_ACCOUNT_ADDRESS": "0x05e47a1d0c0ffee1234",
        "STARKNET_PRIVATE_KEY": "0x05e47c0de5ec12e7abcd"}


NOPREFIX = {**FAKE, "STARKNET_ACCOUNT_ADDRESS": "05e47a1d0c0ffee1234",
            "STARKNET_PRIVATE_KEY": "05e47c0de5ec12e7abcd"}  # no 0x, a leading zero


def forms(name, value):
    """What a leak of `value` may look like in an output."""
    found = {value}
    if name in ("STARKNET_ACCOUNT_ADDRESS", "STARKNET_PRIVATE_KEY"):
        number = int(value[2:] if value[:2] == "0x" else value, 16)
        found |= {hex(number), f"{number:x}", f"{number:064x}", f"{number:#066x}", f"0x{number:x}".upper().replace("0X", "0x"), str(number)}
    if name == "STARKNET_RPC_URL":
        parts = devnet_deploy.urllib.parse.urlparse(value)
        found |= {parts.netloc, *[p for p in parts.path.split("/") if len(p) >= 8]}
    return {f for f in found if len(f) >= 6}


class Stub(http.server.BaseHTTPRequestHandler):
    """A JSON-RPC node: answers a chain id; `devnet_getPredeployedAccounts` fails with an error that
    echoes every value it was given (`Stub.echo`), as a provider's error may echo the URL and the account."""

    chain, echo, methods = "SN_MAIN", "", []

    def do_POST(self):
        request = json.loads(self.rfile.read(int(self.headers["content-length"])))
        Stub.methods.append(request["method"])
        if request["method"] == "starknet_chainId":
            answer = {"result": "0x" + Stub.chain.encode().hex()}
        else:
            answer = {"error": {"code": -32601, "message": f"unknown method at {Stub.echo}"}}
        body = json.dumps({"jsonrpc": "2.0", "id": 1, **answer}).encode()
        self.send_response(200)
        self.send_header("content-length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *args):
        pass


def start_stub(chain, echo=""):
    Stub.chain, Stub.echo, Stub.methods = chain, echo, []
    server = http.server.HTTPServer(("127.0.0.1", 0), Stub)
    threading.Thread(target=server.serve_forever, daemon=True).start()
    return server, f"http://127.0.0.1:{server.server_address[1]}"


def gh(*args):
    out = subprocess.run(["gh", *args], cwd=ROOT, capture_output=True, text=True)
    assert out.returncode == 0, f"gh {args[:3]}: {out.stderr}"
    return out.stdout


def main_run():
    """The newest successful push run of main that holds a contract-classes artefact (the job runs only
    when the contracts changed, so the very latest run may hold none)."""
    for run in json.loads(gh("run", "list", "--workflow", "ci.yml", "--branch", "main", "--event", "push",
                             "--status", "success", "--limit", "30", "--json", "databaseId")):
        names = gh("api", f"repos/{{owner}}/{{repo}}/actions/runs/{run['databaseId']}/artifacts",
                   "--jq", ".artifacts[] | select(.expired == false) | .name")
        if "contract-classes-" in names:
            return run["databaseId"]
    raise AssertionError("no push run of main with a contract-classes artefact in the last 30")


def pull_request_run():
    """A finished, successful pull request run (the run of this very job is in progress, and the
    conclusion guard would refuse it before the event guard is reached)."""
    runs = json.loads(gh("run", "list", "--workflow", "ci.yml", "--event", "pull_request", "--status",
                         "success", "--limit", "1", "--json", "databaseId"))
    assert runs, "no successful pull request run of ci.yml"
    return runs[0]["databaseId"]


def stub_tool(folder, name, script):
    os.makedirs(folder, exist_ok=True)
    path = os.path.join(folder, name)
    with open(path, "w") as handle:
        handle.write("#!/bin/sh\n" + script)
    os.chmod(path, 0o755)


def leftovers():
    return set(os.listdir(tempfile.gettempdir())) if os.path.isdir(tempfile.gettempdir()) else set()


class Run:
    """One run of the script: its exit code, stdout, stderr, log file and the sentinel check."""

    def __init__(self, env_values, *args, path=None):
        before = {n for n in leftovers() if n.startswith("sepolia-deploy-")}
        self.logs = tempfile.mkdtemp(prefix="smoke-logs-")
        env = {k: v for k, v in os.environ.items()
               if not (k.startswith("STARKNET_") or k.startswith("NODE_") or k in ("RPC_URL",
                                                                                   "WITH_NODE_LOG_DIR"))}
        env.update(env_values)
        if path:  # a folder of stub tools in front of the PATH
            env["PATH"] = path + os.pathsep + env["PATH"]
        env["WITH_NODE_LOG_DIR"] = self.logs
        out = subprocess.run([sys.executable, SCRIPT, *args], cwd=ROOT, env=env, capture_output=True, text=True)
        self.code, self.stdout, self.stderr = out.returncode, out.stdout, out.stderr
        log = os.path.join(self.logs, "sepolia-deploy.log")
        self.log = open(log).read() if os.path.exists(log) else ""
        self.values = env_values
        after = {n for n in leftovers() if n.startswith("sepolia-deploy-")}
        assert after == before, f"the script left a temporary folder behind: {after - before}"
        assert os.listdir(self.logs) in ([], ["sepolia-deploy.log"]), os.listdir(self.logs)
        assert oct(os.stat(log).st_mode & 0o777) == "0o600" if self.log else True
        self.no_leak(self.stdout, self.stderr, self.log)

    def no_leak(self, *texts):
        for name, value in self.values.items():
            if name == "STARKNET_NETWORK":  # a public name: the stub's echo of it is not redacted
                continue
            for form in forms(name, value):
                for text in texts:
                    assert form not in text, f"{name} leaked as {form!r} in:\n{text[:800]}"

    def refused(self, message):
        assert self.code != 0, (self.stdout, self.stderr)
        assert message in self.stderr, f"{message!r} not in stderr:\n{self.stderr}"


def check_redactor():
    values = {**FAKE, "STARKNET_ACCOUNT_ADDRESS": "0x0abc", "STARKNET_PRIVATE_KEY": "0x123456789"}
    redact = sepolia_deploy.Redactor(values)
    text = ("GET https://rpc.sentinel-host-9c1d.example/v3/sentinelapikey7788 account 0xabc "
            "also 0x000000000000000abc and key 0x0123456789 host rpc.sentinel-host-9c1d.example "
            "network sentinel-network-a1b2c3 sentinelapikey7788 and another 0xabcd")
    clean = redact(text)
    for name, value in values.items():
        if name != "STARKNET_NETWORK":  # a public name, not redacted
            assert value.lstrip("0x") not in clean.replace("0xabcd", ""), (name, clean)
    assert "sentinelapikey7788" not in clean and "sentinel-host-9c1d" not in clean, clean
    assert "0xabcd" in clean, "another number is left alone"
    assert redact(clean) == clean, ("not idempotent", clean)
    assert "<STARKNET_RPC_URL>" in clean and "<STARKNET_ACCOUNT_ADDRESS>" in clean, clean
    # a value without 0x, with a leading zero, in any padding
    bare = sepolia_deploy.Redactor({**FAKE, "STARKNET_ACCOUNT_ADDRESS": NOPREFIX["STARKNET_ACCOUNT_ADDRESS"],
                                    "STARKNET_PRIVATE_KEY": NOPREFIX["STARKNET_PRIVATE_KEY"]})
    for echo in ("5e47a1d0c0ffee1234", "05e47a1d0c0ffee1234", "0x5e47a1d0c0ffee1234", "0x" + "5e47a1d0c0ffee1234".zfill(64),
                 "5E47C0DE5EC12E7ABCD", "0x05e47c0de5ec12e7abcd"):
        out = bare(f"account {echo} failed")
        assert "5e47" not in out.lower(), (echo, out)
        assert bare(out) == out, ("not idempotent", echo, out)


def check_overlap():
    """Overlapping, realistic values: STARKNET_NETWORK=sepolia and a host that holds it. One pass, so a
    replacement is never cut by another and a placeholder is never scanned again."""
    key = "KEYabcdef1234567890ABCDEF"
    values = {"STARKNET_NETWORK": "sepolia",
              "STARKNET_RPC_URL": f"https://starknet-sepolia.g.alchemy.com/starknet/version/rpc/v0_8/{key}",
              "STARKNET_ACCOUNT_ADDRESS": "0x05e47a1d0c0ffee1234", "STARKNET_PRIVATE_KEY": "5e47c0de5ec12e7abcd0"}
    redact = sepolia_deploy.Redactor(values)
    url = values["STARKNET_RPC_URL"]
    echoes = {"host": "starknet-sepolia.g.alchemy.com", "netloc": "starknet-sepolia.g.alchemy.com:443",
              "path": f"/starknet/version/rpc/v0_8/{key}", "url": url, "upper host": "STARKNET-SEPOLIA.G.ALCHEMY.COM",
              "path no slash": f"starknet/version/rpc/v0_8/{key.lower()}"}
    for what, echo in echoes.items():
        out = redact(f"error at {echo} (retry)")
        for fragment in ("alchemy", "sepolia", key[:10].lower(), "g.alch", "v0_8"):
            assert fragment not in out.lower().replace("<starknet_network>", ""), (what, out)
        assert "<STARKNET_RPC_URL>" in out, (what, out)
        assert "<STARKNET_<" not in out and out.count("<") == out.count(">"), (what, out)
        assert redact(out) == out, ("not idempotent", what, out)
    assert redact("network sepolia") == "network sepolia", "STARKNET_NETWORK is a public name: not redacted"
    # the placeholders survive a second pass whatever the URL's pieces are ("starknet" is one: a path segment)
    assert redact("<STARKNET_RPC_URL> <STARKNET_NETWORK>") == "<STARKNET_RPC_URL> <STARKNET_NETWORK>"
    # the record's check: unchanged by the redactor ("Starknet Sepolia" is in it)
    record = json.dumps({"network": "Starknet Sepolia", "chain_id": "SN_SEPOLIA", "commit": "ab" * 20})
    assert redact(record) == record
    leaked = json.dumps({"rpc": url})
    assert redact(leaked) != leaked
    # a short network value does not garble the log: class hashes and addresses stay readable
    short = sepolia_deploy.Redactor({**values, "STARKNET_NETWORK": "a"})
    line = "class 0x1234abcd declared at 0x0def56789 (a retry needs it)"
    assert short(line) == line, short(line)
    # a number glued to another redacted value: the passes repeat until the text is stable
    glued = sepolia_deploy.Redactor({**values, "STARKNET_NETWORK": "sepolia"})
    host = "starknet-sepolia.g.alchemy.com"
    for what, number in (("address", "5e47a1d0c0ffee1234"), ("key", "5e47c0de5ec12e7abcd0")):
        for text in (f"{number}{host}", f"addr {number}{key}", f"0x{number}{host}x", f"{host}{number}"):
            out = glued(text)
            assert "5e47" not in out.lower(), (what, text, out)
            assert glued(out) == out, ("not idempotent", what, text, out)
    # a `;params` segment is a piece like the path and the query, and the 12-character floor stays
    semi = sepolia_deploy.Redactor({"STARKNET_RPC_URL": "https://rpc.example.org/v3;apikey=SECRETparam123?x=1"})
    out = semi("echo SECRETparam123 and apikey and starknet")
    assert "SECRETparam123" not in out and "starknet" in out and "apikey" in out, out
    short_key = sepolia_deploy.Redactor({"STARKNET_RPC_URL": "https://rpc.example.org/v3/short"})
    assert "short" in short_key("echo short"), "documented limit: a secret under 12 characters is not hidden"


def check_command_line():
    """The URL never reaches a command line: `--url` is dropped and the profile holds it (0600)."""
    logs = tempfile.mkdtemp(prefix="smoke-node-")
    try:
        url = FAKE["STARKNET_RPC_URL"]
        node = sepolia_deploy.SepoliaNode(url, FAKE["STARKNET_ACCOUNT_ADDRESS"], "unused", logs, {}, str)
        args = node.sncast_args(["--account", "deployer", "--wait", "invoke", "--url", url, "--function", "f"])
        assert args == ["--account", "deployer", "--wait", "invoke", "--function", "f"], args
        assert url not in " ".join(args)
        profile = os.path.join(node.sncast_cwd("persistent"), "snfoundry.toml")
        assert oct(os.stat(profile).st_mode & 0o777) == "0o600" and url in open(profile).read()
    finally:
        sepolia_deploy.shutil.rmtree(logs)


def check_cut_secret():
    """A stub `sncast` whose long stderr holds the URL, the key and the address across the 2000-character
    cut of the error message: redaction comes before the cut, so no fragment is left. Also the decimal and
    upper-case forms."""
    logs = tempfile.mkdtemp(prefix="smoke-cut-")
    try:
        url, address, key = FAKE["STARKNET_RPC_URL"], NOPREFIX["STARKNET_ACCOUNT_ADDRESS"], \
            NOPREFIX["STARKNET_PRIVATE_KEY"]
        values = {**FAKE, "STARKNET_ACCOUNT_ADDRESS": address, "STARKNET_PRIVATE_KEY": key}
        redact = sepolia_deploy.Redactor(values)
        node = sepolia_deploy.SepoliaNode(url, address, "unused", logs, {}, redact)
        secrets = [url, url.upper().replace("HTTPS", "https"), key, address, str(int(address, 16)),
                   str(int(key, 16))]
        for secret in secrets:
            for before in (3, len(secret) // 2, len(secret) - 3):  # characters of the secret before the cut
                stderr = "x" * 500 + secret + "y" * (2000 - len(secret) + before)  # the cut falls inside it
                tool = os.path.join(logs, "bin")
                os.makedirs(tool, exist_ok=True)
                fake = os.path.join(tool, "sncast")
                with open(fake, "w") as handle:
                    handle.write(f"#!/bin/sh\nprintf '%s' '{stderr}' >&2\nexit 1\n")
                os.chmod(fake, 0o755)
                old = os.environ["PATH"]
                os.environ["PATH"] = tool + os.pathsep + old
                try:
                    node.sncast("persistent", "--account", "deployer", "call")  # no transaction: no nonce read
                except RuntimeError as error:
                    message = str(error)
                else:
                    raise AssertionError("the stub sncast did not fail")
                finally:
                    os.environ["PATH"] = old
                for tail in (secret[-8:], secret[8:16]):  # a fragment of either end
                    assert tail not in message, (secret, message[-300:])
    finally:
        sepolia_deploy.shutil.rmtree(logs)


def check_chain_unit():
    """`check_chain` and `check_endpoint` on a stub, before any process: the chain id decides first."""
    class Log:
        def __init__(self):
            self.lines = []

        def say(self, text, error=False):
            self.lines.append(text)

        def die(self, text):
            self.lines.append(text)
            raise SystemExit(1)

    class Node(devnet_deploy.Node):
        check_url = staticmethod(lambda url: None)

        def __init__(self, chain, devnet):
            self.chain, self.devnet, self.url = chain, devnet, "http://127.0.0.1:1"

        def rpc(self, method, params):
            if method == "starknet_chainId":
                return "0x" + self.chain.encode().hex()
            if not self.devnet:
                raise RuntimeError("Method not found")
            return []

    for chain in ("SN_MAIN", "SN_GOERLI", "", "SN_SEPOLIA_X"):
        log = Log()
        try:
            sepolia_deploy.check_chain(Node(chain, True), True, log)
        except SystemExit:
            assert "nothing sent" in log.lines[-1], log.lines
        else:
            raise AssertionError(f"chain {chain!r} accepted")
    sepolia_deploy.check_chain(Node("SN_SEPOLIA", False), False, Log())  # Sepolia: not a devnet
    sepolia_deploy.check_chain(Node("SN_SEPOLIA", True), True, Log())  # the rehearsal: a devnet
    for rehearsal, devnet in ((False, True), (True, False)):
        try:
            sepolia_deploy.check_chain(Node("SN_SEPOLIA", devnet), rehearsal, Log())
        except SystemExit:
            pass
        else:
            raise AssertionError("a devnet passed as Sepolia, or a Sepolia node as a rehearsal")
    for url in ("http://localhost:5050", "http://127.0.0.1:5050", "https://10.0.0.1", "http://192.168.1.2:1",
                "http://[::1]:5050", "https://rpc.localhost/x"):
        assert sepolia_deploy.is_local(url), url
    for url in ("https://starknet-sepolia.public.blastapi.io/rpc/v0_8", "https://api.cartridge.gg/x"):
        assert not sepolia_deploy.is_local(url), url
        try:
            sepolia_deploy.check_endpoint(url, True, Log())
        except SystemExit:
            pass
        else:
            raise AssertionError("a remote URL passed with --devnet-rehearsal")
    try:
        sepolia_deploy.check_endpoint("http://127.0.0.1:5050", False, Log())
    except SystemExit:
        pass
    else:
        raise AssertionError("a local URL passed without --devnet-rehearsal")
    sepolia_deploy.check_endpoint("https://starknet-sepolia.public.blastapi.io/rpc/v0_8", False, Log())
    sepolia_deploy.check_endpoint("http://127.0.0.1:5050", True, Log())


class Scripted(http.server.BaseHTTPRequestHandler):
    """A JSON-RPC node driven by `Scripted.answer(method, params)`: ("http", 429), ("error", code, message)
    or ("result", value). Every request is counted in `Scripted.calls`."""

    answer, calls = None, []

    def do_POST(self):
        request = json.loads(self.rfile.read(int(self.headers["content-length"])))
        Scripted.calls.append(request["method"])
        kind, *rest = Scripted.answer(request["method"], request.get("params"))
        if kind == "http":
            self.send_response(rest[0])
            self.send_header("content-length", "0")
            self.end_headers()
            return
        answer = {"error": {"code": rest[0], "message": rest[1]}} if kind == "error" else {"result": rest[0]}
        body = json.dumps({"jsonrpc": "2.0", "id": 1, **answer}).encode()
        self.send_response(200)
        self.send_header("content-length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *args):
        pass


def check_run_node():
    """The node `run()` builds: its tag and pace, with the RPC and the artefact stubbed out, stopped before
    the first send (find_run raises)."""
    class Stop(Exception):
        pass

    class Log:
        def say(self, text, error=False):
            pass

        def die(self, text):
            raise AssertionError(text)

    built = []
    real = {name: getattr(sepolia_deploy, name) for name in
            ("check_endpoint", "check_chain", "read_sncast_version", "find_run", "SepoliaNode")}

    class Recording(real["SepoliaNode"]):
        def __init__(self, *args, **kwargs):
            super().__init__(*args, **kwargs)
            built.append(self)

    def stop(*args):
        raise Stop

    sepolia_deploy.check_endpoint = lambda *a: None
    sepolia_deploy.check_chain = lambda *a: "SN_SEPOLIA"
    sepolia_deploy.read_sncast_version = lambda *a: "sncast 0"
    sepolia_deploy.find_run = stop
    sepolia_deploy.SepoliaNode = Recording
    try:
        for extra, tag, pace in (([], "pre_confirmed", 1.0), (["--pace", "2.5"], "pre_confirmed", 2.5),
                                 (["--devnet-rehearsal", "--out", "/tmp/x.json", "--pace", "2.5"], "latest", 0.0)):
            args = sepolia_deploy.parse(["--commit", "0" * 40, *extra])
            try:
                sepolia_deploy.run(args, Log(), sepolia_deploy.Redactor(FAKE), {
                    **FAKE, "STARKNET_RPC_URL": "https://x.example/rpc"})
            except Stop:
                pass
            assert built[-1].tag == tag and built[-1].pace == pace, (extra, built[-1].tag, built[-1].pace)
    finally:
        for name, value in real.items():
            setattr(sepolia_deploy, name, value)


def check_rate_limit():
    """OPS-03 on a scripted node and a stub `sncast`: nothing here goes near Sepolia. The stub is in the
    PATH only while this runs: the later checks need the real `sncast`."""
    path = os.environ["PATH"]
    try:
        rate_limit_checks()
    finally:
        os.environ["PATH"] = path
        os.environ.pop("SMOKE_FAIL", None)


def rate_limit_checks():
    server = http.server.HTTPServer(("127.0.0.1", 0), Scripted)
    threading.Thread(target=server.serve_forever, daemon=True).start()
    url = f"http://127.0.0.1:{server.server_address[1]}"
    host = "rpc.sentinel-host-9c1d.example"
    limited = f"cu limit exceeded; Request too fast per second at {host}"
    redact = sepolia_deploy.Redactor({**FAKE, "STARKNET_RPC_URL": FAKE["STARKNET_RPC_URL"]})
    folder = tempfile.mkdtemp(prefix="smoke-ratelimit-")
    counter = os.path.join(folder, "count")
    errors = os.path.join(folder, "error")
    stub_tool(os.path.join(folder, "bin"), "sncast",
              f'n=$(cat "{counter}" 2>/dev/null || echo 0); n=$((n+1)); echo $n > "{counter}"\n'
              f'echo "$@" >> "{folder}/argv"\n'
              f'f="{errors}.$n"; [ -f "$f" ] || f="{errors}"\n'
              f'if [ "$n" -le "$SMOKE_FAIL" ]; then cat "$f" >&2; exit 1; fi\n'
              'echo "Transaction Hash: 0xabc1"\n')
    os.environ["PATH"] = os.path.join(folder, "bin") + os.pathsep + os.environ["PATH"]
    lines, sleeps = [], []

    def make(answer, pace=0.0):
        Scripted.answer, Scripted.calls = staticmethod(answer), []
        for path in (counter,):
            if os.path.exists(path):
                os.remove(path)
        logs = tempfile.mkdtemp(prefix="smoke-node-", dir=folder)
        lines.clear()
        sleeps.clear()
        return sepolia_deploy.SepoliaNode(url, "0x5e47a1d0c0ffee1234", "unused", logs, {}, redact,
                                          lines.append, pace=pace, backoff=1.0, sleep=sleeps.append)

    def sncast_count():
        return int(open(counter).read()) if os.path.exists(counter) else 0

    def invoke(node):
        return node.sncast("persistent", "--account", "deployer", "--wait", "invoke", "--url", url,
                           "--contract-address", "0x1", "--function", "f")

    def nothing_leaked():
        text = "\n".join(lines)
        for secret in (url, host, "sentinelapikey7788"):
            assert secret not in text, (secret, text)

    # a read that gets a 429, then a -32011, then succeeds, is retried; one line per retry, no URL
    seen = []

    def twice(method, params):
        seen.append(method)
        if len(seen) == 1:
            return ("http", 429)
        if len(seen) == 2:
            return ("error", -32011, limited)
        return ("result", "0x534e5f5345504f4c4941")
    node = make(twice)
    assert node.rpc("starknet_chainId", {}) == "0x534e5f5345504f4c4941" and len(seen) == 3
    assert sleeps == [1.0, 2.0], sleeps
    assert len(lines) == 2 and "HTTP 429" in lines[0] and "try 1 of 6" in lines[0] and "waiting 1 s" in lines[0], lines
    assert "JSON-RPC -32011" in lines[1] and "try 2 of 6" in lines[1], lines
    assert all(line.startswith("STARKNET_RPC_URL:") for line in lines), lines
    nothing_leaked()
    # a message alone ("Request too fast", "cu limit") is a rate limit too
    node = make(lambda m, p: ("error", -32000, "Request too fast") if len(Scripted.calls) < 2 else ("result", "0x1"))
    assert node.rpc("starknet_blockNumber", {}) == "0x1" and len(Scripted.calls) == 2
    # bounded: always limited, TRIES calls, then the error as before, with the host redacted
    node = make(lambda m, p: ("error", -32011, limited))
    try:
        node.rpc("starknet_chainId", {})
    except sepolia_deploy.dd.RpcError as error:
        assert host not in str(error) and "sentinel-host" not in str(error), error
    else:
        raise AssertionError("a read that is always limited did not fail")
    assert len(Scripted.calls) == sepolia_deploy.TRIES and len(sleeps) == sepolia_deploy.TRIES - 1, Scripted.calls
    assert sleeps == [1.0, 2.0, 4.0, 8.0, 16.0], sleeps
    assert max(sepolia_deploy.SepoliaNode.wait_time(node, k) for k in range(1, 30)) == sepolia_deploy.BACKOFF_CAP
    nothing_leaked()
    # any other answer is not retried
    node = make(lambda m, p: ("error", -32601, "Method not found"))
    try:
        node.rpc("devnet_getPredeployedAccounts", {})
    except sepolia_deploy.dd.RpcError:
        pass
    assert Scripted.calls == ["devnet_getPredeployedAccounts"] and not sleeps
    node = make(lambda m, p: ("http", 500))
    try:
        node.rpc("starknet_chainId", {})
    except Exception:
        pass
    assert len(Scripted.calls) == 1, "an HTTP 500 is not a rate limit"

    rate = ('Error: Failed to fetch chain_id\n\nCaused by:\n    JSON-RPC error: code=-32011, message="'
            + limited + '"\n')
    open(errors, "w").write(rate)
    nonces = {"value": 7}

    def chain(method, params):
        if method == "starknet_getNonce":
            assert params["block_id"] == "pre_confirmed", params  # RPC 0.9: the tag that moves when a transaction is accepted
            return ("result", hex(nonces["value"]))
        return ("error", -32601, "unexpected " + method)

    # sncast: a rate limit before submission (nonce unchanged) is resent, and succeeds
    os.environ["SMOKE_FAIL"] = "2"
    node = make(chain)
    out = invoke(node)
    assert "Transaction Hash: 0xabc1" in out and sncast_count() == 3 and node.sent == ["0xabc1"], (out, sncast_count())
    assert [l for l in lines if "nothing submitted" in l and "try " in l].__len__() == 2, lines
    nothing_leaked()
    # the tries are bounded
    os.environ["SMOKE_FAIL"] = "99"
    node = make(chain)
    try:
        invoke(node)
    except RuntimeError as error:
        assert host not in str(error), error
    else:
        raise AssertionError("an sncast that is always limited did not stop")
    assert sncast_count() == sepolia_deploy.TRIES and not node.sent, sncast_count()
    # an error that is no rate limit (after submission, unclassified) is never retried and the nonce is not even read after
    open(errors, "w").write("Error: Transaction timed out\n")
    os.environ["SMOKE_FAIL"] = "99"
    node = make(chain)
    try:
        invoke(node)
    except RuntimeError as error:
        assert "timed out" in str(error)
    else:
        raise AssertionError("an unclassified error did not stop")
    assert sncast_count() == 1 and Scripted.calls.count("starknet_getNonce") == 1, (sncast_count(), Scripted.calls)
    # a rate-limit text after which the nonce advanced is NOT resent: the node took the transaction
    open(errors, "w").write(rate)
    os.environ["SMOKE_FAIL"] = "99"
    reads = []

    def accepted(method, params):
        if method == "starknet_getNonce":
            reads.append(1)
            return ("result", hex(7 if len(reads) == 1 else 8))
        if method == "starknet_blockNumber":
            return ("result", 100)
        if method == "starknet_getBlockWithTxs":
            return ("result", {"transactions": [
                {"type": "INVOKE", "sender_address": "0x5e47a1d0c0ffee1234", "nonce": "0x7",
                 "transaction_hash": "0xfeed"}]})
        if method == "starknet_getTransactionReceipt":
            return ("result", {"execution_status": "SUCCEEDED", "finality_status": "ACCEPTED_ON_L2", "events": []})
        return ("error", -32601, method)
    node = make(accepted)
    out = invoke(node)
    assert sncast_count() == 1, "an accepted transaction was sent again"
    assert "Transaction Hash: 0xfeed" in out and node.sent == ["0xfeed"], (out, node.sent)
    nothing_leaked()
    # nonce advanced and the transaction cannot be found: stop, naming the call, nothing resent
    reads.clear()
    node = make(lambda m, p: accepted(m, p) if m in ("starknet_getNonce", "starknet_blockNumber")
                else ("result", {"transactions": []}))
    try:
        invoke(node)
    except RuntimeError as error:
        assert "invoke" in str(error) and "accepted" in str(error), error
    else:
        raise AssertionError("a lost transaction did not stop the run")
    assert sncast_count() == 1
    # the same, for a declare-from: the class hash comes from the DECLARE transaction
    reads.clear()

    def declared(method, params):
        if method == "starknet_getBlockWithTxs":
            return ("result", {"transactions": [
                {"type": "DECLARE", "sender_address": "0x5e47a1d0c0ffee1234", "nonce": "0x7",
                 "transaction_hash": "0xdec1", "class_hash": "0xc1a55"}]})
        return accepted(method, params)
    node = make(declared)
    out = node.sncast("persistent", "--account", "deployer", "--wait", "declare-from", "--url", url,
                      "--sierra-file", "x")
    assert "Class Hash: 0xc1a55" in out and "Transaction Hash: 0xdec1" in out and sncast_count() == 1, out
    # a deploy: the address is the ContractDeployed event's (data: address, deployer, unique, class hash)
    reads.clear()
    selector = hex(sepolia_deploy.dd.storage_key("ContractDeployed"))

    def deployed(method, params):
        if method == "starknet_getTransactionReceipt":
            other = {"keys": [selector], "data": ["0xbad", "0x1", "0x0", "0x999"]}
            mine = {"keys": [selector], "data": ["0xadd7e55", "0x5e47a1d0c0ffee1234", "0x0", "0xc1a55"]}
            return ("result", {"execution_status": "SUCCEEDED", "finality_status": "ACCEPTED_ON_L2",
                               "events": [{"keys": ["0x1"], "data": []}, other, mine]})
        return accepted(method, params)
    node = make(deployed)
    out = node.sncast("persistent", "--account", "deployer", "--wait", "deploy", "--url", url,
                      "--class-hash", "0xc1a55")
    assert "Contract Address: 0xadd7e55" in out and sncast_count() == 1, out
    # the race: the node takes the first copy only after our "after" read. The first call and the resend
    # carry the same reference nonce, so the node refuses the resend; we then see nonce + 1 and take the
    # first copy: no second copy is ever accepted
    open(errors + ".2", "w").write("Error: Invalid transaction nonce\n")
    os.remove(folder + "/argv")
    reads.clear()
    os.environ["SMOKE_FAIL"] = "99"

    def race(method, params):
        if method == "starknet_getNonce":
            reads.append(1)
            return ("result", hex(8 if len(reads) >= 3 else 7))  # reference 7, after 7, then taken: 8
        return accepted(method, params)
    node = make(race)
    out = invoke(node)
    argv = open(folder + "/argv").read().splitlines()
    assert len(argv) == 2 and all(" --nonce 0x7" in line + " " for line in argv), argv  # the reference, twice
    assert "Transaction Hash: 0xfeed" in out and node.sent == ["0xfeed"], (out, node.sent)
    os.remove(errors + ".2")
    # the last try fails after acceptance: the nonce is still checked and the transaction recovered
    reads.clear()
    os.environ["SMOKE_FAIL"] = "99"

    def last(method, params):
        if method == "starknet_getNonce":
            reads.append(1)
            # reference 7; every "after" read says 7 until the sixth one
            return ("result", hex(8 if len(reads) > sepolia_deploy.TRIES else 7))
        return accepted(method, params)
    node = make(last)
    out = invoke(node)
    assert sncast_count() == sepolia_deploy.TRIES and "Transaction Hash: 0xfeed" in out, (sncast_count(), out)
    # ...and when nothing was accepted by then, the run stops naming the call
    node = make(chain)
    try:
        invoke(node)
    except RuntimeError as error:
        assert "invoke" in str(error) and "tries are spent" in str(error), error
    else:
        raise AssertionError("the spent tries did not stop the run")
    # a nonce that cannot be read stops the run (rate limited to the end)
    state = []

    def unreadable(method, params):
        state.append(method)
        return ("result", "0x7") if len(state) == 1 else ("error", -32011, limited)
    node = make(unreadable)
    try:
        invoke(node)
    except RuntimeError as error:
        assert "nonce could not be read" in str(error), error
    else:
        raise AssertionError("an unreadable nonce did not stop the run")
    assert sncast_count() == 1
    # pace: a wait between two transactions, none before the first
    os.environ["SMOKE_FAIL"] = "0"
    node = make(chain, pace=2.5)
    invoke(node)
    assert 2.5 not in sleeps, sleeps
    invoke(node)
    assert sleeps == [2.5], sleeps
    # the rehearsal and the defaults
    assert sepolia_deploy.parse(["--commit", "x"]).pace == sepolia_deploy.PACE == 1.0
    server.shutdown()
    print("sepolia_deploy_smoke: rate limit ok: reads retried, sncast resent only when the nonce did not move")


def nonce(node):
    return int(node.rpc("starknet_getNonce", {"block_id": "latest", "contract_address": node.address}), 16)


def check_refusals(real, node, good_run):
    """Every refusal sends nothing: the node's nonce is read before and after, a stub records its calls."""
    pr = pull_request_run()
    before = nonce(node)
    run = Run(real, "--artifact-run", str(pr), "--devnet-rehearsal", "--out", "/dev/null")
    run.refused("not a push to main")
    # the conclusion guard, on a stub `gh` (a push run of main that failed), whatever the history holds
    tools = tempfile.mkdtemp(prefix="smoke-tools-")
    stub_tool(tools, "gh", """case "$*" in
  *"run view"*) printf '{"event":"push","headBranch":"main","headSha":"%s","url":"https://github.com/bal7hazar/grimworld/actions/runs/1","workflowName":"ci","conclusion":"failure"}' 0123456789012345678901234567890123456789;;
  *) exit 1;;
esac
""")
    Run(real, "--artifact-run", "1", "--devnet-rehearsal", "--out", "/dev/null", path=tools).refused("not 'success'")
    # a `sncast --version` that fails or is empty stops the run before anything is sent
    stub_tool(tools, "sncast", "exit 0\n")
    Run(real, "--artifact-run", str(good_run), "--devnet-rehearsal", "--out", "/dev/null", path=tools).refused(
        "sncast --version failed or empty")
    stub_tool(tools, "sncast", "echo broken >&2; exit 3\n")
    Run(real, "--artifact-run", str(good_run), "--devnet-rehearsal", "--out", "/dev/null", path=tools).refused(
        "sncast --version failed or empty")
    sepolia_deploy.shutil.rmtree(tools)
    for option in ("--give-build", "--credit-only", "--build=full", "--deployment=x", "--account=1",
                   "--key-env=X", "--adventurer=1", "--salt=1"):
        run = Run(real, "--artifact-run", str(good_run), "--devnet-rehearsal", "--out", "/dev/null", option)
        run.refused("refused")
    # a local URL without --devnet-rehearsal; the sentinel variables, a path in the URL
    local = {**FAKE, "STARKNET_RPC_URL": "http://127.0.0.1:9/sentinelapikey7788"}
    Run(local, "--artifact-run", str(good_run), "--dry-run").refused("local URL")
    Run(real, "--artifact-run", str(good_run), "--dry-run").refused("local URL")
    # a remote URL with --devnet-rehearsal
    Run(FAKE, "--artifact-run", str(good_run), "--devnet-rehearsal", "--out", "/dev/null").refused(
        "local node only")
    # --devnet-rehearsal needs --out
    Run(real, "--artifact-run", str(good_run), "--devnet-rehearsal").refused("needs --out")
    # a variable missing: its name only
    partial = {k: v for k, v in real.items() if k != "STARKNET_PRIVATE_KEY"}
    Run(partial, "--artifact-run", str(good_run), "--devnet-rehearsal", "--out", "/dev/null").refused(
        "STARKNET_PRIVATE_KEY: not set")
    # a chain id that is not SN_SEPOLIA, on a stub: one call, the chain id, nothing else
    server, url = start_stub("SN_MAIN")
    try:
        stubbed = {**FAKE, "STARKNET_RPC_URL": url}
        Run(stubbed, "--artifact-run", str(good_run), "--devnet-rehearsal", "--out", "/dev/null").refused(
            "chain id 'SN_MAIN', not 'SN_SEPOLIA': nothing sent")
        assert Stub.methods == ["starknet_chainId"], Stub.methods
    finally:
        server.shutdown()
    # a stub whose errors echo all four values: the error path is redacted
    server, url = start_stub("SN_SEPOLIA")
    try:
        stubbed = {**FAKE, "STARKNET_RPC_URL": url}
        Stub.echo = " ".join(stubbed.values()) + f" {url.split('//')[1]}"
        run = Run(stubbed, "--artifact-run", str(good_run), "--devnet-rehearsal", "--out", "/dev/null")
        run.refused("is not a starknet-devnet")
        assert "<STARKNET_RPC_URL>" in run.stderr and "<STARKNET_PRIVATE_KEY>" in run.stderr, run.stderr
        assert set(Stub.methods) <= {"starknet_chainId", "devnet_getPredeployedAccounts"}, Stub.methods
    finally:
        server.shutdown()
    # the same, with an address and a key given without 0x (a leading zero)
    server, url = start_stub("SN_SEPOLIA")
    try:
        stubbed = {**NOPREFIX, "STARKNET_RPC_URL": url}
        Stub.echo = " ".join(stubbed.values()) + " 0x" + stubbed["STARKNET_ACCOUNT_ADDRESS"].lstrip("0")
        run = Run(stubbed, "--artifact-run", str(good_run), "--devnet-rehearsal", "--out", "/dev/null")
        run.refused("is not a starknet-devnet")
    finally:
        server.shutdown()
    # a rehearsal's --out is never under deployments/sepolia
    Run(real, "--artifact-run", str(good_run), "--devnet-rehearsal", "--out",
        os.path.join(ROOT, "deployments", "sepolia", "x.json")).refused("under deployments/sepolia")
    assert nonce(node) == before, "a refusal sent a transaction"


def check_sigterm(good_run):
    """SIGTERM ends the run through the `finally`: the temporary folder (URL, key) is removed."""
    import signal
    import time

    class Slow(Stub):
        def do_POST(self):
            time.sleep(20)

    server = http.server.HTTPServer(("127.0.0.1", 0), Slow)
    threading.Thread(target=server.serve_forever, daemon=True).start()
    logs = tempfile.mkdtemp(prefix="smoke-logs-")
    env = {k: v for k, v in os.environ.items() if not k.startswith(("STARKNET_", "NODE_"))}
    env.update({**NOPREFIX, "STARKNET_RPC_URL": f"http://127.0.0.1:{server.server_address[1]}",
                "WITH_NODE_LOG_DIR": logs})
    before = {n for n in leftovers() if n.startswith("sepolia-deploy-")}
    process = subprocess.Popen([sys.executable, SCRIPT, "--artifact-run", str(good_run), "--dry-run",
                                "--devnet-rehearsal", "--out", "/dev/null"], cwd=ROOT, env=env,
                               stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    for _ in range(100):  # the temporary folder exists once the script is waiting for the node
        if {n for n in leftovers() if n.startswith("sepolia-deploy-")} - before:
            break
        time.sleep(0.1)
    else:
        raise AssertionError("the script never created its temporary folder")
    process.send_signal(signal.SIGTERM)
    out, err = process.communicate(timeout=15)
    server.shutdown()
    assert process.returncode == 128 + signal.SIGTERM, (process.returncode, err)
    assert {n for n in leftovers() if n.startswith("sepolia-deploy-")} == before, "the temporary folder stayed"


def check_rehearsal(real, node, run_id, logs):
    """The deployment, the record and the chain."""
    before = nonce(node)
    dry = Run(real, "--artifact-run", str(run_id), "--dry-run", "--devnet-rehearsal", "--out", "/dev/null")
    assert dry.code == 0 and "--dry-run: nothing sent" in dry.stdout and "plan: declare" in dry.stdout, dry.stderr
    assert nonce(node) == before, "--dry-run sent a transaction"

    record_path = os.path.join(logs, "rehearsal-record.json")
    run = Run(real, "--artifact-run", str(run_id), "--devnet-rehearsal", "--out", record_path)
    assert run.code == 0, run.stderr
    text = open(record_path).read()
    run.no_leak(text)
    record = json.loads(text)
    assert not os.path.exists(os.path.join(ROOT, "deployments", "sepolia", os.path.basename(record_path)))
    assert record["rehearsal"] is True and record["chain_id"] == "SN_SEPOLIA", record
    assert re.fullmatch(r"[0-9a-f]{40}", record["commit"]), record["commit"]
    assert record["artefact"]["name"] == f"contract-classes-{record['commit']}", record["artefact"]
    assert record["artefact"]["run"].endswith(f"/actions/runs/{run_id}"), record["artefact"]
    assert record["build_root"]["commit"] == record["commit"] and record["build_root"]["root"], record
    assert set(record) == {"network", "rehearsal", "chain_id", "commit", "artefact", "build_root", "classes",
                           "contracts", "seed", "tools", "transactions", "total_fee"}, sorted(record)
    assert not any(key in text.lower() for key in ("private", "rpc_url", "127.0.0.1")), "a secret-like key"

    classes, contracts = record["classes"], record["contracts"]
    assert len(classes) == 16 and list(classes)[-1] == "goblins_library", list(classes)
    # the declared class of each contract is the record's class hash
    on_chain = {name: int(node.rpc("starknet_getClassHashAt", {"block_id": "latest",
                                                               "contract_address": contracts[name]}), 16)
                for name in contracts}
    assert on_chain == {"registry": int(classes["registry"], 16), "tx_hash_fate": int(classes["tx_hash_fate"], 16),
                        "hub": int(classes["hub"], 16), "instances": int(classes["instances"], 16)}, on_chain
    for name, class_hash in classes.items():  # every class is declared on the node
        node.rpc("starknet_getClass", {"block_id": "latest", "class_hash": class_hash})
    # the transaction count is the account's nonce, and the fee is positive
    assert record["tools"]["sncast"].startswith("sncast"), record["tools"]
    assert record["transactions"] == nonce(node) - before and record["transactions"] > 50, record["transactions"]
    assert record["total_fee"]["unit"] in ("FRI", "WEI") and int(record["total_fee"]["amount"]) > 0
    # one view per contract
    ids = record["seed"]["ids"]
    assert record["seed"]["records"] == sum(len(v) for v in ids.values()), record["seed"]
    registry = node.view("persistent", contracts["registry"], "last_id", devnet_deploy.REGION)
    assert registry == [max(ids["region"])], registry
    skills = node.view("persistent", contracts["registry"], "last_id", 9)
    assert skills == [max(ids["skill"])], skills
    assert node.view("persistent", contracts["hub"], "account_of", int(node.address, 16)) == [0]  # no one yet
    assert node.view("ephemeral", contracts["instances"], "placement", 1) == [0, 0, 0]  # no adventurer
    # a second rehearsal on the same node declares nothing again: every class is "already declared"
    second_path = os.path.join(logs, "rehearsal-record-2.json")
    again = Run(real, "--artifact-run", str(run_id), "--devnet-rehearsal", "--out", second_path)
    assert again.code == 0, again.stderr
    second = json.load(open(second_path))
    assert second["classes"] == classes, "the class hashes changed"
    assert again.stdout.count("already declared") == 16 and "declared class" not in again.stdout.replace(
        "already declared, class", ""), again.stdout
    assert second["transactions"] == record["transactions"] - 16, (second["transactions"], record["transactions"])
    assert second["contracts"] != contracts, "a second deployment has other addresses"
    assert "transaction 0x" in run.stdout and "declared class" in run.stdout and "deployed class" in run.stdout
    # the order: Registry's records were accepted (set_zone_checks was first), key 6 is GoblinsLibrary
    assert classes["goblins_library"] == list(classes.values())[-1]
    return record


def main():
    check_redactor()
    check_overlap()
    check_command_line()
    check_cut_secret()
    check_chain_unit()
    check_run_node()
    check_rate_limit()
    url, address, key = (os.environ["NODE_URL"], os.environ["NODE_ACCOUNT_ADDRESS"],
                         os.environ["NODE_ACCOUNT_PRIVATE_KEY"])
    real = {"STARKNET_NETWORK": FAKE["STARKNET_NETWORK"], "STARKNET_RPC_URL": url,
            "STARKNET_ACCOUNT_ADDRESS": address, "STARKNET_PRIVATE_KEY": key}
    logs = tempfile.mkdtemp(prefix="smoke-record-")
    node = devnet_deploy.Node(url, address, "unused", logs, name="smoke")
    run_id = main_run()
    print(f"sepolia_deploy_smoke: artefact of run {run_id}")
    check_refusals(real, node, run_id)
    check_sigterm(run_id)
    print("sepolia_deploy_smoke: refusals ok, nothing sent, no value leaked")
    record = check_rehearsal(real, node, run_id, logs)
    print(f"sepolia_deploy_smoke: rehearsal ok: {record['transactions']} transactions, fee "
          f"{record['total_fee']['amount']} {record['total_fee']['unit']}")
    print(json.dumps({k: v for k, v in record.items() if k != "seed"}, indent=2))


if __name__ == "__main__":
    main()
