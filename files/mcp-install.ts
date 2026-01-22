#!/usr/bin/env node
/**
 * install-mcp.ts - Install an MCP server configuration
 *
 * This script:
 * 1. Sources environment from source package's env.export
 * 2. Substitutes ${VAR} placeholders in mcp.json
 * 3. Filters out command array elements that reference empty/undefined variables
 * 4. Optionally splits command array into command+args (for amp format)
 * 5. Wraps result in configured format and writes to target
 *
 * Environment variables:
 *   MCP_TARGET  - Directory to write mcp config (default: $DIR/etc/mcp)
 *   MCP_WRAPPER - JSON wrapper path: "mcp" or "amp.mcpServers" (default: mcp)
 *   MCP_COMMAND_ARGS - If set, split command[0] into command, rest into args
 *
 * Usage: install-mcp.ts [source_dir]
 */

import { execSync } from "node:child_process"
import { existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs"
import { basename, dirname, join } from "node:path"

const selfDir = "{{DIR}}"
const suffixesToStrip = ["-git", "-main"]

interface McpConfig {
  type?: string
  url?: string
  headers?: Record<string, string>
  command?: string | string[]
  args?: string[]
  environment?: Record<string, string>
  enabled?: boolean
  [key: string]: unknown
}

function sourceEnvExport(path: string): void {
  if (!existsSync(path)) return

  const content = readFileSync(path, "utf-8")
  for (const line of content.split("\n")) {
    const trimmed = line.trim()
    if (!trimmed || trimmed.startsWith("#")) continue

    // Handle: export VAR=value, VAR=value
    const match = trimmed.match(/^(?:export\s+)?([A-Za-z_][A-Za-z0-9_]*)=(.*)$/)
    if (match) {
      let [, key, value] = match
      // Strip quotes
      value = value.replace(/^["']|["']$/g, "")
      process.env[key] = value
    }
  }
}

function envsubst(text: string): string {
  let prev = ""
  let current = text

  while (current !== prev) {
    prev = current
    current = current.replace(/\$\{([A-Za-z_][A-Za-z0-9_]*)\}/g, (_, varName) => {
      return process.env[varName] ?? ""
    })
  }

  return current
}

function hasEmptyVarRef(arg: string): boolean {
  const varPattern = /\$\{([A-Za-z_][A-Za-z0-9_]*)\}/g
  let match
  while ((match = varPattern.exec(arg)) !== null) {
    const varName = match[1]
    const value = process.env[varName]
    if (!value || value.length === 0) {
      return true
    }
  }
  return false
}

function filterEmptyArgs(config: McpConfig): McpConfig {
  if (!Array.isArray(config.command)) return config

  const filtered = config.command.filter((arg) => !hasEmptyVarRef(arg))

  if (filtered.length === 0) {
    const { command: _, ...rest } = config
    return rest
  }

  return { ...config, command: filtered }
}

function simplifyFlags(config: McpConfig): McpConfig {
  if (!Array.isArray(config.command)) return config

  const simplified = config.command.map((arg) => {
    if (arg.endsWith("=true")) return arg.slice(0, -5)
    return arg
  })

  return { ...config, command: simplified }
}

function commandArgSplitter(config: McpConfig): McpConfig {
  if (!process.env.MCP_COMMAND_ARGS) return config
  if (!Array.isArray(config.command)) return config

  const [cmd, ...args] = config.command
  const result: McpConfig = { ...config, command: cmd }

  if (args.length > 0) {
    result.args = args
  }

  return result
}

function wrapMcp(name: string, config: McpConfig): Record<string, unknown> {
  const wrapper = process.env.MCP_WRAPPER ?? "mcp"
  const wrapped = { ...config, enabled: true }

  return { [wrapper]: { [name]: wrapped } }
}

function main(): void {
  // Source self env.export first
  sourceEnvExport(join(selfDir, "env.export"))

  const srcDir = process.argv[2] ?? process.cwd()
  const dirName = basename(srcDir)
  let name = dirName
  for (const suffix of suffixesToStrip) {
    if (name.endsWith(suffix)) {
      name = name.slice(0, -suffix.length)
    }
  }
  const mcpFile = join(srcDir, "etc", "mcp.json")

  if (!existsSync(mcpFile)) {
    console.error(`error: ${mcpFile} not found`)
    process.exit(1)
  }

  // Source source package env.export
  sourceEnvExport(join(srcDir, "env.export"))

  const targetDir = process.env.MCP_TARGET ?? join(selfDir, "etc", "mcp")
  const target = join(targetDir, `${name}.json`)

  mkdirSync(targetDir, { recursive: true })

  // Read and process
  const raw = readFileSync(mcpFile, "utf-8")
  const substituted = envsubst(raw)
  let config: McpConfig = JSON.parse(substituted)

  config = filterEmptyArgs(config)
  config = simplifyFlags(config)
  config = commandArgSplitter(config)
  const wrapped = wrapMcp(name, config)

  writeFileSync(target, JSON.stringify(wrapped, null, "\t") + "\n")
  console.log(`installed: ${target}`)

  // Run config.sh if exists
  const configSh = join(selfDir, "bin", "config.sh")
  if (existsSync(configSh)) {
    execSync("./bin/config.sh", { cwd: selfDir, stdio: "inherit" })
  }
}

main()
