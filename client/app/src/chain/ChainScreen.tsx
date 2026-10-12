import { type CSSProperties, useEffect, useRef, useState } from "react";
import { AccountError } from "../account";
import { installKeys } from "../sandbox/keyScope";
import { type KeyCommand, verticalDirection } from "../input/keys";
import type { Intent } from "../input/intent";
import { type BlockId, createReader } from "../preview/read";
import { createRpcSimulator } from "../preview/rpc";
import type { Facing } from "../render/view";
import { RoomSandbox, Sandbox } from "../sandbox/Sandbox";
import type { SandboxController } from "../sandbox/controller";
import { ChainPanel } from "./ChainPanel";
import { type ChainController, createChainController } from "./ChainController";
import { ChainRefused, type Opened, fetchDeployment, openChain } from "./network";
import { type ChainParam, type ChainRefusal, logRefusal, refusalLine } from "./params";
import { type ChainState, createSentReads, readState, sendBatch } from "./send";
import { type Player, SetupFailed, restore } from "./setup";
import { type Stages, createStages } from "./stages";
import { memberPlace } from "./world";

/**
 * The chain mode's screen. CLI-11a: it loads the deployment, opens the node (the checks of §2.2 and
 * §2.3) and restores or makes the burner's player (§3.4); a refusal leaves the sandbox on screen
 * with one line over it, and one `grimworld.chain-refused` record in the console. CLI-11c: it then
 * draws the instance the chain holds (the sandbox's own renderer on `world.ts`'s world, §6.2), turns
 * the inputs into the batch (`ChainController`, §4.1), shows the three stages of its preview in the
 * panel (§5), and sends it on `B` (§4.3), entering again on `N` once the instance closed (§3.4).
 *
 * Loaded by `App.tsx` with a dynamic `import()` only, so the sandbox's bundle does not carry
 * starknet.js.
 */

type Shown =
  | { readonly kind: "opening" }
  | { readonly kind: "refused"; readonly reason: ChainRefusal }
  | { readonly kind: "failed"; readonly what: string }
  | { readonly kind: "ready"; readonly session: Session };

/** What a started mode holds: the player, the batch's model and its inputs. */
interface Session {
  readonly player: Player;
  readonly stages: Stages;
  readonly controller: ChainController;
}

/**
 * What failed, in words that carry no value of the node or the key: a setup step and its status,
 * an account error's code, or the error's class.
 */
function failure(error: unknown): string {
  if (error instanceof SetupFailed) return `${error.step} ${error.status}`;
  if (error instanceof AccountError) return error.code;
  return error instanceof Error ? error.name : "unknown";
}

/**
 * One start per node URL for the page's life: React's development double effect must not register
 * or enter twice.
 */
const started = new Map<string, Promise<Shown>>();

/**
 * The batch's model on the player's instance: the state read, the simulator, the send through the
 * guarded provider (never `Opened.rpc`), and `N` as `restore` again (step 4 of §3.4) and a new read.
 */
async function begin(
  opened: Opened,
  nodeUrl: string,
  first: Player,
  setup: Parameters<typeof restore>[0],
): Promise<Session> {
  const { instances, registry } = opened.deployment.contracts;
  let player = first;
  const ids = () => ({
    instances,
    registry,
    instanceId: player.instanceId,
    adventurerId: player.adventurerId,
  });
  const load = () => readState(opened.reader, ids());
  const initial = await load();
  const stages = createStages(initial, {
    simulator: createRpcSimulator({ nodeUrl, sender: player.address }),
    send: (input) =>
      sendBatch(input, {
        account: opened.provider,
        assertChain: opened.assertChain,
        reads: createSentReads(nodeUrl),
        readerAt: (block: BlockId) => createReader({ nodeUrl, block }),
        registry,
      }),
    load,
  });
  const controller = createChainController({
    stages,
    enter: async () => {
      player = await restore(setup);
      return load();
    },
  });
  return { player, stages, controller };
}

function start(nodeUrl: string): Promise<Shown> {
  let opening = started.get(nodeUrl);
  if (opening === undefined) {
    opening = (async (): Promise<Shown> => {
      try {
        const deployment = await fetchDeployment();
        const opened = await openChain(nodeUrl, deployment);
        const { provider, reader } = opened;
        const setup = { provider, reader, ...deployment.contracts };
        const player = await restore(setup);
        return { kind: "ready", session: await begin(opened, nodeUrl, player, setup) };
      } catch (error) {
        // A refusal before a send or a funding reaches here inside the account's error
        const refused = error instanceof AccountError ? error.cause : error;
        if (refused instanceof ChainRefused) return { kind: "refused", reason: refused.reason };
        return { kind: "failed", what: failure(error) };
      }
    })();
    started.set(nodeUrl, opening);
  }
  return opening;
}

export default function ChainScreen({ param }: { param: Exclude<ChainParam, { kind: "none" }> }) {
  const [shown, setShown] = useState<Shown>(() =>
    param.kind === "refused" ? { kind: "refused", reason: param.reason } : { kind: "opening" },
  );

  useEffect(() => {
    if (param.kind !== "chain") return;
    let alive = true;
    void start(param.nodeUrl).then((next) => {
      if (alive) setShown(next);
    });
    return () => {
      alive = false;
    };
  }, [param]);

  const refused = shown.kind === "refused" ? shown.reason : null;
  useEffect(() => {
    if (refused !== null) logRefusal(refused);
  }, [refused]);

  if (shown.kind === "refused") {
    return (
      <>
        <Sandbox />
        <div style={styles.line} data-chain="refused">
          {refusalLine(shown.reason)}
        </div>
      </>
    );
  }
  if (shown.kind === "ready") return <Play session={shown.session} />;
  return (
    <div style={styles.page}>
      <div style={styles.line} data-chain={shown.kind}>
        {shown.kind === "opening" && "chain mode: opening…"}
        {shown.kind === "failed" && `chain mode: setup failed (${shown.what})`}
      </div>
    </div>
  );
}

/** The chain states drawn so far: a new one is a new map (the sandbox's room is mounted on one). */
const generations = new WeakMap<ChainState, number>();
let generation = 0;
const generationOf = (chain: ChainState): number => {
  let known = generations.get(chain);
  if (known === undefined) {
    known = ++generation;
    generations.set(chain, known);
  }
  return known;
};

/**
 * The map and the panel. The map is the sandbox's room on the world of the chain's last state; it
 * is mounted again when a new state is installed (the start, each sent batch, entering again) and
 * not between two sends, where stage 1 is a layer of markers over it (`Ghosts`).
 */
function Play({ session }: { session: Session }) {
  const { stages, controller } = session;
  const [chain, setChain] = useState(() => stages.get().chain);
  const map = useRef<SandboxController | null>(null);
  const ghosts = useRef<HTMLDivElement>(null);

  useEffect(() => installKeys(), []);
  useEffect(
    () =>
      stages.subscribe((state) => {
        if (state.chain !== chain) {
          // The map is mounted again: the one drawn is destroyed, and the new one reports itself
          map.current = null;
          controller.reset();
          setChain(state.chain);
        }
        place();
      }),
    // `place` reads the refs only
    [stages, controller, chain],
  );
  useEffect(() => controller.subscribe(() => place()), [controller]);

  /** Places stage 1's markers over the map, with the camera as last drawn. */
  function place() {
    const layer = ghosts.current;
    const view = map.current;
    if (!layer) return;
    const { steps, end } = view ? controller.ghosts() : { steps: [], end: undefined };
    const marks = [
      ...steps.map((tile) => ({ tile, kind: "step", text: "" })),
      ...(end ? [{ tile: end.tile, kind: "end", text: String(end.facing) }] : []),
    ];
    while (layer.children.length < marks.length) layer.append(document.createElement("div"));
    while (layer.children.length > marks.length) layer.lastElementChild?.remove();
    marks.forEach((mark, i) => {
      const element = layer.children[i] as HTMLElement;
      if (!view) return;
      const at = view.tileOnScreen(mark.tile);
      const size = (mark.kind === "end" ? 36 : 22) * view.scale();
      Object.assign(element.style, styles.ghost, {
        transform: `translate(${at.x}px, ${at.y}px) translate(-50%, -50%)`,
        width: `${size}px`,
        height: `${size}px`,
        background: mark.kind === "end" ? "rgba(107,199,255,0.25)" : "transparent",
      });
      element.dataset.ghost = mark.kind;
      element.textContent = mark.text;
    });
    layer.dataset.ghosts = `${steps.length}`;
    layer.dataset.end = end ? `${end.tile.x},${end.tile.y},${end.facing}` : "";
  }

  const route = (intent: Intent): Intent | null => {
    // An inspect is the map's own; a tap is the batch's, but a first tap on a goblin selects it
    if (intent.kind !== "tile") return intent;
    return controller.tap(intent.tile).kind === "select" ? intent : null;
  };

  const onKey = (command: KeyCommand, keys: { handle(c: KeyCommand): boolean }): boolean => {
    switch (command.kind) {
      case "step": {
        const { member } = stages.get().chain.mirror;
        const here = stages.get().chain.mirror.view.members[member];
        const facing: Facing = here ? memberPlace(here.state).facing : 0;
        controller.step(
          "direction" in command ? command.direction : verticalDirection(facing, command.vertical),
        );
        return true;
      }
      case "wait":
        controller.wait();
        return true;
      case "turn":
        controller.armTurn();
        return true;
      case "send":
        controller.send();
        return true;
      case "again":
        void controller.enterAgain();
        return true;
      case "leave":
        controller.unbound();
        return true;
      case "escape":
        return controller.disarm() || keys.handle(command);
      case "zoom":
      case "recentre":
        return keys.handle(command);
      default:
        return false;
    }
  };

  return (
    <div style={styles.play} data-chain="ready" data-adventurer={session.player.adventurerId}>
      <RoomSandbox
        key={generationOf(chain)}
        world={controller.world()}
        route={route}
        onKey={(command, keys) => {
          map.current = keys.controller;
          return onKey(command, keys);
        }}
        onFrame={(view) => {
          map.current = view;
          place();
        }}
      />
      <div ref={ghosts} style={styles.layer} data-ghosts="0" />
      <ChainPanel stages={stages} controller={controller} />
    </div>
  );
}

const styles: Record<string, CSSProperties> = {
  play: { position: "fixed", inset: 0 },
  /** Over the map, under the panel; taps pass through to the canvas. */
  layer: { position: "absolute", inset: 0, pointerEvents: "none", overflow: "hidden" },
  ghost: {
    position: "absolute",
    left: "0",
    top: "0",
    borderRadius: "50%",
    border: "2px dashed #6bc7ff",
    boxSizing: "border-box",
    pointerEvents: "none",
    color: "#6bc7ff",
    font: "0.7rem ui-monospace, monospace",
    display: "flex",
    alignItems: "center",
    justifyContent: "center",
  },
  page: { position: "fixed", inset: 0, background: "#1b1b1f" },
  line: {
    position: "fixed",
    right: 8,
    top: 8,
    maxWidth: "calc(100vw - 16px)",
    padding: "6px 10px",
    borderRadius: 6,
    border: "1px dashed #ff6b6b",
    font: "0.75rem ui-monospace, monospace",
    color: "#eee",
    background: "rgba(0,0,0,0.78)",
    zIndex: 10,
  },
};
