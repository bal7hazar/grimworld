/**
 * The editor's palette of the pack (CLI-09e part 1): the kind table, the palette component, the
 * records a placement writes, the placement preview. Self-contained: nothing of the editor imports
 * it yet; part 2 wires it in (docs/reports/CLI-09e-palette.md).
 */
export {
  BRIDGES,
  BUILDINGS,
  type BridgeKind,
  type BuildingKind,
  type Category,
  FOOTPRINTS,
  type FootprintName,
  KINDS,
  type Kind,
  NPCS,
  type NpcKind,
  PROPS,
  type PropKind,
  SIDE,
  kindOf,
  kindTableProblems,
  spritesOf,
} from "./kinds";
export { CATEGORIES, INITIAL_PALETTE, type PaletteState, kindsMatching, paletteStep } from "./menu";
export { Palette, type PaletteProps, THUMB_BOX } from "./Palette";
export { type Preview, type PreviewRole, drawPreview, previewOf } from "./preview";
export {
  type BridgePlacement,
  type BridgeRecord,
  type BuildingPlacement,
  type BuildingRecord,
  type NpcPlacement,
  type NpcRecord,
  type PlacedRecord,
  type Placement,
  type PropPlacement,
  type PropRecord,
  type RecordResult,
  bridgeAt,
  doorChoices,
  doorSide,
  footprintAt,
  hexesOf,
  overlaps,
  recordOf,
} from "./records";
export { type ThumbArt, type ThumbLookup, thumbOf, thumbsFromLibrary } from "./thumbs";
