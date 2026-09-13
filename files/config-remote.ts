#!/usr/bin/env node
/** Source CLI wrapper for the domain-grouped config-remote runtime. */

import { realpath } from "node:fs/promises"
import { dirname, resolve } from "node:path"
import { fileURLToPath } from "node:url"

import { main } from "./config-remote/runtime.ts"

export * from "./config-remote/runtime.ts"

const argvPath = process.argv[1]
if (argvPath) {
  Promise.all([realpath(argvPath), realpath(fileURLToPath(import.meta.url))]).then(
    ([realArgvPath, realModulePath]) => {
      if (realArgvPath !== realModulePath) return
      const deploymentDir = resolve(dirname(realModulePath), "..")
      return main(process.argv.slice(2), deploymentDir).catch((error: unknown) => {
        console.error(`error: ${error instanceof Error ? error.message : String(error)}`)
        process.exitCode = 1
      })
    },
    (error: unknown) => {
      console.error(`error: ${error instanceof Error ? error.message : String(error)}`)
      process.exitCode = 1
    },
  )
}
