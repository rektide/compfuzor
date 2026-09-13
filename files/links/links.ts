#!/usr/bin/env -S node --disable-warning=MODULE_TYPELESS_PACKAGE_JSON
/** Source CLI wrapper for the domain-grouped LINKS runtime. */

import { realpath } from "node:fs/promises";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

import { main } from "./runtime.ts";

export * from "./runtime.ts";

const argvPath = process.argv[1];
if (argvPath) {
  Promise.all([realpath(argvPath), realpath(fileURLToPath(import.meta.url))]).then(
    ([realArgvPath, realModulePath]) => {
      if (realArgvPath !== realModulePath) return;
      const deploymentDir = resolve(dirname(realModulePath), "../..");
      return main(process.argv.slice(2), deploymentDir).then(
        (code) => { process.exitCode = code; },
        (error: unknown) => {
          console.error(error instanceof Error ? error.stack : String(error));
          process.exitCode = 2;
        },
      );
    },
    (error: unknown) => {
      console.error(error instanceof Error ? error.stack : String(error));
      process.exitCode = 2;
    },
  );
}
