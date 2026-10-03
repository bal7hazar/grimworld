/**
 * Text on the chrome (CLI-03i *The method* §5): WCAG 2.2 contrast, and the text each component
 * sets on which element of the art. `contrast.test.ts` checks every pair against the element's
 * centre colour as the build measured it (`tools/art/out/report.json`), copied as numbers.
 */

/** WCAG relative luminance of a 0xRRGGBB colour. */
export function luminance(rgb: number): number {
  const channel = (shift: number) => {
    const c = ((rgb >> shift) & 0xff) / 255;
    return c <= 0.04045 ? c / 12.92 : ((c + 0.055) / 1.055) ** 2.4;
  };
  return 0.2126 * channel(16) + 0.7152 * channel(8) + 0.0722 * channel(0);
}

/** WCAG contrast ratio of two colours, 1 to 21. */
export function contrast(a: number, b: number): number {
  const [hi, lo] = [luminance(a), luminance(b)].sort((x, y) => y - x) as [number, number];
  return (hi + 0.05) / (lo + 0.05);
}

/** AA minimums: body text, and large text (≥ 18.67 px bold or ≥ 24 px). */
export const AA = { body: 4.5, large: 3 } as const;

export const INK = 0x111111;
export const WHITE = 0xffffff;

/**
 * Each component's text: the element it sits on, the states it is seen in, its colour and whether
 * it is large text. The same colours as `chrome.css` (captions and muted lines: `.gw-text-*`).
 */
export const CHROME_TEXT: readonly {
  readonly component: string;
  readonly entry: string;
  readonly states: readonly ("regular" | "pressed")[];
  readonly colour: number;
  readonly large: boolean;
}[] = [
  {
    component: "Button action",
    entry: "button_blue",
    states: ["regular", "pressed"],
    colour: WHITE,
    large: true,
  },
  {
    component: "Button commit",
    entry: "button_red",
    states: ["regular", "pressed"],
    colour: WHITE,
    large: true,
  },
  { component: "Button quiet", entry: "paper", states: ["regular"], colour: INK, large: false },
  {
    component: "IconButton",
    entry: "round_blue",
    states: ["regular", "pressed"],
    colour: WHITE,
    large: true,
  },
  { component: "Panel paper", entry: "paper", states: ["regular"], colour: INK, large: false },
  {
    component: "Panel dark",
    entry: "paper_dark",
    states: ["regular"],
    colour: WHITE,
    large: false,
  },
  { component: "Panel scroll", entry: "scroll", states: ["regular"], colour: INK, large: false },
  {
    component: "Ribbon big blue",
    entry: "ribbon_big_blue",
    states: ["regular"],
    colour: WHITE,
    large: true,
  },
  {
    component: "Ribbon big red",
    entry: "ribbon_big_red",
    states: ["regular"],
    colour: WHITE,
    large: true,
  },
  {
    component: "Text on paper",
    entry: "paper",
    states: ["regular"],
    colour: 0x5b4636,
    large: false,
  },
  {
    component: "Text on scroll",
    entry: "scroll",
    states: ["regular"],
    colour: 0x5b4636,
    large: false,
  },
  {
    component: "Text on dark paper",
    entry: "paper_dark",
    states: ["regular"],
    colour: 0xe3e3e8,
    large: false,
  },
  {
    component: "Ribbon small yellow",
    entry: "ribbon_small_yellow",
    states: ["regular"],
    colour: INK,
    large: false,
  },
];
