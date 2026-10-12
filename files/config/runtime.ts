/** Thin multicall dispatcher for the fixed CONFIG action vocabulary. */

import { readFile } from "node:fs/promises";
import { join, resolve } from "node:path";

import { runAssembly } from "./assembly.ts";
import {
  CONFIG_ACTIONS,
  configAliasPieces,
  parseConfigCommandArgs,
  rejectIrrelevantFlags,
  type ConfigAction,
  type ConfigCliOptions,
} from "./cli.ts";
import {
  bindContextConfigs,
  getConfigContext,
  selectRecipeNames,
  type ConfigScope,
  type ConfigSpec,
} from "./context.ts";
import {
  admitInputArgs,
  inputActionRecipeNames,
  runInputAction,
  syncInputs,
  type InputStrategy,
} from "./inputs.ts";
import { installContext, type ConfigInstallStrategy } from "./install.ts";
import { resolveSelectedName } from "./invocation.ts";
import { publishOutputs } from "./publication.ts";
import { statusContext } from "./status.ts";

export { CONFIG_ACTIONS, parseConfigCommandArgs };
export type { ConfigAction, ConfigCliOptions };

/** Optional general-action assertion; low-level CONFIG calls retain their precedence. */
export type ConfigActionBinding = {
  action: ConfigAction;
  audience: ConfigScope;
  context: string;
};

/** Serializable loaded selection, admitted without registration/publication effects. */
export type AdmittedConfigCommand = {
  spec: ConfigSpec;
  options: ConfigCliOptions;
  action: ConfigAction;
  contextName: string;
};

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

export async function admitConfigCommand(
  options: ConfigCliOptions,
  binding?: ConfigActionBinding,
): Promise<AdmittedConfigCommand> {
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
    fallback: binding?.context ?? spec.defaultContext,
    declared: contextNames,
    label: "config context",
  });
  const context = getConfigContext(spec, contextName);
  if (binding) {
    if (action !== binding.action)
      fail(`config action ${action} does not match declared ${binding.action} operation`);
    if (context.canonical) fail("canonical donor context is not a receiver action audience");
    if (context.scope !== binding.audience)
      fail(
        `config context ${contextName} has ${context.scope} scope, not selected ${binding.audience} audience`,
      );
    if (action === "install" && spec.installOwner !== undefined) {
      if (typeof spec.installOwner !== "string") fail("config install owner must be a domain name");
      if (spec.installOwner !== "config")
        fail(`config installation is owned by ${spec.installOwner}, not config`);
    }
  }
  rejectIrrelevantFlags(options, action);
  const canonicalInputAction = action === "inputs" ? options.args[0] : undefined;
  const canonicalAllowed =
    action === "assemble" ||
    action === "status" ||
    (action === "sync-inputs" &&
      selectRecipeNames(spec, contextName, options.args).some((name) =>
        spec.configs[name].inputs.some((input) => input.fuzings),
      )) ||
    (action === "inputs" &&
      ["list", "status", "enable", "disable", "fuze", "fuzings"].includes(
        canonicalInputAction ?? "",
      ));
  if (context.canonical && !canonicalAllowed) {
    fail(
      `config ${action} is not meaningful for canonical source=destination context; use assemble, status, or explicit input list/status/enable/disable`,
    );
  }

  if (!binding)
    return { spec, options: { ...options, args: [...options.args] }, action, contextName };
  const frozen = structuredClone(spec);
  const fixed = { ...options, args: [...options.args], action, context: contextName };
  if (action === "inputs")
    fixed.args = admitInputArgs(
      { spec, contextName, runner: fixed.runner, initiallyDisabled: fixed.initiallyDisabled },
      fixed.args,
    );
  const names =
    action === "inputs"
      ? inputActionRecipeNames(spec, contextName, fixed.args)
      : selectRecipeNames(spec, contextName, fixed.args, !fixed.list);
  const resolved = bindContextConfigs(spec, contextName, names);
  frozen.configs = Object.fromEntries(names.map((name) => [name, frozen.configs[name]]));
  frozen.contexts = {
    [contextName]: {
      ...context,
      root: { path: "/" },
      subpath: undefined,
      configs: Object.fromEntries(
        names.map((name) => [
          name,
          {
            output: { path: resolved.configs[name].output },
            inputs: resolved.configs[name].inputs.map((input) => ({
              path: String(input.file ?? input.directory),
            })),
          },
        ]),
      ),
    },
  };
  if (action === "assemble") {
    if (fixed.strategy !== undefined) fail("assemble does not accept --strategy");
    if (fixed.check && fixed.stdout) fail("--check and --stdout are mutually exclusive");
    if (fixed.list && fixed.args.length) fail("--list does not accept recipe names");
    const selected = selectRecipeNames(frozen, contextName, fixed.args, !fixed.list);
    if (fixed.stdout && selected.length !== 1)
      fail("--stdout requires exactly one selected config");
  } else if (action === "inputs") {
    if (fixed.args[0] === "put")
      fixed.strategy = contextInputStrategy(frozen, contextName, fixed.strategy);
    else {
      if (fixed.strategy !== undefined) fail(`${fixed.args[0]} does not accept --strategy`);
      if (fixed.initiallyDisabled || !fixed.rebuild)
        fail(`${fixed.args[0]} does not accept put-only flags --disabled/--no-rebuild`);
    }
  } else {
    selectRecipeNames(frozen, contextName, fixed.args);
    if (action === "install") {
      fixed.strategy = contextInstallStrategy(frozen, contextName, fixed.strategy);
      fixed.dropins = contextInputStrategy(frozen, contextName, fixed.dropins);
    } else if (action === "sync-inputs")
      fixed.strategy = contextInputStrategy(frozen, contextName, fixed.strategy);
    else if (action === "publish")
      fixed.strategy = parseInputStrategy(
        fixed.strategy ?? process.env.COMPFUZOR_CONFIG_PUBLISH_STRATEGY,
        "config publish strategy",
      );
    else if (fixed.strategy !== undefined) fail(`${action} does not accept --strategy`);
  }
  return { spec: frozen, options: fixed, action, contextName };
}

export async function runAdmittedConfigCommand(admitted: AdmittedConfigCommand): Promise<number> {
  const { spec, options, action, contextName } = admitted;

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

export async function runConfigCommand(options: ConfigCliOptions): Promise<number> {
  return runAdmittedConfigCommand(await admitConfigCommand(options));
}

export async function main(
  argv: string[],
  deploymentDir: string,
  invokedAs: string,
): Promise<number> {
  const options = parseConfigCommandArgs(argv, deploymentDir, invokedAs);
  if (
    !CONFIG_ACTIONS.some((action) => invokedAs === `config-${action}.sh`) &&
    invokedAs.startsWith("config-") &&
    invokedAs.endsWith(".sh")
  ) {
    let index: { definitions: Record<string, { spec: string }> } | undefined;
    try {
      index = JSON.parse(await readFile(join(deploymentDir, "etc/config/instances.json"), "utf8"));
    } catch (error) {
      if ((error as NodeJS.ErrnoException).code !== "ENOENT") throw error;
    }
    for (const [identity, binding] of Object.entries(index?.definitions ?? {})) {
      const action = CONFIG_ACTIONS.find(
        (candidate) => invokedAs === `config-${identity}-${candidate}.sh`,
      );
      if (!action) continue;
      options.action ??= action;
      options.definitionAlias = true;
      if (!options.specExplicit && options.definition === undefined)
        options.specPath = resolve(deploymentDir, binding.spec);
      break;
    }
  }
  return runConfigCommand(options);
}
