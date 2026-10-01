#!/usr/bin/env node
/**
 * pnpm-prune.ts — prune the pnpm content-addressable store. DRY-RUN BY
 * DEFAULT; --apply runs `pnpm store prune`.
 *
 * Why this exists: pnpm node_modules are hardlinks/reflinks into the
 * store, so deleting project trees frees ~nothing — the store is where
 * the bytes live. `pnpm store prune` removes store content no installed
 * project references any more. Measured on this host 2026-10-01:
 * 6.0 GB / 140,780 files freed by prune alone, with node_modules
 * untouched. That measured result is why node_modules removal was
 * demoted to an opt-in anti-feature in src-clean.ts and the STORE, not
 * the trees, is what gets scheduled.
 *
 * The weekly user unit (disk-cleanup-main-pnpm-prune.timer) runs this bin
 * with --apply: that schedule-and-prune is the operator's standing sanction
 * (2026-10-01) — the timer IS the apply. Interactive runs without
 * --apply stay dry-run like every other disk-cleanup bin.
 *
 * Ordering note: prune releases content no project references, so it
 * pays off AFTER node_modules removals (src-clean --apply --node-modules)
 * — a tree still linked pins its store content.
 *
 * Usage:
 *   pnpm-prune.ts             # dry run: report store + would-run command
 *   pnpm-prune.ts --apply     # run pnpm store prune
 *
 * Exit: 0 ok, 1 runtime failure, 2 usage error.
 */

import { parseArgs } from "node:util";
import { UsageError, capture, human, run } from "./lib.ts";

const PROG = "pnpm-prune.ts";

interface StoreInfo {
	/** Resolved store path, or null when pnpm is absent/failed. */
	path: string | null;
	/** Store size in bytes from bounded `du -s -B1`, or null when unknown. */
	bytes: bigint | null;
}

function usage(): string {
	return `usage: ${PROG} [--apply]

Report the pnpm content-addressable store and optionally prune it.
DRY-RUN BY DEFAULT: --apply is required to run \`pnpm store prune\`.

options:
  --apply   run \`pnpm store prune\` (removes store content no installed
            project references; frees bytes that node_modules deletion
            cannot — trees are store hardlinks/reflinks)
  --help    this help

the weekly disk-cleanup-main-pnpm-prune.timer user unit runs this with
--apply: that schedule is the operator's standing sanction for the
prune. After any src-clean --apply --node-modules, a prune (or the next
timer fire) is what actually releases the store bytes.

sizes are block usage (du -s style), upper bounds — prune removes only
unreferenced packages, typically far less than the whole store.`;
}

async function inspectStore(): Promise<StoreInfo> {
	const path = await capture("pnpm", ["store", "path"], 10_000);
	if (path === null) return { path: null, bytes: null };
	const storePath = path.trim();
	if (!storePath) return { path: null, bytes: null };
	const du = await capture("du", ["-s", "-B1", storePath], 60_000);
	if (du === null) return { path: storePath, bytes: null };
	const tokens = du.trim().split(/\s+/);
	const kilobytes = Number.parseInt(tokens[0] ?? "", 10);
	return { path: storePath, bytes: Number.isFinite(kilobytes) ? BigInt(kilobytes) : null };
}

async function main(argv: string[]): Promise<number> {
	const { values } = parseArgs({
		args: argv,
		options: {
			apply: { type: "boolean", default: false },
			help: { type: "boolean", default: false },
		},
	});
	if (values.help) {
		console.log(usage());
		return 0;
	}
	const store = await inspectStore();
	if (store.path === null) {
		throw new UsageError("pnpm store not detected — is pnpm on PATH?");
	}

	if (!values.apply) {
		const size = store.bytes === null ? "unknown (du failed or exceeded its 60s bound)" : human(store.bytes);
		console.log(`${PROG}: DRY RUN (no --apply) — nothing will run`);
		console.log(`store path: ${store.path} (size ${size}, via bounded du -s)`);
		if (store.bytes !== null) {
			console.log(`prune releases up to ${human(store.bytes)} (upper bound — only unreferenced content goes)`);
		}
		console.log("");
		console.log("command that would run (with --apply):");
		console.log("  pnpm store prune");
		return 0;
	}

	console.log(`${PROG}: APPLY — pnpm store prune (operator-sanctioned schedule; the timer passes --apply)`);
	const code = await run("pnpm", ["store", "prune"]);
	if (code !== 0) return code ?? 1;
	console.log(`${PROG}: prune complete`);
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
