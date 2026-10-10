"""Unit tests of the classification of changes.py (FND-CI, D-253): no git, no network.

  python3 -m unittest discover -s .github/ci -p 'test_*.py'
"""

import json
import os
import sys
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import changes  # noqa: E402

DIRS = ["contracts", "indexer/emitter"]
MANIFESTS = {
    "contracts": {"workspace": {"members": ["logic", "persistent", "ephemeral"]}},
    "contracts/logic": {},
    "contracts/persistent": {"dependencies": {"grimworld_logic": {"path": "../logic"}}},
    "contracts/ephemeral": {"dependencies": {"grimworld_logic": {"path": "../logic"}}},
    "indexer/emitter": {"dependencies": {"grimworld_persistent": {"path": "../../contracts/persistent"}}},
}
PACKAGES = [{"dir": d, "scarb": "2.20.1", "snforge": "0.64.0"} for d in DIRS]
CLOSURES = {d: changes.closure(d, MANIFESTS) for d in DIRS}
PINS = {d: True for d in DIRS}

# Every path outside client/ that a test of the pnpm workspace reads, with the test that reads it.
CLIENT_READS = {
    "tools/map-format/checks.json": "client/app/src/editor/export/convert.test.ts",
    "tools/map-format/schema.json": "client/app/src/editor/export/convert.test.ts",
    "tools/map-format/kinds.json": "client/app/src/editor/export/convert.test.ts",
    "tools/map-format/samples/zone.json": "client/app/src/editor/export/document.test.ts",
    "tools/map-format/samples/manifest.json": "client/app/src/editor/bridges.test.ts",
    "tools/art/manifest.toml": "client/app/src/render/obstacles.test.ts",
    "contracts/seed/test-region.json": "client/app/src/sandbox/fixtures/region.test.ts",
    "contracts/logic/vectors/window.jsonl": "client/sim/src/parity/table.ts",
}


def outputs(files, workflow="ci", event="pull_request", base_known=True):
    out, _ = changes.decide(files, PACKAGES, CLOSURES, PINS, workflow, event, base_known)
    return out


def on(files, job):
    return outputs(files)[job] == "true"


class ClassifyTest(unittest.TestCase):
    def test_map_format_runs_client_and_map_format(self):
        for path in ("tools/map-format/checks.json", "tools/map-format/convert.py",
                     "tools/map-format/samples/zone.json"):
            self.assertTrue(on([path], "client"), path)
            self.assertTrue(on([path], "map_format"), path)

    def test_map_format_alone_runs_no_other_job(self):
        out = outputs(["tools/map-format/checks.json"])
        self.assertEqual(json.loads(out["cairo"]), [])
        for job in ("classes", "indexer", "art"):
            self.assertEqual(out[job], "false", job)

    def test_art_manifest_runs_client_and_art(self):
        self.assertTrue(on(["tools/art/manifest.toml"], "client"))
        self.assertTrue(on(["tools/art/manifest.toml"], "art"))
        self.assertFalse(on(["tools/art/manifest.toml"], "map_format"))

    def test_other_art_files_do_not_run_client(self):
        self.assertTrue(on(["tools/art/build.py"], "art"))
        self.assertFalse(on(["tools/art/build.py"], "client"))

    def test_docs_run_nothing(self):
        out = outputs(["docs/briefs/FND-18-ci-paths.md"])
        self.assertEqual(json.loads(out["cairo"]), [])
        for job in ("classes", "client", "indexer", "art", "map_format"):
            self.assertEqual(out[job], "false", job)
        self.assertEqual(outputs(["docs/a.md"], "tooling")["tooling"], "false")

    def test_map_format_readme_is_a_document(self):
        self.assertFalse(on(["tools/map-format/README.md"], "client"))

    def test_unclassified_runs_everything(self):
        out = outputs(["newfolder/x.rs"])
        self.assertEqual(sorted(p["dir"] for p in json.loads(out["cairo"])), sorted(DIRS))
        for job in ("classes", "client", "indexer", "art", "map_format"):
            self.assertEqual(out[job], "true", job)
        self.assertIsNone(changes.classify("newfolder/x.rs", PACKAGES, CLOSURES, PINS))

    def test_github_runs_everything(self):
        self.assertEqual(changes.classify(".github/ci/changes.py", PACKAGES, CLOSURES, PINS), {changes.ALL})

    def test_each_path_a_client_test_reads_runs_client(self):
        for path, reader in CLIENT_READS.items():
            self.assertTrue(on([path], "client"), f"{path} (read by {reader})")

    def test_unknown_base_runs_everything(self):
        self.assertEqual(outputs([], base_known=False)["client"], "true")


if __name__ == "__main__":
    unittest.main()
