/** Import-safe consumer-context selection and path binding for CONFIGS specs. */

import { isAbsolute, join, normalize, relative, resolve } from "node:path"

export type ConfigScope = "user" | "system"

export type PathSelector = {
  path?: string
  relative?: string
  env?: string
  default?: PathSelector
}

export type ConfigInput = {
  file?: string
  glob?: string
  directory?: string
  pattern?: string
  [key: string]: unknown
}

export type ConfigRecord = {
  output: string
  inputs: ConfigInput[]
  apply?: boolean
  [key: string]: unknown
}

export type ConfigBinding = {
  output: PathSelector
  inputs: PathSelector[]
}

export type ConfigContext = {
  scope: ConfigScope
  root: PathSelector
  subpath?: string
  configs: Record<string, ConfigBinding>
  install?: "assemble" | "copy" | "link"
  dropins?: "copy" | "link"
}

export type ConfigSpec = {
  configs: Record<string, ConfigRecord>
  contexts?: Record<string, ConfigContext>
  [key: string]: unknown
}

export type ContextSelection = {
  context: ConfigContext
  names: string[]
  listOnly: boolean
}

function fail(message: string): never {
  throw new Error(message)
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

export function resolvePathSelector(raw: unknown, base: string | undefined, label: string): string {
  const selector = object(raw, label) as PathSelector
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
  if (selector.default !== undefined) return resolvePathSelector(selector.default, base, `${label}.default`)
  fail(`${label}: environment variable ${selector.env} is required`)
}

function requestedName(runnerArgs: string[]): { name?: string; listOnly: boolean } {
  let name: string | undefined
  let listOnly = false
  for (let index = 0; index < runnerArgs.length; index++) {
    const argument = runnerArgs[index]
    if (argument === "--list") listOnly = true
    else if (argument === "--target") name = runnerArgs[++index]
    else if (!argument.startsWith("-") && name === undefined) name = argument
  }
  return { name, listOnly }
}

export function getConfigContext(spec: ConfigSpec, contextName: string): ConfigContext {
  const contexts = object(spec.contexts, "config spec contexts")
  const context = object(contexts[contextName], `unknown config context ${contextName}`) as ConfigContext
  if (context.scope !== "user" && context.scope !== "system") fail(`context ${contextName}: invalid scope`)
  object(context.configs, `context ${contextName}.configs`)
  return context
}

export function contextConfigNames(spec: ConfigSpec, contextName: string, applyOnly = false): string[] {
  const context = getConfigContext(spec, contextName)
  const names = Object.keys(context.configs)
  if (!applyOnly) return names
  return names.filter((name) => {
    const config = object(spec.configs[name], `context ${contextName}: missing source config ${name}`) as ConfigRecord
    return config.apply !== false
  })
}

export function selectContext(spec: ConfigSpec, contextName: string, runnerArgs: string[]): ContextSelection {
  const context = getConfigContext(spec, contextName)
  const bindings = object(context.configs, `context ${contextName}.configs`)
  const request = requestedName(runnerArgs)
  const available = Object.keys(bindings)
  if (request.listOnly) return { context, names: available, listOnly: true }
  if (request.name !== undefined) {
    if (!(request.name in bindings)) fail(`unknown config in context ${contextName}: ${request.name}`)
    return { context, names: [request.name], listOnly: false }
  }
  return { context, names: contextConfigNames(spec, contextName, true), listOnly: false }
}

export function bindContextConfigs(spec: ConfigSpec, contextName: string, names: string[]): ConfigSpec {
  const context = getConfigContext(spec, contextName)
  for (const name of names) {
    if (!(name in context.configs)) fail(`unknown config in context ${contextName}: ${name}`)
  }
  const root = resolvePathSelector(context.root, undefined, `context ${contextName}.root`)
  const base = context.subpath ? resolve(root, context.subpath) : root
  const contextConfigs = object(context.configs, `context ${contextName}.configs`) as Record<string, ConfigBinding>
  const resolvedConfigs: Record<string, ConfigRecord> = {}
  const outputs = new Map<string, string>()

  for (const name of names) {
    const source = object(spec.configs[name], `context ${contextName}: missing source config ${name}`) as ConfigRecord
    const binding = object(contextConfigs[name], `context ${contextName}.configs.${name}`) as ConfigBinding
    if (!Array.isArray(source.inputs) || !Array.isArray(binding.inputs) || source.inputs.length !== binding.inputs.length) {
      fail(`context ${contextName}.configs.${name}: input bindings do not match the source recipe`)
    }
    const output = resolvePathSelector(binding.output, base, `context ${contextName}.configs.${name}.output`)
    const prior = outputs.get(output)
    if (prior) fail(`context ${contextName}: configs ${prior} and ${name} resolve to the same output ${output}`)
    outputs.set(output, name)
    const inputs = source.inputs.map((rawInput, index) => {
      const input = { ...object(rawInput, `config ${name}.inputs[${index}]`) } as ConfigInput
      const path = resolvePathSelector(binding.inputs[index], base, `context ${contextName}.configs.${name}.inputs[${index}]`)
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

export function bindContextSpec(spec: ConfigSpec, contextName: string, runnerArgs: string[]): ConfigSpec {
  const selection = selectContext(spec, contextName, runnerArgs)
  if (selection.listOnly) {
    return {
      ...spec,
      configs: Object.fromEntries(selection.names.map((name) => [name, spec.configs[name]])),
      contexts: undefined,
      remotes: {},
    }
  }
  return bindContextConfigs(spec, contextName, selection.names)
}
