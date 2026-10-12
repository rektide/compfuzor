/** CONFIG's fixed command vocabulary, argument parsing, aliases, and help. */

import { join, resolve } from "node:path";
import { parseArgs } from "node:util";

import type { StatusFormat } from "./report.ts";

export const CONFIG_ACTIONS = [
  "install",
  "assemble",
  "sync-inputs",
  "publish",
  "inputs",
  "status",
] as const;
export type ConfigAction = (typeof CONFIG_ACTIONS)[number];

export type ConfigCliOptions = {
  help?: boolean;
  action?: string;
  context?: string;
  invokedAs: string;
  specPath: string;
  runner: string;
  strategy?: string;
  dropins?: string;
  seed: boolean;
  rebuild: boolean;
  initiallyDisabled: boolean;
  format: StatusFormat;
  check: boolean;
  stdout: boolean;
  list: boolean;
  quiet: boolean;
  args: string[];
};

export type ConfigAliasPieces = { action?: ConfigAction; context?: string };

const GENERAL_HELP = `Usage: config-ACTION.sh [OPTIONS] [CONFIG ...]

Fixed actions:
  config-install.sh       Install selected recipes
  config-assemble.sh      Assemble or inspect candidates
  config-sync-inputs.sh   Seed or refresh consumer inputs
  config-publish.sh       Copy or link canonical outputs
  config-inputs.sh        Inspect or mutate consumer inputs
  config-status.sh        Report input, assembly, and output health

Binding options on every action:
  --definition ID  Select one complete CONFIG definition
  --spec PATH      Select an exact spec (instead of --definition)
  --runner PATH    Override the shared candidate worker

Run a fixed command with --help for its action-specific options.`;

const ACTION_HELP: Record<ConfigAction, string> = {
  install: `Usage: config-install.sh [--context NAME] [--strategy assemble|copy|link] [--dropins copy|link] [CONFIG ...]

Install selected CONFIG recipes into a context. With no CONFIG names, selects
the context's apply:true recipes.

Options:
  --context NAME                 Select a declared context
  --strategy assemble|copy|link Override the context install strategy
  --dropins copy|link            Override input delivery for assembly

Discover recipes with config-assemble.sh --list.`,
  assemble: `Usage: config-assemble.sh [--context NAME] [--check|--stdout|--list] [CONFIG ...]

Assemble selected CONFIG recipes in one transaction. With no CONFIG names,
selects the context's apply:true recipes.

Options:
  --context NAME  Select a declared context
  --check         Show differences without changing outputs
  --stdout        Write one selected candidate byte-for-byte
  --list          List recipes declared in the selected context
  -q, --quiet     Suppress runner progress`,
  "sync-inputs": `Usage: config-sync-inputs.sh [--context NAME] [--strategy copy|link] [--seed] [CONFIG ...]

Synchronize canonical inputs into a consumer context. Refresh is the default;
--seed preserves every existing consumer entry.

Options:
  --context NAME       Select a declared context
  --strategy copy|link Select input representation
  --seed               Create missing entries without replacing existing ones`,
  publish: `Usage: config-publish.sh [--context NAME] --strategy copy|link [CONFIG ...]

Publish canonical outputs as whole files or links in a consumer context.

Options:
  --context NAME       Select a declared context
  --strategy copy|link Select output representation (required unless set by
                       COMPFUZOR_CONFIG_PUBLISH_STRATEGY)`,
  inputs: `Usage: config-inputs.sh [--context NAME] SUBACTION ...

Inspect or mutate consumer inputs.

Subactions:
  list [CONFIG ...]
  status [CONFIG ...] [--json|--json-array]
  put CONFIG/INPUT SOURCE [NAME] [--strategy copy|link] [--disabled] [--no-rebuild]
  enable CONFIG/INPUT NAME
  disable CONFIG/INPUT NAME
  remove CONFIG/INPUT [NAME]
  fuzings CONFIG/INPUT
  fuze put CONFIG/INPUT MEMBER ROOT
  fuze enable|disable CONFIG/INPUT MEMBER

Use CONFIG/INPUT when an input name is ambiguous across recipes.`,
  status: `Usage: config-status.sh [--context NAME] [--json|--json-array] [CONFIG ...]

Report selected CONFIG recipes: consumer inputs, assembly readiness, and
installed output representation. Exit 0 is clean, 1 is drift, and 2 is an
evaluation error.

Options:
  --context NAME  Select a declared context
  --json          Emit one JSON row per line
  --json-array    Emit one JSON array`,
};

function fail(message: string): never {
  throw new Error(message);
}

function explicitHelpAction(argv: string[]): ConfigAction | undefined {
  for (let index = 0; index < argv.length; index++) {
    const argument = argv[index];
    const value =
      argument === "--action"
        ? argv[index + 1]
        : argument.startsWith("--action=")
          ? argument.slice("--action=".length)
          : undefined;
    if (value && CONFIG_ACTIONS.includes(value as ConfigAction)) return value as ConfigAction;
  }
  return undefined;
}

function invokedHelpAction(invokedAs: string): ConfigAction | undefined {
  const fixed = CONFIG_ACTIONS.find((action) => invokedAs === `config-${action}.sh`);
  if (fixed) return fixed;
  return [...CONFIG_ACTIONS]
    .sort((first, second) => second.length - first.length)
    .find((action) => invokedAs.endsWith(`-${action}.sh`));
}

export function configHelp(invokedAs: string, argv: string[]): string {
  const action = explicitHelpAction(argv) ?? invokedHelpAction(invokedAs);
  return action ? ACTION_HELP[action] : GENERAL_HELP;
}

export function parseConfigCommandArgs(
  argv: string[],
  deploymentDir: string,
  invokedAs: string,
  admission = false,
): ConfigCliOptions {
  const {
    values,
    positionals: args,
    tokens,
  } = parseArgs({
    args: argv,
    strict: true,
    allowPositionals: true,
    tokens: true,
    options: {
      action: { type: "string" },
      context: { type: "string" },
      spec: { type: "string" },
      definition: { type: "string" },
      runner: { type: "string" },
      strategy: { type: "string" },
      dropins: { type: "string" },
      seed: { type: "boolean" },
      "no-rebuild": { type: "boolean" },
      disabled: { type: "boolean" },
      json: { type: "boolean" },
      "json-array": { type: "boolean" },
      check: { type: "boolean" },
      stdout: { type: "boolean" },
      list: { type: "boolean" },
      quiet: { type: "boolean", short: "q" },
      help: { type: "boolean", short: "h" },
    },
  });
  if (values.help && !admission) {
    console.log(configHelp(invokedAs, argv));
    process.exit(0);
  }
  const formatToken = tokens.findLast(
    (token) => token.kind === "option" && (token.name === "json" || token.name === "json-array"),
  );
  const format: StatusFormat =
    formatToken?.name === "json-array" ? "array" : formatToken?.name === "json" ? "jsonl" : "human";
  if (values.spec && values.definition) fail("--spec and --definition are mutually exclusive");
  if (values.definition && !/^[A-Za-z0-9][A-Za-z0-9_.-]*$/.test(values.definition))
    fail("invalid CONFIG definition");
  return {
    ...(values.help ? { help: true } : {}),
    action: values.action,
    context: values.context,
    invokedAs,
    specPath: resolve(
      values.spec ??
        (values.definition
          ? join(deploymentDir, "etc", "config", values.definition, "spec.json")
          : join(deploymentDir, "etc", "config.spec.json")),
    ),
    runner: resolve(values.runner ?? join(deploymentDir, "bin", "config", "run.sh")),
    strategy: values.strategy,
    dropins: values.dropins,
    seed: values.seed ?? false,
    rebuild: !(values["no-rebuild"] ?? false),
    initiallyDisabled: values.disabled ?? false,
    format,
    check: values.check ?? false,
    stdout: values.stdout ?? false,
    list: values.list ?? false,
    quiet: values.quiet ?? false,
    args,
  };
}

export function configAliasPieces(
  options: ConfigCliOptions,
  contextNames: string[],
): ConfigAliasPieces {
  if (options.action !== undefined && options.context !== undefined) return {};
  if (options.invokedAs === "command.ts") return {};
  const fixed = CONFIG_ACTIONS.find((action) => options.invokedAs === `config-${action}.sh`);
  if (fixed) return { action: options.action === undefined ? fixed : undefined };
  if (!options.invokedAs.startsWith("config-") || !options.invokedAs.endsWith(".sh")) {
    fail(
      `unsupported config command alias ${options.invokedAs}; use a fixed config-ACTION.sh command or explicit --action and --context`,
    );
  }
  const body = options.invokedAs.slice("config-".length, -".sh".length);
  const full = contextNames.flatMap((context) =>
    CONFIG_ACTIONS.filter((action) => body === `${context}-${action}`).map((action) => ({
      action,
      context,
    })),
  );
  if (options.action === undefined && options.context === undefined) {
    if (full.length !== 1) fail(`unknown or ambiguous config command alias ${options.invokedAs}`);
    return full[0];
  }
  if (options.action === undefined) {
    const actions = CONFIG_ACTIONS.filter((candidate) => body.endsWith(`-${candidate}`));
    const longest = Math.max(...actions.map((candidate) => candidate.length), -1);
    const selected = actions.filter((candidate) => candidate.length === longest);
    if (selected.length !== 1)
      fail(`unknown or ambiguous action in config command alias ${options.invokedAs}`);
    return { action: selected[0] };
  }
  const contexts = contextNames.filter(
    (candidate) => body === candidate || body.startsWith(`${candidate}-`),
  );
  const longest = Math.max(...contexts.map((candidate) => candidate.length), -1);
  const selected = contexts.filter((candidate) => candidate.length === longest);
  if (selected.length !== 1)
    fail(`unknown or ambiguous context in config command alias ${options.invokedAs}`);
  return { context: selected[0] };
}

export function rejectIrrelevantFlags(options: ConfigCliOptions, action: ConfigAction): void {
  if (action !== "assemble" && (options.check || options.stdout || options.list || options.quiet))
    fail(`${action} does not accept assembly display flags`);
  if (action !== "status" && action !== "inputs" && options.format !== "human")
    fail(`${action} does not accept status format flags`);
  if (action !== "sync-inputs" && options.seed) fail(`${action} does not accept --seed`);
  if (action !== "inputs" && (!options.rebuild || options.initiallyDisabled))
    fail(`${action} does not accept input mutation flags`);
  if (action !== "install" && options.dropins !== undefined)
    fail(`${action} does not accept --dropins`);
}
