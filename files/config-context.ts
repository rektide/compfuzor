#!/usr/bin/env -S node --disable-warning=MODULE_TYPELESS_PACKAGE_JSON
/** Resolve one compiled consumer context, then reuse the shared config runner. */

import { spawn } from "node:child_process"
import { realpathSync } from "node:fs"
import { mkdtemp, readFile, rm, writeFile } from "node:fs/promises"
import { dirname, isAbsolute, join, normalize, relative, resolve } from "node:path"
import { tmpdir } from "node:os"

type Scope = "user" | "system"
type Selector = { path?: string; relative?: string; env?: string; default?: Selector }
type ConfigBinding = { output: Selector; inputs: Selector[] }
type Context = { scope: Scope; root: Selector; subpath?: string; configs: Record<string, ConfigBinding> }
type ConfigInput = {
  file?: string
  glob?: string
  directory?: string
  pattern?: string
  [key: string]: unknown
}
type ConfigRecord = { output: string; inputs: ConfigInput[]; [key: string]: unknown }
type ConfigSpec = { configs: Record<string, ConfigRecord>; contexts?: Record<string, Context>; [key: string]: unknown }

type Options = {
  context: string
  specPath: string
  runner: string
  runnerArgs: string[]
}

const scriptPath = realpathSync(process.argv[1])
const deploymentDir = resolve(dirname(scriptPath), "..")

function fail(message: string): never {
  throw new Error(message)
}

function parseArgs(argv: string[]): Options {
  let context = ""
  let specPath = join(deploymentDir, "etc", "config.spec.json")
  let runner = join(deploymentDir, "bin", "config.sh")
  const runnerArgs: string[] = []
  for (let index = 0; index < argv.length; index++) {
    const argument = argv[index]
    if (argument === "--context") {
      context = argv[++index] ?? fail("--context requires a name")
    } else if (argument === "--spec") {
      specPath = resolve(argv[++index] ?? fail("--spec requires a path"))
    } else if (argument === "--runner") {
      runner = resolve(argv[++index] ?? fail("--runner requires a path"))
    } else {
      runnerArgs.push(argument)
    }
  }
  if (!context) fail("usage: config-context.ts --context NAME [--spec PATH] [--runner PATH] [config.sh arguments]")
  return { context, specPath, runner, runnerArgs }
}

function object(value: unknown, label: string): Record<string, unknown> {
  if (!value || typeof value !== "object" || Array.isArray(value)) fail(`${label} must be an object`)
  return value as Record<string, unknown>
}

function knownRoot(name: string): string | undefined {
  const home = process.env.HOME
  if (name === "HOME") return home
  if (name === "XDG_CONFIG_HOME") return process.env.XDG_CONFIG_HOME || (home ? join(home, ".config") : undefined)
  if (name === "XDG_STATE_HOME") return process.env.XDG_STATE_HOME || (home ? join(home, ".local", "state") : undefined)
  if (name === "XDG_CACHE_HOME") return process.env.XDG_CACHE_HOME || (home ? join(home, ".cache") : undefined)
  if (name === "XDG_DATA_HOME") return process.env.XDG_DATA_HOME || (home ? join(home, ".local", "share") : undefined)
  return undefined
}

function expandPath(value: string, base: string | undefined, label: string): string {
  let expanded = value
  if (value === "~" || value.startsWith("~/")) {
    const home = knownRoot("HOME") ?? fail(`${label}: HOME is required to expand ${value}`)
    if (value.slice(1).includes("$") || value.slice(1).includes("~")) fail(`${label}: unsupported runtime-root expression: ${value}`)
    expanded = home + value.slice(1)
  } else if (value.startsWith("${")) {
    const match = /^\$\{(HOME|XDG_CONFIG_HOME|XDG_STATE_HOME|XDG_CACHE_HOME|XDG_DATA_HOME)\}(?:\/|$)/.exec(value)
    if (!match) fail(`${label}: unsupported runtime-root expression: ${value}`)
    const root = knownRoot(match[1]) ?? fail(`${label}: ${match[1]} or HOME is required to expand ${value}`)
    const suffix = value.slice(match[0].length - (match[0].endsWith("/") ? 1 : 0))
    if (suffix.includes("$") || suffix.includes("~")) fail(`${label}: unsupported runtime-root expression: ${value}`)
    expanded = root + suffix
  } else if (value.includes("$") || value.includes("~")) {
    fail(`${label}: unsupported runtime-root expression: ${value}`)
  }
  if (!isAbsolute(expanded)) {
    if (!base) fail(`${label}: resolved root must be absolute: ${expanded}`)
    expanded = resolve(base, expanded)
  }
  return normalize(expanded)
}

function resolveSelector(raw: unknown, base: string | undefined, label: string): string {
  const selector = object(raw, label) as Selector
  const fields = [selector.path !== undefined, selector.relative !== undefined, selector.env !== undefined].filter(Boolean).length
  if (fields !== 1) fail(`${label} must contain exactly one of path, relative, or env`)
  if (selector.path !== undefined) {
    if (typeof selector.path !== "string" || !selector.path) fail(`${label}.path must be a non-empty string`)
    return expandPath(selector.path, undefined, `${label}.path`)
  }
  if (selector.relative !== undefined) {
    if (typeof selector.relative !== "string" || !selector.relative || !base) fail(`${label}.relative requires a context root`)
    const resolved = resolve(base, selector.relative)
    const fromBase = relative(base, resolved)
    if (fromBase === ".." || fromBase.startsWith(`..${process.platform === "win32" ? "\\" : "/"}`) || isAbsolute(fromBase)) fail(`${label}.relative escapes the context root`)
    return normalize(resolved)
  }
  if (typeof selector.env !== "string" || !selector.env) fail(`${label}.env must name an environment variable`)
  const environmentValue = process.env[selector.env]
  if (environmentValue) return expandPath(environmentValue, base, `${label}.env(${selector.env})`)
  if (selector.default !== undefined) return resolveSelector(selector.default, base, `${label}.default`)
  fail(`${label}: environment variable ${selector.env} is required`)
}

function bindSpec(spec: ConfigSpec, contextName: string): ConfigSpec {
  const rawContexts = object(spec.contexts, "config spec contexts")
  const context = object(rawContexts[contextName], `unknown config context ${contextName}`) as Context
  if (context.scope !== "user" && context.scope !== "system") fail(`context ${contextName}: invalid scope`)
  const root = resolveSelector(context.root, undefined, `context ${contextName}.root`)
  const base = context.subpath ? resolve(root, context.subpath) : root
  const contextConfigs = object(context.configs, `context ${contextName}.configs`) as Record<string, ConfigBinding>
  const resolvedConfigs: Record<string, ConfigRecord> = {}
  const outputs = new Map<string, string>()

  for (const [name, rawBinding] of Object.entries(contextConfigs)) {
    const source = object(spec.configs[name], `context ${contextName}: missing source config ${name}`) as ConfigRecord
    const binding = object(rawBinding, `context ${contextName}.configs.${name}`) as ConfigBinding
    if (!Array.isArray(source.inputs) || !Array.isArray(binding.inputs) || source.inputs.length !== binding.inputs.length) {
      fail(`context ${contextName}.configs.${name}: input bindings do not match the source recipe`)
    }
    const output = resolveSelector(binding.output, base, `context ${contextName}.configs.${name}.output`)
    const prior = outputs.get(output)
    if (prior) fail(`context ${contextName}: configs ${prior} and ${name} resolve to the same output ${output}`)
    outputs.set(output, name)
    const inputs = source.inputs.map((rawInput, index) => {
      const input = { ...object(rawInput, `config ${name}.inputs[${index}]`) } as ConfigInput
      const path = resolveSelector(binding.inputs[index], base, `context ${contextName}.configs.${name}.inputs[${index}]`)
      if (input.file !== undefined) input.file = path
      else {
        input.directory = path
        input.glob = join(path, String(input.pattern))
      }
      return input
    })
    resolvedConfigs[name] = { ...source, output, inputs }
  }
  return { ...spec, configs: resolvedConfigs, contexts: undefined, remotes: {} }
}

async function run(options: Options): Promise<number> {
  const spec = JSON.parse(await readFile(options.specPath, "utf8")) as ConfigSpec
  object(spec.configs, "config spec configs")
  const resolvedSpec = bindSpec(spec, options.context)
  const temporary = await mkdtemp(join(tmpdir(), "compfuzor-config-context-"))
  const resolvedPath = join(temporary, "config.spec.json")
  try {
    await writeFile(resolvedPath, JSON.stringify(resolvedSpec), { mode: 0o600 })
    const runnerDeploymentDir = resolve(dirname(options.runner), "..")
    return await new Promise<number>((complete, reject) => {
      const child = spawn(options.runner, options.runnerArgs, {
        cwd: runnerDeploymentDir,
        env: { ...process.env, DIR: runnerDeploymentDir, CONFIG_SPEC: resolvedPath },
        stdio: "inherit",
      })
      child.once("error", reject)
      child.once("exit", (code, signal) => {
        if (signal) reject(new Error(`config runner terminated by ${signal}`))
        else complete(code ?? 1)
      })
    })
  } finally {
    await rm(temporary, { recursive: true, force: true })
  }
}

run(parseArgs(process.argv.slice(2))).then(
  (code) => { process.exitCode = code },
  (error: unknown) => {
    console.error(error instanceof Error ? error.stack : String(error))
    process.exitCode = 2
  },
)
