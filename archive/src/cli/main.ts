/**
 * Runner wiring: legacy argv normalization, service provision, and the
 * stdout-purity flush discipline. `main` stays a plain exported Promise so
 * the launcher (script/repo-jj-archive.ts) and the committed bundle keep the
 * same import contract as before the Effect migration.
 */
import { Console, Effect } from "effect";
import { CliConfig, CliOutput, Command, GlobalFlag } from "effect/cli";
import { NodeServices } from "@effect/platform-node";
import { reportFailure } from "./failure.ts";
import { createOutputBuffer } from "./output.ts";
import { root } from "./root.ts";
import { VERSION } from "./version.ts";

/** Built-ins trimmed to the documented surface: no wizard, no log-level. */
const builtIns: ReadonlyArray<GlobalFlag.BuiltIn> = [
  GlobalFlag.Help,
  GlobalFlag.Version,
  GlobalFlag.Completions,
];

const baseFormatter: CliOutput.Formatter = CliOutput.defaultFormatter({ colors: false });
const formatter: CliOutput.Formatter = {
  formatHelpDoc: baseFormatter.formatHelpDoc,
  formatCliError: baseFormatter.formatCliError,
  formatError: baseFormatter.formatError,
  formatErrors: baseFormatter.formatErrors,
  // Version output has always been the bare version string.
  formatVersion: (_name: string, version: string): string => version,
};

/**
 * Minimal legacy argv normalization, applied before Effect parsing. This is
 * compatibility translation only, not a parser.
 *
 * - A flag-only Ansible invocation (no subcommand) containing any known
 *   refresh flag is the `refresh` command with JSON output (`--json`
 *   appended last, matching the historical translation). Restricting the
 *   trigger to the refresh flag set keeps native root flags (`--help`,
 *   `--version`, `--completions`) and ordinary unknown-flag failures intact.
 * - Under `refresh`, the legacy `--version BRANCH` spelling maps to
 *   `--branch BRANCH`. Root `--version`/`-v` alone still prints the toolkit
 *   version: it is not a refresh flag, so it never triggers the translation.
 * - Scanning and rewriting stop at `--`, and a value token equal to
 *   `--version` (the value of a preceding value-taking flag) is never
 *   rewritten.
 */
const REFRESH_VALUE_FLAGS: ReadonlySet<string> = new Set([
  "dest",
  "repo",
  "remotes",
  "remote",
  "branch",
  "label",
  "update",
  "depth",
]);
const REFRESH_BOOLEAN_FLAGS: ReadonlySet<string> = new Set([
  "submodules",
  "json",
  "reconcile-remotes",
]);

const flagName = (token: string): string => token.slice(2).split("=")[0];

/** Whether a flag-only invocation carries any known refresh flag. */
const mentionsRefreshFlag = (args: ReadonlyArray<string>): boolean => {
  for (let i = 0; i < args.length; i++) {
    const token = args[i];
    if (token === "--") break;
    if (!token.startsWith("--")) continue;
    const name = flagName(token);
    if (REFRESH_BOOLEAN_FLAGS.has(name) || REFRESH_VALUE_FLAGS.has(name)) return true;
  }
  return false;
};

export const normalizeArgv = (args: ReadonlyArray<string>): Array<string> => {
  const legacy = args[0] !== undefined && args[0].startsWith("--") && mentionsRefreshFlag(args);
  const argv = legacy ? ["refresh", ...args, "--json"] : [...args];
  if (argv[0] === "refresh") {
    for (let i = 1; i < argv.length; i++) {
      const token = argv[i];
      if (token === "--") break;
      if (!token.startsWith("--")) continue;
      if (token === "--version") argv[i] = "--branch";
      else if (!token.includes("=") && REFRESH_VALUE_FLAGS.has(flagName(token))) i++;
    }
  }
  return argv;
};

export const main = (): Promise<void> => {
  const output = createOutputBuffer();
  const program = Command.runWith(root, { version: VERSION, renderErrors: false })(
    normalizeArgv(process.argv.slice(2)),
  ).pipe(
    Effect.provideService(Console.Console, output.console),
    Effect.provideService(CliOutput.Formatter, formatter),
    Effect.provideService(CliConfig.CliConfig, CliConfig.make({ builtIns })),
    Effect.provide(NodeServices.layer),
  );
  return Effect.runPromise(program).then(
    () => output.flush(),
    (error: unknown) => {
      output.discard();
      reportFailure(error);
    },
  );
};
