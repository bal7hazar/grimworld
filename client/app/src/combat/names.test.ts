import { readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";
import { NAMES, itemName, skillName } from "./names";

/** The seed README's table of names, read in place: the copy must follow its single source. */
function table(): { skills: Map<number, string>; items: Map<number, string> } {
  const url = new URL("../../../../contracts/seed/README.md", import.meta.url);
  const skills = new Map<number, string>();
  const items = new Map<number, string>();
  for (const line of readFileSync(url, "utf8").split("\n")) {
    const cells = line.split("|").map((c) => c.trim());
    if (cells.length < 5) continue;
    const [, kind, ids, name] = cells;
    if (kind === "`SKILL`") skills.set(Number(ids), name!);
    if (kind === "`ITEM`" && /^[\d, ]+$/.test(ids!) && !name!.startsWith("Ingredient")) {
      for (const id of ids!.split(",")) items.set(Number(id), name!);
    }
  }
  return { skills, items };
}

describe("names (Q-1)", () => {
  it("gives the README table's name to every skill and potion it names", () => {
    const { skills, items } = table();
    expect([...skills.keys()].sort((a, b) => a - b)).toEqual(
      Array.from({ length: 22 }, (_, k) => k + 1),
    );
    expect([...items.keys()].sort((a, b) => a - b)).toEqual([1, 8, 15, 22, 23]);
    for (const [id, name] of skills) expect(skillName(id), `skill ${id}`).toBe(name);
    for (const [id, name] of items) expect(itemName(id), `item ${id}`).toBe(name);
  });

  it("names every id of a full build's bar and belt", () => {
    // `scripts/devnet_deploy.py --build full`: skills 1 and 4, a belt of healing ×2 and item 23 ×1
    const build = {
      bar: [1, 4, 0, 0, 0, 0, 0, 0],
      belt: [
        { item: 1, count: 2 },
        { item: 23, count: 1 },
      ],
    };
    for (const id of build.bar.filter((s) => s !== 0)) {
      expect(NAMES.skill(id)).not.toMatch(/^Skill \d+$/);
    }
    for (const { item } of build.belt) expect(NAMES.potion(item)).not.toMatch(/^Item \d+$/);
  });

  it("names an unknown id by its number", () => {
    expect(NAMES.skill(23)).toBe("Skill 23");
    expect(NAMES.potion(99)).toBe("Item 99");
  });

  it("names the other ingredients by their id", () => {
    expect(NAMES.potion(2)).toBe("Ingredient 2");
    expect(NAMES.potion(21)).toBe("Ingredient 21");
  });

  it("keeps the art's castes", () => {
    expect(NAMES.caste(1)).toBe("runt");
  });
});
