# PENDING — G-1: protect `main` of `bal7hazar/grimworld` on GitHub

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

*To be filled with the owner's decision and its date.*
