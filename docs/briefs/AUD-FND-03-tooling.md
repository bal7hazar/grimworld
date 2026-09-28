# AUD-FND-03 — Audit of the agent tooling

## Agent
Title: `[GPT-6-Sol] Audit FND-03 security and quality` · codex `gpt-6-sol`, reasoning `high`,
read-only sandbox · Profile: audit

## Goal
An independent audit of task FND-03 (agent tooling) through the **security** and **code
quality** lenses (OPERATIONS §6, "Tooling / CI"), before the orchestrator merges it.

## What to audit
The pull request of branch `chore/fnd-03-agent-tooling`, checked out in your working
directory. Compare with `origin/main` (`git diff origin/main...HEAD`):

- `scripts/agent.sh` — the launcher
- `scripts/lock.sh` — the build lock
- `scripts/profiles/research.txt`, `audit.txt`, `implement.txt` — permission profiles
- `.github/workflows/tooling.yml` — the minimal CI
- `docs/briefs/COMMON.md` — rules inherited by every brief
- `OPERATIONS.md` §3 and §4, `.gitignore`

## Specification
- `docs/briefs/ORCH-game.md` §3: the deliverables and acceptance criteria of FND-03.
- `OPERATIONS.md` §2 to §4 and §7; `CONTEXT.md` §8 (constraints); D-73 (assets).
- The reference it was ported from, for comparison only:
  `/home/claude/projects/glam-cairo/scripts/agent.sh` (it deliberately used
  `--dangerously-skip-permissions`, which this port must not).
- The machine's shims `~/.local/bin/scarb` and `~/.local/bin/snforge` (they take
  `~/orchestrator/heavy-build.lock`), which `scripts/lock.sh` relies on.

## Questions to answer
Security:
1. Can any launch produced by `scripts/agent.sh` run without permission checks, or with a
   permission wider than its profile? Can codex ever write?
2. Do the profiles grant what their names promise and no more: `research` (read, search,
   web, a report), `audit` (plus builds and tests), `implement` (plus toolchain, git except
   force-push, `gh pr`)? Which allowed rule is an escape hatch that runs arbitrary commands,
   and is it justified? Which dangerous action is not denied (force-push forms, merging,
   touching the `assets` submodule or committing asset files, deleting outside the
   worktree, changing the machine's shared toolchain or shims, leaking secrets)?
   Claude Code rules: `*` matches any text anywhere; deny rules win over allow rules;
   each subcommand of a compound command is checked separately.
3. Shell safety of `agent.sh` and `lock.sh`: quoting, word splitting, injection through
   the task name, the prompt or a profile line; `set -euo pipefail` pitfalls; the unit and
   log file names.
4. Locks: can `scripts/lock.sh` deadlock with the machine shims or with the other
   programmes' locks (order: project lock, then heavy lock)? Can it be used to run
   something other than the four tools it wraps?
5. The CI: does it prove what it claims (no `--dangerously…` flag in any launch, codex
   read-only, refusals), and can the asset check be bypassed trivially?

Quality:
6. Does the launcher meet every acceptance criterion of ORCH-game.md §3? Say which are
   met, and which are not.
7. Is the code clear for the next orchestrator: dead code, misleading comments, names,
   behaviour that differs from what OPERATIONS §4 or COMMON.md says?

You may run read-only commands, for example
`bash scripts/agent.sh --dry-run t claude sonnet new "x" implement` (it launches nothing and
writes nothing), `bash -n`, `git diff`. `shellcheck` may be absent on this machine; the CI
runs it.

## Report
Your final message is the report, in this form (OPERATIONS §6):

```markdown
# [GPT-6-Sol] Audit — FND-03 — security, quality

## Verdict
PASS | PASS WITH FINDINGS | FAIL

## Findings
| # | Severity | Location | Finding | Evidence / failing scenario | Suggested fix |

## Coverage
What was reviewed, what was not, and why.
```

Severities: `blocker` (exploit, loss of state, rule broken, build broken), `major` (wrong
behaviour in a reachable case; acceptance criterion not met), `minor` (quality, clarity),
`note`. Every finding needs evidence: a command and its output, a failing scenario, or a
quoted rule. Do not suggest widening the scope of FND-03.
