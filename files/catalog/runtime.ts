/** Read-only inspection of attributed contributors, actions, resources, and flows. */

import { readFile, readdir } from "node:fs/promises";
import { basename, dirname, join, resolve } from "node:path";
import { parseArgs } from "node:util";

type JsonRecord = Record<string, unknown>;

export type RuntimeCatalog = {
  version: 1;
  deployment: JsonRecord;
  contributors: JsonRecord[];
  resources: JsonRecord[];
  commands: JsonRecord[];
  actions: JsonRecord[];
  flows: Record<string, { name: string; entries: string[] }>;
  execution: { authority: string; catalogOnly: boolean };
};

export type ScheduledInvocation = JsonRecord & {
  id: string;
  flow: string;
  effectiveIndex: number;
  effectivePhase: string;
  selectedPath: string;
  selectedLayer: "compiled" | "site";
  shadowedPath?: string;
};

type CatalogOptions = {
  catalogPath: string;
  json: boolean;
  positionals: string[];
};

const FLOW_PHASES: Record<string, Array<{ from: number; to: number; name: string }>> = {
  build: [
    { from: 1, to: 19, name: "prerequisites" },
    { from: 20, to: 39, name: "prepare" },
    { from: 40, to: 69, name: "compile" },
    { from: 70, to: 89, name: "package" },
    { from: 90, to: 99, name: "finalize" },
  ],
  install: [
    { from: 1, to: 19, name: "prerequisites" },
    { from: 20, to: 29, name: "identity" },
    { from: 30, to: 49, name: "materialize" },
    { from: 50, to: 69, name: "publish" },
    { from: 70, to: 89, name: "activate" },
    { from: 90, to: 99, name: "record" },
  ],
  status: [{ from: 1, to: 99, name: "inspect" }],
};

const USAGE = `Usage: compfuzor-catalog.sh [--catalog PATH | --deployment DIR] [--json] [COMMAND]

Inspect the compiled read-only runtime catalog. Commands:
  contributors
  actions
  commands
  resources
  flows
  flow NAME`;

function fail(message: string): never {
  throw new Error(message);
}

function object(value: unknown, label: string): JsonRecord {
  if (typeof value !== "object" || value === null || Array.isArray(value))
    fail(`${label} must be an object`);
  return value as JsonRecord;
}

function strings(value: unknown, label = "value"): string[] {
  if (value === undefined) return [];
  if (!Array.isArray(value) || value.some((item) => typeof item !== "string")) {
    fail(`${label} must be an array of strings`);
  }
  return value as string[];
}

function phaseFor(flow: string, index: number): string {
  const phase = FLOW_PHASES[flow]?.find(
    (candidate) => index >= candidate.from && index <= candidate.to,
  );
  return phase?.name ?? "unknown";
}

function parseCatalog(value: unknown): RuntimeCatalog {
  const record = object(value, "runtime catalog");
  if (record.version !== 1) fail(`unsupported runtime catalog version: ${String(record.version)}`);
  const flows = object(record.flows, "runtime catalog flows");
  return {
    version: 1,
    deployment: object(record.deployment, "runtime catalog deployment"),
    contributors: Array.isArray(record.contributors)
      ? record.contributors.map((item, index) => object(item, `contributor ${index}`))
      : fail("runtime catalog contributors must be an array"),
    resources: Array.isArray(record.resources)
      ? record.resources.map((item, index) => object(item, `resource ${index}`))
      : fail("runtime catalog resources must be an array"),
    commands: Array.isArray(record.commands)
      ? record.commands.map((item, index) => object(item, `command ${index}`))
      : fail("runtime catalog commands must be an array"),
    actions: Array.isArray(record.actions)
      ? record.actions.map((item, index) => object(item, `action ${index}`))
      : fail("runtime catalog actions must be an array"),
    flows: Object.fromEntries(
      Object.entries(flows).map(([name, item]) => {
        const descriptor = object(item, `flow ${name}`);
        return [name, { name, entries: strings(descriptor.entries, `flow ${name} entries`) }];
      }),
    ),
    execution: object(record.execution, "runtime catalog execution") as RuntimeCatalog["execution"],
  };
}

function parseOptions(argv: string[], deploymentDir: string): CatalogOptions {
  const { values, positionals } = parseArgs({
    args: argv,
    strict: true,
    allowPositionals: true,
    options: {
      catalog: { type: "string" },
      deployment: { type: "string" },
      json: { type: "boolean" },
      help: { type: "boolean", short: "h" },
    },
  });
  if (values.help) {
    console.log(USAGE);
    process.exit(0);
  }
  if (values.catalog && values.deployment)
    fail("--catalog and --deployment are mutually exclusive");
  const root = resolve(values.deployment ?? deploymentDir);
  return {
    catalogPath: resolve(values.catalog ?? join(root, "etc", "compfuzor-runtime", "catalog.json")),
    json: values.json ?? false,
    positionals,
  };
}

function placement(path: string, expectedFlow: string): { index: number; flow: string } {
  const match = /^(\d{2})-(build|install|status)-.+\.json$/.exec(basename(path));
  if (!match) fail(`invalid indexed flow filename: ${path}`);
  const index = Number(match[1]);
  if (index < 1 || index > 99) fail(`flow index must be 01-99: ${path}`);
  if (match[2] !== expectedFlow)
    fail(`flow filename ${path} does not match descriptor flow ${expectedFlow}`);
  return { index, flow: match[2] };
}

function canonical(value: unknown): unknown {
  if (Array.isArray(value)) return value.map(canonical);
  if (typeof value !== "object" || value === null) return value;
  const record = value as JsonRecord;
  return Object.fromEntries(
    Object.keys(record)
      .sort()
      .map((key) => [key, canonical(record[key])]),
  );
}

function semanticDescriptor(record: JsonRecord): string {
  const copy = { ...record };
  delete copy.index;
  delete copy.effectiveIndex;
  delete copy.effectivePhase;
  delete copy.selectedPath;
  delete copy.selectedLayer;
  delete copy.shadowedPath;
  return JSON.stringify(canonical(copy));
}

async function readLayer(
  directory: string,
  layer: "compiled" | "site",
): Promise<Array<{ path: string; record: JsonRecord; layer: "compiled" | "site" }>> {
  let names: string[];
  try {
    names = await readdir(directory);
  } catch (error) {
    if ((error as NodeJS.ErrnoException).code === "ENOENT") return [];
    throw error;
  }
  const selected = names.filter((name) => name.endsWith(".json")).sort();
  return await Promise.all(
    selected.map(async (name) => {
      const path = join(directory, name);
      return {
        path,
        record: object(JSON.parse(await readFile(path, "utf8")), `flow descriptor ${path}`),
        layer,
      };
    }),
  );
}

export async function loadFlow(
  catalogPath: string,
  flow: string,
  suppliedCatalog?: RuntimeCatalog,
): Promise<ScheduledInvocation[]> {
  if (!(flow in FLOW_PHASES)) fail(`unknown flow: ${flow}`);
  const catalog = suppliedCatalog ?? parseCatalog(JSON.parse(await readFile(catalogPath, "utf8")));
  const declaredById = new Map<string, string>();
  for (const [declaredFlow, descriptor] of Object.entries(catalog.flows)) {
    for (const id of descriptor.entries) {
      const previous = declaredById.get(id);
      if (previous)
        fail(`flow contribution id ${id} is declared by both ${previous} and ${declaredFlow}`);
      declaredById.set(id, declaredFlow);
    }
  }
  const declaredDescriptor = catalog.flows[flow];
  if (!declaredDescriptor) fail(`catalog does not declare flow: ${flow}`);
  const declared = new Set(declaredDescriptor.entries);
  const root = join(dirname(catalogPath), "workflows");
  const [compiled, site] = await Promise.all([
    readLayer(join(root, "compiled"), "compiled"),
    readLayer(join(root, "site"), "site"),
  ]);
  const selected = new Map<string, ScheduledInvocation>();
  for (const item of compiled) {
    const id = item.record.id;
    if (typeof id !== "string" || !id) fail(`flow descriptor ${item.path} requires an id`);
    if (!declared.has(id)) continue;
    if (item.record.version !== 1)
      fail(`flow descriptor ${item.path} has unsupported version ${String(item.record.version)}`);
    if (item.record.flow !== flow)
      fail(
        `flow descriptor ${item.path} is indexed under ${flow} but declares ${String(item.record.flow)}`,
      );
    object(item.record.invoke, `flow descriptor ${item.path} invocation`);
    strings(item.record.contributors, `flow descriptor ${item.path} contributors`);
    if (selected.has(id)) fail(`duplicate compiled flow contribution id ${id}`);
    const effective = placement(item.path, flow);
    selected.set(id, {
      ...item.record,
      id,
      flow,
      effectiveIndex: effective.index,
      effectivePhase: phaseFor(flow, effective.index),
      selectedPath: item.path,
      selectedLayer: "compiled",
    });
  }
  for (const id of declared) {
    if (!selected.has(id))
      fail(`catalog flow ${flow} references missing compiled contribution ${id}`);
  }
  const siteIds = new Set<string>();
  for (const item of site) {
    const id = item.record.id;
    if (typeof id !== "string" || !id) fail(`site flow descriptor ${item.path} requires an id`);
    if (siteIds.has(id)) fail(`duplicate site flow contribution id ${id}`);
    siteIds.add(id);
    const declaredFlow = declaredById.get(id);
    if (!declaredFlow)
      fail(`site flow descriptor ${item.path} names undeclared contribution ${id}`);
    if (declaredFlow !== flow) continue;
    const previous = selected.get(id);
    if (item.record.state === "absent") {
      if (!previous) fail(`site tombstone ${item.path} names unknown compiled contribution ${id}`);
      if (Object.keys(item.record).some((key) => key !== "id" && key !== "state"))
        fail(`site tombstone ${item.path} may contain only id and state`);
      selected.delete(id);
      continue;
    }
    if (item.record.version !== 1)
      fail(
        `site flow descriptor ${item.path} has unsupported version ${String(item.record.version)}`,
      );
    if (item.record.flow !== flow)
      fail(
        `site flow descriptor ${item.path} is indexed under ${flow} but declares ${String(item.record.flow)}`,
      );
    object(item.record.invoke, `site flow descriptor ${item.path} invocation`);
    strings(item.record.contributors, `site flow descriptor ${item.path} contributors`);
    const effective = placement(item.path, flow);
    if (previous && semanticDescriptor(previous) !== semanticDescriptor(item.record)) {
      fail(
        `site flow contribution ${id} may change placement only; use a new id for changed behavior`,
      );
    }
    selected.set(id, {
      ...item.record,
      id,
      flow,
      effectiveIndex: effective.index,
      effectivePhase: phaseFor(flow, effective.index),
      selectedPath: item.path,
      selectedLayer: "site",
      ...(previous ? { shadowedPath: previous.selectedPath } : {}),
    });
  }
  return [...selected.values()].sort((left, right) =>
    basename(left.selectedPath).localeCompare(basename(right.selectedPath)),
  );
}

function printRows(rows: string[][]): void {
  for (const row of rows) console.log(row.map((cell) => cell || "-").join("\t"));
}

function cell(value: unknown): string {
  if (value === undefined || value === null) return "";
  if (typeof value === "string") return value;
  if (typeof value === "number" || typeof value === "boolean" || typeof value === "bigint") {
    return String(value);
  }
  return JSON.stringify(value);
}

async function runCatalog(options: CatalogOptions): Promise<number> {
  const catalog = parseCatalog(JSON.parse(await readFile(options.catalogPath, "utf8")));
  const [command, argument, ...extra] = options.positionals;
  if (extra.length > 0) fail(USAGE);
  if (!command) {
    const summary = {
      deployment: catalog.deployment,
      authority: catalog.execution.authority,
      contributors: catalog.contributors.length,
      actions: catalog.actions.length,
      commands: catalog.commands.length,
      resources: catalog.resources.length,
      flows: Object.keys(catalog.flows),
    };
    if (options.json) console.log(JSON.stringify(summary));
    else
      printRows(
        Object.entries(summary).map(([key, value]) => [
          key,
          typeof value === "object" ? JSON.stringify(value) : String(value),
        ]),
      );
    return 0;
  }
  if (command === "flow") {
    if (!argument) fail("catalog flow requires a flow name");
    const entries = await loadFlow(options.catalogPath, argument, catalog);
    if (options.json) console.log(JSON.stringify(entries));
    else
      printRows(
        entries.map((entry) => [
          String(entry.effectiveIndex).padStart(2, "0"),
          entry.effectivePhase,
          entry.id,
          cell(object(entry.invoke, `flow invocation ${entry.id}`).action),
          entry.selectedLayer,
          strings(entry.contributors, `flow invocation ${entry.id} contributors`).join(","),
        ]),
      );
    return 0;
  }
  if (argument) fail(`${command} does not accept an argument`);
  if (command === "flows") {
    const rows = await Promise.all(
      Object.keys(catalog.flows).map(async (name) => [
        name,
        String((await loadFlow(options.catalogPath, name, catalog)).length),
      ]),
    );
    if (options.json) console.log(JSON.stringify(Object.fromEntries(rows)));
    else printRows(rows);
    return 0;
  }
  const collections: Record<string, JsonRecord[]> = {
    contributors: catalog.contributors,
    actions: catalog.actions,
    commands: catalog.commands,
    resources: catalog.resources,
  };
  const values = collections[command];
  if (!values) fail(USAGE);
  if (options.json) console.log(JSON.stringify(values));
  else
    printRows(
      values.map((value) => [
        cell(value.id ?? value.name),
        cell(value.action ?? value.contract ?? value.kind),
        strings(value.contributors, "catalog contributors").join(","),
      ]),
    );
  return 0;
}

export async function main(argv: string[], deploymentDir: string): Promise<number> {
  return runCatalog(parseOptions(argv, deploymentDir));
}
