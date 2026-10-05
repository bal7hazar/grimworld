/**
 * Space held: a left drag pans (§3). The press is heard by the editor's key layer, the release
 * here; and the hold ends when the window loses the keys (`blur`) or the page is hidden
 * (`visibilitychange`), where the release would never come: no pan mode is left stuck.
 */
export function listenSpaceRelease(
  win: Pick<Window, "addEventListener" | "removeEventListener">,
  doc: Pick<Document, "addEventListener" | "removeEventListener" | "visibilityState">,
  release: () => void,
): () => void {
  const up = (e: Event) => (e as KeyboardEvent).code === "Space" && release();
  const hidden = () => doc.visibilityState === "hidden" && release();
  win.addEventListener("keyup", up);
  win.addEventListener("blur", release);
  doc.addEventListener("visibilitychange", hidden);
  return () => {
    win.removeEventListener("keyup", up);
    win.removeEventListener("blur", release);
    doc.removeEventListener("visibilitychange", hidden);
  };
}
