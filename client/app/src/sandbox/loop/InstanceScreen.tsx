import {
  type CSSProperties,
  useCallback,
  useEffect,
  useMemo,
  useRef,
  useState,
  useSyncExternalStore,
} from "react";
import { Button, Panel } from "../../chrome/Chrome";
import { Belt } from "../../combat/Belt";
import { CombatLogLine } from "../../combat/CombatLog";
import { type CombatController, type CombatView, slotOf } from "../../combat/controller";
import { Inspection, SkillBar } from "../../combat/SkillBar";
import { TargetZone } from "../../combat/TargetZone";
import type { CombatState } from "../../combat/state";
import type { Intent, LoopIntent } from "../../input/intent";
import type { KeyCommand, KeyLike } from "../../input/keys";
import type { Tile } from "../../render/view";
import type { SandboxController } from "../controller";
import { type GateRecord, globalTile, locationOf } from "../fixtures/region";
import { zoneWorld } from "../fixtures/zone";
import { keyUi, offScreen, useKeyLayer, useScreenFocus } from "../keyScope";
import { type MapKeys, RoomSandbox } from "../Sandbox";
import { spendCosts, startRecharge } from "../wiring";
import type { SandboxWorld } from "../world";
import { Hud, bandSheet } from "./Hud";
import { fightSheet } from "./hudModel";
import { goIntent, leaveAsked, nextTarget, zoneTargets } from "./keyTargets";
import { hubName, leaveQuestion } from "./machine";
import { ui } from "./styles";

type Asking = { kind: "leave"; gate: GateRecord } | { kind: "travel back" };

/**
 * Whether the confirmation keeps this key inside its two buttons: a plain `Tab` or `Shift+Tab`,
 * never one with Ctrl, Meta or Alt (the browser's and the system's own shortcuts).
 */
export function trapsTab(event: KeyLike): boolean {
  return event.code === "Tab" && !event.ctrlKey && !event.metaKey && !event.altKey;
}

/**
 * The combat screen's fight (CLI-05c, `?combat=`): its controller, the world it stands on, and the
 * layout (on a phone, the log's last line under the target zone; on a desktop, a panel beside).
 */
export interface Fight {
  readonly controller: CombatController;
  readonly world: SandboxWorld;
  readonly phone: boolean;
}

/** No fight: a store that never changes. */
const NO_FIGHT = { subscribe: () => () => {}, view: (): CombatView | null => null };

/** The entity of the combat actor on `tile` (the adventurer's, a living goblin's), or null. */
function actorOn(state: CombatState, tile: Tile): number | null {
  const on = (t: Tile) => t.x === tile.x && t.y === tile.y;
  if (on(state.adventurer.tile)) return state.adventurer.entity;
  return state.goblins.find((g) => g.alive && on(g.tile))?.entity ?? null;
}

/**
 * While a slot is armed, a tap on the map is the controller's: an actor, or a tile (§4.1). Returns
 * the intent when the map keeps it, null when the controller took it.
 */
export function handArmedTap(
  controller: Pick<CombatController, "view" | "tile" | "actor"> | undefined,
  intent: Intent,
): Intent | null {
  const now = controller?.view();
  if (!controller || !now?.armed || intent.kind !== "tile") return intent;
  const entity = actorOn(now.state, intent.tile);
  // A TILE slot aims at a tile whatever stands on it; CLI-05a's targeting decides if it is taken.
  if (entity === null || now.aim?.addressing === "tile") controller.tile(intent.tile);
  else controller.actor(entity);
  return null;
}

/** A hub gate's anchor, as its record gives it. */
const anchorOf = (gate: GateRecord) => globalTile(gate.anchor_chunk, gate.anchor_tile);

/**
 * The instance: CLI-03a's room on the entry chunk of the gate's destination, its renderer and input
 * unchanged, under the status band (CLI-03l), with the three ways out (CLI-03c): leaving by a hub gate the adventurer stands on
 * (D-148), travelling back, and a debug defeat. Leaving and travelling back are asked twice
 * (design/11 I-5): the offer or the button, then a confirmation.
 *
 * By keys (CLI-03k): `F` / `Shift+F` select the location's hub gates (a ring on the anchor),
 * `Enter` taps the anchor, `L` is the Leave control (on an anchor only), `Esc` cancels the walk,
 * then clears the selection. The confirmation opens with Stay focused and keeps the focus inside
 * it; leaving takes `Tab` then `Enter`. No key for Travel back.
 *
 * With a `fight` (CLI-05c, `?combat=`), the combat screen: the band's chips, the target zone, the
 * skill bar and the belt under the map (CLI-05 brief §2, §3, §6), the log's last line on a phone.
 * A tap on a slot or its key (`1`–`8`, `Z X C V`) goes to the fight's controller; while a slot is
 * armed, a tap on the map chooses its target (§4.1), `F` / `Shift+F` cycle the targets and `Enter`
 * plays, and `Esc` closes an inspection, then disarms, before the walk and the selection. The
 * screen hands its state and armed slot to the map (`ViewState.combat`) and the map answers what a
 * slot reaches. The ways out are not shown: the fight has no loop around it.
 */
export function InstanceScreen({
  location,
  entry,
  offer,
  gateHere,
  dispatch,
  onMoved,
  fight,
}: {
  /** The instance's location and entry tile; unused in a fight, whose world is given. */
  location?: number;
  entry?: Tile;
  /** The hub gate to offer on its own: on its anchor after leaving one (the machine's `leaveOffer`). */
  offer: GateRecord | null;
  /** The hub gate under the adventurer, if any, at arrival too (the machine's `gateHere`). */
  gateHere: GateRecord | null;
  dispatch: (intent: LoopIntent) => void;
  onMoved: (tile: Tile) => void;
  fight?: Fight;
}) {
  const world = useMemo(
    () => fight?.world ?? zoneWorld(entry!, locationOf(location!)),
    [entry, location, fight?.world],
  );
  const [asking, setAsking] = useState<Asking | null>(null);
  const offerOpen = offer !== null;
  const root = useScreenFocus();
  const mapBox = useRef<HTMLDivElement>(null);
  const targets = useMemo(() => (fight ? [] : zoneTargets(location!, anchorOf)), [location, fight]);
  const [selected, setSelected] = useState<number | null>(null);
  const chosen = selected === null ? null : (targets[selected] ?? null);
  const chosenRef = useRef(chosen);
  chosenRef.current = chosen;
  const marker = useRef<HTMLDivElement>(null);
  const shown = useRef<SandboxController | null>(null);

  const place = useCallback((controller: SandboxController) => {
    shown.current = controller;
    const element = marker.current;
    if (!element) return;
    const target = chosenRef.current;
    if (target) {
      const at = controller.tileOnScreen(target.tile);
      element.style.transform = `translate(${at.x}px, ${at.y}px) translate(-50%, -50%)`;
      element.style.width = element.style.height = `${44 * controller.scale()}px`;
    }
    element.style.visibility = target ? "visible" : "hidden";
  }, []);
  useEffect(() => {
    if (shown.current) place(shown.current);
  }, [chosen, place]);

  // The fight (CLI-05c): its view, the map's controller once mounted, the actor selected there.
  const store = fight?.controller ?? NO_FIGHT;
  const combat = useSyncExternalStore(store.subscribe, store.view);
  const [map, setMap] = useState<SandboxController | null>(null);
  const [picked, setPicked] = useState<number | null>(null);
  const changed = (controller: SandboxController) => {
    if (!fight) return;
    if (map !== controller) {
      setMap(controller);
      fight.controller.setRules({
        aim: (state, armed) => controller.combatAim(state, armed),
        play: (state, armed) => startRecharge(spendCosts(state, armed), armed),
      });
    }
    const id = controller.selectedActorId();
    setPicked(id === null || id === world.adventurerId ? null : id);
    const tile = controller.adventurerTile();
    if (tile) fight.controller.moved(tile);
  };
  useEffect(() => {
    if (!map || !combat) return;
    map.setCombat({ state: combat.state, armed: combat.armed, preview: combat.preview });
  }, [map, combat]);
  // While a slot is armed, a tap on the map is the controller's: an actor, or a tile (§4.1).
  const route = (intent: Intent): Intent | null => handArmedTap(fight?.controller, intent);

  const onKey = (command: KeyCommand, map: MapKeys): boolean => {
    switch (command.kind) {
      case "step":
        setSelected(null);
        return map.handle(command);
      case "skill":
      case "belt":
        if (!fight) return map.handle(command);
        fight.controller.slot({
          kind: command.kind === "skill" ? "skill" : "item",
          slot: command.slot,
        });
        return true;
      case "cycle": {
        if (fight?.controller.cycle(command.by)) return true;
        const next = nextTarget(targets.length, selected, command.by);
        setSelected(next);
        const target = next === null ? null : targets[next];
        if (target && map.controller && offScreen(map.controller, target.tile, mapBox.current)) {
          map.controller.lookAt(target.tile);
        }
        return true;
      }
      case "go":
        if (fight?.controller.go()) return true;
        if (!chosen || !map.controller) return false;
        map.controller.apply(goIntent(chosen.tile));
        return true;
      case "leave": {
        const ask = leaveAsked(gateHere);
        if (ask) setAsking(ask);
        return ask !== null;
      }
      case "escape":
        if (fight?.controller.escape()) return true;
        if (map.handle(command)) return true;
        if (selected === null) return false;
        setSelected(null);
        return true;
      default:
        return map.handle(command);
    }
  };

  return (
    <div ref={root} tabIndex={-1} style={{ ...ui.screen, ...keyUi.root }} data-screen="instance">
      <FightHud combat={combat} />
      <div ref={mapBox} style={styles.map} data-map-box="">
        <RoomSandbox
          world={world}
          onTile={(tile) => tile && onMoved(tile)}
          onChange={changed}
          {...(fight ? { route } : {})}
          onFrame={place}
          onKey={onKey}
        >
          <div ref={marker} className="gw-key-marker" style={keyUi.marker} aria-hidden />
          <div style={styles.top}>
            {offerOpen && (
              <Button
                variant="action"
                plain={{ ...ui.button, ...ui.primary }}
                onClick={() => setAsking({ kind: "leave", gate: offer })}
                aria-label="Leave by this gate"
              >
                Gate to {hubName(offer.destination)} · Leave ▸
              </Button>
            )}
          </div>
          <div style={fight ? { display: "none" } : styles.right}>
            <Button
              variant="action"
              plain={{ ...ui.button, ...ui.quiet, opacity: gateHere === null ? 0.4 : 1 }}
              disabled={gateHere === null}
              onClick={() => gateHere && setAsking({ kind: "leave", gate: gateHere })}
              aria-label="Leave"
            >
              Leave
            </Button>
            <Button
              variant="action"
              plain={ui.button}
              onClick={() => setAsking({ kind: "travel back" })}
            >
              Travel back
            </Button>
            <button
              style={{ ...ui.button, ...ui.debug }}
              onClick={() => dispatch({ kind: "defeat now" })}
              title="A debug control of the sandbox: health reaches 0 now"
            >
              debug: defeat now
            </button>
          </div>
          {asking && (
            <Confirm
              asking={asking}
              stay={() => setAsking(null)}
              confirm={() => {
                setAsking(null);
                dispatch(
                  asking.kind === "leave"
                    ? { kind: "leave", gate: asking.gate.id }
                    : { kind: "travel back" },
                );
              }}
            />
          )}
          {fight && combat?.inspected && slotOf(combat.state, combat.inspected) && (
            <Inspection
              slot={slotOf(combat.state, combat.inspected)!}
              onClose={() => fight.controller.escape()}
            />
          )}
        </RoomSandbox>
      </div>
      {fight && combat && (
        <>
          <TargetZone state={combat.state} selected={combat.focus ?? picked} />
          {fight.phone && <CombatLogLine lines={combat.log} />}
          <div style={styles.dock} data-combat-dock="">
            <div style={styles.said} aria-live="polite" data-said="">
              {combat.said}
            </div>
            <SkillBar
              bar={combat.state.adventurer.bar}
              armed={combat.armed}
              activation={combat.state.adventurer.activation}
              keys={!fight.phone}
              onSlot={(slot) => fight.controller.slot({ kind: "skill", slot })}
              onInspect={(slot) => fight.controller.inspect({ kind: "skill", slot })}
              onWait={() => fight.controller.note("You waited")}
            />
            <Belt
              belt={combat.state.adventurer.belt}
              armed={combat.armed}
              keys={!fight.phone}
              onSlot={(slot) => fight.controller.slot({ kind: "item", slot })}
              onInspect={(slot) => fight.controller.inspect({ kind: "item", slot })}
            />
          </div>
        </>
      )}
      <span style={keyUi.hidden} aria-live="polite" data-key-live="">
        {chosen ? `Gate to ${hubName(chosen.gate.destination)} selected, Enter to go` : ""}
      </span>
    </div>
  );
}

/**
 * The status band: the fixed sheet, or in a fight its figures and Wren's chips. Its sheet changes
 * only with the fight's adventurer, so the band renders again only then (`Hud` is memoised).
 */
function FightHud({ combat }: { combat: CombatView | null }) {
  const adventurer = combat?.state.adventurer ?? null;
  const sheet = useMemo(
    () => (adventurer ? fightSheet(bandSheet(), adventurer) : bandSheet()),
    [adventurer],
  );
  return <Hud sheet={sheet} {...(adventurer ? { chips: adventurer.chips } : {})} />;
}

/**
 * The confirmation (design/11 I-5): Stay focused on opening, `Tab` / `Shift+Tab` kept inside its
 * two buttons, `Esc` is Stay, `Enter` presses the focused button; the map's keys are inert under
 * it. On closing, the focus goes back where it was when it opened.
 */
function Confirm({
  asking,
  stay,
  confirm,
}: {
  asking: Asking;
  stay: () => void;
  confirm: () => void;
}) {
  const box = useRef<HTMLDivElement>(null);
  // Read on the first render, before Stay takes the focus.
  const [opener] = useState(() => document.activeElement as HTMLElement | null);
  useEffect(() => {
    // Stay, the first button, takes the focus (again after a remount: the cleanup gives it back).
    box.current?.querySelector("button")?.focus();
    return () => {
      if (opener?.isConnected && !(opener as HTMLButtonElement).disabled) opener.focus();
      else (document.querySelector('[data-screen="instance"]') as HTMLElement | null)?.focus();
    };
  }, [opener]);
  useKeyLayer("instance", (command: KeyCommand | null, event: KeyLike) => {
    if (command?.kind === "escape") {
      stay();
      return true;
    }
    if (!trapsTab(event)) return false;
    const buttons = [...(box.current?.querySelectorAll("button") ?? [])];
    if (buttons.length === 0) return false;
    const at = buttons.indexOf(document.activeElement as HTMLButtonElement);
    const by = event.shiftKey ? -1 : 1;
    const next = at < 0 ? 0 : (at + by + buttons.length) % buttons.length;
    buttons[next]?.focus();
    return true;
  });
  return (
    <div ref={box} style={styles.scrim} role="dialog" aria-label="Confirm" aria-modal="true">
      <Panel variant="scroll" plain={ui.card} style={{ maxWidth: 320 }}>
        <p style={{ marginTop: 0 }}>
          {leaveQuestion(asking.kind === "leave" ? asking.gate : null)}
        </p>
        <div style={{ ...ui.row, flexWrap: "wrap" }}>
          <Button variant="quiet" plain={{ ...ui.button, ...ui.quiet }} onClick={stay}>
            Stay
          </Button>
          <Button variant="commit" plain={{ ...ui.button, ...ui.primary }} onClick={confirm}>
            {asking.kind === "leave" ? "Leave" : "Travel back"}
          </Button>
        </div>
      </Panel>
    </div>
  );
}

const styles: Record<string, CSSProperties> = {
  /** The map's box under the band: the room fills it, the controls sit at its corners. */
  map: { position: "relative", flex: 1, minHeight: 0, overflow: "hidden" },
  /** The bar and the belt under the target zone (CLI-05c): their height never changes. */
  dock: {
    flex: "none",
    display: "flex",
    flexDirection: "column",
    alignItems: "center",
    gap: 6,
    padding: "4px 8px 10px",
    background: "#0b0b0e",
    borderTop: "1px solid #2a2a33",
  },
  said: {
    alignSelf: "stretch",
    minHeight: "1.125rem",
    font: "0.8125rem/1.125rem system-ui",
    color: "#f2c94c",
    textAlign: "center",
  },
  top: {
    position: "absolute",
    bottom: 76,
    left: "50%",
    transform: "translateX(-50%)",
    display: "flex",
    gap: 8,
  },
  right: {
    position: "absolute",
    top: 8,
    right: 8,
    display: "flex",
    flexDirection: "column",
    alignItems: "flex-end",
    gap: 8,
  },
  scrim: {
    position: "absolute",
    inset: 0,
    display: "flex",
    alignItems: "center",
    justifyContent: "center",
    padding: 16,
    background: "rgba(0,0,0,0.55)",
  },
};
