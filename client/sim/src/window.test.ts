import { describe, expect, it } from "vitest";
import { P } from "./felt";
import { SIZE, WIDTH, shape, shapes, tiles } from "./window";

// `tiles` has no vector table: the cases of `window.cairo`'s `test_tiles` and the `tiles` reads of
// `test_shapes_edges`.
const OPEN = (1n << BigInt(SIZE)) - 1n;
const at = (x: number, y: number): number => y * WIDTH + x;
const bit = (p: number): bigint => 1n << BigInt(p);

describe("tiles", () => {
  it("lists every set bit, ascending, across both limbs", () => {
    expect(tiles(0n)).toEqual([]);
    expect(tiles(OPEN)).toEqual(Array.from({ length: SIZE }, (_, p) => p));
    const some = [0, 63, 64, 127, 128, 200, 239].reduce((mask, p) => mask + bit(p), 0n);
    expect(tiles(some)).toEqual([0, 63, 64, 127, 128, 200, 239]);
  });

  it("reads a shape at the corner and next to walls", () => {
    expect(tiles(shape(OPEN, shapes.DISC_1, at(0, 0)))).toEqual([at(0, 0), at(1, 0), at(0, 1)]);
    const walls = OPEN - bit(at(8, 8)) - bit(at(6, 9)) - bit(at(7, 8));
    expect(tiles(shape(walls, shapes.DISC_1, at(7, 8)))).toEqual([
      at(6, 7),
      at(7, 7),
      at(6, 8),
      at(7, 9),
    ]);
  });

  it("takes a felt, as Cairo's signature", () => {
    expect(tiles(bit(250))).toEqual([250]);
    expect(() => tiles(P)).toThrow(RangeError);
    expect(() => tiles(-1n)).toThrow(RangeError);
  });
});
