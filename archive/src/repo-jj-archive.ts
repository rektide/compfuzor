#!/usr/bin/env -S node --disable-warning=MODULE_TYPELESS_PACKAGE_JSON
/** General jj toolkit, with a JSON-only refresh mode for Ansible. */
import { realpath } from "node:fs/promises";
import { main, runExecutable } from "./cli/main.ts";

export { main, runExecutable };

const argvPath = process.argv[1];
if (argvPath) {
  realpath(argvPath).then(
    (realArgv) => {
      if (realArgv !== import.meta.filename) return;
      return runExecutable();
    },
    (error: unknown) => {
      console.error(`repo-jj-archive: ${error instanceof Error ? error.message : String(error)}`);
      process.exitCode = 1;
    },
  );
}
