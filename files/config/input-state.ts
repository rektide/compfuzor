/** Consumer input catalog, synchronization, and status observation. */

import { mkdir, readdir, stat } from "node:fs/promises";
import type { Dirent } from "node:fs";
import { basename, join, matchesGlob, normalize } from "node:path";

import {
  bindContextConfigs,
  type ConfigInput,
  type ConfigRecord,
  type ConfigSpec,
} from "./context.ts";
import { compareFileContents, inspectUsableFile } from "./file-state.ts";
import { syncFuzings } from "./fuzings.ts";
import { type StatusFormat, type StatusRow, type StatusSeverity } from "./report.ts";
import {
  inspectDeliveryEntry,
  linkResolvesToSameFile,
  pathsSharePhysicalDirectory,
  pathsSharePhysicalEntry,
  replaceWithCopy,
  replaceWithLink,
  type DeliveryEntry,
} from "../links/delivery.ts";

export type InputStrategy = "copy" | "link";

export type InputOperationOptions = {
  spec: ConfigSpec;
  contextName: string;
  runner: string;
  strategy?: InputStrategy;
  rebuild?: boolean;
  initiallyDisabled?: boolean;
  format?: StatusFormat;
};
type InputRelation = {
  id: string;
  config: string;
  inputIndex: number;
  inputName: string;
  source: string;
  destinationDirectory?: string;
  destination: string;
  logicalName: string;
  pattern?: string;
  suffix?: string;
  donorState: "enabled" | "disabled";
  donorConflict?: string;
  aliasHazard?: string;
};

type InputDirectory = {
  config: string;
  inputIndex: number;
  inputName: string;
  donorDirectory: string;
  destinationDirectory: string;
  pattern: string;
  suffix?: string;
  donorNames: Set<string>;
  aliasHazard?: string;
};

type InputCatalog = {
  relations: InputRelation[];
  directories: InputDirectory[];
  rows: StatusRow[];
};

function fail(message: string): never {
  throw new Error(message);
}

function object(value: unknown, label: string): Record<string, unknown> {
  if (!value || typeof value !== "object" || Array.isArray(value))
    fail(`${label} must be an object`);
  return value as Record<string, unknown>;
}

function filenameMatches(value: string, pattern: string): boolean {
  // Prefixing keeps leading-dot filenames compatible with find -name, whose
  // '*' and '?' do not apply shell pathname-expansion dotfile suppression.
  return matchesGlob(`x${value}`, `x${pattern}`);
}

function inputIdentity(input: ConfigInput, index: number): string {
  return typeof input.name === "string" && input.name ? input.name : String(index);
}

async function pathKind(
  path: string,
): Promise<"missing" | "file" | "symlink" | "directory" | "special"> {
  return (await inspectDeliveryEntry(path)).kind;
}

async function readDirectory(path: string): Promise<Dirent<string>[] | undefined> {
  try {
    return await readdir(path, { withFileTypes: true, encoding: "utf8" });
  } catch (error) {
    if ((error as NodeJS.ErrnoException).code === "ENOENT") return undefined;
    throw error;
  }
}

async function inputCatalog(
  spec: ConfigSpec,
  contextName: string,
  names: string[],
): Promise<InputCatalog> {
  const resolved = bindContextConfigs(spec, contextName, names);
  const relations: InputRelation[] = [];
  const directories: InputDirectory[] = [];
  const rows: StatusRow[] = [];

  for (const configName of names) {
    const donorConfig = object(spec.configs[configName], `config ${configName}`) as ConfigRecord;
    const localConfig = object(
      resolved.configs[configName],
      `resolved config ${configName}`,
    ) as ConfigRecord;
    for (let index = 0; index < donorConfig.inputs.length; index++) {
      const donor = donorConfig.inputs[index];
      const local = localConfig.inputs[index];
      const name = inputIdentity(donor, index);
      if (typeof donor.file === "string" && typeof local.file === "string") {
        const aliasHazard = (await pathsSharePhysicalEntry(donor.file, local.file))
          ? `consumer file aliases canonical input: ${local.file}`
          : undefined;
        relations.push({
          id: `${configName}/${name}`,
          config: configName,
          inputIndex: index,
          inputName: name,
          source: donor.file,
          destination: local.file,
          logicalName: basename(local.file),
          donorState: "enabled",
          aliasHazard,
        });
        continue;
      }
      if (
        typeof donor.directory !== "string" ||
        typeof donor.pattern !== "string" ||
        typeof local.directory !== "string"
      ) {
        fail(`config ${configName} input ${index} has an invalid compiled shape`);
      }
      const suffix = typeof donor.disabled_suffix === "string" ? donor.disabled_suffix : undefined;
      const directory: InputDirectory = {
        config: configName,
        inputIndex: index,
        inputName: name,
        donorDirectory: donor.directory,
        destinationDirectory: local.directory,
        pattern: donor.pattern,
        suffix,
        donorNames: new Set<string>(),
        aliasHazard: (await pathsSharePhysicalDirectory(donor.directory, local.directory))
          ? `consumer directory aliases canonical input directory: ${local.directory}`
          : undefined,
      };
      directories.push(directory);
      const entries = await readDirectory(donor.directory);
      if (entries === undefined) {
        rows.push({
          kind: "input",
          status: "donor-missing",
          severity: "error",
          config: configName,
          name,
          source: donor.directory,
          destination: local.directory,
          note: "donor input directory is missing",
        });
        continue;
      }
      const byLogical = new Map<string, InputRelation>();
      for (const entry of entries.sort((a, b) => a.name.localeCompare(b.name))) {
        const disabled = suffix !== undefined && entry.name.endsWith(suffix);
        const logicalName = disabled ? entry.name.slice(0, -suffix.length) : entry.name;
        if (!filenameMatches(logicalName, donor.pattern)) continue;
        const source = join(donor.directory, entry.name);
        const relation: InputRelation = {
          id: `${configName}/${name}/${logicalName}`,
          config: configName,
          inputIndex: index,
          inputName: name,
          source,
          destinationDirectory: local.directory,
          destination: join(local.directory, entry.name),
          logicalName,
          pattern: donor.pattern,
          suffix,
          donorState: disabled ? "disabled" : "enabled",
        };
        const previous = byLogical.get(logicalName);
        if (previous) {
          previous.donorConflict = source;
          continue;
        }
        byLogical.set(logicalName, relation);
        directory.donorNames.add(logicalName);
      }
      relations.push(...byLogical.values());
    }
  }
  return { relations, directories, rows };
}

async function localSelection(relation: InputRelation): Promise<{
  active: string;
  disabled?: string;
  activeEntry: DeliveryEntry;
  disabledEntry?: DeliveryEntry;
  selectedPath?: string;
  selectedState?: "enabled" | "disabled";
  selectedEntry?: DeliveryEntry;
  conflict: boolean;
}> {
  if (!relation.destinationDirectory || !relation.suffix) {
    const entry = await inspectDeliveryEntry(relation.destination);
    return {
      active: relation.destination,
      activeEntry: entry,
      selectedPath: entry.kind === "missing" ? undefined : relation.destination,
      selectedState: entry.kind === "missing" ? undefined : "enabled",
      selectedEntry: entry.kind === "missing" ? undefined : entry,
      conflict: false,
    };
  }
  const active = join(relation.destinationDirectory, relation.logicalName);
  const disabled = `${active}${relation.suffix}`;
  const [activeEntry, disabledEntry] = await Promise.all([
    inspectDeliveryEntry(active),
    inspectDeliveryEntry(disabled),
  ]);
  const hasActive = activeEntry.kind !== "missing";
  const hasDisabled = disabledEntry.kind !== "missing";
  return {
    active,
    disabled,
    activeEntry,
    disabledEntry,
    selectedPath: hasActive ? active : hasDisabled ? disabled : undefined,
    selectedState: hasActive ? "enabled" : hasDisabled ? "disabled" : undefined,
    selectedEntry: hasActive ? activeEntry : hasDisabled ? disabledEntry : undefined,
    conflict: hasActive && hasDisabled,
  };
}

async function deliver(
  source: string,
  destination: string,
  strategy: InputStrategy,
): Promise<void> {
  if (strategy === "link") await replaceWithLink(source, destination);
  else await replaceWithCopy(source, destination);
}

async function applyRelation(
  relation: InputRelation,
  strategy: InputStrategy,
  seed: boolean,
): Promise<string> {
  if (relation.aliasHazard) fail(`${relation.id}: ${relation.aliasHazard}`);
  if (relation.donorConflict) fail(`${relation.id}: donor has both enabled and disabled entries`);
  const sourceEntry = await inspectDeliveryEntry(relation.source);
  if (
    sourceEntry.kind === "missing" ||
    sourceEntry.kind === "directory" ||
    sourceEntry.kind === "special"
  ) {
    fail(`${relation.id}: donor source is ${sourceEntry.kind}: ${relation.source}`);
  }
  const local = await localSelection(relation);
  if (local.conflict) fail(`${relation.id}: both enabled and disabled local entries exist`);
  if (seed && local.selectedPath)
    return `preserved\t${relation.id}\t${local.selectedState}\t${local.selectedPath}`;
  const state = local.selectedState ?? relation.donorState;
  const destination =
    state === "disabled" && relation.suffix && relation.destinationDirectory
      ? join(relation.destinationDirectory, `${relation.logicalName}${relation.suffix}`)
      : relation.destinationDirectory
        ? join(relation.destinationDirectory, relation.logicalName)
        : relation.destination;
  await deliver(relation.source, destination, strategy);
  return `${seed ? "seeded" : "refreshed"}\t${relation.id}\t${state}\t${strategy}\t${destination}`;
}

export async function syncInputs(
  options: InputOperationOptions & { names: string[]; strategy: InputStrategy; seed: boolean },
): Promise<number> {
  const resolved = bindContextConfigs(options.spec, options.contextName, options.names);
  for (const config of Object.values(resolved.configs)) {
    for (const input of config.inputs)
      if (input.fuzings) await syncFuzings(input, options.strategy, options.seed);
  }
  // A canonical context has no donor-to-self delivery, but enrolled producer
  // material still has its own explicit delivery boundary.
  if (options.spec.contexts?.[options.contextName]?.canonical) return 0;
  const catalog = await inputCatalog(options.spec, options.contextName, options.names);
  let failed = catalog.rows.some((row) => row.severity === "error");
  for (const row of catalog.rows)
    console.error(`${row.status}: ${row.config}/${row.name}: ${row.note}`);
  const aliasHazards = [
    ...catalog.relations
      .filter((relation) => relation.aliasHazard)
      .map((relation) => `${relation.id}: ${relation.aliasHazard}`),
    ...catalog.directories
      .filter((directory) => directory.aliasHazard)
      .map((directory) => `${directory.config}/${directory.inputName}: ${directory.aliasHazard}`),
  ];
  if (aliasHazards.length > 0) {
    for (const hazard of aliasHazards) console.error(`error: ${hazard}`);
    return 2;
  }
  for (const directory of catalog.directories) {
    try {
      await mkdir(directory.destinationDirectory, { recursive: true });
    } catch (error) {
      failed = true;
      console.error(
        `error: cannot create input directory ${directory.destinationDirectory}: ${error instanceof Error ? error.message : String(error)}`,
      );
    }
  }
  for (const relation of catalog.relations) {
    try {
      console.log(await applyRelation(relation, options.strategy, options.seed));
    } catch (error) {
      failed = true;
      console.error(`error: ${error instanceof Error ? error.message : String(error)}`);
    }
  }
  return failed ? 2 : 0;
}

async function relationStatus(relation: InputRelation): Promise<StatusRow> {
  if (relation.aliasHazard) {
    return {
      kind: "input",
      status: "alias-hazard",
      severity: "error",
      config: relation.config,
      name: relation.logicalName,
      source: relation.source,
      destination: relation.destination,
      note: relation.aliasHazard,
    };
  }
  if (relation.donorConflict) {
    return {
      kind: "input",
      status: "donor-conflict",
      severity: "drift",
      config: relation.config,
      name: relation.logicalName,
      source: relation.source,
      destination: relation.destination,
      note: `also present as ${relation.donorConflict}`,
    };
  }
  const source = await inspectUsableFile(relation.source);
  const local = await localSelection(relation);
  if (local.conflict) {
    return {
      kind: "input",
      status: "local-conflict",
      severity: "drift",
      config: relation.config,
      name: relation.logicalName,
      source: relation.source,
      destination: local.active,
      note: `both ${local.active} and ${local.disabled} exist`,
    };
  }
  if (!local.selectedPath || !local.selectedEntry) {
    return {
      kind: "input",
      status: source.usable ? "missing" : "donor-missing",
      severity: source.usable ? "drift" : "error",
      config: relation.config,
      name: relation.logicalName,
      state: relation.donorState,
      source: relation.source,
      destination: relation.destination,
      note: source.note,
    };
  }
  const common = {
    kind: "input" as const,
    config: relation.config,
    name: relation.logicalName,
    state: local.selectedState,
    source: relation.source,
    destination: local.selectedPath,
  };
  if (!source.usable) {
    return {
      ...common,
      status: "donor-missing",
      severity: "error",
      representation: local.selectedEntry.kind,
      note: source.note,
    };
  }
  if (local.selectedEntry.kind === "symlink") {
    try {
      if (await linkResolvesToSameFile(local.selectedEntry, relation.source)) {
        return { ...common, status: "ok", severity: "ok", representation: "link" };
      }
    } catch (error) {
      return {
        ...common,
        status: "evaluation-error",
        severity: "error",
        representation: "link",
        note: `cannot resolve link referents: ${error instanceof Error ? error.message : String(error)}`,
      };
    }
  }
  if (local.selectedEntry.kind === "file") {
    const comparison = await compareFileContents(relation.source, local.selectedPath);
    if (comparison.error) {
      return {
        ...common,
        status: "evaluation-error",
        severity: "error",
        representation: "copy",
        note: comparison.error,
      };
    }
    if (comparison.equal)
      return { ...common, status: "ok", severity: "ok", representation: "copy" };
  }
  if (local.selectedEntry.kind === "directory" || local.selectedEntry.kind === "special") {
    return {
      ...common,
      status: "unsupported",
      severity: "drift",
      representation: local.selectedEntry.kind,
    };
  }
  return {
    ...common,
    status: "modified",
    severity: "drift",
    representation: local.selectedEntry.kind === "file" ? "copy" : "link",
    note:
      local.selectedEntry.kind === "symlink"
        ? `points to ${local.selectedEntry.target}`
        : "bytes differ from donor",
  };
}

async function extraInputRows(directory: InputDirectory): Promise<StatusRow[]> {
  const entries = await readDirectory(directory.destinationDirectory);
  if (entries === undefined) return [];
  const grouped = new Map<string, { active?: string; disabled?: string }>();
  for (const entry of entries) {
    const suffix = directory.suffix;
    const disabled = suffix !== undefined && entry.name.endsWith(suffix);
    const logical = disabled ? entry.name.slice(0, -suffix.length) : entry.name;
    if (!filenameMatches(logical, directory.pattern) || directory.donorNames.has(logical)) continue;
    const group = grouped.get(logical) ?? {};
    group[disabled ? "disabled" : "active"] = join(directory.destinationDirectory, entry.name);
    grouped.set(logical, group);
  }
  const rows: StatusRow[] = [];
  for (const [logical, group] of [...grouped].sort(([a], [b]) => a.localeCompare(b))) {
    if (group.active && group.disabled) {
      rows.push({
        kind: "input",
        status: "local-conflict",
        severity: "drift",
        config: directory.config,
        name: logical,
        source: directory.donorDirectory,
        destination: group.active,
        note: `both active and disabled local entries exist`,
      });
      continue;
    }
    const path = group.active ?? group.disabled!;
    const entry = await inspectDeliveryEntry(path);
    let status = "local";
    let severity: StatusSeverity =
      entry.kind === "directory" || entry.kind === "special" ? "drift" : "ok";
    let note = "not present in current donor catalog";
    if (entry.kind === "symlink") {
      const donorRelative = normalize(entry.targetPath).startsWith(
        `${normalize(directory.donorDirectory)}/`,
      );
      try {
        const referent = await stat(path);
        if (!referent.isFile()) {
          status = "non-file-referent";
          severity = "drift";
          note = `local link resolves to a non-file: ${entry.target}`;
        }
      } catch (error) {
        if ((error as NodeJS.ErrnoException).code === "ENOENT") {
          status = donorRelative ? "donor-missing" : "dangling";
          severity = "error";
          note = donorRelative
            ? `dangling link into donor directory: ${entry.target}`
            : `local link has a missing referent: ${entry.target}`;
        } else {
          status = "evaluation-error";
          severity = "error";
          note = `cannot inspect local link referent: ${error instanceof Error ? error.message : String(error)}`;
        }
      }
    }
    rows.push({
      kind: "input",
      status,
      severity,
      config: directory.config,
      name: logical,
      state: group.disabled ? "disabled" : "enabled",
      representation: entry.kind,
      destination: path,
      note,
    });
  }
  return rows;
}

export async function inputStatusRows(
  spec: ConfigSpec,
  contextName: string,
  names: string[],
): Promise<StatusRow[]> {
  const catalog = await inputCatalog(spec, contextName, names);
  const rows = [...catalog.rows];
  for (const relation of catalog.relations) rows.push(await relationStatus(relation));
  for (const directory of catalog.directories) {
    if (directory.aliasHazard) {
      rows.push({
        kind: "input",
        status: "alias-hazard",
        severity: "error",
        config: directory.config,
        name: directory.inputName,
        source: directory.donorDirectory,
        destination: directory.destinationDirectory,
        note: directory.aliasHazard,
      });
      continue;
    }
    if (
      directory.donorNames.size === 0 &&
      (await pathKind(directory.destinationDirectory)) === "missing"
    ) {
      rows.push({
        kind: "input",
        status: "missing",
        severity: "drift",
        config: directory.config,
        name: directory.inputName,
        source: directory.donorDirectory,
        destination: directory.destinationDirectory,
        note: "empty consumer input directory is missing",
      });
    }
    rows.push(...(await extraInputRows(directory)));
  }
  return rows;
}
