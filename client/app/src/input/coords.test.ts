import { describe, expect, it } from "vitest";
import type { Tile } from "../render/view";
import {
  type Camera,
  HEX_RADIUS,
  TILE_WIDTH,
  fitScale,
  neighbours,
  pixelToTile,
  screenToTile,
  screenToWorld,
  tileToPixel,
  tileToScreen,
  worldToScreen,
} from "./coords";
import { LIBRARY_DIRECTIONS, LIBRARY_NEXT, libraryNext } from "../test/hexxLibrary";

const viewport = { width: 375, height: 812 };

/** Every tile of a 15 × 16 window whose origin is (ox, oy). */
function window(ox: number, oy: number): Tile[] {
  const tiles: Tile[] = [];
  for (let y = oy; y < oy + 16; y++) for (let x = ox; x < ox + 15; x++) tiles.push({ x, y });
  return tiles;
}

const index = (t: Tile) => t.y * 1_000_000 + t.x;

describe("pixel ↔ tile", () => {
  // Both parities of the origin's row (D-120 keeps it even; the functions are global), three zooms.
  const origins: [number, number][] = [
    [30, 44],
    [7, 13],
  ];
  const scales = [fitScale(viewport, 13), 1, 2.5];

  for (const [ox, oy] of origins) {
    for (const scale of scales) {
      it(`round trip on every tile of the window at (${ox}, ${oy}), scale ${scale.toFixed(3)}`, () => {
        const camera: Camera = { centre: tileToPixel({ x: ox + 7, y: oy + 8 }), scale };
        for (const tile of window(ox, oy)) {
          const screen = tileToScreen(camera, viewport, tile);
          expect(screenToTile(camera, viewport, screen)).toEqual(tile);
          const back = screenToWorld(camera, viewport, screen);
          const centre = tileToPixel(tile);
          expect(back.x).toBeCloseTo(centre.x, 9);
          expect(back.y).toBeCloseTo(centre.y, 9);
          // Points well inside the hex, toward each of its six corners, stay on the tile.
          for (let k = 0; k < 6; k++) {
            const angle = Math.PI / 6 + (k * Math.PI) / 3;
            const inside = {
              x: centre.x + 0.97 * HEX_RADIUS * Math.cos(angle),
              y: centre.y + 0.97 * HEX_RADIUS * Math.sin(angle),
            };
            expect(screenToTile(camera, viewport, worldToScreen(camera, viewport, inside))).toEqual(
              tile,
            );
          }
        }
      });
    }
  }

  it("resolves a tap on the edge of two tiles to the lower tile index", () => {
    for (const tile of [...window(30, 44), ...window(7, 13)]) {
      for (const next of LIBRARY_NEXT) {
        const other = next(tile);
        const a = tileToPixel(tile);
        const b = tileToPixel(other);
        const edge = { x: (a.x + b.x) / 2, y: (a.y + b.y) / 2 };
        const lower = index(tile) < index(other) ? tile : other;
        expect(pixelToTile(edge)).toEqual(lower);
      }
    }
  });

  it("resolves a tap on a corner of three tiles to the lowest tile index", () => {
    for (const tile of window(30, 44)) {
      const centre = tileToPixel(tile);
      for (let k = 0; k < 6; k++) {
        const angle = Math.PI / 6 + (k * Math.PI) / 3;
        const corner = {
          x: centre.x + HEX_RADIUS * Math.cos(angle),
          y: centre.y + HEX_RADIUS * Math.sin(angle),
        };
        const around = LIBRARY_NEXT.map((next) => next(tile))
          .filter((t) => {
            const c = tileToPixel(t);
            return Math.abs(Math.hypot(c.x - corner.x, c.y - corner.y) - HEX_RADIUS) < 1e-6;
          })
          .concat([tile]);
        expect(around).toHaveLength(3);
        const lowest = around.reduce((m, t) => (index(t) < index(m) ? t : m));
        expect(pixelToTile(corner)).toEqual(lowest);
      }
    }
  });

  it("puts neighbours one tile width apart, the library's neighbours adjacent on screen", () => {
    for (const tile of window(30, 44)) {
      for (const next of LIBRARY_NEXT) {
        const a = tileToPixel(tile);
        const b = tileToPixel(next(tile));
        expect(Math.hypot(a.x - b.x, a.y - b.y)).toBeCloseTo(TILE_WIDTH, 9);
      }
    }
  });
});

describe("fitScale", () => {
  it("fits the 13 tiles of sight across a 375-wide portrait viewport", () => {
    const scale = fitScale(viewport, 13);
    expect(13 * TILE_WIDTH * scale).toBeCloseTo(375, 9);
    expect(TILE_WIDTH * scale).toBeCloseTo(28.846, 3);
  });

  it("fits the height on a desktop window", () => {
    const scale = fitScale({ width: 1440, height: 900 }, 13);
    expect(13 * TILE_WIDTH * scale).toBeLessThan(1440);
    expect((12 * 1.5 + 2) * HEX_RADIUS * scale).toBeCloseTo(900, 9);
  });
});

describe("neighbours (CLI-03f)", () => {
  it("equals the library's next in the six directions, on even and odd rows", () => {
    for (const tile of [
      { x: 4, y: 4 },
      { x: 4, y: 5 },
      { x: 37, y: 12 },
      { x: 37, y: 13 },
    ]) {
      const around = neighbours(tile);
      for (const d of LIBRARY_DIRECTIONS) expect(around[d], `${d}`).toEqual(libraryNext(tile, d));
    }
  });
});
