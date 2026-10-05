import { tileKey } from "../render/fog";
import type { SandboxState } from "../sandbox/wiring";

/**
 * The state with every tile of its terrain explored (CLI-03n): the view then draws every revealed
 * tile, as before exploration by sight, for the tests of the ground and the obstacles.
 */
export function allExplored(state: SandboxState): SandboxState {
  const { width, height } = state.world.terrain;
  const explored = new Set<string>();
  for (let y = 0; y < height; y++) {
    for (let x = 0; x < width; x++) explored.add(tileKey({ x, y }));
  }
  return { ...state, explored };
}
