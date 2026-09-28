import { useEffect, useRef } from "react";
import { renderFrame } from "./frame";

export function App() {
  const host = useRef<HTMLDivElement>(null);

  useEffect(() => {
    const element = host.current;
    if (!element) return;
    const pending = renderFrame(element);
    return () => {
      void pending.then((app) => app.destroy(true));
    };
  }, []);

  return <div ref={host} />;
}
