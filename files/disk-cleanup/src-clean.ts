#!/usr/bin/env node
/**
 * src-clean.ts — ~/src disk-reclaim report and cleaner. DRY-RUN BY DEFAULT.
 *
 * After the 2026-10-01 root-fs-full incident (btrfs / hit 100%, k3s crash
 * looped on etcd fsync starvation), this captures the recurring ad-hoc
 * ~/src cleanup as a reviewable, report-first tool. In default mode it
 * only walks, measures, and prints what it WOULD do; `--apply` is the
 * single key that unlocks deletion. There is no code path that deletes
 * without `--apply`.
 *
 * What it targets:
 *   Rust:   cargo target/ INNARDS, never whole target/ trees —
 *             target/<profile>/incremental/   (debug + release + custom)
 *             target/package/, target/doc/
 *           A target/ dir only counts when a Cargo.toml sits beside it.
 *           `--rust-aggressive` additionally targets
 *             target/<profile>/deps/, build/, .fingerprint/
 *           which FORCES FULL REBUILDS of every project it touches —
 *           next cargo build recompiles everything, redownloads nothing.
 *   Node:   whole node_modules/ trees (traversal prunes at the first one;
 *           a nested node_modules is unreachable anyway once the outer
 *           tree goes).
 *
 * pnpm semantics (why node_modules deletion can "free nothing"):
 *   pnpm node_modules are hardlinks/reflinks into a content-addressable
 *   store (`pnpm store path`). Unlinking a project's node_modules drops
 *   directory entries, not the store's blocks — freed space stays ~0 until
 *   the store itself is pruned. The flip side: re-running pnpm install
 *   after deleting only node_modules is cheap (re-link, no re-download)
 *   as long as the store still holds the content. So the report keeps
 *   "space freed by unlinking" and "space freed by store prune" separate,
 *   and `--pnpm-store-prune` (apply-mode only) runs `pnpm store prune`
 *   after node_modules removal to actually release bytes.
 *
 * Sizes are block usage (du -s style: st_blocks × 512), an UPPER bound on
 * what unlinking frees — hardlinked/reflinked content shared with the
 * pnpm store (or other checkouts) is not freed by removal alone.
 *
 * Walk bounds: skips .git/.jj internals, prunes at node_modules/target,
 * caps depth (--max-depth, default 6), and counts unreadable (EACCES)
 * directories quietly instead of failing.
 *
 * Usage:
 *   src-clean.ts [--root <dir>] [--max-depth N] [--rust-aggressive]
 *   src-clean.ts --apply [--rust-aggressive] [--pnpm-store-prune]
 *
 * Exit: 0 ok, 1 runtime failure, 2 usage error.
 */

import { spawn } from "node:child_process";
import { lstat, readdir, rm, rmdir, stat } from "node:fs/promises";
import { homedir } from "node:os";
import { basename, join } from "node:path";
import { parseArgs } from "node:util";
import type { Dirent } from "node:fs";

const PROG = "src-clean.ts";
const DEFAULT_MAX_DEPTH = 6;
/** Directory names never descended into (VCS internals). */
const SKIP_DIR_NAMES: ReadonlySet<string> = new Set([".git", ".jj"]);
/** Cargo target/ children handled directly at the target level. */
const RUST_TARGET_TOP: readonly string[] = ["package", "doc"];
/** target/<profile>/ innards removed in the default (safe) mode. */
const RUST_PROFILE_INNARDS: readonly string[] = ["incremental"];
/** target/<profile>/ innards additionally removed by --rust-aggressive. */
const RUST_AGGRESSIVE_INNARDS: readonly string[] = ["deps", "build", ".fingerprint"];

type Category = "rust-safe" | "rust-aggressive" | "node-modules";

interface Candidate {
	category: Category;
	/** Absolute path of the directory that would be removed. */
	path: string;
	/** Block-usage bytes (upper bound on reclaim). */
	bytes: bigint;
	/** node_modules/.pnpm present — pnpm-managed, store-linked tree. */
	pnpm: boolean;
	/** Measurement walk hit permission/IO errors; size is a lower bound. */
	partial: boolean;
}

/** Profile/target bookkeeping for post-removal `rmdir` candidates. */
interface TargetLayout {
	/** Absolute target/ path. */
	target: string;
	/** Entry names directly under target/. */
	targetEntries: readonly string[];
	/** Non-candidate entry names per profile dir under target/. */
	profiles: ReadonlyArray<{ path: string; entries: readonly string[] }>;
}

interface DiscoverResult {
	candidates: readonly Candidate[];
	targets: readonly TargetLayout[];
	unreadable: number;
	pruned: number;
}

interface DuOutcome {
	bytes: bigint;
	errors: number;
}

class UsageError extends Error {
	readonly code = 2;
}

function usage(): string {
	return `usage: ${PROG} [options]

Walk a source tree (default $HOME/src), report reclaimable build-artifact
space, and optionally remove it. DRY-RUN BY DEFAULT: nothing is deleted
without --apply.

options:
  --apply              actually remove candidates (destructive)
  --root <dir>         scan root (default: $HOME/src)
  --max-depth <n>      directory depth cap for the walk (default ${DEFAULT_MAX_DEPTH})
  --rust-aggressive    also remove target/<profile>/{deps,build,.fingerprint};
                       FORCES FULL REBUILDS — next cargo build recompiles
                       every touched project from scratch
  --pnpm-store-prune   with --apply only: run \`pnpm store prune\` after
                       node_modules removal to release store bytes
  --help               this help

what is removed:
  rust (default):    target/<profile>/incremental/, target/package/,
                     target/doc/ — target/ itself is kept, so incremental
                     metadata and packaging caches go but the build tree
                     skeleton and most artifacts survive
  rust (aggressive): additionally target/<profile>/{deps,build,.fingerprint}
                     — cheap on disk, expensive later: full recompile
  node:              whole node_modules/ trees

pnpm semantics:
  pnpm node_modules are hardlinks/reflinks into the content-addressable
  pnpm store. Deleting node_modules frees almost nothing until the store
  is pruned; conversely, re-install after only deleting node_modules is
  cheap (re-link, no re-download) while the store still holds the content.
  The report separates "space freed by unlinking" from "space freed by
  store prune" for exactly this reason.

sizes are block usage and upper bounds: content shared with the pnpm
store or other checkouts (hardlinks/reflinks) is not freed by unlinking.`;
}

function human(bytes: bigint): string {
	const units = ["B", "KiB", "MiB", "GiB", "TiB", "PiB"];
	let value = Number(bytes);
	let unit = 0;
	while (value >= 1024 && unit < units.length - 1) {
		value /= 1024;
		unit++;
	}
	return unit === 0 ? `${value} ${units[unit]}` : `${value.toFixed(1)} ${units[unit]}`;
}

/** Capture a command's stdout, bounded by a timeout; null on any failure. */
function capture(command: string, args: readonly string[], timeoutMs: number): Promise<string | null> {
	return new Promise((resolve) => {
		let child;
		try {
			child = spawn(command, args, { stdio: ["ignore", "pipe", "ignore"] });
		} catch {
			resolve(null);
			return;
		}
		let out = "";
		const timer = setTimeout(() => child.kill("SIGKILL"), timeoutMs);
		child.stdout?.on("data", (chunk: Buffer) => {
			out += chunk.toString("utf8");
		});
		child.on("error", () => {
			clearTimeout(timer);
			resolve(null);
		});
		child.on("close", (code) => {
			clearTimeout(timer);
			resolve(code === 0 ? out : null);
		});
	});
}

/** Run a command inheriting stdio; resolve to its exit code (never rejects). */
function run(command: string, args: readonly string[]): Promise<number | null> {
	return new Promise((resolve) => {
		let child;
		try {
			child = spawn(command, args, { stdio: "inherit" });
		} catch (error) {
			console.error(`${PROG}: failed to spawn ${command}:`, error);
			resolve(1);
			return;
		}
		child.on("error", (error) => {
			console.error(`${PROG}: ${command}:`, error);
			resolve(1);
		});
		child.on("close", (code) => resolve(code));
	});
}

/**
 * Block-usage size of a subtree, du -s style: st_blocks × 512 per inode,
 * hardlinks counted once per traversal (parity with du within one tree).
 * Read errors are counted, not thrown.
 */
async function duBytes(rootPath: string): Promise<DuOutcome> {
	let bytes = 0n;
	let errors = 0;
	const seen = new Set<string>();
	const walk = async (dir: string): Promise<void> => {
		let entries: Dirent[];
		try {
			entries = await readdir(dir, { withFileTypes: true });
		} catch {
			errors++;
			return;
		}
		await Promise.all(
			entries.map(async (entry) => {
				const entryPath = join(dir, entry.name);
				try {
					const info = await lstat(entryPath);
					if (info.nlink > 1) {
						const key = `${info.dev}:${info.ino}`;
						if (seen.has(key)) return;
						seen.add(key);
					}
					bytes += BigInt(info.blocks ?? 0) * 512n;
					if (info.isDirectory()) await walk(entryPath);
				} catch {
					errors++;
				}
			}),
		);
	};
	try {
		const info = await lstat(rootPath);
		bytes += BigInt(info.blocks ?? 0) * 512n;
		if (info.isDirectory()) await walk(rootPath);
	} catch {
		errors++;
	}
	return { bytes, errors };
}

async function isRealDir(path: string): Promise<boolean> {
	try {
		return (await lstat(path)).isDirectory();
	} catch {
		return false;
	}
}

async function measureCandidate(category: Category, path: string): Promise<Candidate> {
	const pnpm = category === "node-modules" && (await isRealDir(join(path, ".pnpm")));
	const { bytes, errors } = await duBytes(path);
	return { category, path, bytes, pnpm, partial: errors > 0 };
}

async function discover(
	root: string,
	maxDepth: number,
	rustAggressive: boolean,
): Promise<DiscoverResult> {
	const candidates: Candidate[] = [];
	const targets: TargetLayout[] = [];
	let unreadable = 0;
	let pruned = 0;

	// A root that is itself a node_modules is one candidate, not a tree to
	// mine for nested ones (.pnpm package dirs each carry node_modules).
	if (basename(root) === "node_modules") {
		pruned++;
		candidates.push(await measureCandidate("node-modules", root));
		return { candidates, targets, unreadable, pruned };
	}

	/** Scan a cargo target/ dir for removable innards (never whole target/). */
	const handleTarget = async (target: string): Promise<void> => {
		pruned++;
		let children: Dirent[];
		try {
			children = await readdir(target, { withFileTypes: true });
		} catch {
			unreadable++;
			return;
		}
		const layout: TargetLayout = { target, targetEntries: children.map((c) => c.name), profiles: [] };
		for (const child of children) {
			if (!child.isDirectory()) continue;
			const childPath = join(target, child.name);
			if (RUST_TARGET_TOP.includes(child.name)) {
				candidates.push(await measureCandidate("rust-safe", childPath));
				continue;
			}
			// Profile dir: target/debug, target/release, custom profiles.
			let innards: Dirent[];
			try {
				innards = await readdir(childPath, { withFileTypes: true });
			} catch {
				unreadable++;
				continue;
			}
			const profileLayout = { path: childPath, entries: innards.map((i) => i.name) };
			layout.profiles.push(profileLayout);
			for (const innard of innards) {
				if (!innard.isDirectory()) continue;
				const innardPath = join(childPath, innard.name);
				if (RUST_PROFILE_INNARDS.includes(innard.name)) {
					candidates.push(await measureCandidate("rust-safe", innardPath));
				} else if (rustAggressive && RUST_AGGRESSIVE_INNARDS.includes(innard.name)) {
					candidates.push(await measureCandidate("rust-aggressive", innardPath));
				}
			}
		}
		targets.push(layout);
	};

	const visitDir = async (dir: string, depth: number): Promise<void> => {
		let entries: Dirent[];
		try {
			entries = await readdir(dir, { withFileTypes: true });
		} catch {
			unreadable++;
			return;
		}
		// Cargo target/ only counts with a sibling Cargo.toml: a random
		// directory named "target" must not be mined for rust innards.
		const cargoRoot = entries.some((entry) => entry.name === "Cargo.toml" && entry.isFile());
		await Promise.all(
			entries.map(async (entry) => {
				if (SKIP_DIR_NAMES.has(entry.name)) return;
				if (!entry.isDirectory()) return;
				const entryPath = join(dir, entry.name);
				if (entry.name === "node_modules") {
					pruned++;
					candidates.push(await measureCandidate("node-modules", entryPath));
					return;
				}
				if (entry.name === "target" && cargoRoot) {
					await handleTarget(entryPath);
					return;
				}
				if (depth + 1 <= maxDepth) await visitDir(entryPath, depth + 1);
			}),
		);
	};

	await visitDir(root, 0);
	return { candidates, targets, unreadable, pruned };
}

interface PnpmStoreInfo {
	/** Resolved store path, or null when pnpm is absent/failed. */
	path: string | null;
	/** Store size in bytes from bounded `du -s -B1`, or null when unknown. */
	bytes: bigint | null;
	duBounded: boolean;
}

async function inspectPnpmStore(): Promise<PnpmStoreInfo> {
	const path = await capture("pnpm", ["store", "path"], 10_000);
	if (path === null) return { path: null, bytes: null, duBounded: false };
	const storePath = path.trim();
	if (!storePath) return { path: null, bytes: null, duBounded: false };
	const du = await capture("du", ["-s", "-B1", storePath], 60_000);
	if (du === null) return { path: storePath, bytes: null, duBounded: true };
	const tokens = du.trim().split(/\s+/);
	const kilobytes = Number.parseInt(tokens[0] ?? "", 10);
	return {
		path: storePath,
		bytes: Number.isFinite(kilobytes) ? BigInt(kilobytes) : null,
		duBounded: true,
	};
}

/**
 * Dirs that would be empty after candidate removal: `rmdir --ignore-fail-
 * on-non-empty` semantics — attempted, quietly skipped when not empty.
 */
function emptyAfterRemoval(result: DiscoverResult): string[] {
	const removed = new Set(result.candidates.map((candidate) => candidate.path));
	const rmdirs: string[] = [];
	const emptiedTargets = new Set<string>();
	for (const { path, entries } of result.targets.flatMap((target) => target.profiles)) {
		if (entries.length > 0 && entries.every((name) => removed.has(join(path, name)))) {
			rmdirs.push(path);
			emptiedTargets.add(path);
		}
	}
	for (const target of result.targets) {
		if (target.targetEntries.length === 0) continue;
		const clears = target.targetEntries.every((name) => {
			const entryPath = join(target.target, name);
			return removed.has(entryPath) || emptiedTargets.has(entryPath);
		});
		if (clears) rmdirs.push(target.target);
	}
	return rmdirs;
}

function report(
	root: string,
	result: DiscoverResult,
	store: PnpmStoreInfo,
	opts: { maxDepth: number; rustAggressive: boolean; pnpmStorePrune: boolean },
): string {
	const lines: string[] = [];
	const byCategory = new Map<Category, Candidate[]>();
	for (const candidate of result.candidates) {
		const bucket = byCategory.get(candidate.category) ?? [];
		bucket.push(candidate);
		byCategory.set(candidate.category, bucket);
	}
	const total = result.candidates.reduce((sum, candidate) => sum + candidate.bytes, 0n);

	lines.push(`${PROG}: DRY RUN (no --apply) — nothing will be deleted`);
	lines.push(`root: ${root}  max-depth: ${opts.maxDepth}  rust-aggressive: ${opts.rustAggressive ? "on" : "off"}`);
	lines.push("");
	lines.push("candidates:");
	if (result.candidates.length === 0) {
		lines.push("  (none found)");
	} else {
		lines.push("       SIZE  CATEGORY           PATH");
		const sorted = [...result.candidates].sort((a, b) => (a.bytes < b.bytes ? 1 : a.bytes > b.bytes ? -1 : 0));
		for (const candidate of sorted) {
			const note =
				candidate.pnpm ? "  [pnpm: store-linked]" : candidate.partial ? "  [partial: size is a lower bound]" : "";
			lines.push(
				`${human(candidate.bytes).padStart(10)}  ${candidate.category.padEnd(17)}  ${candidate.path}${note}`,
			);
		}
	}
	lines.push("");
	lines.push("totals — space freed by unlinking (UPPER bound; see pnpm semantics in --help):");
	const order: Category[] = ["rust-safe", "rust-aggressive", "node-modules"];
	for (const category of order) {
		const bucket = byCategory.get(category);
		if (!bucket) continue;
		const sum = bucket.reduce((acc, candidate) => acc + candidate.bytes, 0n);
		lines.push(`  ${category.padEnd(17)} ${human(sum).padStart(10)}  (${bucket.length} dir${bucket.length === 1 ? "" : "s"})`);
	}
	lines.push(`  ${"total".padEnd(17)} ${human(total).padStart(10)}`);
	lines.push("");
	lines.push("pnpm store:");
	if (store.path === null) {
		lines.push("  not detected (no pnpm on PATH, or `pnpm store path` failed)");
	} else {
		const size = store.bytes === null ? "unknown (du failed or exceeded its 60s bound)" : human(store.bytes);
		lines.push(`  store path: ${store.path} (size ${size}, via bounded du -s)`);
		if (store.bytes !== null) {
			lines.push(`  space freed by \`pnpm store prune\`: up to ${human(store.bytes)} (upper bound —`);
			lines.push("    prune releases only packages no longer referenced by any project)");
		}
		lines.push("  note: unlinking store-linked node_modules frees ~0 by itself; the store");
		lines.push("        prune is what releases bytes, and it only counts after projects");
		lines.push("        stopped referencing the content (i.e. after node_modules removal).");
	}
	lines.push("");
	lines.push(`skipped: ${result.unreadable} unreadable dir(s) (quiet), ${result.pruned} pruned subtree(s) (node_modules/target)`);
	lines.push("");
	lines.push("commands that would run (with --apply):");
	const removals = [...result.candidates].map((candidate) => `rm -rf -- ${candidate.path}`);
	lines.push(...(removals.length > 0 ? removals.map((line) => `  ${line}`) : ["  (nothing to remove)"]));
	for (const dir of emptyAfterRemoval(result)) {
		lines.push(`  rmdir --ignore-fail-on-non-empty -- ${dir}`);
	}
	if (opts.pnpmStorePrune) lines.push("  pnpm store prune");
	return lines.join("\n");
}

async function main(argv: string[]): Promise<number> {
	const { values } = parseArgs({
		args: argv,
		options: {
			apply: { type: "boolean", default: false },
			root: { type: "string" },
			"rust-aggressive": { type: "boolean", default: false },
			"pnpm-store-prune": { type: "boolean", default: false },
			"max-depth": { type: "string" },
			help: { type: "boolean", default: false },
		},
	});
	if (values.help) {
		console.log(usage());
		return 0;
	}
	if (values["pnpm-store-prune"] && !values.apply) {
		throw new UsageError("--pnpm-store-prune is apply-mode only; add --apply (this tool dry-runs by default)");
	}
	const maxDepthRaw = values["max-depth"] ?? String(DEFAULT_MAX_DEPTH);
	const maxDepth = Number.parseInt(maxDepthRaw, 10);
	if (!Number.isInteger(maxDepth) || maxDepth < 1 || maxDepth > 64) {
		throw new UsageError(`--max-depth expects an integer 1..64 (got "${maxDepthRaw}")`);
	}
	const rootPath = values.root ?? join(homedir(), "src");
	try {
		const rootStat = await stat(rootPath);
		if (!rootStat.isDirectory()) {
			throw new UsageError(`--root is not a directory: ${rootPath}`);
		}
	} catch (error) {
		if (error instanceof UsageError) throw error;
		throw new UsageError(`--root is unreadable or missing: ${rootPath} (${(error as NodeJS.ErrnoException).code ?? error})`);
	}

	const result = await discover(rootPath, maxDepth, values["rust-aggressive"] ?? false);
	const store = await inspectPnpmStore();

	if (!values.apply) {
		console.log(report(rootPath, result, store, {
			maxDepth,
			rustAggressive: values["rust-aggressive"] ?? false,
			pnpmStorePrune: values["pnpm-store-prune"] ?? false,
		}));
		return 0;
	}

	console.log(`${PROG}: APPLY — removing ${result.candidates.length} candidate(s) under ${rootPath}`);
	for (const candidate of result.candidates) {
		await rm(candidate.path, { recursive: true, force: true });
		console.log(`removed ${human(candidate.bytes).padStart(10)}  ${candidate.path}`);
	}
	for (const dir of emptyAfterRemoval(result)) {
		await rmdir(dir).catch(() => {
			// --ignore-fail-on-non-empty parity: leftover files keep the dir.
		});
	}
	if (values["pnpm-store-prune"]) {
		console.log(`${PROG}: running pnpm store prune (releases store bytes no project references)`);
		const code = await run("pnpm", ["store", "prune"]);
		if (code !== 0) return code ?? 1;
	}
	console.log(`${PROG}: apply complete`);
	return 0;
}

try {
	const code = await main(process.argv.slice(2));
	process.exitCode = code;
} catch (error) {
	if (error instanceof UsageError) {
		console.error(`${PROG}: ${error.message}`);
		console.error(`${PROG}: try --help`);
		process.exitCode = error.code;
	} else {
		console.error(`${PROG}:`, error);
		process.exitCode = 1;
	}
}
