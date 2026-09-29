#!/usr/bin/env python3
"""Option (b) in headless Firefox: serves spikes/SPK-4 on 127.0.0.1, opens vm/js/browser/index.html
in a Firefox of its own (a fresh profile under spikes/SPK-4/out), waits for the worker's result,
then stops that Firefox by the pid it started. Everything lives and ends inside this command.

  python3 spikes/SPK-4/vm/browser_bench.py [--timeout 900]
"""

import argparse
import http.server
import json
import os
import shutil
import subprocess
import tempfile
import threading
import time

HERE = os.path.dirname(os.path.abspath(__file__))
SPIKE = os.path.dirname(HERE)
OUT = os.path.join(SPIKE, "out")
result = {}
done = threading.Event()


class Handler(http.server.SimpleHTTPRequestHandler):
    extensions_map = {
        **http.server.SimpleHTTPRequestHandler.extensions_map,
        ".mjs": "text/javascript",
        ".js": "text/javascript",
        ".wasm": "application/wasm",
        ".json": "application/json",
        ".jsonl": "text/plain",
    }

    def __init__(self, *a, **k):
        super().__init__(*a, directory=SPIKE, **k)

    def do_POST(self):
        body = self.rfile.read(int(self.headers["Content-Length"]))
        result.update(json.loads(body))
        self.send_response(204)
        self.end_headers()
        done.set()

    def log_message(self, *a):
        pass


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--timeout", type=int, default=900)
    a = ap.parse_args()
    os.makedirs(OUT, exist_ok=True)
    server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Handler)
    threading.Thread(target=server.serve_forever, daemon=True).start()
    port = server.server_address[1]
    profile = tempfile.mkdtemp(prefix="firefox-profile-", dir=OUT)
    version = subprocess.run(["firefox", "--version"], capture_output=True, text=True).stdout.strip()
    url = f"http://127.0.0.1:{port}/vm/js/browser/index.html"
    t0 = time.time()
    ff = subprocess.Popen(
        ["firefox", "--headless", "--no-remote", "--profile", profile, url],
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
    )
    peak_rss = 0
    try:
        while not done.wait(1.0):
            peak_rss = max(peak_rss, tree_rss(ff.pid))
            if time.time() - t0 > a.timeout:
                result["error"] = f"no result after {a.timeout} s"
                break
    finally:
        ff.terminate()
        try:
            ff.wait(10)
        except subprocess.TimeoutExpired:
            ff.kill()
            ff.wait()
        server.shutdown()
        shutil.rmtree(profile, ignore_errors=True)
    result["firefox"] = version
    result["firefox_tree_peak_rss_mb"] = round(peak_rss / 1024, 1)
    result["wall_s"] = round(time.time() - t0, 1)
    print(json.dumps(result, indent=1))


def tree_rss(root):
    """Resident memory of `root` and its descendants, in KiB, from /proc."""
    children = {}
    for pid in os.listdir("/proc"):
        if not pid.isdigit():
            continue
        try:
            with open(f"/proc/{pid}/stat", encoding="utf-8") as f:
                ppid = int(f.read().rsplit(")", 1)[1].split()[1])
            children.setdefault(ppid, []).append(int(pid))
        except (OSError, ValueError, IndexError):
            pass
    total, stack = 0, [root]
    while stack:
        pid = stack.pop()
        stack.extend(children.get(pid, []))
        try:
            with open(f"/proc/{pid}/status", encoding="utf-8") as f:
                for line in f:
                    if line.startswith("VmRSS:"):
                        total += int(line.split()[1])
        except OSError:
            pass
    return total


if __name__ == "__main__":
    main()
