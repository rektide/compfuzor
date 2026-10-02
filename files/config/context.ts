/** Import-safe consumer-context selection and path binding for CONFIGS specs. */

import { isAbsolute, join, normalize, relative, resolve } from "node:path"

export type ConfigScope = "user" | "system"

export type PathSelector = {
  path?: string
  relative?: string
  env?: string
  default?: PathSelector
  ignore?: string[]
}

export type ConfigInput = {
  file?: string
  glob?: string
  directory?: string
  pattern?: string
  [key: string]: unknown
}

export type ConfigRecord = {
  /** Sole output entry; keybinding adapters bind an absolute live path before invoking CONFIG. */
  output: string
  /** Ordered selected inputs; naming a pending output here does not establish a candidate DAG. */
  inputs: ConfigInput[]
  apply?: boolean
  /**
   * Retains compiled/runtime recipe settings. The keybinding seam uses `leaf`
   * (explicit deployed shared processor path) and `link` (absolute requested
   * symlink target) without changing this open record contract. A link recipe
   * still produces captured candidate bytes for validation; the runner stages
   * its directory-entry representation only at the existing commit boundary.
   */
  [key: string]: unknown
}

export type ConfigBinding = {
  output: PathSelector
  inputs: PathSelector[]
}

export type ConfigContext = {
  scope: ConfigScope
  canonical?: boolean
  root: PathSelector
  subpath?: string
  configs: Record<string, ConfigBinding>
  install?: "assemble" | "copy" | "link"
  dropins?: "copy" | "link"
  compose?: boolean
}

export type ConfigSpec = {
  version: 2
  defaultContext: string
  configs: Record<string, ConfigRecord>
  contexts?: Record<string, ConfigContext>
  /**
   * Retains spec-level extensions such as `transaction_validate`. That trusted
   * command receives the complete versioned candidate map after production and
   * immediate per-recipe validation, before check/stdout/publication. It may write
   * private validation layouts, not publish live outputs or modify candidates.
   * @see /files/config/keybindings/closure.ts
   */
  [key: string]: unknown
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
  if (environmentValue && !selector.ignore?.includes(environmentValue)) {
    return expandPath(environmentValue, base, `${label}.env(${selector.env})`)
  }
  if (selector.default !== undefined) return resolvePathSelector(selector.default, base, `${label}.default`)
  fail(`${label}: environment variable ${selector.env} is required`)
}

export function getConfigContext(spec: ConfigSpec, contextName: string): ConfigContext {
  if (spec.version !== 2) fail(`unsupported config spec version: ${String(spec.version)}; rerender the deployment (expected version 2)`)
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

export function selectRecipeNames(spec: ConfigSpec, contextName: string, requested: string[], applyOnly = true): string[] {
  const available = contextConfigNames(spec, contextName)
  if (requested.length === 0) return contextConfigNames(spec, contextName, applyOnly)
  const seen = new Set<string>()
  for (const name of requested) {
    if (!available.includes(name)) fail(`unknown config in context ${contextName}: ${name}`)
    if (seen.has(name)) fail(`config selected more than once in context ${contextName}: ${name}`)
    seen.add(name)
  }
  return requested
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
