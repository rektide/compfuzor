/** Thin multicall dispatcher for the fixed CONFIG action vocabulary. */

import { readFile } from "node:fs/promises";

import { runAssembly } from "./assembly.ts";
import {
  CONFIG_ACTIONS,
  configAliasPieces,
  parseConfigCommandArgs,
  rejectIrrelevantFlags,
  type ConfigAction,
  type ConfigCliOptions,
} from "./cli.ts";
import { getConfigContext, selectRecipeNames, type ConfigSpec } from "./context.ts";
import { runInputAction, syncInputs, type InputStrategy } from "./inputs.ts";
import { installContext, type ConfigInstallStrategy } from "./install.ts";
import { resolveSelectedName } from "./invocation.ts";
import { publishOutputs } from "./publication.ts";
import { statusContext } from "./status.ts";

export { CONFIG_ACTIONS, parseConfigCommandArgs };
export type { ConfigAction, ConfigCliOptions };

function fail(message: string): never {
  throw new Error(message);
}

function parseInputStrategy(value: string | undefined, label: string): InputStrategy {
  if (value === "copy" || value === "link") return value;
  fail(`${label} must be copy or link`);
}

function parseInstallStrategy(value: string | undefined, label: string): ConfigInstallStrategy {
  if (value === "assemble" || value === "copy" || value === "link") return value;
  fail(`${label} must be assemble, copy, or link`);
}

function contextInputStrategy(
  spec: ConfigSpec,
  contextName: string,
  explicit?: string,
): InputStrategy {
  return parseInputStrategy(
    explicit ??
      process.env.COMPFUZOR_CONFIG_DROPINS_STRATEGY ??
      getConfigContext(spec, contextName).dropins ??
      "link",
    "effective config input strategy",
  );
}

function contextInstallStrategy(
  spec: ConfigSpec,
  contextName: string,
  explicit?: string,
): ConfigInstallStrategy {
  return parseInstallStrategy(
    explicit ??
      process.env.COMPFUZOR_CONFIG_INSTALL_STRATEGY ??
      getConfigContext(spec, contextName).install ??
      "assemble",
    "effective config install strategy",
  );
}

export async function runConfigCommand(options: ConfigCliOptions): Promise<number> {
  const spec = JSON.parse(await readFile(options.specPath, "utf8")) as ConfigSpec;
  const contextNames = Object.keys(spec.contexts ?? {});
  const inferred = configAliasPieces(options, contextNames);
  const action = resolveSelectedName({
    explicit: options.action,
    invokedAs: options.invokedAs,
    inferAlias: () => inferred.action,
    fallback: "",
    declared: CONFIG_ACTIONS,
    label: "config action",
  }) as ConfigAction;
  const contextName = resolveSelectedName({
    explicit: options.context,
    invokedAs: options.invokedAs,
    inferAlias: () => inferred.context,
    environment: process.env.COMPFUZOR_CONFIG_CONTEXT ?? process.env.COMPFUZOR_CONTEXT,
    fallback: spec.defaultContext,
    declared: contextNames,
    label: "config context",
  });
  const context = getConfigContext(spec, contextName);
  rejectIrrelevantFlags(options, action);
  if (context.canonical && !["assemble", "status"].includes(action)) {
    fail(
      `config ${action} is not meaningful for canonical source=destination context; use assemble or status`,
    );
  }

  if (action === "assemble") {
    if (options.check && options.stdout) fail("--check and --stdout are mutually exclusive");
    if (options.list) {
      if (options.args.length > 0) fail("--list does not accept recipe names");
      for (const name of selectRecipeNames(spec, contextName, [], false).sort()) console.log(name);
      return 0;
    }
    const names = selectRecipeNames(spec, contextName, options.args);
    if (options.stdout && names.length !== 1) fail("--stdout requires exactly one selected config");
    return runAssembly({
      spec,
      contextName,
      runner: options.runner,
      names,
      check: options.check,
      stdout: options.stdout,
      quiet: options.quiet,
    });
  }

  if (action === "status") {
    const names = selectRecipeNames(spec, contextName, options.args);
    return statusContext({
      spec,
      contextName,
      runner: options.runner,
      names,
      format: options.format,
    });
  }

  if (action === "sync-inputs") {
    const names = selectRecipeNames(spec, contextName, options.args);
    const strategy = contextInputStrategy(spec, contextName, options.strategy);
    return syncInputs({
      spec,
      contextName,
      runner: options.runner,
      names,
      strategy,
      seed: options.seed,
    });
  }

  if (action === "publish") {
    const names = selectRecipeNames(spec, contextName, options.args);
    const strategy = parseInputStrategy(
      options.strategy ?? process.env.COMPFUZOR_CONFIG_PUBLISH_STRATEGY,
      "config publish strategy",
    );
    return publishOutputs({ spec, contextName, names, strategy });
  }

  if (action === "inputs") {
    const inputAction = options.args[0];
    const strategy =
      inputAction === "put"
        ? contextInputStrategy(spec, contextName, options.strategy)
        : options.strategy === undefined
          ? undefined
          : fail(`${inputAction ?? "inputs"} does not accept --strategy`);
    return runInputAction(
      {
        spec,
        contextName,
        runner: options.runner,
        strategy,
        rebuild: options.rebuild,
        initiallyDisabled: options.initiallyDisabled,
        format: options.format,
      },
      options.args,
    );
  }

  const names = selectRecipeNames(spec, contextName, options.args);
  const outcome = await installContext({
    spec,
    contextName,
    runner: options.runner,
    names,
    strategy: () => contextInstallStrategy(spec, contextName, options.strategy),
    inputStrategy: () => contextInputStrategy(spec, contextName, options.dropins),
  });
  if (outcome.status === "skipped")
    console.error(`skipped config install for ${contextName}: ${outcome.reason}`);
  return outcome.code;
}

export async function main(
  argv: string[],
  deploymentDir: string,
  invokedAs: string,
): Promise<number> {
  return runConfigCommand(parseConfigCommandArgs(argv, deploymentDir, invokedAs));
}
