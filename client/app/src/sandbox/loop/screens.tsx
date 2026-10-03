import { useEffect } from "react";
import { Button, IconButton, Panel, Ribbon, Text } from "../../chrome/Chrome";
import type { LoopIntent, ServiceId } from "../../input/intent";
import { targetLabel } from "../../render/hubView";
import { ADVENTURER, REPORT_FIGURES, type AdventurerSheet } from "../fixtures/hubs";
import { keyUi, useKeyLayer, useScreenFocus } from "../keyScope";
import { gatesFrom, hubName, locationName } from "./machine";
import { ui } from "./styles";

type Dispatch = (intent: LoopIntent) => void;

/** `Esc` on a service or the Gate screen: the header's ‹ Back (CLI-03k). */
function useEscapeBack(screen: "service" | "gate", dispatch: Dispatch) {
  useKeyLayer(screen, (command) => {
    if (command?.kind !== "escape") return false;
    dispatch({ kind: "back" });
    return true;
  });
}

/** What each service's screen will hold (design/11 *Hubs*), said on its stub. */
const SERVICE_CONTENT: Readonly<Record<ServiceId, string>> = {
  guild: "Board: quests, contracts, the day's Rifts; rank and merit; titles.",
  trainer: "Skills to buy; the build editor: 8 skills, attributes, belt.",
  smith: "One task per screen, the item on the left, the result on the right.",
  armorer: "One task per screen, the item on the left, the result on the right.",
  enchanter: "One task per screen, the item on the left, the result on the right.",
  alchemist: "One task per screen, the item on the left, the result on the right.",
  market: "Search, cheapest lot per size, average price; my lots.",
  vault: "Shared storage; move to and from the pack.",
};

/** A screen's header: the back, and the title on a big ribbon (blue, red for a defeat). */
function Header({
  title,
  dispatch,
  colour = "blue",
}: {
  title: string;
  dispatch?: Dispatch;
  colour?: "blue" | "red";
}) {
  return (
    <header style={ui.header}>
      {dispatch ? (
        <IconButton
          icon="back"
          label="Back"
          plain={{ ...ui.button, ...ui.quiet }}
          plainText="‹ Back"
          onClick={() => dispatch({ kind: "back" })}
        />
      ) : (
        <span className="gw-header-side" />
      )}
      <Ribbon colour={colour} size="big" plain={ui.title}>
        {title}
      </Ribbon>
      <span className="gw-header-side" style={{ minWidth: 44 }} />
    </header>
  );
}

/** A service: a titled stub with a back (CLI-06 and CLI-07 build the real screens). */
export function ServiceScreen({
  hub,
  service,
  dispatch,
}: {
  hub: number;
  service: ServiceId;
  dispatch: Dispatch;
}) {
  const title = targetLabel({ kind: "service", service });
  const root = useScreenFocus();
  useEscapeBack("service", dispatch);
  return (
    <div
      ref={root}
      tabIndex={-1}
      style={{ ...ui.screen, ...keyUi.root }}
      data-screen="service"
      data-service={service}
    >
      <Header title={title} dispatch={dispatch} />
      <div style={ui.body}>
        <p style={ui.muted}>{hubName(hub)}</p>
        <Panel variant="paper" plain={ui.card}>
          {SERVICE_CONTENT[service]}
        </Panel>
        <p style={ui.muted}>A stub: the real screen comes with CLI-06 and CLI-07.</p>
      </div>
    </div>
  );
}

/** The build and the belt, as the Gate screen and the desktop's left panel show them. */
export function SheetSummary({ sheet = ADVENTURER }: { sheet?: AdventurerSheet }) {
  return (
    <>
      <div style={ui.section}>
        <Text tone="caption" plain={ui.label}>
          Adventurer
        </Text>
        <div>
          <b>{sheet.name}</b> · {sheet.profession}, level {sheet.level}
        </div>
      </div>
      <div style={ui.section}>
        <Text tone="caption" plain={ui.label}>
          Skill bar
        </Text>
        <ol style={ui.list}>
          {sheet.bar.map((skill, i) =>
            skill ? (
              <li key={i}>{skill}</li>
            ) : (
              <Text key={i} as="li" tone="muted" plain={ui.muted}>
                empty
              </Text>
            ),
          )}
        </ol>
      </div>
      <div style={ui.section}>
        <Text tone="caption" plain={ui.label}>
          Attributes
        </Text>
        {sheet.attributes.map(([name, value]) => (
          <div key={name} style={ui.row}>
            <span>{name}</span>
            <span>{value}</span>
          </div>
        ))}
      </div>
      <div style={ui.section}>
        <Text tone="caption" plain={ui.label}>
          Belt
        </Text>
        {sheet.belt.map(([name, count]) => (
          <div key={name} style={ui.row}>
            <span>{name}</span>
            <span>× {count}</span>
          </div>
        ))}
      </div>
    </>
  );
}

/**
 * The Gate screen (design/11 *Hubs*): where this hub's gates lead, the build and the belt, and a
 * last check: what the bar cannot do, a reminder, never a block. "Leave" is `enter gate g`.
 */
export function GateScreen({ hub, dispatch }: { hub: number; dispatch: Dispatch }) {
  const gates = gatesFrom(hub);
  const root = useScreenFocus();
  useEscapeBack("gate", dispatch);
  return (
    <div ref={root} tabIndex={-1} style={{ ...ui.screen, ...keyUi.root }} data-screen="gate">
      <Header title={`Gate · ${hubName(hub)}`} dispatch={dispatch} />
      <div style={ui.body}>
        <div style={ui.section}>
          <Text tone="caption" plain={ui.label}>
            Where the gates lead
          </Text>
          {gates.map((gate) => (
            <Panel key={gate.id} variant="paper" plain={ui.card} style={ui.row} data-gate={gate.id}>
              <span>
                Gate {gate.id} → {locationName(gate.destination)}
              </span>
              <Button
                variant="action"
                plain={{ ...ui.button, ...ui.primary }}
                onClick={() => dispatch({ kind: "enter gate", gate: gate.id })}
                aria-label={`Leave by gate ${gate.id}`}
              >
                Leave ▸
              </Button>
            </Panel>
          ))}
        </div>
        <Panel variant="paper" className="gw-sheet">
          <SheetSummary />
        </Panel>
        <Panel variant="dark" plain={{ ...ui.card, borderColor: "#6b5a2a" }} role="note">
          <Text tone="caption" plain={ui.label}>
            Before leaving
          </Text>
          This bar has {ADVENTURER.cannot.join(", ")}. A reminder, not a block.
        </Panel>
      </div>
    </div>
  );
}

/**
 * The entry moment: the entry draw is a Fate action sent alone (design/02), so the instance waits
 * for it. On fixed data it completes after a fixed delay (`entryMs`, `?entry=`), or at once when
 * skipped; the answer is `entry drawn`. Skip takes the focus (CLI-03k): `Enter` skips.
 */
export function EntryScreen({
  destination,
  entryMs,
  dispatch,
  answer,
}: {
  destination: string;
  entryMs: number;
  dispatch: Dispatch;
  answer: () => void;
}) {
  useEffect(() => {
    const timer = window.setTimeout(answer, entryMs);
    return () => window.clearTimeout(timer);
  }, [answer, entryMs]);
  useKeyLayer("entry", () => false);
  return (
    <div style={{ ...ui.screen, justifyContent: "center", alignItems: "center", gap: 20 }}>
      <Panel
        variant="scroll"
        data-screen="entry"
        className="gw-entry"
        plain={{ padding: 24 }}
        style={{ textAlign: "center" }}
      >
        <div style={ui.title}>Through the gate</div>
        <Text as="p" tone="muted" plain={ui.muted}>
          to {destination}
        </Text>
      </Panel>
      <Button
        variant="quiet"
        plain={{ ...ui.button, ...ui.quiet }}
        onClick={() => dispatch({ kind: "skip entry" })}
        autoFocus
      >
        Skip ▸
      </Button>
    </div>
  );
}

/**
 * The closing report (design/02 *Ending an expedition*): returned or defeated, experience, loot,
 * quest progress, the belt's potions credited back (D-141). Fixed figures, nothing computed.
 * "On to …" takes the focus (CLI-03k): `Enter` continues.
 */
export function ReportScreen({
  outcome,
  how,
  hub,
  dispatch,
}: {
  outcome: "returned" | "defeated";
  how: string;
  hub: number;
  dispatch: Dispatch;
}) {
  const figures = REPORT_FIGURES[outcome];
  useKeyLayer("report", () => false);
  const by =
    how === "gate" ? "through the gate" : how === "travel back" ? "travelled back" : "health at 0";
  return (
    <div style={ui.screen} data-screen="report" data-outcome={outcome}>
      <Header
        title={outcome === "returned" ? "Returned" : "Defeated"}
        colour={outcome === "returned" ? "blue" : "red"}
      />
      <div style={ui.body}>
        <p style={ui.muted}>
          {outcome === "returned" ? "Back" : "Carried back"} to {hubName(hub)}, {by}. Everything
          earned is kept.
        </p>
        <Panel variant="paper" plain={ui.card}>
          <Text tone="caption" plain={ui.label}>
            Experience
          </Text>
          +{figures.experience}
        </Panel>
        <Panel variant="paper" plain={ui.card}>
          <Text tone="caption" plain={ui.label}>
            Loot
          </Text>
          <ul style={ui.list}>
            {figures.loot.map((line) => (
              <li key={line}>{line}</li>
            ))}
          </ul>
        </Panel>
        <Panel variant="paper" plain={ui.card}>
          <Text tone="caption" plain={ui.label}>
            Quest progress
          </Text>
          <ul style={ui.list}>
            {figures.quests.map((line) => (
              <li key={line}>{line}</li>
            ))}
          </ul>
        </Panel>
        <Panel variant="paper" plain={ui.card}>
          <Text tone="caption" plain={ui.label}>
            Belt
          </Text>
          <ul style={ui.list}>
            {figures.beltBack.map((line) => (
              <li key={line}>{line}</li>
            ))}
          </ul>
        </Panel>
      </div>
      <div style={{ padding: 12 }}>
        <Button
          variant="action"
          plain={{ ...ui.button, ...ui.primary }}
          style={{ width: "100%" }}
          onClick={() => dispatch({ kind: "close report" })}
          autoFocus
        >
          On to {hubName(hub)} ▸
        </Button>
      </div>
    </div>
  );
}
