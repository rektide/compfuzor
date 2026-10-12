/** Manage external symlinks declared by config.spec.json remote targets. */

import { lstat, mkdir, readFile, readlink, realpath, rename, rm, symlink } from "node:fs/promises";
import { basename, dirname, join, resolve } from "node:path";
import { parseArgs } from "node:util";
import { runAssembly } from "../config/assembly.ts";
import type { ConfigSpec } from "../config/context.ts";

type Remote = {
  config: string;
  directory: string;
  pattern: string;
  disabled_suffix: string | null;
};
type LinkState = { path: string; target: string } | undefined;

async function linkState(path: string): Promise<LinkState> {
  try {
    const stat = await lstat(path);
    if (!stat.isSymbolicLink()) throw new Error(`managed destination is not a symlink: ${path}`);
    return { path, target: await readlink(path) };
  } catch (error) {
    if ((error as NodeJS.ErrnoException).code === "ENOENT") return undefined;
    throw error;
  }
}

function matches(pattern: string, value: string): boolean {
  const escaped = pattern.replace(/[.+^${}()|[\]\\]/g, "\\$&");
  return new RegExp(`^${escaped.replaceAll("*", ".*").replaceAll("?", ".")}$`).test(value);
}

function validateName(remote: Remote, target: string, name: string): void {
  if (!name || basename(name) !== name || name === "." || name === "..")
    throw new Error(`invalid remote filename: ${name}`);
  if (remote.disabled_suffix && name.endsWith(remote.disabled_suffix)) {
    throw new Error(
      `remote filename must not include disabled suffix ${remote.disabled_suffix}: ${name}`,
    );
  }
  if (!matches(remote.pattern, name))
    throw new Error(`${name} does not match ${target} pattern ${remote.pattern}`);
}

async function atomicLink(source: string, destination: string): Promise<void> {
  const temporary = join(
    dirname(destination),
    `.${basename(destination)}.tmp-${process.pid}-${Date.now()}`,
  );
  await symlink(source, temporary);
  await rename(temporary, destination).catch(async (error) => {
    await rm(temporary, { force: true });
    throw error;
  });
}

async function rebuild(config: string, spec: ConfigSpec, runner: string): Promise<void> {
  const code = await runAssembly({ spec, runner, contextName: "canonical", names: [config] });
  if (code !== 0) throw new Error(`config rebuild failed (exit ${code})`);
}

async function inspect(
  remote: Remote,
  target: string,
  name: string,
): Promise<{ active: LinkState; disabled: LinkState }> {
  validateName(remote, target, name);
  const activePath = join(remote.directory, name);
  const disabledPath = remote.disabled_suffix
    ? `${activePath}${remote.disabled_suffix}`
    : undefined;
  const [active, disabled] = await Promise.all([
    linkState(activePath),
    disabledPath ? linkState(disabledPath) : Promise.resolve(undefined),
  ]);
  if (active && disabled)
    throw new Error(`both active and disabled remote links exist: ${target}/${name}`);
  return { active, disabled };
}

async function putRemote(
  remote: Remote,
  target: string,
  name: string,
  source: string,
  spec: ConfigSpec,
  runner: string,
  pair: Awaited<ReturnType<typeof inspect>>,
): Promise<void> {
  const { active, disabled } = pair;
  const previous = active ?? disabled;
  const destination = previous?.path ?? join(remote.directory, name);
  await mkdir(remote.directory, { recursive: true });
  await atomicLink(source, destination);
  try {
    await rebuild(remote.config, spec, runner);
  } catch (error) {
    if (previous) await atomicLink(previous.target, destination);
    else await rm(destination, { force: true });
    throw error;
  }
  console.log(`put: ${target}/${name}${disabled ? " (disabled)" : ""} -> ${source}`);
}

type Target = { id: string; name: string; remote: Remote; spec: ConfigSpec; specPath: string };

async function targets(
  deploymentDir: string,
  specs?: string[],
  definitions?: string[],
): Promise<Target[]> {
  if (specs && definitions) throw new Error("--spec and --definition are mutually exclusive");
  let bindings: Array<{ id: string; path: string }>;
  if (specs) bindings = specs.map((path) => ({ id: resolve(path), path: resolve(path) }));
  else {
    let index: { definitions: Record<string, { spec: string }> };
    try {
      index = JSON.parse(await readFile(join(deploymentDir, "etc/config/instances.json"), "utf8"));
    } catch (error) {
      if ((error as NodeJS.ErrnoException).code !== "ENOENT") throw error;
      index = { definitions: { default: { spec: "etc/config.spec.json" } } };
    }
    bindings = (definitions ?? Object.keys(index.definitions).sort()).map((id) => {
      const binding = index.definitions[id];
      if (!binding) throw new Error(`unknown CONFIG definition: ${id}`);
      return { id, path: resolve(deploymentDir, binding.spec) };
    });
  }
  const result: Target[] = [];
  for (const binding of bindings) {
    const spec = JSON.parse(await readFile(binding.path, "utf8")) as ConfigSpec;
    for (const [name, remote] of Object.entries((spec.remotes ?? {}) as Record<string, Remote>))
      result.push({ id: `${binding.id}/${name}`, name, remote, spec, specPath: binding.path });
  }
  return result;
}

export async function main(argv: string[], deploymentDir: string): Promise<void> {
  const parsed = parseArgs({
    args: argv,
    allowPositionals: true,
    strict: true,
    options: {
      name: { type: "string", short: "n" },
      spec: { type: "string", multiple: true },
      definition: { type: "string", multiple: true },
      runner: { type: "string" },
      target: { type: "string", multiple: true },
    },
  });
  const [rawAction, target, value, positionalName] = parsed.positionals;
  const action = rawAction === "link" ? "put" : rawAction;
  const available = await targets(deploymentDir, parsed.values.spec, parsed.values.definition);
  const runner = resolve(parsed.values.runner ?? join(deploymentDir, "bin/config/run.sh"));

  if (action === "list") {
    if (target) throw new Error("usage: config-remote.mjs list");
    for (const entry of available) {
      const remote = entry.remote;
      console.log(
        `${entry.id}\tconfig=${remote.config}\tdestination=${join(remote.directory, remote.pattern)}\tdisabled=${remote.disabled_suffix ?? "-"}`,
      );
    }
    return;
  }
  if (action === "put-matching") {
    for (const selector of parsed.values.target ?? []) {
      if (!available.some((entry) => entry.id === selector || entry.name === selector))
        throw new Error(`unknown selected remote target: ${selector}`);
    }
    if (!target || positionalName)
      throw new Error(
        "usage: config-remote.mjs put-matching SOURCE [NAME] [--definition ID ...] [--target ID/INPUT ...]",
      );
    if (parsed.values.name && value) throw new Error("filename specified twice");
    const source = await realpath(target);
    if (!(await lstat(source)).isFile()) throw new Error(`remote source is not a file: ${source}`);
    const name = parsed.values.name ?? value ?? basename(source);
    const selected = available.filter(
      (entry) =>
        matches(entry.remote.pattern, name) &&
        (!parsed.values.target ||
          parsed.values.target.includes(entry.id) ||
          parsed.values.target.includes(entry.name)),
    );
    if (!selected.length)
      throw new Error(`no matching remote input for ${name} in selected CONFIG definitions`);
    // Resolve and admit EVERY match before the first mutation. Failures during
    // delivery/rebuild are per-target and do not cancel later compatible targets.
    const plans = [];
    for (const entry of selected)
      plans.push({ entry, pair: await inspect(entry.remote, entry.id, name) });
    const errors: Error[] = [];
    for (const { entry, pair } of plans) {
      try {
        await putRemote(entry.remote, entry.id, name, source, entry.spec, runner, pair);
      } catch (error) {
        console.error(
          `failed: ${entry.id}/${name}: ${error instanceof Error ? error.message : String(error)}`,
        );
        errors.push(new Error(`${entry.id}: delivery or rebuild failed`, { cause: error }));
      }
    }
    if (errors.length)
      throw new AggregateError(
        errors,
        `${errors.length}/${selected.length} matching targets failed; successful targets remain installed`,
      );
    return;
  }
  if (parsed.values.target) throw new Error("--target requires put-matching");
  const selected = available.filter((entry) => entry.id === target || entry.name === target);
  if (selected.length !== 1)
    throw new Error(
      selected.length
        ? `ambiguous remote target ${target}; use DEFINITION/INPUT or --spec`
        : `unknown remote target: ${target ?? ""}`,
    );
  const { remote, spec } = selected[0];

  if (action === "status") {
    if (!value) throw new Error("usage: config-remote.mjs status <target> <name>");
    const { active, disabled } = await inspect(remote, target, value);
    const state = active ? "enabled" : disabled ? "disabled" : "absent";
    console.log(
      `${target}/${value}\t${state}${active || disabled ? `\t${(active ?? disabled)!.target}` : ""}`,
    );
    return;
  }

  if (action === "put") {
    if (!value)
      throw new Error("usage: config-remote.mjs put <target> <source> [name] [--name name]");
    if (parsed.values.name && positionalName)
      throw new Error("filename may be supplied positionally or with --name, not both");
    const source = await realpath(value).catch((error) => {
      throw new Error(`remote source does not exist: ${value}`, { cause: error });
    });
    if (!(await lstat(source)).isFile()) throw new Error(`remote source is not a file: ${source}`);
    const name = parsed.values.name ?? positionalName ?? basename(source);
    await putRemote(
      remote,
      target,
      name,
      source,
      spec,
      runner,
      await inspect(remote, target, name),
    );
    return;
  }

  if (!["remove", "enable", "disable"].includes(action ?? "") || !value) {
    throw new Error("usage: config-remote.mjs <list|put|link|status|remove|enable|disable> ...");
  }
  const { active, disabled } = await inspect(remote, target, value);
  if (action === "remove") {
    const existing = active ?? disabled;
    if (!existing) return;
    const backup = join(
      remote.directory,
      `.${basename(existing.path)}.remove-${process.pid}-${Date.now()}`,
    );
    await rename(existing.path, backup);
    try {
      await rebuild(remote.config, spec, runner);
      await rm(backup);
    } catch (error) {
      await rename(backup, existing.path);
      throw error;
    }
  } else {
    if (!remote.disabled_suffix) throw new Error(`remote target cannot be toggled: ${target}`);
    const from = action === "disable" ? active : disabled;
    const already = action === "disable" ? disabled : active;
    if (already) return;
    if (!from) throw new Error(`remote link does not exist: ${target}/${value}`);
    const destination =
      action === "disable"
        ? `${from.path}${remote.disabled_suffix}`
        : from.path.slice(0, -remote.disabled_suffix.length);
    await rename(from.path, destination);
    try {
      await rebuild(remote.config, spec, runner);
    } catch (error) {
      await rename(destination, from.path);
      throw error;
    }
  }
  console.log(`${action}: ${target}/${value}`);
}
