#!/usr/bin/env node
// status-sysctl.ts — sysctl drift report: desired vs deployed vs live.
//
// TS implementation; the bash status-sysctl.sh is deprecated in favor of this
// file. Runs via Node type stripping.
//
// Sources (default: all three):
//   --compfuzor [FILE]  DESIRED   rebuilt from the playbook JSON ($KERNEL_SYSCTL_JSON).
//                                 Defines the key set together with --system.
//   --system [FILE]     DEPLOYED  system-installed conf (/etc/sysctl.d/<NAME>.conf),
//                                 where install-kernel-sysctl.sh links it. NAME = basename($DIR).
//                                 Missing file => every value <missing> ("install
//                                 advised"); not an error.
//   --kernel            LIVE      current values via `sysctl -n`; per-key lookup.
//
//   --json              emit one JSON object per row (JSON Lines).
//   --json-array        emit all rows as a single JSON array.
//   -q                  one-word synopsis (OK/DRIFT); -qq = fully silent.
//   -h, --help          help.
//
// Exit: 0 no drift, 1 drift, 2 usage/source error.

import { readFileSync, existsSync } from "node:fs";
import { execFileSync } from "node:child_process";
import { basename, dirname } from "node:path";
import { fileURLToPath } from "node:url";

type Source = "compfuzor" | "system" | "kernel";
const MISSING = "<missing>";
const ALL: Source[] = ["compfuzor", "system", "kernel"];

// $DIR is the project root (e.g. /etc/opt/fs-inotify-main). Prefer the env
// (set when run via a wrapped bin); otherwise derive it from this script's
// own location ($DIR/bin/status-sysctl.ts), so it works with no env wrapper.
// NAME is the project name; install-kernel-sysctl.sh installs the system file.
const DIR = process.env.DIR ?? dirname(dirname(fileURLToPath(import.meta.url)));
const NAME = process.env.NAME ?? basename(DIR);
const DEFAULTS: Record<Source, string> = {
  compfuzor: process.env.KERNEL_SYSCTL_JSON ?? `${DIR}/etc/kernel.sysctl.json`,
  system: `/etc/sysctl.d/${NAME}.conf`,
  kernel: "",
};

function usage(): void {
  console.error(`usage: status-sysctl.ts [--json | --json-array] [-q] [--compfuzor [FILE]] [--system [FILE]] [--kernel] [-h]
  --compfuzor [FILE]  desired: rebuilt from playbook JSON (defines keys)
  --system [FILE]     deployed: /etc/sysctl.d/<NAME>.conf (missing => install advised)
  --kernel            live: current kernel values via \`sysctl -n\`
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
    // consume an optional path arg only if it is present and not itself a flag
    const takePath = (): string | undefined => {
      if (next && !next.startsWith("-")) { i++; return next; }
      return undefined;
    };
    // -q = one-word synopsis (OK/DRIFT); -qq or more = fully silent
    if (/^-q+$/.test(a)) { quiet += a.length - 1; continue; }
    switch (a) {
      case "-h": case "--help": usage(); process.exit(0);
      case "--json": format = "jsonl"; break;
      case "--json-array": format = "array"; break;
      case "--compfuzor": sources.add("compfuzor"); { const f = takePath(); if (f) files.compfuzor = f; } break;
      case "--system": sources.add("system"); { const f = takePath(); if (f) files.system = f; } break;
      case "--kernel": sources.add("kernel"); break;
      default:
        if (a.startsWith("-")) { console.error(`status-sysctl.ts: unknown option: ${a}`); process.exit(2); }
    }
  }
  if (sources.size === 0) for (const s of ALL) sources.add(s);
  return { sources, files, format, quiet };
}

// --- source loaders -> Map<key, value> -------------------------------------

function loadCompfuzor(file: string): Map<string, string> {
  if (!file || !existsSync(file)) {
    console.error(`status-sysctl.ts: cannot read json: ${file || "(set KERNEL_SYSCTL_JSON or pass --compfuzor FILE)"}`);
    process.exit(2);
  }
  const obj = JSON.parse(readFileSync(file, "utf8")) as Record<string, unknown>;
  const m = new Map<string, string>();
  for (const [k, v] of Object.entries(obj)) m.set(k, String(v));
  return m;
}

function loadSystem(file: string): Map<string, string> {
  const m = new Map<string, string>();
  if (!file || !existsSync(file)) return m; // missing => empty => install advised
  for (const raw of readFileSync(file, "utf8").split("\n")) {
    const line = raw.replace(/^\s+/, "");
    if (!line || line.startsWith("#")) continue;
    const eq = line.indexOf("=");
    if (eq < 0) continue;
    const key = line.slice(0, eq).replace(/\s+$/, "");
    const val = line.slice(eq + 1).replace(/^\s+/, "");
    if (key) m.set(key, val);
  }
  return m;
}

function loadKernel(keys: Iterable<string>): Map<string, string> {
  const m = new Map<string, string>();
  for (const k of keys) {
    try {
      m.set(k, execFileSync("sysctl", ["-n", k], { encoding: "utf8", stdio: ["ignore", "pipe", "ignore"] }).trim());
    } catch {
      // unset => <missing>
    }
  }
  return m;
}

// --- main ------------------------------------------------------------------

const { sources, files, format, quiet } = parseArgs(process.argv.slice(2));

if (!sources.has("compfuzor") && !sources.has("system") && sources.has("kernel")) {
  console.error("status-sysctl.ts: --kernel needs --compfuzor or --system to define the key set");
  process.exit(2);
}

const order = ALL.filter((s) => sources.has(s));

const compfuzor = sources.has("compfuzor") ? loadCompfuzor(files.compfuzor ?? DEFAULTS.compfuzor) : new Map<string, string>();
const system = sources.has("system") ? loadSystem(files.system ?? DEFAULTS.system) : new Map<string, string>();

// key universe = declared intent (compfuzor + system); kernel never defines it
const keys = new Set<string>([...compfuzor.keys(), ...system.keys()]);
if (keys.size === 0) {
  console.error("status-sysctl.ts: no key-defining source available (need --compfuzor or --system with data)");
  process.exit(2);
}

const kernel = sources.has("kernel") ? loadKernel(keys) : new Map<string, string>();
const maps: Record<Source, Map<string, string>> = { compfuzor, system, kernel };

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
  // one-word synopsis
  console.log(drift ? "DRIFT" : "OK");
} else if (quiet >= 2) {
  // very silent: exit code only
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
