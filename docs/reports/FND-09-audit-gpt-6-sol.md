# [GPT-6-Sol] Audit — PR 152 (FND-09) — quality

## Verdict

**PASS.** Finding 1 is resolved; no open findings.

## Findings

| # | Severity | Location | Finding | Evidence / failing scenario | Suggested fix |
|---|---|---|---|---|---|
| 1 | major, resolved | [scripts/with-node.sh:61](/home/claude/projects/grimworld/.claude/worktrees/cli-AUD-152/scripts/with-node.sh:61) | The Perl fallback previously returned 1 when `setsid(2)` failed. | The fallback now explicitly exits 127. A foreground probe forced `setsid(2)` to fail and got 127 without running the command. A missing executable also returned 127. The new [fixture](/home/claude/projects/grimworld/.claude/worktrees/cli-AUD-152/.github/workflows/tooling.yml:281) asserts the failure status and that its command did not run. | Complete. |

## Coverage

The earlier review of group cleanup, Linux behavior, archive flag, usage text, and the existing fixtures still stands; this fix changes only the Perl failure branch and adds its fixture. `bash -n` and `git diff --check` passed. I did not run the full fixtures or ShellCheck locally; ShellCheck is unavailable here.