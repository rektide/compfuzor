#!/usr/bin/env node
// status-modules.ts — kernel module parameter drift: desired vs deployed vs live.
//
// TS sibling of status-sysctl.ts for the kernel_modprobe leaf. It compares three
// representations of module parameters and flags desync, flattening every source
// to a `module.param` key -- the same shape install-kernel-cmdline.sh uses for
// builtin cmdline tokens, and the dotted form of modprobe `options` lines.
//
// Sources (default: all three):
//   --compfuzor [FILE]  DESIRED   module params from the playbook JSON
//                                 ($KERNEL_MODULES_JSON). Each module's `params`
//                                 mapping is flattened to module.param. Also
//                                 defines the module scope (which modules we
//                                 report on). Default FILE: $KERNEL_MODULES_JSON.
//   --system [FILE]     DEPLOYED  installed params, merged from both deploy
//                                 modes: /etc/modprobe.d/<NAME>.conf
//                                 (`options <mod> k=v ...`, module mode) and
//                                 /etc/kernel/cmdline (`mod.param=v`, builtin
//                                 mode). An explicit FILE is parsed as modprobe
//                                 `options` format instead. <unset> => install
//                                 advised; not an error.
//   --kernel            LIVE      /sys/module/<mod>/parameters/<param>, enumerated
//                                 per declared module (the broad keys+values
//                                 view -- every param the module exposes, so
//                                 defaults we don't set are visible). An
//                                 unreadable value (e.g. 0400 root-only) is
//                                 <unset>. Never defines the module scope.
//
//   --json              one JSON object per row (JSON Lines).
//   --json-array        all rows as a single JSON array.
//   -q                  one-word synopsis (OK/UNSET/DRIFT); -qq = fully silent.
//   -h, --help          help.
//
// $DIR from env or this script's own location; NAME = basename($DIR).
// Exit: 0 no drift, 1 drift, 2 usage/source error. A param renders <unset> when a
// source has no value for it (we don't declare it, or a live sysfs file is
// unreadable). UNSET rows are visible but not drift -- re-run as root to verify
// unreadable live values.

import { readFileSync, existsSync, readdirSync } from "node:fs";
import { basename, dirname } from "node:path";
import { fileURLToPath } from "node:url";

type Source = "compfuzor" | "system" | "kernel";
// <unset>: this source's empty value -- it contributes nothing for a param. Used
// when WE don't declare it (our column is empty) or when a live sysfs value can't
// be read (e.g. a 0400 root-only file). A row is only DRIFT when readable values
// disagree; a param we don't manage, or one we can't verify live, is UNSET --
// visible (so you can see what the kernel sets) but not drift.
const UNSET = "<unset>";
const ALL: Source[] = ["compfuzor", "system", "kernel"];

const DIR = process.env.DIR ?? dirname(dirname(fileURLToPath(import.meta.url)));
const NAME = process.env.NAME ?? basename(DIR);
const DEFAULTS: Record<Source, string> = {
  compfuzor: process.env.KERNEL_MODULES_JSON ?? `${DIR}/etc/kernel.modules.json`,
  system: "",
  kernel: "",
};

function usage(): void {
  console.error(`usage: status-modules.ts [--json | --json-array] [-q] [--compfuzor [FILE]] [--system [FILE]] [--kernel] [-h]
  --compfuzor [FILE]  desired: module params from playbook JSON (defines module scope)
  --system [FILE]     deployed: /etc/modprobe.d + /etc/kernel/cmdline merged (<unset> => install advised)
  --kernel            live: /sys/module/<mod>/parameters/* (all params per declared module; unreadable -> <unset>)
  --json              one JSON object per row (JSON Lines)
  --json-array        all rows as a single JSON array
  -q                  one-word synopsis (OK/UNSET/DRIFT); -qq = silent
  exit: 0 in-sync / 1 drift / 2 error (UNSET = unverified live value, not drift)`);
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
      case "--kernel": sources.add("kernel"); break;
      default:
        if (a.startsWith("-")) { console.error(`status-modules.ts: unknown option: ${a}`); process.exit(2); }
    }
  }
  if (sources.size === 0) for (const s of ALL) sources.add(s);
  return { sources, files, format, quiet };
}

// --- source loaders -> Map<"module.param", value> --------------------------

interface ModuleEntry { params?: Record<string, unknown>; }

// compfuzor: flatten JSON {module: {params: {k:v}}} -> module.param = v.
// Also returns the declared module set (used as the live-enumeration scope).
function loadCompfuzor(file: string): { map: Map<string, string>; modules: Set<string> } {
  if (!file || !existsSync(file)) {
    console.error(`status-modules.ts: cannot read json: ${file || "(set KERNEL_MODULES_JSON or pass --compfuzor FILE)"}`);
    process.exit(2);
  }
  const obj = JSON.parse(readFileSync(file, "utf8")) as Record<string, ModuleEntry>;
  const map = new Map<string, string>();
  const modules = new Set<string>();
  for (const [mod, entry] of Object.entries(obj)) {
    modules.add(mod);
    for (const [k, v] of Object.entries(entry?.params ?? {})) map.set(`${mod}.${k}`, String(v));
  }
  return { map, modules };
}

// Parse a modprobe-format file (`options <mod> k=v k=v ...`) into module.param.
function parseModprobe(file: string, out: Map<string, string>, modules?: Set<string>): void {
  if (!existsSync(file)) return;
  for (const raw of readFileSync(file, "utf8").split("\n")) {
    const line = raw.trim();
    if (!line || line.startsWith("#")) continue;
    const m = line.match(/^options\s+(\S+)\s+(.*)$/);
    if (!m) continue;
    const mod = m[1];
    if (modules && !modules.has(mod)) continue;
    for (const tok of m[2].trim().split(/\s+/)) {
      if (!tok) continue;
      const eq = tok.indexOf("=");
      if (eq > 0) out.set(`${mod}.${tok.slice(0, eq)}`, tok.slice(eq + 1));
    }
  }
}

// system: merge /etc/modprobe.d/<NAME>.conf (module mode) + /etc/kernel/cmdline
// (builtin mode, `mod.param=v` tokens). An explicit FILE is parsed as modprobe
// format only. Scoped to declared modules when known.
function loadSystem(file: string | undefined, name: string, modules: Set<string>): Map<string, string> {
  const out = new Map<string, string>();
  if (file) {
    parseModprobe(file, out, modules);
    return out;
  }
  parseModprobe(`/etc/modprobe.d/${name}.conf`, out, modules);
  const cmdline = "/etc/kernel/cmdline";
  if (existsSync(cmdline)) {
    for (const tok of readFileSync(cmdline, "utf8").split(/\s+/)) {
      const eq = tok.indexOf("=");
      if (eq <= 0) continue;
      const key = tok.slice(0, eq);
      const dot = key.indexOf(".");
      if (dot <= 0) continue;
      const mod = key.slice(0, dot);
      if (modules.has(mod)) out.set(key, tok.slice(eq + 1));
    }
  }
  return out;
}

// live: enumerate /sys/module/<declared_mod>/parameters/* -> module.param.
// A module that is not loaded (no readable parameters dir) contributes nothing;
// its declared params render <unset> downstream. A param whose value can't be
// read (e.g. a 0400 root-only sysfs file) is also recorded as <unset>, so every
// param the module exposes stays visible -- including defaults we don't set.
function loadKernel(modules: Iterable<string>): Map<string, string> {
  const out = new Map<string, string>();
  for (const mod of modules) {
    const pdir = `/sys/module/${mod}/parameters`;
    let files: string[];
    try { files = readdirSync(pdir); } catch { continue; }
    for (const param of files) {
      try {
        out.set(`${mod}.${param}`, readFileSync(`${pdir}/${param}`, "utf8").trim());
      } catch {
        out.set(`${mod}.${param}`, UNSET);
      }
    }
  }
  return out;
}

// --- main ------------------------------------------------------------------

const { sources, files, format, quiet } = parseArgs(process.argv.slice(2));

if (!sources.has("compfuzor") && !sources.has("system") && sources.has("kernel")) {
  console.error("status-modules.ts: --kernel needs --compfuzor or --system to define the module scope");
  process.exit(2);
}

const order = ALL.filter((s) => sources.has(s));

// compfuzor defines the module scope; if it is not selected, derive modules
// from the system entries instead.
let compfuzorMap = new Map<string, string>();
let modules: Set<string>;
if (sources.has("compfuzor")) {
  const r = loadCompfuzor(files.compfuzor ?? DEFAULTS.compfuzor);
  compfuzorMap = r.map;
  modules = r.modules;
} else {
  // scope from system file: parse without filter to discover module names
  modules = new Set<string>();
  const tmp = new Map<string, string>();
  if (files.system) parseModprobe(files.system, tmp);
  else parseModprobe(`/etc/modprobe.d/${NAME}.conf`, tmp);
  for (const k of tmp.keys()) { const d = k.indexOf("."); if (d > 0) modules.add(k.slice(0, d)); }
}

const systemMap = sources.has("system") ? loadSystem(files.system, NAME, modules) : new Map<string, string>();
const kernelMap = sources.has("kernel") ? loadKernel(modules) : new Map<string, string>();

// key universe across selected sources, scoped to declared modules
const keys = new Set<string>([...compfuzorMap.keys(), ...systemMap.keys(), ...kernelMap.keys()]);
if (keys.size === 0) {
  console.error("status-modules.ts: no module parameters found (need --compfuzor or --system with data)");
  process.exit(2);
}

const maps: Record<Source, Map<string, string>> = { compfuzor: compfuzorMap, system: systemMap, kernel: kernelMap };

// Canonical comparison form. Integers (decimal or 0x hex, optional sign) collapse
// to a decimal string so a playbook's hex literal compares equal to the kernel's
// decimal sysfs rendering (e.g. 0x100000000 == 4294967296, 0x40000 == 262144).
// Display still uses the raw value; this is for the status decision only.
// Sentinels and non-numeric strings compare as their trimmed raw form.
function compareKey(v: string): string {
  if (v === UNSET) return v;
  const s = v.trim();
  if (/^-?0x[0-9a-fA-F]+$/i.test(s) || /^-?\d+$/.test(s)) {
    try { return BigInt(s).toString(10); } catch { return s; }
  }
  return s;
}

let drift = false;
let unsetCount = 0;
const rows = [...keys].sort().map((k) => {
  const vals = order.map((src) => maps[src].get(k) ?? UNSET);
  const cmp = vals.map(compareKey);
  const cfIdx = order.indexOf("compfuzor");
  const cfSet = cfIdx >= 0 && vals[cfIdx] !== UNSET;

  let status: string;
  if (!cfSet) {
    // We don't manage this param (compfuzor doesn't declare it) -- e.g. a module
    // default the kernel exposes. Show it so you can see what the kernel sets,
    // but it isn't drift: we never claimed to set it.
    status = "UNSET";
    unsetCount++;
  } else if (cmp.every((v) => v === cmp[0])) {
    status = "OK";
  } else {
    const real = cmp.filter((v) => v !== UNSET);
    const realAgree = real.length > 0 && real.every((v) => v === real[0]);
    if (!realAgree) {
      status = "DRIFT";
      drift = true;
    } else {
      // Readable values agree, but some source is <unset>. If that source is the
      // deployed (system) side, we declared it but never installed it -> DRIFT.
      // If only the live (kernel) side is unset (e.g. an unreadable 0400 sysfs
      // file), it is unverified, not wrong -> UNSET.
      const sysIdx = order.indexOf("system");
      if (sysIdx >= 0 && cmp[sysIdx] === UNSET) {
        status = "DRIFT";
        drift = true;
      } else {
        status = "UNSET";
        unsetCount++;
      }
    }
  }
  const row: Record<string, string> = { key: k, status };
  order.forEach((s, idx) => { row[s] = vals[idx]; });
  return row;
});

if (quiet === 1) {
  console.log(drift ? "DRIFT" : unsetCount > 0 ? "UNSET" : "OK");
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
