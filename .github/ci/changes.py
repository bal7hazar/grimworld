#!/usr/bin/env python3
"""Which jobs of CI a change concerns (FND-18, docs/briefs/FND-18-ci-paths.md).

Run by the first job of .github/workflows/ci.yml (`discover`) and by the first step of the `tooling`
job of .github/workflows/tooling.yml. It lists the files that differ from the base and sets the
outputs that each test job's `if:` reads:

  ci:      cairo (JSON list of the discovered packages to run, [] when none), classes, client, indexer, art,
           map_format
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

# The art job: the art pipeline's Python tests (tools/art/tests). They read the pipeline, its manifest and
# its pinned requirements, all under tools/art/; the rest of tools/ stays ignored. The manifest also
# feeds `client` (above).
ART_PREFIXES = ("tools/art/",)

# The map-format job (ENG-09): the authored zones' converter's Python tests (tools/map-format/tests).
# They read the converter, its schema, checks table and samples, and the Registry's Cairo twins of each
# refusal (`test_cairo_twins` reads the one test file below).
MAP_FORMAT_PREFIXES = ("tools/map-format/",)
MAP_FORMAT_FILES = ("contracts/persistent/tests/test_zone.cairo",)

# The `contracts` package also reads these (gas budgets, GAS.md, class sizes, exp2 table, vectors).
# contracts/tools/exp2_table.py checks the client's mirror of the table too (TS_PATH).
CONTRACTS_FILES = ("scripts/gas_budgets.py", "docs/BUDGETS.md", "client/sim/src/exp2.ts")
# What the class-artefacts job builds: only these files of contracts/ can change the bytes.
CLASS_INPUT = re.compile(r"(\.cairo|(^|/)Scarb\.toml|(^|/)Scarb\.lock|(^|/)\.tool-versions)$")

# The tooling job's checks (shellcheck, launcher dry-run, lock.sh, with-node.sh, the self-tests): the
# scripts, and the one brief the launcher dry-run reads for its Sepolia grant.
TOOLING_PREFIXES = ("scripts/", ".githooks/")  # shellcheck and the pre-push hook step read .githooks/
TOOLING_FILES = ("docs/briefs/SPK-1-*",)

# Paths that no test of CI reads. A markdown file is a document unless a job above claims it
# (docs/BUDGETS.md, contracts/**/GAS.md, the SPK-1 brief).
IGNORED_PREFIXES = ("docs/", "tools/", "spikes/", "assets/")
IGNORED_FILES = ("*.md", "LICENSE", ".gitmodules", "assets")

# The indexer-node job: the indexer, and what its emitter and its node depend on (decided by the
# orchestrator, 2026-10-03: the emitter builds from contracts/persistent and contracts/logic, the node
# is the pinned devnet started by with-node.sh).
INDEXER_PREFIXES = ("indexer/", "contracts/persistent/", "contracts/logic/")
# contracts/Scarb.toml is the workspace manifest the members inherit from; the emitter and the spikes are
# outside the workspace and resolve through their own Scarb.lock, so contracts/Scarb.lock is not an input.
INDEXER_FILES = (".tool-versions", "scripts/with-node.sh", "contracts/Scarb.toml")
# prettier checks client/ and indexer/ whatever the file type, markdown included (decided by the
# orchestrator, 2026-10-03; reversed by a later lot that adds a .prettierignore for *.md).
PRETTIER_PREFIXES = ("client/", "indexer/")

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
    """(folders, files) a job rooted at `root` compiles: the folders are its own and (transitively) the
    folder of every path dependency of a manifest at or below one of them; the files are the manifests of
    the workspaces that those folders are members of (they inherit version, edition and dependencies from
    it). `manifests` maps a folder to its parsed Scarb.toml."""
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
    files = set()
    for folder in folders:
        for dir_, manifest in manifests.items():
            if "workspace" in manifest and dir_ != folder and under(folder, dir_):
                files.add(posixpath.join(dir_, "Scarb.toml"))
    return folders, files


def under(path, folder):
    return path == folder or path.startswith(folder + "/")


# --- the classification ----------------------------------------------------------------------------


def classify(path, packages, closures, pins):
    """The set of tags a changed path carries: ALL, 'classes', 'client', 'indexer', 'art', 'tooling'
    and 'pkg:<dir>'. An empty set is a path that runs nothing; None is unclassified (runs everything)."""
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
        tags |= {"classes", "client", "tooling", "indexer"}
    if not is_markdown:
        for package in packages:
            root = package["dir"]
            folders, files = closures[root]
            if path in files or any(under(path, folder) for folder in folders):
                tags.add(f"pkg:{root}")
        if under(path, "contracts") and CLASS_INPUT.search(path):
            tags.add("classes")
    if path.startswith(PRETTIER_PREFIXES):
        tags.add("client")
    if path.startswith(ART_PREFIXES):
        tags.add("art")
    if path.startswith(MAP_FORMAT_PREFIXES) or path in MAP_FORMAT_FILES:
        tags.add("map_format")
    if not is_markdown:
        if path.startswith(CLIENT_PREFIXES) or path in CLIENT_FILES or matches(path, CLIENT_ROOT_FILES):
            tags.add("client")
        if path.startswith(INDEXER_PREFIXES) or path in INDEXER_FILES:
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
        "art": str(event == "push" or everything or "art" in tags).lower(),
        "map_format": str(event == "push" or everything or "map_format" in tags).lower(),
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
        "spikes/SPK-15": {"dependencies": {"grimworld_logic": {"path": "../../contracts/logic"}}},
        "spikes/SPK-5": {},
    }
    dirs = ["contracts", "indexer/emitter", "spikes/SPK-12", "spikes/SPK-15", "spikes/SPK-5"]
    packages = [{"dir": d, "scarb": "2.20.1", "snforge": "0.64.0"} for d in dirs]
    closures = {d: closure(d, manifests) for d in dirs}
    assert closures["indexer/emitter"] == (
        {"indexer/emitter", "contracts/persistent", "contracts/logic"}, {"contracts/Scarb.toml"}), closures
    assert closures["contracts"] == ({"contracts"}, set()), closures
    assert closures["spikes/SPK-5"] == ({"spikes/SPK-5"}, set()), closures
    pins = {"contracts": True, "indexer/emitter": True, "spikes/SPK-12": True, "spikes/SPK-15": True,
            "spikes/SPK-5": False}

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

    def art(files, event="pull_request", base_known=True):
        outputs, _ = decide(files, packages, closures, pins, "ci", event, base_known)
        return outputs["art"] == "true"

    nothing = ([], False, False, False)
    everything = (sorted(dirs), True, True, True)
    # documents run no test
    for doc in ("docs/briefs/FND-18-ci-paths.md", "docs/architecture/x.md", "PLAN.md", "STATUS.md", "CHANGELOG.md",
                "README.md", "contracts/README.md", "contracts/logic/vectors/README.md", "spikes/SPK-5/NOTES.md",
                "LICENSE", "tools/site/deploy-site.sh", "spikes/SPK-3/run.ts", "assets"):
        assert run([doc]) == nothing, doc
        assert run([doc], "tooling") is False, doc
    assert run(["PLAN.md", "docs/a.md", "STATUS.md"]) == nothing
    # the client
    assert run(["client/sim/src/hit.ts"]) == ([], False, True, False)
    assert run(["services/funder/src/index.ts"]) == ([], False, True, False)
    assert run(["pnpm-lock.yaml"]) == ([], False, True, False)
    assert run(["tools/art/manifest.toml"]) == ([], False, True, False)
    assert run(["indexer/src/db.ts"]) == ([], False, True, True)
    # the art pipeline's tests: any file under tools/art/, and nothing else of tools/
    for path in ("tools/art/requirements.txt", "tools/art/build.py", "tools/art/artpipe/png.py",
                 "tools/art/tests/test_build.py", "tools/art/manifest.toml", "tools/art/README.md"):
        assert art([path]), path
    assert run(["tools/art/requirements.txt"]) == nothing and run(["tools/art/build.py"]) == nothing
    assert art(["tools/art/manifest.toml"]) and run(["tools/art/manifest.toml"]) == ([], False, True, False)
    for path in ("tools/site/deploy-site.sh", "tools/artifact/x.py", "docs/a.md", "client/sim/src/hit.ts",
                 "contracts/logic/src/hit.cairo", "scripts/lock.sh", "PLAN.md", "assets"):
        assert not art([path]), path
    assert not art([]) and art([], base_known=False) and art(["PLAN.md"], event="push")
    assert art([".github/workflows/ci.yml"]) and art(["newfolder/x.rs"])

    # the map format's tests (ENG-09): any file under tools/map-format/ and the Registry's twins of its
    # refusals, which run nothing else of the tools; a Cairo test file also runs its package
    def map_format(files, event="pull_request"):
        outputs, _ = decide(files, packages, closures, pins, "ci", event, True)
        return outputs["map_format"] == "true"

    for path in ("tools/map-format/convert.py", "tools/map-format/checks.json",
                 "tools/map-format/samples/zone.json", "tools/map-format/tests/test_convert.py",
                 "tools/map-format/README.md", "contracts/persistent/tests/test_zone.cairo"):
        assert map_format([path]), path
    assert run(["tools/map-format/convert.py"]) == nothing
    assert run(["contracts/persistent/tests/test_zone.cairo"]) == (["contracts", "indexer/emitter"], True, False, True)
    for path in ("tools/art/build.py", "docs/a.md", "contracts/persistent/tests/test_registry.cairo", "PLAN.md"):
        assert not map_format([path]), path
    assert map_format(["PLAN.md"], event="push") and map_format([".github/ci/changes.py"])
    # the contracts
    assert run(["contracts/ephemeral/src/lib.cairo"]) == (["contracts"], True, False, False)
    assert run(["contracts/logic/src/hit.cairo"]) == (["contracts", "indexer/emitter", "spikes/SPK-12", "spikes/SPK-15"], True, False, True)
    assert run(["contracts/persistent/src/lib.cairo"]) == (["contracts", "indexer/emitter"], True, False, True)
    assert run(["contracts/ephemeral/src/lib.cairo"]) == (["contracts"], True, False, False)
    assert run(["contracts/logic/GAS.md"]) == (["contracts"], False, False, False)
    assert run(["scripts/with-node.sh"]) == ([], False, False, True)
    assert run(["scripts/with-node.sh"], "tooling") is True
    assert run(["contracts/logic/vectors/hit.jsonl"]) == (
        ["contracts", "indexer/emitter", "spikes/SPK-12", "spikes/SPK-15"], False, True, True)
    assert run(["contracts/tools/class_sizes.py"]) == (["contracts"], False, False, False)
    assert run(["contracts/persistent/GAS.md"]) == (["contracts"], False, False, False)
    assert run(["docs/BUDGETS.md"]) == (["contracts"], False, False, False)
    assert run(["scripts/gas_budgets.py"]) == (["contracts"], False, False, False)
    assert run(["contracts/seed/test-region.json"]) == (["contracts"], False, True, False)
    # the workspace manifest: its members, and the packages outside it that depend on them
    assert run(["contracts/Scarb.toml"]) == (
        ["contracts", "indexer/emitter", "spikes/SPK-12", "spikes/SPK-15"], True, False, True)
    assert run(["contracts/Scarb.lock"]) == (["contracts"], True, False, False)
    # the exp2 table is checked against the client's mirror
    assert run(["client/sim/src/exp2.ts"]) == (["contracts"], False, True, False)
    # prettier checks markdown under client/ and indexer/
    assert run(["client/app/README.md"]) == ([], False, True, False)
    assert run(["indexer/README.md"]) == ([], False, True, False)
    assert run(["services/funder/README.md"]) == nothing
    # assets is the submodule pointer, not a prefix
    assert run(["assets"]) == nothing and run(["assets/x.txt"]) == nothing and run(["assetsfoo/x.rs"]) == everything
    # a spike and the emitter
    assert run(["spikes/SPK-5/src/lib.cairo"]) == (["spikes/SPK-5"], False, False, False)
    assert run(["spikes/SPK-12/Scarb.lock"]) == (["spikes/SPK-12"], False, False, False)
    assert run(["indexer/emitter/src/lib.cairo"]) == (["indexer/emitter"], False, True, True)
    # the root pins: every package whose pin is the root's, the pnpm jobs, the tooling checks
    assert run([".tool-versions"]) == (
        ["contracts", "indexer/emitter", "spikes/SPK-12", "spikes/SPK-15"], True, True, True)
    assert run([".tool-versions"], "tooling") is True
    # the scripts and the one brief the launcher reads
    assert run(["scripts/lock.sh"], "tooling") is True and run(["scripts/lock.sh"]) == nothing
    assert run([".githooks/pre-push"], "tooling") is True and run([".githooks/pre-push"]) == nothing
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
