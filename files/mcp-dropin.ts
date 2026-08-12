#!/usr/bin/env node
/** Transform a portable MCP record, then delegate its lifecycle to DROPINS. */

import { spawn } from "node:child_process"
import { access, mkdtemp, readFile, rm, writeFile } from "node:fs/promises"
import { tmpdir } from "node:os"
import { basename, join } from "node:path"

const selfDir = "{{DIR}}"

async function exists(path: string): Promise<boolean> {
  return access(path).then(() => true, () => false)
}

async function sourceEnv(path: string): Promise<void> {
  if (!(await exists(path))) return
  for (const line of (await readFile(path, "utf-8")).split("\n")) {
    const match = line.trim().match(/^(?:export\s+)?([A-Za-z_][A-Za-z0-9_]*)=(.*)$/)
    if (match) process.env[match[1]] = match[2].replace(/^["']|["']$/g, "")
  }
}

function envsubst(text: string): string {
  let previous = ""
  while (text !== previous) {
    previous = text
    text = text.replace(/\$\{([A-Za-z_][A-Za-z0-9_]*)\}/g, (_, name) => process.env[name] ?? "")
  }
  return text
}

function transform(name: string, config: Record<string, unknown>, wrapper: string, splitArgs: boolean): object {
  if (Array.isArray(config.command)) {
    const command = config.command.map((argument: string) => argument.endsWith("=true") ? argument.slice(0, -5) : argument)
    if (splitArgs) {
      const [executable, ...args] = command
      config.command = executable
      if (args.length) config.args = args
    } else config.command = command
  }
  let cursor: Record<string, unknown> = {}
  const result = cursor
  for (const part of wrapper.split(".")) {
    const next: Record<string, unknown> = {}
    cursor[part] = next
    cursor = next
  }
  cursor[name] = { ...config, enabled: true }
  return result
}

async function delegate(setName: string, source: string, name: string): Promise<void> {
  await new Promise<void>((resolve, reject) => {
    const child = spawn(join(selfDir, "bin", "dropin-manage.ts"), ["put", setName, source, name], { cwd: selfDir, stdio: "inherit" })
    child.once("error", reject)
    child.once("exit", (code, signal) => code === 0 ? resolve() : reject(new Error(`drop-in manager failed: ${signal ?? code}`)))
  })
}

async function main(): Promise<void> {
  const [setName, wrapper, splitArgs, sourceArg] = process.argv.slice(2)
  if (!setName || !wrapper) throw new Error("usage: mcp-dropin.ts <dropins> <wrapper> <command-args> [source-dir]")
  const sourceDir = sourceArg ?? process.cwd()
  const mcpFile = join(sourceDir, "etc", "mcp.json")
  if (!(await exists(mcpFile))) throw new Error(`${mcpFile} not found`)
  await sourceEnv(join(sourceDir, "env.export"))
  let name = basename(sourceDir).replace(/-(git|main)$/, "")
  const config = JSON.parse(envsubst(await readFile(mcpFile, "utf-8")))
  const directory = await mkdtemp(join(tmpdir(), "compfuzor-mcp-"))
  const fragment = join(directory, `${name}.json`)
  try {
    await writeFile(fragment, `${JSON.stringify(transform(name, config, wrapper, splitArgs === "true"), null, "\t")}\n`)
    await delegate(setName, fragment, `${name}.json`)
  } finally {
    await rm(directory, { recursive: true, force: true })
  }
}

main().catch((error: unknown) => {
  console.error(`error: ${error instanceof Error ? error.message : String(error)}`)
  process.exitCode = 1
})
