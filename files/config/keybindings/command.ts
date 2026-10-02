#!/usr/bin/env -S node --disable-warning=MODULE_TYPELESS_PACKAGE_JSON
/**
 * Direct `.ts` development entry and re-export of the internal one-candidate
 * processor. Importing starts only the asynchronous physical-main comparison
 * when argv[1] exists; no registration, assembly or installation is run merely by
 * importing this wrapper. Matching physical argv/module paths dynamically load
 * command.main.ts, so symlinked development entry points work consistently.
 * The deployed omnibus calls runtime.ts directly and supplies its own worker path.
 * @see /doc/config/keybinding-producers.md
 */
import { realpath } from "node:fs/promises";
import { fileURLToPath } from "node:url";

export { runProcessor } from "./processor.ts";

const argvPath = process.argv[1];
if (argvPath) {
  void Promise.all([realpath(argvPath), realpath(fileURLToPath(import.meta.url))]).then(
    async ([argv, module]) => {
      if (argv !== module) return;
      const { main } = await import("./command.main.ts");
      await main();
    },
  );
}
