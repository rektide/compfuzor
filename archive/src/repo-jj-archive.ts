#!/usr/bin/env -S node --disable-warning=MODULE_TYPELESS_PACKAGE_JSON
/** jj archive toolkit; importable entry point for the compfuzor launcher. */
import { realpath } from "node:fs/promises";
import { cli, define } from "gunshi";
import completion from "@gunshi/plugin-completion";
import { main as legacyRefresh } from "./refresh.ts";

const refresh = define({
  name: "refresh",
  description: "Safely refresh an archive checkout from declared remotes.",
  run: async () => legacyRefresh(),
});

export async function main(): Promise<void> {
  const args = process.argv.slice(2);
  // The old flag-only invocation remains supported while Ansible migrates to
  // the explicit refresh --json contract.
  if (args[0]?.startsWith("--") && args[0] !== "--help") return legacyRefresh();
  await cli(
    args,
    define({
      name: "archive",
      description: "Small, composable jj archive operations. See archive/README.md.",
      run: () => console.log("Run archive --help for available commands."),
    }),
    {
      name: "repo-jj-archive",
      version: "0.1.0",
      subCommands: { refresh },
      plugins: [completion()],
    },
  );
}

const argvPath = process.argv[1];
if (argvPath) {
  realpath(argvPath).then(
    (realArgv) => {
      if (realArgv !== import.meta.filename) return;
      return main().catch((error: unknown) => {
        console.error(`repo-jj-archive: ${error instanceof Error ? error.message : String(error)}`);
        process.exitCode = 1;
      });
    },
    (error: unknown) => {
      console.error(`repo-jj-archive: ${error instanceof Error ? error.message : String(error)}`);
      process.exitCode = 1;
    },
  );
}
