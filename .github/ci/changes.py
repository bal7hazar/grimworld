#!/usr/bin/env python3
"""Which jobs of CI a change concerns (FND-18, docs/briefs/FND-18-ci-paths.md).

Run by the first job of .github/workflows/ci.yml (`discover`) and by the first step of the `tooling`
job of .github/workflows/tooling.yml. It lists the files that differ from the base and sets the
outputs that each test job's `if:` reads:

  ci:      cairo (JSON list of the discovered packages to run, [] when none), classes, client, indexer
  tooling: tooling

Every changed path is classified, never guessed: the paths a job depends on are the tables below; a
document runs nothing; a path that no table claims is unclassified and runs every job (the fail-safe
direction), and the log says which. A change to a workflow or to a CI helper (.github/) runs everything.
A pull request is compared with its base; an unknown or malformed base, or a base that cannot be
fetched, runs everything. A push to main keeps what it ran before FND-18: every job but `indexer-node`,
which keeps its diff against the commit before the push.

The base and the packages reach this script as environment variables (EVENT, PR_BASE, PUSH_BEFORE,
PACKAGES), never interpolated into a command. Outputs go to GITHUB_OUTPUT, else to stdout.

  changes.py [--workflow ci|tooling]    (default ci)
  changes.py --self-test
"""

import fnmatch
import json
import os
import posixpath
import re
import subprocess
import sys
import tomllib

# --- the tables: which paths concern which job ---------------------------------------------------

# Files at the root that the pnpm workspace's jobs read (install, lint, typecheck, test, prettier).
CLIENT_ROOT_FILES = (
    "package.json",
    "pnpm-lock.yaml",
    "pnpm-workspace.yaml",
    ".gitignore",  # prettier reads it
    ".npmrc",
    ".prettierrc*",
    ".prettierignore",
    "eslint.config.*",
    "tsconfig*.json",
)
# Folders of the pnpm workspace (client/*, services/*, indexer) and the files outside it that its tests
# read: the sim's parity tests read the vector tables and the seed region, a client test reads the art
# manifest.
CLIENT_PREFIXES = ("client/", "services/", "indexer/", "contracts/logic/vectors/", "contracts/seed/")
CLIENT_FILES = ("tools/art/manifest.toml",)

# The `contracts` package also reads these (gas budgets, GAS.md, class sizes, exp2 table, vectors).
CONTRACTS_FILES = ("scripts/gas_budgets.py", "docs/BUDGETS.md")
# What the class-artefacts job builds: only these files of contracts/ can change the bytes.
CLASS_INPUT = re.compile(r"(\.cairo|(^|/)Scarb\.toml|(^|/)Scarb\.lock|(^|/)\.tool-versions)$")

# The tooling job's checks (shellcheck, launcher dry-run, lock.sh, with-node.sh, the self-tests): the
# scripts, and the one brief the launcher dry-run reads for its Sepolia grant.
TOOLING_PREFIXES = ("scripts/",)
TOOLING_FILES = ("docs/briefs/SPK-1-*",)

# Paths that no test of CI reads. A markdown file is a document unless a job above claims it
# (docs/BUDGETS.md, contracts/**/GAS.md, the SPK-1 brief).
IGNORED_PREFIXES = ("docs/", "tools/", "spikes/", ".githooks/", "assets")
IGNORED_FILES = ("*.md", "LICENSE", ".gitmodules")

ALL = "all"  # a tag: everything runs


def matches(path, patterns):
    return any(fnmatch.fnmatchcase(path, p) for p in patterns)


# --- the package closure: the folders whose change concerns a Cairo job ----------------------------


def path_deps(manifest):
    """The `path` of every dependency table of a parsed Scarb.toml."""
    tables = [manifest.get("dependencies", {}), manifest.get("dev-dependencies", {})]
    tables.append(manifest.get("workspace", {}).get("dependencies", {}))
    for target in manifest.get("target", {}).values():
        if isinstance(target, dict):
            tables.append(target.get("dependencies", {}))
    for table in tables:
        for spec in table.values():
            if isinstance(spec, dict) and isinstance(spec.get("path"), str):
                yield spec["path"]


def closure(root, manifests):
    """The folders a job rooted at `root` compiles: itself, and (transitively) the folder of every path
    dependency of a manifest at or below one of them. `manifests` maps a folder to its parsed Scarb.toml."""
    folders = {root}
    todo = [root]
    while todo:
        folder = todo.pop()
        for dir_, manifest in manifests.items():
            if dir_ != folder and not dir_.startswith(folder + "/"):
                continue
            for dep in path_deps(manifest):
                target = posixpath.normpath(posixpath.join(dir_, dep))
                if not any(target == f or target.startswith(f + "/") for f in folders):
                    folders.add(target)
                    todo.append(target)
    return folders


def under(path, folder):
    return path == folder or path.startswith(folder + "/")


# --- the classification ----------------------------------------------------------------------------


def classify(path, packages, closures, pins):
    """The set of tags a changed path carries: ALL, 'classes', 'client', 'indexer', 'tooling' and
    'pkg:<dir>'. An empty set is a path that runs nothing; None is unclassified (runs everything)."""
    if path.startswith(".github/"):
        return {ALL}
    tags = set()
    is_markdown = path.endswith(".md")
    gas_doc = path == "docs/BUDGETS.md" or (path.startswith("contracts/") and path.endswith("/GAS.md"))
    if matches(path, TOOLING_FILES) or (not is_markdown and path.startswith(TOOLING_PREFIXES)):
        tags.add("tooling")
    if matches(path, CONTRACTS_FILES) or gas_doc:
        tags.add("pkg:contracts")
    if path == ".tool-versions":
        # every package whose Scarb or snforge pin is the root's, the pnpm jobs, the tooling checks
        tags |= {f"pkg:{p['dir']}" for p in packages if pins.get(p["dir"], True)}
        tags |= {"classes", "client", "tooling"}
    if not is_markdown:
        for package in packages:
            root = package["dir"]
            if any(under(path, folder) for folder in closures[root]):
                tags.add(f"pkg:{root}")
        if under(path, "contracts") and CLASS_INPUT.search(path):
            tags.add("classes")
    if not is_markdown:
        if path.startswith(CLIENT_PREFIXES) or path in CLIENT_FILES or matches(path, CLIENT_ROOT_FILES):
            tags.add("client")
        if path.startswith("indexer/"):
            tags.add("indexer")
    if tags:
        return tags
    if path.startswith(IGNORED_PREFIXES) or matches(path, IGNORED_FILES):
        return set()
    return None


def decide(files, packages, closures, pins, workflow, event, base_known):
    """(outputs, notes): the outputs of the workflow for the changed files."""
    notes = []
    tags = set()
    if not base_known:
        tags.add(ALL)
        notes.append("base unknown: every job runs")
    for path in files:
        found = classify(path, packages, closures, pins)
        if found is None:
            notes.append(f"unclassified, every job runs: {path}")
            tags.add(ALL)
        else:
            tags |= found
    everything = ALL in tags
    if workflow == "tooling":
        run = event == "push" or everything or "tooling" in tags
        return {"tooling": str(run).lower()}, notes
    if event == "push":
        # as before FND-18: only the indexer's job follows the diff
        cairo = list(packages)
    else:
        cairo = [p for p in packages if everything or f"pkg:{p['dir']}" in tags]
    outputs = {
        "cairo": json.dumps(cairo, separators=(",", ":")),
        "classes": str(event == "push" or everything or "classes" in tags).lower(),
        "client": str(event == "push" or everything or "client" in tags).lower(),
        "indexer": str(everything or "indexer" in tags).lower(),
    }
    return outputs, notes


# --- the repository ---------------------------------------------------------------------------------


def tool_pin_file(folder, tool):
    """The .tool-versions file `tool` is read from: the nearest going up from `folder`."""
    folder = posixpath.normpath(folder)
    while True:
        path = posixpath.join(folder, ".tool-versions") if folder != "." else ".tool-versions"
        if os.path.isfile(path):
            with open(path, encoding="utf-8") as f:
                for line in f:
                    fields = line.split("#", 1)[0].split()
                    if len(fields) >= 2 and fields[0] == tool:
                        return path
        if folder == ".":
            return None
        folder = posixpath.dirname(folder) or "."


def tracked_manifests():
    tracked = subprocess.check_output(["git", "ls-files", "-z"], text=True).split("\0")
    out = {}
    for path in tracked:
        if path == "Scarb.toml" or path.endswith("/Scarb.toml"):
            with open(path, "rb") as f:
                out[posixpath.dirname(path) or "."] = tomllib.load(f)
    return out


def changed_files(workflow, event):
    """(files, base_known): the files that differ from the base, or ([], False) when it is unknown."""
    base = os.environ.get("PR_BASE" if event == "pull_request" else "PUSH_BEFORE", "")
    if not re.fullmatch(r"[0-9a-f]{40}", base) or re.fullmatch(r"0+", base):
        return [], False
    if subprocess.run(["git", "fetch", "--no-tags", "--depth=1", "origin", base]).returncode != 0:
        return [], False
    out = subprocess.run(
        ["git", "diff", "--no-renames", "--name-only", "-z", base, "HEAD"],
        capture_output=True, text=True,
    )
    if out.returncode != 0:
        return [], False
    return [p for p in out.stdout.split("\0") if p], True


def main(workflow):
    event = os.environ.get("EVENT", "pull_request")
    packages = []
    closures, pins = {}, {}
    if workflow == "ci":
        packages = json.loads(os.environ["PACKAGES"])
        manifests = tracked_manifests()
        for package in packages:
            closures[package["dir"]] = closure(package["dir"], manifests)
            pins[package["dir"]] = any(
                tool_pin_file(package["dir"], tool) == ".tool-versions" for tool in ("scarb", "starknet-foundry")
            )
    files, base_known = changed_files(workflow, event)
    outputs, notes = decide(files, packages, closures, pins, workflow, event, base_known)
    print(f"{len(files)} changed file(s) ({event})")
    for note in notes:
        print(note)
    for key, value in outputs.items():
        print(f"{key}={value}")
    target = os.environ.get("GITHUB_OUTPUT")
    if target:
        with open(target, "a", encoding="utf-8") as f:
            for key, value in outputs.items():
                f.write(f"{key}={value}\n")


# --- the self-test: the table as cases -------------------------------------------------------------


def self_test():
    manifests = {
        "contracts": {"workspace": {"members": ["logic", "persistent", "ephemeral"]}},
        "contracts/logic": {},
        "contracts/persistent": {"dependencies": {"grimworld_logic": {"path": "../logic"}}},
        "contracts/ephemeral": {"dependencies": {"grimworld_logic": {"path": "../logic"}}},
        "indexer/emitter": {"dependencies": {"grimworld_persistent": {"path": "../../contracts/persistent"}}},
        "spikes/SPK-12": {"dependencies": {"grimworld_logic": {"path": "../../contracts/logic"}}},
        "spikes/SPK-5": {},
    }
    dirs = ["contracts", "indexer/emitter", "spikes/SPK-12", "spikes/SPK-5"]
    packages = [{"dir": d, "scarb": "2.20.1", "snforge": "0.64.0"} for d in dirs]
    closures = {d: closure(d, manifests) for d in dirs}
    assert closures["indexer/emitter"] == {"indexer/emitter", "contracts/persistent", "contracts/logic"}, closures
    assert closures["contracts"] == {"contracts"}, closures
    pins = {"contracts": True, "indexer/emitter": True, "spikes/SPK-12": True, "spikes/SPK-5": False}

    def run(files, workflow="ci", event="pull_request", base_known=True):
        outputs, _ = decide(files, packages, closures, pins, workflow, event, base_known)
        if workflow == "tooling":
            return outputs["tooling"] == "true"
        return (
            sorted(p["dir"] for p in json.loads(outputs["cairo"])),
            outputs["classes"] == "true",
            outputs["client"] == "true",
            outputs["indexer"] == "true",
        )

    nothing = ([], False, False, False)
    everything = (sorted(dirs), True, True, True)
    # documents run no test
    for doc in ("docs/briefs/FND-18-ci-paths.md", "docs/architecture/x.md", "PLAN.md", "STATUS.md", "CHANGELOG.md",
                "README.md", "contracts/README.md", "contracts/logic/vectors/README.md", "spikes/SPK-5/NOTES.md",
                "LICENSE", ".githooks/pre-push", "tools/site/deploy-site.sh", "spikes/SPK-3/run.ts", "assets"):
        assert run([doc]) == nothing, doc
        assert run([doc], "tooling") is False, doc
    assert run(["PLAN.md", "docs/a.md", "STATUS.md"]) == nothing
    # the client
    assert run(["client/sim/src/hit.ts"]) == ([], False, True, False)
    assert run(["services/funder/src/index.ts"]) == ([], False, True, False)
    assert run(["pnpm-lock.yaml"]) == ([], False, True, False)
    assert run(["tools/art/manifest.toml"]) == ([], False, True, False)
    assert run(["indexer/src/db.ts"]) == ([], False, True, True)
    # the contracts
    assert run(["contracts/ephemeral/src/lib.cairo"]) == (["contracts"], True, False, False)
    assert run(["contracts/logic/src/hit.cairo"]) == (["contracts", "indexer/emitter", "spikes/SPK-12"], True, False, False)
    assert run(["contracts/logic/vectors/hit.jsonl"]) == (
        ["contracts", "indexer/emitter", "spikes/SPK-12"], False, True, False)
    assert run(["contracts/tools/class_sizes.py"]) == (["contracts"], False, False, False)
    assert run(["contracts/persistent/GAS.md"]) == (["contracts"], False, False, False)
    assert run(["docs/BUDGETS.md"]) == (["contracts"], False, False, False)
    assert run(["scripts/gas_budgets.py"]) == (["contracts"], False, False, False)
    assert run(["contracts/seed/test-region.json"]) == (["contracts"], False, True, False)
    # a spike and the emitter
    assert run(["spikes/SPK-5/src/lib.cairo"]) == (["spikes/SPK-5"], False, False, False)
    assert run(["spikes/SPK-12/Scarb.lock"]) == (["spikes/SPK-12"], False, False, False)
    assert run(["indexer/emitter/src/lib.cairo"]) == (["indexer/emitter"], False, True, True)
    # the root pins: every package whose pin is the root's, the pnpm jobs, the tooling checks
    assert run([".tool-versions"]) == (
        ["contracts", "indexer/emitter", "spikes/SPK-12"], True, True, False)
    assert run([".tool-versions"], "tooling") is True
    # the scripts and the one brief the launcher reads
    assert run(["scripts/lock.sh"], "tooling") is True and run(["scripts/lock.sh"]) == nothing
    assert run(["docs/briefs/SPK-1-sepolia.md"], "tooling") is True
    assert run(["client/sim/src/hit.ts"], "tooling") is False
    # a workflow or a CI helper runs everything
    for ci in (".github/workflows/ci.yml", ".github/workflows/tooling.yml", ".github/ci/changes.py"):
        assert run([ci]) == everything, ci
        assert run([ci], "tooling") is True, ci
    # unclassified runs everything
    assert run(["newfolder/x.rs"]) == everything
    assert run(["Makefile"], "tooling") is True
    # an unknown base runs everything, a push keeps its jobs (the indexer follows its diff)
    assert run([], base_known=False) == everything
    assert run(["PLAN.md"], event="push") == (sorted(dirs), True, True, False)
    assert run(["indexer/src/db.ts"], event="push") == (sorted(dirs), True, True, True)
    assert run(["PLAN.md"], "tooling", "push") is True
    # no change at all runs nothing
    assert run([]) == nothing
    print("changes.py self-test: ok")


if __name__ == "__main__":
    args = sys.argv[1:]
    if args == ["--self-test"]:
        self_test()
    elif args in ([], ["--workflow", "ci"]):
        main("ci")
    elif args == ["--workflow", "tooling"]:
        main("tooling")
    else:
        sys.exit("usage: changes.py [--workflow ci|tooling] | --self-test")
