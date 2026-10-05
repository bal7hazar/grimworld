import { describe, expect, it } from "vitest";
import type { Tile } from "../render/view";
import { type FitScore, chunkAt, evenRow, fitChunks, fitted, nudge, scoreAt } from "./fit";
import { FLOOR, type MapDocument, apply, createMap, erase, paint, sideOf } from "./model";

const zone = () => createMap({ kind: "zone", name: "Fit", location: 2, biome: "meadow" });

/** A map with a block of `w × h` floor hexes from `(x, y)`. */
function block(x: number, y: number, w: number, h: number, doc = zone()): MapDocument {
  const tiles: Tile[] = [];
  for (let dy = 0; dy < h; dy++)
    for (let dx = 0; dx < w; dx++) tiles.push({ x: x + dx, y: y + dy });
  apply(doc, paint(doc, tiles, { layer: "terrain", value: FLOOR }));
  return doc;
}

function best(doc: MapDocument): FitScore {
  const s = fitChunks(doc);
  if (typeof s === "string") throw new Error(s);
  return s;
}

describe("the parity rule (ADR-0006 §4, odd-r rows)", () => {
  it("every origin row is even: a residue's own row, or that row + 15", () => {
    expect([0, 1, 2, 13, 14].map(evenRow)).toEqual([0, 16, 2, 28, 14]);
    expect(evenRow(-1)).toBe(14);
    expect(evenRow(15)).toBe(0);
  });

  it("the move to global coordinates keeps every hex's neighbours; an odd row would not", () => {
    const doc = block(-37, -21, 20, 9);
    const fit = best(doc);
    expect(fit.y0 & 1).toBe(0);
    const global = (t: Tile, at: { x0: number; y0: number }) => {
      const g = chunkAt(t, at);
      return { x: g.x, y: g.y };
    };
    for (const t of [
      { x: -37, y: -21 },
      { x: -30, y: -16 },
    ]) {
      for (let side = 0; side < 6; side++) {
        expect(global(sideOf(t, side), fit)).toEqual(sideOf(global(t, fit), side));
      }
    }
    // Shifted by one row more: some neighbour lands elsewhere.
    const odd = { x0: fit.x0, y0: fit.y0 + 1 };
    const t = { x: -37, y: -21 };
    const kept = [0, 1, 2, 3, 4, 5].every((side) => {
      const a = global(sideOf(t, side), odd);
      const b = sideOf(global(t, odd), side);
      return a.x === b.x && a.y === b.y;
    });
    expect(kept).toBe(false);
  });
});

describe("Fit chunks (D-216): layouts computed by hand", () => {
  it("one hex: one chunk, partly filled, at origin (0, 0) by the stable rule", () => {
    const fit = best(block(0, 0, 1, 1));
    expect(fit).toMatchObject({ chunks: 1, partial: 1, width: 1, height: 1, x0: 0, y0: 0 });
    expect(fit.origin).toEqual({ x: 0, y: 0 });
  });

  it("a 15 × 15 block from (3, 4): one whole chunk, origin (3, 4)", () => {
    const fit = best(block(3, 4, 15, 15));
    expect(fit).toMatchObject({ chunks: 1, partial: 0, x0: 3, y0: 4, lowRow: false });
  });

  it("a 15 × 15 block from (0, 1): the odd row's even origin is 16, so an empty foot row", () => {
    const fit = best(block(0, 1, 15, 15));
    // Seams at y ≡ 1 (mod 15) on an even row: 16, i.e. global (0, 0) at y = -14.
    expect(fit.origin).toEqual({ x: 0, y: 16 });
    expect(fit).toMatchObject({ chunks: 1, partial: 0, x0: 0, y0: -14, height: 2, lowRow: true });
  });

  it("a 45 × 30 block far away and below zero: 3 × 2 whole chunks", () => {
    const fit = best(block(-1000, -600, 45, 30));
    expect(fit).toMatchObject({ chunks: 6, partial: 0, width: 3, height: 2 });
    expect((fit.x0 - -1000) % 15).toBe(0);
    expect(fit.y0).toBe(-600);
  });

  it("ties on the chunk count go to the fewest partly filled chunks", () => {
    // 16 × 15: two chunks at any column offset; one partly filled only at x ≡ 0 or 1.
    const doc = block(0, 0, 16, 15);
    const fit = best(doc);
    expect(fit).toMatchObject({ chunks: 2, partial: 1, origin: { x: 0, y: 0 } });
    expect(scoreAt(doc, { x: 5, y: 0 })).toMatchObject({ chunks: 2, partial: 2 });
    expect(scoreAt(doc, { x: 1, y: 0 })).toMatchObject({ chunks: 2, partial: 1 });
  });

  it("a plus sign: one chunk with the seams at (0, 0), three with them at (3, 2)", () => {
    // Arms of 7 around (7, 7): x 0..14 on row 7, y 0..14 on column 7.
    const doc = zone();
    const plus: Tile[] = [];
    for (let d = -7; d <= 7; d++) plus.push({ x: 7 + d, y: 7 }, { x: 7, y: 7 + d });
    apply(doc, paint(doc, plus, { layer: "terrain", value: FLOOR }));
    const fit = best(doc);
    expect(fit).toMatchObject({ chunks: 1, partial: 1, x0: 0, y0: 0 });
    // Columns cut at x = 3, rows at y = 2: the row's x 0..2 and 3..14 (two chunks), the column's
    // y 0..1 below the row's chunk (a third).
    expect(scoreAt(doc, { x: 3, y: 2 })).toMatchObject({ chunks: 3, partial: 3 });
  });

  it("a zone fits its inside hexes; nothing painted, nothing to fit", () => {
    const doc = block(0, 0, 30, 15);
    const right: Tile[] = [];
    for (let y = 0; y < 15; y++) for (let x = 15; x < 30; x++) right.push({ x, y });
    apply(doc, erase(doc, right, true));
    expect(best(doc)).toMatchObject({ chunks: 1, partial: 0 });
    expect(fitChunks(zone())).toBe("empty");
  });
});

describe("the nudge", () => {
  it("moves the origin by a hex, wrapping every 15, the row kept even, marked nudged", () => {
    expect(nudge({ x: 0, y: 0 }, 1, 0)).toEqual({ x: 1, y: 0, how: "nudged" });
    expect(nudge({ x: 0, y: 0 }, -1, 0)).toEqual({ x: 14, y: 0, how: "nudged" });
    expect(nudge({ x: 0, y: 0 }, 0, 1)).toEqual({ x: 0, y: 16, how: "nudged" });
    expect(nudge({ x: 0, y: 16 }, 0, 1)).toEqual({ x: 0, y: 2, how: "nudged" });
    expect(nudge({ x: 0, y: 0 }, 0, -1)).toEqual({ x: 0, y: 14, how: "nudged" });
  });

  it("the counts follow the nudged origin", () => {
    const doc = block(3, 4, 15, 15);
    doc.origin = { ...best(doc).origin, how: "fitted" };
    const before = fitted(doc);
    doc.origin = nudge(doc.origin, 1, 0);
    const after = fitted(doc);
    if (typeof before === "string" || typeof after === "string") throw new Error("unfitted");
    expect([before.chunks, before.partial]).toEqual([1, 0]);
    expect([after.chunks, after.partial]).toEqual([2, 2]);
  });
});

describe("the fitted records (§4.4, ADR-0006)", () => {
  it("the chunk set and the border chunks' masks, in the fitted map's indices", () => {
    const doc = block(100, 50, 16, 15);
    doc.origin = { ...best(doc).origin, how: "fitted" };
    const fit = fitted(doc);
    if (typeof fit === "string") throw new Error(fit);
    expect(fit.x0).toBe(100);
    expect(fit.y0).toBe(50);
    expect(fit.chunkSet).toEqual([0, 1]);
    expect([...fit.masks.keys()]).toEqual([1]);
    // Chunk 1's column 0, rows 0 to 14.
    expect(fit.masks.get(1)).toEqual(Array.from({ length: 15 }, (_, row) => 15 * row));
    expect(fit.problems).toEqual([]);
    expect(chunkAt({ x: 115, y: 64 }, fit)).toMatchObject({ cx: 1, cy: 0, chunk: 1, tile: 210 });
  });

  it("a fitted map past 15 chunks on a side (4 for a town) is a problem", () => {
    const doc = block(0, 0, 16 * 15, 1);
    doc.origin = { x: 0, y: 0, how: "fitted" };
    const fit = fitted(doc);
    if (typeof fit === "string") throw new Error(fit);
    expect(fit.problems[0]).toMatch(/16 × 1 chunks: a zone is at most 15 × 15/);
    const town = block(
      0,
      0,
      5 * 15,
      1,
      createMap({ kind: "town", name: "T", location: 1, biome: "meadow" }),
    );
    town.origin = { x: 0, y: 0, how: "nudged" };
    const t = fitted(town);
    expect(typeof t !== "string" && t.problems[0]).toMatch(/town is at most 4 × 4/);
    expect(fitted(zone())).toBe("unfitted");
  });
});

describe("the fit's time (AC-2)", () => {
  it("on a 225 × 225 painted map, well under a second (median of 5)", () => {
    const doc = block(-112, -112, 225, 225);
    expect(doc.hexes.size).toBe(225 * 225);
    const times: number[] = [];
    let fit: FitScore | null = null;
    for (let k = 0; k < 5; k++) {
      const start = performance.now();
      fit = best(doc);
      times.push(performance.now() - start);
    }
    times.sort((a, b) => a - b);
    const median = times[2]!;
    console.log(
      `[AC-2] fit of 225 × 225 painted hexes: median ${median.toFixed(1)} ms of 5 (${times.map((t) => t.toFixed(1)).join(", ")})`,
    );
    expect(fit).toMatchObject({ chunks: 225, partial: 0 });
    expect(median).toBeLessThan(1000);
  });
});
