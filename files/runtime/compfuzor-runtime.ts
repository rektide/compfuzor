#!/usr/bin/env -S node --disable-warning=MODULE_TYPELESS_PACKAGE_JSON
/** Minimal multicall entry for Compfuzor's domain-grouped JavaScript runtimes. */

import { readlink, realpath } from "node:fs/promises";
import { basename, dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

import { main as runConfig } from "../config/runtime.ts";
import { main as runConfigRemote } from "../config-remote/runtime.ts";
import { main as runCatalog } from "../catalog/runtime.ts";
import { main as runLinks } from "../links/runtime.ts";
import { main as runZim } from "../zim/runtime.ts";

export type RuntimeDomain = "catalog" | "config" | "config-remote" | "links" | "zim";

const RUNTIME_NAME = "compfuzor-runtime.mjs";
const RUNTIME_SOURCE_NAME = "compfuzor-runtime.ts";
const USAGE = `Usage: compfuzor-runtime.mjs <catalog|config|config-remote|links|zim> ...

Ordinary deployments invoke this multicall runtime through stable domain
aliases such as config/command.mjs, config-remote.mjs, links.mjs, and
zim/install.mjs.`;

function fail(message: string): never {
  throw new Error(message);
}

function classifyCandidate(path: string): RuntimeDomain | undefined {
  const name = basename(path);
  if (name === "compfuzor-catalog.sh") return "catalog";
  if (name === "config-remote.mjs") return "config-remote";
  if (name === "links.mjs") return "links";
  if (name === "command.mjs" && basename(dirname(path)) === "config") return "config";
  if (name === "install.mjs" && basename(dirname(path)) === "zim") return "zim";
  if (name.startsWith("config-") && name.endsWith(".sh")) return "config";
  return undefined;
}

async function invocationChain(argvPath: string): Promise<string[]> {
  const chain = [resolve(argvPath)];
  const seen = new Set(chain);
  for (let depth = 0; depth < 64; depth++) {
    const current = chain.at(-1)!;
    let target: string;
    try {
      target = await readlink(current);
    } catch (error) {
      const code = (error as NodeJS.ErrnoException).code;
      if (code === "EINVAL" || code === "ENOENT") return chain;
      throw error;
    }
    const next = resolve(dirname(current), target);
    if (seen.has(next)) fail(`cyclic runtime command symlink: ${argvPath}`);
    chain.push(next);
    seen.add(next);
  }
  fail(`runtime command symlink chain is too deep: ${argvPath}`);
}

async function selectedDomain(
  argvPath: string,
  argv: string[],
): Promise<{ domain: RuntimeDomain; argv: string[]; invokedAs: string }> {
  const chain = await invocationChain(argvPath);
  for (const candidate of chain) {
    const domain = classifyCandidate(candidate);
    if (domain) return { domain, argv, invokedAs: basename(argvPath) };
  }
  if (basename(argvPath) !== RUNTIME_NAME && basename(argvPath) !== RUNTIME_SOURCE_NAME) {
    fail(`unknown Compfuzor runtime alias: ${basename(argvPath)}\n${USAGE}`);
  }
  const [domain, ...domainArgv] = argv;
  if (
    domain !== "catalog" &&
    domain !== "config" &&
    domain !== "config-remote" &&
    domain !== "links" &&
    domain !== "zim"
  ) {
    fail(USAGE);
  }
  return { domain, argv: domainArgv, invokedAs: domain === "config" ? "command.ts" : RUNTIME_NAME };
}

async function runDomain(
  domain: RuntimeDomain,
  argv: string[],
  invokedAs: string,
  deploymentDir: string,
): Promise<number> {
  try {
    if (domain === "catalog") return await runCatalog(argv, deploymentDir);
    if (domain === "config") return await runConfig(argv, deploymentDir, invokedAs);
    if (domain === "links") return await runLinks(argv, deploymentDir);
    if (domain === "zim") return await runZim(argv, deploymentDir);
    await runConfigRemote(argv, deploymentDir);
    return 0;
  } catch (error) {
    if (domain === "config-remote") {
      console.error(`error: ${error instanceof Error ? error.message : String(error)}`);
      return 1;
    }
    console.error(error instanceof Error ? error.stack : String(error));
    return 2;
  }
}

function deploymentDirectory(realModulePath: string): string {
  return realModulePath.endsWith(".ts")
    ? resolve(dirname(realModulePath), "../..")
    : resolve(dirname(realModulePath), "..");
}

export async function main(
  argv: string[] = process.argv.slice(2),
  argvPath: string | undefined = process.argv[1],
  modulePath: string = fileURLToPath(import.meta.url),
): Promise<number> {
  if (!argvPath) fail(USAGE);
  const [selection, realModulePath] = await Promise.all([
    selectedDomain(argvPath, argv),
    realpath(modulePath),
  ]);
  return runDomain(
    selection.domain,
    selection.argv,
    selection.invokedAs,
    deploymentDirectory(realModulePath),
  );
}

const argvPath = process.argv[1];
if (argvPath) {
  Promise.all([realpath(argvPath), realpath(fileURLToPath(import.meta.url))]).then(
    ([realArgvPath, realModulePath]) => {
      if (realArgvPath !== realModulePath) return;
      return main(process.argv.slice(2), argvPath, realModulePath).then(
        (code) => {
          process.exitCode = code;
        },
        (error: unknown) => {
          console.error(error instanceof Error ? error.stack : String(error));
          process.exitCode = 2;
        },
      );
    },
    (error: unknown) => {
      console.error(error instanceof Error ? error.stack : String(error));
      process.exitCode = 2;
    },
  );
}
