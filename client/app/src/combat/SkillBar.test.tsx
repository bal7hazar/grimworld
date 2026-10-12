import { renderToStaticMarkup } from "react-dom/server";
import { describe, expect, it } from "vitest";
import { combatFixture } from "./fixture";
import { SkillBar, initials } from "./SkillBar";

describe("the bar's monograms (CLI-05e)", () => {
  it("each slot's monogram is its own skill's initials", () => {
    const { bar } = combatFixture().adventurer;
    const html = renderToStaticMarkup(
      <SkillBar
        bar={bar}
        armed={null}
        activation={null}
        keys
        onSlot={() => {}}
        onInspect={() => {}}
      />,
    );
    const chunks = html
      .split("<button ")
      .slice(1)
      .filter((c) => c.includes("data-slot="));
    expect(chunks).toHaveLength(bar.length);
    chunks.forEach((chunk, i) => {
      const skill = bar[i]!.skill;
      if (skill === null) return;
      expect(chunk).toContain(`data-slot="${i}"`);
      expect(chunk).toContain(`aria-label="Skill ${i + 1}, ${skill.name}:`);
      // the monogram is the aria-hidden span that holds the two initials
      expect(chunk).toContain(`>${initials(skill.name!)}</span>`);
    });
    // The fixture's slot 3 is Charge ("Ch"), not the hobgoblin's Overhead Smash ("Ov")
    expect(bar[2]!.skill?.name).toBe("Charge");
    expect(initials("Charge")).toBe("Ch");
    expect(initials("Shield bash")).toBe("SB");
  });
});
