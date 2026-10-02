/** Bind CONFIG recipes to one context and invoke the sole transaction runner. */

import { spawn, type ChildProcess, type StdioOptions } from "node:child_process"
import { constants as osConstants } from "node:os"
import { mkdtemp, rm, writeFile } from "node:fs/promises"
import { basename, dirname, join, resolve } from "node:path"
import { tmpdir } from "node:os"

import { bindContextConfigs, getConfigContext, type ConfigSpec } from "./context.ts"
import { pathsSharePhysicalEntry } from "../links/delivery.ts"

/** Existing runner invocation used by domain adapters; apply is already a complete publication. */
export type AssemblyOptions = {
  /** Compiled/runtime spec; context binding retains leaf/link and transaction hook extensions. */
  spec: ConfigSpec
  /** Explicit context key whose selectors resolve before spawning the runner. */
  contextName: string
  /** Existing worker executable; deployment identity is derived from this path, not inherited DIR. */
  runner: string
  /** Explicit recipe selection/order; consumer adapters offer one sole-candidate recipe per output. */
  names: string[]
  /** Prepare/validate and report drift without output publication. */
  check?: boolean
  /** Return one selected validated candidate's bytes; not multi-output preparation or commit. */
  stdout?: boolean
  /** Suppress drift detail where supported by the existing runner. */
  quiet?: boolean
  /** Pipe captures streams in AssemblyResult; inherit/ignore normally return empty buffers. */
  stdio?: "inherit" | "ignore" | "pipe"
}

/** Process outcome, not a durable history or crash-atomic transaction claim. */
export type AssemblyResult = {
  /** Exit code (or signal-derived code); native/transaction validation failure stays nonzero. */
  code: number
  /** Captured stdout when piped; stdout mode contains candidate bytes, apply contains runner output. */
  stdout: Buffer
  /** Captured diagnostics when piped; the adapter does not reinterpret native errors as success. */
  stderr: Buffer
}

async function assertContextOutputsSeparated(source: ConfigSpec, resolved: ConfigSpec): Promise<void> {
  for (const [name, config] of Object.entries(resolved.configs)) {
    const canonical = source.configs[name]?.output
    if (canonical && await pathsSharePhysicalEntry(canonical, config.output)) {
      throw new Error(`context output aliases canonical output for ${name}: ${config.output}`)
    }
  }
}

function signalExitCode(signal: NodeJS.Signals): number {
  const number = osConstants.signals[signal]
  return typeof number === "number" ? 128 + number : 1
}

async function invokeRunner(options: AssemblyOptions, specPath: string): Promise<AssemblyResult> {
  const runnerDirectory = dirname(options.runner)
  const runnerDeploymentDir = resolve(runnerDirectory, basename(runnerDirectory) === "config" ? "../.." : "..")
  const args = [
    ...(options.check ? ["--check"] : []),
    ...(options.stdout ? ["--stdout"] : []),
    ...(options.quiet ? ["--quiet"] : []),
    ...options.names,
  ]
  return await new Promise<AssemblyResult>((complete, reject) => {
    const stdio: StdioOptions = options.stdio === "pipe" ? ["ignore", "pipe", "pipe"] : (options.stdio ?? "inherit")
    const child: ChildProcess = spawn(options.runner, args, {
      cwd: runnerDeploymentDir,
      detached: true,
      env: { ...process.env, DIR: runnerDeploymentDir, CONFIG_SPEC: specPath },
      stdio,
    })
    const stdout: Buffer[] = []
    const stderr: Buffer[] = []
    child.stdout?.on("data", (chunk: Buffer | string) => stdout.push(Buffer.from(chunk)))
    child.stderr?.on("data", (chunk: Buffer | string) => stderr.push(Buffer.from(chunk)))
    const handlers = new Map<NodeJS.Signals, () => void>()
    const cleanupHandlers = (): void => {
      for (const [signal, handler] of handlers) process.off(signal, handler)
    }
    for (const signal of ["SIGINT", "SIGHUP", "SIGTERM"] as const) {
      const handler = (): void => {
        if (child.pid === undefined) return
        try {
          process.kill(-child.pid, signal)
        } catch (error) {
          if ((error as NodeJS.ErrnoException).code !== "ESRCH") reject(error)
        }
      }
      handlers.set(signal, handler)
      process.on(signal, handler)
    }
    child.once("error", (error) => {
      cleanupHandlers()
      reject(error)
    })
    child.once("exit", (code, signal) => {
      cleanupHandlers()
      complete({
        code: signal ? signalExitCode(signal) : (code ?? 1),
        stdout: Buffer.concat(stdout),
        stderr: Buffer.concat(stderr),
      })
    })
  })
}

/**
 * Bind context paths, write a private resolved spec and invoke the existing runner once.
 * Apply commits inside that runner; callers must not call this as prepare-only and
 * then publish the same outputs again. Retained transaction_validate hooks see all
 * candidates before publication; stdout/check remain non-publishing modes.
 * @param options Explicit worker/context/recipe binding and stream/mode policy.
 * @returns Runner outcome/streams after it completes; no second publisher runs here.
 * @throws On context/path/alias validation, scratch/spec I/O, process setup or cleanup
 * errors. Cleanup can fail after a successful mutation, so rejection is not safe-retry proof.
 * @see /doc/config/keybinding-consumers.md
 */
export async function runAssemblyResult(options: AssemblyOptions): Promise<AssemblyResult> {
  const resolvedSpec = bindContextConfigs(options.spec, options.contextName, options.names)
  const context = getConfigContext(options.spec, options.contextName)
  if (!context.canonical && !options.check && !options.stdout) {
    await assertContextOutputsSeparated(options.spec, resolvedSpec)
  }
  const temporary = await mkdtemp(join(tmpdir(), "compfuzor-config-context-"))
  const resolvedPath = join(temporary, "config.spec.json")
  try {
    await writeFile(resolvedPath, JSON.stringify(resolvedSpec), { mode: 0o600 })
    return await invokeRunner(options, resolvedPath)
  } finally {
    await rm(temporary, { recursive: true, force: true })
  }
}

/**
 * Convenience form of the same COMPLETE runner operation, returning only its code.
 * @param options Same explicit binding/mode policy as runAssemblyResult.
 * @returns Runner code; no additional publication follows successful apply.
 * @throws Propagates context/process/scratch errors from runAssemblyResult.
 */
export async function runAssembly(options: AssemblyOptions): Promise<number> {
  return (await runAssemblyResult(options)).code
}

export async function evaluateAssembly(options: Omit<AssemblyOptions, "names" | "stdout" | "stdio">, name: string): Promise<{ candidate?: Buffer; error?: string }> {
  try {
    const result = await runAssemblyResult({ ...options, names: [name], stdout: true, stdio: "pipe" })
    if (result.code === 0) return { candidate: result.stdout }
    const detail = result.stderr.toString("utf8").trim()
    return { error: `assembly candidate failed (exit ${result.code})${detail ? `: ${detail}` : ""}` }
  } catch (error) {
    return { error: `assembly candidate could not run: ${error instanceof Error ? error.message : String(error)}` }
  }
}
