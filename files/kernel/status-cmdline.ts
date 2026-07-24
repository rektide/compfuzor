#!/usr/bin/env node
// status-cmdline.ts -- raw kernel cmdline token drift: desired vs deployed vs live.
//
// The status sibling of install-kernel-params.sh. status-modules.ts covers the
// <module>.<param>=<value> tokens (ramoops.mem_address, pstore.backend, ...);
// this covers the RAW tokens that don't fit that shape (memmap=...,
// rootflags=..., nospectre_v2) -- the ones declared via KERNEL_PARAMS and
// written to /etc/kernel/cmdline by install-kernel-params.sh. Keys on the part
// before the first '='; tokens without '=' are flag-style (presence compared).
//
// Duplicate keys are flagged: if the same key appears more than once in a
// source, that source's value is annotated " [DUP]" (which also makes the row
// DRIFT, since the annotation differs across sources). install-kernel-params.sh
// collapses duplicates by default; a DUP here means a stale dup survived, or a
// token was declared with dup:true (allow-duplicates mode).
//
// Sources (default: all three):
//   --compfuzor [FILE]  DESIRED   raw tokens from $KERNEL_PARAMS_JSON (JSON
//                                 array; entries are strings, or objects
//                                 {token, dup} in allow-duplicates mode).
//                                 Default FILE: $KERNEL_PARAMS_JSON.
//   --system [FILE]     DEPLOYED  /etc/kernel/cmdline (where install-kernel-params.sh
//                                 wrote them). An explicit FILE is read as cmdline text.
//   --kernel [FILE]     LIVE      /proc/cmdline (what the running kernel booted with).
//
//   --json              one JSON object per row (JSON Lines).
//   --json-array        all rows as a single JSON array.
//   -q                  one-word synopsis (OK/DRIFT); -qq = fully silent.
//   -h, --help          help.
//
// Scope is the desired (compfuzor) keys. Exit: 0 no drift, 1 drift, 2 error.

import { readFileSync, existsSync } from "node:fs";
import { basename, dirname } from "node:path";
import { fileURLToPath } from "node:url";

/**
 * The three drift-comparison sources, in canonical display order.
 *
 * - `"compfuzor"` — DESIRED: the tokens the playbook declares (KERNEL_PARAMS).
 * - `"system"`    — DEPLOYED: `/etc/kernel/cmdline`, where install-kernel-params.sh wrote them.
 * - `"kernel"`    — LIVE: `/proc/cmdline`, what the running kernel actually booted with.
 */
type Source = "compfuzor" | "system" | "kernel";

/** Placeholder shown when a declared key is absent from a given source. */
const MISSING = "<missing>";

/** All sources in canonical display/comparison order. */
const ALL: Source[] = ["compfuzor", "system", "kernel"];

/**
 * Resolved config dir and instance name. `$DIR` is the deployed config root
 * (e.g. `/etc/opt/pstore-main`); `$NAME` is its basename, used in diagnostics.
 * Both default from this script's own location (`bin/` -> parent dir).
 */
const DIR = process.env.DIR ?? dirname(dirname(fileURLToPath(import.meta.url)));
const NAME = process.env.NAME ?? basename(DIR);

/**
 * Default source paths, overridable per-source via the CLI flags. `compfuzor`
 * honors `$KERNEL_PARAMS_JSON`; `system`/`kernel` are fixed kernel paths.
 */
const DEFAULTS: Record<Source, string> = {
  compfuzor: process.env.KERNEL_PARAMS_JSON ?? `${DIR}/etc/kernel.params.json`,
  system: "/etc/kernel/cmdline",
  kernel: "/proc/cmdline",
};

/**
 * Result of parsing one cmdline source.
 *
 * @property map   key -> value. For `key=value` tokens the value follows the
 *                 first `=`; for flag tokens (no `=`) key == value == the token.
 *                 When a key repeats, the LAST value wins here.
 * @property dups  keys that appeared more than once in this source, surfaced so
 *                 the row formatter can annotate them "[DUP]" and force DRIFT.
 */
interface Parsed {
  map: Map<string, string>;
  dups: Set<string>;
}

/**
 * Print the usage banner to stderr. The caller is responsible for exiting
 * (this returns normally so tests can capture the stream if needed).
 */
function usage(): void {
  console.error(`usage: status-cmdline.ts [--json | --json-array] [-q] [--compfuzor [FILE]] [--system [FILE]] [--kernel [FILE]] [-h]
  --compfuzor [FILE]  desired: raw tokens from $KERNEL_PARAMS_JSON (defines scope)
  --system [FILE]     deployed: /etc/kernel/cmdline (default)
  --kernel [FILE]     live: /proc/cmdline (default)
  --json              one JSON object per row (JSON Lines)
  --json-array        all rows as a single JSON array
  -q                  one-word synopsis (OK/DRIFT); -qq = silent
  exit: 0 in-sync / 1 drift / 2 error`);
}

/** Output shape: aligned TSV table, one JSON object per line, or a single JSON array. */
type Format = "tsv" | "jsonl" | "array";

/**
 * Parsed CLI options.
 *
 * @property sources  which sources to load; empty until a `--<source>` is seen,
 *                    then filled with all of {@link ALL} so a bare invocation
 *                    loads every source from its default.
 * @property files    optional per-source path overrides (the `[FILE]` of `--<source> FILE`).
 * @property format   output {@link Format}; default `"tsv"`.
 * @property quiet    0 = full table, 1 = one-word synopsis (`OK`/`DRIFT`), >=2 = silent.
 */
interface Opts {
  sources: Set<Source>;
  files: Partial<Record<Source, string>>;
  format: Format;
  quiet: number;
}

/**
 * Parse the reporter's CLI flags into {@link Opts}.
 *
 * Each `--<source>` flag takes an OPTIONAL following path (any non-flag token);
 * `--kernel` likewise accepts an override so tests can point at a fixture. If no
 * source flag is given, all three sources load from {@link DEFAULTS}. `--json` /
 * `--json-array` select output format; `-q` repeats for quietness. `-h`/`--help`
 * prints usage and exits 0. Unknown flags exit 2.
 *
 * @param argv  the arg list after the script name (typically `process.argv.slice(2)`).
 * @returns the resolved {@link Opts}.
 */
function parseArgs(argv: string[]): Opts {
  const sources = new Set<Source>();
  const files: Partial<Record<Source, string>> = {};
  let format: Format = "tsv";
  let quiet = 0;
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    const next = argv[i + 1];
    const takePath = (): string | undefined => {
      if (next && !next.startsWith("-")) { i++; return next; }
      return undefined;
    };
    if (/^-q+$/.test(a)) { quiet += a.length - 1; continue; }
    switch (a) {
      case "-h": case "--help": usage(); process.exit(0);
      case "--json": format = "jsonl"; break;
      case "--json-array": format = "array"; break;
      case "--compfuzor": sources.add("compfuzor"); { const f = takePath(); if (f) files.compfuzor = f; } break;
      case "--system": sources.add("system"); { const f = takePath(); if (f) files.system = f; } break;
      case "--kernel": sources.add("kernel"); { const f = takePath(); if (f) files.kernel = f; } break;
      default:
        if (a.startsWith("-")) { console.error(`status-cmdline.ts: unknown option: ${a}`); process.exit(2); }
    }
  }
  if (sources.size === 0) for (const s of ALL) sources.add(s);
  return { sources, files, format, quiet };
}

/** Empty {@link Parsed}, returned for sources whose file is absent. */
const EMPTY: Parsed = { map: new Map(), dups: new Set() };

/**
 * Split a cmdline-style string into a {@link Parsed}. Keys are the part before
 * the first `=`; tokens without `=` are flag-style (key == value == the token,
 * so presence compares against {@link MISSING}). Repeated keys land in `dups`
 * (last value wins in `map`).
 *
 * @example
 * tokenize("a=1 b=2 nosmp b=3")
 * // -> { map: { a:"1", b:"3", nosmp:"nosmp" }, dups: Set { "b" } }
 */
function tokenize(s: string): Parsed {
  const map = new Map<string, string>();
  const dups = new Set<string>();
  for (const tok of s.split(/\s+/)) {
    if (!tok) continue;
    const eq = tok.indexOf("=");
    const key = eq > 0 ? tok.slice(0, eq) : tok;
    const val = eq > 0 ? tok.slice(eq + 1) : tok;
    if (map.has(key)) dups.add(key);
    map.set(key, val);
  }
  return { map, dups };
}

/**
 * Load the DESIRED tokens from `file` (KERNEL_PARAMS_JSON): a JSON array of
 * token strings. This source defines the report scope (we only emit rows for
 * declared keys). Tracks repeated keys into `dups` so they can be flagged.
 * Exits with status 2 if the file is missing or not a JSON array.
 */
function loadCompfuzor(file: string): Parsed {
  if (!file || !existsSync(file)) {
    console.error(`status-cmdline.ts: cannot read json: ${file || "(set KERNEL_PARAMS_JSON or pass --compfuzor FILE)"}`);
    process.exit(2);
  }
  const arr = JSON.parse(readFileSync(file, "utf8")) as unknown;
  if (!Array.isArray(arr)) {
    console.error(`status-cmdline.ts: ${file} is not a JSON array`);
    process.exit(2);
  }
  const map = new Map<string, string>();
  const dups = new Set<string>();
  for (const tok of arr as (string | number | boolean)[]) {
    const s = String(tok);
    if (!s) continue;
    const eq = s.indexOf("=");
    const key = eq > 0 ? s.slice(0, eq) : s;
    const val = eq > 0 ? s.slice(eq + 1) : s;
    if (map.has(key)) dups.add(key);
    map.set(key, val);
  }
  return { map, dups };
}

/**
 * Load a DEPLOYED/LIVE source from `file`, falling back to {@link DEFAULTS}
 * when no override was given. Returns {@link EMPTY} if the path doesn't exist
 * (e.g. `/etc/kernel/cmdline` absent on a minimal box, or a `--kernel` fixture
 * that isn't there) so a missing source reads as all-`<missing>` rather than
 * erroring.
 *
 * @param file      explicit override path (`undefined` means "use fallback").
 * @param fallback  the {@link DEFAULTS} path for this source.
 */
function loadFile(file: string | undefined, fallback: string): Parsed {
  const path = file ?? fallback;
  if (!existsSync(path)) return EMPTY;
  return tokenize(readFileSync(path, "utf8"));
}

// --- main ------------------------------------------------------------------
// Load the selected sources, scope to the DESIRED (compfuzor) keys, and emit one
// row per key comparing values across sources. A source with a duplicate key for
// a given row annotates its value " [DUP]", which both surfaces the dup and
// forces the row to DRIFT (the annotation differs from clean sources).

const { sources, files, format, quiet } = parseArgs(process.argv.slice(2));

/** Sources actually requested, in canonical order. */
const order = ALL.filter((s) => sources.has(s));

const compfuzor = sources.has("compfuzor") ? loadCompfuzor(files.compfuzor ?? DEFAULTS.compfuzor) : EMPTY;
const system = sources.has("system") ? loadFile(files.system, DEFAULTS.system) : EMPTY;
const kernel = sources.has("kernel") ? loadFile(files.kernel, DEFAULTS.kernel) : EMPTY;

/** Scope = desired tokens only; we never report on kernel tokens we didn't declare. */
const keys = new Set<string>(compfuzor.map.keys());
if (keys.size === 0) {
  console.error(`status-cmdline.ts: no raw cmdline tokens found (need --compfuzor or $KERNEL_PARAMS_JSON)`);
  process.exit(2);
}

const parsed: Record<Source, Parsed> = { compfuzor, system, kernel };

let drift = false;
/** One comparison row per declared key: per-source value (with " [DUP]" marker) and OK/DRIFT. */
const rows = [...keys].sort().map((k) => {
  const vals = order.map((src) => {
    const v = parsed[src].map.get(k) ?? MISSING;
    return parsed[src].dups.has(k) ? `${v} [DUP]` : v;
  });
  const status = vals.every((v) => v === vals[0]) ? "OK" : "DRIFT";
  if (status === "DRIFT") drift = true;
  const row: Record<string, string> = { key: k, status };
  order.forEach((s, idx) => { row[s] = vals[idx]; });
  return row;
});

if (quiet === 1) {
  console.log(drift ? "DRIFT" : "OK");
} else if (quiet >= 2) {
  // fully silent
} else if (format === "jsonl") {
  for (const r of rows) console.log(JSON.stringify(r));
} else if (format === "array") {
  console.log(JSON.stringify(rows, null, 2));
} else {
  const cols = ["key", "status", ...order];
  console.log(cols.join("\t"));
  for (const r of rows) console.log(cols.map((c) => r[c]).join("\t"));
}

process.exit(drift ? 1 : 0);
