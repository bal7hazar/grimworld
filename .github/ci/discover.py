#!/usr/bin/env python3
"""Discovery step of .github/workflows/ci.yml: which Cairo jobs to run, with which toolchain.

Everything read here comes from the checked-out pull request, so it is untrusted until this script
has validated it. It runs before any setup step and fails the workflow on anything unexpected:

- Every tracked Scarb.toml is either a job root or a member of a Scarb workspace that is a job
  root. A workspace (contracts/) is one job at its root; its `members` (globs included) are read
  and expanded. A tracked manifest below a workspace root that is not one of its members fails the
  discovery, it is never skipped silently. A workspace with `exclude` is refused (not supported
  here, so it cannot hide a manifest).
- The toolchain of a job is, per tool, the nearest .tool-versions going up from its folder (asdf
  semantics); a workspace member cannot pin another toolchain than its workspace root's (it would
  be ignored), so that fails. Every version that reaches a setup step (Scarb, snforge, Node, pnpm) is an exact
  release number: `latest`, `nightly`, ranges and paths are refused.
- package.json `devEngines.packageManager`, which pnpm/action-setup would let override the pinned
  pnpm (ranges accepted), is refused unless it is exactly pnpm at the validated version.
- Job folders are repository-relative paths made of safe characters, without `..`.

Outputs (GITHUB_OUTPUT, else stdout): packages (JSON list of {dir, scarb, snforge}), node, pnpm.
"""

import glob
import json
import os
import re
import subprocess
import sys
import tomllib

VERSION = re.compile(r"^[0-9]+\.[0-9]+\.[0-9]+$")
SAFE_PATH = re.compile(r"^(\.|[A-Za-z0-9._-]+(/[A-Za-z0-9._-]+)*)$")

errors = []


def fail(message):
    errors.append(message)


def safe_dir(path):
    return bool(SAFE_PATH.match(path)) and ".." not in path.split("/")


def tool_pin(folder, tool):
    """(version, file) of `tool` in the nearest .tool-versions from `folder` up to the root."""
    folder = os.path.normpath(folder)
    while True:
        path = os.path.join(folder, ".tool-versions")
        if os.path.isfile(path):
            with open(path, encoding="utf-8") as f:
                for line in f:
                    fields = line.split("#", 1)[0].split()
                    if len(fields) >= 2 and fields[0] == tool:
                        return fields[1], path
        if folder == ".":
            return None, None
        folder = os.path.dirname(folder) or "."


def tool_version(folder, tool):
    return tool_pin(folder, tool)[0]


def exact_version(folder, tool):
    version = tool_version(folder, tool)
    if version is None:
        fail(f"{folder}: no {tool} in any .tool-versions")
    elif not VERSION.match(version):
        fail(f"{folder}: {tool} {version!r} is not an exact release number (x.y.z)")
    return version


tracked = subprocess.check_output(["git", "ls-files", "-z"], text=True).split("\0")
manifests = sorted(p for p in tracked if p == "Scarb.toml" or p.endswith("/Scarb.toml"))
manifest_dirs = {os.path.dirname(p) or "." for p in manifests}

# Workspaces: root folder -> member folders (globs expanded on the checked-out tree).
members_of = {}
member_root = {}
for dir_ in sorted(manifest_dirs):
    with open(os.path.join(dir_, "Scarb.toml"), "rb") as f:
        try:
            workspace = tomllib.load(f).get("workspace")
        except tomllib.TOMLDecodeError as e:
            fail(f"{dir_}/Scarb.toml: {e}")
            continue
    if workspace is None:
        continue
    patterns = workspace.get("members")
    if "exclude" in workspace:
        fail(f"{dir_}/Scarb.toml: [workspace] exclude is not supported by the CI discovery")
    if not isinstance(patterns, list) or not all(isinstance(p, str) for p in patterns):
        fail(f"{dir_}/Scarb.toml: [workspace] members must be a list of strings")
        continue
    members = set()
    for pattern in patterns:
        if os.path.isabs(pattern) or ".." in pattern.split("/"):
            fail(f"{dir_}/Scarb.toml: member {pattern!r} leaves the workspace folder")
            continue
        hits = [os.path.normpath(h) for h in glob.glob(os.path.join(dir_, pattern)) if os.path.isdir(h)]
        if not hits:
            fail(f"{dir_}/Scarb.toml: member {pattern!r} matches no folder")
        for hit in hits:
            if hit not in manifest_dirs:
                fail(f"{dir_}/Scarb.toml: member {hit} has no tracked Scarb.toml")
            elif hit in member_root:
                fail(f"{hit} is a member of two workspaces ({member_root[hit]} and {dir_})")
            else:
                members.add(hit)
                member_root[hit] = dir_
    members_of[dir_] = members

roots = sorted(d for d in manifest_dirs if d not in member_root)
for member in sorted(member_root):
    if member in members_of:
        fail(f"{member} is a workspace and also a member of {member_root[member]}")
for root, members in members_of.items():
    if root in member_root:
        continue
    for dir_ in sorted(manifest_dirs):
        below = dir_ != root and (root == "." or dir_.startswith(root + "/"))
        if below and dir_ not in members:
            fail(f"{dir_}/Scarb.toml is below the workspace {root} but is not one of its members")

packages = []
for root in roots:
    if not safe_dir(root):
        fail(f"{root!r} is not a plain repository-relative folder")
        continue
    packages.append(
        {
            "dir": root,
            "scarb": exact_version(root, "scarb"),
            "snforge": exact_version(root, "starknet-foundry"),
        }
    )
if not packages:
    fail("no Cairo package found")

# A workspace is one job on its root's toolchain: a member cannot pin another one, that pin would be
# silently ignored. (A package that needs another toolchain lives outside the workspace.)
for member, root in sorted(member_root.items()):
    for tool in ("scarb", "starknet-foundry"):
        (own, own_file), (job, _) = tool_pin(member, tool), tool_pin(root, tool)
        if own != job:
            fail(
                f"{own_file}: {tool} {own} differs from the workspace {root} ({job}); a workspace is "
                "one job on its root's toolchain, so a member's own pin is ignored: remove it, or "
                "move the package out of the workspace"
            )

node = exact_version(".", "nodejs")
pnpm = exact_version(".", "pnpm")
try:
    with open("package.json", encoding="utf-8") as f:
        package_json = json.load(f)
except (OSError, ValueError) as e:
    package_json = {}
    fail(f"package.json: {e}")
package_manager = package_json.get("packageManager")
if package_manager != f"pnpm@{pnpm}":
    fail(f"package.json packageManager {package_manager!r} is not 'pnpm@{pnpm}' (.tool-versions)")

# pnpm/action-setup lets devEngines.packageManager (ranges accepted) override `packageManager`;
# the workflow passes the validated version explicitly, and a field that says otherwise is refused.
dev_engines = (package_json.get("devEngines") or {}).get("packageManager")
if dev_engines is not None:
    for entry in dev_engines if isinstance(dev_engines, list) else [dev_engines]:
        if not (isinstance(entry, dict) and entry.get("name") == "pnpm" and entry.get("version") == pnpm):
            fail(f"package.json devEngines.packageManager {entry!r} is not exactly pnpm {pnpm} (.tool-versions)")

if errors:
    for message in errors:
        print(f"::error::{message}", file=sys.stderr)
    sys.exit(1)

print(json.dumps(packages, indent=2))
print(f"node {node}, pnpm {pnpm}")
outputs = {"packages": json.dumps(packages, separators=(",", ":")), "node": node, "pnpm": pnpm}
target = os.environ.get("GITHUB_OUTPUT")
if target:
    with open(target, "a", encoding="utf-8") as f:
        for key, value in outputs.items():
            f.write(f"{key}={value}\n")
