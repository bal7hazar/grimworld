import { describe, expect, it } from "vitest";
import { ADVENTURER, type AdventurerSheet } from "../fixtures/hubs";
import { hudSheet, readHud } from "../params";
import { combatFixture } from "../../combat/fixture";
import { chipModel, fightSheet, hudModel, portraitLabel } from "./hudModel";

/** The status band's content (CLI-03l AC-5), on the pure model: no DOM. */
describe("hudModel", () => {
  it("shows the Vanguard's two meters, figures and adrenaline", () => {
    const model = hudModel(ADVENTURER, "atlas");
    expect(model.portrait).toEqual({
      profession: "vanguard",
      entry: "portrait_vanguard",
      label: "Wren, Vanguard level 4",
    });
    const [health, energy] = model.meters;
    expect(health).toMatchObject({ label: "Health", glyph: "♥", size: "big", text: "160 / 160" });
    expect(health.aria).toEqual({ "aria-valuemin": 0, "aria-valuemax": 160, "aria-valuenow": 160 });
    expect(energy).toMatchObject({ label: "Energy", glyph: "⚡", size: "small", text: "20 / 20" });
    expect(energy.aria).toEqual({ "aria-valuemin": 0, "aria-valuemax": 20, "aria-valuenow": 20 });
    expect(model.adrenaline).toEqual({ count: 0, label: "Adrenaline: 0 strikes" });
  });

  it("shows no adrenaline for a Warden, and its own portrait", () => {
    const warden: AdventurerSheet = { ...ADVENTURER, profession: "warden", adrenaline: null };
    const model = hudModel(warden, "atlas");
    expect(model.adrenaline).toBeNull();
    expect(model.portrait.entry).toBe("portrait_warden");
    expect(model.portrait.label).toBe("Wren, Warden level 4");
  });

  it("draws the plain portrait for an Arcanist even with the art, and for all without it", () => {
    const arcanist: AdventurerSheet = { ...ADVENTURER, profession: "arcanist", adrenaline: null };
    expect(hudModel(arcanist, "atlas").portrait.entry).toBe("plain");
    expect(hudModel(ADVENTURER, "plain").portrait.entry).toBe("plain");
    expect(hudModel({ ...ADVENTURER, profession: "cleric" }, "atlas").portrait.entry).toBe(
      "portrait_cleric",
    );
  });

  it("reads ?hud=low and ?hud=empty, and ignores an unknown value", () => {
    const low = hudModel(hudSheet(ADVENTURER, readHud("low")), "atlas");
    expect(low.meters.map((m) => m.text)).toEqual(["37 / 160", "5 / 20"]);
    expect(low.meters.map((m) => m.aria["aria-valuenow"])).toEqual([37, 5]);
    expect(low.adrenaline).toEqual({ count: 3, label: "Adrenaline: 3 strikes" });
    const empty = hudModel(hudSheet(ADVENTURER, readHud("empty")), "atlas");
    expect(empty.meters.map((m) => m.text)).toEqual(["0 / 160", "0 / 20"]);
    expect(empty.meters.map((m) => m.aria["aria-valuenow"])).toEqual([0, 0]);
    expect(empty.adrenaline!.count).toBe(0);
    expect(hudModel(hudSheet(ADVENTURER, readHud("half")), "atlas")).toEqual(
      hudModel(ADVENTURER, "atlas"),
    );
  });

  it("keeps aria-valuenow within its bounds; the text says the figure as given", () => {
    const over: AdventurerSheet = { ...ADVENTURER, health: { current: 200, max: 160 } };
    const [health] = hudModel(over, "atlas").meters;
    expect(health.aria["aria-valuenow"]).toBe(160);
    expect(health.text).toBe("200 / 160");
    expect(hudModel({ ...ADVENTURER, adrenaline: 1 }, "atlas").adrenaline!.label).toBe(
      "Adrenaline: 1 strike",
    );
  });

  it("names the inspected adventurer", () => {
    expect(portraitLabel({ name: "Maren", profession: "warden", level: 7 })).toBe(
      "Maren, Warden level 7",
    );
  });
});

describe("the combat screen's band (CLI-05c)", () => {
  it("shows the fight's figures", () => {
    const { adventurer } = combatFixture();
    const model = hudModel(fightSheet(ADVENTURER, adventurer), "atlas");
    expect(model.meters.map((m) => m.text)).toEqual(["118 / 160", "3 / 20"]);
    expect(model.adrenaline).toEqual({ count: 0, label: "Adrenaline: 0 strikes" });
    const warden: AdventurerSheet = { ...ADVENTURER, adrenaline: null };
    expect(fightSheet(warden, adventurer).adrenaline).toBeNull();
  });

  it("writes Wren's chips: a letter, then pips, charges and ticks left (§6.1)", () => {
    const chips = combatFixture().adventurer.chips.map(chipModel);
    expect(chips).toEqual([
      { letter: "B", figure: "4", label: "Bleeding, 4 ticks left", kind: "condition" },
      {
        letter: "R",
        figure: "+2 · 5",
        label: "Regeneration, +2 a tick, 5 ticks left",
        kind: "effect",
      },
      { letter: "▣", figure: "×2 · 6", label: "Block, 2 charges, 6 ticks left", kind: "effect" },
    ]);
  });

  it("an effect that lasts by charges only shows no ticks; a negative pip is signed", () => {
    const chip = {
      kind: "effect" as const,
      letter: "R",
      name: "Regeneration",
      ticks: null,
      charges: 3,
      pips: -1,
      source: null,
    };
    expect(chipModel(chip)).toMatchObject({
      figure: "−1 · ×3",
      label: "Regeneration, −1 a tick, 3 charges",
    });
    expect(chipModel({ ...chip, charges: 1, pips: null, ticks: 1 }).label).toBe(
      "Regeneration, 1 charge, 1 tick left",
    );
  });
});
