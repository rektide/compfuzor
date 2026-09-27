#!/usr/bin/env -S node --disable-warning=MODULE_TYPELESS_PACKAGE_JSON
/**
 * Compatibility launcher for the archive runner, which now lives at
 * archive/src/repo-jj-archive.ts (see archive/README.md).
 *
 * tasks/compfuzor/repo_jj_archive.tasks and tests/integration/repo_jj_archive.test.py
 * invoke this path, so it stays as a thin shim. Resolution order:
 *
 *   1. archive/src/repo-jj-archive.ts — run the TypeScript source directly
 *      via Node type stripping; no bundler transport between checkout and
 *      execution.
 *   2. archive/repo-jj-archive.mjs — the committed build output, for trees
 *      that ship only built artifacts.
 */

import { realpath, stat } from "node:fs/promises"
import { dirname, join, resolve } from "node:path"

type Runner = { main: () => Promise<void> }

async function launch(): Promise<void> {
  const root = resolve(dirname(import.meta.filename), "..")
  const source = join(root, "archive/src/repo-jj-archive.ts")
  const bundle = join(root, "archive/repo-jj-archive.mjs")
  const runner = (await stat(source, { throwIfNoEntry: false })) === undefined ? bundle : source
  const { main } = (await import(runner)) as Runner
  await main()
}

const argvPath = process.argv[1]
if (argvPath) {
  realpath(argvPath).then(
    (realArgv) => {
      if (realArgv !== import.meta.filename) return
      return launch().catch((error: unknown) => {
        console.error(`repo-jj-archive: ${error instanceof Error ? error.message : String(error)}`)
        process.exitCode = 1
      })
    },
    (error: unknown) => {
      console.error(`repo-jj-archive: ${error instanceof Error ? error.message : String(error)}`)
      process.exitCode = 1
    },
  )
}
