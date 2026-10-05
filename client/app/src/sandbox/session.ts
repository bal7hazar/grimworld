import type { Intent } from "../input/intent";
import type { ViewState } from "../render/view";
import type { SandboxWorld } from "./world";
import {
  type SandboxState,
  type FogMode,
  type TapOptions,
  applyIntent,
  cancelWalk,
  initialState,
  pathCost,
  toView,
  walkStep,
} from "./wiring";

/** What draws the view: the renderer in the browser and in tests. */
export interface ViewSink {
  setView(view: ViewState): void;
}

/** Timers and visibility of the host (the renderer's `FrameHost` is one). */
export interface WalkTimers {
  setTimer(callback: () => void, ms: number): number;
  clearTimer(handle: number): void;
  hidden(): boolean;
  /** Calls back on every change of visibility; returns the unsubscription. */
  onVisibilityChange(callback: () => void): () => void;
}

/** The minimal counter of the planned queue (design/11 *The queue*; the real HUD is CLI-05). */
export interface WalkInfo {
  /** Steps not walked yet. */
  readonly steps: number;
  /** Their cost in ticks (a placeholder: one tick a step). */
  readonly cost: number;
  /** Walked now; otherwise a preview, when `steps` > 0. */
  readonly walking: boolean;
  /** Why the last walk stopped, in one line, or "". */
  readonly stopped: string;
}

export interface SessionOptions extends TapOptions {
  /** The pace of a walk: one step every `stepMs`, the step animation's duration. */
  readonly stepMs: number;
  /** Called after every change of the state (a tap, a step, a stop). */
  readonly onChange?: () => void;
  /** How the map shows what was seen (CLI-03n); `sight` by default. */
  readonly fog?: FogMode;
}

/**
 * The sandbox's state over time: intents through the wiring, and a planned queue walked one step
 * at a time on the host's timers (design/02 *The planned queue*). The first step is played on the
 * tap that starts the walk, each next one `stepMs` later; nothing is scheduled once the walk ends.
 *
 * No step is played unseen: while the page is hidden the walk pauses (its timer is cleared, the
 * plan kept), and when the page shows again it resumes, the next step `stepMs` later. Resumed, not
 * stopped: nothing happened while hidden (no step was played, and goblins act only on the
 * adventurer's actions, D-40), and each resumed step evaluates the stop conditions as before.
 *
 * An inspect never touches the walk: no step played, no timer restarted.
 */
export class SandboxSession {
  private current: SandboxState;
  private timer: number | null = null;
  private options: SessionOptions;
  private readonly unsubscribe: () => void;

  constructor(
    world: SandboxWorld,
    private readonly sink: ViewSink,
    private readonly timers: WalkTimers,
    options: SessionOptions,
  ) {
    this.options = options;
    this.current = initialState(world);
    this.sink.setView(toView(this.current, options.fog));
    this.unsubscribe = timers.onVisibilityChange(() => this.visibilityChanged());
  }

  get state(): SandboxState {
    return this.current;
  }

  apply(intent: Intent): void {
    if (intent.kind === "inspect") {
      this.current = applyIntent(this.current, intent, this.options);
      this.show();
      return;
    }
    this.stopTimer();
    this.current = applyIntent(this.current, intent, this.options);
    this.show();
    if (this.current.walking) this.walkOn();
  }

  /** A tap on the counter. */
  cancel(): void {
    this.stopTimer();
    this.current = cancelWalk(this.current);
    this.show();
  }

  setWorld(world: SandboxWorld): void {
    this.stopTimer();
    this.current = initialState(world);
    this.show();
  }

  setPlayOnTap(playOnTap: boolean): void {
    this.options = { ...this.options, playOnTap };
  }

  playOnTap(): boolean {
    return this.options.playOnTap;
  }

  walk(): WalkInfo {
    return {
      steps: this.current.path.length,
      cost: pathCost(this.current),
      walking: this.current.walking,
      stopped: this.current.stopped,
    };
  }

  /** Whether a step of the walk is scheduled. */
  stepScheduled(): boolean {
    return this.timer !== null;
  }

  destroy(): void {
    this.stopTimer();
    this.unsubscribe();
  }

  private visibilityChanged(): void {
    if (this.timers.hidden()) {
      this.stopTimer();
    } else if (this.current.walking && this.timer === null) {
      this.timer = this.timers.setTimer(() => this.walkOn(), this.options.stepMs);
    }
  }

  private walkOn(): void {
    this.timer = null;
    // Hidden: paused; the step is played once the page shows again.
    if (this.timers.hidden()) return;
    this.current = walkStep(this.current);
    this.show();
    if (this.current.walking) {
      this.timer = this.timers.setTimer(() => this.walkOn(), this.options.stepMs);
    }
  }

  private stopTimer(): void {
    if (this.timer !== null) this.timers.clearTimer(this.timer);
    this.timer = null;
  }

  private show(): void {
    this.sink.setView(toView(this.current, this.options.fog));
    this.options.onChange?.();
  }
}
