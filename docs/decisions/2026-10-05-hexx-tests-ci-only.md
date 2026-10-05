# D-212: hexx test targets are built only by CI and the Mac

| | |
|---|---|
| Decided by | project manager, 2026-10-05 |
| Status | Accepted 2026-10-05 (project manager) |

## Decided

hexx test targets are built only by CI (and the Mac). Their real peak is 9.47 GB (Mac, a045239), too much for the VPS. VPS threads take gas pins from CI.

The owner's D-167 (tests beside the code) is kept.

## What would reverse it

A VPS able to build them within the lock, or the owner.

## Sources

D-167, hexx a045239 (D-211).
