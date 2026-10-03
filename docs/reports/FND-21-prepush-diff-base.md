Archived at the merge of #352, 53f1095.

## Report
FND-21, head `85063ba`, review fixes (Opus, #352 at dc0b7c5) all in one push. Not merged.
1. Self-test can now fail: the subshell's status is read with `$?` (not `|| rc=1`, which disabled `set -e`), and `expect` returns 1. Proof: with `d.txt` removed from one expectation the run printed `self-test FAILED: a deleted file: expected [a.txt doc.md own1.txt own2.txt], got [a.txt d.txt doc.md own1.txt own2.txt]` and exited 1; restored, exit 0.
2. origin/main with no merge base with HEAD (orphan branch): no base, every check runs. Self-test case added.
3. Cases added: file changed by both main and branch, revert, rename (--no-renames), deleted file, upstream ahead of HEAD, detached HEAD (plus the earlier ones; 11 in all).
4. SC2015 lines gone with the rewritten self-test; the one remaining `&& ... ||` line in the file is pre-existing and not that pattern.
5. `.github/workflows/tooling.yml`: one test step `prepush changed-set self-test` (nexus #60); PR body names the file. Edited with the Edit tool.
6. compute_changed's comment says a file reverted within the push is left out.
- Local `scripts/prepush.sh` passed on push; shellcheck not available on the VPS, CI to confirm.

## Next
Wait for PR #352 checks to finish
Re-review PR #352 with Opus
Merge PR #352 once green
Remove the worktree and branch after merge
