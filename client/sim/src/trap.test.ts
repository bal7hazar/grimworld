// What the trap class holds beyond `trap.jsonl` (CLI-02g-D): the placer's caste is the source, not
// another goblin's (track game's known gap: the table's goblins are of one caste), and the class
// leaves its inputs as they were (`parity/trapcases.ts`' cases, which the mutation check also runs).

import { describe, expect, it } from "vitest";
import { CHECKS, holds } from "./parity/trapcases";

describe("the trap class beyond its table", () => {
  for (const check of CHECKS) {
    it(check.name, () => {
      expect(() => holds(check)).not.toThrow();
    });
  }
});
