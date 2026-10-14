import { Suspense, lazy, useState } from "react";
import { readChainParam } from "./chain/params";
import { Sandbox } from "./sandbox/Sandbox";

/** The chain mode (CLI-11), loaded only behind `?chain=`: the sandbox's bundle carries none of it. */
const ChainScreen = lazy(() => import("./chain/ChainScreen"));

/**
 * The rendering sandbox (CLI-03a) by default. `?chain=<node url>` plays on a local node instead
 * (CLI-11, D-273); a refused value shows the sandbox with the refusal's line. `?chain=sepolia`
 * (CLI-11e1) is read under the development server only: in `vite build` it is "not a URL".
 */
export function App() {
  const [chain] = useState(() =>
    readChainParam(window.location.search, { sepolia: import.meta.env.DEV }),
  );
  if (chain.kind === "none") return <Sandbox />;
  return (
    <Suspense fallback={null}>
      <ChainScreen param={chain} />
    </Suspense>
  );
}
