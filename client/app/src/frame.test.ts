import { describe, expect, it } from "vitest";
import { TILE_SIZE, buildFrame } from "./frame";

describe("buildFrame", () => {
  it("holds one static tile, sized like the art tiles", () => {
    const frame = buildFrame();
    expect(frame.children).toHaveLength(1);
    expect(frame.getLocalBounds().width).toBe(TILE_SIZE);
    expect(frame.getLocalBounds().height).toBe(TILE_SIZE);
  });
});
