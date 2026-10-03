import { figureIntent, targetIntent } from "../../input/hubTaps";
import type { Intent, LoopIntent } from "../../input/intent";
import type { HubPlace, HubView } from "../../render/hubView";
import type { Tile } from "../../render/view";
import { hubTap, onDoor } from "../fixtures/hubWorld";
import type { WalkInfo, WalkTimers } from "../session";

/**
 * A hub's places open by walking onto their door (CLI-03f §5): the hub screen's hook on the zone's
 * map. `route` sees each map intent before the session: a tap on a place's hexes walks to its door
 * (and remembers the place as the walk's goal), a figure is inspected, a decor building or
 * a prop does nothing, anything else is the zone's own tap. `changed` sees every change of the
 * session: when the walk the player started ends with the adventurer on the goal's door,
 * the place opens, once, `openMs` later (the last step drawn). Presentation: nothing here is sent,
 * checked or stored.
 */
export class HubDoors {
  private goal: HubPlace | null = null;
  /** The walk toward the goal has taken a step (else a walk that ends is "no path"). */
  private started = false;
  /** The opening scheduled once the walk ended on the door. */
  private opening: number | null = null;

  constructor(
    private readonly view: HubView,
    private readonly dispatch: (intent: LoopIntent) => void,
    /** Where the player's adventurer stands now. */
    private readonly standing: () => Tile | null,
    private readonly timers: Pick<WalkTimers, "setTimer" | "clearTimer">,
    /** How long after the walk's last step the place opens: that step's animation. */
    private readonly openMs: number,
    private readonly log: (line: string) => void = () => {},
  ) {}

  destroy(): void {
    this.cancelOpening();
  }

  /** The place the walk goes to, if any. */
  goingTo(): HubPlace | null {
    return this.goal;
  }

  route(intent: Intent): Intent | null {
    const what = hubTap(this.view, intent.tile);
    if (what.kind === "figure") {
      this.dispatch(figureIntent(what.figure));
      return null;
    }
    if (intent.kind === "inspect") return intent;
    this.cancelOpening();
    this.goal = null;
    this.started = false;
    switch (what.kind) {
      case "place": {
        const { place } = what;
        if (onDoor(place, this.standing())) {
          this.log(`${place.label}: on its door, open`);
          this.dispatch(targetIntent(place.target));
          return null;
        }
        this.goal = place;
        this.log(`${place.label}: walk to its door (${place.at.x}, ${place.at.y})`);
        return { kind: "tile", tile: place.at };
      }
      case "decor":
      case "prop":
        this.log(`${what.kind} ${what.id}: no target`);
        return null;
      case "ground":
        return intent;
    }
  }

  /** After every change of the session: the adventurer's hex and the walk. */
  changed(tile: Tile | null, walk: WalkInfo): void {
    const place = this.goal;
    if (!place) return;
    if (walk.walking) {
      if (!onDoor(place, tile) || walk.steps > 0) this.started = true;
      return;
    }
    if (walk.steps > 0) return; // a preview (tap twice): not walked yet
    this.goal = null;
    if (onDoor(place, tile)) {
      this.opening = this.timers.setTimer(() => {
        this.opening = null;
        this.dispatch(targetIntent(place.target));
      }, this.openMs);
    } else if (!this.started) {
      // No path to the door: the place opens at once rather than never.
      this.log(`${place.label}: no path to its door, open at once`);
      this.dispatch(targetIntent(place.target));
    }
  }

  private cancelOpening(): void {
    if (this.opening !== null) this.timers.clearTimer(this.opening);
    this.opening = null;
  }
}
