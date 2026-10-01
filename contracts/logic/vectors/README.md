# Vector tables for the client's mirror

Each table is printed by a test of `grimworld_logic` and kept here, one JSON line per case, every
felt in hexadecimal. The test holds a digest of every case and outcome: a change to a rule, or to
the cases, fails it until the table is regenerated (D-140, SPK-4).

## `window.jsonl`: the geometry of the window (ENG-02)

Printed by `types::window::tests::test_vectors`; regenerated from `contracts/logic` by

```
snforge test types::window::tests::test_vectors | grep '^{"id"' > vectors/window.jsonl
```

and the `DIGEST` of the test set to the `digest` it prints.

One line: `{"id", "fn", "case", "ok"}`. A position is the window's index `15 y + x` (0–239; 240 and
up is outside the window), a facing `0..=5` (East, North-East, North-West, West, South-West,
South-East), a boolean 0 or 1. `open` is the window's walkable bitmap (bit `p` is 1 for a walkable
tile `p`); the vectors use one fixture with seven walls.

| `fn` | `case` | `ok` |
|---|---|---|
| `sight` | `open`, `from`, `to` | `WindowTrait::sight` |
| `reach` | `open`, `from`, `to`, `range` (6) | `WindowTrait::reach` |
| `arc` | `source`, `target`, `facing` (the target's) | `Option<Arc>` as Cairo `Serde`: `[0, a]` for `Some`, `a` 0 `Front`, 1 `FrontSide`, 2 `RearSide`, 3 `Back`; `[1]` for `None` |
| `facing` | `from`, `to`, `facing` (the actor's) | the facing after the action |
| `front` | `source`, `facing` (the source's), `target` | `WindowTrait::front` |
| `shape` | `open`, `shape` (1 `SINGLE` … 5 `DISC_3`), `centre` | the bitmap of the shape's tiles |

The cases: `sight` and `reach` from both row parities at the centre to every tile within 7, and the
edges (a line leaving the window at a corner, a position outside); `arc` and `facing` from every
tile within 6 of the target `(7, 8)`, the facing turning with the source, and the edges; `front`
for every neighbour and facing at the centre and on the East edge; `shape` for each shape at the
corners, the edges, the centre and next to walls.
