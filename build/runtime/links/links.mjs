#!/usr/bin/env -S node --disable-warning=MODULE_TYPELESS_PACKAGE_JSON
import { basename, dirname, isAbsolute, join, normalize, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { parseArgs, promisify } from "node:util";
import { access, chmod, constants, copyFile, lstat, mkdir, readFile, readlink, realpath, rename, rm, stat, symlink } from "node:fs/promises";
import { execFile } from "node:child_process";
//#region files/links/cli.ts
/** Strict command-line parsing and help for the LINKS manager. */
const LINKS_HELP = `Usage: links <apply|status|audit|remove> [MANIFEST ...] [options]

Manage version 1 and 2 link plans. A directory argument means its links.json;
the default manifest is the current deployment's links.json.

Options:
  --scope system|user  Operate on one activation scope
  --id GLOBS           Comma-separated record-id globs; may be repeated
  --strategy link|copy Apply using one declared representation
  --composed           Apply only generic-install records
  --json               Emit one JSON object per row
  --json-array         Emit one JSON array
  --sudo MODE          auto (default), always, or never
                       Bare --sudo remains accepted as always for compatibility
  -q, -qq              Synopsis only, or no output
  -h, --help           Show this help

Exit: 0 success/in-sync, 1 drift or policy conflict, 2 usage/source error.`;
function fail$2(message) {
	throw new Error(message);
}
function parseSudoWord(value) {
	const raw = value.trim().toLowerCase();
	if (raw === "auto") return "auto";
	if ([
		"always",
		"1",
		"true",
		"y",
		"yes"
	].includes(raw)) return "always";
	if ([
		"never",
		"0",
		"false",
		"n",
		"no"
	].includes(raw)) return "never";
}
function resolveSudoMode(flagValue) {
	if (flagValue !== void 0) {
		const mode = parseSudoWord(flagValue);
		if (!mode) fail$2(`--sudo expects auto, always, or never (got ${flagValue})`);
		return mode;
	}
	const environmentValue = process.env.COMPFUZOR_LINKS_SUDO;
	if (environmentValue === void 0 || environmentValue.trim() === "") return "auto";
	const mode = parseSudoWord(environmentValue);
	if (!mode) fail$2(`COMPFUZOR_LINKS_SUDO must be auto, always, or never (got ${environmentValue})`);
	return mode;
}
/**
* node:util parseArgs intentionally has no optional-value options. Preserve the
* historical bare `--sudo` shorthand by making its implicit value explicit;
* every other token is passed to strict parseArgs unchanged.
*/
function normalizeBareSudo(argv) {
	const normalized = [];
	for (let index = 0; index < argv.length; index++) {
		const argument = argv[index];
		const next = argv[index + 1];
		normalized.push(argument === "--sudo" && (next === void 0 || parseSudoWord(next) === void 0) ? "--sudo=always" : argument);
	}
	return normalized;
}
function parseLinksArgs(argv, defaultManifest) {
	const { values, positionals, tokens } = parseArgs({
		args: normalizeBareSudo(argv),
		strict: true,
		allowPositionals: true,
		tokens: true,
		options: {
			scope: { type: "string" },
			id: {
				type: "string",
				multiple: true
			},
			strategy: { type: "string" },
			composed: { type: "boolean" },
			json: { type: "boolean" },
			"json-array": { type: "boolean" },
			sudo: { type: "string" },
			quiet: {
				type: "boolean",
				short: "q",
				multiple: true
			},
			help: {
				type: "boolean",
				short: "h"
			}
		}
	});
	if (values.help) {
		console.log(LINKS_HELP);
		process.exit(0);
	}
	const commandIndex = positionals.findIndex((value) => value === "apply" || value === "status" || value === "audit" || value === "remove");
	if (commandIndex < 0) fail$2("expected apply, status, audit, or remove");
	const command = positionals[commandIndex];
	const paths = positionals.toSpliced(commandIndex, 1);
	if (command !== "audit" && paths.length > 1) fail$2(`${command} accepts at most one manifest`);
	if (values.strategy !== void 0 && command !== "apply") fail$2("--strategy is only valid with apply");
	if (values.composed && command !== "apply") fail$2("--composed is only valid with apply");
	if (values.scope !== void 0 && values.scope !== "system" && values.scope !== "user") fail$2("--scope must be system or user");
	if (values.strategy !== void 0 && values.strategy !== "link" && values.strategy !== "copy") fail$2("--strategy must be link or copy");
	const id = values.id?.flatMap((value) => value.split(",").map((part) => part.trim()).filter(Boolean));
	if (values.id !== void 0 && id?.length === 0) fail$2("--id requires a comma-separated glob list");
	const formatToken = tokens.findLast((token) => token.kind === "option" && (token.name === "json" || token.name === "json-array"));
	const format = formatToken?.name === "json-array" ? "array" : formatToken?.name === "json" ? "jsonl" : "human";
	return {
		command,
		scope: values.scope,
		id,
		format,
		quiet: values.quiet?.length ?? 0,
		paths: paths.length === 0 ? [defaultManifest] : paths,
		sudo: values.sudo,
		strategy: values.strategy,
		composed: values.composed ?? false
	};
}
//#endregion
//#region files/links/manifest.ts
/** LINKS manifest v1/v2 decoding, path binding, and record selection. */
function fail$1(message) {
	throw new Error(message);
}
function object(value, description) {
	if (!value || typeof value !== "object" || Array.isArray(value)) fail$1(`${description} must be an object`);
	return value;
}
function stringField(value, description) {
	if (typeof value !== "string" || value.length === 0) fail$1(`${description} must be a non-empty string`);
	return value;
}
function strategiesField(value, description) {
	if (value === void 0) return {
		available: ["link"],
		default: "link"
	};
	const strategies = object(value, description);
	const unknown = Object.keys(strategies).filter((key) => key !== "available" && key !== "default");
	if (unknown.length > 0) fail$1(`${description} has unknown fields: ${unknown.sort().join(", ")}`);
	if (!Array.isArray(strategies.available) || strategies.available.length === 0) fail$1(`${description}.available must be a non-empty array`);
	if (strategies.available.some((entry) => entry !== "link" && entry !== "copy")) fail$1(`${description}.available contains an unsupported strategy`);
	const declared = strategies.available;
	if (new Set(declared).size !== declared.length) fail$1(`${description}.available contains duplicates`);
	if (strategies.default !== "link" && strategies.default !== "copy") fail$1(`${description}.default must be link or copy`);
	if (!declared.includes(strategies.default)) fail$1(`${description}.default must be available`);
	return {
		available: ["link", "copy"].filter((strategy) => declared.includes(strategy)),
		default: strategies.default
	};
}
async function manifestPath(path) {
	try {
		if ((await lstat(path)).isDirectory()) return join(path, "links.json");
	} catch {}
	return path;
}
async function loadManifest(inputPath) {
	const path = await manifestPath(inputPath);
	let raw;
	try {
		raw = JSON.parse(await readFile(path, "utf8"));
	} catch (error) {
		fail$1(`cannot read manifest ${path}: ${error instanceof Error ? error.message : String(error)}`);
	}
	const value = object(raw, `manifest ${path}`);
	if (value.version !== 1 && value.version !== 2) fail$1(`manifest ${path}: unsupported version ${String(value.version)}`);
	const version = value.version;
	if (!Array.isArray(value.links)) fail$1(`manifest ${path}: links must be an array`);
	const seen = /* @__PURE__ */ new Set();
	const links = value.links.map((entry, index) => {
		const record = object(entry, `${path}: links[${index}]`);
		const id = stringField(record.id, `${path}: links[${index}].id`);
		if (seen.has(id)) fail$1(`${path}: duplicate link id ${id}`);
		seen.add(id);
		if (record.scope !== "system" && record.scope !== "user") fail$1(`${path}: ${id}: invalid scope`);
		if (record.policy !== "preserve" && record.policy !== "fail" && record.policy !== "replace") fail$1(`${path}: ${id}: invalid policy`);
		if (record.state !== "present" && record.state !== "absent") fail$1(`${path}: ${id}: invalid state`);
		if (version === 1 && (record.strategies !== void 0 || record.compose !== void 0)) fail$1(`${path}: ${id}: version 1 records cannot declare strategies or compose; rerender as LINKS manifest version 2`);
		let runtimeRoots;
		if (record.runtimeRoots !== void 0) {
			if (!Array.isArray(record.runtimeRoots) || record.runtimeRoots.some((root) => root !== "HOME" && root !== "XDG_RUNTIME_DIR" && root !== "XDG_STATE_HOME")) fail$1(`${path}: ${id}: runtimeRoots contains an unsupported root`);
			runtimeRoots = record.runtimeRoots;
		}
		return {
			id,
			scope: record.scope,
			src: stringField(record.src, `${path}: ${id}: src`),
			dest: stringField(record.dest, `${path}: ${id}: dest`),
			policy: record.policy,
			state: record.state,
			strategies: strategiesField(record.strategies, `${path}: ${id}: strategies`),
			compose: record.compose === void 0 ? true : typeof record.compose === "boolean" ? record.compose : fail$1(`${path}: ${id}: compose must be boolean`),
			runtimeRoots
		};
	});
	let deployment;
	if (value.deployment !== void 0) {
		const entry = object(value.deployment, `${path}: deployment`);
		if (entry.dir !== void 0) stringField(entry.dir, `${path}: deployment.dir`);
		deployment = { dir: entry.dir };
	}
	return {
		path,
		manifest: {
			version,
			deployment,
			links
		}
	};
}
function expandPath(value, base) {
	let expanded = value;
	const home = process.env.HOME;
	const runtime = process.env.XDG_RUNTIME_DIR;
	const state = process.env.XDG_STATE_HOME || (home ? join(home, ".local/state") : void 0);
	if (value === "~" || value.startsWith("~/")) {
		if (!home) fail$1(`HOME is required to expand ${value}`);
		expanded = home + value.slice(1);
	} else if (value === "${HOME}" || value.startsWith("${HOME}/")) {
		if (!home) fail$1(`HOME is required to expand ${value}`);
		expanded = home + value.slice(7);
	} else if (value === "${XDG_RUNTIME_DIR}" || value.startsWith("${XDG_RUNTIME_DIR}/")) {
		if (!runtime) fail$1(`XDG_RUNTIME_DIR is required to expand ${value}`);
		expanded = runtime + value.slice(18);
	} else if (value === "${XDG_STATE_HOME}" || value.startsWith("${XDG_STATE_HOME}/")) {
		if (!state) fail$1(`HOME or XDG_STATE_HOME is required to expand ${value}`);
		expanded = state + value.slice(17);
	} else if (value.startsWith("~") || value.includes("${") || value.includes("$")) fail$1(`unsupported runtime-root expression: ${value}`);
	return normalize(isAbsolute(expanded) ? expanded : resolve(base, expanded));
}
function idMatches(idPatterns, id) {
	if (!idPatterns || idPatterns.length === 0) return true;
	return idPatterns.some((pattern) => globMatches(pattern, id));
}
function resolveRecords(path, manifest, scope, idPatterns, composed = false) {
	const base = expandPath(manifest.deployment?.dir ?? dirname(resolve(path)), dirname(resolve(path)));
	const claims = /* @__PURE__ */ new Map();
	const records = [];
	const invalid = [];
	for (const record of manifest.links.filter((entry) => (!scope || entry.scope === scope) && idMatches(idPatterns, entry.id) && (!composed || entry.compose))) try {
		const resolved = {
			...record,
			manifest: path,
			srcPath: expandPath(record.src, base),
			destPath: expandPath(record.dest, base)
		};
		if (resolved.srcPath === resolved.destPath) fail$1(`${path}: ${record.id}: source and destination are the same path`);
		const key = `${record.scope}\0${resolved.destPath}`;
		const prior = claims.get(key);
		if (prior && (prior.srcPath !== resolved.srcPath || prior.policy !== resolved.policy || prior.state !== resolved.state || prior.compose !== resolved.compose || prior.strategies.default !== resolved.strategies.default || prior.strategies.available.join("\0") !== resolved.strategies.available.join("\0"))) fail$1(`${path}: conflicting claims for ${resolved.destPath}`);
		claims.set(key, resolved);
		records.push(resolved);
	} catch (error) {
		invalid.push({
			id: record.id,
			scope: record.scope,
			status: "INVALID",
			src: record.src,
			dest: record.dest,
			manifest: path,
			detail: error instanceof Error ? error.message : String(error)
		});
	}
	return {
		records,
		invalid
	};
}
function globMatches(pattern, value) {
	let source = "^";
	for (let i = 0; i < pattern.length; i++) {
		const char = pattern[i];
		if (char === "*") source += ".*";
		else if (char === "?") source += ".";
		else source += char.replace(/[\\^$.*+?()[\]{}|]/g, "\\$&");
	}
	return new RegExp(source + "$").test(value);
}
//#endregion
//#region files/links/delivery.ts
/** Shared, import-safe filesystem delivery primitives used by LINKS and CONFIGS. */
const localLinkDeliveryExecutor = {
	async mkdir(path) {
		await mkdir(path, { recursive: true });
	},
	async symlink(source, destination) {
		await symlink(source, destination);
	},
	async rename(source, destination) {
		await rename(source, destination);
	},
	async rm(path) {
		await rm(path, { force: true });
	}
};
const localCopyDeliveryExecutor = {
	async mkdir(path) {
		await mkdir(path, { recursive: true });
	},
	async copyFile(source, destination) {
		await copyFile(source, destination);
	},
	async chmod(path, mode) {
		await chmod(path, mode);
	},
	async rename(source, destination) {
		await rename(source, destination);
	},
	async rm(path) {
		await rm(path, { force: true });
	}
};
async function inspectDeliveryEntry(path) {
	let entry;
	try {
		entry = await lstat(path);
	} catch (error) {
		if (error.code === "ENOENT") return { kind: "missing" };
		throw error;
	}
	if (entry.isSymbolicLink()) {
		const target = await readlink(path);
		return {
			kind: "symlink",
			target,
			targetPath: normalize(isAbsolute(target) ? target : resolve(dirname(path), target))
		};
	}
	if (entry.isFile()) return { kind: "file" };
	if (entry.isDirectory()) return { kind: "directory" };
	return { kind: "special" };
}
function linkMatches(entry, source) {
	return entry.kind === "symlink" && entry.targetPath === normalize(resolve(source));
}
function temporaryPath(destination) {
	return join(dirname(destination), `.${destination.split("/").pop()}.delivery-${process.pid}-${Date.now()}-${Math.random().toString(16).slice(2)}`);
}
function assertReplaceable(entry, destination) {
	if (entry.kind === "directory" || entry.kind === "special") throw new Error(`delivery destination is not a regular file or symlink: ${destination}`);
}
async function physicalParent(path) {
	const parent = dirname(resolve(path));
	try {
		return await realpath(parent);
	} catch (error) {
		if (error.code !== "ENOENT" || dirname(parent) === parent) throw error;
		return join(await physicalParent(parent), basename(parent));
	}
}
/** Compare directory entries without following either final entry. */
async function pathsSharePhysicalEntry(first, second) {
	if (normalize(resolve(first)) === normalize(resolve(second))) return true;
	const [firstParent, secondParent] = await Promise.all([physicalParent(first), physicalParent(second)]);
	return firstParent === secondParent && basename(first) === basename(second);
}
async function assertDistinct(source, destination) {
	if (await pathsSharePhysicalEntry(source, destination)) throw new Error(`delivery source and destination resolve to the same directory entry: ${source}`);
}
async function replaceWithLink(source, destination, executor = localLinkDeliveryExecutor) {
	await assertDistinct(source, destination);
	assertReplaceable(await inspectDeliveryEntry(destination), destination);
	await executor.mkdir(dirname(destination));
	const temporary = temporaryPath(destination);
	try {
		await executor.symlink(source, temporary);
		await executor.rename(temporary, destination);
	} catch (error) {
		await executor.rm(temporary).catch(() => void 0);
		throw error;
	}
}
async function replaceWithCopy(source, destination, executor = localCopyDeliveryExecutor) {
	await assertDistinct(source, destination);
	const sourceStat = await stat(source);
	if (!sourceStat.isFile()) throw new Error(`delivery source is not a regular file: ${source}`);
	assertReplaceable(await inspectDeliveryEntry(destination), destination);
	await executor.mkdir(dirname(destination));
	const temporary = temporaryPath(destination);
	try {
		await executor.copyFile(source, temporary);
		await executor.chmod(temporary, sourceStat.mode & 511);
		await executor.rename(temporary, destination);
	} catch (error) {
		await executor.rm(temporary).catch(() => void 0);
		throw error;
	}
}
//#endregion
//#region files/links/operations.ts
/** LINKS representation assessment and bounded filesystem mutations. */
const _execFile = promisify(execFile);
async function destWritable(destPath) {
	let dir = dirname(destPath);
	for (;;) try {
		await access(dir, constants.W_OK | constants.X_OK);
		return true;
	} catch (error) {
		if (error.code === "ENOENT" && dirname(dir) !== dir) {
			dir = dirname(dir);
			continue;
		}
		return false;
	}
}
async function needsSudo(sudoMode, scope, destPath) {
	if (scope === "user") return false;
	if (sudoMode === "always") return true;
	if (sudoMode === "never") return false;
	return !await destWritable(destPath);
}
function linkExecutor(sudo) {
	if (!sudo) return localLinkDeliveryExecutor;
	return {
		async mkdir(path) {
			await _execFile("sudo", [
				"mkdir",
				"-p",
				"--",
				path
			]);
		},
		async symlink(source, destination) {
			await _execFile("sudo", [
				"ln",
				"-s",
				"--",
				source,
				destination
			]);
		},
		async rename(source, destination) {
			await _execFile("sudo", [
				"mv",
				"-T",
				"--",
				source,
				destination
			]);
		},
		async rm(path) {
			await _execFile("sudo", [
				"rm",
				"-f",
				"--",
				path
			]);
		}
	};
}
function copyExecutor(sudo) {
	if (!sudo) return localCopyDeliveryExecutor;
	return {
		async mkdir(path) {
			await _execFile("sudo", [
				"mkdir",
				"-p",
				"--",
				path
			]);
		},
		async copyFile(source, destination) {
			await _execFile("sudo", [
				"cp",
				"--",
				source,
				destination
			]);
		},
		async chmod(path, mode) {
			await _execFile("sudo", [
				"chmod",
				mode.toString(8),
				"--",
				path
			]);
		},
		async rename(source, destination) {
			await _execFile("sudo", [
				"mv",
				"-T",
				"--",
				source,
				destination
			]);
		},
		async rm(path) {
			await _execFile("sudo", [
				"rm",
				"-f",
				"--",
				path
			]);
		}
	};
}
async function rmLink(path, sudo) {
	if (sudo) await _execFile("sudo", [
		"rm",
		"-f",
		"--",
		path
	]);
	else await rm(path);
}
async function sourceState(path) {
	let entryExists = false;
	try {
		await lstat(path);
		entryExists = true;
	} catch (error) {
		if (error.code !== "ENOENT") throw error;
	}
	try {
		const source = await stat(path);
		return {
			entryExists,
			regular: source.isFile()
		};
	} catch (error) {
		if (error.code === "ENOENT") return {
			entryExists,
			regular: false
		};
		throw error;
	}
}
async function filesMatch(source, destination) {
	const [sourceBytes, destinationBytes] = await Promise.all([readFile(source), readFile(destination)]);
	return sourceBytes.equals(destinationBytes);
}
async function inspectRecord(record) {
	const [entry, source] = await Promise.all([inspectDeliveryEntry(record.destPath), sourceState(record.srcPath)]);
	if (entry.kind === "missing") return {
		entry,
		kind: "missing",
		sourceEntryExists: source.entryExists,
		sourceRegular: source.regular
	};
	if (entry.kind === "directory") return {
		entry,
		kind: "directory",
		sourceEntryExists: source.entryExists,
		sourceRegular: source.regular
	};
	if (entry.kind === "special") return {
		entry,
		kind: "special",
		sourceEntryExists: source.entryExists,
		sourceRegular: source.regular
	};
	if (entry.kind === "symlink") {
		if (record.strategies.available.includes("link") && linkMatches(entry, record.srcPath)) return {
			entry,
			kind: "healthy",
			sourceEntryExists: source.entryExists,
			sourceRegular: source.regular,
			representation: "link",
			healthyRepresentation: "link"
		};
		let dangling = false;
		try {
			await stat(record.destPath);
		} catch (error) {
			if (error.code === "ENOENT") dangling = true;
			else throw error;
		}
		return {
			entry,
			kind: "foreign",
			sourceEntryExists: source.entryExists,
			sourceRegular: source.regular,
			representation: "link",
			detail: dangling ? "dangling link" : "foreign link"
		};
	}
	const healthy = record.strategies.available.includes("copy") && source.regular && await filesMatch(record.srcPath, record.destPath);
	return {
		entry,
		kind: healthy ? "healthy" : "foreign",
		sourceEntryExists: source.entryExists,
		sourceRegular: source.regular,
		representation: "copy",
		healthyRepresentation: healthy ? "copy" : void 0,
		detail: record.strategies.available.includes("copy") ? "copy bytes differ" : void 0
	};
}
function entryOf(assessment) {
	return assessment.entry.kind;
}
function commonRow(record, assessment) {
	return {
		id: record.id,
		scope: record.scope,
		src: record.state === "absent" ? "" : record.srcPath,
		dest: record.destPath,
		manifest: record.manifest,
		entry: entryOf(assessment),
		target: assessment.entry.kind === "symlink" ? assessment.entry.target : void 0,
		representation: assessment.representation
	};
}
function classifyAssessment(record, dest, selectedStrategy) {
	const common = { ...commonRow(record, dest) };
	if (record.state === "absent") {
		if (dest.kind === "missing") return {
			...common,
			status: "MANAGED",
			detail: "absent as requested"
		};
		if (dest.kind === "healthy") return {
			...common,
			status: "CONFLICT",
			detail: "should be absent"
		};
		return {
			...common,
			status: "OVERRIDE"
		};
	}
	if (!dest.sourceEntryExists) return {
		...common,
		status: "SOURCE_MISSING",
		detail: "src missing"
	};
	if (dest.kind === "healthy" && (!selectedStrategy || dest.healthyRepresentation === selectedStrategy)) return {
		...common,
		status: "MANAGED"
	};
	if ((selectedStrategy ?? record.strategies.default) === "copy" && !dest.sourceRegular) return {
		...common,
		status: "SOURCE_UNUSABLE",
		detail: "copy source does not resolve to a regular file"
	};
	if (dest.kind === "missing") return {
		...common,
		status: "MISSING"
	};
	if (dest.kind === "healthy") return {
		...common,
		status: "MANAGED"
	};
	if (record.policy === "preserve") return {
		...common,
		status: "OVERRIDE"
	};
	const detail = dest.kind === "directory" || dest.kind === "special" ? "never replaced" : dest.detail ? `${dest.detail}; ${record.policy} policy` : `${record.policy} policy`;
	return {
		...common,
		status: "CONFLICT",
		detail
	};
}
async function classifyRecord(record) {
	return classifyAssessment(record, await inspectRecord(record));
}
function overwriteSelected(id) {
	const setting = process.env.COMPFUZOR_LINK_OVERWRITE?.trim();
	if (!setting) return false;
	if ([
		"1",
		"true",
		"y",
		"yes",
		"*"
	].includes(setting.toLowerCase())) return true;
	return setting.split(",").map((part) => part.trim()).filter(Boolean).some((pattern) => globMatches(pattern, id));
}
async function removeManaged(record, action, sudoMode) {
	const sudo = await needsSudo(sudoMode, record.scope, record.destPath);
	const dest = await inspectRecord(record);
	const common = commonRow(record, dest);
	if (dest.kind === "healthy") {
		await rmLink(record.destPath, sudo);
		return {
			...common,
			status: "MANAGED",
			action,
			detail: sudo ? "via sudo" : void 0
		};
	}
	if (dest.kind === "missing") return {
		...common,
		status: "MANAGED",
		action: "unchanged",
		detail: "already absent"
	};
	return {
		...common,
		status: "OVERRIDE",
		action: "preserved"
	};
}
async function deliver(record, strategy, sudo) {
	if (strategy === "link") await replaceWithLink(record.srcPath, record.destPath, linkExecutor(sudo));
	else await replaceWithCopy(record.srcPath, record.destPath, copyExecutor(sudo));
}
async function applyRecord(record, options) {
	const selectedStrategy = options.strategy;
	if (record.state === "absent") return removeManaged(record, "removed", options.sudoMode);
	const sudo = await needsSudo(options.sudoMode, record.scope, record.destPath);
	const dest = await inspectRecord(record);
	let row = classifyAssessment(record, dest, selectedStrategy);
	if (row.status === "SOURCE_MISSING" || row.status === "SOURCE_UNUSABLE") return row;
	const strategy = selectedStrategy ?? record.strategies.default;
	if (dest.kind === "missing") {
		await deliver(record, strategy, sudo);
		return {
			...row,
			status: "MANAGED",
			action: "created",
			entry: strategy === "link" ? "symlink" : "file",
			target: strategy === "link" ? record.srcPath : void 0,
			representation: strategy,
			detail: sudo ? "via sudo" : void 0
		};
	}
	if (dest.kind === "healthy" && (!selectedStrategy || dest.healthyRepresentation === selectedStrategy)) return {
		...row,
		action: "unchanged"
	};
	if (dest.kind === "healthy") {
		await deliver(record, strategy, sudo);
		return {
			...row,
			status: "MANAGED",
			action: "switched",
			entry: strategy === "link" ? "symlink" : "file",
			target: strategy === "link" ? record.srcPath : void 0,
			representation: strategy,
			detail: sudo ? "via sudo" : void 0
		};
	}
	if (!(record.policy === "replace" || record.policy === "preserve" && overwriteSelected(record.id)) || dest.kind !== "foreign") return {
		...row,
		action: "preserved"
	};
	await deliver(record, strategy, sudo);
	row = {
		...row,
		status: "MANAGED",
		action: "replaced",
		entry: strategy === "link" ? "symlink" : "file",
		target: strategy === "link" ? record.srcPath : void 0,
		representation: strategy,
		detail: sudo ? "via sudo" : void 0
	};
	return row;
}
async function removeRecord(record, sudoMode) {
	return removeManaged(record, "removed", sudoMode);
}
//#endregion
//#region files/links/links.ts
const DIR = process.env.DIR ?? dirname(dirname(dirname(fileURLToPath(import.meta.url))));
function fail(message) {
	throw new Error(message);
}
async function audit(paths, scope, idPatterns) {
	const records = [];
	const invalid = [];
	for (const input of paths) {
		const loaded = await loadManifest(input);
		const resolved = resolveRecords(loaded.path, loaded.manifest, scope, idPatterns);
		records.push(...resolved.records.filter((record) => record.state === "present"));
		invalid.push(...resolved.invalid);
	}
	const groups = /* @__PURE__ */ new Map();
	for (const record of records) {
		const key = `${record.scope}\0${record.destPath}`;
		groups.set(key, [...groups.get(key) ?? [], record]);
	}
	return invalid.concat(records.map((record) => {
		const group = groups.get(`${record.scope}\0${record.destPath}`) ?? [];
		const conflict = group.some((other) => other.srcPath !== record.srcPath || other.policy !== record.policy || other.compose !== record.compose || other.strategies.default !== record.strategies.default || other.strategies.available.join("\0") !== record.strategies.available.join("\0"));
		return {
			id: record.id,
			scope: record.scope,
			status: conflict ? "CONFLICT" : "MANAGED",
			src: record.srcPath,
			dest: record.destPath,
			manifest: record.manifest,
			detail: conflict ? `${group.length} incompatible claims` : `${group.length} compatible claim${group.length === 1 ? "" : "s"}`
		};
	}));
}
/** Plain words for the human table; machine statuses stay unchanged. */
const HUMAN_STATUS = {
	MANAGED: "ok",
	OVERRIDE: "override",
	MISSING: "missing",
	CONFLICT: "conflict",
	SOURCE_MISSING: "no-source",
	SOURCE_UNUSABLE: "bad-source",
	INVALID: "invalid"
};
/** Verdict column: mutating verbs (created/replaced/removed) read better
* than ok+action, so the verb replaces the status word for those rows. */
function humanLineLabel(row) {
	return row.action ?? HUMAN_STATUS[row.status] ?? row.status;
}
/** src column: the plan's src (what the link should point at). */
function srcCell(row) {
	return row.src ?? "";
}
function output(rows, options) {
	if (options.quiet >= 2) return;
	const sourceError = rows.some((row) => row.status === "SOURCE_MISSING" || row.status === "SOURCE_UNUSABLE" || row.status === "INVALID");
	const drift = rows.some((row) => row.status === "MISSING" || row.status === "CONFLICT");
	if (options.quiet === 1) console.log(sourceError ? "ERROR" : drift ? "DRIFT" : "OK");
	else if (options.format === "jsonl") for (const row of rows) console.log(JSON.stringify(row));
	else if (options.format === "array") console.log(JSON.stringify(rows, null, 2));
	else {
		const visible = options.command === "apply" || options.command === "remove" ? rows.filter((row) => row.action !== "unchanged") : rows;
		if (visible.length === 0) return;
		console.log("status	dest	src	actual	note");
		for (const row of visible) {
			const note = row.detail ? `(${row.detail})` : "";
			const actual = row.entry === "symlink" && row.target !== void 0 ? row.target : row.entry === "file" || row.entry === "directory" || row.entry === "special" ? `(${row.entry})` : "";
			console.log([
				humanLineLabel(row),
				row.dest,
				srcCell(row),
				actual,
				note
			].map((cell) => cell === "" ? "\"\"" : cell).join("	"));
		}
	}
}
async function main() {
	const options = parseLinksArgs(process.argv.slice(2), join(DIR, "links.json"));
	const sudoMode = resolveSudoMode(options.sudo);
	if ([
		"1",
		"true",
		"y",
		"yes"
	].includes(process.env.COMPFUZOR_LINK_BYPASS?.trim().toLowerCase() ?? "")) return 0;
	let rows;
	if (options.command === "audit") rows = await audit(options.paths, options.scope, options.id);
	else {
		const loaded = await loadManifest(options.paths[0]);
		const resolved = resolveRecords(loaded.path, loaded.manifest, options.scope, options.id, options.composed);
		if ((options.command === "apply" || options.command === "remove") && sudoMode === "always" && resolved.records.some((record) => record.scope === "user")) fail("--sudo always is not permitted for user-scope link mutations");
		if (options.command === "apply" && options.strategy) {
			const unavailable = resolved.records.filter((record) => record.state === "present" && !record.strategies.available.includes(options.strategy));
			if (unavailable.length > 0) fail(`strategy ${options.strategy} is unavailable for: ${unavailable.map((record) => record.id).join(", ")}`);
			if (options.strategy === "copy") {
				const unusable = (await Promise.all(resolved.records.map(async (record) => ({
					record,
					source: await sourceState(record.srcPath)
				})))).filter(({ record, source }) => record.state === "present" && source.entryExists && !source.regular);
				if (unusable.length > 0) fail(`strategy copy requires a source that resolves to a regular file: ${unusable.map(({ record }) => record.id).join(", ")}`);
			}
		}
		const operation = options.command === "apply" ? (record) => applyRecord(record, {
			sudoMode,
			strategy: options.strategy
		}) : options.command === "remove" ? (record) => removeRecord(record, sudoMode) : classifyRecord;
		rows = [...resolved.invalid];
		if (resolved.invalid.length === 0 || options.command === "status") for (const record of resolved.records) rows.push(await operation(record));
	}
	output(rows, options);
	if (rows.some((row) => row.status === "SOURCE_MISSING" || row.status === "SOURCE_UNUSABLE" || row.status === "INVALID")) return 2;
	return rows.some((row) => row.status === "MISSING" || row.status === "CONFLICT") ? 1 : 0;
}
main().then((code) => {
	process.exitCode = code;
}, (error) => {
	console.error(error instanceof Error ? error.stack : String(error));
	process.exitCode = 2;
});
//#endregion
export {};
