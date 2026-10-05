import { describe, expect, it } from "vitest";
import { BUILDINGS, NPCS, PROPS } from "./kinds";
import { CATEGORIES, INITIAL_PALETTE, kindsMatching, paletteStep } from "./menu";

describe("the palette's menus (CLI-09e)", () => {
  it("has one menu per category", () => {
    expect(CATEGORIES.map((c) => c.id)).toEqual(["building", "npc", "prop", "bridge"]);
    expect(CATEGORIES.map((c) => c.label)).toEqual(["Buildings", "Characters", "Props", "Bridges"]);
  });

  it("lists a category's kinds in the table's order, filtered by every word", () => {
    expect(kindsMatching("prop", "")).toEqual(PROPS);
    expect(kindsMatching("npc", "").map((k) => k.id)).toEqual(NPCS.map((k) => k.id));
    expect(kindsMatching("building", "HOUSE").map((k) => k.id)).toEqual([
      "house1",
      "house2",
      "house3",
      "bourgeois_house",
      "rural_house",
      "sacrificial_house",
      "small_house",
      "treehouse",
      "urban_house",
      "washhouse",
    ]);
    expect(kindsMatching("npc", "pawn ax").map((k) => k.id)).toEqual(["pawn_axe", "pawn_pickaxe"]);
    expect(kindsMatching("building", "market_hall").map((k) => k.id)).toEqual(["market_hall"]);
    expect(kindsMatching("bridge", "stone").map((k) => k.id)).toEqual(["stone_bridge"]);
    // A filter never reaches another category.
    expect(kindsMatching("prop", "castle")).toEqual([]);
    expect(kindsMatching("building", "").length).toBe(BUILDINGS.length);
  });

  it("keeps the filter and the selection across menus; selecting again clears", () => {
    let state = paletteStep(INITIAL_PALETTE, { type: "filter", filter: "tower" });
    state = paletteStep(state, { type: "open", category: "building" });
    state = paletteStep(state, { type: "select", id: "watchtower" });
    expect(state).toEqual({ category: "building", filter: "tower", selected: "watchtower" });
    state = paletteStep(state, { type: "open", category: "npc" });
    expect(state.selected).toBe("watchtower");
    expect(paletteStep(state, { type: "select", id: "watchtower" }).selected).toBeNull();
    expect(paletteStep(state, { type: "select", id: "pawn" }).selected).toBe("pawn");
    expect(paletteStep(state, { type: "select", id: "nothing" }).selected).toBeNull();
    expect(paletteStep(state, { type: "select", id: null }).selected).toBeNull();
  });
});
