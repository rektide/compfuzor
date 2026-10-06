#!/usr/bin/env node
// Exercise tools/diff-configs.ts against durable fixtures already in the bundle.
//
// Covers the preserved 22-symbol 7.1 state, default metadata exclusion, the
// --keys-from fragment restriction, and mixed .xz/plain input. Results are
// written to a scratch directory under .test-agent/ (gitignored) and removed on
// success; a failure keeps them in place for diagnosis. This is a maintenance
// test, not part of any automatic test run.
//
// Ported from run.py with identical assertions. The diff tool runs through
// this Node binary, so the exercised code path is exactly `node <tool>.ts`.

import { spawnSync } from "node:child_process";
import { mkdirSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { basename, dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import assert from "node:assert/strict";

const HERE = dirname(fileURLToPath(import.meta.url));               // tests/tools
const BUNDLE = resolve(HERE, "..", "..");
const TOOL = join(BUNDLE, "tools", "diff-configs.ts");
const RUNNING = join(BUNDLE, "baselines/7.1/config-running.xz");
const SEED_ARCHIVE = join(BUNDLE, "archive/previous-normalization/config-debian-plus.7.1.0.xz");
const FRAGMENT = join(BUNDLE, "overrides.config");
const DEFCONFIG = join(BUNDLE, "baselines/7.3/config-upstream-defconfig.xz");
const CURRENT = join(BUNDLE, "config-debian-plus.xz");

// The preserved 22 symbol states between the exact running 7.1 configuration
// and the saved seed (which equals the old checkout's .config.old), as
// recorded in the bundle README and baselines/7.1/README.md: Rust support and
// availability, Rust-dependent drivers/panic-QR options, one compiler
// capability probe, and three toolchain metadata symbols. The transitions
// below run old=running config, new=saved seed, matching the invocation order.
const PRESERVED_22 = new Set([
  "AMCC_QT2025_PHY", "ANDROID_BINDER_IPC_RUST", "AX88796B_RUST_PHY",
  "BINDGEN_VERSION_TEXT", "BLK_DEV_RUST_NULL", "CC_HAS_KCFI_ARITY",
  "DRM_PANIC_SCREEN_QR_CODE", "DRM_PANIC_SCREEN_QR_CODE_URL",
  "DRM_PANIC_SCREEN_QR_VERSION", "FIND_BIT_BENCHMARK_RUST", "NOVA_CORE",
  "RUST", "RUST_BITMAP_HARDENED", "RUST_BUILD_ASSERT_ALLOW",
  "RUST_DEBUG_ASSERTIONS", "RUST_FW_LOADER_ABSTRACTIONS",
  "RUST_IS_AVAILABLE", "RUST_OVERFLOW_CHECKS", "RUST_PHYLIB_ABSTRACTIONS",
  "RUSTC_LLVM_VERSION", "RUSTC_VERSION", "RUSTC_VERSION_TEXT",
]);
// The subset of PRESERVED_22 that the default metadata exclusion must hide.
const METADATA_SYMBOLS = new Set(["RUSTC_LLVM_VERSION", "RUSTC_VERSION", "RUSTC_VERSION_TEXT"]);

function runTool(...arguments_: string[]): string[] {
  const result = spawnSync(process.execPath, [TOOL, ...arguments_], { encoding: "utf8", maxBuffer: 1 << 26 });
  assert.equal(result.status, 0, result.stderr);
  return result.stdout.split("\n").filter((line) => line !== "");
}

function symbols(lines: string[]): Set<string> {
  return new Set(lines.map((line) => line.split(":", 1)[0]));
}

function transitions(lines: string[]): Map<string, [string, string]> {
  const changes = new Map<string, [string, string]>();
  for (const line of lines) {
    const head = line.slice(0, line.indexOf(": "));
    const tail = line.slice(line.indexOf(": ") + 2);
    const arrow = tail.indexOf(" -> ");
    changes.set(head, [tail.slice(0, arrow), tail.slice(arrow + 4)]);
  }
  return changes;
}

/** Fragment symbol names, treating "# ... is not set" as declared too. */
function declaredSymbols(text: string): Set<string> {
  const found = new Set<string>();
  for (const line of text.split("\n")) {
    if (line.startsWith("CONFIG_")) {
      found.add(line.split("=", 1)[0].slice("CONFIG_".length));
    } else if (line.startsWith("# CONFIG_") && line.endsWith(" is not set")) {
      found.add(line.slice("# CONFIG_".length, -" is not set".length));
    }
  }
  return found;
}

function runTests(scratch: string): void {
  // The preserved 22-state shape, metadata included (recorded count).
  const included = runTool(RUNNING, SEED_ARCHIVE, "--include-metadata");
  writeFileSync(join(scratch, "running-vs-seed-22.txt"), `${included.join("\n")}\n`);
  assert.equal(included.length, 22, `expected 22 differences, got ${included.length}`);
  assert.deepEqual(symbols(included), PRESERVED_22,
    [...new Set([...symbols(included), ...PRESERVED_22])].filter(
      (symbol) => symbols(included).has(symbol) !== PRESERVED_22.has(symbol)).sort());

  // Default output excludes toolchain metadata symbols; exactly the
  // 19 non-metadata states of the same preserved shape remain.
  const standard = runTool(RUNNING, SEED_ARCHIVE);
  writeFileSync(join(scratch, "running-vs-seed-default.txt"), `${standard.join("\n")}\n`);
  assert.equal(standard.length, 19, `expected 19 differences, got ${standard.length}`);
  const expectedDefault = new Set([...PRESERVED_22].filter((symbol) => !METADATA_SYMBOLS.has(symbol)));
  assert.deepEqual(symbols(standard), expectedDefault);

  // --keys-from restricts the comparison to symbols declared in the
  // fragment; the defconfig->current pair then shows only declared policy.
  const fragment = runTool(DEFCONFIG, CURRENT, "--keys-from", FRAGMENT);
  writeFileSync(join(scratch, "defconfig-keys-from-overrides.txt"), `${fragment.join("\n")}\n`);
  assert.ok(fragment.length > 0, "expected declared-policy differences against the defconfig");
  const fragmentText = readFileSync(FRAGMENT, "utf8");
  assert.deepEqual(
    [...symbols(fragment)].filter((symbol) => !declaredSymbols(fragmentText).has(symbol)).sort(), [],
    [...symbols(fragment)].filter((symbol) => !declaredSymbols(fragmentText).has(symbol)).sort());
  const changes = transitions(fragment);
  const expectations: [string, [string, string]][] = [
    ["X86_NATIVE_CPU", ["n", "y"]],
    ["DEFAULT_TCP_CONG", ['"cubic"', '"bbr"']],
    ["RUST", ["n", "y"]],
  ];
  for (const [symbol, expected] of expectations) {
    assert.deepEqual(changes.get(symbol), expected, `${symbol}: ${JSON.stringify(changes.get(symbol))}`);
  }

  // The full defconfig->current keymap stays pinned at the 7461 differing
  // entries recorded in baselines/7.3/README.md (the recorded audit counts
  // RUSTC_VERSION_TEXT, so --include-metadata matches its keymap exactly).
  // A regenerated saved config that grows or shrinks the Debian-plus delta
  // fails here instead of drifting silently. Spot-anchor the deliberate
  // overrides, including built-in zswap zstd (zswap.etc.pb policy).
  const full = runTool(DEFCONFIG, CURRENT, "--include-metadata");
  writeFileSync(join(scratch, "defconfig-vs-current-full.txt"), `${full.join("\n")}\n`);
  assert.equal(full.length, 7461, `expected 7461 differences, got ${full.length}`);
  const fullChanges = transitions(full);
  const fullExpectations: [string, [string, string]][] = [
    ["CRYPTO_ZSTD", ["n", "y"]],
    ["X86_NATIVE_CPU", ["n", "y"]],
    ["DEFAULT_TCP_CONG", ['"cubic"', '"bbr"']],
    ["RUST", ["n", "y"]],
  ];
  for (const [symbol, expected] of fullExpectations) {
    assert.deepEqual(fullChanges.get(symbol), expected, `${symbol}: ${JSON.stringify(fullChanges.get(symbol))}`);
  }

  // Mixed input: the seed as decompressed plain text must yield the
  // identical comparison to its .xz container.
  const plain = join(scratch, basename(SEED_ARCHIVE).replace(/\.[^.]*$/, ""));
  writeFileSync(plain, xzDecompress(readFileSync(SEED_ARCHIVE)));
  const mixed = runTool(RUNNING, plain, "--include-metadata");
  writeFileSync(join(scratch, "running-vs-seed-plain.txt"), `${mixed.join("\n")}\n`);
  assert.deepEqual(mixed, included, "plain-text input changed the comparison");
}

function xzDecompress(data: Buffer): Buffer {
  const result = spawnSync("xz", ["-dc"], { input: data, maxBuffer: 1 << 30 });
  if (result.error) throw result.error;
  if (result.status !== 0) {
    throw new Error(`xz -dc failed with status ${result.status}: ${result.stderr.toString()}`);
  }
  return result.stdout;
}

// ---------------------------------------------------------------------------
// Minimal CLI layer reproducing Python argparse's rendered output.
// ---------------------------------------------------------------------------

const DESCRIPTION = `Exercise tools/diff-configs.ts against durable fixtures already in the bundle.
Covers the preserved 22-symbol 7.1 state, default metadata exclusion, the
--keys-from fragment restriction, and mixed .xz/plain input. Results are
written to a scratch directory under .test-agent/ (gitignored) and removed on
success; a failure keeps them in place for diagnosis. This is a maintenance
test, not part of any automatic test run.`;

interface HelpEntry {
  invocation: string;
  help?: string;
}

function terminalWidth(): number {
  const columns = process.env.COLUMNS;
  if (columns !== undefined && /^\d+$/.test(columns)) return Math.max(parseInt(columns, 10), 1) - 2;
  return (process.stdout.columns ?? 80) - 2;
}

function wrapText(text: string, width: number): string[] {
  const chunks: string[] = [];
  for (const token of text.split(/(\s+)/)) {
    if (token === "") continue;
    if (/^\s+$/.test(token)) {
      chunks.push(" ");
      continue;
    }
    let start = 0;
    for (let index = 1; index < token.length - 1; index += 1) {
      const boundary = token[index] === "-" && /[A-Za-z]/.test(token[index - 1]) &&
        /[A-Za-z0-9]/.test(token[index + 1]);
      if (boundary) {
        chunks.push(token.slice(start, index + 1));
        start = index + 1;
      }
    }
    chunks.push(token.slice(start));
  }
  const lines: string[] = [];
  while (chunks.length > 0) {
    const line: string[] = [];
    let length = 0;
    while (chunks.length > 0) {
      const chunk = chunks[0];
      if (line.length === 0 && /^\s+$/.test(chunk)) {
        chunks.shift();
        continue;
      }
      if (length + chunk.length <= width) {
        line.push(chunks.shift()!);
        length += chunk.length;
      } else {
        break;
      }
    }
    if (chunks.length > 0 && chunks[0].length > width) {
      const spaceLeft = Math.max(width - length, 1);
      line.push(chunks[0].slice(0, spaceLeft));
      chunks[0] = chunks[0].slice(spaceLeft);
    }
    while (line.length > 0 && line[line.length - 1].trim() === "") line.pop();
    if (line.length > 0) lines.push(line.join(""));
  }
  return lines;
}

function usage(prog: string, width: number): string {
  const prefix = "usage: ";
  const parts = ["[-h]", "[--scratch-dir SCRATCH_DIR]"];
  const line = `${prefix}${prog} ${parts.join(" ")}`;
  if (line.length <= width) return line;
  const indent = " ".repeat(prefix.length + prog.length + 1);
  return `${prefix}${prog} [-h]\n${indent}[--scratch-dir SCRATCH_DIR]`;
}

function buildHelp(prog: string): string {
  const width = terminalWidth();
  const entries: HelpEntry[] = [
    { invocation: "-h, --help", help: "show this help message and exit" },
    { invocation: "--scratch-dir SCRATCH_DIR", help: "temporary test root (default: cwd/.test-agent/linux-debplus-tools)" },
  ];
  const helpPosition = Math.min(
    Math.max(...entries.map((entry) => entry.invocation.length + 2)) + 2,
    Math.min(24, Math.max(width - 20, 4)));
  let out = usage(prog, width) + "\n\n";
  out += wrapText(DESCRIPTION.replace(/\s+/g, " ").trim(), width).join("\n") + "\n\n";
  out += "\noptions:\n";
  out += entries.map((entry) => {
    const helpWidth = Math.max(width - helpPosition, 11);
    const helpLines = wrapText(entry.help!.replace(/\s+/g, " ").trim(), helpWidth);
    if (entry.invocation.length <= helpPosition - 4) {
      return "  " + entry.invocation.padEnd(helpPosition - 4) + "  " +
        helpLines.join("\n" + " ".repeat(helpPosition)) + "\n";
    }
    return `  ${entry.invocation}\n` +
      helpLines.map((line) => " ".repeat(helpPosition) + line).join("\n") + "\n";
  }).join("");
  return out.replace(/\n{3,}/g, "\n\n").replace(/\n+$/, "") + "\n";
}

// ---------------------------------------------------------------------------

function main(argv: string[]): void {
  const prog = basename(process.argv[1] ?? "run.ts");
  let scratchDir: string | null = null;
  for (let index = 0; index < argv.length; index += 1) {
    const argument = argv[index];
    if (argument === "-h" || argument === "--help") {
      process.stdout.write(buildHelp(prog));
      process.exit(0);
    }
    if (argument === "--scratch-dir") {
      const value = argv[++index];
      if (value === undefined || value.startsWith("-")) {
        process.stderr.write(usage(prog, terminalWidth()) + "\n" +
          `${prog}: error: argument --scratch-dir: expected one argument\n`);
        process.exit(2);
      }
      scratchDir = value;
    } else {
      process.stderr.write(usage(prog, terminalWidth()) + "\n" +
        `${prog}: error: unrecognized arguments: ${argument}\n`);
      process.exit(2);
    }
  }
  const scratch = resolve(scratchDir ?? join(process.cwd(), ".test-agent/linux-debplus-tools"));
  mkdirSync(scratch, { recursive: true });
  try {
    runTests(scratch);
  } catch (error) {
    process.stderr.write(`results kept for diagnosis: ${scratch}\n`);
    throw error;
  }
  rmSync(scratch, { recursive: true, force: true });
}

// Run only when executed directly. The realpath comparison resolves symlinks
// so the tool also runs correctly through a symlinked invocation path.
import { realpath } from "node:fs/promises";
realpath(process.argv[1] ?? "").then((self) => {
  if (self === fileURLToPath(import.meta.url)) main(process.argv.slice(2));
}, () => {});
