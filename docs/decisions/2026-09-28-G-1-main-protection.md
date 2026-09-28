# G-1: protect `main` on GitHub — declined for now (2026-09-28)

| | |
|---|---|
| Asked by | `[Opus 5.5]` game orchestrator, 2026-09-28, from finding F4 of the `[GPT-6-Sol]` audit of FND-03 (`docs/reports/FND-03-audit-gpt-6-sol.md`) |
| Decides | The owner: it is a security setting of the owner's repository. The project manager applies it once allowed |
| State on 2026-09-28 | `main` is not protected, no ruleset exists; the repository is public |

## Why

The launcher's profiles restrict the commands an agent may run. They cannot stop a program
the agent is allowed to run (a test, an interpreter, a script) from calling `git push` with
the credentials of the machine, which belong to an administrator of the repository. Only
the server can refuse a force-push or a deletion of `main`, whoever asks.

## Proposal

| Step | Setting | Effect on our process |
|---|---|---|
| **Now** | Ruleset on `main`: **block force-push, block deletion**. Nothing else | None: nobody force-pushes or deletes `main` (OPERATIONS §7 forbids it already). Bookkeeping pushes and squash merges are unchanged |
| When FND-02 lands | Require the CI checks on pull requests, **administrators may bypass** | Task pull requests cannot merge red. The orchestrators' bookkeeping commits to `main` (status, plan, changelog) keep working through the bypass |

Not proposed: requiring a pull request for every change to `main`, or reviews. Orchestrators
and the project manager commit bookkeeping on `main`; all sessions act as the same GitHub
user, so a required review could not be given.

The same two steps apply to `bal7hazar/hexx-cairo`.

Limit: with the bypass, step 2 protects against mistakes, not against a program using the
administrator's credentials on purpose. Step 1 has no bypass.

## Recommendation

Yes to both steps, on both repositories.

## Answer

Given by the owner on 2026-09-28: **no protection for now** (D-121). The project is being
kick-started with a large volume of implementation, and the owner prefers to keep full
freedom on `main` during that time. Neither step is applied, on either repository.

| | |
|---|---|
| Accepted residual | A program run by an agent could push to `main`, force-push included, with the machine's credentials (finding F4 of the FND-03 audit). Mitigations that remain: the launcher's profiles, the rule of OPERATIONS §7 (no force-push on shared branches), reviews by the orchestrators, and the history kept by every clone and worktree on the machine |
| To raise again | By the project manager at the gate of Phase 0, and at the latest before anything of value or any public playtest depends on the repository (Phase 6). Not before, unless an incident happens |
