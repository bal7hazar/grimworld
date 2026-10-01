import { useEffect } from "react";
import type { LoopIntent, ServiceId } from "../../input/intent";
import { targetLabel } from "../../render/hubView";
import { ADVENTURER, REPORT_FIGURES, type AdventurerSheet } from "../fixtures/hubs";
import { gatesFrom, hubName, locationName } from "./machine";
import { ui } from "./styles";

type Dispatch = (intent: LoopIntent) => void;

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

function Header({ title, dispatch }: { title: string; dispatch?: Dispatch }) {
  return (
    <header style={ui.header}>
      {dispatch ? (
        <button
          style={{ ...ui.button, ...ui.quiet }}
          onClick={() => dispatch({ kind: "back" })}
          aria-label="Back"
        >
          ‹ Back
        </button>
      ) : (
        <span />
      )}
      <span style={ui.title}>{title}</span>
      <span style={{ minWidth: 44 }} />
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
  return (
    <div style={ui.screen} data-screen="service" data-service={service}>
      <Header title={title} dispatch={dispatch} />
      <div style={ui.body}>
        <p style={ui.muted}>{hubName(hub)}</p>
        <div style={ui.card}>{SERVICE_CONTENT[service]}</div>
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
        <div style={ui.label}>Adventurer</div>
        <div>
          <b>{sheet.name}</b> · {sheet.profession}, level {sheet.level}
        </div>
      </div>
      <div style={ui.section}>
        <div style={ui.label}>Skill bar</div>
        <ol style={ui.list}>
          {sheet.bar.map((skill, i) => (
            <li key={i} style={skill ? undefined : ui.muted}>
              {skill ?? "empty"}
            </li>
          ))}
        </ol>
      </div>
      <div style={ui.section}>
        <div style={ui.label}>Attributes</div>
        {sheet.attributes.map(([name, value]) => (
          <div key={name} style={ui.row}>
            <span>{name}</span>
            <span>{value}</span>
          </div>
        ))}
      </div>
      <div style={ui.section}>
        <div style={ui.label}>Belt</div>
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
  return (
    <div style={ui.screen} data-screen="gate">
      <Header title={`Gate · ${hubName(hub)}`} dispatch={dispatch} />
      <div style={ui.body}>
        <div style={ui.section}>
          <div style={ui.label}>Where the gates lead</div>
          {gates.map((gate) => (
            <div key={gate.id} style={{ ...ui.card, ...ui.row }} data-gate={gate.id}>
              <span>
                Gate {gate.id} → {locationName(gate.destination)}
              </span>
              <button
                style={{ ...ui.button, ...ui.primary }}
                onClick={() => dispatch({ kind: "enter gate", gate: gate.id })}
                aria-label={`Leave by gate ${gate.id}`}
              >
                Leave ▸
              </button>
            </div>
          ))}
        </div>
        <SheetSummary />
        <div style={{ ...ui.card, borderColor: "#6b5a2a" }} role="note">
          <div style={ui.label}>Before leaving</div>
          This bar has {ADVENTURER.cannot.join(", ")}. A reminder, not a block.
        </div>
      </div>
    </div>
  );
}

/**
 * The entry moment: the entry draw is a Fate action sent alone (design/02), so the instance waits
 * for it. On fixed data it completes after a fixed delay (`entryMs`, `?entry=`), or at once when
 * skipped; the answer is `entry drawn`.
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
  return (
    <div style={{ ...ui.screen, justifyContent: "center", alignItems: "center", gap: 20 }}>
      <div data-screen="entry" style={{ textAlign: "center", padding: 24 }}>
        <div style={ui.title}>Through the gate</div>
        <p style={ui.muted}>to {destination}</p>
      </div>
      <button
        style={{ ...ui.button, ...ui.quiet }}
        onClick={() => dispatch({ kind: "skip entry" })}
      >
        Skip ▸
      </button>
    </div>
  );
}

/**
 * The closing report (design/02 *Ending an expedition*): returned or defeated, experience, loot,
 * quest progress, the belt's potions credited back (D-141). Fixed figures, nothing computed.
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
  const by =
    how === "gate" ? "through the gate" : how === "travel back" ? "travelled back" : "health at 0";
  return (
    <div style={ui.screen} data-screen="report" data-outcome={outcome}>
      <Header title={outcome === "returned" ? "Returned" : "Defeated"} />
      <div style={ui.body}>
        <p style={ui.muted}>
          {outcome === "returned" ? "Back" : "Carried back"} to {hubName(hub)}, {by}. Everything
          earned is kept.
        </p>
        <div style={ui.card}>
          <div style={ui.label}>Experience</div>+{figures.experience}
        </div>
        <div style={ui.card}>
          <div style={ui.label}>Loot</div>
          <ul style={ui.list}>
            {figures.loot.map((line) => (
              <li key={line}>{line}</li>
            ))}
          </ul>
        </div>
        <div style={ui.card}>
          <div style={ui.label}>Quest progress</div>
          <ul style={ui.list}>
            {figures.quests.map((line) => (
              <li key={line}>{line}</li>
            ))}
          </ul>
        </div>
        <div style={ui.card}>
          <div style={ui.label}>Belt</div>
          <ul style={ui.list}>
            {figures.beltBack.map((line) => (
              <li key={line}>{line}</li>
            ))}
          </ul>
        </div>
      </div>
      <div style={{ padding: 12 }}>
        <button
          style={{ ...ui.button, ...ui.primary, width: "100%" }}
          onClick={() => dispatch({ kind: "close report" })}
        >
          On to {hubName(hub)} ▸
        </button>
      </div>
    </div>
  );
}
