import { join } from "node:path";

import {
  parseLinksArgs,
  resolveSudoMode,
  type LinksCliOptions as Options,
  type LinksScope as Scope,
} from "./cli.ts";

import {
  loadManifest,
  resolveRecords,
  type LinkRow as Row,
  type LinkStatus as Status,
  type ResolvedRecord,
} from "./manifest.ts";
import { applyRecord, classifyRecord, removeRecord, sourceState } from "./operations.ts";

function fail(message: string): never {
  throw new Error(message);
}

async function audit(paths: string[], scope?: Scope, idPatterns?: string[]): Promise<Row[]> {
  const records: ResolvedRecord[] = [];
  const invalid: Row[] = [];
  for (const input of paths) {
    const loaded = await loadManifest(input);
    const resolved = resolveRecords(loaded.path, loaded.manifest, scope, idPatterns);
    records.push(...resolved.records.filter((record) => record.state === "present"));
    invalid.push(...resolved.invalid);
  }
  const groups = new Map<string, ResolvedRecord[]>();
  for (const record of records) {
    const key = `${record.scope}\0${record.destPath}`;
    groups.set(key, [...(groups.get(key) ?? []), record]);
  }
  return invalid.concat(
    records.map((record) => {
      const group = groups.get(`${record.scope}\0${record.destPath}`) ?? [];
      const conflict = group.some(
        (other) =>
          other.srcPath !== record.srcPath ||
          other.policy !== record.policy ||
          other.compose !== record.compose ||
          other.strategies.default !== record.strategies.default ||
          other.strategies.available.join("\0") !== record.strategies.available.join("\0"),
      );
      return {
        id: record.id,
        scope: record.scope,
        status: conflict ? "CONFLICT" : "MANAGED",
        src: record.srcPath,
        dest: record.destPath,
        manifest: record.manifest,
        detail: conflict
          ? `${group.length} incompatible claims`
          : `${group.length} compatible claim${group.length === 1 ? "" : "s"}`,
      };
    }),
  );
}

/** Plain words for the human table; machine statuses stay unchanged. */
const HUMAN_STATUS: Record<Status, string> = {
  MANAGED: "ok",
  OVERRIDE: "override",
  MISSING: "missing",
  CONFLICT: "conflict",
  SOURCE_MISSING: "no-source",
  SOURCE_UNUSABLE: "bad-source",
  INVALID: "invalid",
};

/** Verdict column: mutating verbs (created/replaced/removed) read better
 * than ok+action, so the verb replaces the status word for those rows. */
function humanLineLabel(row: Row): string {
  return row.action ?? HUMAN_STATUS[row.status] ?? row.status;
}

/** src column: the plan's src (what the link should point at). */
function srcCell(row: Row): string {
  return row.src ?? "";
}

function output(rows: Row[], options: Options): void {
  if (options.quiet >= 2) return;
  const sourceError = rows.some(
    (row) =>
      row.status === "SOURCE_MISSING" ||
      row.status === "SOURCE_UNUSABLE" ||
      row.status === "INVALID",
  );
  const drift = rows.some((row) => row.status === "MISSING" || row.status === "CONFLICT");
  if (options.quiet === 1) {
    console.log(sourceError ? "ERROR" : drift ? "DRIFT" : "OK");
  } else if (options.format === "jsonl") {
    for (const row of rows) console.log(JSON.stringify(row));
  } else if (options.format === "array") {
    console.log(JSON.stringify(rows, null, 2));
  } else {
    // apply/remove: only changed or problem rows are worth reporting; a
    // satisfied manifest prints nothing at all (the bin wrapper's "complete"
    // is the feedback). status/audit keep the full table.
    const visible =
      options.command === "apply" || options.command === "remove"
        ? rows.filter((row) => row.action !== "unchanged")
        : rows;
    if (visible.length === 0) return;
    console.log("status\tdest\tsrc\tactual\tnote");
    for (const row of visible) {
      const note = row.detail ? `(${row.detail})` : "";
      const actual =
        row.entry === "symlink" && row.target !== undefined
          ? row.target
          : row.entry === "file" || row.entry === "directory" || row.entry === "special"
            ? `(${row.entry})`
            : "";
      console.log(
        [humanLineLabel(row), row.dest, srcCell(row), actual, note]
          .map((cell) => (cell === "" ? '""' : cell))
          .join("\t"),
      );
    }
  }
}

export async function main(argv: string[], deploymentDir: string): Promise<number> {
  const options = parseLinksArgs(argv, join(process.env.DIR ?? deploymentDir, "links.json"));
  const sudoMode = resolveSudoMode(options.sudo);
  if (
    ["1", "true", "y", "yes"].includes(
      process.env.COMPFUZOR_LINK_BYPASS?.trim().toLowerCase() ?? "",
    )
  )
    return 0;
  let rows: Row[];
  if (options.command === "audit") {
    rows = await audit(options.paths, options.scope, options.id);
  } else {
    const loaded = await loadManifest(options.paths[0]);
    const resolved = resolveRecords(
      loaded.path,
      loaded.manifest,
      options.scope,
      options.id,
      options.composed,
    );
    if (
      (options.command === "apply" || options.command === "remove") &&
      sudoMode === "always" &&
      resolved.records.some((record) => record.scope === "user")
    ) {
      fail("--sudo always is not permitted for user-scope link mutations");
    }
    if (options.command === "apply" && options.strategy) {
      const unavailable = resolved.records.filter(
        (record) =>
          record.state === "present" && !record.strategies.available.includes(options.strategy!),
      );
      if (unavailable.length > 0)
        fail(
          `strategy ${options.strategy} is unavailable for: ${unavailable.map((record) => record.id).join(", ")}`,
        );
      if (options.strategy === "copy") {
        const sourceStates = await Promise.all(
          resolved.records.map(async (record) => ({
            record,
            source: await sourceState(record.srcPath),
          })),
        );
        const unusable = sourceStates.filter(
          ({ record, source }) =>
            record.state === "present" && source.entryExists && !source.regular,
        );
        if (unusable.length > 0) {
          fail(
            `strategy copy requires a source that resolves to a regular file: ${unusable.map(({ record }) => record.id).join(", ")}`,
          );
        }
      }
    }
    const operation =
      options.command === "apply"
        ? (record: ResolvedRecord) => applyRecord(record, { sudoMode, strategy: options.strategy })
        : options.command === "remove"
          ? (record: ResolvedRecord) => removeRecord(record, sudoMode)
          : classifyRecord;
    rows = [...resolved.invalid];
    // Mutation is all-or-nothing with respect to plan validity.
    if (resolved.invalid.length === 0 || options.command === "status") {
      for (const record of resolved.records) rows.push(await operation(record));
    }
  }
  output(rows, options);
  if (
    rows.some(
      (row) =>
        row.status === "SOURCE_MISSING" ||
        row.status === "SOURCE_UNUSABLE" ||
        row.status === "INVALID",
    )
  )
    return 2;
  return rows.some((row) => row.status === "MISSING" || row.status === "CONFLICT") ? 1 : 0;
}
