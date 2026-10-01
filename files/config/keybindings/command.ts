#!/usr/bin/env -S node --disable-warning=MODULE_TYPELESS_PACKAGE_JSON
/** Direct development entry; the deployed omnibus imports processor.ts instead. */
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
