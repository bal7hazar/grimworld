// What the action class holds beyond `act.jsonl` (CLI-02g-E, review t-0209): a carrier whose
// entries mix a `TILE` target with an entity one is not mirrored, a same-kind one runs
// (`parity/actcases.ts`' cases, which the mutation check also runs).

import { describe, expect, it } from "vitest";
import { CHECKS, holds } from "./parity/actcases";

describe("the action class beyond its table", () => {
  for (const check of CHECKS) {
    it(check.name, () => {
      expect(() => holds(check)).not.toThrow();
    });
  }
});
