#!/usr/bin/env node
/**
 * rust-aggressive.ts — cargo target/ aggressive sweep. DRY-RUN BY DEFAULT.
 *
 * Split out of src-clean.ts (2026-10-01, operator decision) because it is
 * a different risk class, not a bigger version of the same one:
 *
 *   removes  target/<profile>/deps/
 *            target/<profile>/build/
 *            target/<profile>/.fingerprint/
 *
 * These are the compilation OUTPUT CACHE. Removing them FORCES FULL
 * REBUILDS: the next `cargo build` in every touched workspace recompiles
 * every dependency from scratch (no re-download — crates.io artifacts
 * live in ~/.cargo — but full recompile, which on big workspaces is tens
 * of minutes to hours and, on this box, real disk churn writing new
 * artifacts right back). src-clean.ts's default pass (incremental/,
 * package/, doc/) never triggers this: the build cache stays intact.
 *
 * When this trade is worth it: reclaim needed NOW, machine idle for the
 * foreseeable, and you accept that the next build in each project pays
 * the recompile tax. Otherwise run src-clean.ts instead.
 *
 * Same walk rules as src-clean: a target/ only counts with a sibling
 * Cargo.toml; .git/.jj skipped; traversal prunes at node_modules/target;
 * depth cap (--max-depth, default 6); EACCES quiet. Sizes are block
 * usage (du -s style), upper bounds.
 *
 * Usage:
 *   rust-aggressive.ts [--root <dir>] [--max-depth N]
 *   rust-aggressive.ts --apply [--root <dir>]
 *
 * Exit: 0 ok, 1 runtime failure, 2 usage error.
 */

import { readdir, rm, rmdir, stat } from "node:fs/promises";
import { homedir } from "node:os";
import { join } from "node:path";
import { parseArgs } from "node:util";
import type { Dirent } from "node:fs";
import { DEFAULT_MAX_DEPTH, SKIP_DIR_NAMES, UsageError, duBytes, human, isErrnoError } from "./lib.ts";

const PROG = "rust-aggressive.ts";
/** target/<profile>/ innards THIS bin owns (src-clean owns the rest). */
const AGGRESSIVE_INNARDS: readonly string[] = ["deps", "build", ".fingerprint"];

interface Candidate {
	/** Absolute path of the directory that would be removed. */
	path: string;
	/** Block-usage bytes (upper bound on reclaim). */
	bytes: bigint;
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

function usage(): string {
	return `usage: ${PROG} [options]

Find and optionally remove cargo target/<profile>/{deps,build,.fingerprint}
directories. DRY-RUN BY DEFAULT: nothing is deleted without --apply.

*** WARNING: --apply FORCES FULL REBUILDS. Every touched workspace ***
*** recompiles all dependencies from scratch on its next build.     ***
No re-downloads (~/.cargo keeps crate sources); full recompile only.
If you do not want that, run src-clean.ts instead — its default pass
removes only incremental/, package/, doc/ and keeps the build cache.

options:
  --apply            actually remove candidates (destructive, see warning)
  --root <dir>       scan root (default: $HOME/src)
  --max-depth <n>    directory depth cap for the walk (default ${DEFAULT_MAX_DEPTH})
  --help             this help

a target/ dir only counts when a Cargo.toml sits beside it. Walk skips
.git/.jj, prunes at node_modules/target, caps depth, and counts
unreadable (EACCES) directories quietly.

sizes are block usage and upper bounds: content shared with other
checkouts (hardlinks/reflinks) is not freed by unlinking.`;
}

async function measure(path: string): Promise<Candidate> {
	const { bytes, errors } = await duBytes(path);
	return { path, bytes, partial: errors > 0 };
}

async function discover(root: string, maxDepth: number): Promise<DiscoverResult> {
	const candidates: Candidate[] = [];
	const targets: TargetLayout[] = [];
	let unreadable = 0;
	let pruned = 0;

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
			// Profile dir: target/debug, target/release, custom profiles.
			let innards: Dirent[];
			try {
				innards = await readdir(childPath, { withFileTypes: true });
			} catch (error) {
				if (!isErrnoError(error)) throw error;
				unreadable++;
				continue;
			}
			layout.profiles.push({ path: childPath, entries: innards.map((i) => i.name) });
			for (const innard of innards) {
				if (innard.isDirectory() && AGGRESSIVE_INNARDS.includes(innard.name)) {
					candidates.push(await measure(join(childPath, innard.name)));
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
		const cargoRoot = entries.some((entry) => entry.name === "Cargo.toml" && entry.isFile());
		await Promise.all(
			entries.map(async (entry) => {
				if (SKIP_DIR_NAMES.has(entry.name)) return;
				if (!entry.isDirectory()) return;
				const entryPath = join(dir, entry.name);
				if (entry.name === "node_modules") {
					pruned++;
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

/**
 * Dirs that would be empty after candidate removal (a profile whose every
 * entry was an aggressive innard): `rmdir --ignore-fail-on-non-empty`
 * semantics — attempted, quietly skipped when not empty.
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

function report(root: string, result: DiscoverResult): string {
	const lines: string[] = [];
	const total = result.candidates.reduce((sum, candidate) => sum + candidate.bytes, 0n);
	lines.push(`${PROG}: DRY RUN (no --apply) — nothing will be deleted`);
	lines.push(`root: ${root}`);
	lines.push("");
	lines.push("candidates (ALL of these force full rebuilds when removed):");
	if (result.candidates.length === 0) {
		lines.push("  (none found)");
	} else {
		lines.push("       SIZE  PATH");
		const sorted = [...result.candidates].sort((a, b) => (a.bytes < b.bytes ? 1 : a.bytes > b.bytes ? -1 : 0));
		for (const candidate of sorted) {
			const note = candidate.partial ? "  [partial: size is a lower bound]" : "";
			lines.push(`${human(candidate.bytes).padStart(10)}  ${candidate.path}${note}`);
		}
	}
	lines.push("");
	lines.push(`total — space freed by unlinking (UPPER bound): ${human(total)} across ${result.candidates.length} dir(s)`);
	lines.push("");
	lines.push(`cost: next \`cargo build\` in each touched workspace recompiles ALL dependencies`);
	lines.push(`skipped: ${result.unreadable} unreadable dir(s) (quiet), ${result.pruned} pruned subtree(s)`);
	lines.push("");
	lines.push("commands that would run (with --apply):");
	const removals = result.candidates.map((candidate) => `rm -rf -- ${candidate.path}`);
	lines.push(...(removals.length > 0 ? removals.map((line) => `  ${line}`) : ["  (nothing to remove)"]));
	for (const dir of emptyAfterRemoval(result)) {
		lines.push(`  rmdir --ignore-fail-on-non-empty -- ${dir}`);
	}
	return lines.join("\n");
}

async function main(argv: string[]): Promise<number> {
	const { values } = parseArgs({
		args: argv,
		options: {
			apply: { type: "boolean", default: false },
			root: { type: "string" },
			"max-depth": { type: "string" },
			help: { type: "boolean", default: false },
		},
	});
	if (values.help) {
		console.log(usage());
		return 0;
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

	const result = await discover(rootPath, maxDepth);

	if (!values.apply) {
		console.log(report(rootPath, result));
		return 0;
	}

	console.log(`${PROG}: APPLY — removing ${result.candidates.length} candidate(s) under ${rootPath}`);
	console.log(`${PROG}: every touched workspace pays a FULL REBUILD on its next cargo build`);
	for (const candidate of result.candidates) {
		await rm(candidate.path, { recursive: true, force: true });
		console.log(`removed ${human(candidate.bytes).padStart(10)}  ${candidate.path}`);
	}
	for (const dir of emptyAfterRemoval(result)) {
		await rmdir(dir).catch(() => {
			// --ignore-fail-on-non-empty parity: leftover files keep the dir.
		});
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
