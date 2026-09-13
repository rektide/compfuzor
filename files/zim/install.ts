#!/usr/bin/env -S node --disable-warning=MODULE_TYPELESS_PACKAGE_JSON
/** Context-parametric Zim install, contribution import, and activation status. */

import { spawn } from "node:child_process"
import { lstat, mkdir, mkdtemp, readFile, readdir, realpath, rm, stat, writeFile } from "node:fs/promises"
import { basename, dirname, join, resolve } from "node:path"
import { tmpdir } from "node:os"
import { fileURLToPath } from "node:url"
import { parseArgs } from "node:util"

import { runAssembly } from "../config/assembly.ts"
import {
  bindContextConfigs,
  getConfigContext,
  resolvePathSelector,
  type ConfigScope,
  type ConfigSpec,
  type PathSelector,
} from "../config/context.ts"
import {
  installContext,
  type ConfigInstallStrategy,
} from "../config/install.ts"
import { putInput, type InputStrategy } from "../config/inputs.ts"
import { resolveSelectedName } from "../config/invocation.ts"
import { statusContext } from "../config/status.ts"

type Action = "install" | "import" | "status"

type ZimActivationContext = {
  config: string
  scope: ConfigScope
  loader_root: PathSelector
  zimrc_home: PathSelector
  zimenv_home: PathSelector
  registry: PathSelector
}

type ZimCanonical = {
  zimrc: string
  zimenv: string
  zimrcLegacy: string[]
  zimenvLegacy: string[]
  zimrcLoaderTemplate: string
  zimenvLoaderTemplate: string
  controller: string
  emergencyModule: string
  registry: string
  blockPrefix: string
}

type ZimSpec = {
  version: 2
  defaultContext: string
  contexts: Record<string, ZimActivationContext>
  canonical: ZimCanonical
}

type CliOptions = {
  action: Action
  context?: string
  install?: ConfigInstallStrategy
  dropins?: InputStrategy
  invokedAs: string
  zimSpecPath: string
  configSpecPath: string
  configRunner: string
  activationOnly: boolean
  args: string[]
}

type EffectiveSettings = {
  contextName: string
  install?: ConfigInstallStrategy
  dropins?: InputStrategy
}

type Activation = {
  name: string
  spec: ZimActivationContext
  configSpec: ConfigSpec
  zimrc: string
  zimenv: string
  loaderRoot: string
  zimrcHome: string
  zimenvHome: string
  registry: string
}

type CommandResult = { code: number; stdout: Buffer; stderr: Buffer }

const HELP: Record<Action, string> = {
  install: `Usage: install-zim.sh [--context NAME] [--install assemble|copy|link] [--dropins copy|link]

Install and activate Zim for a selected context: install its CONFIG recipes,
project startup loaders, build both caches, and publish the registry link.

Options:
  --context NAME                 Select a declared Zim context
  --install assemble|copy|link  Override CONFIG output installation
  --dropins copy|link            Override CONFIG input delivery`,
  import: `Usage: install-zim-context.sh [--context NAME] [--dropins copy|link] PRODUCER_DIR

Import a producer's Zim fragments into a selected consumer context, then rebuild
only the channels that received fragments.

Options:
  --context NAME       Select a declared Zim context
  --dropins copy|link  Select imported fragment representation`,
  status: `Usage: status-zim.sh [--context NAME] [--activation-only]

Report Zim activation health: CONFIG state, startup loaders, both caches, and
the registry link. Exit 0 is clean, 1 is drift, and 2 is an evaluation error.

Options:
  --context NAME     Select a declared Zim context
  --activation-only  Skip CONFIG rows (used by aggregate status)`,
}

function fail(message: string): never {
  throw new Error(message)
}

function truthy(value: string | undefined): boolean {
  return ["1", "true", "y", "yes"].includes(value?.trim().toLowerCase() ?? "")
}

function parseInstall(value: string | undefined, label: string): ConfigInstallStrategy {
  if (value === "assemble" || value === "copy" || value === "link") return value
  fail(`${label} must be assemble, copy, or link`)
}

function parseDropins(value: string | undefined, label: string): InputStrategy {
  if (value === "copy" || value === "link") return value
  fail(`${label} must be copy or link`)
}

export function parseZimArgs(argv: string[], deploymentDir: string): CliOptions {
  const { values, positionals } = parseArgs({
    args: argv,
    strict: true,
    allowPositionals: true,
    options: {
      context: { type: "string" },
      install: { type: "string" },
      dropins: { type: "string" },
      "invoked-as": { type: "string" },
      spec: { type: "string" },
      "config-spec": { type: "string" },
      "config-runner": { type: "string" },
      "activation-only": { type: "boolean" },
      help: { type: "boolean", short: "h" },
    },
  })
  const actionIndex = positionals.findIndex((value) => value === "install" || value === "import" || value === "status")
  const action = actionIndex < 0 ? undefined : positionals[actionIndex] as Action
  if (values.help) {
    console.log(action ? HELP[action] : Object.values(HELP).join("\n\n"))
    process.exit(0)
  }
  if (!action) fail("expected Zim action: install, import, or status")
  const args = positionals.toSpliced(actionIndex, 1)
  if (action !== "import" && args.length > 0) fail(`${action} does not accept positional arguments`)
  if (action === "import" && args.length !== 1) fail("import requires exactly one producer directory")
  if (values["activation-only"] && action !== "status") fail("--activation-only requires status")
  return {
    action,
    context: values.context,
    install: values.install === undefined ? undefined : parseInstall(values.install, "--install"),
    dropins: values.dropins === undefined ? undefined : parseDropins(values.dropins, "--dropins"),
    invokedAs: basename(values["invoked-as"] ?? "install-zim.sh"),
    zimSpecPath: resolve(values.spec ?? join(deploymentDir, "etc", "zim.spec.json")),
    configSpecPath: resolve(values["config-spec"] ?? join(deploymentDir, "etc", "config.spec.json")),
    configRunner: resolve(values["config-runner"] ?? join(deploymentDir, "bin", "config", "run.sh")),
    activationOnly: values["activation-only"] ?? false,
    args,
  }
}

function aliasContext(invokedAs: string, spec: ZimSpec): string | undefined {
  if (invokedAs === "install-zim.sh") return undefined
  const match = /^install-zim-(.+)\.sh$/.exec(invokedAs)
  if (!match) fail(`unsupported Zim command alias ${invokedAs}; use install-zim-CONTEXT.sh or explicit --context`)
  if (!(match[1] in spec.contexts)) fail(`Zim command alias ${invokedAs} names undeclared context ${match[1]}`)
  return match[1]
}

export function resolveSettings(options: CliOptions, spec: ZimSpec, configSpec: ConfigSpec): EffectiveSettings {
  const contextName = resolveSelectedName({
    explicit: options.context,
    invokedAs: options.invokedAs,
    inferAlias: (invokedAs) => options.action === "install" ? aliasContext(invokedAs, spec) : undefined,
    environment: process.env.COMPFUZOR_ZIM_CONTEXT ?? process.env.COMPFUZOR_CONTEXT,
    fallback: spec.defaultContext,
    declared: Object.keys(spec.contexts),
    label: "Zim context",
  })
  const activation = spec.contexts[contextName]
  const configContext = getConfigContext(configSpec, activation.config)
  if (configContext.scope !== activation.scope) fail(`Zim context ${contextName} scope does not match config context ${activation.config}`)
  const install = options.action === "install" ? options.install : undefined
  const dropins = options.action === "import"
    ? options.dropins ?? parseDropins(
      process.env.COMPFUZOR_ZIM_DROPINS_STRATEGY ?? process.env.COMPFUZOR_CONFIG_DROPINS_STRATEGY ?? configContext.dropins ?? "link",
      "effective drop-in strategy",
    )
    : options.action === "install" ? options.dropins : undefined
  return { contextName, install, dropins }
}

function resolveActivation(name: string, zimSpec: ZimSpec, configSpec: ConfigSpec): Activation {
  const spec = zimSpec.contexts[name] ?? fail(`unknown Zim context: ${name}`)
  const bound = bindContextConfigs(configSpec, spec.config, ["zimrc", "zimenv"])
  return {
    name,
    spec,
    configSpec,
    zimrc: bound.configs.zimrc.output,
    zimenv: bound.configs.zimenv.output,
    loaderRoot: resolvePathSelector(spec.loader_root, undefined, `Zim context ${name}.loader_root`),
    zimrcHome: resolvePathSelector(spec.zimrc_home, undefined, `Zim context ${name}.zimrc_home`),
    zimenvHome: resolvePathSelector(spec.zimenv_home, undefined, `Zim context ${name}.zimenv_home`),
    registry: resolvePathSelector(spec.registry, undefined, `Zim context ${name}.registry`),
  }
}

async function command(file: string, args: string[], capture = false, input?: Buffer): Promise<CommandResult> {
  return await new Promise<CommandResult>((complete, reject) => {
    const child = spawn(file, args, {
      stdio: capture
        ? [input ? "pipe" : "ignore", "pipe", "pipe"]
        : input
          ? ["pipe", "inherit", "inherit"]
          : "inherit",
    })
    const stdout: Buffer[] = []
    const stderr: Buffer[] = []
    child.stdout?.on("data", (chunk: Buffer | string) => stdout.push(Buffer.from(chunk)))
    child.stderr?.on("data", (chunk: Buffer | string) => stderr.push(Buffer.from(chunk)))
    child.once("error", reject)
    child.once("exit", (code, signal) => complete({
      code: signal ? 1 : (code ?? 1),
      stdout: Buffer.concat(stdout),
      stderr: Buffer.concat(stderr),
    }))
    if (input) child.stdin?.end(input)
  })
}

export function zshQuote(value: string): string {
  if (value.includes("\0")) fail("cannot project a Zsh path containing NUL")
  return `'${value.replaceAll("'", "'\\''")}'`
}

function replaceLoaderToken(template: string, token: string, value: string, source: string): string {
  const first = template.indexOf(token)
  if (first < 0) fail(`Zim loader template ${source} is missing ${token}`)
  if (template.indexOf(token, first + token.length) >= 0) fail(`Zim loader template ${source} repeats ${token}`)
  return `${template.slice(0, first)}${value}${template.slice(first + token.length)}`
}

async function projectLoader(
  channel: "zimrc" | "zimenv",
  activation: Activation,
  canonical: ZimCanonical,
): Promise<{ content: Buffer; template: string }> {
  const template = channel === "zimrc" ? canonical.zimrcLoaderTemplate : canonical.zimenvLoaderTemplate
  const home = channel === "zimrc" ? activation.zimrcHome : activation.zimenvHome
  const config = channel === "zimrc" ? activation.zimrc : activation.zimenv
  const legacy = channel === "zimrc" ? canonical.zimrcLegacy : canonical.zimenvLegacy
  let projected = await readFile(template, "utf8")
  const replacements: Array<[string, string]> = [
    ["@@ZIM_CACHE_HOME@@", zshQuote(home)],
    ["@@ZIM_CONFIG_OUTPUT@@", zshQuote(config)],
    ["@@ZIM_LEGACY_CONFIG_PATTERN@@", [...new Set(legacy)].map(zshQuote).join("|")],
    ["@@ZIM_CONTROLLER@@", zshQuote(canonical.controller)],
  ]
  if (channel === "zimrc") {
    replacements.push(["@@ZIM_EMERGENCY_MODULE@@", zshQuote(canonical.emergencyModule)])
  }
  for (const [token, value] of replacements) projected = replaceLoaderToken(projected, token, value, template)
  const unknown = projected.match(/@@ZIM_[A-Z_]+@@/)
  if (unknown) fail(`Zim loader template ${template} has unsupported placeholder ${unknown[0]}`)
  // block-in-file --read returns the block body without its terminal separator.
  // Normalize one template boundary newline so install and status share bytes.
  projected = projected.replace(/\r?\n$/, "")
  return { content: Buffer.from(projected), template }
}

async function installLoader(block: string, content: Buffer, destination: string, legacyBlock: string): Promise<void> {
  const executable = process.env.CONFIG_BLOCK_IN_FILE || "block-in-file"
  try {
    await lstat(destination)
    const removed = await command(executable, ["--remove-match", `^${legacyBlock}$`, "-o", destination])
    if (removed.code !== 0) fail(`failed to remove legacy block from ${destination}`)
  } catch (error) {
    if ((error as NodeJS.ErrnoException).code !== "ENOENT") throw error
  }
  const installed = await command(executable, ["-n", block, "-C", "true", "-i", "-", "-o", destination], false, content)
  if (installed.code !== 0) fail(`failed to install block ${block} in ${destination}`)
}

async function buildChannel(channel: "zimrc" | "zimenv", activation: Activation, canonical: ZimCanonical): Promise<void> {
  const home = channel === "zimrc" ? activation.zimrcHome : activation.zimenvHome
  const config = channel === "zimrc" ? activation.zimrc : activation.zimenv
  const script = `ZIM_HOME=$1\nZIM_CONFIG_FILE=$2\ncontroller=$3\nshift 3\nsource "$controller" "$@"`
  const result = await command("zsh", ["-dfc", script, `zimfw-${channel}`, home, config, canonical.controller, "install"])
  if (result.code !== 0) fail(`failed to build ${channel} cache for context ${activation.name}`)
}

async function withRegistryManifest<T>(activation: Activation, canonical: ZimCanonical, callback: (path: string) => Promise<T>): Promise<T> {
  const temporary = await mkdtemp(join(tmpdir(), "compfuzor-zim-registry-"))
  const path = join(temporary, "links.json")
  const manifest = {
    version: 1,
    deployment: { dir: dirname(canonical.controller) },
    links: [{
      id: `zim-registry-${activation.name}`,
      scope: activation.spec.scope,
      src: canonical.registry,
      dest: activation.registry,
      policy: "replace",
      state: "present",
    }],
  }
  try {
    await writeFile(path, JSON.stringify(manifest), { mode: 0o600 })
    return await callback(path)
  } finally {
    await rm(temporary, { recursive: true, force: true })
  }
}

async function registry(action: "apply" | "status", activation: Activation, canonical: ZimCanonical, deploymentDir: string): Promise<number> {
  return withRegistryManifest(activation, canonical, async (manifest) => {
    const args = [action, "--scope", activation.spec.scope]
    if (action === "apply") args.push("--sudo", "never")
    args.push(manifest)
    return (await command(join(deploymentDir, "bin", "links.ts"), args)).code
  })
}

async function install(options: CliOptions, settings: EffectiveSettings, activation: Activation, spec: ZimSpec, deploymentDir: string): Promise<number> {
  const configContext = getConfigContext(activation.configSpec, activation.spec.config)
  const configResult = await installContext({
    spec: activation.configSpec,
    contextName: activation.spec.config,
    runner: options.configRunner,
    names: ["zimrc", "zimenv"],
    strategy: () => settings.install ?? parseInstall(
      process.env.COMPFUZOR_ZIM_INSTALL_STRATEGY ?? process.env.COMPFUZOR_CONFIG_INSTALL_STRATEGY ?? configContext.install ?? "assemble",
      "effective install strategy",
    ),
    inputStrategy: () => settings.dropins ?? parseDropins(
      process.env.COMPFUZOR_ZIM_DROPINS_STRATEGY ?? process.env.COMPFUZOR_CONFIG_DROPINS_STRATEGY ?? configContext.dropins ?? "link",
      "effective drop-in strategy",
    ),
  })
  if (configResult.code !== 0) return configResult.code
  if (configResult.status === "skipped") {
    const available = await Promise.all([activation.zimenv, activation.zimrc].map(async (path) => {
      try {
        return (await stat(path)).isFile()
      } catch {
        return false
      }
    }))
    console.error(`skipped Zim config install for ${activation.name}: ${configResult.reason}`)
    if (!available.every(Boolean)) {
      console.error(`skipped remaining Zim install for ${activation.name}: required config outputs are unavailable`)
      return 0
    }
  }
  const [zimenvLoader, zimrcLoader] = await Promise.all([
    projectLoader("zimenv", activation, spec.canonical),
    projectLoader("zimrc", activation, spec.canonical),
  ])
  await mkdir(activation.loaderRoot, { recursive: true })
  await installLoader(`${spec.canonical.blockPrefix}-zimenv`, zimenvLoader.content, join(activation.loaderRoot, ".zshenv"), spec.canonical.blockPrefix)
  await installLoader(`${spec.canonical.blockPrefix}-zimrc`, zimrcLoader.content, join(activation.loaderRoot, ".zshrc"), spec.canonical.blockPrefix)
  await buildChannel("zimenv", activation, spec.canonical)
  await buildChannel("zimrc", activation, spec.canonical)
  const registryResult = await registry("apply", activation, spec.canonical, deploymentDir)
  if (registryResult !== 0) return registryResult
  return 0
}

async function inventoryProducer(producer: string): Promise<Array<{ channel: "zimrc" | "zimenv"; source: string; disabled: boolean }>> {
  const records: Array<{ channel: "zimrc" | "zimenv"; source: string; disabled: boolean }> = []
  const seen = new Set<string>()
  for (const channel of ["zimenv", "zimrc"] as const) {
    for (const state of ["active", "disabled"] as const) {
      const directory = join(producer, "etc", "zim", channel, state)
      let entries
      try {
        entries = await readdir(directory, { withFileTypes: true, encoding: "utf8" })
      } catch (error) {
        if ((error as NodeJS.ErrnoException).code === "ENOENT") continue
        throw error
      }
      for (const entry of entries.sort((a, b) => a.name.localeCompare(b.name))) {
        if (!entry.name.endsWith(".conf") || (!entry.isFile() && !entry.isSymbolicLink())) continue
        const key = `${channel}/${entry.name}`
        if (seen.has(key)) fail(`producer has both active and disabled entries: ${key}`)
        seen.add(key)
        records.push({ channel, source: join(directory, entry.name), disabled: state === "disabled" })
      }
    }
  }
  return records
}

async function importProducer(options: CliOptions, settings: EffectiveSettings, activation: Activation, spec: ZimSpec): Promise<number> {
  const records = await inventoryProducer(resolve(options.args[0]))
  const touched = new Set<"zimrc" | "zimenv">()
  for (const record of records) {
    const result = await putInput({
      spec: activation.configSpec,
      contextName: activation.spec.config,
      runner: options.configRunner,
      strategy: settings.dropins!,
      rebuild: false,
      initiallyDisabled: record.disabled,
      selector: `${record.channel}/${record.channel}`,
      source: record.source,
      name: basename(record.source),
    })
    if (result !== 0) return result
    touched.add(record.channel)
  }
  for (const channel of ["zimenv", "zimrc"] as const) {
    if (!touched.has(channel)) continue
    const assembled = await runAssembly({
      spec: activation.configSpec,
      contextName: activation.spec.config,
      runner: options.configRunner,
      names: [channel],
    })
    if (assembled !== 0) return assembled
    await buildChannel(channel, activation, spec.canonical)
  }
  console.log(`install-zim-context: imported ${records.length} fragment(s) for context ${activation.name}`)
  return 0
}

async function loaderHealthy(
  channel: "zimrc" | "zimenv",
  activation: Activation,
  canonical: ZimCanonical,
): Promise<boolean> {
  let projection: { content: Buffer; template: string }
  try {
    projection = await projectLoader(channel, activation, canonical)
  } catch (error) {
    const template = channel === "zimrc" ? canonical.zimrcLoaderTemplate : canonical.zimenvLoaderTemplate
    console.log(`drift: ${channel} loader template is missing or invalid: ${template}: ${error instanceof Error ? error.message : String(error)}`)
    return false
  }
  const name = `${canonical.blockPrefix}-${channel}`
  const destination = join(activation.loaderRoot, channel === "zimrc" ? ".zshrc" : ".zshenv")
  const result = await command(process.env.CONFIG_BLOCK_IN_FILE || "block-in-file", ["--read", "-n", name, destination], true)
  if (result.code !== 0) {
    console.log(`drift: block ${name} is missing or unreadable in ${destination}`)
    return false
  }
  if (projection.content.equals(result.stdout)) return true
  console.log(`drift: block ${name} in ${destination} differs from projected template ${projection.template}`)
  return false
}

async function cacheHealthy(channel: "zimrc" | "zimenv", activation: Activation): Promise<boolean> {
  const config = channel === "zimrc" ? activation.zimrc : activation.zimenv
  const home = channel === "zimrc" ? activation.zimrcHome : activation.zimenvHome
  try {
    const [configStat, cacheStat] = await Promise.all([stat(config), stat(join(home, "init.zsh"))])
    if (cacheStat.mtimeMs > configStat.mtimeMs) return true
  } catch {
    // The common drift message below names both expected paths.
  }
  console.log(`drift: ${channel} cache ${join(home, "init.zsh")} is missing or stale for ${config}`)
  return false
}

async function status(activation: Activation, spec: ZimSpec, deploymentDir: string, configRunner: string, activationOnly: boolean): Promise<number> {
  const configResult = activationOnly ? 0 : await statusContext({
      spec: activation.configSpec,
      contextName: activation.spec.config,
      runner: configRunner,
      names: ["zimrc", "zimenv"],
      format: "human",
    })
  const checks = await Promise.all([
    cacheHealthy("zimenv", activation),
    cacheHealthy("zimrc", activation),
    loaderHealthy("zimenv", activation, spec.canonical),
    loaderHealthy("zimrc", activation, spec.canonical),
  ])
  const registryResult = await registry("status", activation, spec.canonical, deploymentDir)
  if (configResult === 2 || registryResult === 2) return 2
  return configResult === 0 && checks.every(Boolean) && registryResult === 0 ? 0 : 1
}

export async function runZim(options: CliOptions, deploymentDir: string): Promise<number> {
  if (options.action !== "status" && truthy(process.env.COMPFUZOR_ZIM_BYPASS)) {
    console.error(`skipped Zim ${options.action}: COMPFUZOR_ZIM_BYPASS`)
    return 0
  }
  const [zimSpec, configSpec] = await Promise.all([
    readFile(options.zimSpecPath, "utf8").then((text) => JSON.parse(text) as ZimSpec),
    readFile(options.configSpecPath, "utf8").then((text) => JSON.parse(text) as ConfigSpec),
  ])
  if (zimSpec.version !== 2) {
    fail(`unsupported Zim spec version: ${String(zimSpec.version)}; rerender the deployment with the current playbook (expected version 2)`)
  }
  const settings = resolveSettings(options, zimSpec, configSpec)
  const activation = resolveActivation(settings.contextName, zimSpec, configSpec)
  if (options.action === "install") return install(options, settings, activation, zimSpec, deploymentDir)
  if (options.action === "import") return importProducer(options, settings, activation, zimSpec)
  return status(activation, zimSpec, deploymentDir, options.configRunner, options.activationOnly)
}

export async function main(argv: string[] = process.argv.slice(2), modulePath: string = fileURLToPath(import.meta.url)): Promise<number> {
  const realModule = await realpath(modulePath)
  const deploymentDir = resolve(dirname(realModule), "../..")
  return runZim(parseZimArgs(argv, deploymentDir), deploymentDir)
}

const argvPath = process.argv[1]
if (argvPath) {
  Promise.all([realpath(argvPath), realpath(fileURLToPath(import.meta.url))]).then(
    ([realArgv, realModule]) => {
      if (realArgv !== realModule) return
      return main(process.argv.slice(2), realModule).then(
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
