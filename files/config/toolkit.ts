#!/usr/bin/env -S node --disable-warning=MODULE_TYPELESS_PACKAGE_JSON
/** Donor delivery, local input operations, and status for bound CONFIGS contexts. */

import { mkdir, readFile, readdir, realpath, rename, rm, stat } from "node:fs/promises"
import { basename, dirname, isAbsolute, join, normalize, resolve } from "node:path"
import { fileURLToPath } from "node:url"

import { runConfigContext, type ConfigContextCliOptions } from "../config-context.ts"
import {
  bindContextConfigs,
  contextConfigNames,
  getConfigContext,
  type ConfigContext,
  type ConfigInput,
  type ConfigRecord,
  type ConfigSpec,
} from "./context.ts"
import {
  inspectDeliveryEntry,
  linkMatches,
  replaceWithCopy,
  replaceWithLink,
  type DeliveryEntry,
} from "../links/delivery.ts"

export type Strategy = "copy" | "link"
type Format = "human" | "jsonl" | "array"
type Severity = "ok" | "drift" | "error"
type ToolkitAction = "install" | "dropins" | "whole" | "status" | "inputs"

export type ToolkitOptions = {
  context: string
  specPath: string
  runner: string
  action: ToolkitAction
  strategy?: Strategy
  seed: boolean
  format: Format
  args: string[]
}

type InputRelation = {
  id: string
  config: string
  inputIndex: number
  inputName: string
  source: string
  destinationDirectory?: string
  destination: string
  logicalName: string
  pattern?: string
  suffix?: string
  donorState: "enabled" | "disabled"
  donorConflict?: string
}

type InputDirectory = {
  config: string
  inputIndex: number
  inputName: string
  donorDirectory: string
  destinationDirectory: string
  pattern: string
  suffix?: string
  donorNames: Set<string>
}

export type StatusRow = {
  kind: "input" | "output"
  status: string
  severity: Severity
  config: string
  name: string
  state?: string
  representation?: string
  source?: string
  destination?: string
  note?: string
}

type InputCatalog = {
  relations: InputRelation[]
  directories: InputDirectory[]
  rows: StatusRow[]
}

function fail(message: string): never {
  throw new Error(message)
}

function object(value: unknown, label: string): Record<string, unknown> {
  if (!value || typeof value !== "object" || Array.isArray(value)) fail(`${label} must be an object`)
  return value as Record<string, unknown>
}

function truthy(value: string | undefined): boolean {
  return ["1", "true", "y", "yes"].includes(value?.trim().toLowerCase() ?? "")
}

function globMatches(pattern: string, value: string): boolean {
  let source = "^"
  for (const character of pattern) {
    if (character === "*") source += ".*"
    else if (character === "?") source += "."
    else source += character.replace(/[\\^$.*+?()[\]{}|]/g, "\\$&")
  }
  return new RegExp(`${source}$`).test(value)
}

function inputIdentity(input: ConfigInput, index: number): string {
  return typeof input.name === "string" && input.name ? input.name : String(index)
}

function selectedNames(spec: ConfigSpec, contextName: string, name?: string, applyOnly = true): string[] {
  const available = contextConfigNames(spec, contextName, applyOnly && name === undefined)
  if (name === undefined) return available
  if (!contextConfigNames(spec, contextName).includes(name)) fail(`unknown config in context ${contextName}: ${name}`)
  return [name]
}

function parseStrategy(value: string | undefined, label: string): Strategy | undefined {
  if (value === undefined) return undefined
  if (value !== "copy" && value !== "link") fail(`${label} must be copy or link`)
  return value
}

export function parseConfigToolkitArgs(argv: string[], deploymentDir: string): ToolkitOptions {
  let context = ""
  let specPath = join(deploymentDir, "etc", "config.spec.json")
  let runner = join(deploymentDir, "bin", "config.sh")
  let action: ToolkitAction | undefined
  let strategy: Strategy | undefined
  let seed = false
  let format: Format = "human"
  const args: string[] = []
  for (let index = 0; index < argv.length; index++) {
    const argument = argv[index]
    if (argument === "--context") context = argv[++index] ?? fail("--context requires a name")
    else if (argument === "--spec") specPath = resolve(argv[++index] ?? fail("--spec requires a path"))
    else if (argument === "--runner") runner = resolve(argv[++index] ?? fail("--runner requires a path"))
    else if (argument === "--strategy") strategy = parseStrategy(argv[++index], "--strategy")
    else if (argument === "--seed") seed = true
    else if (argument === "--json") format = "jsonl"
    else if (argument === "--json-array") format = "array"
    else if (!action && ["install", "dropins", "whole", "status", "inputs"].includes(argument)) action = argument as ToolkitAction
    else if (argument.startsWith("-")) fail(`unknown option: ${argument}`)
    else args.push(argument)
  }
  if (!context || !action) fail("usage: config/toolkit.ts --context NAME <install|dropins|whole|status|inputs> [options]")
  return { context, specPath, runner, action, strategy, seed, format, args }
}

async function pathKind(path: string): Promise<"missing" | "file" | "symlink" | "directory" | "special"> {
  return (await inspectDeliveryEntry(path)).kind
}

async function usableSource(path: string): Promise<{ usable: boolean; note?: string }> {
  const entry = await inspectDeliveryEntry(path)
  if (entry.kind === "missing") return { usable: false, note: "donor entry missing" }
  if (entry.kind === "directory" || entry.kind === "special") return { usable: false, note: `donor entry is ${entry.kind}` }
  try {
    const followed = await stat(path)
    if (!followed.isFile()) return { usable: false, note: "donor entry does not resolve to a regular file" }
  } catch (error) {
    if ((error as NodeJS.ErrnoException).code === "ENOENT") return { usable: false, note: "donor entry is dangling" }
    return { usable: false, note: error instanceof Error ? error.message : String(error) }
  }
  return { usable: true }
}

async function sameContents(first: string, second: string): Promise<boolean> {
  try {
    const [one, two] = await Promise.all([readFile(first), readFile(second)])
    return one.equals(two)
  } catch {
    return false
  }
}

async function readDirectory(path: string): Promise<Awaited<ReturnType<typeof readdir>> | undefined> {
  try {
    return await readdir(path, { withFileTypes: true })
  } catch (error) {
    if ((error as NodeJS.ErrnoException).code === "ENOENT") return undefined
    throw error
  }
}

async function inputCatalog(spec: ConfigSpec, contextName: string, names: string[]): Promise<InputCatalog> {
  const resolved = bindContextConfigs(spec, contextName, names)
  const relations: InputRelation[] = []
  const directories: InputDirectory[] = []
  const rows: StatusRow[] = []

  for (const configName of names) {
    const donorConfig = object(spec.configs[configName], `config ${configName}`) as ConfigRecord
    const localConfig = object(resolved.configs[configName], `resolved config ${configName}`) as ConfigRecord
    for (let index = 0; index < donorConfig.inputs.length; index++) {
      const donor = donorConfig.inputs[index]
      const local = localConfig.inputs[index]
      const name = inputIdentity(donor, index)
      if (typeof donor.file === "string" && typeof local.file === "string") {
        relations.push({
          id: `${configName}/${name}`,
          config: configName,
          inputIndex: index,
          inputName: name,
          source: donor.file,
          destination: local.file,
          logicalName: basename(local.file),
          donorState: "enabled",
        })
        continue
      }
      if (typeof donor.directory !== "string" || typeof donor.pattern !== "string" || typeof local.directory !== "string") {
        fail(`config ${configName} input ${index} has an invalid compiled shape`)
      }
      const suffix = typeof donor.disabled_suffix === "string" ? donor.disabled_suffix : undefined
      const directory: InputDirectory = {
        config: configName,
        inputIndex: index,
        inputName: name,
        donorDirectory: donor.directory,
        destinationDirectory: local.directory,
        pattern: donor.pattern,
        suffix,
        donorNames: new Set<string>(),
      }
      directories.push(directory)
      const entries = await readDirectory(donor.directory)
      if (entries === undefined) {
        rows.push({
          kind: "input", status: "donor-missing", severity: "error", config: configName, name,
          source: donor.directory, destination: local.directory, note: "donor input directory is missing",
        })
        continue
      }
      const byLogical = new Map<string, InputRelation>()
      for (const entry of entries.sort((a, b) => a.name.localeCompare(b.name))) {
        const disabled = suffix !== undefined && entry.name.endsWith(suffix)
        const logicalName = disabled ? entry.name.slice(0, -suffix.length) : entry.name
        if (!globMatches(donor.pattern, logicalName)) continue
        const source = join(donor.directory, entry.name)
        const relation: InputRelation = {
          id: `${configName}/${name}/${logicalName}`,
          config: configName,
          inputIndex: index,
          inputName: name,
          source,
          destinationDirectory: local.directory,
          destination: join(local.directory, entry.name),
          logicalName,
          pattern: donor.pattern,
          suffix,
          donorState: disabled ? "disabled" : "enabled",
        }
        const previous = byLogical.get(logicalName)
        if (previous) {
          previous.donorConflict = source
          continue
        }
        byLogical.set(logicalName, relation)
        directory.donorNames.add(logicalName)
      }
      relations.push(...byLogical.values())
    }
  }
  return { relations, directories, rows }
}

async function localSelection(relation: InputRelation): Promise<{
  active: string
  disabled?: string
  activeEntry: DeliveryEntry
  disabledEntry?: DeliveryEntry
  selectedPath?: string
  selectedState?: "enabled" | "disabled"
  selectedEntry?: DeliveryEntry
  conflict: boolean
}> {
  if (!relation.destinationDirectory || !relation.suffix) {
    const entry = await inspectDeliveryEntry(relation.destination)
    return {
      active: relation.destination,
      activeEntry: entry,
      selectedPath: entry.kind === "missing" ? undefined : relation.destination,
      selectedState: entry.kind === "missing" ? undefined : "enabled",
      selectedEntry: entry.kind === "missing" ? undefined : entry,
      conflict: false,
    }
  }
  const active = join(relation.destinationDirectory, relation.logicalName)
  const disabled = `${active}${relation.suffix}`
  const [activeEntry, disabledEntry] = await Promise.all([inspectDeliveryEntry(active), inspectDeliveryEntry(disabled)])
  const hasActive = activeEntry.kind !== "missing"
  const hasDisabled = disabledEntry.kind !== "missing"
  return {
    active, disabled, activeEntry, disabledEntry,
    selectedPath: hasActive ? active : hasDisabled ? disabled : undefined,
    selectedState: hasActive ? "enabled" : hasDisabled ? "disabled" : undefined,
    selectedEntry: hasActive ? activeEntry : hasDisabled ? disabledEntry : undefined,
    conflict: hasActive && hasDisabled,
  }
}

async function deliver(source: string, destination: string, strategy: Strategy): Promise<void> {
  if (strategy === "link") await replaceWithLink(source, destination)
  else await replaceWithCopy(source, destination)
}

async function applyRelation(relation: InputRelation, strategy: Strategy, seed: boolean): Promise<string> {
  if (relation.donorConflict) fail(`${relation.id}: donor has both enabled and disabled entries`)
  const sourceEntry = await inspectDeliveryEntry(relation.source)
  if (sourceEntry.kind === "missing" || sourceEntry.kind === "directory" || sourceEntry.kind === "special") {
    fail(`${relation.id}: donor source is ${sourceEntry.kind}: ${relation.source}`)
  }
  const local = await localSelection(relation)
  if (local.conflict) fail(`${relation.id}: both enabled and disabled local entries exist`)
  if (seed && local.selectedPath) return `preserved\t${relation.id}\t${local.selectedState}\t${local.selectedPath}`
  const state = local.selectedState ?? relation.donorState
  const destination = state === "disabled" && relation.suffix && relation.destinationDirectory
    ? join(relation.destinationDirectory, `${relation.logicalName}${relation.suffix}`)
    : relation.destinationDirectory ? join(relation.destinationDirectory, relation.logicalName) : relation.destination
  await deliver(relation.source, destination, strategy)
  return `${seed ? "seeded" : "refreshed"}\t${relation.id}\t${state}\t${strategy}\t${destination}`
}

async function applyDropins(spec: ConfigSpec, options: ToolkitOptions, strategy: Strategy, seed: boolean, config?: string): Promise<number> {
  const names = selectedNames(spec, options.context, config)
  const catalog = await inputCatalog(spec, options.context, names)
  let failed = catalog.rows.some((row) => row.severity === "error")
  for (const row of catalog.rows) console.error(`${row.status}: ${row.config}/${row.name}: ${row.note}`)
  for (const directory of catalog.directories) {
    try {
      await mkdir(directory.destinationDirectory, { recursive: true })
    } catch (error) {
      failed = true
      console.error(`error: cannot create input directory ${directory.destinationDirectory}: ${error instanceof Error ? error.message : String(error)}`)
    }
  }
  for (const relation of catalog.relations) {
    try {
      console.log(await applyRelation(relation, strategy, seed))
    } catch (error) {
      failed = true
      console.error(`error: ${error instanceof Error ? error.message : String(error)}`)
    }
  }
  return failed ? 2 : 0
}

async function applyWhole(spec: ConfigSpec, options: ToolkitOptions, strategy: Strategy, config?: string): Promise<number> {
  const names = selectedNames(spec, options.context, config)
  const resolved = bindContextConfigs(spec, options.context, names)
  let failed = false
  for (const name of names) {
    const source = spec.configs[name].output
    const destination = resolved.configs[name].output
    try {
      await deliver(source, destination, strategy)
      console.log(`${strategy}\t${name}\t${source}\t${destination}`)
    } catch (error) {
      failed = true
      console.error(`error: ${name}: ${error instanceof Error ? error.message : String(error)}`)
    }
  }
  return failed ? 2 : 0
}

function rowSeverity(rows: StatusRow[]): number {
  if (rows.some((row) => row.severity === "error")) return 2
  return rows.some((row) => row.severity === "drift") ? 1 : 0
}

function printRows(rows: StatusRow[], format: Format): void {
  if (format === "array") {
    console.log(JSON.stringify(rows, null, 2))
    return
  }
  if (format === "jsonl") {
    for (const row of rows) console.log(JSON.stringify(row))
    return
  }
  if (rows.length === 0) return
  console.log("kind\tstatus\tconfig\tname\tstate\trepresentation\tsource\tdestination\tnote")
  for (const row of rows) {
    console.log([
      row.kind, row.status, row.config, row.name, row.state ?? "-", row.representation ?? "-",
      row.source ?? "-", row.destination ?? "-", row.note ?? "-",
    ].join("\t"))
  }
}

async function relationStatus(relation: InputRelation): Promise<StatusRow> {
  if (relation.donorConflict) {
    return {
      kind: "input", status: "donor-conflict", severity: "drift", config: relation.config, name: relation.logicalName,
      source: relation.source, destination: relation.destination, note: `also present as ${relation.donorConflict}`,
    }
  }
  const source = await usableSource(relation.source)
  const local = await localSelection(relation)
  if (local.conflict) {
    return {
      kind: "input", status: "local-conflict", severity: "drift", config: relation.config, name: relation.logicalName,
      source: relation.source, destination: local.active, note: `both ${local.active} and ${local.disabled} exist`,
    }
  }
  if (!local.selectedPath || !local.selectedEntry) {
    return {
      kind: "input", status: source.usable ? "missing" : "donor-missing", severity: source.usable ? "drift" : "error",
      config: relation.config, name: relation.logicalName, state: relation.donorState,
      source: relation.source, destination: relation.destination, note: source.note,
    }
  }
  const common = {
    kind: "input" as const, config: relation.config, name: relation.logicalName, state: local.selectedState,
    source: relation.source, destination: local.selectedPath,
  }
  if (!source.usable) {
    return { ...common, status: "donor-missing", severity: "error", representation: local.selectedEntry.kind, note: source.note }
  }
  if (linkMatches(local.selectedEntry, relation.source)) {
    return { ...common, status: "ok", severity: "ok", representation: "link" }
  }
  if (local.selectedEntry.kind === "file" && await sameContents(relation.source, local.selectedPath)) {
    return { ...common, status: "ok", severity: "ok", representation: "copy" }
  }
  if (local.selectedEntry.kind === "directory" || local.selectedEntry.kind === "special") {
    return { ...common, status: "unsupported", severity: "drift", representation: local.selectedEntry.kind }
  }
  return {
    ...common, status: "modified", severity: "drift", representation: local.selectedEntry.kind === "file" ? "copy" : "link",
    note: local.selectedEntry.kind === "symlink" ? `points to ${local.selectedEntry.target}` : "bytes differ from donor",
  }
}

async function extraInputRows(directory: InputDirectory): Promise<StatusRow[]> {
  const entries = await readDirectory(directory.destinationDirectory)
  if (entries === undefined) return []
  const grouped = new Map<string, { active?: string; disabled?: string }>()
  for (const entry of entries) {
    const disabled = directory.suffix !== undefined && entry.name.endsWith(directory.suffix)
    const logical = disabled ? entry.name.slice(0, -directory.suffix.length) : entry.name
    if (!globMatches(directory.pattern, logical) || directory.donorNames.has(logical)) continue
    const group = grouped.get(logical) ?? {}
    group[disabled ? "disabled" : "active"] = join(directory.destinationDirectory, entry.name)
    grouped.set(logical, group)
  }
  const rows: StatusRow[] = []
  for (const [logical, group] of [...grouped].sort(([a], [b]) => a.localeCompare(b))) {
    if (group.active && group.disabled) {
      rows.push({
        kind: "input", status: "local-conflict", severity: "drift", config: directory.config, name: logical,
        source: directory.donorDirectory, destination: group.active, note: `both active and disabled local entries exist`,
      })
      continue
    }
    const path = group.active ?? group.disabled!
    const entry = await inspectDeliveryEntry(path)
    let status = "local"
    let severity: Severity = entry.kind === "directory" || entry.kind === "special" ? "drift" : "ok"
    let note = "not present in current donor catalog"
    if (entry.kind === "symlink") {
      const donorRelative = normalize(entry.targetPath).startsWith(`${normalize(directory.donorDirectory)}/`)
      if (donorRelative && await pathKind(entry.targetPath) === "missing") {
        status = "donor-missing"
        severity = "error"
        note = `dangling link into donor directory: ${entry.target}`
      }
    }
    rows.push({
      kind: "input", status, severity, config: directory.config, name: logical,
      state: group.disabled ? "disabled" : "enabled", representation: entry.kind,
      destination: path, note,
    })
  }
  return rows
}

async function inputStatusRows(spec: ConfigSpec, contextName: string, names: string[]): Promise<StatusRow[]> {
  const catalog = await inputCatalog(spec, contextName, names)
  const rows = [...catalog.rows]
  for (const relation of catalog.relations) rows.push(await relationStatus(relation))
  for (const directory of catalog.directories) {
    if (directory.donorNames.size === 0 && await pathKind(directory.destinationDirectory) === "missing") {
      rows.push({
        kind: "input", status: "missing", severity: "drift", config: directory.config, name: directory.inputName,
        source: directory.donorDirectory, destination: directory.destinationDirectory, note: "empty consumer input directory is missing",
      })
    }
    rows.push(...await extraInputRows(directory))
  }
  return rows
}

async function assemblyMatches(options: ToolkitOptions, config: string): Promise<boolean> {
  const runOptions: ConfigContextCliOptions = {
    context: options.context,
    specPath: options.specPath,
    runner: options.runner,
    runnerArgs: ["--check", "--quiet", config],
    stdio: "ignore",
  }
  return await runConfigContext(runOptions) === 0
}

async function outputStatusRows(spec: ConfigSpec, options: ToolkitOptions, names: string[]): Promise<StatusRow[]> {
  const resolved = bindContextConfigs(spec, options.context, names)
  const rows: StatusRow[] = []
  for (const name of names) {
    const source = spec.configs[name].output
    const destination = resolved.configs[name].output
    const [sourceState, entry] = await Promise.all([usableSource(source), inspectDeliveryEntry(destination)])
    const common = { kind: "output" as const, config: name, name, source, destination }
    if (entry.kind === "missing") {
      rows.push({ ...common, status: sourceState.usable ? "missing" : "donor-missing", severity: sourceState.usable ? "drift" : "error", note: sourceState.note })
    } else if (linkMatches(entry, source)) {
      rows.push({ ...common, status: sourceState.usable ? "ok" : "donor-missing", severity: sourceState.usable ? "ok" : "error", representation: "link", note: sourceState.note })
    } else if (entry.kind === "file" && sourceState.usable && await sameContents(source, destination)) {
      rows.push({ ...common, status: "ok", severity: "ok", representation: "copy" })
    } else if (entry.kind === "file" && await assemblyMatches(options, name)) {
      rows.push({ ...common, status: sourceState.usable ? "ok" : "donor-missing", severity: sourceState.usable ? "ok" : "error", representation: "assembly", note: sourceState.note })
    } else if (entry.kind === "directory" || entry.kind === "special") {
      rows.push({ ...common, status: "unsupported", severity: "drift", representation: entry.kind })
    } else {
      rows.push({ ...common, status: "modified", severity: "drift", representation: entry.kind === "file" ? "copy" : "link", note: entry.kind === "symlink" ? `points to ${entry.target}` : "differs from donor and local assembly" })
    }
  }
  return rows
}

async function showStatus(spec: ConfigSpec, options: ToolkitOptions, config?: string, inputsOnly = false): Promise<number> {
  const names = selectedNames(spec, options.context, config)
  const inputRows = await inputStatusRows(spec, options.context, names)
  const rows = inputsOnly ? inputRows : [...await outputStatusRows(spec, options, names), ...inputRows]
  printRows(rows, options.format)
  return rowSeverity(rows)
}

function findInput(spec: ConfigSpec, contextName: string, selector: string): { config: string; index: number; input: ConfigInput } {
  const slash = selector.indexOf("/")
  const configSelector = slash === -1 ? undefined : selector.slice(0, slash)
  const inputSelector = slash === -1 ? selector : selector.slice(slash + 1)
  const matches: { config: string; index: number; input: ConfigInput }[] = []
  for (const config of contextConfigNames(spec, contextName)) {
    if (configSelector && config !== configSelector) continue
    const inputs = spec.configs[config].inputs
    inputs.forEach((input, index) => {
      if (inputIdentity(input, index) === inputSelector) matches.push({ config, index, input })
    })
  }
  if (matches.length !== 1) fail(matches.length === 0 ? `unknown context input: ${selector}` : `ambiguous context input: ${selector}; use CONFIG/INPUT`)
  return matches[0]
}

async function rebuild(options: ToolkitOptions, config: string): Promise<number> {
  const code = await runConfigContext({
    context: options.context,
    specPath: options.specPath,
    runner: options.runner,
    runnerArgs: [config],
  })
  if (code === 0) return 0
  console.error(`input mutation remains; config rebuild failed for ${config} (exit ${code})`)
  return 4
}

async function localInputPaths(spec: ConfigSpec, contextName: string, found: ReturnType<typeof findInput>, name: string): Promise<{ active: string; disabled?: string }> {
  const resolved = bindContextConfigs(spec, contextName, [found.config])
  const input = resolved.configs[found.config].inputs[found.index]
  if (typeof input.directory !== "string") fail(`${found.config}/${inputIdentity(found.input, found.index)} is not a glob input`)
  const suffix = typeof found.input.disabled_suffix === "string" ? found.input.disabled_suffix : undefined
  return { active: join(input.directory, name), disabled: suffix ? join(input.directory, `${name}${suffix}`) : undefined }
}

function resolvedInput(spec: ConfigSpec, contextName: string, found: ReturnType<typeof findInput>): ConfigInput {
  return bindContextConfigs(spec, contextName, [found.config]).configs[found.config].inputs[found.index]
}

function validateInputName(input: ConfigInput, name: string): void {
  if (!name || basename(name) !== name || name === "." || name === "..") fail(`invalid input filename: ${name}`)
  if (typeof input.pattern !== "string" || !globMatches(input.pattern, name)) fail(`${name} does not match input pattern ${String(input.pattern)}`)
  if (typeof input.disabled_suffix === "string" && name.endsWith(input.disabled_suffix)) fail(`input filename must not include disabled suffix ${input.disabled_suffix}`)
}

async function inspectPair(paths: { active: string; disabled?: string }): Promise<{ active: DeliveryEntry; disabled?: DeliveryEntry; conflict: boolean }> {
  const [active, disabled] = await Promise.all([
    inspectDeliveryEntry(paths.active),
    paths.disabled ? inspectDeliveryEntry(paths.disabled) : Promise.resolve(undefined),
  ])
  return { active, disabled, conflict: active.kind !== "missing" && disabled !== undefined && disabled.kind !== "missing" }
}

function replaceableLocal(entry: DeliveryEntry, path: string): void {
  if (entry.kind === "directory" || entry.kind === "special") fail(`local input is not a regular file or symlink: ${path}`)
}

async function inputPut(spec: ConfigSpec, options: ToolkitOptions, args: string[]): Promise<number> {
  const [selector, sourceArgument, suppliedName] = args
  if (!selector || !sourceArgument || args.length > 3) fail("usage: config-inputs-CONTEXT.sh put INPUT SOURCE [NAME] [--strategy copy|link]")
  const found = findInput(spec, options.context, selector)
  const source = resolve(sourceArgument)
  if (typeof found.input.file === "string") {
    if (suppliedName !== undefined) fail(`${selector} is a direct file input and does not accept a destination name`)
    const local = resolvedInput(spec, options.context, found)
    if (typeof local.file !== "string") fail(`${selector} has an invalid resolved file binding`)
    await deliver(source, local.file, options.strategy ?? getConfigContext(spec, options.context).dropins ?? "link")
    console.log(`put\t${found.config}/${inputIdentity(found.input, found.index)}\t${local.file}`)
    return rebuild(options, found.config)
  }
  const name = suppliedName ?? basename(source)
  validateInputName(found.input, name)
  const paths = await localInputPaths(spec, options.context, found, name)
  const pair = await inspectPair(paths)
  if (pair.conflict) fail(`both enabled and disabled local entries exist for ${name}`)
  const destination = pair.active.kind !== "missing" ? paths.active : pair.disabled && pair.disabled.kind !== "missing" ? paths.disabled! : paths.active
  await deliver(source, destination, options.strategy ?? getConfigContext(spec, options.context).dropins ?? "link")
  console.log(`put\t${found.config}/${inputIdentity(found.input, found.index)}\t${destination}`)
  return rebuild(options, found.config)
}

async function inputMutation(spec: ConfigSpec, options: ToolkitOptions, action: "enable" | "disable" | "remove", args: string[]): Promise<number> {
  const [selector, name] = args
  if (!selector) fail(`usage: config-inputs-CONTEXT.sh ${action} INPUT [NAME]`)
  const found = findInput(spec, options.context, selector)
  if (typeof found.input.file === "string") {
    if (action !== "remove") fail(`${selector} is a direct file input and cannot be ${action}d`)
    if (args.length !== 1) fail(`usage: config-inputs-CONTEXT.sh remove DIRECT_INPUT`)
    const local = resolvedInput(spec, options.context, found)
    if (typeof local.file !== "string") fail(`${selector} has an invalid resolved file binding`)
    const entry = await inspectDeliveryEntry(local.file)
    if (entry.kind === "missing") return 0
    replaceableLocal(entry, local.file)
    await rm(local.file)
    console.log(`remove\t${found.config}/${inputIdentity(found.input, found.index)}\t${local.file}`)
    return rebuild(options, found.config)
  }
  if (!name || args.length !== 2) fail(`usage: config-inputs-CONTEXT.sh ${action} INPUT NAME`)
  validateInputName(found.input, name)
  const paths = await localInputPaths(spec, options.context, found, name)
  const pair = await inspectPair(paths)
  if (pair.conflict) fail(`both enabled and disabled local entries exist for ${name}`)
  if (action === "remove") {
    const path = pair.active.kind !== "missing" ? paths.active : pair.disabled && pair.disabled.kind !== "missing" ? paths.disabled! : undefined
    if (!path) return 0
    replaceableLocal(path === paths.active ? pair.active : pair.disabled!, path)
    await rm(path)
    console.log(`remove\t${found.config}/${inputIdentity(found.input, found.index)}\t${path}`)
    return rebuild(options, found.config)
  }
  if (!paths.disabled) fail(`${found.config}/${inputIdentity(found.input, found.index)} cannot be disabled`)
  const from = action === "disable" ? paths.active : paths.disabled
  const to = action === "disable" ? paths.disabled : paths.active
  const fromEntry = action === "disable" ? pair.active : pair.disabled!
  const toEntry = action === "disable" ? pair.disabled! : pair.active
  if (toEntry.kind !== "missing") return 0
  if (fromEntry.kind === "missing") fail(`local input does not exist: ${from}`)
  replaceableLocal(fromEntry, from)
  await rename(from, to)
  console.log(`${action}\t${found.config}/${inputIdentity(found.input, found.index)}\t${to}`)
  return rebuild(options, found.config)
}

async function listInputs(spec: ConfigSpec, options: ToolkitOptions, config?: string): Promise<number> {
  const names = selectedNames(spec, options.context, config, false)
  const resolved = bindContextConfigs(spec, options.context, names)
  for (const name of names) {
    spec.configs[name].inputs.forEach((input, index) => {
      const local = resolved.configs[name].inputs[index]
      const donor = typeof input.file === "string" ? input.file : input.directory
      const destination = typeof local.file === "string" ? local.file : local.directory
      console.log(`${name}/${inputIdentity(input, index)}\t${donor}\t${destination}`)
    })
  }
  return 0
}

async function inputAction(spec: ConfigSpec, options: ToolkitOptions): Promise<number> {
  const [action, ...args] = options.args
  if (action === "list") return listInputs(spec, options, args[0])
  if (action === "status") return showStatus(spec, options, args[0], true)
  if (action === "put") return inputPut(spec, options, args)
  if (action === "enable" || action === "disable" || action === "remove") return inputMutation(spec, options, action, args)
  fail("usage: config-inputs-CONTEXT.sh <list|status|put|enable|disable|remove> ...")
}

function defaultStrategy(context: ConfigContext, surface: "install" | "dropins"): string {
  if (surface === "install") return process.env.COMPFUZOR_CONFIG_INSTALL_STRATEGY || context.install || "assemble"
  return process.env.COMPFUZOR_CONFIG_DROPINS_STRATEGY || context.dropins || "link"
}

async function install(spec: ConfigSpec, options: ToolkitOptions, config?: string): Promise<number> {
  if (truthy(process.env.COMPFUZOR_CONFIG_CONTEXTS_BYPASS) || truthy(process.env.COMPFUZOR_CONFIG_BYPASS)) {
    console.error(`skipped install-config-${options.context}: config context bypass`)
    return 0
  }
  const context = getConfigContext(spec, options.context)
  const selected = defaultStrategy(context, "install")
  if (selected === "copy" || selected === "link") return applyWhole(spec, options, selected, config)
  if (selected !== "assemble") fail(`config install strategy must be assemble, copy, or link: ${selected}`)
  const dropins = parseStrategy(defaultStrategy(context, "dropins"), "config dropins strategy")!
  const seeded = await applyDropins(spec, options, dropins, true, config)
  if (seeded !== 0) return seeded
  return runConfigContext({
    context: options.context,
    specPath: options.specPath,
    runner: options.runner,
    runnerArgs: config ? [config] : [],
  })
}

export async function runConfigToolkit(options: ToolkitOptions): Promise<number> {
  const spec = JSON.parse(await readFile(options.specPath, "utf8")) as ConfigSpec
  object(spec.configs, "config spec configs")
  const config = options.args.length === 1 ? options.args[0] : undefined
  if (options.action !== "inputs" && options.args.length > 1) fail(`${options.action} accepts at most one config name`)
  if (options.action === "install") return install(spec, options, config)
  if (options.action === "dropins") {
    const strategy = options.strategy ?? parseStrategy(defaultStrategy(getConfigContext(spec, options.context), "dropins"), "config dropins strategy")!
    return applyDropins(spec, options, strategy, options.seed, config)
  }
  if (options.action === "whole") return applyWhole(spec, options, options.strategy ?? fail("whole requires --strategy copy or link"), config)
  if (options.action === "status") return showStatus(spec, options, config)
  return inputAction(spec, options)
}

export async function main(argv = process.argv.slice(2), modulePath = fileURLToPath(import.meta.url)): Promise<number> {
  const realModulePath = await realpath(modulePath)
  const deploymentDir = resolve(dirname(dirname(realModulePath)), "..")
  return runConfigToolkit(parseConfigToolkitArgs(argv, deploymentDir))
}

const argvPath = process.argv[1]
if (argvPath) {
  Promise.all([realpath(argvPath), realpath(fileURLToPath(import.meta.url))]).then(
    ([realArgvPath, realModulePath]) => {
      if (realArgvPath !== realModulePath) return
      return main(process.argv.slice(2), realModulePath).then(
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
