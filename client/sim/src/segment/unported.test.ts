// What the segment tables cannot show of the mirror (CLI-02f, CLI-02g-A): the branches of
// `SegmentTrait::run` it does not mirror (a Move off the window's edge, D-255), that a refusal
// leaves the words and the ground as they were even when the class mutates its inputs (D-259,
// `parity/seam.ts`' cases), that `run` does not change what it is given, and that the replayer of
// the parity tests stays out of the app's API.

import { existsSync, readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";
import * as sim from "../index";
import { board as origin_board, position } from "../movement";
import { CHECKS, UNREACHED, holds, segment } from "../parity/seam";
import { run } from "../segment";
import { WIDTH, inside, neighbor } from "../window";

describe("the segment beyond its tables", () => {
  for (const check of CHECKS) {
    it(`${check.name} (D-259)`, () => {
      expect(() => holds(check)).not.toThrow();
    });
  }

  it("cannot reach Blocked by a missing neighbour: the adventurer stands inside the window's ring", () => {
    // Its window is around it (column 7, row 7 or 8): every direction has a neighbour, so the
    // branch's `NotMirrored` is a guard only
    for (const [x, y] of [
      [0, 0],
      [22, 22],
      [22, 23],
      [44, 44],
      [224, 224],
    ] as const) {
      const from = position(origin_board(x, y), x, y);
      expect(inside(from)).toBe(true);
      expect([from % WIDTH, Math.floor(from / WIDTH)]).toEqual([7, y % 2 === 1 ? 7 : 8]);
      for (let d = 0; d < 6; d++) expect(neighbor(from, d)).toBeDefined();
    }
  });

  it("does not change the segment it is given", () => {
    const before = segment();
    const { done } = run(before, UNREACHED);
    expect(done.played).toBe(3);
    expect(before).toEqual(segment());
  });

  it("exports the seam of the classes, not the parity tests' replayer", () => {
    expect(Object.keys(sim)).toContain("callDigest");
    expect(Object.keys(sim).filter((name) => /replay/i.test(name))).toEqual([]);
  });

  it("reaches nothing under src/parity/ from index.ts, by any import (a static scan)", () => {
    // A name check misses a replayer re-exported as `callDigest`: scan what the entry point imports,
    // and what those import, for a module under `parity/` (the `import ... from`, `export ... from`
    // and bare `import "..."` forms; a dynamic `import()` is refused outright)
    const root = new URL("../", import.meta.url);
    const seen = new Set<string>();
    const queue = ["index.ts"];
    while (queue.length > 0) {
      const file = queue.pop()!;
      if (seen.has(file)) continue;
      seen.add(file);
      const text = readFileSync(new URL(file, root), "utf8");
      expect(text, `${file} imports dynamically`).not.toMatch(/\bimport\s*\(/);
      for (const [, specifier] of text.matchAll(/(?:from|import)\s+["']([^"']+)["']/g)) {
        // A package (`@scure/starknet`) is not a module of `parity/`
        if (!specifier!.startsWith(".")) continue;
        // A module, or a folder's `index.ts` (`./body`)
        const module = new URL(`${specifier}.ts`, new URL(file, root));
        const target = existsSync(module)
          ? module
          : new URL(`${specifier}/index.ts`, new URL(file, root));
        queue.push(target.pathname.slice(root.pathname.length));
      }
    }
    expect(seen.has("segment/classes.ts")).toBe(true);
    expect([...seen].filter((file) => file.startsWith("parity/"))).toEqual([]);
  });
});
