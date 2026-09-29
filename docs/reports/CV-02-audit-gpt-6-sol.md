# [GPT-6-Sol] Audit — CV-02 — security

## Verdict
PASS

## Findings

| # | Severity (blocker/major/minor/note) | Location | Finding | Evidence / failing scenario | Suggested fix |
|---|---|---|---|---|---|
| — | — | — | No finding within the launcher’s stated scope. | — | — |

## Coverage

Reviewed `git diff origin/main -- scripts/mac`, the CV-02 brief, `OPERATIONS.md` §3, and the CV-01 audit. The launcher considers exactly five slots; `slots-init` checks existing slots are free before adding `cv-3` through `cv-5`, and the shared launch lock covers slot selection through acquisition. The account check and job use the same absolute CLI path. Test mode selects paths under its test home; reaching a real CLI would require the same user to deliberately replace a stub or redirect its path.

The new tests exercise migration from two slots, five concurrent stubs and a refused sixth, the last-slot race, the load boundary, PATH, CLI paths, missing binaries, and `status` without `.cli`. Both installed CLI targets are native Mach-O binaries, so the Claude CLI does not need Node from PATH. The dry runs showed the fixed CLI paths, shim-first PATH, model labels, and no `--dangerously-skip-permissions`.

`bash -n`, `shellcheck`, and `git diff --check` passed. I did not run `scripts/mac/test.sh` or launch an agent, so its reported passing run was not independently reproduced.