import { type Finding, tally } from "./validate";

/** The light's colour by what stands: red with an error, amber with a warning, green with none. */
export function lightOf(findings: readonly Finding[]): "error" | "warning" | "clear" {
  const { errors, warnings } = tally(findings);
  return errors > 0 ? "error" : warnings > 0 ? "warning" : "clear";
}

/** The top bar's light (§2.3): it opens the panel. */
export function ValidationLight({
  findings,
  onOpen,
}: {
  findings: readonly Finding[];
  onOpen: () => void;
}) {
  const { errors, warnings } = tally(findings);
  const light = lightOf(findings);
  return (
    <button
      type="button"
      className="ed-light"
      data-light={light}
      title="Validate [Y]"
      onClick={onOpen}
    >
      Validate <span aria-hidden="true">●</span>{" "}
      {light === "clear"
        ? "0"
        : `${errors} error${errors === 1 ? "" : "s"} · ${warnings} warning${warnings === 1 ? "" : "s"}`}
    </button>
  );
}

const SEVERITY: Readonly<Record<Finding["severity"], string>> = {
  error: "error",
  warning: "warning",
  hint: "hint",
};

/**
 * The validation panel (§2.6): a drawer over the inspector's column, one line per finding with its
 * severity in words, its source (R, E), its message and Show.
 */
export function ValidationPanel({
  findings,
  onShow,
  onClose,
}: {
  findings: readonly Finding[];
  onShow: (finding: Finding) => void;
  onClose: () => void;
}) {
  const { errors, warnings } = tally(findings);
  return (
    <aside className="ed-validation" data-validation="" aria-label="Validation">
      <div className="ed-validation-head">
        <strong>Validation</strong>
        <span data-counts="">
          <span className="ed-sev" data-severity="error">
            ●
          </span>{" "}
          {errors}{" "}
          <span className="ed-sev" data-severity="warning">
            ●
          </span>{" "}
          {warnings}
        </span>
        <button type="button" aria-label="Close the panel" onClick={onClose}>
          ✕
        </button>
      </div>
      {findings.length === 0 ? (
        <p className="ed-dim" data-finding-none="">
          No finding: every check passes.
        </p>
      ) : (
        <ul className="ed-findings">
          {findings.map((f, i) => (
            <li key={i} data-finding={f.check} data-severity={f.severity}>
              <span className="ed-sev" data-severity={f.severity} aria-hidden="true">
                ●
              </span>{" "}
              <span className="ed-visually-hidden">{SEVERITY[f.severity]}</span>
              <span className="ed-source" title={f.check}>
                {f.source}
              </span>{" "}
              <span className="ed-dim">{f.check}</span> {f.message}{" "}
              {(f.hexes.length > 0 || f.objects.length > 0) && (
                <button type="button" data-show="" onClick={() => onShow(f)}>
                  Show
                </button>
              )}
            </li>
          ))}
        </ul>
      )}
      <p className="ed-dim ed-validation-key">
        R = ENG-08&apos;s check · E = the editor&apos;s or the converter&apos;s own. With a content
        manifest, the converter&apos;s refusal is shown too. Export is refused while an error
        stands; saving never is.
      </p>
    </aside>
  );
}
