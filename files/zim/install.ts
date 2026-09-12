#!/usr/bin/env -S node --disable-warning=MODULE_TYPELESS_PACKAGE_JSON
/** Context-parametric Zim install, contribution import, and activation status. */

import { spawn } from "node:child_process"
import { lstat, mkdir, mkdtemp, readFile, readdir, realpath, rm, stat, writeFile } from "node:fs/promises"
import { basename, dirname, join, resolve } from "node:path"
import { tmpdir } from "node:os"
import { fileURLToPath } from "node:url"

import { runConfigContext } from "../config-context.ts"
import {
  bindContextConfigs,
  getConfigContext,
  resolvePathSelector,
  type ConfigScope,
  type ConfigSpec,
  type PathSelector,
} from "../config/context.ts"
import {
  runConfigToolkit,
  type InstallStrategy,
  type Strategy,
  type ToolkitOptions,
} from "../config/toolkit.ts"

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
  zimrcLoader: string
  zimenvLoader: string
  controller: string
  registry: string
  blockPrefix: string
}

type ZimSpec = {
  version: 1
  defaultContext: string
  contexts: Record<string, ZimActivationContext>
  canonical: ZimCanonical
}

type CliOptions = {
  action: Action
  context?: string
  install?: InstallStrategy
  dropins?: Strategy
  invokedAs: string
  zimSpecPath: string
  configSpecPath: string
  configRunner: string
  args: string[]
}

type EffectiveSettings = {
  contextName: string
  install: InstallStrategy
  dropins: Strategy
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

const HELP = `Usage:
  install-zim.sh [--context NAME] [--install assemble|copy|link] [--dropins copy|link]
  install-zim-context.sh [--context NAME] [--dropins copy|link] PRODUCER_DIR
  status-zim.sh [--context NAME]

Precedence per setting: explicit flag, user-created install-zim-CONTEXT.sh alias,
runtime environment, compiled default. Context scope never invokes sudo.`

function fail(message: string): never {
  throw new Error(message)
}

function parseInstall(value: string | undefined, label: string): InstallStrategy {
  if (value === "assemble" || value === "copy" || value === "link") return value
  fail(`${label} must be assemble, copy, or link`)
}

function parseDropins(value: string | undefined, label: string): Strategy {
  if (value === "copy" || value === "link") return value
  fail(`${label} must be copy or link`)
}

export function parseZimArgs(argv: string[], deploymentDir: string): CliOptions {
  let action: Action | undefined
  let context: string | undefined
  let install: InstallStrategy | undefined
  let dropins: Strategy | undefined
  let invokedAs = "install-zim.sh"
  let zimSpecPath = join(deploymentDir, "etc", "zim.spec.json")
  let configSpecPath = join(deploymentDir, "etc", "config.spec.json")
  let configRunner = join(deploymentDir, "bin", "config.sh")
  const args: string[] = []
  for (let index = 0; index < argv.length; index++) {
    const argument = argv[index]
    if (argument === "-h" || argument === "--help") {
      console.log(HELP)
      process.exit(0)
    } else if (!action && (argument === "install" || argument === "import" || argument === "status")) action = argument
    else if (argument === "--context") context = argv[++index] ?? fail("--context requires a name")
    else if (argument === "--install") install = parseInstall(argv[++index], "--install")
    else if (argument === "--dropins") dropins = parseDropins(argv[++index], "--dropins")
    else if (argument === "--invoked-as") invokedAs = basename(argv[++index] ?? fail("--invoked-as requires a basename"))
    else if (argument === "--spec") zimSpecPath = resolve(argv[++index] ?? fail("--spec requires a path"))
    else if (argument === "--config-spec") configSpecPath = resolve(argv[++index] ?? fail("--config-spec requires a path"))
    else if (argument === "--config-runner") configRunner = resolve(argv[++index] ?? fail("--config-runner requires a path"))
    else if (argument.startsWith("-")) fail(`unknown option: ${argument}`)
    else args.push(argument)
  }
  if (!action) fail(HELP)
  if (action !== "import" && args.length > 0) fail(`${action} does not accept positional arguments`)
  if (action === "import" && args.length !== 1) fail("import requires exactly one producer directory")
  return { action, context, install, dropins, invokedAs, zimSpecPath, configSpecPath, configRunner, args }
}

function aliasContext(invokedAs: string, spec: ZimSpec): string | undefined {
  if (invokedAs === "install-zim.sh") return undefined
  const match = /^install-zim-(.+)\.sh$/.exec(invokedAs)
  if (!match) fail(`unsupported Zim command alias ${invokedAs}; use install-zim-CONTEXT.sh or explicit --context`)
  if (!(match[1] in spec.contexts)) fail(`Zim command alias ${invokedAs} names undeclared context ${match[1]}`)
  return match[1]
}

export function resolveSettings(options: CliOptions, spec: ZimSpec, configSpec: ConfigSpec): EffectiveSettings {
  const inferredContext = options.action === "install" && options.context === undefined
    ? aliasContext(options.invokedAs, spec)
    : undefined
  const contextName = options.context ?? inferredContext ?? process.env.COMPFUZOR_ZIM_CONTEXT ?? spec.defaultContext
  const activation = spec.contexts[contextName]
  if (!activation) fail(`unknown Zim context: ${contextName}`)
  const configContext = getConfigContext(configSpec, activation.config)
  if (configContext.scope !== activation.scope) fail(`Zim context ${contextName} scope does not match config context ${activation.config}`)
  const install = options.install ?? parseInstall(
    process.env.COMPFUZOR_ZIM_INSTALL_STRATEGY ?? process.env.COMPFUZOR_CONFIG_INSTALL_STRATEGY ?? configContext.install ?? "assemble",
    "effective install strategy",
  )
  const dropins = options.dropins ?? parseDropins(
    process.env.COMPFUZOR_ZIM_DROPINS_STRATEGY ?? process.env.COMPFUZOR_CONFIG_DROPINS_STRATEGY ?? configContext.dropins ?? "link",
    "effective drop-in strategy",
  )
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

async function command(file: string, args: string[], capture = false): Promise<CommandResult> {
  return await new Promise<CommandResult>((complete, reject) => {
    const child = spawn(file, args, { stdio: capture ? ["ignore", "pipe", "pipe"] : "inherit" })
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
  })
}

function toolkitOptions(options: CliOptions, context: string): ToolkitOptions {
  return {
    context,
    specPath: options.configSpecPath,
    runner: options.configRunner,
    action: "install",
    installStrategy: options.install,
    dropinsStrategy: options.dropins,
    seed: false,
    rebuild: true,
    initiallyDisabled: false,
    format: "human",
    args: [],
  }
}

async function installLoader(block: string, source: string, destination: string, legacyBlock: string): Promise<void> {
  const executable = process.env.CONFIG_BLOCK_IN_FILE || "block-in-file"
  try {
    await lstat(destination)
    const removed = await command(executable, ["--remove-match", `^${legacyBlock}$`, "-o", destination])
    if (removed.code !== 0) fail(`failed to remove legacy block from ${destination}`)
  } catch (error) {
    if ((error as NodeJS.ErrnoException).code !== "ENOENT") throw error
  }
  const installed = await command(executable, ["-n", block, "-C", "true", "-i", source, "-o", destination])
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
  const configured = toolkitOptions({ ...options, install: settings.install, dropins: settings.dropins }, activation.spec.config)
  const configResult = await runConfigToolkit(configured)
  if (configResult !== 0) return configResult
  await mkdir(activation.loaderRoot, { recursive: true })
  await installLoader(`${spec.canonical.blockPrefix}-zimenv`, spec.canonical.zimenvLoader, join(activation.loaderRoot, ".zshenv"), spec.canonical.blockPrefix)
  await installLoader(`${spec.canonical.blockPrefix}-zimrc`, spec.canonical.zimrcLoader, join(activation.loaderRoot, ".zshrc"), spec.canonical.blockPrefix)
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
    const result = await runConfigToolkit({
      ...toolkitOptions(options, activation.spec.config),
      action: "inputs",
      strategy: settings.dropins,
      rebuild: false,
      initiallyDisabled: record.disabled,
      args: ["put", `${record.channel}/${record.channel}`, record.source, basename(record.source)],
    })
    if (result !== 0) return result
    touched.add(record.channel)
  }
  for (const channel of ["zimenv", "zimrc"] as const) {
    if (!touched.has(channel)) continue
    const assembled = await runConfigContext({
      context: activation.spec.config,
      specPath: options.configSpecPath,
      runner: options.configRunner,
      runnerArgs: [channel],
    })
    if (assembled !== 0) return assembled
    await buildChannel(channel, activation, spec.canonical)
  }
  console.log(`install-zim-context: imported ${records.length} fragment(s) for context ${activation.name}`)
  return 0
}

async function blockHealthy(name: string, source: string, destination: string): Promise<boolean> {
  let expected: Buffer
  try {
    expected = await readFile(source)
  } catch (error) {
    console.log(`drift: block source is missing or unreadable: ${source}: ${error instanceof Error ? error.message : String(error)}`)
    return false
  }
  const result = await command(process.env.CONFIG_BLOCK_IN_FILE || "block-in-file", ["--read", "-n", name, destination], true)
  if (result.code !== 0) {
    console.log(`drift: block ${name} is missing or unreadable in ${destination}`)
    return false
  }
  if (expected.equals(result.stdout)) return true
  console.log(`drift: block ${name} in ${destination} differs from ${source}`)
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

async function status(activation: Activation, spec: ZimSpec, deploymentDir: string): Promise<number> {
  const checks = await Promise.all([
    cacheHealthy("zimenv", activation),
    cacheHealthy("zimrc", activation),
    blockHealthy(`${spec.canonical.blockPrefix}-zimenv`, spec.canonical.zimenvLoader, join(activation.loaderRoot, ".zshenv")),
    blockHealthy(`${spec.canonical.blockPrefix}-zimrc`, spec.canonical.zimrcLoader, join(activation.loaderRoot, ".zshrc")),
  ])
  const registryResult = await registry("status", activation, spec.canonical, deploymentDir)
  return checks.every(Boolean) && registryResult === 0 ? 0 : 1
}

export async function runZim(options: CliOptions, deploymentDir: string): Promise<number> {
  const [zimSpec, configSpec] = await Promise.all([
    readFile(options.zimSpecPath, "utf8").then((text) => JSON.parse(text) as ZimSpec),
    readFile(options.configSpecPath, "utf8").then((text) => JSON.parse(text) as ConfigSpec),
  ])
  if (zimSpec.version !== 1) fail(`unsupported Zim spec version: ${String(zimSpec.version)}`)
  const settings = resolveSettings(options, zimSpec, configSpec)
  const activation = resolveActivation(settings.contextName, zimSpec, configSpec)
  if (options.action === "install") return install(options, settings, activation, zimSpec, deploymentDir)
  if (options.action === "import") return importProducer(options, settings, activation, zimSpec)
  return status(activation, zimSpec, deploymentDir)
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
