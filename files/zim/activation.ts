/** Zim context binding, loader projection, cache builds, and health checks. */

import { spawn } from "node:child_process"
import { lstat, mkdir, readFile, stat } from "node:fs/promises"
import { join } from "node:path"

import {
  bindContextConfigs,
  resolvePathSelector,
  type ConfigScope,
  type ConfigSpec,
  type PathSelector,
} from "../config/context.ts"

export type ZimChannel = "zimrc" | "zimenv"

export type ZimActivationContext = {
  config: string
  scope: ConfigScope
  loader_root: PathSelector
  zimrc_home: PathSelector
  zimenv_home: PathSelector
  registry: PathSelector
}

export type ZimCanonical = {
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

export type ZimSpec = {
  version: 2
  defaultContext: string
  contexts: Record<string, ZimActivationContext>
  canonical: ZimCanonical
}

export type Activation = {
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

export type CommandResult = { code: number; stdout: Buffer; stderr: Buffer }

function fail(message: string): never {
  throw new Error(message)
}

export function resolveActivation(name: string, zimSpec: ZimSpec, configSpec: ConfigSpec): Activation {
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

export async function runCommand(file: string, args: string[], capture = false, input?: Buffer): Promise<CommandResult> {
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
  channel: ZimChannel,
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
    const removed = await runCommand(executable, ["--remove-match", `^${legacyBlock}$`, "-o", destination])
    if (removed.code !== 0) fail(`failed to remove legacy block from ${destination}`)
  } catch (error) {
    if ((error as NodeJS.ErrnoException).code !== "ENOENT") throw error
  }
  const installed = await runCommand(executable, ["-n", block, "-C", "true", "-i", "-", "-o", destination], false, content)
  if (installed.code !== 0) fail(`failed to install block ${block} in ${destination}`)
}

export async function buildChannel(channel: ZimChannel, activation: Activation, canonical: ZimCanonical): Promise<void> {
  const home = channel === "zimrc" ? activation.zimrcHome : activation.zimenvHome
  const config = channel === "zimrc" ? activation.zimrc : activation.zimenv
  const script = `ZIM_HOME=$1\nZIM_CONFIG_FILE=$2\ncontroller=$3\nshift 3\nsource "$controller" "$@"`
  const result = await runCommand("zsh", ["-dfc", script, `zimfw-${channel}`, home, config, canonical.controller, "install"])
  if (result.code !== 0) fail(`failed to build ${channel} cache for context ${activation.name}`)
}


export async function installActivation(activation: Activation, canonical: ZimCanonical): Promise<void> {
  const [zimenvLoader, zimrcLoader] = await Promise.all([
    projectLoader("zimenv", activation, canonical),
    projectLoader("zimrc", activation, canonical),
  ])
  await mkdir(activation.loaderRoot, { recursive: true })
  await installLoader(`${canonical.blockPrefix}-zimenv`, zimenvLoader.content, join(activation.loaderRoot, ".zshenv"), canonical.blockPrefix)
  await installLoader(`${canonical.blockPrefix}-zimrc`, zimrcLoader.content, join(activation.loaderRoot, ".zshrc"), canonical.blockPrefix)
  await buildChannel("zimenv", activation, canonical)
  await buildChannel("zimrc", activation, canonical)
}

async function loaderHealthy(
  channel: ZimChannel,
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
  const result = await runCommand(process.env.CONFIG_BLOCK_IN_FILE || "block-in-file", ["--read", "-n", name, destination], true)
  if (result.code !== 0) {
    console.log(`drift: block ${name} is missing or unreadable in ${destination}`)
    return false
  }
  if (projection.content.equals(result.stdout)) return true
  console.log(`drift: block ${name} in ${destination} differs from projected template ${projection.template}`)
  return false
}

async function cacheHealthy(channel: ZimChannel, activation: Activation): Promise<boolean> {
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


export async function activationHealthy(activation: Activation, canonical: ZimCanonical): Promise<boolean> {
  const checks = await Promise.all([
    cacheHealthy("zimenv", activation),
    cacheHealthy("zimrc", activation),
    loaderHealthy("zimenv", activation, canonical),
    loaderHealthy("zimrc", activation, canonical),
  ])
  return checks.every(Boolean)
}
