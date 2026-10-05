import { type Category, KINDS, type Kind } from "./kinds";

/** The palette's menus (CLI-09e): one per category, in this order. */
export const CATEGORIES: readonly { readonly id: Category; readonly label: string }[] = [
  { id: "prop", label: "Props" },
  { id: "building", label: "Buildings" },
  { id: "npc", label: "NPCs" },
  { id: "bridge", label: "Bridges" },
];

/**
 * The kinds of a category that match a filter: every word of it (case and `_` ignored) found in the
 * kind's label or id. An empty filter keeps them all, in the table's order.
 */
export function kindsMatching(
  category: Category,
  filter: string,
  table: readonly Kind[] = KINDS,
): Kind[] {
  const words = filter.toLowerCase().replace(/_/g, " ").split(/\s+/).filter(Boolean);
  return table.filter((kind) => {
    if (kind.category !== category) return false;
    const text = `${kind.label} ${kind.id}`.toLowerCase().replace(/_/g, " ");
    return words.every((word) => text.includes(word));
  });
}

/** What the palette shows: its open menu, its filter, the selected kind's id. */
export interface PaletteState {
  readonly category: Category;
  readonly filter: string;
  readonly selected: string | null;
}

export const INITIAL_PALETTE: PaletteState = { category: "prop", filter: "", selected: null };

export type PaletteAction =
  | { readonly type: "open"; readonly category: Category }
  | { readonly type: "filter"; readonly filter: string }
  | { readonly type: "select"; readonly id: string | null };

/**
 * The palette's state after an action. Opening a menu keeps the filter and the selection: the
 * selected kind stays the one placed until another is chosen or the selection cleared. Selecting
 * the selected kind again clears it; an id that is not a kind clears it too.
 */
export function paletteStep(
  state: PaletteState,
  action: PaletteAction,
  table: readonly Kind[] = KINDS,
): PaletteState {
  switch (action.type) {
    case "open":
      return { ...state, category: action.category };
    case "filter":
      return { ...state, filter: action.filter };
    case "select": {
      const known = action.id !== null && table.some((kind) => kind.id === action.id);
      const id = known && action.id !== state.selected ? action.id : null;
      return { ...state, selected: id };
    }
  }
}
