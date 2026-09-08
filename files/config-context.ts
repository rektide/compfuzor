#!/usr/bin/env -S node --disable-warning=MODULE_TYPELESS_PACKAGE_JSON
/** Thin CLI facade for reusable CONFIGS consumer-context binding. */

import { spawn, type ChildProcess, type StdioOptions } from "node:child_process"
import { constants as osConstants } from "node:os"
import { realpath } from "node:fs/promises"
import { mkdtemp, readFile, rm, writeFile } from "node:fs/promises"
import { dirname, join, resolve } from "node:path"
import { tmpdir } from "node:os"
import { fileURLToPath } from "node:url"

import { bindContextSpec, type ConfigSpec } from "./config/context.ts"
import { pathsSharePhysicalEntry } from "./links/delivery.ts"

export type ConfigContextCliOptions = {
  context: string
  specPath: string
  runner: string
  runnerArgs: string[]
  stdio?: "inherit" | "ignore" | "pipe"
}

export type ConfigContextResult = {
  code: number
  stdout: Buffer
  stderr: Buffer
}

function isPreview(runnerArgs: string[]): boolean {
  return runnerArgs.some((argument) => argument === "--list" || argument === "--check" || argument === "--stdout")
}

async function assertContextOutputsSeparated(source: ConfigSpec, resolved: ConfigSpec): Promise<void> {
  for (const [name, config] of Object.entries(resolved.configs)) {
    const canonical = source.configs[name]?.output
    if (canonical && await pathsSharePhysicalEntry(canonical, config.output)) {
      throw new Error(`context output aliases canonical output for ${name}: ${config.output}`)
    }
  }
}

function fail(message: string): never {
  throw new Error(message)
}

export function parseConfigContextArgs(argv: string[], deploymentDir: string): ConfigContextCliOptions {
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

function signalExitCode(signal: NodeJS.Signals): number {
  const number = osConstants.signals[signal]
  return typeof number === "number" ? 128 + number : 1
}

async function invokeRunner(options: ConfigContextCliOptions, specPath: string): Promise<ConfigContextResult> {
  const runnerDeploymentDir = resolve(dirname(options.runner), "..")
  return await new Promise<ConfigContextResult>((complete, reject) => {
    const stdio: StdioOptions = options.stdio === "pipe" ? ["ignore", "pipe", "pipe"] : (options.stdio ?? "inherit")
    const child: ChildProcess = spawn(options.runner, options.runnerArgs, {
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

export async function runConfigContextResult(options: ConfigContextCliOptions): Promise<ConfigContextResult> {
  const spec = JSON.parse(await readFile(options.specPath, "utf8")) as ConfigSpec
  const resolvedSpec = bindContextSpec(spec, options.context, options.runnerArgs)
  if (!isPreview(options.runnerArgs)) await assertContextOutputsSeparated(spec, resolvedSpec)
  const temporary = await mkdtemp(join(tmpdir(), "compfuzor-config-context-"))
  const resolvedPath = join(temporary, "config.spec.json")
  try {
    await writeFile(resolvedPath, JSON.stringify(resolvedSpec), { mode: 0o600 })
    return await invokeRunner(options, resolvedPath)
  } finally {
    await rm(temporary, { recursive: true, force: true })
  }
}

export async function runConfigContext(options: ConfigContextCliOptions): Promise<number> {
  return (await runConfigContextResult(options)).code
}

export async function main(argv: string[] = process.argv.slice(2), modulePath: string = fileURLToPath(import.meta.url)): Promise<number> {
  const realModulePath = await realpath(modulePath)
  const deploymentDir = resolve(dirname(realModulePath), "..")
  return runConfigContext(parseConfigContextArgs(argv, deploymentDir))
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
