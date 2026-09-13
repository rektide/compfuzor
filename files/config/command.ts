#!/usr/bin/env -S node --disable-warning=MODULE_TYPELESS_PACKAGE_JSON
/** Thin multicall dispatcher for the fixed CONFIG action vocabulary. */

import { readFile, realpath } from "node:fs/promises"
import { basename, dirname, join, resolve } from "node:path"
import { fileURLToPath } from "node:url"

import { runAssembly } from "./assembly.ts"
import { getConfigContext, selectRecipeNames, type ConfigSpec } from "./context.ts"
import { runInputAction, syncInputs, type InputStrategy } from "./inputs.ts"
import { installContext, type ConfigInstallStrategy } from "./install.ts"
import { resolveSelectedName } from "./invocation.ts"
import { publishOutputs } from "./publication.ts"
import { statusContext } from "./status.ts"
import type { StatusFormat } from "./report.ts"

export const CONFIG_ACTIONS = ["install", "assemble", "sync-inputs", "publish", "inputs", "status"] as const
export type ConfigAction = typeof CONFIG_ACTIONS[number]

type CliOptions = {
  action?: string
  context?: string
  invokedAs: string
  specPath: string
  runner: string
  strategy?: string
  dropins?: string
  seed: boolean
  rebuild: boolean
  initiallyDisabled: boolean
  format: StatusFormat
  check: boolean
  stdout: boolean
  list: boolean
  quiet: boolean
  args: string[]
}

const HELP = `Usage:
  config-install.sh [--context NAME] [--strategy assemble|copy|link] [--dropins copy|link] [CONFIG ...]
  config-assemble.sh [--context NAME] [--check|--stdout|--list] [CONFIG ...]
  config-sync-inputs.sh [--context NAME] [--strategy copy|link] [--seed] [CONFIG ...]
  config-publish.sh [--context NAME] --strategy copy|link [CONFIG ...]
  config-inputs.sh [--context NAME] list|status|put|enable|disable|remove ...
  config-status.sh [--context NAME] [--json|--json-array] [CONFIG ...]

Direct internal use adds --action ACTION. Selection precedence is explicit flag,
recognized manual config-CONTEXT-ACTION.sh alias, environment, compiled default.`

function fail(message: string): never {
  throw new Error(message)
}

function optionValue(argv: string[], index: number, name: string): [string, number] {
  const value = argv[index + 1]
  if (!value) fail(`${name} requires a value`)
  return [value, index + 1]
}

export function parseConfigCommandArgs(argv: string[], deploymentDir: string, invokedAs: string): CliOptions {
  let action: string | undefined
  let context: string | undefined
  let specPath = join(deploymentDir, "etc", "config.spec.json")
  let runner = join(deploymentDir, "bin", "config", "run.sh")
  let strategy: string | undefined
  let dropins: string | undefined
  let seed = false
  let rebuild = true
  let initiallyDisabled = false
  let format: StatusFormat = "human"
  let check = false
  let stdout = false
  let list = false
  let quiet = false
  const args: string[] = []

  for (let index = 0; index < argv.length; index++) {
    const argument = argv[index]
    if (argument === "-h" || argument === "--help") {
      console.log(HELP)
      process.exit(0)
    } else if (argument === "--action") [action, index] = optionValue(argv, index, "--action")
    else if (argument.startsWith("--action=")) action = argument.slice("--action=".length) || fail("--action requires a value")
    else if (argument === "--context") [context, index] = optionValue(argv, index, "--context")
    else if (argument.startsWith("--context=")) context = argument.slice("--context=".length) || fail("--context requires a value")
    else if (argument === "--spec") [specPath, index] = optionValue(argv, index, "--spec")
    else if (argument === "--runner") [runner, index] = optionValue(argv, index, "--runner")
    else if (argument === "--strategy") [strategy, index] = optionValue(argv, index, "--strategy")
    else if (argument === "--dropins") [dropins, index] = optionValue(argv, index, "--dropins")
    else if (argument === "--seed") seed = true
    else if (argument === "--no-rebuild") rebuild = false
    else if (argument === "--disabled") initiallyDisabled = true
    else if (argument === "--json") format = "jsonl"
    else if (argument === "--json-array") format = "array"
    else if (argument === "--check") check = true
    else if (argument === "--stdout") stdout = true
    else if (argument === "--list") list = true
    else if (argument === "-q" || argument === "--quiet") quiet = true
    else if (argument.startsWith("-")) fail(`unknown option: ${argument}`)
    else args.push(argument)
  }
  return {
    action, context, invokedAs, specPath: resolve(specPath), runner: resolve(runner), strategy, dropins,
    seed, rebuild, initiallyDisabled, format, check, stdout, list, quiet, args,
  }
}

type AliasPieces = { action?: ConfigAction; context?: string }

function aliasPieces(options: CliOptions, contextNames: string[]): AliasPieces {
  if (options.action !== undefined && options.context !== undefined) return {}
  if (options.invokedAs === "command.ts") return {}
  const fixed = CONFIG_ACTIONS.find((action) => options.invokedAs === `config-${action}.sh`)
  if (fixed) return { action: options.action === undefined ? fixed : undefined }
  if (!options.invokedAs.startsWith("config-") || !options.invokedAs.endsWith(".sh")) {
    fail(`unsupported config command alias ${options.invokedAs}; use a fixed config-ACTION.sh command or explicit --action and --context`)
  }
  const body = options.invokedAs.slice("config-".length, -".sh".length)
  const full = contextNames.flatMap((context) => CONFIG_ACTIONS
    .filter((action) => body === `${context}-${action}`)
    .map((action) => ({ action, context })))
  if (options.action === undefined && options.context === undefined) {
    if (full.length !== 1) fail(`unknown or ambiguous config command alias ${options.invokedAs}`)
    return full[0]
  }
  if (options.action === undefined) {
    const actions = CONFIG_ACTIONS.filter((candidate) => body.endsWith(`-${candidate}`))
    const longest = Math.max(...actions.map((candidate) => candidate.length), -1)
    const selected = actions.filter((candidate) => candidate.length === longest)
    if (selected.length !== 1) fail(`unknown or ambiguous action in config command alias ${options.invokedAs}`)
    return { action: selected[0] }
  }
  const contexts = contextNames.filter((candidate) => body === candidate || body.startsWith(`${candidate}-`))
  const longest = Math.max(...contexts.map((candidate) => candidate.length), -1)
  const selected = contexts.filter((candidate) => candidate.length === longest)
  if (selected.length !== 1) fail(`unknown or ambiguous context in config command alias ${options.invokedAs}`)
  return { context: selected[0] }
}

function parseInputStrategy(value: string | undefined, label: string): InputStrategy {
  if (value === "copy" || value === "link") return value
  fail(`${label} must be copy or link`)
}

function parseInstallStrategy(value: string | undefined, label: string): ConfigInstallStrategy {
  if (value === "assemble" || value === "copy" || value === "link") return value
  fail(`${label} must be assemble, copy, or link`)
}

function contextInputStrategy(spec: ConfigSpec, contextName: string, explicit?: string): InputStrategy {
  return parseInputStrategy(
    explicit ?? process.env.COMPFUZOR_CONFIG_DROPINS_STRATEGY ?? getConfigContext(spec, contextName).dropins ?? "link",
    "effective config input strategy",
  )
}

function contextInstallStrategy(spec: ConfigSpec, contextName: string, explicit?: string): ConfigInstallStrategy {
  return parseInstallStrategy(
    explicit ?? process.env.COMPFUZOR_CONFIG_INSTALL_STRATEGY ?? getConfigContext(spec, contextName).install ?? "assemble",
    "effective config install strategy",
  )
}

function rejectIrrelevantFlags(options: CliOptions, action: ConfigAction): void {
  if (action !== "assemble" && (options.check || options.stdout || options.list || options.quiet)) fail(`${action} does not accept assembly display flags`)
  if (action !== "status" && action !== "inputs" && options.format !== "human") fail(`${action} does not accept status format flags`)
  if (action !== "sync-inputs" && options.seed) fail(`${action} does not accept --seed`)
  if (action !== "inputs" && (!options.rebuild || options.initiallyDisabled)) fail(`${action} does not accept input mutation flags`)
  if (action !== "install" && options.dropins !== undefined) fail(`${action} does not accept --dropins`)
}

export async function runConfigCommand(options: CliOptions): Promise<number> {
  const spec = JSON.parse(await readFile(options.specPath, "utf8")) as ConfigSpec
  const contextNames = Object.keys(spec.contexts ?? {})
  const inferred = aliasPieces(options, contextNames)
  const action = resolveSelectedName({
    explicit: options.action,
    invokedAs: options.invokedAs,
    inferAlias: () => inferred.action,
    fallback: "",
    declared: CONFIG_ACTIONS,
    label: "config action",
  }) as ConfigAction
  const contextName = resolveSelectedName({
    explicit: options.context,
    invokedAs: options.invokedAs,
    inferAlias: () => inferred.context,
    environment: process.env.COMPFUZOR_CONFIG_CONTEXT ?? process.env.COMPFUZOR_CONTEXT,
    fallback: spec.defaultContext,
    declared: contextNames,
    label: "config context",
  })
  const context = getConfigContext(spec, contextName)
  rejectIrrelevantFlags(options, action)
  if (context.canonical && !["assemble", "status"].includes(action)) {
    fail(`config ${action} is not meaningful for canonical source=destination context; use assemble or status`)
  }

  if (action === "assemble") {
    if (options.check && options.stdout) fail("--check and --stdout are mutually exclusive")
    if (options.list) {
      if (options.args.length > 0) fail("--list does not accept recipe names")
      for (const name of selectRecipeNames(spec, contextName, [], false).sort()) console.log(name)
      return 0
    }
    const names = selectRecipeNames(spec, contextName, options.args)
    if (options.stdout && names.length !== 1) fail("--stdout requires exactly one selected config")
    return runAssembly({ spec, contextName, runner: options.runner, names, check: options.check, stdout: options.stdout, quiet: options.quiet })
  }

  if (action === "status") {
    const names = selectRecipeNames(spec, contextName, options.args)
    return statusContext({ spec, contextName, runner: options.runner, names, format: options.format })
  }

  if (action === "sync-inputs") {
    const names = selectRecipeNames(spec, contextName, options.args)
    const strategy = contextInputStrategy(spec, contextName, options.strategy)
    return syncInputs({ spec, contextName, runner: options.runner, names, strategy, seed: options.seed })
  }

  if (action === "publish") {
    const names = selectRecipeNames(spec, contextName, options.args)
    const strategy = parseInputStrategy(options.strategy ?? process.env.COMPFUZOR_CONFIG_PUBLISH_STRATEGY, "config publish strategy")
    return publishOutputs({ spec, contextName, names, strategy })
  }

  if (action === "inputs") {
    const inputAction = options.args[0]
    const strategy = inputAction === "put"
      ? contextInputStrategy(spec, contextName, options.strategy)
      : options.strategy === undefined ? undefined : fail(`${inputAction ?? "inputs"} does not accept --strategy`)
    return runInputAction({
      spec, contextName, runner: options.runner, strategy, rebuild: options.rebuild,
      initiallyDisabled: options.initiallyDisabled, format: options.format,
    }, options.args)
  }

  const names = selectRecipeNames(spec, contextName, options.args)
  const outcome = await installContext({
    spec,
    contextName,
    runner: options.runner,
    names,
    strategy: () => contextInstallStrategy(spec, contextName, options.strategy),
    inputStrategy: () => contextInputStrategy(spec, contextName, options.dropins),
  })
  if (outcome.status === "skipped") console.error(`skipped config install for ${contextName}: ${outcome.reason}`)
  return outcome.code
}

export async function main(argv: string[] = process.argv.slice(2), modulePath: string = fileURLToPath(import.meta.url), invokedAs: string = basename(process.argv[1] ?? modulePath)): Promise<number> {
  const realModulePath = await realpath(modulePath)
  const deploymentDir = resolve(dirname(realModulePath), "../..")
  return runConfigCommand(parseConfigCommandArgs(argv, deploymentDir, invokedAs))
}

const argvPath = process.argv[1]
if (argvPath) {
  Promise.all([realpath(argvPath), realpath(fileURLToPath(import.meta.url))]).then(
    ([realArgvPath, realModulePath]) => {
      if (realArgvPath !== realModulePath) return
      return main(process.argv.slice(2), realModulePath, basename(argvPath)).then(
        (code) => { process.exitCode = code },
        (error: unknown) => {
          console.error(error instanceof Error ? error.stack : String(error))
          process.exitCode = 2
        },
      )
    },
    (error: unknown) => {
      console.error(error instanceof Error ? error.stack : String(error))
      process.exitCode = 2
    },
  )
}
