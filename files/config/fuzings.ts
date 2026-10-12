/** Native contribution-root resolution and derived input delivery (no registry). */

import {
  lstat,
  mkdir,
  readFile,
  readdir,
  readlink,
  realpath,
  rename,
  stat,
  symlink,
} from "node:fs/promises";
import { basename, dirname, join, matchesGlob, resolve } from "node:path";
import type { ConfigInput, ConfigSpec } from "./context.ts";
import { inspectDeliveryEntry, replaceWithCopy, replaceWithLink } from "../links/delivery.ts";

type Rules = { roots: string; paths: string[] };
export type FuzingRelation = {
  member: string;
  relative: string;
  source: string;
  destination: string;
  disabled?: string;
  sourceDisabled: boolean;
};

async function entries(path: string): Promise<string[]> {
  try {
    return (await readdir(path)).sort();
  } catch (error) {
    if ((error as NodeJS.ErrnoException).code === "ENOENT") return [];
    throw error;
  }
}

function rules(input: ConfigInput): Rules {
  const value = input.fuzings as Rules | undefined;
  if (!value || typeof value.roots !== "string" || !Array.isArray(value.paths))
    throw new Error("input has no compiled fuzing contract");
  return value;
}

/** Sorted member order, authored rule order, then native filename order. */
export async function resolveFuzings(input: ConfigInput): Promise<FuzingRelation[]> {
  const selection = rules(input);
  const suffix = typeof input.disabled_suffix === "string" ? input.disabled_suffix : undefined;
  const result: FuzingRelation[] = [];
  const members = await entries(selection.roots);
  const seen = new Set<string>();
  for (const member of members) {
    if (member.endsWith(".disabled")) continue;
    if (!/^[A-Za-z0-9][A-Za-z0-9_.-]*$/.test(member))
      throw new Error(`invalid enrolled fuzing name: ${member}`);
    if (members.includes(`${member}.disabled`))
      throw new Error(`fuzing is both enabled and disabled: ${member}`);
    const enrollment = join(selection.roots, member);
    if (!(await lstat(enrollment)).isSymbolicLink())
      throw new Error(`fuzing enrollment is not a root symlink: ${enrollment}`);
    if (!(await stat(enrollment)).isDirectory())
      throw new Error(`enrolled fuzing root is not a directory: ${enrollment}`);
    const sourceRoot = await realpath(enrollment);
    for (const pattern of selection.paths) {
      const directory = dirname(pattern);
      const names = await entries(join(enrollment, directory));
      for (const filename of names) {
        const sourceDisabled = !!suffix && filename.endsWith(suffix);
        const logical = sourceDisabled ? filename.slice(0, -suffix!.length) : filename;
        if (!matchesGlob(`x${logical}`, `x${basename(pattern)}`)) continue;
        if (/[\t\r\n]/.test(logical))
          throw new Error(`unsupported control characters in fuzing filename`);
        const relative = join(directory, logical);
        const identity = `${member}/${relative}`;
        if (seen.has(identity))
          throw new Error(`duplicate/active-disabled fuzing contribution: ${identity}`);
        seen.add(identity);
        const source = join(sourceRoot, directory, filename);
        if (!(await stat(source)).isFile())
          throw new Error(`recognized fuzing input is not a file: ${source}`);
        const destination = join(String(input.directory), ".fuzings", member, relative);
        result.push({
          member,
          relative,
          source,
          destination,
          disabled: suffix ? `${destination}${suffix}` : undefined,
          sourceDisabled,
        });
      }
    }
  }
  return result;
}

export async function installedFuzing(
  relation: FuzingRelation,
): Promise<{ path?: string; disabled: boolean }> {
  const active = await inspectDeliveryEntry(relation.destination);
  const disabled = relation.disabled ? await inspectDeliveryEntry(relation.disabled) : undefined;
  if (active.kind !== "missing" && disabled && disabled.kind !== "missing")
    throw new Error(`both active and disabled fuzing inputs exist: ${relation.destination}`);
  if (active.kind !== "missing")
    return { path: relation.destination, disabled: relation.sourceDisabled };
  if (disabled && disabled.kind !== "missing") return { path: relation.disabled, disabled: true };
  return { disabled: relation.sourceDisabled };
}

/** Explicit refresh; assembly never enters here, and retained stale files are not pruned. */
export async function syncFuzings(
  input: ConfigInput,
  strategy: "copy" | "link",
  seed: boolean,
): Promise<void> {
  const relations = await resolveFuzings(input);
  for (const relation of relations) {
    const installed = await installedFuzing(relation);
    const destination =
      installed.path ?? (relation.sourceDisabled ? relation.disabled! : relation.destination);
    const entry = await inspectDeliveryEntry(destination);
    if (entry.kind === "directory" || entry.kind === "special")
      throw new Error(`foreign fuzing input slot: ${destination}`);
    if (
      entry.kind === "symlink" &&
      resolve(dirname(destination), await readlink(destination)) !== resolve(relation.source)
    )
      throw new Error(`foreign fuzing input link: ${destination}`);
    if (seed && installed.path) continue;
    await mkdir(dirname(destination), { recursive: true });
    if (strategy === "link") await replaceWithLink(relation.source, destination);
    else await replaceWithCopy(relation.source, destination);
    console.log(`fuzing\t${relation.member}/${relation.relative}\t${strategy}\t${destination}`);
  }
}

/** Explicit root membership, kept in native symlink/disabled controls. */
export async function mutateFuzing(
  input: ConfigInput,
  action: string,
  member: string,
  source?: string,
): Promise<void> {
  if (!/^[A-Za-z0-9][A-Za-z0-9_.-]*$/.test(member) || member.endsWith(".disabled"))
    throw new Error(`invalid fuzing member: ${member}`);
  const selection = rules(input);
  const active = join(selection.roots, member);
  const disabled = `${active}.disabled`;
  const [a, d] = await Promise.all([inspectDeliveryEntry(active), inspectDeliveryEntry(disabled)]);
  if (a.kind !== "missing" && d.kind !== "missing")
    throw new Error(`both active and disabled fuzings exist: ${member}`);
  if (action === "put") {
    if (!source) throw new Error("fuze put requires a contribution root");
    const root = await realpath(source);
    if (/[\t\r\n]/.test(root)) throw new Error("fuzing root has unsupported control characters");
    if (!(await stat(root)).isDirectory())
      throw new Error(`fuzing root is not a directory: ${root}`);
    const existing = a.kind !== "missing" ? a : d;
    if (existing.kind !== "missing") {
      if (
        existing.kind !== "symlink" ||
        (await realpath(a.kind !== "missing" ? active : disabled)) !== root
      )
        throw new Error(`foreign enrollment slot: ${member}; remove/rebind deliberately`);
      return;
    }
    await mkdir(selection.roots, { recursive: true });
    await symlink(root, active);
  } else if (action === "enable" || action === "disable") {
    const from = action === "enable" ? disabled : active;
    const to = action === "enable" ? active : disabled;
    const fromEntry = action === "enable" ? d : a;
    const toEntry = action === "enable" ? a : d;
    if (toEntry.kind !== "missing") return;
    if (fromEntry.kind !== "symlink") throw new Error(`missing/foreign fuzing membership: ${from}`);
    await rename(from, to);
  } else throw new Error("fuze action must be put, enable, or disable");
}

/** Raw candidate worker uses exactly the same relation/selection resolver. */
export async function main(argv: string[]): Promise<number> {
  const [action, path, name, index] = argv;
  if (action !== "manifest" || !path || !name || index === undefined)
    throw new Error("config-fuzings manifest SPEC RECIPE INDEX");
  const spec = JSON.parse(await readFile(path, "utf8")) as ConfigSpec;
  const input = spec.configs[name].inputs[Number(index)];
  for (const relation of await resolveFuzings(input)) {
    const installed = await installedFuzing(relation);
    if (installed.disabled) continue;
    if (!installed.path)
      throw new Error(
        `fuzing input not delivered: ${relation.member}/${relation.relative}; run config-sync-inputs.sh before assembly`,
      );
    if (!(await stat(installed.path)).isFile())
      throw new Error(`installed fuzing input is not a file: ${installed.path}`);
    const settings = {
      ...(input.block as object),
      place: input.place ?? null,
      envsubst: input.envsubst ?? null,
    };
    console.log(
      `glob\tfuzing/${relation.member}/${relation.relative}\t${installed.path}\t${JSON.stringify(settings)}`,
    );
  }
  return 0;
}
