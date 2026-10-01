/**
 * lib.ts — shared helpers for the disk-cleanup bins (src-clean.ts,
 * rust-aggressive.ts, pnpm-prune.ts, rustup-clean.ts, btrfs-balance.ts).
 *
 * Not a bin itself: deployed alongside them (raw copy) and imported with
 * explicit .ts extensions, which Node 22.18+/23.6+ type stripping (and
 * therefore this box's node 26) resolves natively.
 *
 * Conventions shared by every consumer:
 *   - stdlib only, node:util parseArgs CLIs
 *   - DRY-RUN by default; --apply is the only deletion path
 *   - exit 0 ok, 1 runtime failure, 2 usage error
 *   - sizes are block usage (st_blocks × 512, du -s parity) — upper bounds
 */

import { spawn } from "node:child_process";
import { lstat, readdir } from "node:fs/promises";
import { join } from "node:path";
import type { Dirent } from "node:fs";

/** Directory names never descended into (VCS internals). */
export const SKIP_DIR_NAMES: ReadonlySet<string> = new Set([".git", ".jj"]);
/** Default directory depth cap for source-tree walks. */
export const DEFAULT_MAX_DEPTH = 6;

export class UsageError extends Error {
	readonly code = 2;
}

/** Human-readable byte count (binary units). */
export function human(bytes: bigint): string {
	const units = ["B", "KiB", "MiB", "GiB", "TiB", "PiB"];
	let value = Number(bytes);
	let unit = 0;
	while (value >= 1024 && unit < units.length - 1) {
		value /= 1024;
		unit++;
	}
	return unit === 0 ? `${value} ${units[unit]}` : `${value.toFixed(1)} ${units[unit]}`;
}

/**
 * Capture a command's stdout, optionally bounded by a timeout; null on any
 * failure (never rejects).
 */
export function capture(
	command: string,
	args: readonly string[],
	timeoutMs?: number,
): Promise<string | null> {
	return new Promise((resolve) => {
		let child;
		try {
			child = spawn(command, args, { stdio: ["ignore", "pipe", "ignore"] });
		} catch {
			resolve(null);
			return;
		}
		let out = "";
		const timer = timeoutMs === undefined ? undefined : setTimeout(() => child.kill("SIGKILL"), timeoutMs);
		child.stdout?.on("data", (chunk: Buffer) => {
			out += chunk.toString("utf8");
		});
		child.on("error", () => {
			if (timer !== undefined) clearTimeout(timer);
			resolve(null);
		});
		child.on("close", (code) => {
			if (timer !== undefined) clearTimeout(timer);
			resolve(code === 0 ? out : null);
		});
	});
}

/** Run a command inheriting stdio; resolve to its exit code (never rejects). */
export function run(command: string, args: readonly string[]): Promise<number | null> {
	return new Promise((resolve) => {
		let child;
		try {
			child = spawn(command, args, { stdio: "inherit" });
		} catch (error) {
			console.error(`failed to spawn ${command}:`, error);
			resolve(1);
			return;
		}
		child.on("error", (error) => {
			console.error(`${command}:`, error);
			resolve(1);
		});
		child.on("close", (code) => resolve(code));
	});
}

export interface DuOutcome {
	bytes: bigint;
	/** Read errors encountered (permission etc.); size is a lower bound then. */
	errors: number;
}

/**
 * Block-usage size of a subtree, du -s style: st_blocks × 512 per inode,
 * hardlinks counted once per traversal (parity with du within one tree).
 * Read errors are counted, not thrown.
 */
export async function duBytes(rootPath: string): Promise<DuOutcome> {
	let bytes = 0n;
	let errors = 0;
	const seen = new Set<string>();
	const walk = async (dir: string): Promise<void> => {
		let entries: Dirent[];
		try {
			entries = await readdir(dir, { withFileTypes: true });
		} catch (error) {
			if (!isErrnoError(error)) throw error;
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
				} catch (error) {
					if (!isErrnoError(error)) throw error;
					errors++;
				}
			}),
		)
	};
	try {
		const info = await lstat(rootPath);
		bytes += BigInt(info.blocks ?? 0) * 512n;
		if (info.isDirectory()) await walk(rootPath);
	} catch (error) {
		if (!isErrnoError(error)) throw error;
		errors++;
	}
	return { bytes, errors };
}

/** True when the path exists and is a real directory (not a symlink). */
export async function isRealDir(path: string): Promise<boolean> {
	try {
		return (await lstat(path)).isDirectory();
	} catch {
		return false;
	}
}

/**
 * True for filesystem errors (EACCES, ENOENT, ...) worth swallowing during
 * walks. Anything else (ReferenceError, TypeError — a bin's own bug) must
 * rethrow: a too-broad catch once turned a missing import into a silent
 * "0 unreadable dirs" empty report.
 */
export function isErrnoError(error: unknown): boolean {
	return error instanceof Error && typeof (error as NodeJS.ErrnoException).code === "string";
}

/**
 * Glob → RegExp for --keep style patterns: `*` any run except `/`, `?` one
 * non-`/` char, everything else literal. Full-string match.
 */
export function globToRegExp(glob: string): RegExp {
	let source = "";
	for (const char of glob) {
		if (char === "*") source += "[^/]*";
		else if (char === "?") source += "[^/]";
		else source += char.replace(/[\\^$.+(){}[\]|]/g, "\\$&");
	}
	return new RegExp(`^${source}$`);
}
