/**
 * The actions of a batch and the felt `Instances.play` takes them in: the encoder of
 * `contracts/logic/src/actions.cairo` (`encode_action` :45, `encode_batch` :139), whose layout and
 * refusals are its documentation. No vector table covers it: `actions.test.ts` holds it to the Cairo
 * tests' words (`contracts/logic/tests/test_actions.cairo`).
 *
 * `PlayAction` has the shape of client/sim's `Action` (`segment/serde.ts`), so a batch passes to the
 * mirror as it is.
 */

/** `Target`: an entity (`tile` false) or a tile. */
export type Target = { tile: boolean; value: number };

/** `actions::Action`: what one felt of `play` carries. */
export type PlayAction =
  | { kind: "move"; direction: number }
  | { kind: "turn"; direction: number }
  | { kind: "wait" }
  | { kind: "attack"; entity: number }
  | { kind: "skill"; slot: number; target: Target }
  | { kind: "item"; slot: number; entity: number }
  | { kind: "interact"; tile: number };

/**
 * An action that draws Fate from the transaction's hash and ends a batch (loot, open, mine, barter,
 * the entry of a gate): its own entrypoint, never in `play`'s felt, so never previewed.
 */
export type FateAction = { kind: "loot" | "open" | "mine" | "barter" | "entry" };

export type BatchAction = PlayAction | FateAction;

/** `types::MAX_ACTIONS`. */
export const MAX_ACTIONS = 10;

const FATE = new Set<string>(["loot", "open", "mine", "barter", "entry"]);

export function isFate(action: BatchAction): action is FateAction {
  return FATE.has(action.kind);
}

const P24 = 1n << 24n;
const TWO_POW_128 = 1n << 128n;

/** An argument of `width` bits: the Cairo type's range, else `undefined`. */
function bits(value: number, width: number): bigint | undefined {
  return Number.isInteger(value) && value >= 0 && value < 2 ** width ? BigInt(value) : undefined;
}

/** `encode_action`: the 24 bits of an action; `undefined` for an argument out of range. */
export function encodeAction(action: PlayAction): bigint | undefined {
  switch (action.kind) {
    case "move":
    case "turn": {
      const d = bits(action.direction, 8);
      if (d === undefined || d > 5n) return undefined;
      return (action.kind === "move" ? 0n : 1n) + d * 8n;
    }
    case "wait":
      return 2n;
    case "attack": {
      const entity = bits(action.entity, 16);
      return entity === undefined ? undefined : 3n + entity * 8n;
    }
    case "skill": {
      const slot = bits(action.slot, 8);
      const value = bits(action.target.value, 16);
      if (slot === undefined || slot > 7n || value === undefined) return undefined;
      return 4n + slot * 8n + (action.target.tile ? 64n : 0n) + value * 128n;
    }
    case "item": {
      const slot = bits(action.slot, 8);
      const entity = bits(action.entity, 16);
      if (slot === undefined || slot > 3n || entity === undefined) return undefined;
      return 5n + slot * 8n + entity * 32n;
    }
    case "interact": {
      const tile = bits(action.tile, 16);
      return tile === undefined ? undefined : 6n + tile * 8n;
    }
  }
}

/**
 * `encode_batch`: the count in bits 0 to 3, actions 0 to 4 at `4 + 24 i`, 5 to 9 at
 * `128 + 24 (i − 5)`; `undefined` for an empty or longer batch, or an action out of range.
 */
export function encodeBatch(actions: readonly PlayAction[]): bigint | undefined {
  if (actions.length === 0 || actions.length > MAX_ACTIONS) return undefined;
  let low = BigInt(actions.length);
  let high = 0n;
  let factor = 0x10n;
  for (const [i, action] of actions.entries()) {
    if (i === 5) factor = 1n;
    const code = encodeAction(action);
    if (code === undefined) return undefined;
    if (i < 5) low += code * factor;
    else high += code * factor;
    factor *= P24;
  }
  return low + high * TWO_POW_128;
}
