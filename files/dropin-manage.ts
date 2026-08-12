#!/usr/bin/env node
/** Publish and remove files in named DROPINS sets. */

import { spawn } from "node:child_process"
import { access, mkdir, readFile, rename, rm, writeFile } from "node:fs/promises"
import { basename, join } from "node:path"

const selfDir = "{{DIR}}"

async function exists(path: string): Promise<boolean> {
  return access(path).then(() => true, () => false)
}

function matches(pattern: string, value: string): boolean {
  const escaped = pattern.replace(/[.+^${}()|[\]\\]/g, "\\$&")
  return new RegExp(`^${escaped.replaceAll("*", ".*").replaceAll("?", ".")}$`).test(value)
}

async function rebuild(): Promise<void> {
  const command = join(selfDir, "bin", "config.sh")
  if (!(await exists(command))) return
  await new Promise<void>((resolve, reject) => {
    const child = spawn(command, [], { cwd: selfDir, stdio: "inherit" })
    child.once("error", reject)
    child.once("exit", (code, signal) => {
      if (code === 0) resolve()
      else reject(new Error(`config rebuild failed: ${signal ?? code}`))
    })
  })
}

async function main(): Promise<void> {
  const [action, setName, value, requestedName] = process.argv.slice(2)
  if (!(["put", "remove"].includes(action)) || !setName || !value) {
    throw new Error("usage: dropin-manage.ts put <set> <source> [name] | remove <set> <name>")
  }

  const spec = JSON.parse(await readFile(join(selfDir, "etc", "config.spec.json"), "utf-8"))
  const dropin = spec.dropins?.[setName]
  if (!dropin || typeof dropin.path !== "string") throw new Error(`unknown DROPINS set: ${setName}`)

  const name = action === "put" ? (requestedName ?? basename(value)) : value
  if (basename(name) !== name || name === "." || name === "..") throw new Error(`invalid fragment name: ${name}`)
  if (!matches(dropin.include, name)) throw new Error(`${name} does not match ${setName} include ${dropin.include}`)

  const active = join(dropin.path, name)
  const disabled = dropin.disabled_suffix ? `${active}${dropin.disabled_suffix}` : undefined
  const activeExists = await exists(active)
  const disabledExists = disabled ? await exists(disabled) : false
  if (activeExists && disabledExists) throw new Error(`both active and disabled fragments exist: ${name}`)

  const destination = disabledExists ? disabled! : active
  const previous = (activeExists || disabledExists) ? await readFile(destination) : undefined

  await mkdir(dropin.path, { recursive: true })
  if (action === "put") {
    const temporary = join(dropin.path, `.${name}.tmp-${process.pid}`)
    await writeFile(temporary, await readFile(value))
    await rename(temporary, destination).catch(async (error) => {
      await rm(temporary, { force: true })
      throw error
    })
  } else if (activeExists || disabledExists) {
    await rm(destination)
  } else {
    return
  }

  try {
    await rebuild()
  } catch (error) {
    if (previous === undefined) await rm(destination, { force: true })
    else await writeFile(destination, previous)
    throw error
  }

  console.log(`${action}: ${setName}/${name}${disabledExists ? " (disabled)" : ""}`)
}

main().catch((error: unknown) => {
  console.error(`error: ${error instanceof Error ? error.message : String(error)}`)
  process.exitCode = 1
})
