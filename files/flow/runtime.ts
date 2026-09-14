/** Sequential execution of validated, lexically ordered catalog flows. */

import { spawn } from "node:child_process";
import { realpath } from "node:fs/promises";
import { join, relative, resolve, sep } from "node:path";
import { parseArgs } from "node:util";

import { loadCatalog, loadFlow, type ScheduledInvocation } from "../catalog/runtime.ts";

type FlowOptions = {
  catalogPath: string;
  deploymentDir: string;
  dryRun: boolean;
  flow: string;
};

const USAGE = `Usage: compfuzor-flow.sh [--catalog PATH | --deployment DIR] [--dry-run] FLOW

Execute one catalog-authorized build, install, or status flow in lexical order.`;

function fail(message: string): never {
  throw new Error(message);
}

function object(value: unknown, label: string): Record<string, unknown> {
  if (typeof value !== "object" || value === null || Array.isArray(value)) {
    fail(`${label} must be an object`);
  }
  return value as Record<string, unknown>;
}

function stringArray(value: unknown, label: string): string[] {
  if (value === undefined) return [];
  if (!Array.isArray(value) || value.some((item) => typeof item !== "string")) {
    fail(`${label} must be an array of strings`);
  }
  return value as string[];
}

function parseOptions(argv: string[], defaultDeployment: string): FlowOptions {
  const { values, positionals } = parseArgs({
    args: argv,
    strict: true,
    allowPositionals: true,
    options: {
      catalog: { type: "string" },
      deployment: { type: "string" },
      "dry-run": { type: "boolean" },
      help: { type: "boolean", short: "h" },
    },
  });
  if (values.help) {
    console.log(USAGE);
    process.exit(0);
  }
  if (values.catalog && values.deployment)
    fail("--catalog and --deployment are mutually exclusive");
  if (positionals.length !== 1 || !["build", "install", "status"].includes(positionals[0])) {
    fail(USAGE);
  }
  const deploymentDir = resolve(values.deployment ?? defaultDeployment);
  return {
    catalogPath: resolve(
      values.catalog ?? join(deploymentDir, "etc", "compfuzor-runtime", "catalog.json"),
    ),
    deploymentDir,
    dryRun: values["dry-run"] ?? false,
    flow: positionals[0],
  };
}

async function executablePath(
  deploymentDir: string,
  configured: unknown,
  id: string,
): Promise<string> {
  if (typeof configured !== "string" || !configured) {
    fail(`flow invocation ${id} requires an executable path`);
  }
  const lexicalPath = resolve(deploymentDir, configured);
  const [root, physicalPath] = await Promise.all([realpath(deploymentDir), realpath(lexicalPath)]);
  const remainder = relative(root, physicalPath);
  if (remainder === ".." || remainder.startsWith(`..${sep}`)) {
    fail(`flow invocation ${id} executable escapes deployment: ${configured}`);
  }
  return lexicalPath;
}

async function runExecutable(path: string, args: string[], deploymentDir: string): Promise<number> {
  return await new Promise<number>((complete, reject) => {
    const child = spawn(path, args, {
      detached: true,
      env: { ...process.env, DIR: deploymentDir },
      stdio: "inherit",
    });
    const signals = ["SIGINT", "SIGTERM"] as const;
    const listeners = new Map<NodeJS.Signals, () => void>();
    let interrupted = false;
    const cleanup = (): void => {
      for (const [signal, listener] of listeners) process.off(signal, listener);
    };
    for (const signal of signals) {
      const listener = (): void => {
        interrupted = true;
        if (child.pid === undefined) return;
        try {
          process.kill(-child.pid, signal);
        } catch (error) {
          if ((error as NodeJS.ErrnoException).code !== "ESRCH") reject(error);
        }
      };
      listeners.set(signal, listener);
      process.on(signal, listener);
    }
    child.once("error", (error) => {
      cleanup();
      reject(error);
    });
    child.once("exit", (code, signal) => {
      cleanup();
      complete(interrupted || signal ? 1 : (code ?? 1));
    });
  });
}

async function runInvocation(
  entry: ScheduledInvocation,
  deploymentDir: string,
  dryRun: boolean,
): Promise<number> {
  const invoke = object(entry.invoke, `flow invocation ${entry.id}`);
  const handler = object(invoke.handler, `flow invocation ${entry.id} handler`);
  if (handler.kind !== "exec") {
    fail(`flow invocation ${entry.id} has unsupported handler kind ${String(handler.kind)}`);
  }
  const path = await executablePath(deploymentDir, handler.path, entry.id);
  const args = stringArray(invoke.args, `flow invocation ${entry.id} args`);
  console.error(
    `${dryRun ? "would run" : "running"} ${entry.effectiveIndex.toString().padStart(2, "0")} ${entry.id}: ${path}${args.length ? ` ${args.join(" ")}` : ""}`,
  );
  return dryRun ? 0 : await runExecutable(path, args, deploymentDir);
}

async function executeFlow(options: FlowOptions): Promise<number> {
  const catalog = await loadCatalog(options.catalogPath);
  if (catalog.execution.catalogOnly || catalog.execution.authority !== "catalog") {
    const deploymentId =
      typeof catalog.deployment.id === "string" ? catalog.deployment.id : "deployment";
    fail(`catalog flow execution is disabled for ${deploymentId}`);
  }
  const entries = await loadFlow(options.catalogPath, options.flow, catalog);
  let attention = false;
  for (const entry of entries) {
    const code = await runInvocation(entry, options.deploymentDir, options.dryRun);
    if (options.dryRun || code === 0) continue;
    const handler = object(
      object(entry.invoke, `flow invocation ${entry.id}`).handler,
      `flow invocation ${entry.id} handler`,
    );
    if (options.flow === "status" && handler.protocol === "legacy-status-v1") {
      if (code === 2 && handler.exit2 !== "error") continue;
      attention = true;
      continue;
    }
    return code === 2 ? 2 : 1;
  }
  return attention ? 1 : 0;
}

export async function main(argv: string[], deploymentDir: string): Promise<number> {
  return executeFlow(parseOptions(argv, deploymentDir));
}
