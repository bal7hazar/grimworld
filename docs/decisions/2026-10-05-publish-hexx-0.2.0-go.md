# D-211: the owner's go to publish `hexx` 0.2.0

| | |
|---|---|
| Decided by | the owner, 2026-10-05, written directly to the project manager in its own pane |
| Asked by | the project manager, under D-132 (stable versions of `hexx` stay the owner's go) |
| Status | Accepted 2026-10-05 (owner, written go) |

## The go

The owner's words, verbatim:

> Ok je te donne mon go pour la publication de hexx 0.2.0

English: "OK, I give you my go for publishing hexx 0.2.0."

It answers the project manager's request, which named exactly:

| Package | Version | Commit | Archive sha256 |
|---|---|---|---|
| hexx | 0.2.0 | `a045239e243511018e223aab21fb1be2db6f0d4e` of `bal7hazar/hexx-cairo` | `853a6f7016fc2828258933c477ce3676472729caae90dffbac2d5602e4709b08` |

The go covers exactly this package, this version, this commit and this sha256.

## Checked before the request

The project manager's own D-132 checklist, in a clean clone, passed:

- the commit is on `main` with CI green;
- the L-M2 parity audit has no blocker and no major;
- the sha256 of the archive reproduces;
- the archive holds 53 files, with `LICENSE-hexx` and `LICENSE-origami`;
- 0.2.0 is free on the registry.

## What would reverse it

Nothing once published: a version stays on the registry; a fix is a new version. Any other commit or
archive needs a new go.

## Sources

D-132, D-186, D-203, D-204.
