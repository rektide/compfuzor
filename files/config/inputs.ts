/** Consumer input inventory and mutation operations. */

import { rename, rm } from "node:fs/promises"
import { basename, join, matchesGlob, resolve } from "node:path"

import { runAssembly } from "./assembly.ts"
import {
  bindContextConfigs,
  contextConfigNames,
  getConfigContext,
  selectRecipeNames,
  type ConfigInput,
  type ConfigSpec,
} from "./context.ts"
import {
  inputStatusRows,
  type InputOperationOptions,
  type InputStrategy,
} from "./input-state.ts"
import { printStatusRows, statusCode } from "./report.ts"
import {
  inspectDeliveryEntry,
  pathsSharePhysicalDirectory,
  pathsSharePhysicalEntry,
  replaceWithCopy,
  replaceWithLink,
  type DeliveryEntry,
} from "../links/delivery.ts"

export { inputStatusRows, syncInputs } from "./input-state.ts"
export type { InputOperationOptions, InputStrategy } from "./input-state.ts"

function fail(message: string): never {
  throw new Error(message)
}

function filenameMatches(value: string, pattern: string): boolean {
  return matchesGlob(`x${value}`, `x${pattern}`)
}

function inputIdentity(input: ConfigInput, index: number): string {
  return typeof input.name === "string" && input.name ? input.name : String(index)
}

async function deliver(source: string, destination: string, strategy: InputStrategy): Promise<void> {
  if (strategy === "link") await replaceWithLink(source, destination)
  else await replaceWithCopy(source, destination)
}

type SelectedInput = {
  config: string
  index: number
  source: ConfigInput
  consumer: ConfigInput
}

function selectInput(spec: ConfigSpec, contextName: string, selector: string): SelectedInput {
  const slash = selector.indexOf("/")
  const configSelector = slash === -1 ? undefined : selector.slice(0, slash)
  const inputSelector = slash === -1 ? selector : selector.slice(slash + 1)
  const matches: Array<{ config: string; index: number; source: ConfigInput }> = []
  for (const config of contextConfigNames(spec, contextName)) {
    if (configSelector && config !== configSelector) continue
    const inputs = spec.configs[config].inputs
    inputs.forEach((input, index) => {
      if (inputIdentity(input, index) === inputSelector) matches.push({ config, index, source: input })
    })
  }
  if (matches.length !== 1) fail(matches.length === 0 ? `unknown context input: ${selector}` : `ambiguous context input: ${selector}; use CONFIG/INPUT`)
  const selected = matches[0]
  const consumer = bindContextConfigs(spec, contextName, [selected.config]).configs[selected.config].inputs[selected.index]
  return { ...selected, consumer }
}

async function rebuild(options: InputOperationOptions, config: string): Promise<number> {
  const code = await runAssembly({
    spec: options.spec,
    contextName: options.contextName,
    runner: options.runner,
    names: [config],
  })
  if (code === 0) return 0
  console.error(`input mutation remains; config rebuild failed for ${config} (exit ${code})`)
  return 4
}

function localInputPaths(selected: SelectedInput, name: string): { active: string; disabled?: string } {
  if (typeof selected.consumer.directory !== "string") {
    fail(`${selected.config}/${inputIdentity(selected.source, selected.index)} is not a glob input`)
  }
  const suffix = typeof selected.source.disabled_suffix === "string" ? selected.source.disabled_suffix : undefined
  return {
    active: join(selected.consumer.directory, name),
    disabled: suffix ? join(selected.consumer.directory, `${name}${suffix}`) : undefined,
  }
}

async function assertInputBindingSeparated(selected: SelectedInput): Promise<void> {
  if (typeof selected.source.file === "string" && typeof selected.consumer.file === "string") {
    if (await pathsSharePhysicalEntry(selected.source.file, selected.consumer.file)) {
      fail(`${selected.config}/${inputIdentity(selected.source, selected.index)} consumer file aliases canonical input: ${selected.consumer.file}`)
    }
    return
  }
  if (typeof selected.source.directory === "string" && typeof selected.consumer.directory === "string" &&
      await pathsSharePhysicalDirectory(selected.source.directory, selected.consumer.directory)) {
    fail(`${selected.config}/${inputIdentity(selected.source, selected.index)} consumer directory aliases canonical input directory: ${selected.consumer.directory}`)
  }
}

function validateInputName(input: ConfigInput, name: string): void {
  if (!name || basename(name) !== name || name === "." || name === "..") fail(`invalid input filename: ${name}`)
  if (typeof input.pattern !== "string" || !filenameMatches(name, input.pattern)) fail(`${name} does not match input pattern ${String(input.pattern)}`)
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

export async function putInput(options: InputOperationOptions & { selector: string; source: string; name?: string }): Promise<number> {
  const spec = options.spec
  const selector = options.selector
  const sourceArgument = options.source
  const suppliedName = options.name
  const selected = selectInput(spec, options.contextName, selector)
  await assertInputBindingSeparated(selected)
  const source = resolve(sourceArgument)
  if (typeof selected.source.file === "string") {
    if (suppliedName !== undefined) fail(`${selector} is a direct file input and does not accept a destination name`)
    if ((options.initiallyDisabled ?? false)) fail(`${selector} is a direct file input and cannot be disabled`)
    if (typeof selected.consumer.file !== "string") fail(`${selector} has an invalid resolved file binding`)
    await deliver(source, selected.consumer.file, options.strategy ?? getConfigContext(spec, options.contextName).dropins ?? "link")
    console.log(`put\t${selected.config}/${inputIdentity(selected.source, selected.index)}\t${selected.consumer.file}`)
    return (options.rebuild ?? true) ? rebuild(options, selected.config) : 0
  }
  const name = suppliedName ?? basename(source)
  validateInputName(selected.source, name)
  const paths = localInputPaths(selected, name)
  const pair = await inspectPair(paths)
  if (pair.conflict) fail(`both enabled and disabled local entries exist for ${name}`)
  const destination = pair.active.kind !== "missing"
    ? paths.active
    : pair.disabled && pair.disabled.kind !== "missing"
      ? paths.disabled!
      : (options.initiallyDisabled ?? false)
        ? paths.disabled ?? fail(`${selector} cannot be disabled`)
        : paths.active
  await deliver(source, destination, options.strategy ?? getConfigContext(spec, options.contextName).dropins ?? "link")
  console.log(`put\t${selected.config}/${inputIdentity(selected.source, selected.index)}\t${destination}`)
  return (options.rebuild ?? true) ? rebuild(options, selected.config) : 0
}

async function inputMutation(options: InputOperationOptions, action: "enable" | "disable" | "remove", args: string[]): Promise<number> {
  const [selector, name] = args
  if (!selector) fail(`usage: config-inputs.sh ${action} INPUT [NAME]`)
  const selected = selectInput(options.spec, options.contextName, selector)
  if (!getConfigContext(options.spec, options.contextName).canonical || action === "remove") {
    await assertInputBindingSeparated(selected)
  }
  if (typeof selected.source.file === "string") {
    if (action !== "remove") fail(`${selector} is a direct file input and cannot be ${action}d`)
    if (args.length !== 1) fail(`usage: config-inputs.sh remove DIRECT_INPUT`)
    if (typeof selected.consumer.file !== "string") fail(`${selector} has an invalid resolved file binding`)
    const entry = await inspectDeliveryEntry(selected.consumer.file)
    if (entry.kind === "missing") return 0
    replaceableLocal(entry, selected.consumer.file)
    await rm(selected.consumer.file)
    console.log(`remove\t${selected.config}/${inputIdentity(selected.source, selected.index)}\t${selected.consumer.file}`)
    return rebuild(options, selected.config)
  }
  if (!name || args.length !== 2) fail(`usage: config-inputs.sh ${action} INPUT NAME`)
  validateInputName(selected.source, name)
  const paths = localInputPaths(selected, name)
  const pair = await inspectPair(paths)
  if (pair.conflict) fail(`both enabled and disabled local entries exist for ${name}`)
  if (action === "remove") {
    const path = pair.active.kind !== "missing" ? paths.active : pair.disabled && pair.disabled.kind !== "missing" ? paths.disabled! : undefined
    if (!path) return 0
    replaceableLocal(path === paths.active ? pair.active : pair.disabled!, path)
    await rm(path)
    console.log(`remove\t${selected.config}/${inputIdentity(selected.source, selected.index)}\t${path}`)
    return rebuild(options, selected.config)
  }
  if (!paths.disabled) fail(`${selected.config}/${inputIdentity(selected.source, selected.index)} cannot be disabled`)
  const from = action === "disable" ? paths.active : paths.disabled
  const to = action === "disable" ? paths.disabled : paths.active
  const fromEntry = action === "disable" ? pair.active : pair.disabled!
  const toEntry = action === "disable" ? pair.disabled! : pair.active
  if (toEntry.kind !== "missing") return 0
  if (fromEntry.kind === "missing") fail(`local input does not exist: ${from}`)
  replaceableLocal(fromEntry, from)
  await rename(from, to)
  console.log(`${action}\t${selected.config}/${inputIdentity(selected.source, selected.index)}\t${to}`)
  return rebuild(options, selected.config)
}

async function listInputs(options: InputOperationOptions, requested: string[]): Promise<number> {
  const names = selectRecipeNames(options.spec, options.contextName, requested, false)
  const resolved = bindContextConfigs(options.spec, options.contextName, names)
  for (const name of names) {
    options.spec.configs[name].inputs.forEach((input, index) => {
      const local = resolved.configs[name].inputs[index]
      const donor = typeof input.file === "string" ? input.file : input.directory
      const destination = typeof local.file === "string" ? local.file : local.directory
      console.log(`${name}/${inputIdentity(input, index)}\t${donor}\t${destination}`)
    })
  }
  return 0
}

export async function runInputAction(options: InputOperationOptions, commandArgs: string[]): Promise<number> {
  const [action, ...args] = commandArgs
  const spec = options.spec
  if (action === "list") return listInputs(options, args)
  if (action === "status") {
    const names = selectRecipeNames(spec, options.contextName, args)
    const rows = await inputStatusRows(spec, options.contextName, names)
    printStatusRows(rows, options.format ?? "human")
    return statusCode(rows)
  }
  if (action === "put") {
    const [selector, source, name] = args
    if (!selector || !source || args.length > 3) fail("usage: config-inputs.sh put INPUT SOURCE [NAME] [--strategy copy|link]")
    return putInput({ ...options, selector, source, name })
  }
  if (action === "enable" || action === "disable" || action === "remove") return inputMutation(options, action, args)
  fail("usage: config-inputs.sh <list|status|put|enable|disable|remove> ...")
}
