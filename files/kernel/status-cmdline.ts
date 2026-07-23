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
// Sources (default: all three):
//   --compfuzor [FILE]  DESIRED   raw tokens from $KERNEL_PARAMS_JSON (JSON
//                                 array of strings, e.g. ["memmap=256K$0x1..."]).
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
// Scope is the desired (compfuzor) keys -- we report on what the playbook
// declared, not every token the kernel booted with. Exit: 0 no drift, 1 drift, 2 error.

import { readFileSync, existsSync } from "node:fs";
import { basename, dirname } from "node:path";
import { fileURLToPath } from "node:url";

type Source = "compfuzor" | "system" | "kernel";
const MISSING = "<missing>";
const ALL: Source[] = ["compfuzor", "system", "kernel"];

const DIR = process.env.DIR ?? dirname(dirname(fileURLToPath(import.meta.url)));
const NAME = process.env.NAME ?? basename(DIR);
const DEFAULTS: Record<Source, string> = {
  compfuzor: process.env.KERNEL_PARAMS_JSON ?? `${DIR}/etc/kernel.params.json`,
  system: "/etc/kernel/cmdline",
  kernel: "/proc/cmdline",
};

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

type Format = "tsv" | "jsonl" | "array";

interface Opts {
  sources: Set<Source>;
  files: Partial<Record<Source, string>>;
  format: Format;
  quiet: number;
}

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

// Split a cmdline-style string into key -> value. "a=1 b=2 nosmp" becomes
// { a:"1", b:"2", nosmp:"nosmp" } -- flag tokens (no '=') map to themselves so
// presence compares correctly against <missing>.
function tokenizeLine(s: string): Map<string, string> {
  const out = new Map<string, string>();
  for (const tok of s.split(/\s+/)) {
    if (!tok) continue;
    const eq = tok.indexOf("=");
    if (eq > 0) out.set(tok.slice(0, eq), tok.slice(eq + 1));
    else out.set(tok, tok);
  }
  return out;
}

// compfuzor: KERNEL_PARAMS_JSON is a JSON array of token strings.
function loadCompfuzor(file: string): Map<string, string> {
  if (!file || !existsSync(file)) {
    console.error(`status-cmdline.ts: cannot read json: ${file || "(set KERNEL_PARAMS_JSON or pass --compfuzor FILE)"}`);
    process.exit(2);
  }
  const arr = JSON.parse(readFileSync(file, "utf8")) as unknown;
  if (!Array.isArray(arr)) {
    console.error(`status-cmdline.ts: ${file} is not a JSON array`);
    process.exit(2);
  }
  const out = new Map<string, string>();
  for (const tok of arr as (string | number | boolean)[]) {
    const s = String(tok);
    const eq = s.indexOf("=");
    if (eq > 0) out.set(s.slice(0, eq), s.slice(eq + 1));
    else out.set(s, s);
  }
  return out;
}

function loadFile(file: string | undefined, fallback: string): Map<string, string> {
  const path = file ?? fallback;
  if (!existsSync(path)) return new Map<string, string>();
  return tokenizeLine(readFileSync(path, "utf8"));
}

// --- main ------------------------------------------------------------------

const { sources, files, format, quiet } = parseArgs(process.argv.slice(2));

const order = ALL.filter((s) => sources.has(s));

const compfuzorMap = sources.has("compfuzor") ? loadCompfuzor(files.compfuzor ?? DEFAULTS.compfuzor) : new Map<string, string>();
const systemMap = sources.has("system") ? loadFile(files.system, DEFAULTS.system) : new Map<string, string>();
const kernelMap = sources.has("kernel") ? loadFile(files.kernel, DEFAULTS.kernel) : new Map<string, string>();

// scope = desired tokens only
const keys = new Set<string>(compfuzorMap.keys());
if (keys.size === 0) {
  console.error(`status-cmdline.ts: no raw cmdline tokens found (need --compfuzor or $KERNEL_PARAMS_JSON)`);
  process.exit(2);
}

const maps: Record<Source, Map<string, string>> = { compfuzor: compfuzorMap, system: systemMap, kernel: kernelMap };

let drift = false;
const rows = [...keys].sort().map((k) => {
  const vals = order.map((src) => maps[src].get(k) ?? MISSING);
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
