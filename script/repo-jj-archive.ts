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
 *   2. archive/repo-jj-archive.ts — the committed single-file bundle
 *      (erased JS emitted as TypeScript), for trees without source or
 *      locally installed CLI dependencies. Runs on system Node ≥ 26.
 */

import { realpath, stat } from "node:fs/promises";
import { dirname, join, resolve } from "node:path";

type Runner = { main: () => Promise<void> };

async function launch(): Promise<void> {
  const root = resolve(dirname(import.meta.filename), "..");
  const source = join(root, "archive/src/repo-jj-archive.ts");
  const bundle = join(root, "archive/repo-jj-archive.ts");
  const sourceFiles = [
    source,
    join(root, "node_modules/effect"),
    join(root, "node_modules/@effect/platform-node"),
  ];
  const available = await Promise.all(
    sourceFiles.map((path) => stat(path, { throwIfNoEntry: false })),
  );
  const runner = available.every(Boolean) ? source : bundle;
  const { main } = (await import(runner)) as Runner;
  await main();
}

const argvPath = process.argv[1];
if (argvPath) {
  realpath(argvPath).then(
    (realArgv) => {
      if (realArgv !== import.meta.filename) return;
      return launch().catch((error: unknown) => {
        const detail =
          error instanceof AggregateError
            ? error.errors
                .map((item: unknown) => (item instanceof Error ? item.message : String(item)))
                .join("; ")
            : error instanceof Error
              ? error.message
              : String(error);
        console.error(`repo-jj-archive: ${detail}`);
        process.exitCode = 1;
      });
    },
    (error: unknown) => {
      console.error(`repo-jj-archive: ${error instanceof Error ? error.message : String(error)}`);
      process.exitCode = 1;
    },
  );
}
