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
 * Restructured 2026-10-01 per operator decisions: the DEFAULT pass is
 * rust-safe cargo target/ innards ONLY — never whole target/ trees:
 *   target/<profile>/incremental/   (debug + release + custom profiles)
 *   target/package/, target/doc/
 * A target/ dir only counts when a Cargo.toml sits beside it.
 *
 * node_modules removal is an OPT-IN anti-feature (--node-modules): pnpm
 * node_modules are hardlinks/reflinks into a content-addressable store,
 * so deleting them frees almost nothing until the store is pruned — and
 * re-install is cheap (re-link, no re-download) only while the store
 * still holds the content. Operator-measured 2026-10-01: `pnpm store
 * prune` alone freed 6.0 GB / 140,780 files; node_modules unlinking
 * freed ~nothing by itself. The sweep is kept for the rare cases where
 * the DIRECTORY ENTRIES themselves are the problem (disk inode/dirent
 * bloat, broken trees), not space.
 *
 * The aggressive cargo sweep (target/<profile>/{deps,build,.fingerprint},
 * forces full rebuilds) moved to its own bin: rust-aggressive.ts.
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
 *   src-clean.ts [--root <dir>] [--max-depth N]
 *   src-clean.ts --apply [--node-modules] [--pnpm-store-prune]
 *
 * Exit: 0 ok, 1 runtime failure, 2 usage error.
 */

import { readdir, rm, rmdir, stat } from "node:fs/promises";
import { homedir } from "node:os";
import { basename, join } from "node:path";
import { parseArgs } from "node:util";
import type { Dirent } from "node:fs";
import { DEFAULT_MAX_DEPTH, SKIP_DIR_NAMES, UsageError, capture, duBytes, human, isErrnoError, isRealDir, run } from "./lib.ts";

const PROG = "src-clean.ts";
/** Cargo target/ children handled directly at the target level. */
const RUST_TARGET_TOP: readonly string[] = ["package", "doc"];
/** target/<profile>/ innards removed by the default (rust-safe) pass. */
const RUST_PROFILE_INNARDS: readonly string[] = ["incremental"];

type Category = "rust-safe" | "node-modules";

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
	/** Entry names per profile dir under target/. */
	profiles: ReadonlyArray<{ path: string; entries: readonly string[] }>;
}

interface DiscoverResult {
	candidates: readonly Candidate[];
	targets: readonly TargetLayout[];
	unreadable: number;
	pruned: number;
}

interface PnpmStoreInfo {
	/** Resolved store path, or null when pnpm is absent/failed. */
	path: string | null;
	/** Store size in bytes from bounded `du -s -B1`, or null when unknown. */
	bytes: bigint | null;
	duBounded: boolean;
}

function usage(): string {
	return `usage: ${PROG} [options]

Walk a source tree (default $HOME/src), report reclaimable cargo
target/ innards, and optionally remove them. DRY-RUN BY DEFAULT:
nothing is deleted without --apply.

options:
  --apply              actually remove candidates (destructive)
  --root <dir>         scan root (default: $HOME/src)
  --max-depth <n>      directory depth cap for the walk (default ${DEFAULT_MAX_DEPTH})
  --node-modules       ALSO remove whole node_modules/ trees. Opt-in
                       anti-feature: pnpm trees are store hardlinks, so
                       this rarely frees bytes (see semantics below); use
                       it for dirent/inode bloat or broken trees
  --pnpm-store-prune   with --apply only: run \`pnpm store prune\` after
                       removals to release store bytes
  --help               this help

what is removed (default pass — rust-safe only):
  target/<profile>/incremental/, target/package/, target/doc/ — target/
  itself is kept, so incremental metadata and packaging caches go but the
  build tree skeleton and most artifacts survive (next build is
  incremental-but-slower, not from-scratch). The aggressive sweep
  (deps/build/.fingerprint — FORCES FULL REBUILDS) is a separate bin:
  rust-aggressive.ts.

pnpm semantics (why --node-modules is opt-in):
  pnpm node_modules are hardlinks/reflinks into the content-addressable
  pnpm store. Deleting node_modules frees almost nothing until the store
  is pruned; conversely, re-install after only deleting node_modules is
  cheap (re-link, no re-download) while the store still holds the
  content. Measured on this host 2026-10-01: store prune freed 6.0 GB /
  140,780 files; node_modules unlinking ~nothing by itself. The report
  separates "space freed by unlinking" from "space freed by store
  prune"; the store itself is pruned weekly by the
  ${PROG.replace("src-clean.ts", "pnpm-prune")}.timer user unit.

sizes are block usage and upper bounds: content shared with the pnpm
store or other checkouts (hardlinks/reflinks) is not freed by unlinking.`;
}

async function measureCandidate(category: Category, path: string): Promise<Candidate> {
	const pnpm = category === "node-modules" && (await isRealDir(join(path, ".pnpm")));
	const { bytes, errors } = await duBytes(path);
	return { category, path, bytes, pnpm, partial: errors > 0 };
}

async function discover(
	root: string,
	maxDepth: number,
	nodeModules: boolean,
): Promise<DiscoverResult> {
	const candidates: Candidate[] = [];
	const targets: TargetLayout[] = [];
	let unreadable = 0;
	let pruned = 0;

	// A root that is itself a node_modules is one candidate, not a tree to
	// mine for nested ones (.pnpm package dirs each carry node_modules).
	if (basename(root) === "node_modules") {
		if (!nodeModules) {
			return { candidates, targets, unreadable, pruned };
		}
		pruned++;
		candidates.push(await measureCandidate("node-modules", root));
		return { candidates, targets, unreadable, pruned };
	}

	/** Scan a cargo target/ dir for rust-safe innards (never whole target/). */
	const handleTarget = async (target: string): Promise<void> => {
		pruned++;
		let children: Dirent[];
		try {
			children = await readdir(target, { withFileTypes: true });
		} catch (error) {
			if (!isErrnoError(error)) throw error;
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
			} catch (error) {
				if (!isErrnoError(error)) throw error;
				unreadable++;
				continue;
			}
			const profileLayout = { path: childPath, entries: innards.map((i) => i.name) };
			layout.profiles.push(profileLayout);
			for (const innard of innards) {
				if (!innard.isDirectory()) continue;
				if (RUST_PROFILE_INNARDS.includes(innard.name)) {
					candidates.push(await measureCandidate("rust-safe", join(childPath, innard.name)));
				}
			}
		}
		targets.push(layout);
	};

	const visitDir = async (dir: string, depth: number): Promise<void> => {
		let entries: Dirent[];
		try {
			entries = await readdir(dir, { withFileTypes: true });
		} catch (error) {
			if (!isErrnoError(error)) throw error;
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
					if (nodeModules) candidates.push(await measureCandidate("node-modules", entryPath));
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
	opts: { maxDepth: number; nodeModules: boolean; pnpmStorePrune: boolean },
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
	lines.push(
		`root: ${root}  max-depth: ${opts.maxDepth}  node-modules: ${opts.nodeModules ? "on (opt-in)" : "off"}`,
	);
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
	const order: Category[] = ["rust-safe", "node-modules"];
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
		if (!opts.nodeModules) {
			lines.push("  note: node_modules removal is opt-in (--node-modules) because unlinking");
			lines.push("        store-linked trees frees ~0 by itself; the weekly prune (user unit)");
			lines.push("        is what releases store bytes here.");
		} else {
			lines.push("  note: unlinking store-linked node_modules frees ~0 by itself; the store");
			lines.push("        prune is what releases bytes, and it only counts after projects");
			lines.push("        stopped referencing the content (i.e. after node_modules removal).");
		}
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
			"node-modules": { type: "boolean", default: false },
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

	const nodeModules = values["node-modules"] ?? false;
	const result = await discover(rootPath, maxDepth, nodeModules);
	const store = await inspectPnpmStore();

	if (!values.apply) {
		console.log(report(rootPath, result, store, {
			maxDepth,
			nodeModules,
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
