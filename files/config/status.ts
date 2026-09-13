/** Multi-representation CONFIG status over selected recipes. */

import { readFile, stat } from "node:fs/promises"

import { evaluateAssembly } from "./assembly.ts"
import { bindContextConfigs, getConfigContext, type ConfigSpec } from "./context.ts"
import { inputStatusRows } from "./inputs.ts"
import { printStatusRows, statusCode, type StatusFormat, type StatusRow } from "./report.ts"
import {
  inspectDeliveryEntry,
  linkMatches,
  linkResolvesToSameFile,
  pathsSharePhysicalEntry,
} from "../links/delivery.ts"

export type ContextStatusOptions = {
  spec: ConfigSpec
  contextName: string
  runner: string
  names: string[]
  format: StatusFormat
}

type ContentComparison = { equal: boolean; error?: string }

async function sameContents(first: string, second: string): Promise<ContentComparison> {
  try {
    const [one, two] = await Promise.all([readFile(first), readFile(second)])
    return { equal: one.equals(two) }
  } catch (error) {
    return { equal: false, error: `cannot compare ${first} and ${second}: ${error instanceof Error ? error.message : String(error)}` }
  }
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

async function candidateMatches(candidate: Buffer, destination: string): Promise<ContentComparison> {
  try {
    return { equal: candidate.equals(await readFile(destination)) }
  } catch (error) {
    return { equal: false, error: `cannot read assembled output ${destination}: ${error instanceof Error ? error.message : String(error)}` }
  }
}

async function outputStatusRows(options: ContextStatusOptions): Promise<StatusRow[]> {
  const resolved = bindContextConfigs(options.spec, options.contextName, options.names)
  const rows: StatusRow[] = []
  for (const name of options.names) {
    const source = options.spec.configs[name].output
    const destination = resolved.configs[name].output
    const [sourceState, entry, assembly, aliasHazard] = await Promise.all([
      usableSource(source),
      inspectDeliveryEntry(destination),
      evaluateAssembly(options, name),
      pathsSharePhysicalEntry(source, destination),
    ])
    const common = { kind: "output" as const, config: name, name, source, destination }
    rows.push(assembly.error
      ? { kind: "assembly", status: "evaluation-error", severity: "error", config: name, name, note: assembly.error }
      : { kind: "assembly", status: "ready", severity: "ok", config: name, name })
    if (aliasHazard) {
      rows.push({ ...common, status: "alias-hazard", severity: "error", note: `consumer output aliases canonical output: ${destination}` })
      continue
    }
    if (entry.kind === "missing") {
      rows.push({ ...common, status: "missing", severity: "drift", note: sourceState.usable ? undefined : `canonical output unavailable: ${sourceState.note}` })
      continue
    }
    if (entry.kind === "directory" || entry.kind === "special") {
      rows.push({ ...common, status: "unsupported", severity: "drift", representation: entry.kind })
      continue
    }
    if (entry.kind === "symlink") {
      if (!sourceState.usable && linkMatches(entry, source)) {
        rows.push({ ...common, status: "donor-missing", severity: "error", representation: "link", note: sourceState.note })
        continue
      }
      if (sourceState.usable) {
        try {
          if (await linkResolvesToSameFile(entry, source)) {
            rows.push({ ...common, status: "ok", severity: "ok", representation: "link" })
            continue
          }
        } catch (error) {
          rows.push({
            ...common, status: "evaluation-error", severity: "error", representation: "link",
            note: `cannot resolve link referents: ${error instanceof Error ? error.message : String(error)}`,
          })
          continue
        }
      }
      rows.push({ ...common, status: "modified", severity: "drift", representation: "link", note: `points to ${entry.target}` })
      continue
    }

    let donorComparisonError: string | undefined
    if (sourceState.usable) {
      const donorComparison = await sameContents(source, destination)
      if (donorComparison.equal) {
        rows.push({ ...common, status: "ok", severity: "ok", representation: "copy" })
        continue
      }
      donorComparisonError = donorComparison.error
      if (donorComparison.error && !assembly.candidate) {
        rows.push({ ...common, status: "evaluation-error", severity: "error", representation: "copy", note: donorComparison.error })
        continue
      }
    }
    if (assembly.candidate) {
      const localComparison = await candidateMatches(assembly.candidate, destination)
      if (localComparison.error) {
        rows.push({ ...common, status: "evaluation-error", severity: "error", representation: "assembly", note: localComparison.error })
      } else if (localComparison.equal) {
        rows.push({
          ...common, status: "ok", severity: "ok", representation: "assembly",
          note: donorComparisonError ?? (sourceState.usable ? undefined : `canonical output unavailable: ${sourceState.note}`),
        })
      } else {
        rows.push({
          ...common, status: "modified", severity: "drift", representation: "assembly",
          note: donorComparisonError ?? (sourceState.usable ? "differs from donor and local assembly" : `differs from local assembly; canonical output unavailable: ${sourceState.note}`),
        })
      }
    } else {
      rows.push({ ...common, status: "unclassified", severity: "error", representation: "file", note: "assembly evaluation failed" })
    }
  }
  return rows
}

async function assemblyInputsActive(spec: ConfigSpec, contextName: string, config: string): Promise<boolean> {
  const resolved = bindContextConfigs(spec, contextName, [config]).configs[config]
  for (const input of resolved.inputs) {
    const path = typeof input.file === "string" ? input.file : input.directory
    if (typeof path !== "string") continue
    if ((await inspectDeliveryEntry(path)).kind !== "missing") return true
  }
  return false
}

async function markInactiveAssemblyRoutes(options: ContextStatusOptions, rows: StatusRow[]): Promise<void> {
  for (const config of options.names) {
    const output = rows.find((row) => row.kind === "output" && row.config === config)
    const assembly = rows.find((row) => row.kind === "assembly" && row.config === config)
    const healthyWhole = output?.status === "ok" && (output.representation === "copy" || output.representation === "link")
    if (!healthyWhole || assembly?.status !== "evaluation-error" || await assemblyInputsActive(options.spec, options.contextName, config)) continue
    assembly.status = "inactive"
    assembly.severity = "ok"
    assembly.note = `local assembly inputs are not initialized; ${assembly.note}`
    for (const row of rows) {
      if (row.kind === "input" && row.config === config && row.status === "missing") {
        row.status = "inactive"
        row.severity = "ok"
        row.note = row.note ? `inactive assembly route: ${row.note}` : "inactive assembly route"
      }
    }
  }
}

async function canonicalStatusRows(options: ContextStatusOptions): Promise<StatusRow[]> {
  const rows: StatusRow[] = []
  for (const name of options.names) {
    const destination = options.spec.configs[name].output
    const [entry, assembly] = await Promise.all([
      inspectDeliveryEntry(destination),
      evaluateAssembly(options, name),
    ])
    if (assembly.error) {
      rows.push({ kind: "assembly", status: "evaluation-error", severity: "error", config: name, name, destination, note: assembly.error })
      continue
    }
    rows.push({ kind: "assembly", status: "ready", severity: "ok", config: name, name, destination })
    if (entry.kind === "missing") {
      rows.push({ kind: "output", status: "missing", severity: "drift", config: name, name, destination })
    } else if (entry.kind !== "file") {
      rows.push({ kind: "output", status: "unsupported", severity: "drift", config: name, name, destination, representation: entry.kind, note: "canonical assembly owns a regular file" })
    } else {
      const comparison = await candidateMatches(assembly.candidate!, destination)
      rows.push(comparison.error
        ? { kind: "output", status: "evaluation-error", severity: "error", config: name, name, destination, representation: "assembly", note: comparison.error }
        : { kind: "output", status: comparison.equal ? "ok" : "modified", severity: comparison.equal ? "ok" : "drift", config: name, name, destination, representation: "assembly" })
    }
  }
  return rows
}

export async function statusContext(options: ContextStatusOptions): Promise<number> {
  const context = getConfigContext(options.spec, options.contextName)
  const rows = context.canonical
    ? await canonicalStatusRows(options)
    : [...await outputStatusRows(options), ...await inputStatusRows(options.spec, options.contextName, options.names)]
  if (!context.canonical) await markInactiveAssemblyRoutes(options, rows)
  printStatusRows(rows, options.format)
  return statusCode(rows)
}
