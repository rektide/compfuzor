#!/usr/bin/env node
/**
 * rustup-clean.ts — ~/.rustup toolchain keeper-policy cleanup. DRY-RUN BY
 * DEFAULT.
 *
 * This host: ~25 toolchains / 33G under ~/.rustup (RUSTUP_HOME respected)
 * — the biggest untapped reclaim after the 2026-10-01 root-fs-full
 * incident. Uninstalling a toolchain via rustup (not rm!) also clears its
 * rustup metadata (settings, update hashes), so always go through
 * `rustup toolchain uninstall`.
 *
 * Keeper policy (operator-set 2026-10-01) — a toolchain is KEPT when any:
 *   - it is the DEFAULT (`rustup default`)
 *   - it is the currently-ACTIVE toolchain (`rustup show active-toolchain`,
 *     which resolves RUSTUP_TOOLCHAIN env and rust-toolchain.toml overrides;
 *     the `(active)` list annotation is honored too)
 *   - among the N newest STABLE-family toolchains (--keep-stables, default
 *     2; the tracking `stable` counts as newest, semver pins like 1.98.0
 *     rank below it by version)
 *   - among the N newest NIGHTLIES (--keep-nightlies, default 2; tracking
 *     `nightly` counts as newest, dated nightlies rank by date)
 *   - it matches an explicit --keep glob (e.g. --keep '1.8*' --keep '*musl*')
 * Everything else is a removal candidate. Custom/linked/unknown-channel
 * toolchains (beta, cross targets, rustup toolchain link names) are KEPT —
 * they are deliberate installs this policy does not understand.
 *
 * Semver pins heads-up: a rust-toolchain.toml that pins a removed version
 * does not break builds — rustup shims re-download the pin on demand — but
 * that is network + a few hundred MB the next time that project builds.
 * Keep pins with --keep when in doubt; the dry run names every candidate.
 *
 * Usage:
 *   rustup-clean.ts [--keep-stables N] [--keep-nightlies N] [--keep GLOB]...
 *   rustup-clean.ts --apply [...]
 *
 * Exit: 0 ok, 1 runtime failure, 2 usage error.
 */

import { homedir } from "node:os";
import { join } from "node:path";
import { parseArgs } from "node:util";
import { UsageError, capture, duBytes, globToRegExp, human, run } from "./lib.ts";

const PROG = "rustup-clean.ts";
const DEFAULT_KEEP_STABLES = 2;
const DEFAULT_KEEP_NIGHTLIES = 2;
/** Host-triple vendor markers: the token right after the arch token. */
const VENDOR_TOKENS: ReadonlySet<string> = new Set(["unknown", "pc", "apple", "wasi"]);
const NIGHTLY_DATE_RE = /^nightly-(\d{4})-(\d{2})-(\d{2})$/;
const SEMVER_RE = /^(\d+)(?:\.(\d+))?(?:\.(\d+))?$/;

type Channel = "stable" | "nightly" | "other";

/**
 * Channel part of a toolchain name. The host triple is arch-vendor-os(-abi)
 * (x86_64-unknown-linux-gnu = 4 dash tokens), so peel it by locating the
 * first vendor marker at token index >= 1 and taking everything before the
 * arch token that precedes it: "nightly-2026-09-30-x86_64-unknown-linux-gnu"
 * -> "nightly-2026-09-30". No vendor marker (custom/linked names) -> the
 * whole name is the channel, classified "other" and kept by policy.
 */
function channelOf(name: string): string {
	const tokens = name.split("-");
	const vendorIndex = tokens.findIndex((token, index) => index >= 1 && VENDOR_TOKENS.has(token));
	if (vendorIndex < 2) return name;
	return tokens.slice(0, vendorIndex - 1).join("-");
}

interface Toolchain {
	name: string;
	channel: Channel;
	/** Sort key within the channel (bigger = newer). */
	rank: number;
	isDefault: boolean;
	isActive: boolean;
	bytes: bigint;
	partial: boolean;
	keep: boolean;
	/** Why kept/removed, for the report. */
	reason: string;
}

function classify(name: string): { channel: Channel; rank: number } {
	const channelPart = channelOf(name);
	if (channelPart === "stable") return { channel: "stable", rank: Number.MAX_SAFE_INTEGER };
	if (channelPart === "nightly") return { channel: "nightly", rank: Number.MAX_SAFE_INTEGER };
	const nightly = NIGHTLY_DATE_RE.exec(channelPart);
	if (nightly !== null) {
		const date = Number(`${nightly[1]}${nightly[2]}${nightly[3]}`);
		return { channel: "nightly", rank: date };
	}
	const semver = SEMVER_RE.exec(channelPart);
	if (semver !== null) {
		// Versioned stable releases (1.98.0, 1.87, ...). Rank below the
		// tracking `stable` (MAX_SAFE_INTEGER) minus the patch-minor blend,
		// keeping room for every real version.
		const major = Number(semver[1]);
		const minor = Number(semver[2] ?? 0);
		const patch = Number(semver[3] ?? 0);
		return { channel: "stable", rank: major * 1_000_000 + minor * 1_000 + patch };
	}
	return { channel: "other", rank: 0 };
}

/** `rustup toolchain list` rows → names + default/active annotations. */
function parseList(output: string): { names: string[]; annotatedDefault: string | null; annotatedActive: string | null } {
	const names: string[] = [];
	let annotatedDefault: string | null = null;
	let annotatedActive: string | null = null;
	for (const line of output.split("\n")) {
		const name = line.trim().split(/\s+/)[0];
		if (!name || line.trim() === "") continue;
		names.push(name);
		if (/\(default\)/.test(line)) annotatedDefault ??= name;
		if (/\(active\)/.test(line)) annotatedActive ??= name;
	}
	return { names, annotatedDefault, annotatedActive };
}

function usage(): string {
	return `usage: ${PROG} [options]

List rustup toolchains with sizes, mark keepers per policy, and
optionally uninstall the rest via \`rustup toolchain uninstall\`.
DRY-RUN BY DEFAULT: nothing is uninstalled without --apply.

keeper policy — KEEP a toolchain when any:
  - it is the default          (rustup default)
  - it is the active toolchain (rustup show active-toolchain; resolves
                                RUSTUP_TOOLCHAIN env + rust-toolchain
                                file overrides)
  - among the N newest stables (--keep-stables, default ${DEFAULT_KEEP_STABLES};
                                tracking 'stable' = newest, semver pins
                                rank below by version)
  - among the N newest nightlies (--keep-nightlies, default ${DEFAULT_KEEP_NIGHTLIES};
                                tracking 'nightly' = newest, dated by date)
  - it matches a --keep glob   (repeatable; * and ? wildcards, matched
                                against the full toolchain name)
Custom/linked/unknown-channel toolchains (beta, cross, link names) are
always kept: deliberate installs this policy does not understand.

options:
  --apply                uninstall removal candidates (destructive)
  --keep-stables <n>     newest stable-family toolchains to keep (default ${DEFAULT_KEEP_STABLES})
  --keep-nightlies <n>   newest nightlies to keep (default ${DEFAULT_KEEP_NIGHTLIES})
  --keep <glob>...       glob(s) naming toolchains to always keep
  --help                 this help

semver pins: removing a version a rust-toolchain.toml pins does not
break builds — rustup shims re-download it on demand — but that costs
network + a few hundred MB on that project's next build. --keep pins
when in doubt; the dry run names every candidate.

sizes are block usage (du -s style), upper bounds on reclaim.`;
}

function parseCount(raw: string | undefined, label: string, fallback: number): number {
	if (raw === undefined) return fallback;
	const value = Number.parseInt(raw, 10);
	if (!Number.isInteger(value) || value < 0 || value > 1000) {
		throw new UsageError(`${label} expects an integer 0..1000 (got "${raw}")`);
	}
	return value;
}

async function main(argv: string[]): Promise<number> {
	const { values } = parseArgs({
		args: argv,
		options: {
			apply: { type: "boolean", default: false },
			"keep-stables": { type: "string" },
			"keep-nightlies": { type: "string" },
			keep: { type: "string", multiple: true },
			help: { type: "boolean", default: false },
		},
	});
	if (values.help) {
		console.log(usage());
		return 0;
	}
	const keepStables = parseCount(values["keep-stables"], "--keep-stables", DEFAULT_KEEP_STABLES);
	const keepNightlies = parseCount(values["keep-nightlies"], "--keep-nightlies", DEFAULT_KEEP_NIGHTLIES);
	const keepGlobs = (values.keep ?? []).map((glob) => globToRegExp(glob));

	const listOutput = await capture("rustup", ["toolchain", "list"]);
	if (listOutput === null) {
		console.error(`${PROG}: \`rustup toolchain list\` failed — is rustup on PATH?`);
		return 1;
	}
	const { names, annotatedDefault, annotatedActive } = parseList(listOutput);

	const defaultName = annotatedDefault ?? (await capture("rustup", ["default"]))?.trim().split(/\s+/)[0] ?? null;
	// `rustup show active-toolchain` resolves env/toolchain-file overrides,
	// which the list annotation does not reflect.
	const activeName = (await capture("rustup", ["show", "active-toolchain"]))?.trim().split(/\s+/)[0] ?? annotatedActive;

	const rustupHome = process.env.RUSTUP_HOME ?? join(homedir(), ".rustup");
	const toolchainsDir = join(rustupHome, "toolchains");

	const toolchains: Toolchain[] = [];
	for (const name of names) {
		const { channel, rank } = classify(name);
		const { bytes, errors } = await duBytes(join(toolchainsDir, name));
		const isDefault = name === defaultName;
		const isActive = name === activeName || name === annotatedActive;
		toolchains.push({ name, channel, rank, isDefault, isActive, bytes, partial: errors > 0, keep: false, reason: "" });
	}

	// Rank per channel (newest first) and apply the keep windows.
	for (const channel of ["stable", "nightly"] as const) {
		const pool = toolchains
			.filter((toolchain) => toolchain.channel === channel)
			.sort((a, b) => b.rank - a.rank || b.name.localeCompare(a.name));
		pool.forEach((toolchain, index) => {
			const label = channel === "stable" ? "stable" : "nightly";
			if (toolchain.isDefault || toolchain.isActive) return; // protected below
			if (channel === "stable" ? index < keepStables : index < keepNightlies) {
				toolchain.keep = true;
				toolchain.reason = `${label} #${index + 1} of keep-window ${channel === "stable" ? keepStables : keepNightlies}`;
			}
		});
	}
	for (const toolchain of toolchains) {
		const matched = keepGlobs.find((re) => re.test(toolchain.name));
		if (toolchain.isDefault) {
			toolchain.keep = true;
			toolchain.reason = "default toolchain";
		} else if (toolchain.isActive) {
			toolchain.keep = true;
			toolchain.reason = "active toolchain";
		} else if (matched !== undefined) {
			toolchain.keep = true;
			toolchain.reason = `--keep ${matched}`;
		} else if (toolchain.channel === "other") {
			toolchain.keep = true;
			toolchain.reason = "custom/unknown channel (policy keeps)";
		} else if (!toolchain.keep) {
			toolchain.reason = `beyond keep window (${toolchain.channel})`;
		}
	}

	const removals = toolchains.filter((toolchain) => !toolchain.keep);
	const keepBytes = toolchains.filter((t) => t.keep).reduce((sum, t) => sum + t.bytes, 0n);
	const removeBytes = removals.reduce((sum, t) => sum + t.bytes, 0n);

	const lines: string[] = [];
	lines.push(`${PROG}: DRY RUN (no --apply) — nothing will be uninstalled`);
	lines.push(`rustup home: ${rustupHome} (RUSTUP_HOME respected)`);
	lines.push(`default: ${defaultName ?? "unknown"}   active: ${activeName ?? "unknown"}`);
	lines.push(`policy: keep ${keepStables} newest stable(s), ${keepNightlies} newest nightly/nightlies, default, active, --keep globs`);
	lines.push("");
	lines.push("toolchains:");
	lines.push("       SIZE  DISPOSITION  NAME");
	const sorted = [...toolchains].sort((a, b) => (a.bytes < b.bytes ? 1 : a.bytes > b.bytes ? -1 : a.name.localeCompare(b.name)));
	for (const toolchain of sorted) {
		const disposition = toolchain.keep ? "keep" : "REMOVE";
		const note = toolchain.partial ? "  [partial: size is a lower bound]" : "";
		lines.push(
			`${human(toolchain.bytes).padStart(10)}  ${disposition.padEnd(12)}  ${toolchain.name}  (${toolchain.reason})${note}`,
		);
	}
	lines.push("");
	lines.push(`totals: keep ${human(keepBytes)} (${toolchains.length - removals.length}), remove ${human(removeBytes)} (${removals.length}) — upper bounds`);
	lines.push("");
	lines.push("commands that would run (with --apply):");
	lines.push(
		...(removals.length > 0
			? removals.map((toolchain) => `  rustup toolchain uninstall ${toolchain.name}`)
			: ["  (nothing to remove)"]),
	);
	if (!values.apply) {
		console.log(lines.join("\n"));
		return 0;
	}

	console.log(`${PROG}: APPLY — uninstalling ${removals.length} toolchain(s) via rustup`);
	for (const toolchain of removals) {
		console.log(`${PROG}: rustup toolchain uninstall ${toolchain.name}`);
		const code = await run("rustup", ["toolchain", "uninstall", toolchain.name]);
		if (code !== 0) {
			console.error(`${PROG}: uninstall of ${toolchain.name} failed (exit ${code}) — aborting; later candidates NOT attempted.`);
			console.error(`${PROG}: already-uninstalled progress is kept; re-run to finish the rest.`);
			return code ?? 1;
		}
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
