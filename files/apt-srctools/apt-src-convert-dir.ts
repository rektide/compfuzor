#!/usr/bin/env -S node --strip-types
/**
 * apt-src-convert-dir.ts - move every apt source file in a directory to a
 * target format (classic .list <-> deb822 .sources) through the canonical
 * JSON model (see apt-src-model.ts).
 *
 * The in-place foo.list -> foo.sources replacement IS this tool's job: after
 * writing the converted file it removes the source file. Nothing else is ever
 * deleted. Files already in the target format are left alone. Symlinks are
 * skipped with a warning (their content is managed elsewhere); only plain
 * *.list and *.sources files are considered.
 *
 * Every conversion is verified before it replaces anything: the emitted text
 * is re-parsed and must canonicalize to the same JSON as the input.
 *
 * Usage:
 *   apt-src-convert-dir.ts [--to classic|deb822] [--dry-run] [--out DIR] [--force] [DIR]
 *
 * Examples:
 *   apt-src-convert-dir.ts --to deb822 --dry-run
 *   sudo apt-src-convert-dir.ts --to deb822 /etc/apt/sources.list.d
 *   apt-src-convert-dir.ts --to classic --out /tmp/converted .
 */

import { lstat, mkdir, readdir, readFile, rm, writeFile } from "node:fs/promises";
import { join } from "node:path";
import { parseArgs } from "node:util";
import {
  AptParseError,
  canonical,
  emitClassic,
  emitDeb822,
  parseClassic,
  parseDeb822,
} from "./apt-src-model.ts";

const USAGE = `apt-src-convert-dir.ts - convert a directory of apt sources between formats

Usage:
  apt-src-convert-dir.ts [--to classic|deb822] [--dry-run] [--out DIR] [--force] [DIR]

Options:
  --to FORMAT    target format: classic or deb822 (default: deb822)
  --dry-run      print the plan without writing anything
  --out DIR      write converted copies into DIR instead of replacing in place
  --force        overwrite a differing existing destination file
  DIR            directory to convert (default: /etc/apt/sources.list.d)

In-place conversion writes foo.sources then removes foo.list (and vice
versa); nothing else is deleted. Symlinks are skipped. Each conversion is
roundtrip-verified through the JSON model before replacing the original.`;

const args = parseArgs({
  allowPositionals: true,
  options: {
    to: { type: "string", default: "deb822" },
    "dry-run": { type: "boolean" },
    out: { type: "string" },
    force: { type: "boolean" },
    help: { type: "boolean", short: "h" },
  },
});
if (args.values.help) {
  console.log(USAGE);
  process.exit(0);
}
if (args.values.to !== "classic" && args.values.to !== "deb822") {
  console.error(`error: --to must be 'classic' or 'deb822', not '${args.values.to}'`);
  process.exit(2);
}

const dir = args.positionals[0] ?? "/etc/apt/sources.list.d";
const target = args.values.to;
const targetExt = target === "deb822" ? ".sources" : ".list";
const sourceExt = target === "deb822" ? ".list" : ".sources";

function parseAs(ext: string, text: string, path: string) {
  try {
    return ext === ".sources" ? parseDeb822(text) : parseClassic(text);
  } catch (err) {
    if (err instanceof AptParseError)
      throw new Error(`${path}: ${err.message}`);
    throw err;
  }
}

function emitAs(ext: string, json: ReturnType<typeof canonical>): string {
  return ext === ".sources" ? emitDeb822(json) : emitClassic(json);
}

async function main(): Promise<number> {
  let entries: string[];
  try {
    entries = (await readdir(dir)).sort();
  } catch (err) {
    console.error(`error: cannot read directory ${dir}: ${(err as Error).message}`);
    return 1;
  }

  let failures = 0;
  for (const name of entries) {
    const path = join(dir, name);

    if (!name.endsWith(".list") && !name.endsWith(".sources")) continue;
    const ext = name.endsWith(".sources") ? ".sources" : ".list";
    if (ext === targetExt) continue; // already in the target format

    let stat;
    try {
      stat = await lstat(path);
    } catch (err) {
      console.error(`error: ${path}: ${(err as Error).message}`);
      failures++;
      continue;
    }
    if (stat.isSymbolicLink()) {
      console.warn(`skip: ${path} is a symlink (managed elsewhere)`);
      continue;
    }

    const destName = name.slice(0, -ext.length) + targetExt;
    const destPath = args.values.out ? join(args.values.out, destName) : join(dir, destName);
    const verb = args.values.out
      ? `convert ${path} (${ext === ".list" ? "classic" : "deb822"} -> ${target}) -> ${destPath}`
      : `convert ${path} (${ext === ".list" ? "classic" : "deb822"} -> ${target}), replacing with ${destPath}`;

    let text: string;
    try {
      text = await readFile(path, "utf8");
    } catch (err) {
      console.error(`error: ${path}: ${(err as Error).message}`);
      failures++;
      continue;
    }

    let json: ReturnType<typeof canonical>;
    try {
      json = canonical(parseAs(ext, text, path));
    } catch (err) {
      console.error(`error: ${(err as Error).message}`);
      failures++;
      continue;
    }

    // verify: re-parse what we would write and canonical-compare
    let out: string;
    try {
      out = emitAs(targetExt, json);
      const reparsed = canonical(parseAs(targetExt, out, `${path} (emitted)`));
      if (JSON.stringify(reparsed) !== JSON.stringify(json))
        throw new Error(`${path}: emitted ${target} does not roundtrip to the same JSON; refusing`);
    } catch (err) {
      console.error(`error: ${(err as Error).message}`);
      failures++;
      continue;
    }

    // destination checks
    let destExists = false;
    let destSame = false;
    try {
      const existing = await readFile(destPath, "utf8");
      destExists = true;
      destSame = existing === out;
    } catch {
      /* destination absent: fine */
    }
    if (destExists) {
      if (!destSame && !args.values.force) {
        console.error(
          `refuse: ${destPath} already exists and differs; use --force to overwrite`,
        );
        failures++;
        continue;
      }
      if (destSame && !args.values.out) {
        // conversion already complete on disk; finishing it just removes the source
        if (args.values["dry-run"]) {
          console.log(`would remove ${path} (${destPath} already holds the identical conversion)`);
          continue;
        }
        console.log(`${verb} (destination already identical; removing source)`);
        await rm(path);
        continue;
      }
    }

    if (args.values["dry-run"]) {
      console.log(`would ${verb}`);
      continue;
    }

    try {
      if (args.values.out) await mkdir(args.values.out, { recursive: true });
      await writeFile(destPath, out, "utf8");
      if (!args.values.out) await rm(path);
      console.log(verb);
    } catch (err) {
      console.error(`error: ${(err as Error).message}`);
      failures++;
    }
  }

  return failures ? 1 : 0;
}

const code = await main();
process.exitCode = code;
