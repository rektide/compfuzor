/** Bind CONFIG recipes to one context and invoke the sole transaction runner. */

import { spawn, type ChildProcess, type StdioOptions } from "node:child_process"
import { constants as osConstants } from "node:os"
import { mkdtemp, rm, writeFile } from "node:fs/promises"
import { basename, dirname, join, resolve } from "node:path"
import { tmpdir } from "node:os"

import { bindContextConfigs, getConfigContext, type ConfigSpec } from "./context.ts"
import { pathsSharePhysicalEntry } from "../links/delivery.ts"

export type AssemblyOptions = {
  spec: ConfigSpec
  contextName: string
  runner: string
  names: string[]
  check?: boolean
  stdout?: boolean
  quiet?: boolean
  stdio?: "inherit" | "ignore" | "pipe"
}

export type AssemblyResult = {
  code: number
  stdout: Buffer
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
