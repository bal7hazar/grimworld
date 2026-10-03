# D-203: hexx ships the licence notices of its two origins from 0.1.0-rc.2

| | |
|---|---|
| Decided by | project manager, 2026-10-02; recorded by the project manager |

## Decided

From 0.1.0-rc.2 on, hexx ships `crates/hexx/LICENSE-origami` (MIT, origami_hexmap) and `crates/hexx/LICENSE-hexx` (Apache-2.0 text of bevy hexx 0.25.0). The package README names both, with "Ported to Cairo from bevy hexx 0.25.0". rc.1, published without them, is kept (the owner's session: no yank), with a note in its release and in the CHANGELOG. hexx-cairo #101 (merged c60e05a).

## Why

The take-over of origami_hexmap requires its MIT notice; rc.1 shipped without it.

## What would reverse it

The owner's word (a yank of rc.1).

## Sources

hexx-cairo #101, D-173.
