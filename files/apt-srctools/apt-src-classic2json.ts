#!/usr/bin/env -S node --strip-types
/**
 * apt-src-classic2json.ts - convert one-line classic .list sources to the
 * canonical apt-srctools JSON model (see apt-src-model.ts).
 *
 * One classic line becomes one JSON entry. Commented-out lines ("#deb ...")
 * become entries with "enabled": false; pure comments are dropped.
 *
 * Usage:
 *   apt-src-classic2json.ts [--file PATH | --in PATH] [--out PATH] < classic.list
 *   apt-src-classic2json.ts --file /etc/apt/sources.list --out sources.json
 */

import { readFile, writeFile } from "node:fs/promises";
import { parseArgs } from "node:util";
import { AptParseError, canonical, parseClassic } from "./apt-src-model.ts";

const USAGE = `apt-src-classic2json.ts - classic .list sources -> JSON

Usage:
  apt-src-classic2json.ts [--file PATH | --in PATH] [--out PATH]

Options:
  --file, -f PATH   input file (default: stdin)
  --in PATH         alias for --file
  --out, -o PATH    output file (default: stdout)
  --help, -h        this help

Reads one-line-format apt sources from stdin or a file and writes the
canonical JSON model. One line = one entry; "#deb" lines get enabled:false.`;

async function readStdin(): Promise<string> {
  const chunks: Buffer[] = [];
  for await (const chunk of process.stdin) chunks.push(chunk as Buffer);
  return Buffer.concat(chunks).toString("utf8");
}

const args = parseArgs({
  options: {
    file: { type: "string", short: "f" },
    in: { type: "string" },
    out: { type: "string", short: "o" },
    help: { type: "boolean", short: "h" },
  },
});
if (args.values.help) {
  console.log(USAGE);
  process.exit(0);
}

const input = args.values.in ?? args.values.file;
try {
  const text = input ? await readFile(input, "utf8") : await readStdin();
  const json = canonical(parseClassic(text));
  const out = JSON.stringify(json, null, 2) + "\n";
  if (args.values.out) await writeFile(args.values.out, out, "utf8");
  else process.stdout.write(out);
} catch (err) {
  if (err instanceof AptParseError) {
    console.error(`error: ${input ?? "stdin"}: ${err.message}`);
    process.exit(1);
  }
  throw err;
}
