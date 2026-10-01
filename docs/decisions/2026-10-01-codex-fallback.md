# D-175: nobody waits for Codex

| | |
|---|---|
| Decided by | The owner, 2026-10-01, relayed by the Overseer; recorded by the `[Fable 5.1]` project manager |
| Replaces | The rule of the morning (reviews fall back to Opus, audits wait for Codex) |

**While Codex has no quota, nobody waits for Codex.** The review of a pull request is made by
**Claude Sonnet**; every audit, whatever its lens (quality, cost, security, organisation, design,
content), by **Claude Opus 5.5**. Nexus applies it by itself once `bal7hazar/nexus` R2 is deployed:
the review's fallback is `claude/sonnet`, the audits' fallback `claude/opus`, at start and when
queued, on the probation rule of the reviews; `auditor:fallback` and `reviewer:fallback` of the
project's definition may replace them. Until R2 is deployed, an audit is held for the deployment,
not for Codex's reset. When the work was written by the fallback's model, the project manager may
ask the other Claude model so that the reviewer is not the author's.

The four orchestrators of the project have the rule (2026-10-01). OPERATIONS §2 and §6 point to it.
