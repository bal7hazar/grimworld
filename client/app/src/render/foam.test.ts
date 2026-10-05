import { Rectangle, Texture, TextureSource } from "pixi.js";
import { describe, expect, it } from "vitest";
import { tileToPixel } from "../input/coords";
import { FOAM_AXIS, FoamMesh, foamDiagonal, foamFrame, overlaps, readWater } from "./foam";
import { FOAM_SIZE, type FoamPiece, acrossSide, waterFoam } from "./ground";
import { BAKE_CHUNK } from "./renderer";
import type { GroundKind, Tile, ViewTile } from "./view";

/** Sixteen frames of `FOAM_SIZE` in one row of a page, as the atlas packs `foam_c/loop`. */
function loopFrames(count = 16): Texture[] {
  const source = new TextureSource({ width: count * (FOAM_SIZE + 2), height: FOAM_SIZE + 4 });
  return Array.from(
    { length: count },
    (_, i) =>
      new Texture({ source, frame: new Rectangle(i * (FOAM_SIZE + 2), 2, FOAM_SIZE, FOAM_SIZE) }),
  );
}

/** Water West of x = 10, land from there: a coast along a column, across chunk edges. */
function coast(): ViewTile[] {
  const tiles: ViewTile[] = [];
  for (let y = 0; y < 2 * BAKE_CHUNK; y++) {
    for (let x = 0; x < 20; x++) {
      const ground: GroundKind = x >= 10 ? "water" : "grass";
      tiles.push({ x, y, kind: ground === "water" ? "wall" : "floor", ground });
    }
  }
  return tiles;
}

/** The frame a mesh shows on a piece, read back from its texture coordinates. */
function frameOn(mesh: FoamMesh, frames: readonly Texture[], piece: FoamPiece): number {
  let v = 0;
  for (const p of mesh.pieces) {
    if (p === piece) break;
    v += p.points.length / 2;
  }
  const uvs = mesh.mesh.geometry.getBuffer("aUV").data as Float32Array;
  const u = uvs[2 * v]! * frames[0]!.source.width;
  const local = piece.points[0]! - piece.origin.x;
  const x = u - local;
  const index = frames.findIndex((f) => Math.abs(f.frame.x - x) < 1e-3);
  expect(index).toBeGreaterThanOrEqual(0);
  return index;
}

describe("the foam's phase (CLI-03o)", () => {
  it(`the same frame along a diagonal (${FOAM_AXIS}), one frame later on the next`, () => {
    // Along a line of constant q + r: the six directions, two of them keep it.
    const start = { x: 5, y: 6 };
    const same = [0, 1, 2, 3, 4, 5]
      .map((side) => acrossSide(start, side))
      .filter((t) => foamDiagonal(t) === foamDiagonal(start));
    expect(same).toHaveLength(2);
    // The two sides on that diagonal are opposite: a straight line through the hex.
    const [a, b] = same.map(tileToPixel);
    const c = tileToPixel(start);
    expect(a!.x + b!.x).toBeCloseTo(2 * c.x, 9);
    expect(a!.y + b!.y).toBeCloseTo(2 * c.y, 9);
    for (let t = 0; t < 40; t++) {
      for (const tile of same) expect(foamFrame(t, tile, 16)).toBe(foamFrame(t, start, 16));
    }
    // Each other neighbour is one diagonal on: one frame apart, either way.
    for (const side of [0, 1, 2, 3, 4, 5]) {
      const next = acrossSide(start, side);
      const step = foamDiagonal(next) - foamDiagonal(start);
      expect([-1, 0, 1]).toContain(step);
      for (let t = 0; t < 40; t++) {
        expect(foamFrame(t, next, 16)).toBe((foamFrame(t, start, 16) + step + 16) % 16);
      }
    }
  });

  it("one frame per tick, looping over the frames, negative coordinates included", () => {
    for (const tile of [
      { x: 0, y: 0 },
      { x: -7, y: -3 },
      { x: 31, y: -17 },
    ]) {
      for (let t = -20; t < 40; t++) {
        const f = foamFrame(t, tile, 16);
        expect(f).toBeGreaterThanOrEqual(0);
        expect(f).toBeLessThan(16);
        expect(foamFrame(t + 1, tile, 16)).toBe((f + 1) % 16);
        expect(foamFrame(t + 16, tile, 16)).toBe(f);
      }
    }
  });

  it("depends on the tile only: the axes give their own index", () => {
    const tile: Tile = { x: 4, y: 7 };
    const q = 4 - Math.floor(7 / 2);
    expect(foamDiagonal(tile, "q")).toBe(q);
    expect(foamDiagonal(tile, "r")).toBe(7);
    expect(foamDiagonal(tile, "q+r")).toBe(q + 7);
  });
});

describe("the foam's meshes (CLI-03o)", () => {
  const frames = loopFrames();
  const tiles = coast();
  const at = new Map(tiles.map((t) => [`${t.x},${t.y}`, t.ground ?? "grass"] as const));
  const pieces = waterFoam(tiles, { around: (t) => at.get(`${t.x},${t.y}`) ?? null });

  it("each piece shows its source's frame; the frame moves on with the clock", () => {
    const mesh = new FoamMesh(pieces, frames);
    expect(pieces.length).toBeGreaterThan(0);
    for (const tick of [0, 1, 7, 15, 16, 123]) {
      mesh.show(tick);
      for (const piece of pieces.slice(0, 50)) {
        expect(frameOn(mesh, frames, piece)).toBe(foamFrame(tick, piece.source, 16));
      }
    }
    // Still: frame 0 on every piece, whatever its diagonal.
    mesh.show(null);
    for (const piece of pieces.slice(0, 50)) expect(frameOn(mesh, frames, piece)).toBe(0);
    mesh.destroy();
  });

  it("a point maps to its cell's pixel: (frame's corner + its offset in the cell) over the page", () => {
    const mesh = new FoamMesh(pieces, frames);
    mesh.show(3);
    const positions = mesh.mesh.geometry.getBuffer("aPosition").data as Float32Array;
    const uvs = mesh.mesh.geometry.getBuffer("aUV").data as Float32Array;
    const { width, height } = frames[0]!.source;
    let v = 0;
    for (const piece of pieces) {
      const frame = frames[foamFrame(3, piece.source, 16)]!.frame;
      for (let k = 0; k < piece.points.length; k += 2, v++) {
        expect(positions[2 * v]).toBeCloseTo(piece.points[k]!, 3);
        expect(uvs[2 * v]! * width).toBeCloseTo(frame.x + piece.points[k]! - piece.origin.x, 2);
        expect(uvs[2 * v + 1]! * height).toBeCloseTo(
          frame.y + piece.points[k + 1]! - piece.origin.y,
          2,
        );
      }
    }
    mesh.destroy();
  });

  it("seamless across chunks: one source's pieces in two chunks' meshes show the same frame", () => {
    const chunk = (p: FoamPiece) => Math.floor(p.over.y / BAKE_CHUNK);
    const north = new FoamMesh(
      pieces.filter((p) => chunk(p) === 0),
      frames,
    );
    const south = new FoamMesh(
      pieces.filter((p) => chunk(p) === 1),
      frames,
    );
    const across = north.pieces.filter((p) =>
      south.pieces.some((q) => q.source.x === p.source.x && q.source.y === p.source.y),
    );
    expect(across.length).toBeGreaterThan(0);
    for (const tick of [0, 5, 11]) {
      north.show(tick);
      south.show(tick);
      for (const p of across) {
        const q = south.pieces.find((s) => s.source.x === p.source.x && s.source.y === p.source.y)!;
        expect(frameOn(north, frames, p)).toBe(frameOn(south, frames, q));
      }
    }
    north.destroy();
    south.destroy();
  });

  it("shows a frame once: the same tick changes nothing", () => {
    const mesh = new FoamMesh(pieces, frames);
    expect(mesh.show(4)).toBe(true);
    expect(mesh.show(4)).toBe(false);
    expect(mesh.show(20)).toBe(false); // 20 ≡ 4 over 16 frames
    expect(mesh.show(5)).toBe(true);
    expect(mesh.show(null)).toBe(true);
    expect(mesh.show(null)).toBe(false);
    mesh.destroy();
  });

  it("its bounds hold its pieces", () => {
    const mesh = new FoamMesh(pieces, frames);
    for (const { points } of pieces) {
      for (let k = 0; k < points.length; k += 2) {
        expect(points[k]!).toBeGreaterThanOrEqual(mesh.bounds.x - 1e-3);
        expect(points[k]!).toBeLessThanOrEqual(mesh.bounds.x + mesh.bounds.width + 1e-3);
      }
    }
    expect(overlaps(mesh.bounds, new Rectangle(mesh.bounds.x + 1, mesh.bounds.y + 1, 2, 2))).toBe(
      true,
    );
    expect(overlaps(mesh.bounds, new Rectangle(mesh.bounds.x - 10, mesh.bounds.y, 10, 10))).toBe(
      false,
    );
    mesh.destroy();
  });
});

describe("the foam over the chunks, trimmed (CLI-03o)", () => {
  it("never reaches into a land hex: the grass, grown, still covers the foam's inner part", () => {
    const tiles = coast();
    const at = new Map(tiles.map((t) => [`${t.x},${t.y}`, t.ground ?? "grass"] as const));
    const pieces = waterFoam(tiles, { around: (t) => at.get(`${t.x},${t.y}`) ?? null });
    for (const piece of pieces) {
      const c = tileToPixel(piece.over);
      for (let side = 0; side < 6; side++) {
        const next = acrossSide(piece.over, side);
        if ((at.get(`${next.x},${next.y}`) ?? null) === "water") continue;
        const angle = ((side + 1) * Math.PI) / 3;
        for (let k = 0; k < piece.points.length; k += 2) {
          const d =
            (piece.points[k]! - c.x) * Math.cos(angle) +
            (piece.points[k + 1]! - c.y) * Math.sin(angle);
          // The land hex grown by half a pixel reaches 0.43 px across the side.
          expect(d).toBeLessThanOrEqual(32 - 0.5 * Math.cos(Math.PI / 6) + 1e-6);
        }
      }
    }
  });
});

describe("?water= (CLI-03o)", () => {
  it("still only for `still`", () => {
    expect(readWater("?water=still")).toBe("still");
    expect(readWater("?fixture=zone&water=still")).toBe("still");
    expect(readWater("")).toBe("loop");
    expect(readWater("?water=loop")).toBe("loop");
    expect(readWater("?water=STILL")).toBe("loop");
  });
});
