#!/usr/bin/env -S node --disable-warning=MODULE_TYPELESS_PACKAGE_JSON
/** General jj toolkit, with a JSON-only refresh mode for Ansible. */
import { realpath } from "node:fs/promises";
import { main } from "./cli/main.ts";

export { main };

const argvPath = process.argv[1];
if (argvPath) {
  realpath(argvPath).then(
    (realArgv) => {
      if (realArgv !== import.meta.filename) return;
      return main().catch((error: unknown) => {
        const detail =
          error instanceof AggregateError
            ? error.errors
                .map((item: unknown) => (item instanceof Error ? item.message : String(item)))
                .join("; ")
            : error instanceof Error
              ? error.message
              : String(error);
        console.error(`repo-jj-archive: ${detail}`);
        process.exitCode = 1;
      });
    },
    (error: unknown) => {
      console.error(`repo-jj-archive: ${error instanceof Error ? error.message : String(error)}`);
      process.exitCode = 1;
    },
  );
}
