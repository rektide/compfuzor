#!/usr/bin/env -S node --disable-warning=MODULE_TYPELESS_PACKAGE_JSON
import { createRequire } from "node:module";
import { access, chmod, constants, copyFile, lstat, mkdir, mkdtemp, readFile, readdir, readlink, realpath, rename, rm, stat, symlink, writeFile } from "node:fs/promises";
import { basename, dirname, isAbsolute, join, matchesGlob, normalize, relative, resolve, sep } from "node:path";
import { fileURLToPath } from "node:url";
import { execFile, spawn } from "node:child_process";
import { constants as constants$1, tmpdir } from "node:os";
import { parseArgs, promisify } from "node:util";
//#region \0rolldown/runtime.js
var __commonJSMin = (cb, mod) => () => (mod || (cb((mod = { exports: {} }).exports, mod), cb = null), mod.exports);
var __require = /* #__PURE__ */ (() => createRequire(import.meta.url))();
//#endregion
//#region files/config/context.ts
/** Import-safe consumer-context selection and path binding for CONFIGS specs. */
function fail$14(message) {
	throw new Error(message);
}
function object$5(value, label) {
	if (!value || typeof value !== "object" || Array.isArray(value)) fail$14(`${label} must be an object`);
	return value;
}
function knownRoot(name) {
	const home = process.env.HOME;
	if (name === "HOME") return home;
	if (name === "XDG_CONFIG_HOME") return process.env.XDG_CONFIG_HOME || (home ? join(home, ".config") : void 0);
	if (name === "XDG_STATE_HOME") return process.env.XDG_STATE_HOME || (home ? join(home, ".local", "state") : void 0);
	if (name === "XDG_CACHE_HOME") return process.env.XDG_CACHE_HOME || (home ? join(home, ".cache") : void 0);
	if (name === "XDG_DATA_HOME") return process.env.XDG_DATA_HOME || (home ? join(home, ".local", "share") : void 0);
}
function expandPath$1(value, base, label) {
	let expanded = value;
	if (value === "~" || value.startsWith("~/")) {
		const home = knownRoot("HOME") ?? fail$14(`${label}: HOME is required to expand ${value}`);
		if (value.slice(1).includes("$") || value.slice(1).includes("~")) fail$14(`${label}: unsupported runtime-root expression: ${value}`);
		expanded = home + value.slice(1);
	} else if (value.startsWith("${")) {
		const match = /^\$\{(HOME|XDG_CONFIG_HOME|XDG_STATE_HOME|XDG_CACHE_HOME|XDG_DATA_HOME)\}(?:\/|$)/.exec(value);
		if (!match) fail$14(`${label}: unsupported runtime-root expression: ${value}`);
		const root = knownRoot(match[1]) ?? fail$14(`${label}: ${match[1]} or HOME is required to expand ${value}`);
		const suffix = value.slice(match[0].length - (match[0].endsWith("/") ? 1 : 0));
		if (suffix.includes("$") || suffix.includes("~")) fail$14(`${label}: unsupported runtime-root expression: ${value}`);
		expanded = root + suffix;
	} else if (value.includes("$") || value.includes("~")) fail$14(`${label}: unsupported runtime-root expression: ${value}`);
	if (!isAbsolute(expanded)) {
		if (!base) fail$14(`${label}: resolved root must be absolute: ${expanded}`);
		expanded = resolve(base, expanded);
	}
	return normalize(expanded);
}
function resolvePathSelector(raw, base, label) {
	const selector = object$5(raw, label);
	if ([
		selector.path !== void 0,
		selector.relative !== void 0,
		selector.env !== void 0
	].filter(Boolean).length !== 1) fail$14(`${label} must contain exactly one of path, relative, or env`);
	if (selector.path !== void 0) {
		if (typeof selector.path !== "string" || !selector.path) fail$14(`${label}.path must be a non-empty string`);
		return expandPath$1(selector.path, void 0, `${label}.path`);
	}
	if (selector.relative !== void 0) {
		if (typeof selector.relative !== "string" || !selector.relative || !base) fail$14(`${label}.relative requires a context root`);
		const resolved = resolve(base, selector.relative);
		const fromBase = relative(base, resolved);
		if (fromBase === ".." || fromBase.startsWith(`..${process.platform === "win32" ? "\\" : "/"}`) || isAbsolute(fromBase)) fail$14(`${label}.relative escapes the context root`);
		return normalize(resolved);
	}
	if (typeof selector.env !== "string" || !selector.env) fail$14(`${label}.env must name an environment variable`);
	const environmentValue = process.env[selector.env];
	if (environmentValue && !selector.ignore?.includes(environmentValue)) return expandPath$1(environmentValue, base, `${label}.env(${selector.env})`);
	if (selector.default !== void 0) return resolvePathSelector(selector.default, base, `${label}.default`);
	fail$14(`${label}: environment variable ${selector.env} is required`);
}
function getConfigContext(spec, contextName) {
	if (spec.version !== 2) fail$14(`unsupported config spec version: ${String(spec.version)}; rerender the deployment (expected version 2)`);
	const context = object$5(object$5(spec.contexts, "config spec contexts")[contextName], `unknown config context ${contextName}`);
	if (context.scope !== "user" && context.scope !== "system") fail$14(`context ${contextName}: invalid scope`);
	object$5(context.configs, `context ${contextName}.configs`);
	return context;
}
function contextConfigNames(spec, contextName, applyOnly = false) {
	const context = getConfigContext(spec, contextName);
	const names = Object.keys(context.configs);
	if (!applyOnly) return names;
	return names.filter((name) => {
		return object$5(spec.configs[name], `context ${contextName}: missing source config ${name}`).apply !== false;
	});
}
function selectRecipeNames(spec, contextName, requested, applyOnly = true) {
	const available = contextConfigNames(spec, contextName);
	if (requested.length === 0) return contextConfigNames(spec, contextName, applyOnly);
	const seen = /* @__PURE__ */ new Set();
	for (const name of requested) {
		if (!available.includes(name)) fail$14(`unknown config in context ${contextName}: ${name}`);
		if (seen.has(name)) fail$14(`config selected more than once in context ${contextName}: ${name}`);
		seen.add(name);
	}
	return requested;
}
function bindContextConfigs(spec, contextName, names) {
	const context = getConfigContext(spec, contextName);
	for (const name of names) if (!(name in context.configs)) fail$14(`unknown config in context ${contextName}: ${name}`);
	const root = resolvePathSelector(context.root, void 0, `context ${contextName}.root`);
	const base = context.subpath ? resolve(root, context.subpath) : root;
	const contextConfigs = object$5(context.configs, `context ${contextName}.configs`);
	const resolvedConfigs = {};
	const outputs = /* @__PURE__ */ new Map();
	for (const name of names) {
		const source = object$5(spec.configs[name], `context ${contextName}: missing source config ${name}`);
		const binding = object$5(contextConfigs[name], `context ${contextName}.configs.${name}`);
		if (!Array.isArray(source.inputs) || !Array.isArray(binding.inputs) || source.inputs.length !== binding.inputs.length) fail$14(`context ${contextName}.configs.${name}: input bindings do not match the source recipe`);
		const output = resolvePathSelector(binding.output, base, `context ${contextName}.configs.${name}.output`);
		const prior = outputs.get(output);
		if (prior) fail$14(`context ${contextName}: configs ${prior} and ${name} resolve to the same output ${output}`);
		outputs.set(output, name);
		const inputs = source.inputs.map((rawInput, index) => {
			const input = { ...object$5(rawInput, `config ${name}.inputs[${index}]`) };
			const path = resolvePathSelector(binding.inputs[index], base, `context ${contextName}.configs.${name}.inputs[${index}]`);
			if (input.file !== void 0) input.file = path;
			else {
				input.directory = path;
				input.glob = join(path, String(input.pattern));
			}
			return input;
		});
		resolvedConfigs[name] = {
			...source,
			output,
			inputs
		};
	}
	return {
		...spec,
		configs: resolvedConfigs,
		contexts: void 0,
		remotes: {}
	};
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
/** Compare final regular-file referents. CONFIGS accepts equivalent topology;
* LINKS keeps using linkMatches() where the literal managed target is identity. */
async function linkResolvesToSameFile(entry, source) {
	if (entry.kind !== "symlink") return false;
	try {
		const [targetPath, sourcePath, targetStat, sourceStat] = await Promise.all([
			realpath(entry.targetPath),
			realpath(source),
			stat(entry.targetPath),
			stat(source)
		]);
		return targetStat.isFile() && sourceStat.isFile() && (targetPath === sourcePath || targetStat.dev === sourceStat.dev && targetStat.ino === sourceStat.ino);
	} catch (error) {
		if (error.code === "ENOENT") return false;
		throw error;
	}
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
async function physicalDirectory(path) {
	try {
		return await realpath(path);
	} catch (error) {
		if (error.code !== "ENOENT") throw error;
		return join(await physicalParent(path), basename(path));
	}
}
/** Compare directory locations, following a final directory symlink. */
async function pathsSharePhysicalDirectory(first, second) {
	const [firstDirectory, secondDirectory] = await Promise.all([physicalDirectory(first), physicalDirectory(second)]);
	return firstDirectory === secondDirectory;
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
//#region files/config/assembly.ts
/** Bind CONFIG recipes to one context and invoke the sole transaction runner. */
async function assertContextOutputsSeparated(source, resolved) {
	for (const [name, config] of Object.entries(resolved.configs)) {
		const canonical = source.configs[name]?.output;
		if (canonical && await pathsSharePhysicalEntry(canonical, config.output)) throw new Error(`context output aliases canonical output for ${name}: ${config.output}`);
	}
}
function signalExitCode(signal) {
	const number = constants$1.signals[signal];
	return typeof number === "number" ? 128 + number : 1;
}
async function invokeRunner(options, specPath) {
	const runnerDirectory = dirname(options.runner);
	const runnerDeploymentDir = resolve(runnerDirectory, basename(runnerDirectory) === "config" ? "../.." : "..");
	const args = [
		...options.check ? ["--check"] : [],
		...options.stdout ? ["--stdout"] : [],
		...options.quiet ? ["--quiet"] : [],
		...options.names
	];
	return await new Promise((complete, reject) => {
		const stdio = options.stdio === "pipe" ? [
			"ignore",
			"pipe",
			"pipe"
		] : options.stdio ?? "inherit";
		const child = spawn(options.runner, args, {
			cwd: runnerDeploymentDir,
			detached: true,
			env: {
				...process.env,
				DIR: runnerDeploymentDir,
				CONFIG_SPEC: specPath
			},
			stdio
		});
		const stdout = [];
		const stderr = [];
		child.stdout?.on("data", (chunk) => stdout.push(Buffer.from(chunk)));
		child.stderr?.on("data", (chunk) => stderr.push(Buffer.from(chunk)));
		const handlers = /* @__PURE__ */ new Map();
		const cleanupHandlers = () => {
			for (const [signal, handler] of handlers) process.off(signal, handler);
		};
		for (const signal of [
			"SIGINT",
			"SIGHUP",
			"SIGTERM"
		]) {
			const handler = () => {
				if (child.pid === void 0) return;
				try {
					process.kill(-child.pid, signal);
				} catch (error) {
					if (error.code !== "ESRCH") reject(error);
				}
			};
			handlers.set(signal, handler);
			process.on(signal, handler);
		}
		child.once("error", (error) => {
			cleanupHandlers();
			reject(error);
		});
		child.once("exit", (code, signal) => {
			cleanupHandlers();
			complete({
				code: signal ? signalExitCode(signal) : code ?? 1,
				stdout: Buffer.concat(stdout),
				stderr: Buffer.concat(stderr)
			});
		});
	});
}
async function runAssemblyResult(options) {
	const resolvedSpec = bindContextConfigs(options.spec, options.contextName, options.names);
	if (!getConfigContext(options.spec, options.contextName).canonical && !options.check && !options.stdout) await assertContextOutputsSeparated(options.spec, resolvedSpec);
	const temporary = await mkdtemp(join(tmpdir(), "compfuzor-config-context-"));
	const resolvedPath = join(temporary, "config.spec.json");
	try {
		await writeFile(resolvedPath, JSON.stringify(resolvedSpec), { mode: 384 });
		return await invokeRunner(options, resolvedPath);
	} finally {
		await rm(temporary, {
			recursive: true,
			force: true
		});
	}
}
async function runAssembly(options) {
	return (await runAssemblyResult(options)).code;
}
async function evaluateAssembly(options, name) {
	try {
		const result = await runAssemblyResult({
			...options,
			names: [name],
			stdout: true,
			stdio: "pipe"
		});
		if (result.code === 0) return { candidate: result.stdout };
		const detail = result.stderr.toString("utf8").trim();
		return { error: `assembly candidate failed (exit ${result.code})${detail ? `: ${detail}` : ""}` };
	} catch (error) {
		return { error: `assembly candidate could not run: ${error instanceof Error ? error.message : String(error)}` };
	}
}
//#endregion
//#region files/config/cli.ts
/** CONFIG's fixed command vocabulary, argument parsing, aliases, and help. */
const CONFIG_ACTIONS = [
	"install",
	"assemble",
	"sync-inputs",
	"publish",
	"inputs",
	"status"
];
const GENERAL_HELP = `Usage: config-ACTION.sh [OPTIONS] [CONFIG ...]

Fixed actions:
  config-install.sh       Install selected recipes
  config-assemble.sh      Assemble or inspect candidates
  config-sync-inputs.sh   Seed or refresh consumer inputs
  config-publish.sh       Copy or link canonical outputs
  config-inputs.sh        Inspect or mutate consumer inputs
  config-status.sh        Report input, assembly, and output health

Run a fixed command with --help for its action-specific options.`;
const ACTION_HELP = {
	install: `Usage: config-install.sh [--context NAME] [--strategy assemble|copy|link] [--dropins copy|link] [CONFIG ...]

Install selected CONFIG recipes into a context. With no CONFIG names, selects
the context's apply:true recipes.

Options:
  --context NAME                 Select a declared context
  --strategy assemble|copy|link Override the context install strategy
  --dropins copy|link            Override input delivery for assembly

Discover recipes with config-assemble.sh --list.`,
	assemble: `Usage: config-assemble.sh [--context NAME] [--check|--stdout|--list] [CONFIG ...]

Assemble selected CONFIG recipes in one transaction. With no CONFIG names,
selects the context's apply:true recipes.

Options:
  --context NAME  Select a declared context
  --check         Show differences without changing outputs
  --stdout        Write one selected candidate byte-for-byte
  --list          List recipes declared in the selected context
  -q, --quiet     Suppress runner progress`,
	"sync-inputs": `Usage: config-sync-inputs.sh [--context NAME] [--strategy copy|link] [--seed] [CONFIG ...]

Synchronize canonical inputs into a consumer context. Refresh is the default;
--seed preserves every existing consumer entry.

Options:
  --context NAME       Select a declared context
  --strategy copy|link Select input representation
  --seed               Create missing entries without replacing existing ones`,
	publish: `Usage: config-publish.sh [--context NAME] --strategy copy|link [CONFIG ...]

Publish canonical outputs as whole files or links in a consumer context.

Options:
  --context NAME       Select a declared context
  --strategy copy|link Select output representation (required unless set by
                       COMPFUZOR_CONFIG_PUBLISH_STRATEGY)`,
	inputs: `Usage: config-inputs.sh [--context NAME] SUBACTION ...

Inspect or mutate consumer inputs.

Subactions:
  list [CONFIG ...]
  status [CONFIG ...] [--json|--json-array]
  put CONFIG/INPUT SOURCE [NAME] [--strategy copy|link] [--disabled] [--no-rebuild]
  enable CONFIG/INPUT NAME
  disable CONFIG/INPUT NAME
  remove CONFIG/INPUT [NAME]

Use CONFIG/INPUT when an input name is ambiguous across recipes.`,
	status: `Usage: config-status.sh [--context NAME] [--json|--json-array] [CONFIG ...]

Report selected CONFIG recipes: consumer inputs, assembly readiness, and
installed output representation. Exit 0 is clean, 1 is drift, and 2 is an
evaluation error.

Options:
  --context NAME  Select a declared context
  --json          Emit one JSON row per line
  --json-array    Emit one JSON array`
};
function fail$13(message) {
	throw new Error(message);
}
function explicitHelpAction(argv) {
	for (let index = 0; index < argv.length; index++) {
		const argument = argv[index];
		const value = argument === "--action" ? argv[index + 1] : argument.startsWith("--action=") ? argument.slice(9) : void 0;
		if (value && CONFIG_ACTIONS.includes(value)) return value;
	}
}
function invokedHelpAction(invokedAs) {
	const fixed = CONFIG_ACTIONS.find((action) => invokedAs === `config-${action}.sh`);
	if (fixed) return fixed;
	return [...CONFIG_ACTIONS].sort((first, second) => second.length - first.length).find((action) => invokedAs.endsWith(`-${action}.sh`));
}
function configHelp(invokedAs, argv) {
	const action = explicitHelpAction(argv) ?? invokedHelpAction(invokedAs);
	return action ? ACTION_HELP[action] : GENERAL_HELP;
}
function parseConfigCommandArgs(argv, deploymentDir, invokedAs) {
	const { values, positionals: args, tokens } = parseArgs({
		args: argv,
		strict: true,
		allowPositionals: true,
		tokens: true,
		options: {
			action: { type: "string" },
			context: { type: "string" },
			spec: { type: "string" },
			runner: { type: "string" },
			strategy: { type: "string" },
			dropins: { type: "string" },
			seed: { type: "boolean" },
			"no-rebuild": { type: "boolean" },
			disabled: { type: "boolean" },
			json: { type: "boolean" },
			"json-array": { type: "boolean" },
			check: { type: "boolean" },
			stdout: { type: "boolean" },
			list: { type: "boolean" },
			quiet: {
				type: "boolean",
				short: "q"
			},
			help: {
				type: "boolean",
				short: "h"
			}
		}
	});
	if (values.help) {
		console.log(configHelp(invokedAs, argv));
		process.exit(0);
	}
	const formatToken = tokens.findLast((token) => token.kind === "option" && (token.name === "json" || token.name === "json-array"));
	const format = formatToken?.name === "json-array" ? "array" : formatToken?.name === "json" ? "jsonl" : "human";
	return {
		action: values.action,
		context: values.context,
		invokedAs,
		specPath: resolve(values.spec ?? join(deploymentDir, "etc", "config.spec.json")),
		runner: resolve(values.runner ?? join(deploymentDir, "bin", "config", "run.sh")),
		strategy: values.strategy,
		dropins: values.dropins,
		seed: values.seed ?? false,
		rebuild: !(values["no-rebuild"] ?? false),
		initiallyDisabled: values.disabled ?? false,
		format,
		check: values.check ?? false,
		stdout: values.stdout ?? false,
		list: values.list ?? false,
		quiet: values.quiet ?? false,
		args
	};
}
function configAliasPieces(options, contextNames) {
	if (options.action !== void 0 && options.context !== void 0) return {};
	if (options.invokedAs === "command.ts") return {};
	const fixed = CONFIG_ACTIONS.find((action) => options.invokedAs === `config-${action}.sh`);
	if (fixed) return { action: options.action === void 0 ? fixed : void 0 };
	if (!options.invokedAs.startsWith("config-") || !options.invokedAs.endsWith(".sh")) fail$13(`unsupported config command alias ${options.invokedAs}; use a fixed config-ACTION.sh command or explicit --action and --context`);
	const body = options.invokedAs.slice(7, -3);
	const full = contextNames.flatMap((context) => CONFIG_ACTIONS.filter((action) => body === `${context}-${action}`).map((action) => ({
		action,
		context
	})));
	if (options.action === void 0 && options.context === void 0) {
		if (full.length !== 1) fail$13(`unknown or ambiguous config command alias ${options.invokedAs}`);
		return full[0];
	}
	if (options.action === void 0) {
		const actions = CONFIG_ACTIONS.filter((candidate) => body.endsWith(`-${candidate}`));
		const longest = Math.max(...actions.map((candidate) => candidate.length), -1);
		const selected = actions.filter((candidate) => candidate.length === longest);
		if (selected.length !== 1) fail$13(`unknown or ambiguous action in config command alias ${options.invokedAs}`);
		return { action: selected[0] };
	}
	const contexts = contextNames.filter((candidate) => body === candidate || body.startsWith(`${candidate}-`));
	const longest = Math.max(...contexts.map((candidate) => candidate.length), -1);
	const selected = contexts.filter((candidate) => candidate.length === longest);
	if (selected.length !== 1) fail$13(`unknown or ambiguous context in config command alias ${options.invokedAs}`);
	return { context: selected[0] };
}
function rejectIrrelevantFlags(options, action) {
	if (action !== "assemble" && (options.check || options.stdout || options.list || options.quiet)) fail$13(`${action} does not accept assembly display flags`);
	if (action !== "status" && action !== "inputs" && options.format !== "human") fail$13(`${action} does not accept status format flags`);
	if (action !== "sync-inputs" && options.seed) fail$13(`${action} does not accept --seed`);
	if (action !== "inputs" && (!options.rebuild || options.initiallyDisabled)) fail$13(`${action} does not accept input mutation flags`);
	if (action !== "install" && options.dropins !== void 0) fail$13(`${action} does not accept --dropins`);
}
//#endregion
//#region files/config/file-state.ts
/** Shared regular-file availability and byte comparison observations. */
async function compareFileContents(first, second) {
	try {
		const [one, two] = await Promise.all([readFile(first), readFile(second)]);
		return { equal: one.equals(two) };
	} catch (error) {
		return {
			equal: false,
			error: `cannot compare ${first} and ${second}: ${error instanceof Error ? error.message : String(error)}`
		};
	}
}
async function inspectUsableFile(path) {
	const entry = await inspectDeliveryEntry(path);
	if (entry.kind === "missing") return {
		usable: false,
		note: "donor entry missing"
	};
	if (entry.kind === "directory" || entry.kind === "special") return {
		usable: false,
		note: `donor entry is ${entry.kind}`
	};
	try {
		if (!(await stat(path)).isFile()) return {
			usable: false,
			note: "donor entry does not resolve to a regular file"
		};
	} catch (error) {
		if (error.code === "ENOENT") return {
			usable: false,
			note: "donor entry is dangling"
		};
		return {
			usable: false,
			note: error instanceof Error ? error.message : String(error)
		};
	}
	return { usable: true };
}
//#endregion
//#region files/config/input-state.ts
/** Consumer input catalog, synchronization, and status observation. */
function fail$12(message) {
	throw new Error(message);
}
function object$4(value, label) {
	if (!value || typeof value !== "object" || Array.isArray(value)) fail$12(`${label} must be an object`);
	return value;
}
function filenameMatches$1(value, pattern) {
	return matchesGlob(`x${value}`, `x${pattern}`);
}
function inputIdentity$1(input, index) {
	return typeof input.name === "string" && input.name ? input.name : String(index);
}
async function pathKind(path) {
	return (await inspectDeliveryEntry(path)).kind;
}
async function readDirectory(path) {
	try {
		return await readdir(path, {
			withFileTypes: true,
			encoding: "utf8"
		});
	} catch (error) {
		if (error.code === "ENOENT") return void 0;
		throw error;
	}
}
async function inputCatalog(spec, contextName, names) {
	const resolved = bindContextConfigs(spec, contextName, names);
	const relations = [];
	const directories = [];
	const rows = [];
	for (const configName of names) {
		const donorConfig = object$4(spec.configs[configName], `config ${configName}`);
		const localConfig = object$4(resolved.configs[configName], `resolved config ${configName}`);
		for (let index = 0; index < donorConfig.inputs.length; index++) {
			const donor = donorConfig.inputs[index];
			const local = localConfig.inputs[index];
			const name = inputIdentity$1(donor, index);
			if (typeof donor.file === "string" && typeof local.file === "string") {
				const aliasHazard = await pathsSharePhysicalEntry(donor.file, local.file) ? `consumer file aliases canonical input: ${local.file}` : void 0;
				relations.push({
					id: `${configName}/${name}`,
					config: configName,
					inputIndex: index,
					inputName: name,
					source: donor.file,
					destination: local.file,
					logicalName: basename(local.file),
					donorState: "enabled",
					aliasHazard
				});
				continue;
			}
			if (typeof donor.directory !== "string" || typeof donor.pattern !== "string" || typeof local.directory !== "string") fail$12(`config ${configName} input ${index} has an invalid compiled shape`);
			const suffix = typeof donor.disabled_suffix === "string" ? donor.disabled_suffix : void 0;
			const directory = {
				config: configName,
				inputIndex: index,
				inputName: name,
				donorDirectory: donor.directory,
				destinationDirectory: local.directory,
				pattern: donor.pattern,
				suffix,
				donorNames: /* @__PURE__ */ new Set(),
				aliasHazard: await pathsSharePhysicalDirectory(donor.directory, local.directory) ? `consumer directory aliases canonical input directory: ${local.directory}` : void 0
			};
			directories.push(directory);
			const entries = await readDirectory(donor.directory);
			if (entries === void 0) {
				rows.push({
					kind: "input",
					status: "donor-missing",
					severity: "error",
					config: configName,
					name,
					source: donor.directory,
					destination: local.directory,
					note: "donor input directory is missing"
				});
				continue;
			}
			const byLogical = /* @__PURE__ */ new Map();
			for (const entry of entries.sort((a, b) => a.name.localeCompare(b.name))) {
				const disabled = suffix !== void 0 && entry.name.endsWith(suffix);
				const logicalName = disabled ? entry.name.slice(0, -suffix.length) : entry.name;
				if (!filenameMatches$1(logicalName, donor.pattern)) continue;
				const source = join(donor.directory, entry.name);
				const relation = {
					id: `${configName}/${name}/${logicalName}`,
					config: configName,
					inputIndex: index,
					inputName: name,
					source,
					destinationDirectory: local.directory,
					destination: join(local.directory, entry.name),
					logicalName,
					pattern: donor.pattern,
					suffix,
					donorState: disabled ? "disabled" : "enabled"
				};
				const previous = byLogical.get(logicalName);
				if (previous) {
					previous.donorConflict = source;
					continue;
				}
				byLogical.set(logicalName, relation);
				directory.donorNames.add(logicalName);
			}
			relations.push(...byLogical.values());
		}
	}
	return {
		relations,
		directories,
		rows
	};
}
async function localSelection(relation) {
	if (!relation.destinationDirectory || !relation.suffix) {
		const entry = await inspectDeliveryEntry(relation.destination);
		return {
			active: relation.destination,
			activeEntry: entry,
			selectedPath: entry.kind === "missing" ? void 0 : relation.destination,
			selectedState: entry.kind === "missing" ? void 0 : "enabled",
			selectedEntry: entry.kind === "missing" ? void 0 : entry,
			conflict: false
		};
	}
	const active = join(relation.destinationDirectory, relation.logicalName);
	const disabled = `${active}${relation.suffix}`;
	const [activeEntry, disabledEntry] = await Promise.all([inspectDeliveryEntry(active), inspectDeliveryEntry(disabled)]);
	const hasActive = activeEntry.kind !== "missing";
	const hasDisabled = disabledEntry.kind !== "missing";
	return {
		active,
		disabled,
		activeEntry,
		disabledEntry,
		selectedPath: hasActive ? active : hasDisabled ? disabled : void 0,
		selectedState: hasActive ? "enabled" : hasDisabled ? "disabled" : void 0,
		selectedEntry: hasActive ? activeEntry : hasDisabled ? disabledEntry : void 0,
		conflict: hasActive && hasDisabled
	};
}
async function deliver$2(source, destination, strategy) {
	if (strategy === "link") await replaceWithLink(source, destination);
	else await replaceWithCopy(source, destination);
}
async function applyRelation(relation, strategy, seed) {
	if (relation.aliasHazard) fail$12(`${relation.id}: ${relation.aliasHazard}`);
	if (relation.donorConflict) fail$12(`${relation.id}: donor has both enabled and disabled entries`);
	const sourceEntry = await inspectDeliveryEntry(relation.source);
	if (sourceEntry.kind === "missing" || sourceEntry.kind === "directory" || sourceEntry.kind === "special") fail$12(`${relation.id}: donor source is ${sourceEntry.kind}: ${relation.source}`);
	const local = await localSelection(relation);
	if (local.conflict) fail$12(`${relation.id}: both enabled and disabled local entries exist`);
	if (seed && local.selectedPath) return `preserved\t${relation.id}\t${local.selectedState}\t${local.selectedPath}`;
	const state = local.selectedState ?? relation.donorState;
	const destination = state === "disabled" && relation.suffix && relation.destinationDirectory ? join(relation.destinationDirectory, `${relation.logicalName}${relation.suffix}`) : relation.destinationDirectory ? join(relation.destinationDirectory, relation.logicalName) : relation.destination;
	await deliver$2(relation.source, destination, strategy);
	return `${seed ? "seeded" : "refreshed"}\t${relation.id}\t${state}\t${strategy}\t${destination}`;
}
async function syncInputs(options) {
	const catalog = await inputCatalog(options.spec, options.contextName, options.names);
	let failed = catalog.rows.some((row) => row.severity === "error");
	for (const row of catalog.rows) console.error(`${row.status}: ${row.config}/${row.name}: ${row.note}`);
	const aliasHazards = [...catalog.relations.filter((relation) => relation.aliasHazard).map((relation) => `${relation.id}: ${relation.aliasHazard}`), ...catalog.directories.filter((directory) => directory.aliasHazard).map((directory) => `${directory.config}/${directory.inputName}: ${directory.aliasHazard}`)];
	if (aliasHazards.length > 0) {
		for (const hazard of aliasHazards) console.error(`error: ${hazard}`);
		return 2;
	}
	for (const directory of catalog.directories) try {
		await mkdir(directory.destinationDirectory, { recursive: true });
	} catch (error) {
		failed = true;
		console.error(`error: cannot create input directory ${directory.destinationDirectory}: ${error instanceof Error ? error.message : String(error)}`);
	}
	for (const relation of catalog.relations) try {
		console.log(await applyRelation(relation, options.strategy, options.seed));
	} catch (error) {
		failed = true;
		console.error(`error: ${error instanceof Error ? error.message : String(error)}`);
	}
	return failed ? 2 : 0;
}
async function relationStatus(relation) {
	if (relation.aliasHazard) return {
		kind: "input",
		status: "alias-hazard",
		severity: "error",
		config: relation.config,
		name: relation.logicalName,
		source: relation.source,
		destination: relation.destination,
		note: relation.aliasHazard
	};
	if (relation.donorConflict) return {
		kind: "input",
		status: "donor-conflict",
		severity: "drift",
		config: relation.config,
		name: relation.logicalName,
		source: relation.source,
		destination: relation.destination,
		note: `also present as ${relation.donorConflict}`
	};
	const source = await inspectUsableFile(relation.source);
	const local = await localSelection(relation);
	if (local.conflict) return {
		kind: "input",
		status: "local-conflict",
		severity: "drift",
		config: relation.config,
		name: relation.logicalName,
		source: relation.source,
		destination: local.active,
		note: `both ${local.active} and ${local.disabled} exist`
	};
	if (!local.selectedPath || !local.selectedEntry) return {
		kind: "input",
		status: source.usable ? "missing" : "donor-missing",
		severity: source.usable ? "drift" : "error",
		config: relation.config,
		name: relation.logicalName,
		state: relation.donorState,
		source: relation.source,
		destination: relation.destination,
		note: source.note
	};
	const common = {
		kind: "input",
		config: relation.config,
		name: relation.logicalName,
		state: local.selectedState,
		source: relation.source,
		destination: local.selectedPath
	};
	if (!source.usable) return {
		...common,
		status: "donor-missing",
		severity: "error",
		representation: local.selectedEntry.kind,
		note: source.note
	};
	if (local.selectedEntry.kind === "symlink") try {
		if (await linkResolvesToSameFile(local.selectedEntry, relation.source)) return {
			...common,
			status: "ok",
			severity: "ok",
			representation: "link"
		};
	} catch (error) {
		return {
			...common,
			status: "evaluation-error",
			severity: "error",
			representation: "link",
			note: `cannot resolve link referents: ${error instanceof Error ? error.message : String(error)}`
		};
	}
	if (local.selectedEntry.kind === "file") {
		const comparison = await compareFileContents(relation.source, local.selectedPath);
		if (comparison.error) return {
			...common,
			status: "evaluation-error",
			severity: "error",
			representation: "copy",
			note: comparison.error
		};
		if (comparison.equal) return {
			...common,
			status: "ok",
			severity: "ok",
			representation: "copy"
		};
	}
	if (local.selectedEntry.kind === "directory" || local.selectedEntry.kind === "special") return {
		...common,
		status: "unsupported",
		severity: "drift",
		representation: local.selectedEntry.kind
	};
	return {
		...common,
		status: "modified",
		severity: "drift",
		representation: local.selectedEntry.kind === "file" ? "copy" : "link",
		note: local.selectedEntry.kind === "symlink" ? `points to ${local.selectedEntry.target}` : "bytes differ from donor"
	};
}
async function extraInputRows(directory) {
	const entries = await readDirectory(directory.destinationDirectory);
	if (entries === void 0) return [];
	const grouped = /* @__PURE__ */ new Map();
	for (const entry of entries) {
		const suffix = directory.suffix;
		const disabled = suffix !== void 0 && entry.name.endsWith(suffix);
		const logical = disabled ? entry.name.slice(0, -suffix.length) : entry.name;
		if (!filenameMatches$1(logical, directory.pattern) || directory.donorNames.has(logical)) continue;
		const group = grouped.get(logical) ?? {};
		group[disabled ? "disabled" : "active"] = join(directory.destinationDirectory, entry.name);
		grouped.set(logical, group);
	}
	const rows = [];
	for (const [logical, group] of [...grouped].sort(([a], [b]) => a.localeCompare(b))) {
		if (group.active && group.disabled) {
			rows.push({
				kind: "input",
				status: "local-conflict",
				severity: "drift",
				config: directory.config,
				name: logical,
				source: directory.donorDirectory,
				destination: group.active,
				note: `both active and disabled local entries exist`
			});
			continue;
		}
		const path = group.active ?? group.disabled;
		const entry = await inspectDeliveryEntry(path);
		let status = "local";
		let severity = entry.kind === "directory" || entry.kind === "special" ? "drift" : "ok";
		let note = "not present in current donor catalog";
		if (entry.kind === "symlink") {
			const donorRelative = normalize(entry.targetPath).startsWith(`${normalize(directory.donorDirectory)}/`);
			try {
				if (!(await stat(path)).isFile()) {
					status = "non-file-referent";
					severity = "drift";
					note = `local link resolves to a non-file: ${entry.target}`;
				}
			} catch (error) {
				if (error.code === "ENOENT") {
					status = donorRelative ? "donor-missing" : "dangling";
					severity = "error";
					note = donorRelative ? `dangling link into donor directory: ${entry.target}` : `local link has a missing referent: ${entry.target}`;
				} else {
					status = "evaluation-error";
					severity = "error";
					note = `cannot inspect local link referent: ${error instanceof Error ? error.message : String(error)}`;
				}
			}
		}
		rows.push({
			kind: "input",
			status,
			severity,
			config: directory.config,
			name: logical,
			state: group.disabled ? "disabled" : "enabled",
			representation: entry.kind,
			destination: path,
			note
		});
	}
	return rows;
}
async function inputStatusRows(spec, contextName, names) {
	const catalog = await inputCatalog(spec, contextName, names);
	const rows = [...catalog.rows];
	for (const relation of catalog.relations) rows.push(await relationStatus(relation));
	for (const directory of catalog.directories) {
		if (directory.aliasHazard) {
			rows.push({
				kind: "input",
				status: "alias-hazard",
				severity: "error",
				config: directory.config,
				name: directory.inputName,
				source: directory.donorDirectory,
				destination: directory.destinationDirectory,
				note: directory.aliasHazard
			});
			continue;
		}
		if (directory.donorNames.size === 0 && await pathKind(directory.destinationDirectory) === "missing") rows.push({
			kind: "input",
			status: "missing",
			severity: "drift",
			config: directory.config,
			name: directory.inputName,
			source: directory.donorDirectory,
			destination: directory.destinationDirectory,
			note: "empty consumer input directory is missing"
		});
		rows.push(...await extraInputRows(directory));
	}
	return rows;
}
//#endregion
//#region files/config/report.ts
function statusCode(rows) {
	if (rows.some((row) => row.severity === "error")) return 2;
	return rows.some((row) => row.severity === "drift") ? 1 : 0;
}
function printStatusRows(rows, format) {
	if (format === "array") {
		console.log(JSON.stringify(rows, null, 2));
		return;
	}
	if (format === "jsonl") {
		for (const row of rows) console.log(JSON.stringify(row));
		return;
	}
	if (rows.length === 0) return;
	console.log("kind	status	recipe	item	state	representation	source	destination	note");
	for (const row of rows) console.log([
		row.kind,
		row.status,
		row.config,
		row.name,
		row.state ?? "-",
		row.representation ?? "-",
		row.source ?? "-",
		row.destination ?? "-",
		row.note ?? "-"
	].join("	"));
}
//#endregion
//#region files/config/inputs.ts
/** Consumer input inventory and mutation operations. */
function fail$11(message) {
	throw new Error(message);
}
function filenameMatches(value, pattern) {
	return matchesGlob(`x${value}`, `x${pattern}`);
}
function inputIdentity(input, index) {
	return typeof input.name === "string" && input.name ? input.name : String(index);
}
async function deliver$1(source, destination, strategy) {
	if (strategy === "link") await replaceWithLink(source, destination);
	else await replaceWithCopy(source, destination);
}
function selectInput(spec, contextName, selector) {
	const slash = selector.indexOf("/");
	const configSelector = slash === -1 ? void 0 : selector.slice(0, slash);
	const inputSelector = slash === -1 ? selector : selector.slice(slash + 1);
	const matches = [];
	for (const config of contextConfigNames(spec, contextName)) {
		if (configSelector && config !== configSelector) continue;
		spec.configs[config].inputs.forEach((input, index) => {
			if (inputIdentity(input, index) === inputSelector) matches.push({
				config,
				index,
				source: input
			});
		});
	}
	if (matches.length !== 1) fail$11(matches.length === 0 ? `unknown context input: ${selector}` : `ambiguous context input: ${selector}; use CONFIG/INPUT`);
	const selected = matches[0];
	const consumer = bindContextConfigs(spec, contextName, [selected.config]).configs[selected.config].inputs[selected.index];
	return {
		...selected,
		consumer
	};
}
async function rebuild$1(options, config) {
	const code = await runAssembly({
		spec: options.spec,
		contextName: options.contextName,
		runner: options.runner,
		names: [config]
	});
	if (code === 0) return 0;
	console.error(`input mutation remains; config rebuild failed for ${config} (exit ${code})`);
	return 4;
}
function localInputPaths(selected, name) {
	if (typeof selected.consumer.directory !== "string") fail$11(`${selected.config}/${inputIdentity(selected.source, selected.index)} is not a glob input`);
	const suffix = typeof selected.source.disabled_suffix === "string" ? selected.source.disabled_suffix : void 0;
	return {
		active: join(selected.consumer.directory, name),
		disabled: suffix ? join(selected.consumer.directory, `${name}${suffix}`) : void 0
	};
}
async function assertInputBindingSeparated(selected) {
	if (typeof selected.source.file === "string" && typeof selected.consumer.file === "string") {
		if (await pathsSharePhysicalEntry(selected.source.file, selected.consumer.file)) fail$11(`${selected.config}/${inputIdentity(selected.source, selected.index)} consumer file aliases canonical input: ${selected.consumer.file}`);
		return;
	}
	if (typeof selected.source.directory === "string" && typeof selected.consumer.directory === "string" && await pathsSharePhysicalDirectory(selected.source.directory, selected.consumer.directory)) fail$11(`${selected.config}/${inputIdentity(selected.source, selected.index)} consumer directory aliases canonical input directory: ${selected.consumer.directory}`);
}
function validateInputName(input, name) {
	if (!name || basename(name) !== name || name === "." || name === "..") fail$11(`invalid input filename: ${name}`);
	if (typeof input.pattern !== "string" || !filenameMatches(name, input.pattern)) fail$11(`${name} does not match input pattern ${String(input.pattern)}`);
	if (typeof input.disabled_suffix === "string" && name.endsWith(input.disabled_suffix)) fail$11(`input filename must not include disabled suffix ${input.disabled_suffix}`);
}
async function inspectPair(paths) {
	const [active, disabled] = await Promise.all([inspectDeliveryEntry(paths.active), paths.disabled ? inspectDeliveryEntry(paths.disabled) : Promise.resolve(void 0)]);
	return {
		active,
		disabled,
		conflict: active.kind !== "missing" && disabled !== void 0 && disabled.kind !== "missing"
	};
}
function replaceableLocal(entry, path) {
	if (entry.kind === "directory" || entry.kind === "special") fail$11(`local input is not a regular file or symlink: ${path}`);
}
async function putInput(options) {
	const spec = options.spec;
	const selector = options.selector;
	const sourceArgument = options.source;
	const suppliedName = options.name;
	const selected = selectInput(spec, options.contextName, selector);
	await assertInputBindingSeparated(selected);
	const source = resolve(sourceArgument);
	if (typeof selected.source.file === "string") {
		if (suppliedName !== void 0) fail$11(`${selector} is a direct file input and does not accept a destination name`);
		if (options.initiallyDisabled ?? false) fail$11(`${selector} is a direct file input and cannot be disabled`);
		if (typeof selected.consumer.file !== "string") fail$11(`${selector} has an invalid resolved file binding`);
		await deliver$1(source, selected.consumer.file, options.strategy ?? getConfigContext(spec, options.contextName).dropins ?? "link");
		console.log(`put\t${selected.config}/${inputIdentity(selected.source, selected.index)}\t${selected.consumer.file}`);
		return options.rebuild ?? true ? rebuild$1(options, selected.config) : 0;
	}
	const name = suppliedName ?? basename(source);
	validateInputName(selected.source, name);
	const paths = localInputPaths(selected, name);
	const pair = await inspectPair(paths);
	if (pair.conflict) fail$11(`both enabled and disabled local entries exist for ${name}`);
	const destination = pair.active.kind !== "missing" ? paths.active : pair.disabled && pair.disabled.kind !== "missing" ? paths.disabled : options.initiallyDisabled ?? false ? paths.disabled ?? fail$11(`${selector} cannot be disabled`) : paths.active;
	await deliver$1(source, destination, options.strategy ?? getConfigContext(spec, options.contextName).dropins ?? "link");
	console.log(`put\t${selected.config}/${inputIdentity(selected.source, selected.index)}\t${destination}`);
	return options.rebuild ?? true ? rebuild$1(options, selected.config) : 0;
}
async function inputMutation(options, action, args) {
	const [selector, name] = args;
	if (!selector) fail$11(`usage: config-inputs.sh ${action} INPUT [NAME]`);
	const selected = selectInput(options.spec, options.contextName, selector);
	if (!getConfigContext(options.spec, options.contextName).canonical || action === "remove") await assertInputBindingSeparated(selected);
	if (typeof selected.source.file === "string") {
		if (action !== "remove") fail$11(`${selector} is a direct file input and cannot be ${action}d`);
		if (args.length !== 1) fail$11(`usage: config-inputs.sh remove DIRECT_INPUT`);
		if (typeof selected.consumer.file !== "string") fail$11(`${selector} has an invalid resolved file binding`);
		const entry = await inspectDeliveryEntry(selected.consumer.file);
		if (entry.kind === "missing") return 0;
		replaceableLocal(entry, selected.consumer.file);
		await rm(selected.consumer.file);
		console.log(`remove\t${selected.config}/${inputIdentity(selected.source, selected.index)}\t${selected.consumer.file}`);
		return rebuild$1(options, selected.config);
	}
	if (!name || args.length !== 2) fail$11(`usage: config-inputs.sh ${action} INPUT NAME`);
	validateInputName(selected.source, name);
	const paths = localInputPaths(selected, name);
	const pair = await inspectPair(paths);
	if (pair.conflict) fail$11(`both enabled and disabled local entries exist for ${name}`);
	if (action === "remove") {
		const path = pair.active.kind !== "missing" ? paths.active : pair.disabled && pair.disabled.kind !== "missing" ? paths.disabled : void 0;
		if (!path) return 0;
		replaceableLocal(path === paths.active ? pair.active : pair.disabled, path);
		await rm(path);
		console.log(`remove\t${selected.config}/${inputIdentity(selected.source, selected.index)}\t${path}`);
		return rebuild$1(options, selected.config);
	}
	if (!paths.disabled) fail$11(`${selected.config}/${inputIdentity(selected.source, selected.index)} cannot be disabled`);
	const from = action === "disable" ? paths.active : paths.disabled;
	const to = action === "disable" ? paths.disabled : paths.active;
	const fromEntry = action === "disable" ? pair.active : pair.disabled;
	if ((action === "disable" ? pair.disabled : pair.active).kind !== "missing") return 0;
	if (fromEntry.kind === "missing") fail$11(`local input does not exist: ${from}`);
	replaceableLocal(fromEntry, from);
	await rename(from, to);
	console.log(`${action}\t${selected.config}/${inputIdentity(selected.source, selected.index)}\t${to}`);
	return rebuild$1(options, selected.config);
}
async function listInputs(options, requested) {
	const names = selectRecipeNames(options.spec, options.contextName, requested, false);
	const resolved = bindContextConfigs(options.spec, options.contextName, names);
	for (const name of names) options.spec.configs[name].inputs.forEach((input, index) => {
		const local = resolved.configs[name].inputs[index];
		const donor = typeof input.file === "string" ? input.file : input.directory;
		const destination = typeof local.file === "string" ? local.file : local.directory;
		console.log(`${name}/${inputIdentity(input, index)}\t${donor}\t${destination}`);
	});
	return 0;
}
async function runInputAction(options, commandArgs) {
	const [action, ...args] = commandArgs;
	const spec = options.spec;
	if (action === "list") return listInputs(options, args);
	if (action === "status") {
		const names = selectRecipeNames(spec, options.contextName, args);
		const rows = await inputStatusRows(spec, options.contextName, names);
		printStatusRows(rows, options.format ?? "human");
		return statusCode(rows);
	}
	if (action === "put") {
		const [selector, source, name] = args;
		if (!selector || !source || args.length > 3) fail$11("usage: config-inputs.sh put INPUT SOURCE [NAME] [--strategy copy|link]");
		return putInput({
			...options,
			selector,
			source,
			name
		});
	}
	if (action === "enable" || action === "disable" || action === "remove") return inputMutation(options, action, args);
	fail$11("usage: config-inputs.sh <list|status|put|enable|disable|remove> ...");
}
//#endregion
//#region files/config/publication.ts
/** Whole-output publication for selected CONFIG recipes. */
async function publishOutputs(options) {
	const resolved = bindContextConfigs(options.spec, options.contextName, options.names);
	let failed = false;
	for (const name of options.names) {
		const source = options.spec.configs[name].output;
		const destination = resolved.configs[name].output;
		try {
			if (options.strategy === "link") await replaceWithLink(source, destination);
			else await replaceWithCopy(source, destination);
			console.log(`${options.strategy}\t${name}\t${source}\t${destination}`);
		} catch (error) {
			failed = true;
			console.error(`error: ${name}: ${error instanceof Error ? error.message : String(error)}`);
		}
	}
	return failed ? 2 : 0;
}
//#endregion
//#region files/config/install.ts
/** Complete ordinary CONFIG install over typed assembly and delivery operations. */
function truthy$1(value) {
	return [
		"1",
		"true",
		"y",
		"yes"
	].includes(value?.trim().toLowerCase() ?? "");
}
function resolve$1(value) {
	return typeof value === "function" ? value() : value;
}
async function installContext(options) {
	const reason = truthy$1(process.env.COMPFUZOR_CONFIG_CONTEXTS_BYPASS) ? "COMPFUZOR_CONFIG_CONTEXTS_BYPASS" : truthy$1(process.env.COMPFUZOR_CONFIG_BYPASS) ? "COMPFUZOR_CONFIG_BYPASS" : void 0;
	if (reason) return {
		status: "skipped",
		code: 0,
		reason
	};
	const strategy = resolve$1(options.strategy);
	if (strategy === "copy" || strategy === "link") return {
		status: "completed",
		code: await publishOutputs({
			...options,
			strategy
		})
	};
	if (!options.inputStrategy) throw new Error("assemble install requires an input strategy");
	const inputStrategy = resolve$1(options.inputStrategy);
	const seeded = await syncInputs({
		...options,
		strategy: inputStrategy,
		seed: true
	});
	if (seeded !== 0) return {
		status: "completed",
		code: seeded
	};
	return {
		status: "completed",
		code: await runAssembly({
			spec: options.spec,
			contextName: options.contextName,
			runner: options.runner,
			names: options.names
		})
	};
}
//#endregion
//#region files/config/invocation.ts
function fail$10(message) {
	throw new Error(message);
}
/**
* Resolve one declared name. Alias parsing is deliberately lazy: an explicit
* value completely bypasses it, allowing callers to escape stale aliases.
*/
function resolveSelectedName(options) {
	const declared = new Set(options.declared);
	const selected = options.explicit ?? options.inferAlias(options.invokedAs, declared) ?? options.environment ?? options.fallback;
	if (!declared.has(selected)) fail$10(`unknown ${options.label}: ${selected}`);
	return selected;
}
//#endregion
//#region files/config/status.ts
/** Multi-representation CONFIG status over selected recipes. */
async function candidateMatches(candidate, destination) {
	try {
		return { equal: candidate.equals(await readFile(destination)) };
	} catch (error) {
		return {
			equal: false,
			error: `cannot read assembled output ${destination}: ${error instanceof Error ? error.message : String(error)}`
		};
	}
}
async function outputStatusRows(options) {
	const resolved = bindContextConfigs(options.spec, options.contextName, options.names);
	const rows = [];
	for (const name of options.names) {
		const source = options.spec.configs[name].output;
		const destination = resolved.configs[name].output;
		const [sourceState, entry, assembly, aliasHazard] = await Promise.all([
			inspectUsableFile(source),
			inspectDeliveryEntry(destination),
			evaluateAssembly(options, name),
			pathsSharePhysicalEntry(source, destination)
		]);
		const common = {
			kind: "output",
			config: name,
			name,
			source,
			destination
		};
		rows.push(assembly.error ? {
			kind: "assembly",
			status: "evaluation-error",
			severity: "error",
			config: name,
			name,
			note: assembly.error
		} : {
			kind: "assembly",
			status: "ready",
			severity: "ok",
			config: name,
			name
		});
		if (aliasHazard) {
			rows.push({
				...common,
				status: "alias-hazard",
				severity: "error",
				note: `consumer output aliases canonical output: ${destination}`
			});
			continue;
		}
		if (entry.kind === "missing") {
			rows.push({
				...common,
				status: "missing",
				severity: "drift",
				note: sourceState.usable ? void 0 : `canonical output unavailable: ${sourceState.note}`
			});
			continue;
		}
		if (entry.kind === "directory" || entry.kind === "special") {
			rows.push({
				...common,
				status: "unsupported",
				severity: "drift",
				representation: entry.kind
			});
			continue;
		}
		if (entry.kind === "symlink") {
			if (!sourceState.usable && linkMatches(entry, source)) {
				rows.push({
					...common,
					status: "donor-missing",
					severity: "error",
					representation: "link",
					note: sourceState.note
				});
				continue;
			}
			if (sourceState.usable) try {
				if (await linkResolvesToSameFile(entry, source)) {
					rows.push({
						...common,
						status: "ok",
						severity: "ok",
						representation: "link"
					});
					continue;
				}
			} catch (error) {
				rows.push({
					...common,
					status: "evaluation-error",
					severity: "error",
					representation: "link",
					note: `cannot resolve link referents: ${error instanceof Error ? error.message : String(error)}`
				});
				continue;
			}
			rows.push({
				...common,
				status: "modified",
				severity: "drift",
				representation: "link",
				note: `points to ${entry.target}`
			});
			continue;
		}
		let donorComparisonError;
		if (sourceState.usable) {
			const donorComparison = await compareFileContents(source, destination);
			if (donorComparison.equal) {
				rows.push({
					...common,
					status: "ok",
					severity: "ok",
					representation: "copy"
				});
				continue;
			}
			donorComparisonError = donorComparison.error;
			if (donorComparison.error && !assembly.candidate) {
				rows.push({
					...common,
					status: "evaluation-error",
					severity: "error",
					representation: "copy",
					note: donorComparison.error
				});
				continue;
			}
		}
		if (assembly.candidate) {
			const localComparison = await candidateMatches(assembly.candidate, destination);
			if (localComparison.error) rows.push({
				...common,
				status: "evaluation-error",
				severity: "error",
				representation: "assembly",
				note: localComparison.error
			});
			else if (localComparison.equal) rows.push({
				...common,
				status: "ok",
				severity: "ok",
				representation: "assembly",
				note: donorComparisonError ?? (sourceState.usable ? void 0 : `canonical output unavailable: ${sourceState.note}`)
			});
			else rows.push({
				...common,
				status: "modified",
				severity: "drift",
				representation: "assembly",
				note: donorComparisonError ?? (sourceState.usable ? "differs from donor and local assembly" : `differs from local assembly; canonical output unavailable: ${sourceState.note}`)
			});
		} else rows.push({
			...common,
			status: "unclassified",
			severity: "error",
			representation: "file",
			note: "assembly evaluation failed"
		});
	}
	return rows;
}
async function assemblyInputsActive(spec, contextName, config) {
	const resolved = bindContextConfigs(spec, contextName, [config]).configs[config];
	for (const input of resolved.inputs) {
		const path = typeof input.file === "string" ? input.file : input.directory;
		if (typeof path !== "string") continue;
		if ((await inspectDeliveryEntry(path)).kind !== "missing") return true;
	}
	return false;
}
async function markInactiveAssemblyRoutes(options, rows) {
	for (const config of options.names) {
		const output = rows.find((row) => row.kind === "output" && row.config === config);
		const assembly = rows.find((row) => row.kind === "assembly" && row.config === config);
		if (!(output?.status === "ok" && (output.representation === "copy" || output.representation === "link")) || assembly?.status !== "evaluation-error" || await assemblyInputsActive(options.spec, options.contextName, config)) continue;
		assembly.status = "inactive";
		assembly.severity = "ok";
		assembly.note = `local assembly inputs are not initialized; ${assembly.note}`;
		for (const row of rows) if (row.kind === "input" && row.config === config && row.status === "missing") {
			row.status = "inactive";
			row.severity = "ok";
			row.note = row.note ? `inactive assembly route: ${row.note}` : "inactive assembly route";
		}
	}
}
async function canonicalStatusRows(options) {
	const rows = [];
	for (const name of options.names) {
		const destination = options.spec.configs[name].output;
		const [entry, assembly] = await Promise.all([inspectDeliveryEntry(destination), evaluateAssembly(options, name)]);
		if (assembly.error) {
			rows.push({
				kind: "assembly",
				status: "evaluation-error",
				severity: "error",
				config: name,
				name,
				destination,
				note: assembly.error
			});
			continue;
		}
		rows.push({
			kind: "assembly",
			status: "ready",
			severity: "ok",
			config: name,
			name,
			destination
		});
		if (entry.kind === "missing") rows.push({
			kind: "output",
			status: "missing",
			severity: "drift",
			config: name,
			name,
			destination
		});
		else if (entry.kind !== "file") rows.push({
			kind: "output",
			status: "unsupported",
			severity: "drift",
			config: name,
			name,
			destination,
			representation: entry.kind,
			note: "canonical assembly owns a regular file"
		});
		else {
			const comparison = await candidateMatches(assembly.candidate, destination);
			rows.push(comparison.error ? {
				kind: "output",
				status: "evaluation-error",
				severity: "error",
				config: name,
				name,
				destination,
				representation: "assembly",
				note: comparison.error
			} : {
				kind: "output",
				status: comparison.equal ? "ok" : "modified",
				severity: comparison.equal ? "ok" : "drift",
				config: name,
				name,
				destination,
				representation: "assembly"
			});
		}
	}
	return rows;
}
async function statusContext(options) {
	const context = getConfigContext(options.spec, options.contextName);
	const rows = context.canonical ? await canonicalStatusRows(options) : [...await outputStatusRows(options), ...await inputStatusRows(options.spec, options.contextName, options.names)];
	if (!context.canonical) await markInactiveAssemblyRoutes(options, rows);
	printStatusRows(rows, options.format);
	return statusCode(rows);
}
//#endregion
//#region files/config/runtime.ts
/** Thin multicall dispatcher for the fixed CONFIG action vocabulary. */
function fail$9(message) {
	throw new Error(message);
}
function parseInputStrategy$1(value, label) {
	if (value === "copy" || value === "link") return value;
	fail$9(`${label} must be copy or link`);
}
function parseInstallStrategy$1(value, label) {
	if (value === "assemble" || value === "copy" || value === "link") return value;
	fail$9(`${label} must be assemble, copy, or link`);
}
function contextInputStrategy(spec, contextName, explicit) {
	return parseInputStrategy$1(explicit ?? process.env.COMPFUZOR_CONFIG_DROPINS_STRATEGY ?? getConfigContext(spec, contextName).dropins ?? "link", "effective config input strategy");
}
function contextInstallStrategy(spec, contextName, explicit) {
	return parseInstallStrategy$1(explicit ?? process.env.COMPFUZOR_CONFIG_INSTALL_STRATEGY ?? getConfigContext(spec, contextName).install ?? "assemble", "effective config install strategy");
}
async function runConfigCommand(options) {
	const spec = JSON.parse(await readFile(options.specPath, "utf8"));
	const contextNames = Object.keys(spec.contexts ?? {});
	const inferred = configAliasPieces(options, contextNames);
	const action = resolveSelectedName({
		explicit: options.action,
		invokedAs: options.invokedAs,
		inferAlias: () => inferred.action,
		fallback: "",
		declared: CONFIG_ACTIONS,
		label: "config action"
	});
	const contextName = resolveSelectedName({
		explicit: options.context,
		invokedAs: options.invokedAs,
		inferAlias: () => inferred.context,
		environment: process.env.COMPFUZOR_CONFIG_CONTEXT ?? process.env.COMPFUZOR_CONTEXT,
		fallback: spec.defaultContext,
		declared: contextNames,
		label: "config context"
	});
	const context = getConfigContext(spec, contextName);
	rejectIrrelevantFlags(options, action);
	const canonicalInputAction = action === "inputs" ? options.args[0] : void 0;
	const canonicalAllowed = action === "assemble" || action === "status" || action === "inputs" && [
		"list",
		"status",
		"enable",
		"disable"
	].includes(canonicalInputAction ?? "");
	if (context.canonical && !canonicalAllowed) fail$9(`config ${action} is not meaningful for canonical source=destination context; use assemble, status, or explicit input list/status/enable/disable`);
	if (action === "assemble") {
		if (options.check && options.stdout) fail$9("--check and --stdout are mutually exclusive");
		if (options.list) {
			if (options.args.length > 0) fail$9("--list does not accept recipe names");
			for (const name of selectRecipeNames(spec, contextName, [], false).sort()) console.log(name);
			return 0;
		}
		const names = selectRecipeNames(spec, contextName, options.args);
		if (options.stdout && names.length !== 1) fail$9("--stdout requires exactly one selected config");
		return runAssembly({
			spec,
			contextName,
			runner: options.runner,
			names,
			check: options.check,
			stdout: options.stdout,
			quiet: options.quiet
		});
	}
	if (action === "status") {
		const names = selectRecipeNames(spec, contextName, options.args);
		return statusContext({
			spec,
			contextName,
			runner: options.runner,
			names,
			format: options.format
		});
	}
	if (action === "sync-inputs") {
		const names = selectRecipeNames(spec, contextName, options.args);
		const strategy = contextInputStrategy(spec, contextName, options.strategy);
		return syncInputs({
			spec,
			contextName,
			runner: options.runner,
			names,
			strategy,
			seed: options.seed
		});
	}
	if (action === "publish") return publishOutputs({
		spec,
		contextName,
		names: selectRecipeNames(spec, contextName, options.args),
		strategy: parseInputStrategy$1(options.strategy ?? process.env.COMPFUZOR_CONFIG_PUBLISH_STRATEGY, "config publish strategy")
	});
	if (action === "inputs") {
		const inputAction = options.args[0];
		const strategy = inputAction === "put" ? contextInputStrategy(spec, contextName, options.strategy) : options.strategy === void 0 ? void 0 : fail$9(`${inputAction ?? "inputs"} does not accept --strategy`);
		return runInputAction({
			spec,
			contextName,
			runner: options.runner,
			strategy,
			rebuild: options.rebuild,
			initiallyDisabled: options.initiallyDisabled,
			format: options.format
		}, options.args);
	}
	const names = selectRecipeNames(spec, contextName, options.args);
	const outcome = await installContext({
		spec,
		contextName,
		runner: options.runner,
		names,
		strategy: () => contextInstallStrategy(spec, contextName, options.strategy),
		inputStrategy: () => contextInputStrategy(spec, contextName, options.dropins)
	});
	if (outcome.status === "skipped") console.error(`skipped config install for ${contextName}: ${outcome.reason}`);
	return outcome.code;
}
async function main$6(argv, deploymentDir, invokedAs) {
	return runConfigCommand(parseConfigCommandArgs(argv, deploymentDir, invokedAs));
}
//#endregion
//#region files/config-remote/runtime.ts
/** Manage external symlinks declared by config.spec.json remote targets. */
async function linkState(path) {
	try {
		if (!(await lstat(path)).isSymbolicLink()) throw new Error(`managed destination is not a symlink: ${path}`);
		return {
			path,
			target: await readlink(path)
		};
	} catch (error) {
		if (error.code === "ENOENT") return void 0;
		throw error;
	}
}
function matches(pattern, value) {
	const escaped = pattern.replace(/[.+^${}()|[\]\\]/g, "\\$&");
	return new RegExp(`^${escaped.replaceAll("*", ".*").replaceAll("?", ".")}$`).test(value);
}
function validateName(remote, target, name) {
	if (!name || basename(name) !== name || name === "." || name === "..") throw new Error(`invalid remote filename: ${name}`);
	if (remote.disabled_suffix && name.endsWith(remote.disabled_suffix)) throw new Error(`remote filename must not include disabled suffix ${remote.disabled_suffix}: ${name}`);
	if (!matches(remote.pattern, name)) throw new Error(`${name} does not match ${target} pattern ${remote.pattern}`);
}
async function atomicLink(source, destination) {
	const temporary = join(dirname(destination), `.${basename(destination)}.tmp-${process.pid}-${Date.now()}`);
	await symlink(source, temporary);
	await rename(temporary, destination).catch(async (error) => {
		await rm(temporary, { force: true });
		throw error;
	});
}
async function rebuild(config, deploymentDir) {
	await new Promise((resolve, reject) => {
		const child = spawn(join(deploymentDir, "bin", "config", "command.mjs"), [
			"--action",
			"assemble",
			"--context",
			"canonical",
			config
		], {
			cwd: deploymentDir,
			stdio: "inherit"
		});
		child.once("error", reject);
		child.once("exit", (code, signal) => code === 0 ? resolve() : reject(/* @__PURE__ */ new Error(`config rebuild failed: ${signal ?? code}`)));
	});
}
async function inspect(remote, target, name) {
	validateName(remote, target, name);
	const activePath = join(remote.directory, name);
	const disabledPath = remote.disabled_suffix ? `${activePath}${remote.disabled_suffix}` : void 0;
	const [active, disabled] = await Promise.all([linkState(activePath), disabledPath ? linkState(disabledPath) : Promise.resolve(void 0)]);
	if (active && disabled) throw new Error(`both active and disabled remote links exist: ${target}/${name}`);
	return {
		active,
		disabled
	};
}
async function main$5(argv, deploymentDir) {
	const parsed = parseArgs({
		args: argv,
		allowPositionals: true,
		strict: true,
		options: { name: {
			type: "string",
			short: "n"
		} }
	});
	const [rawAction, target, value, positionalName] = parsed.positionals;
	const action = rawAction === "link" ? "put" : rawAction;
	const remotes = JSON.parse(await readFile(join(deploymentDir, "etc", "config.spec.json"), "utf-8")).remotes ?? {};
	if (action === "list") {
		if (target) throw new Error("usage: config-remote.mjs list");
		for (const name of Object.keys(remotes).sort()) {
			const remote = remotes[name];
			console.log(`${name}\tconfig=${remote.config}\tdestination=${join(remote.directory, remote.pattern)}\tdisabled=${remote.disabled_suffix ?? "-"}`);
		}
		return;
	}
	if (!target || !remotes[target]) throw new Error(`unknown remote target: ${target ?? ""}`);
	const remote = remotes[target];
	if (action === "status") {
		if (!value) throw new Error("usage: config-remote.mjs status <target> <name>");
		const { active, disabled } = await inspect(remote, target, value);
		console.log(`${target}/${value}\t${active ? "enabled" : disabled ? "disabled" : "absent"}${active || disabled ? `\t${(active ?? disabled).target}` : ""}`);
		return;
	}
	if (action === "put") {
		if (!value) throw new Error("usage: config-remote.mjs put <target> <source> [name] [--name name]");
		if (parsed.values.name && positionalName) throw new Error("filename may be supplied positionally or with --name, not both");
		const source = await realpath(value).catch((error) => {
			throw new Error(`remote source does not exist: ${value}`, { cause: error });
		});
		if (!(await lstat(source)).isFile()) throw new Error(`remote source is not a file: ${source}`);
		const name = parsed.values.name ?? positionalName ?? basename(source);
		const { active, disabled } = await inspect(remote, target, name);
		const previous = active ?? disabled;
		const destination = previous?.path ?? join(remote.directory, name);
		await mkdir(remote.directory, { recursive: true });
		await atomicLink(source, destination);
		try {
			await rebuild(remote.config, deploymentDir);
		} catch (error) {
			if (previous) await atomicLink(previous.target, destination);
			else await rm(destination, { force: true });
			throw error;
		}
		console.log(`put: ${target}/${name}${disabled ? " (disabled)" : ""} -> ${source}`);
		return;
	}
	if (![
		"remove",
		"enable",
		"disable"
	].includes(action ?? "") || !value) throw new Error("usage: config-remote.mjs <list|put|link|status|remove|enable|disable> ...");
	const { active, disabled } = await inspect(remote, target, value);
	if (action === "remove") {
		const existing = active ?? disabled;
		if (!existing) return;
		const backup = join(remote.directory, `.${basename(existing.path)}.remove-${process.pid}-${Date.now()}`);
		await rename(existing.path, backup);
		try {
			await rebuild(remote.config, deploymentDir);
			await rm(backup);
		} catch (error) {
			await rename(backup, existing.path);
			throw error;
		}
	} else {
		if (!remote.disabled_suffix) throw new Error(`remote target cannot be toggled: ${target}`);
		const from = action === "disable" ? active : disabled;
		if (action === "disable" ? disabled : active) return;
		if (!from) throw new Error(`remote link does not exist: ${target}/${value}`);
		const destination = action === "disable" ? `${from.path}${remote.disabled_suffix}` : from.path.slice(0, -remote.disabled_suffix.length);
		await rename(from.path, destination);
		try {
			await rebuild(remote.config, deploymentDir);
		} catch (error) {
			await rename(destination, from.path);
			throw error;
		}
	}
	console.log(`${action}: ${target}/${value}`);
}
//#endregion
//#region files/catalog/runtime.ts
/** Read-only inspection of attributed contributors, actions, resources, and flows. */
const FLOW_PHASES = {
	build: [
		{
			from: 1,
			to: 19,
			name: "prerequisites"
		},
		{
			from: 20,
			to: 39,
			name: "prepare"
		},
		{
			from: 40,
			to: 69,
			name: "compile"
		},
		{
			from: 70,
			to: 89,
			name: "package"
		},
		{
			from: 90,
			to: 99,
			name: "finalize"
		}
	],
	install: [
		{
			from: 1,
			to: 19,
			name: "prerequisites"
		},
		{
			from: 20,
			to: 29,
			name: "identity"
		},
		{
			from: 30,
			to: 49,
			name: "materialize"
		},
		{
			from: 50,
			to: 69,
			name: "publish"
		},
		{
			from: 70,
			to: 89,
			name: "activate"
		},
		{
			from: 90,
			to: 99,
			name: "record"
		}
	],
	status: [{
		from: 1,
		to: 99,
		name: "inspect"
	}]
};
const USAGE$2 = `Usage: compfuzor-catalog.sh [--catalog PATH | --deployment DIR] [--json] [COMMAND]

Inspect the compiled read-only runtime catalog. Commands:
  contributors
  actions
  commands
  resources
  flows
  flow NAME`;
function fail$8(message) {
	throw new Error(message);
}
function object$3(value, label) {
	if (typeof value !== "object" || value === null || Array.isArray(value)) fail$8(`${label} must be an object`);
	return value;
}
function strings(value, label = "value") {
	if (value === void 0) return [];
	if (!Array.isArray(value) || value.some((item) => typeof item !== "string")) fail$8(`${label} must be an array of strings`);
	return value;
}
function phaseFor(flow, index) {
	return (FLOW_PHASES[flow]?.find((candidate) => index >= candidate.from && index <= candidate.to))?.name ?? "unknown";
}
function lexical(left, right) {
	return left < right ? -1 : left > right ? 1 : 0;
}
function parseCatalog(value) {
	const record = object$3(value, "runtime catalog");
	if (record.version !== 1) fail$8(`unsupported runtime catalog version: ${String(record.version)}`);
	const flows = object$3(record.flows, "runtime catalog flows");
	return {
		version: 1,
		deployment: object$3(record.deployment, "runtime catalog deployment"),
		contributors: Array.isArray(record.contributors) ? record.contributors.map((item, index) => object$3(item, `contributor ${index}`)) : fail$8("runtime catalog contributors must be an array"),
		resources: Array.isArray(record.resources) ? record.resources.map((item, index) => object$3(item, `resource ${index}`)) : fail$8("runtime catalog resources must be an array"),
		commands: Array.isArray(record.commands) ? record.commands.map((item, index) => object$3(item, `command ${index}`)) : fail$8("runtime catalog commands must be an array"),
		actions: Array.isArray(record.actions) ? record.actions.map((item, index) => object$3(item, `action ${index}`)) : fail$8("runtime catalog actions must be an array"),
		flows: Object.fromEntries(Object.entries(flows).map(([name, item]) => {
			return [name, {
				name,
				entries: strings(object$3(item, `flow ${name}`).entries, `flow ${name} entries`)
			}];
		})),
		execution: object$3(record.execution, "runtime catalog execution")
	};
}
async function loadCatalog(path) {
	return parseCatalog(JSON.parse(await readFile(path, "utf8")));
}
function parseOptions$1(argv, deploymentDir) {
	const { values, positionals } = parseArgs({
		args: argv,
		strict: true,
		allowPositionals: true,
		options: {
			catalog: { type: "string" },
			deployment: { type: "string" },
			json: { type: "boolean" },
			help: {
				type: "boolean",
				short: "h"
			}
		}
	});
	if (values.help) {
		console.log(USAGE$2);
		process.exit(0);
	}
	if (values.catalog && values.deployment) fail$8("--catalog and --deployment are mutually exclusive");
	const root = resolve(values.deployment ?? deploymentDir);
	return {
		catalogPath: resolve(values.catalog ?? join(root, "etc", "compfuzor-runtime", "catalog.json")),
		json: values.json ?? false,
		positionals
	};
}
function placement(path, expectedFlow) {
	const match = /^(\d{2})-(build|install|status)-.+\.json$/.exec(basename(path));
	if (!match) fail$8(`invalid indexed flow filename: ${path}`);
	const index = Number(match[1]);
	if (index < 1 || index > 99) fail$8(`flow index must be 01-99: ${path}`);
	if (match[2] !== expectedFlow) fail$8(`flow filename ${path} does not match descriptor flow ${expectedFlow}`);
	return {
		index,
		flow: match[2]
	};
}
function canonical(value) {
	if (Array.isArray(value)) return value.map(canonical);
	if (typeof value !== "object" || value === null) return value;
	const record = value;
	return Object.fromEntries(Object.keys(record).sort().map((key) => [key, canonical(record[key])]));
}
function semanticDescriptor(record) {
	const copy = { ...record };
	delete copy.index;
	delete copy.effectiveIndex;
	delete copy.effectivePhase;
	delete copy.selectedPath;
	delete copy.selectedLayer;
	delete copy.shadowedPath;
	return JSON.stringify(canonical(copy));
}
async function readLayer(directory, layer) {
	let names;
	try {
		names = await readdir(directory);
	} catch (error) {
		if (error.code === "ENOENT") return [];
		throw error;
	}
	const selected = names.filter((name) => name.endsWith(".json")).sort(lexical);
	return await Promise.all(selected.map(async (name) => {
		const path = join(directory, name);
		return {
			path,
			record: object$3(JSON.parse(await readFile(path, "utf8")), `flow descriptor ${path}`),
			layer
		};
	}));
}
async function loadFlow(catalogPath, flow, suppliedCatalog) {
	if (!(flow in FLOW_PHASES)) fail$8(`unknown flow: ${flow}`);
	const catalog = suppliedCatalog ?? await loadCatalog(catalogPath);
	const declaredById = /* @__PURE__ */ new Map();
	for (const [declaredFlow, descriptor] of Object.entries(catalog.flows)) for (const id of descriptor.entries) {
		const previous = declaredById.get(id);
		if (previous) fail$8(`flow contribution id ${id} is declared by both ${previous} and ${declaredFlow}`);
		declaredById.set(id, declaredFlow);
	}
	const declaredDescriptor = catalog.flows[flow];
	if (!declaredDescriptor) fail$8(`catalog does not declare flow: ${flow}`);
	const declared = new Set(declaredDescriptor.entries);
	const root = join(dirname(catalogPath), "workflows");
	const [compiled, site] = await Promise.all([readLayer(join(root, "compiled"), "compiled"), readLayer(join(root, "site"), "site")]);
	const selected = /* @__PURE__ */ new Map();
	for (const item of compiled) {
		const id = item.record.id;
		if (typeof id !== "string" || !id) fail$8(`flow descriptor ${item.path} requires an id`);
		if (!declared.has(id)) continue;
		if (item.record.version !== 1) fail$8(`flow descriptor ${item.path} has unsupported version ${String(item.record.version)}`);
		if (item.record.flow !== flow) fail$8(`flow descriptor ${item.path} is indexed under ${flow} but declares ${String(item.record.flow)}`);
		object$3(item.record.invoke, `flow descriptor ${item.path} invocation`);
		strings(item.record.contributors, `flow descriptor ${item.path} contributors`);
		if (selected.has(id)) fail$8(`duplicate compiled flow contribution id ${id}`);
		const effective = placement(item.path, flow);
		selected.set(id, {
			...item.record,
			id,
			flow,
			effectiveIndex: effective.index,
			effectivePhase: phaseFor(flow, effective.index),
			selectedPath: item.path,
			selectedLayer: "compiled"
		});
	}
	for (const id of declared) if (!selected.has(id)) fail$8(`catalog flow ${flow} references missing compiled contribution ${id}`);
	const siteIds = /* @__PURE__ */ new Set();
	for (const item of site) {
		const id = item.record.id;
		if (typeof id !== "string" || !id) fail$8(`site flow descriptor ${item.path} requires an id`);
		if (siteIds.has(id)) fail$8(`duplicate site flow contribution id ${id}`);
		siteIds.add(id);
		const declaredFlow = declaredById.get(id);
		if (!declaredFlow) fail$8(`site flow descriptor ${item.path} names undeclared contribution ${id}`);
		if (declaredFlow !== flow) continue;
		const previous = selected.get(id);
		if (item.record.state === "absent") {
			if (!previous) fail$8(`site tombstone ${item.path} names unknown compiled contribution ${id}`);
			if (Object.keys(item.record).some((key) => key !== "id" && key !== "state")) fail$8(`site tombstone ${item.path} may contain only id and state`);
			selected.delete(id);
			continue;
		}
		if (item.record.version !== 1) fail$8(`site flow descriptor ${item.path} has unsupported version ${String(item.record.version)}`);
		if (item.record.flow !== flow) fail$8(`site flow descriptor ${item.path} is indexed under ${flow} but declares ${String(item.record.flow)}`);
		object$3(item.record.invoke, `site flow descriptor ${item.path} invocation`);
		strings(item.record.contributors, `site flow descriptor ${item.path} contributors`);
		const effective = placement(item.path, flow);
		if (previous && semanticDescriptor(previous) !== semanticDescriptor(item.record)) fail$8(`site flow contribution ${id} may change placement only; use a new id for changed behavior`);
		selected.set(id, {
			...item.record,
			id,
			flow,
			effectiveIndex: effective.index,
			effectivePhase: phaseFor(flow, effective.index),
			selectedPath: item.path,
			selectedLayer: "site",
			...previous ? { shadowedPath: previous.selectedPath } : {}
		});
	}
	return [...selected.values()].sort((left, right) => lexical(basename(left.selectedPath), basename(right.selectedPath)));
}
function printRows(rows) {
	for (const row of rows) console.log(row.map((cell) => cell || "-").join("	"));
}
function cell(value) {
	if (value === void 0 || value === null) return "";
	if (typeof value === "string") return value;
	if (typeof value === "number" || typeof value === "boolean" || typeof value === "bigint") return String(value);
	return JSON.stringify(value);
}
async function runCatalog(options) {
	const catalog = await loadCatalog(options.catalogPath);
	const [command, argument, ...extra] = options.positionals;
	if (extra.length > 0) fail$8(USAGE$2);
	if (!command) {
		const summary = {
			deployment: catalog.deployment,
			authority: catalog.execution.authority,
			contributors: catalog.contributors.length,
			actions: catalog.actions.length,
			commands: catalog.commands.length,
			resources: catalog.resources.length,
			flows: Object.keys(catalog.flows)
		};
		if (options.json) console.log(JSON.stringify(summary));
		else printRows(Object.entries(summary).map(([key, value]) => [key, typeof value === "object" ? JSON.stringify(value) : String(value)]));
		return 0;
	}
	if (command === "flow") {
		if (!argument) fail$8("catalog flow requires a flow name");
		const entries = await loadFlow(options.catalogPath, argument, catalog);
		if (options.json) console.log(JSON.stringify(entries));
		else printRows(entries.map((entry) => [
			String(entry.effectiveIndex).padStart(2, "0"),
			entry.effectivePhase,
			entry.id,
			cell(object$3(entry.invoke, `flow invocation ${entry.id}`).action),
			entry.selectedLayer,
			strings(entry.contributors, `flow invocation ${entry.id} contributors`).join(",")
		]));
		return 0;
	}
	if (argument) fail$8(`${command} does not accept an argument`);
	if (command === "flows") {
		const rows = await Promise.all(Object.keys(catalog.flows).map(async (name) => [name, String((await loadFlow(options.catalogPath, name, catalog)).length)]));
		if (options.json) console.log(JSON.stringify(Object.fromEntries(rows)));
		else printRows(rows);
		return 0;
	}
	const values = {
		contributors: catalog.contributors,
		actions: catalog.actions,
		commands: catalog.commands,
		resources: catalog.resources
	}[command];
	if (!values) fail$8(USAGE$2);
	if (options.json) console.log(JSON.stringify(values));
	else printRows(values.map((value) => [
		cell(value.id ?? value.name),
		cell(value.action ?? value.contract ?? value.kind),
		strings(value.contributors, "catalog contributors").join(",")
	]));
	return 0;
}
async function main$4(argv, deploymentDir) {
	return runCatalog(parseOptions$1(argv, deploymentDir));
}
//#endregion
//#region files/flow/runtime.ts
/** Sequential execution of validated, lexically ordered catalog flows. */
const USAGE$1 = `Usage: compfuzor-flow.sh [--catalog PATH | --deployment DIR] [--dry-run] FLOW

Execute one catalog-authorized build, install, or status flow in lexical order.`;
function fail$7(message) {
	throw new Error(message);
}
function object$2(value, label) {
	if (typeof value !== "object" || value === null || Array.isArray(value)) fail$7(`${label} must be an object`);
	return value;
}
function stringArray(value, label) {
	if (value === void 0) return [];
	if (!Array.isArray(value) || value.some((item) => typeof item !== "string")) fail$7(`${label} must be an array of strings`);
	return value;
}
function parseOptions(argv, defaultDeployment) {
	const { values, positionals } = parseArgs({
		args: argv,
		strict: true,
		allowPositionals: true,
		options: {
			catalog: { type: "string" },
			deployment: { type: "string" },
			"dry-run": { type: "boolean" },
			help: {
				type: "boolean",
				short: "h"
			}
		}
	});
	if (values.help) {
		console.log(USAGE$1);
		process.exit(0);
	}
	if (values.catalog && values.deployment) fail$7("--catalog and --deployment are mutually exclusive");
	if (positionals.length !== 1 || ![
		"build",
		"install",
		"status"
	].includes(positionals[0])) fail$7(USAGE$1);
	const deploymentDir = resolve(values.deployment ?? defaultDeployment);
	return {
		catalogPath: resolve(values.catalog ?? join(deploymentDir, "etc", "compfuzor-runtime", "catalog.json")),
		deploymentDir,
		dryRun: values["dry-run"] ?? false,
		flow: positionals[0]
	};
}
async function executablePath(deploymentDir, configured, id) {
	if (typeof configured !== "string" || !configured) fail$7(`flow invocation ${id} requires an executable path`);
	const lexicalPath = resolve(deploymentDir, configured);
	const [root, physicalPath] = await Promise.all([realpath(deploymentDir), realpath(lexicalPath)]);
	const remainder = relative(root, physicalPath);
	if (remainder === ".." || remainder.startsWith(`..${sep}`)) fail$7(`flow invocation ${id} executable escapes deployment: ${configured}`);
	return lexicalPath;
}
async function runExecutable(path, args, deploymentDir) {
	return await new Promise((complete, reject) => {
		const child = spawn(path, args, {
			detached: true,
			env: {
				...process.env,
				DIR: deploymentDir
			},
			stdio: "inherit"
		});
		const signals = ["SIGINT", "SIGTERM"];
		const listeners = /* @__PURE__ */ new Map();
		let interrupted = false;
		const cleanup = () => {
			for (const [signal, listener] of listeners) process.off(signal, listener);
		};
		for (const signal of signals) {
			const listener = () => {
				interrupted = true;
				if (child.pid === void 0) return;
				try {
					process.kill(-child.pid, signal);
				} catch (error) {
					if (error.code !== "ESRCH") reject(error);
				}
			};
			listeners.set(signal, listener);
			process.on(signal, listener);
		}
		child.once("error", (error) => {
			cleanup();
			reject(error);
		});
		child.once("exit", (code, signal) => {
			cleanup();
			complete(interrupted || signal ? 1 : code ?? 1);
		});
	});
}
async function runInvocation(entry, deploymentDir, dryRun) {
	const invoke = object$2(entry.invoke, `flow invocation ${entry.id}`);
	const handler = object$2(invoke.handler, `flow invocation ${entry.id} handler`);
	if (handler.kind !== "exec") fail$7(`flow invocation ${entry.id} has unsupported handler kind ${String(handler.kind)}`);
	const path = await executablePath(deploymentDir, handler.path, entry.id);
	const args = stringArray(invoke.args, `flow invocation ${entry.id} args`);
	console.error(`${dryRun ? "would run" : "running"} ${entry.effectiveIndex.toString().padStart(2, "0")} ${entry.id}: ${path}${args.length ? ` ${args.join(" ")}` : ""}`);
	return dryRun ? 0 : await runExecutable(path, args, deploymentDir);
}
async function executeFlow(options) {
	const catalog = await loadCatalog(options.catalogPath);
	if (catalog.execution.catalogOnly || catalog.execution.authority !== "catalog") fail$7(`catalog flow execution is disabled for ${typeof catalog.deployment.id === "string" ? catalog.deployment.id : "deployment"}`);
	const entries = await loadFlow(options.catalogPath, options.flow, catalog);
	let attention = false;
	for (const entry of entries) {
		const code = await runInvocation(entry, options.deploymentDir, options.dryRun);
		if (options.dryRun || code === 0) continue;
		const handler = object$2(object$2(entry.invoke, `flow invocation ${entry.id}`).handler, `flow invocation ${entry.id} handler`);
		if (options.flow === "status" && handler.protocol === "legacy-status-v1") {
			if (code === 2 && handler.exit2 !== "error") continue;
			attention = true;
			continue;
		}
		return code === 2 ? 2 : 1;
	}
	return attention ? 1 : 0;
}
async function main$3(argv, deploymentDir) {
	return executeFlow(parseOptions(argv, deploymentDir));
}
//#endregion
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
function fail$6(message) {
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
		if (!mode) fail$6(`--sudo expects auto, always, or never (got ${flagValue})`);
		return mode;
	}
	const environmentValue = process.env.COMPFUZOR_LINKS_SUDO;
	if (environmentValue === void 0 || environmentValue.trim() === "") return "auto";
	const mode = parseSudoWord(environmentValue);
	if (!mode) fail$6(`COMPFUZOR_LINKS_SUDO must be auto, always, or never (got ${environmentValue})`);
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
	if (commandIndex < 0) fail$6("expected apply, status, audit, or remove");
	const command = positionals[commandIndex];
	const paths = positionals.toSpliced(commandIndex, 1);
	if (command !== "audit" && paths.length > 1) fail$6(`${command} accepts at most one manifest`);
	if (values.strategy !== void 0 && command !== "apply") fail$6("--strategy is only valid with apply");
	if (values.composed && command !== "apply") fail$6("--composed is only valid with apply");
	if (values.scope !== void 0 && values.scope !== "system" && values.scope !== "user") fail$6("--scope must be system or user");
	if (values.strategy !== void 0 && values.strategy !== "link" && values.strategy !== "copy") fail$6("--strategy must be link or copy");
	const id = values.id?.flatMap((value) => value.split(",").map((part) => part.trim()).filter(Boolean));
	if (values.id !== void 0 && id?.length === 0) fail$6("--id requires a comma-separated glob list");
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
function fail$5(message) {
	throw new Error(message);
}
function object$1(value, description) {
	if (!value || typeof value !== "object" || Array.isArray(value)) fail$5(`${description} must be an object`);
	return value;
}
function stringField(value, description) {
	if (typeof value !== "string" || value.length === 0) fail$5(`${description} must be a non-empty string`);
	return value;
}
function strategiesField(value, description) {
	if (value === void 0) return {
		available: ["link"],
		default: "link"
	};
	const strategies = object$1(value, description);
	const unknown = Object.keys(strategies).filter((key) => key !== "available" && key !== "default");
	if (unknown.length > 0) fail$5(`${description} has unknown fields: ${unknown.sort().join(", ")}`);
	if (!Array.isArray(strategies.available) || strategies.available.length === 0) fail$5(`${description}.available must be a non-empty array`);
	if (strategies.available.some((entry) => entry !== "link" && entry !== "copy")) fail$5(`${description}.available contains an unsupported strategy`);
	const declared = strategies.available;
	if (new Set(declared).size !== declared.length) fail$5(`${description}.available contains duplicates`);
	if (strategies.default !== "link" && strategies.default !== "copy") fail$5(`${description}.default must be link or copy`);
	if (!declared.includes(strategies.default)) fail$5(`${description}.default must be available`);
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
		fail$5(`cannot read manifest ${path}: ${error instanceof Error ? error.message : String(error)}`);
	}
	const value = object$1(raw, `manifest ${path}`);
	if (value.version !== 1 && value.version !== 2) fail$5(`manifest ${path}: unsupported version ${String(value.version)}`);
	const version = value.version;
	if (!Array.isArray(value.links)) fail$5(`manifest ${path}: links must be an array`);
	const seen = /* @__PURE__ */ new Set();
	const links = value.links.map((entry, index) => {
		const record = object$1(entry, `${path}: links[${index}]`);
		const id = stringField(record.id, `${path}: links[${index}].id`);
		if (seen.has(id)) fail$5(`${path}: duplicate link id ${id}`);
		seen.add(id);
		if (record.scope !== "system" && record.scope !== "user") fail$5(`${path}: ${id}: invalid scope`);
		if (record.policy !== "preserve" && record.policy !== "fail" && record.policy !== "replace") fail$5(`${path}: ${id}: invalid policy`);
		if (record.state !== "present" && record.state !== "absent") fail$5(`${path}: ${id}: invalid state`);
		if (version === 1 && (record.strategies !== void 0 || record.compose !== void 0)) fail$5(`${path}: ${id}: version 1 records cannot declare strategies or compose; rerender as LINKS manifest version 2`);
		let runtimeRoots;
		if (record.runtimeRoots !== void 0) {
			if (!Array.isArray(record.runtimeRoots) || record.runtimeRoots.some((root) => root !== "HOME" && root !== "XDG_RUNTIME_DIR" && root !== "XDG_STATE_HOME")) fail$5(`${path}: ${id}: runtimeRoots contains an unsupported root`);
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
			compose: record.compose === void 0 ? true : typeof record.compose === "boolean" ? record.compose : fail$5(`${path}: ${id}: compose must be boolean`),
			runtimeRoots
		};
	});
	let deployment;
	if (value.deployment !== void 0) {
		const entry = object$1(value.deployment, `${path}: deployment`);
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
		if (!home) fail$5(`HOME is required to expand ${value}`);
		expanded = home + value.slice(1);
	} else if (value === "${HOME}" || value.startsWith("${HOME}/")) {
		if (!home) fail$5(`HOME is required to expand ${value}`);
		expanded = home + value.slice(7);
	} else if (value === "${XDG_RUNTIME_DIR}" || value.startsWith("${XDG_RUNTIME_DIR}/")) {
		if (!runtime) fail$5(`XDG_RUNTIME_DIR is required to expand ${value}`);
		expanded = runtime + value.slice(18);
	} else if (value === "${XDG_STATE_HOME}" || value.startsWith("${XDG_STATE_HOME}/")) {
		if (!state) fail$5(`HOME or XDG_STATE_HOME is required to expand ${value}`);
		expanded = state + value.slice(17);
	} else if (value.startsWith("~") || value.includes("${") || value.includes("$")) fail$5(`unsupported runtime-root expression: ${value}`);
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
		if (resolved.srcPath === resolved.destPath) fail$5(`${path}: ${record.id}: source and destination are the same path`);
		const key = `${record.scope}\0${resolved.destPath}`;
		const prior = claims.get(key);
		if (prior && (prior.srcPath !== resolved.srcPath || prior.policy !== resolved.policy || prior.state !== resolved.state || prior.compose !== resolved.compose || prior.strategies.default !== resolved.strategies.default || prior.strategies.available.join("\0") !== resolved.strategies.available.join("\0"))) fail$5(`${path}: conflicting claims for ${resolved.destPath}`);
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
//#region files/links/runtime.ts
function fail$4(message) {
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
async function main$2(argv, deploymentDir) {
	const options = parseLinksArgs(argv, join(process.env.DIR ?? deploymentDir, "links.json"));
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
		if ((options.command === "apply" || options.command === "remove") && sudoMode === "always" && resolved.records.some((record) => record.scope === "user")) fail$4("--sudo always is not permitted for user-scope link mutations");
		if (options.command === "apply" && options.strategy) {
			const unavailable = resolved.records.filter((record) => record.state === "present" && !record.strategies.available.includes(options.strategy));
			if (unavailable.length > 0) fail$4(`strategy ${options.strategy} is unavailable for: ${unavailable.map((record) => record.id).join(", ")}`);
			if (options.strategy === "copy") {
				const unusable = (await Promise.all(resolved.records.map(async (record) => ({
					record,
					source: await sourceState(record.srcPath)
				})))).filter(({ record, source }) => record.state === "present" && source.entryExists && !source.regular);
				if (unusable.length > 0) fail$4(`strategy copy requires a source that resolves to a regular file: ${unusable.map(({ record }) => record.id).join(", ")}`);
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
//#endregion
//#region files/zim/activation.ts
/** Zim context binding, loader projection, cache builds, and health checks. */
function fail$3(message) {
	throw new Error(message);
}
function resolveActivation(name, zimSpec, configSpec) {
	const spec = zimSpec.contexts[name] ?? fail$3(`unknown Zim context: ${name}`);
	const bound = bindContextConfigs(configSpec, spec.config, ["zimrc", "zimenv"]);
	return {
		name,
		spec,
		configSpec,
		zimrc: bound.configs.zimrc.output,
		zimenv: bound.configs.zimenv.output,
		loaderRoot: resolvePathSelector(spec.loader_root, void 0, `Zim context ${name}.loader_root`),
		zimrcHome: resolvePathSelector(spec.zimrc_home, void 0, `Zim context ${name}.zimrc_home`),
		zimenvHome: resolvePathSelector(spec.zimenv_home, void 0, `Zim context ${name}.zimenv_home`),
		registry: resolvePathSelector(spec.registry, void 0, `Zim context ${name}.registry`),
		zshenv: spec.zshenv === void 0 ? void 0 : resolvePathSelector(spec.zshenv, void 0, `Zim context ${name}.zshenv`),
		zshrc: spec.zshrc === void 0 ? void 0 : resolvePathSelector(spec.zshrc, void 0, `Zim context ${name}.zshrc`),
		wireRemove: spec.wire_remove ?? []
	};
}
async function runCommand(file, args, capture = false, input) {
	return await new Promise((complete, reject) => {
		const child = spawn(file, args, { stdio: capture ? [
			input ? "pipe" : "ignore",
			"pipe",
			"pipe"
		] : input ? [
			"pipe",
			"inherit",
			"inherit"
		] : "inherit" });
		const stdout = [];
		const stderr = [];
		child.stdout?.on("data", (chunk) => stdout.push(Buffer.from(chunk)));
		child.stderr?.on("data", (chunk) => stderr.push(Buffer.from(chunk)));
		child.once("error", reject);
		child.once("exit", (code, signal) => complete({
			code: signal ? 1 : code ?? 1,
			stdout: Buffer.concat(stdout),
			stderr: Buffer.concat(stderr)
		}));
		if (input) child.stdin?.end(input);
	});
}
function zshQuote(value) {
	if (value.includes("\0")) fail$3("cannot project a Zsh path containing NUL");
	return `'${value.replaceAll("'", "'\\''")}'`;
}
function replaceLoaderToken(template, token, value, source) {
	const first = template.indexOf(token);
	if (first < 0) fail$3(`Zim loader template ${source} is missing ${token}`);
	if (template.indexOf(token, first + token.length) >= 0) fail$3(`Zim loader template ${source} repeats ${token}`);
	return `${template.slice(0, first)}${value}${template.slice(first + token.length)}`;
}
async function projectLoader(channel, activation, canonical) {
	const template = channel === "zimrc" ? canonical.zimrcLoaderTemplate : canonical.zimenvLoaderTemplate;
	const home = channel === "zimrc" ? activation.zimrcHome : activation.zimenvHome;
	const config = channel === "zimrc" ? activation.zimrc : activation.zimenv;
	const legacy = channel === "zimrc" ? canonical.zimrcLegacy : canonical.zimenvLegacy;
	let projected = await readFile(template, "utf8");
	const replacements = [
		["@@ZIM_CACHE_HOME@@", zshQuote(home)],
		["@@ZIM_CONFIG_OUTPUT@@", zshQuote(config)],
		["@@ZIM_LEGACY_CONFIG_PATTERN@@", [...new Set(legacy)].map(zshQuote).join("|")],
		["@@ZIM_CONTROLLER@@", zshQuote(canonical.controller)]
	];
	if (channel === "zimrc") replacements.push(["@@ZIM_EMERGENCY_MODULE@@", zshQuote(canonical.emergencyModule)]);
	for (const [token, value] of replacements) projected = replaceLoaderToken(projected, token, value, template);
	const unknown = projected.match(/@@ZIM_[A-Z_]+@@/);
	if (unknown) fail$3(`Zim loader template ${template} has unsupported placeholder ${unknown[0]}`);
	projected = projected.replace(/\r?\n$/, "");
	return {
		content: Buffer.from(projected),
		template
	};
}
async function installLoader(block, content, destination, legacyBlock) {
	const executable = process.env.CONFIG_BLOCK_IN_FILE || "block-in-file";
	try {
		await lstat(destination);
		if ((await runCommand(executable, [
			"--remove-match",
			`^${legacyBlock}$`,
			"-o",
			destination
		])).code !== 0) fail$3(`failed to remove legacy block from ${destination}`);
	} catch (error) {
		if (error.code !== "ENOENT") throw error;
	}
	if ((await runCommand(executable, [
		"-n",
		block,
		"-C",
		"true",
		"-i",
		"-",
		"-o",
		destination
	], false, content)).code !== 0) fail$3(`failed to install block ${block} in ${destination}`);
}
async function buildChannel(channel, activation, canonical) {
	const home = channel === "zimrc" ? activation.zimrcHome : activation.zimenvHome;
	const config = channel === "zimrc" ? activation.zimrc : activation.zimenv;
	if ((await runCommand("zsh", [
		"-dfc",
		`ZIM_HOME=$1\nZIM_CONFIG_FILE=$2\ncontroller=$3\nshift 3\nsource "$controller" "$@"`,
		`zimfw-${channel}`,
		home,
		config,
		canonical.controller,
		"install"
	])).code !== 0) fail$3(`failed to build ${channel} cache for context ${activation.name}`);
}
async function installActivation(activation, canonical) {
	const [zimenvLoader, zimrcLoader] = await Promise.all([projectLoader("zimenv", activation, canonical), projectLoader("zimrc", activation, canonical)]);
	await mkdir(activation.loaderRoot, { recursive: true });
	await installLoader(`${canonical.blockPrefix}-zimenv`, zimenvLoader.content, join(activation.loaderRoot, ".zshenv"), canonical.blockPrefix);
	await installLoader(`${canonical.blockPrefix}-zimrc`, zimrcLoader.content, join(activation.loaderRoot, ".zshrc"), canonical.blockPrefix);
	await buildChannel("zimenv", activation, canonical);
	await buildChannel("zimrc", activation, canonical);
	await wireDotfile("zimenv", activation, canonical);
	await wireDotfile("zimrc", activation, canonical);
}
function wiringTarget(channel, activation) {
	return channel === "zimrc" ? activation.zshrc : activation.zshenv;
}
function wiringContent(channel, activation) {
	return `source ${zshQuote(join(activation.loaderRoot, channel === "zimrc" ? ".zshrc" : ".zshenv"))}\n`;
}
async function wireDotfile(channel, activation, canonical) {
	const destination = wiringTarget(channel, activation);
	if (destination === void 0) return;
	const executable = process.env.CONFIG_BLOCK_IN_FILE || "block-in-file";
	const block = `${canonical.blockPrefix}-${channel}`;
	await mkdir(dirname(destination), { recursive: true });
	try {
		await stat(destination);
	} catch {
		await writeFile(destination, "", { mode: 420 });
	}
	for (const pattern of activation.wireRemove) if ((await runCommand(executable, [
		"--remove-match",
		pattern,
		"-o",
		destination
	])).code !== 0) fail$3(`failed to remove legacy block ${pattern} from ${destination}`);
	if ((await runCommand(executable, [
		"-n",
		block,
		"-C",
		"true",
		"-i",
		"-",
		"-o",
		destination
	], false, Buffer.from(wiringContent(channel, activation)))).code !== 0) fail$3(`failed to wire block ${block} into ${destination}`);
}
async function wiringHealthy(channel, activation, canonical) {
	const destination = wiringTarget(channel, activation);
	if (destination === void 0) return true;
	const block = `${canonical.blockPrefix}-${channel}`;
	const result = await runCommand(process.env.CONFIG_BLOCK_IN_FILE || "block-in-file", [
		"--read",
		"-n",
		block,
		destination
	], true);
	const expected = wiringContent(channel, activation).replace(/\r?\n$/, "");
	if (result.code === 0 && result.stdout.toString() === expected) {
		console.log(`zim ${channel} wiring: ok: ${destination}`);
		return true;
	}
	console.log(`zim ${channel} wiring: drift: ${destination} (block ${block} is missing or does not source ${join(activation.loaderRoot, channel === "zimrc" ? ".zshrc" : ".zshenv")})`);
	return false;
}
async function loaderHealthy(channel, activation, canonical) {
	const destination = join(activation.loaderRoot, channel === "zimrc" ? ".zshrc" : ".zshenv");
	let projection;
	try {
		projection = await projectLoader(channel, activation, canonical);
	} catch (error) {
		const template = channel === "zimrc" ? canonical.zimrcLoaderTemplate : canonical.zimenvLoaderTemplate;
		console.log(`zim ${channel} loader: drift: ${destination} (loader template is missing or invalid: ${template}: ${error instanceof Error ? error.message : String(error)})`);
		return false;
	}
	const name = `${canonical.blockPrefix}-${channel}`;
	const result = await runCommand(process.env.CONFIG_BLOCK_IN_FILE || "block-in-file", [
		"--read",
		"-n",
		name,
		destination
	], true);
	if (result.code !== 0) {
		console.log(`zim ${channel} loader: drift: ${destination} (block ${name} is missing or unreadable)`);
		return false;
	}
	if (projection.content.equals(result.stdout)) {
		console.log(`zim ${channel} loader: ok: ${destination}`);
		return true;
	}
	console.log(`zim ${channel} loader: drift: ${destination} (block ${name} differs from projected template ${projection.template})`);
	return false;
}
async function cacheHealthy(channel, activation) {
	const config = channel === "zimrc" ? activation.zimrc : activation.zimenv;
	const home = channel === "zimrc" ? activation.zimrcHome : activation.zimenvHome;
	const cache = join(home, "init.zsh");
	try {
		const [configStat, cacheStat] = await Promise.all([stat(config), stat(cache)]);
		if (cacheStat.mtimeMs > configStat.mtimeMs) {
			console.log(`zim ${channel} cache: ok: ${cache}`);
			return true;
		}
	} catch {}
	console.log(`zim ${channel} cache: drift: ${cache} (missing or stale for ${config})`);
	return false;
}
async function activationHealthy(activation, canonical) {
	return (await Promise.all([
		cacheHealthy("zimenv", activation),
		cacheHealthy("zimrc", activation),
		loaderHealthy("zimenv", activation, canonical),
		loaderHealthy("zimrc", activation, canonical),
		wiringHealthy("zimenv", activation, canonical),
		wiringHealthy("zimrc", activation, canonical)
	])).every(Boolean);
}
//#endregion
//#region files/zim/cli.ts
/** Zim command parsing, context selection, strategy normalization, and help. */
const HELP = {
	install: `Usage: install-zim.sh [--context NAME] [--install assemble|copy|link] [--dropins copy|link]

Install and activate Zim for a selected context: install its CONFIG recipes,
project startup loaders, build both caches, wire the loaders into the context's
dotfiles (when declared), and publish the registry link.

Options:
  --context NAME                 Select a declared Zim context
  --install assemble|copy|link  Override CONFIG output installation
  --dropins copy|link            Override CONFIG input delivery`,
	import: `Usage: install-zim-context.sh [--context NAME] [--dropins copy|link] PRODUCER_DIR

Import a producer's Zim fragments into a selected consumer context, then rebuild
only the channels that received fragments.

Options:
  --context NAME       Select a declared Zim context
  --dropins copy|link  Select imported fragment representation`,
	status: `Usage: status-zim.sh [--context NAME] [--activation-only]

Report Zim activation health: CONFIG state, startup loaders, both caches, and
the registry link. Exit 0 is clean, 1 is drift, and 2 is an evaluation error.

Options:
  --context NAME     Select a declared Zim context
  --activation-only  Skip CONFIG rows (used by aggregate status)`
};
function fail$2(message) {
	throw new Error(message);
}
function parseInstallStrategy(value, label) {
	if (value === "assemble" || value === "copy" || value === "link") return value;
	fail$2(`${label} must be assemble, copy, or link`);
}
function parseInputStrategy(value, label) {
	if (value === "copy" || value === "link") return value;
	fail$2(`${label} must be copy or link`);
}
function parseZimArgs(argv, deploymentDir) {
	const { values, positionals } = parseArgs({
		args: argv,
		strict: true,
		allowPositionals: true,
		options: {
			context: { type: "string" },
			install: { type: "string" },
			dropins: { type: "string" },
			"invoked-as": { type: "string" },
			spec: { type: "string" },
			"config-spec": { type: "string" },
			"config-runner": { type: "string" },
			"activation-only": { type: "boolean" },
			help: {
				type: "boolean",
				short: "h"
			}
		}
	});
	const actionIndex = positionals.findIndex((value) => value === "install" || value === "import" || value === "status");
	const action = actionIndex < 0 ? void 0 : positionals[actionIndex];
	if (values.help) {
		console.log(action ? HELP[action] : Object.values(HELP).join("\n\n"));
		process.exit(0);
	}
	if (!action) fail$2("expected Zim action: install, import, or status");
	const args = positionals.toSpliced(actionIndex, 1);
	if (action !== "import" && args.length > 0) fail$2(`${action} does not accept positional arguments`);
	if (action === "import" && args.length !== 1) fail$2("import requires exactly one producer directory");
	if (values["activation-only"] && action !== "status") fail$2("--activation-only requires status");
	return {
		action,
		context: values.context,
		install: values.install === void 0 ? void 0 : parseInstallStrategy(values.install, "--install"),
		dropins: values.dropins === void 0 ? void 0 : parseInputStrategy(values.dropins, "--dropins"),
		invokedAs: basename(values["invoked-as"] ?? "install-zim.sh"),
		zimSpecPath: resolve(values.spec ?? join(deploymentDir, "etc", "zim.spec.json")),
		configSpecPath: resolve(values["config-spec"] ?? join(deploymentDir, "etc", "config.spec.json")),
		configRunner: resolve(values["config-runner"] ?? join(deploymentDir, "bin", "config", "run.sh")),
		activationOnly: values["activation-only"] ?? false,
		args
	};
}
function aliasContext(invokedAs, spec) {
	if (invokedAs === "install-zim.sh") return void 0;
	const match = /^install-zim-(.+)\.sh$/.exec(invokedAs);
	if (!match) fail$2(`unsupported Zim command alias ${invokedAs}; use install-zim-CONTEXT.sh or explicit --context`);
	if (!(match[1] in spec.contexts)) fail$2(`Zim command alias ${invokedAs} names undeclared context ${match[1]}`);
	return match[1];
}
function resolveSettings(options, spec, configSpec) {
	const contextName = resolveSelectedName({
		explicit: options.context,
		invokedAs: options.invokedAs,
		inferAlias: (invokedAs) => options.action === "install" ? aliasContext(invokedAs, spec) : void 0,
		environment: process.env.COMPFUZOR_ZIM_CONTEXT ?? process.env.COMPFUZOR_CONTEXT,
		fallback: spec.defaultContext,
		declared: Object.keys(spec.contexts),
		label: "Zim context"
	});
	const activation = spec.contexts[contextName];
	const configContext = getConfigContext(configSpec, activation.config);
	if (configContext.scope !== activation.scope) fail$2(`Zim context ${contextName} scope does not match config context ${activation.config}`);
	return {
		contextName,
		install: options.action === "install" ? options.install : void 0,
		dropins: options.action === "import" ? options.dropins ?? parseInputStrategy(process.env.COMPFUZOR_ZIM_DROPINS_STRATEGY ?? process.env.COMPFUZOR_CONFIG_DROPINS_STRATEGY ?? configContext.dropins ?? "link", "effective drop-in strategy") : options.action === "install" ? options.dropins : void 0
	};
}
//#endregion
//#region files/zim/runtime.ts
/** Complete Zim install, producer import, and status orchestration. */
function fail$1(message) {
	throw new Error(message);
}
function truthy(value) {
	return [
		"1",
		"true",
		"y",
		"yes"
	].includes(value?.trim().toLowerCase() ?? "");
}
async function withRegistryManifest(activation, canonical, callback) {
	const temporary = await mkdtemp(join(tmpdir(), "compfuzor-zim-registry-"));
	const path = join(temporary, "links.json");
	const manifest = {
		version: 1,
		deployment: { dir: dirname(canonical.controller) },
		links: [{
			id: `zim-registry-${activation.name}`,
			scope: activation.spec.scope,
			src: canonical.registry,
			dest: activation.registry,
			policy: "replace",
			state: "present"
		}]
	};
	try {
		await writeFile(path, JSON.stringify(manifest), { mode: 384 });
		return await callback(path);
	} finally {
		await rm(temporary, {
			recursive: true,
			force: true
		});
	}
}
async function runRegistry(action, activation, canonical, deploymentDir) {
	return withRegistryManifest(activation, canonical, async (manifest) => {
		const args = [
			action,
			"--scope",
			activation.spec.scope
		];
		if (action === "apply") args.push("--sudo", "never");
		args.push(manifest);
		return (await runCommand(join(deploymentDir, "bin", "links.mjs"), args)).code;
	});
}
async function installZim(options, settings, activation, spec, deploymentDir) {
	const configContext = getConfigContext(activation.configSpec, activation.spec.config);
	const configResult = await installContext({
		spec: activation.configSpec,
		contextName: activation.spec.config,
		runner: options.configRunner,
		names: ["zimrc", "zimenv"],
		strategy: () => settings.install ?? parseInstallStrategy(process.env.COMPFUZOR_ZIM_INSTALL_STRATEGY ?? process.env.COMPFUZOR_CONFIG_INSTALL_STRATEGY ?? configContext.install ?? "assemble", "effective install strategy"),
		inputStrategy: () => settings.dropins ?? parseInputStrategy(process.env.COMPFUZOR_ZIM_DROPINS_STRATEGY ?? process.env.COMPFUZOR_CONFIG_DROPINS_STRATEGY ?? configContext.dropins ?? "link", "effective drop-in strategy")
	});
	if (configResult.code !== 0) return configResult.code;
	if (configResult.status === "skipped") {
		const available = await Promise.all([activation.zimenv, activation.zimrc].map(async (path) => {
			try {
				return (await stat(path)).isFile();
			} catch {
				return false;
			}
		}));
		console.error(`skipped Zim config install for ${activation.name}: ${configResult.reason}`);
		if (!available.every(Boolean)) {
			console.error(`skipped remaining Zim install for ${activation.name}: required config outputs are unavailable`);
			return 0;
		}
	}
	await installActivation(activation, spec.canonical);
	const registryResult = await runRegistry("apply", activation, spec.canonical, deploymentDir);
	if (registryResult !== 0) return registryResult;
	return 0;
}
async function inventoryProducer(producer) {
	const records = [];
	const seen = /* @__PURE__ */ new Set();
	for (const channel of ["zimenv", "zimrc"]) for (const state of ["active", "disabled"]) {
		const directory = join(producer, "etc", "zim", channel, state);
		let entries;
		try {
			entries = await readdir(directory, {
				withFileTypes: true,
				encoding: "utf8"
			});
		} catch (error) {
			if (error.code === "ENOENT") continue;
			throw error;
		}
		for (const entry of entries.sort((a, b) => a.name.localeCompare(b.name))) {
			if (!entry.name.endsWith(".conf") || !entry.isFile() && !entry.isSymbolicLink()) continue;
			const key = `${channel}/${entry.name}`;
			if (seen.has(key)) fail$1(`producer has both active and disabled entries: ${key}`);
			seen.add(key);
			records.push({
				channel,
				source: join(directory, entry.name),
				disabled: state === "disabled"
			});
		}
	}
	return records;
}
async function importProducer(options, settings, activation, spec) {
	const records = await inventoryProducer(resolve(options.args[0]));
	const touched = /* @__PURE__ */ new Set();
	for (const record of records) {
		const result = await putInput({
			spec: activation.configSpec,
			contextName: activation.spec.config,
			runner: options.configRunner,
			strategy: settings.dropins,
			rebuild: false,
			initiallyDisabled: record.disabled,
			selector: `${record.channel}/${record.channel}`,
			source: record.source,
			name: basename(record.source)
		});
		if (result !== 0) return result;
		touched.add(record.channel);
	}
	for (const channel of ["zimenv", "zimrc"]) {
		if (!touched.has(channel)) continue;
		const assembled = await runAssembly({
			spec: activation.configSpec,
			contextName: activation.spec.config,
			runner: options.configRunner,
			names: [channel]
		});
		if (assembled !== 0) return assembled;
		await buildChannel(channel, activation, spec.canonical);
	}
	console.log(`install-zim-context: imported ${records.length} fragment(s) for context ${activation.name}`);
	return 0;
}
async function statusZim(activation, spec, deploymentDir, configRunner, activationOnly) {
	const configResult = activationOnly ? 0 : await statusContext({
		spec: activation.configSpec,
		contextName: activation.spec.config,
		runner: configRunner,
		names: ["zimrc", "zimenv"],
		format: "human"
	});
	const healthy = await activationHealthy(activation, spec.canonical);
	const registryResult = await runRegistry("status", activation, spec.canonical, deploymentDir);
	if (configResult === 2 || registryResult === 2) return 2;
	return configResult === 0 && healthy && registryResult === 0 ? 0 : 1;
}
async function runZim(options, deploymentDir) {
	if (options.action !== "status" && truthy(process.env.COMPFUZOR_ZIM_BYPASS)) {
		console.error(`skipped Zim ${options.action}: COMPFUZOR_ZIM_BYPASS`);
		return 0;
	}
	const [zimSpec, configSpec] = await Promise.all([readFile(options.zimSpecPath, "utf8").then((text) => JSON.parse(text)), readFile(options.configSpecPath, "utf8").then((text) => JSON.parse(text))]);
	if (zimSpec.version !== 2) fail$1(`unsupported Zim spec version: ${String(zimSpec.version)}; rerender the deployment with the current playbook (expected version 2)`);
	const settings = resolveSettings(options, zimSpec, configSpec);
	const activation = resolveActivation(settings.contextName, zimSpec, configSpec);
	if (options.action === "install") return installZim(options, settings, activation, zimSpec, deploymentDir);
	if (options.action === "import") return importProducer(options, settings, activation, zimSpec);
	return statusZim(activation, zimSpec, deploymentDir, options.configRunner, options.activationOnly);
}
async function main$1(argv, deploymentDir) {
	return runZim(parseZimArgs(argv, deploymentDir), deploymentDir);
}
//#endregion
//#region node_modules/.pnpm/yaml@2.9.1/node_modules/yaml/dist/nodes/identity.js
var require_identity = /* @__PURE__ */ __commonJSMin(((exports) => {
	const ALIAS = Symbol.for("yaml.alias");
	const DOC = Symbol.for("yaml.document");
	const MAP = Symbol.for("yaml.map");
	const PAIR = Symbol.for("yaml.pair");
	const SCALAR = Symbol.for("yaml.scalar");
	const SEQ = Symbol.for("yaml.seq");
	const NODE_TYPE = Symbol.for("yaml.node.type");
	const isAlias = (node) => !!node && typeof node === "object" && node[NODE_TYPE] === ALIAS;
	const isDocument = (node) => !!node && typeof node === "object" && node[NODE_TYPE] === DOC;
	const isMap = (node) => !!node && typeof node === "object" && node[NODE_TYPE] === MAP;
	const isPair = (node) => !!node && typeof node === "object" && node[NODE_TYPE] === PAIR;
	const isScalar = (node) => !!node && typeof node === "object" && node[NODE_TYPE] === SCALAR;
	const isSeq = (node) => !!node && typeof node === "object" && node[NODE_TYPE] === SEQ;
	function isCollection(node) {
		if (node && typeof node === "object") switch (node[NODE_TYPE]) {
			case MAP:
			case SEQ: return true;
		}
		return false;
	}
	function isNode(node) {
		if (node && typeof node === "object") switch (node[NODE_TYPE]) {
			case ALIAS:
			case MAP:
			case SCALAR:
			case SEQ: return true;
		}
		return false;
	}
	const hasAnchor = (node) => (isScalar(node) || isCollection(node)) && !!node.anchor;
	exports.ALIAS = ALIAS;
	exports.DOC = DOC;
	exports.MAP = MAP;
	exports.NODE_TYPE = NODE_TYPE;
	exports.PAIR = PAIR;
	exports.SCALAR = SCALAR;
	exports.SEQ = SEQ;
	exports.hasAnchor = hasAnchor;
	exports.isAlias = isAlias;
	exports.isCollection = isCollection;
	exports.isDocument = isDocument;
	exports.isMap = isMap;
	exports.isNode = isNode;
	exports.isPair = isPair;
	exports.isScalar = isScalar;
	exports.isSeq = isSeq;
}));
//#endregion
//#region node_modules/.pnpm/yaml@2.9.1/node_modules/yaml/dist/visit.js
var require_visit = /* @__PURE__ */ __commonJSMin(((exports) => {
	var identity = require_identity();
	const BREAK = Symbol("break visit");
	const SKIP = Symbol("skip children");
	const REMOVE = Symbol("remove node");
	/**
	* Apply a visitor to an AST node or document.
	*
	* Walks through the tree (depth-first) starting from `node`, calling a
	* `visitor` function with three arguments:
	*   - `key`: For sequence values and map `Pair`, the node's index in the
	*     collection. Within a `Pair`, `'key'` or `'value'`, correspondingly.
	*     `null` for the root node.
	*   - `node`: The current node.
	*   - `path`: The ancestry of the current node.
	*
	* The return value of the visitor may be used to control the traversal:
	*   - `undefined` (default): Do nothing and continue
	*   - `visit.SKIP`: Do not visit the children of this node, continue with next
	*     sibling
	*   - `visit.BREAK`: Terminate traversal completely
	*   - `visit.REMOVE`: Remove the current node, then continue with the next one
	*   - `Node`: Replace the current node, then continue by visiting it
	*   - `number`: While iterating the items of a sequence or map, set the index
	*     of the next step. This is useful especially if the index of the current
	*     node has changed.
	*
	* If `visitor` is a single function, it will be called with all values
	* encountered in the tree, including e.g. `null` values. Alternatively,
	* separate visitor functions may be defined for each `Map`, `Pair`, `Seq`,
	* `Alias` and `Scalar` node. To define the same visitor function for more than
	* one node type, use the `Collection` (map and seq), `Value` (map, seq & scalar)
	* and `Node` (alias, map, seq & scalar) targets. Of all these, only the most
	* specific defined one will be used for each node.
	*/
	function visit(node, visitor) {
		const visitor_ = initVisitor(visitor);
		if (identity.isDocument(node)) {
			if (visit_(null, node.contents, visitor_, Object.freeze([node])) === REMOVE) node.contents = null;
		} else visit_(null, node, visitor_, Object.freeze([]));
	}
	/** Terminate visit traversal completely */
	visit.BREAK = BREAK;
	/** Do not visit the children of the current node */
	visit.SKIP = SKIP;
	/** Remove the current node */
	visit.REMOVE = REMOVE;
	function visit_(key, node, visitor, path) {
		const ctrl = callVisitor(key, node, visitor, path);
		if (identity.isNode(ctrl) || identity.isPair(ctrl)) {
			replaceNode(key, path, ctrl);
			return visit_(key, ctrl, visitor, path);
		}
		if (typeof ctrl !== "symbol") {
			if (identity.isCollection(node)) {
				path = Object.freeze(path.concat(node));
				for (let i = 0; i < node.items.length; ++i) {
					const ci = visit_(i, node.items[i], visitor, path);
					if (typeof ci === "number") i = ci - 1;
					else if (ci === BREAK) return BREAK;
					else if (ci === REMOVE) {
						node.items.splice(i, 1);
						i -= 1;
					}
				}
			} else if (identity.isPair(node)) {
				path = Object.freeze(path.concat(node));
				const ck = visit_("key", node.key, visitor, path);
				if (ck === BREAK) return BREAK;
				else if (ck === REMOVE) node.key = null;
				const cv = visit_("value", node.value, visitor, path);
				if (cv === BREAK) return BREAK;
				else if (cv === REMOVE) node.value = null;
			}
		}
		return ctrl;
	}
	/**
	* Apply an async visitor to an AST node or document.
	*
	* Walks through the tree (depth-first) starting from `node`, calling a
	* `visitor` function with three arguments:
	*   - `key`: For sequence values and map `Pair`, the node's index in the
	*     collection. Within a `Pair`, `'key'` or `'value'`, correspondingly.
	*     `null` for the root node.
	*   - `node`: The current node.
	*   - `path`: The ancestry of the current node.
	*
	* The return value of the visitor may be used to control the traversal:
	*   - `Promise`: Must resolve to one of the following values
	*   - `undefined` (default): Do nothing and continue
	*   - `visit.SKIP`: Do not visit the children of this node, continue with next
	*     sibling
	*   - `visit.BREAK`: Terminate traversal completely
	*   - `visit.REMOVE`: Remove the current node, then continue with the next one
	*   - `Node`: Replace the current node, then continue by visiting it
	*   - `number`: While iterating the items of a sequence or map, set the index
	*     of the next step. This is useful especially if the index of the current
	*     node has changed.
	*
	* If `visitor` is a single function, it will be called with all values
	* encountered in the tree, including e.g. `null` values. Alternatively,
	* separate visitor functions may be defined for each `Map`, `Pair`, `Seq`,
	* `Alias` and `Scalar` node. To define the same visitor function for more than
	* one node type, use the `Collection` (map and seq), `Value` (map, seq & scalar)
	* and `Node` (alias, map, seq & scalar) targets. Of all these, only the most
	* specific defined one will be used for each node.
	*/
	async function visitAsync(node, visitor) {
		const visitor_ = initVisitor(visitor);
		if (identity.isDocument(node)) {
			if (await visitAsync_(null, node.contents, visitor_, Object.freeze([node])) === REMOVE) node.contents = null;
		} else await visitAsync_(null, node, visitor_, Object.freeze([]));
	}
	/** Terminate visit traversal completely */
	visitAsync.BREAK = BREAK;
	/** Do not visit the children of the current node */
	visitAsync.SKIP = SKIP;
	/** Remove the current node */
	visitAsync.REMOVE = REMOVE;
	async function visitAsync_(key, node, visitor, path) {
		const ctrl = await callVisitor(key, node, visitor, path);
		if (identity.isNode(ctrl) || identity.isPair(ctrl)) {
			replaceNode(key, path, ctrl);
			return visitAsync_(key, ctrl, visitor, path);
		}
		if (typeof ctrl !== "symbol") {
			if (identity.isCollection(node)) {
				path = Object.freeze(path.concat(node));
				for (let i = 0; i < node.items.length; ++i) {
					const ci = await visitAsync_(i, node.items[i], visitor, path);
					if (typeof ci === "number") i = ci - 1;
					else if (ci === BREAK) return BREAK;
					else if (ci === REMOVE) {
						node.items.splice(i, 1);
						i -= 1;
					}
				}
			} else if (identity.isPair(node)) {
				path = Object.freeze(path.concat(node));
				const ck = await visitAsync_("key", node.key, visitor, path);
				if (ck === BREAK) return BREAK;
				else if (ck === REMOVE) node.key = null;
				const cv = await visitAsync_("value", node.value, visitor, path);
				if (cv === BREAK) return BREAK;
				else if (cv === REMOVE) node.value = null;
			}
		}
		return ctrl;
	}
	function initVisitor(visitor) {
		if (typeof visitor === "object" && (visitor.Collection || visitor.Node || visitor.Value)) return Object.assign({
			Alias: visitor.Node,
			Map: visitor.Node,
			Scalar: visitor.Node,
			Seq: visitor.Node
		}, visitor.Value && {
			Map: visitor.Value,
			Scalar: visitor.Value,
			Seq: visitor.Value
		}, visitor.Collection && {
			Map: visitor.Collection,
			Seq: visitor.Collection
		}, visitor);
		return visitor;
	}
	function callVisitor(key, node, visitor, path) {
		if (typeof visitor === "function") return visitor(key, node, path);
		if (identity.isMap(node)) return visitor.Map?.(key, node, path);
		if (identity.isSeq(node)) return visitor.Seq?.(key, node, path);
		if (identity.isPair(node)) return visitor.Pair?.(key, node, path);
		if (identity.isScalar(node)) return visitor.Scalar?.(key, node, path);
		if (identity.isAlias(node)) return visitor.Alias?.(key, node, path);
	}
	function replaceNode(key, path, node) {
		const parent = path[path.length - 1];
		if (identity.isCollection(parent)) parent.items[key] = node;
		else if (identity.isPair(parent)) {
			if (key === "key") parent.key = node;
			else parent.value = node;
		} else if (identity.isDocument(parent)) parent.contents = node;
		else {
			const pt = identity.isAlias(parent) ? "alias" : "scalar";
			throw new Error(`Cannot replace node with ${pt} parent`);
		}
	}
	exports.visit = visit;
	exports.visitAsync = visitAsync;
}));
//#endregion
//#region node_modules/.pnpm/yaml@2.9.1/node_modules/yaml/dist/doc/directives.js
var require_directives = /* @__PURE__ */ __commonJSMin(((exports) => {
	var identity = require_identity();
	var visit = require_visit();
	const escapeChars = {
		"!": "%21",
		",": "%2C",
		"[": "%5B",
		"]": "%5D",
		"{": "%7B",
		"}": "%7D"
	};
	const escapeTagName = (tn) => tn.replace(/[!,[\]{}]/g, (ch) => escapeChars[ch]);
	var Directives = class Directives {
		constructor(yaml, tags) {
			/**
			* The directives-end/doc-start marker `---`. If `null`, a marker may still be
			* included in the document's stringified representation.
			*/
			this.docStart = null;
			/** The doc-end marker `...`.  */
			this.docEnd = false;
			this.yaml = Object.assign({}, Directives.defaultYaml, yaml);
			this.tags = Object.assign({}, Directives.defaultTags, tags);
		}
		clone() {
			const copy = new Directives(this.yaml, this.tags);
			copy.docStart = this.docStart;
			return copy;
		}
		/**
		* During parsing, get a Directives instance for the current document and
		* update the stream state according to the current version's spec.
		*/
		atDocument() {
			const res = new Directives(this.yaml, this.tags);
			switch (this.yaml.version) {
				case "1.1":
					this.atNextDocument = true;
					break;
				case "1.2":
					this.atNextDocument = false;
					this.yaml = {
						explicit: Directives.defaultYaml.explicit,
						version: "1.2"
					};
					this.tags = Object.assign({}, Directives.defaultTags);
			}
			return res;
		}
		/**
		* @param onError - May be called even if the action was successful
		* @returns `true` on success
		*/
		add(line, onError) {
			if (this.atNextDocument) {
				this.yaml = {
					explicit: Directives.defaultYaml.explicit,
					version: "1.1"
				};
				this.tags = Object.assign({}, Directives.defaultTags);
				this.atNextDocument = false;
			}
			const parts = line.trim().split(/[ \t]+/);
			const name = parts.shift();
			switch (name) {
				case "%TAG": {
					if (parts.length !== 2) {
						onError(0, "%TAG directive should contain exactly two parts");
						if (parts.length < 2) return false;
					}
					const [handle, prefix] = parts;
					this.tags[handle] = prefix;
					return true;
				}
				case "%YAML": {
					this.yaml.explicit = true;
					if (parts.length !== 1) {
						onError(0, "%YAML directive should contain exactly one part");
						return false;
					}
					const [version] = parts;
					if (version === "1.1" || version === "1.2") {
						this.yaml.version = version;
						return true;
					} else {
						const isValid = /^\d+\.\d+$/.test(version);
						onError(6, `Unsupported YAML version ${version}`, isValid);
						return false;
					}
				}
				default:
					onError(0, `Unknown directive ${name}`, true);
					return false;
			}
		}
		/**
		* Resolves a tag, matching handles to those defined in %TAG directives.
		*
		* @returns Resolved tag, which may also be the non-specific tag `'!'` or a
		*   `'!local'` tag, or `null` if unresolvable.
		*/
		tagName(source, onError) {
			if (source === "!") return "!";
			if (source[0] !== "!") {
				onError(`Not a valid tag: ${source}`);
				return null;
			}
			if (source[1] === "<") {
				const verbatim = source.slice(2, -1);
				if (verbatim === "!" || verbatim === "!!") {
					onError(`Verbatim tags aren't resolved, so ${source} is invalid.`);
					return null;
				}
				if (source[source.length - 1] !== ">") onError("Verbatim tags must end with a >");
				return verbatim;
			}
			const [, handle, suffix] = source.match(/^(.*!)([^!]*)$/s);
			if (!suffix) onError(`The ${source} tag has no suffix`);
			const prefix = this.tags[handle];
			if (prefix) try {
				return prefix + decodeURIComponent(suffix);
			} catch (error) {
				onError(String(error));
				return null;
			}
			if (handle === "!") return source;
			onError(`Could not resolve tag: ${source}`);
			return null;
		}
		/**
		* Given a fully resolved tag, returns its printable string form,
		* taking into account current tag prefixes and defaults.
		*/
		tagString(tag) {
			for (const [handle, prefix] of Object.entries(this.tags)) if (tag.startsWith(prefix)) return handle + escapeTagName(tag.substring(prefix.length));
			return tag[0] === "!" ? tag : `!<${tag}>`;
		}
		toString(doc) {
			const lines = this.yaml.explicit ? [`%YAML ${this.yaml.version || "1.2"}`] : [];
			const tagEntries = Object.entries(this.tags);
			let tagNames;
			if (doc && tagEntries.length > 0 && identity.isNode(doc.contents)) {
				const tags = {};
				visit.visit(doc.contents, (_key, node) => {
					if (identity.isNode(node) && node.tag) tags[node.tag] = true;
				});
				tagNames = Object.keys(tags);
			} else tagNames = [];
			for (const [handle, prefix] of tagEntries) {
				if (handle === "!!" && prefix === "tag:yaml.org,2002:") continue;
				if (!doc || tagNames.some((tn) => tn.startsWith(prefix))) lines.push(`%TAG ${handle} ${prefix}`);
			}
			return lines.join("\n");
		}
	};
	Directives.defaultYaml = {
		explicit: false,
		version: "1.2"
	};
	Directives.defaultTags = { "!!": "tag:yaml.org,2002:" };
	exports.Directives = Directives;
}));
//#endregion
//#region node_modules/.pnpm/yaml@2.9.1/node_modules/yaml/dist/doc/anchors.js
var require_anchors = /* @__PURE__ */ __commonJSMin(((exports) => {
	var identity = require_identity();
	var visit = require_visit();
	/**
	* Verify that the input string is a valid anchor.
	*
	* Will throw on errors.
	*/
	function anchorIsValid(anchor) {
		if (/[\x00-\x19\s,[\]{}]/.test(anchor)) {
			const msg = `Anchor must not contain whitespace or control characters: ${JSON.stringify(anchor)}`;
			throw new Error(msg);
		}
		return true;
	}
	function anchorNames(root) {
		const anchors = /* @__PURE__ */ new Set();
		visit.visit(root, { Value(_key, node) {
			if (node.anchor) anchors.add(node.anchor);
		} });
		return anchors;
	}
	/** Find a new anchor name with the given `prefix` and a one-indexed suffix. */
	function findNewAnchor(prefix, exclude) {
		for (let i = 1;; ++i) {
			const name = `${prefix}${i}`;
			if (!exclude.has(name)) return name;
		}
	}
	function createNodeAnchors(doc, prefix) {
		const aliasObjects = [];
		const sourceObjects = /* @__PURE__ */ new Map();
		let prevAnchors = null;
		return {
			onAnchor: (source) => {
				aliasObjects.push(source);
				prevAnchors ?? (prevAnchors = anchorNames(doc));
				const anchor = findNewAnchor(prefix, prevAnchors);
				prevAnchors.add(anchor);
				return anchor;
			},
			/**
			* With circular references, the source node is only resolved after all
			* of its child nodes are. This is why anchors are set only after all of
			* the nodes have been created.
			*/
			setAnchors: () => {
				for (const source of aliasObjects) {
					const ref = sourceObjects.get(source);
					if (typeof ref === "object" && ref.anchor && (identity.isScalar(ref.node) || identity.isCollection(ref.node))) ref.node.anchor = ref.anchor;
					else {
						const error = /* @__PURE__ */ new Error("Failed to resolve repeated object (this should not happen)");
						error.source = source;
						throw error;
					}
				}
			},
			sourceObjects
		};
	}
	exports.anchorIsValid = anchorIsValid;
	exports.anchorNames = anchorNames;
	exports.createNodeAnchors = createNodeAnchors;
	exports.findNewAnchor = findNewAnchor;
}));
//#endregion
//#region node_modules/.pnpm/yaml@2.9.1/node_modules/yaml/dist/doc/applyReviver.js
var require_applyReviver = /* @__PURE__ */ __commonJSMin(((exports) => {
	/**
	* Applies the JSON.parse reviver algorithm as defined in the ECMA-262 spec,
	* in section 24.5.1.1 "Runtime Semantics: InternalizeJSONProperty" of the
	* 2021 edition: https://tc39.es/ecma262/#sec-json.parse
	*
	* Includes extensions for handling Map and Set objects.
	*/
	function applyReviver(reviver, obj, key, val) {
		if (val && typeof val === "object") {
			if (Array.isArray(val)) for (let i = 0, len = val.length; i < len; ++i) {
				const v0 = val[i];
				const v1 = applyReviver(reviver, val, String(i), v0);
				if (v1 === void 0) delete val[i];
				else if (v1 !== v0) val[i] = v1;
			}
			else if (val instanceof Map) for (const k of Array.from(val.keys())) {
				const v0 = val.get(k);
				const v1 = applyReviver(reviver, val, k, v0);
				if (v1 === void 0) val.delete(k);
				else if (v1 !== v0) val.set(k, v1);
			}
			else if (val instanceof Set) for (const v0 of Array.from(val)) {
				const v1 = applyReviver(reviver, val, v0, v0);
				if (v1 === void 0) val.delete(v0);
				else if (v1 !== v0) {
					val.delete(v0);
					val.add(v1);
				}
			}
			else for (const [k, v0] of Object.entries(val)) {
				const v1 = applyReviver(reviver, val, k, v0);
				if (v1 === void 0) delete val[k];
				else if (v1 !== v0) val[k] = v1;
			}
		}
		return reviver.call(obj, key, val);
	}
	exports.applyReviver = applyReviver;
}));
//#endregion
//#region node_modules/.pnpm/yaml@2.9.1/node_modules/yaml/dist/nodes/toJS.js
var require_toJS = /* @__PURE__ */ __commonJSMin(((exports) => {
	var identity = require_identity();
	/**
	* Recursively convert any node or its contents to native JavaScript
	*
	* @param value - The input value
	* @param arg - If `value` defines a `toJSON()` method, use this
	*   as its first argument
	* @param ctx - Conversion context, originally set in Document#toJS(). If
	*   `{ keep: true }` is not set, output should be suitable for JSON
	*   stringification.
	*/
	function toJS(value, arg, ctx) {
		if (Array.isArray(value)) return value.map((v, i) => toJS(v, String(i), ctx));
		if (value && typeof value.toJSON === "function") {
			if (!ctx || !identity.hasAnchor(value)) return value.toJSON(arg, ctx);
			const data = {
				aliasCount: 0,
				count: 1,
				res: void 0
			};
			ctx.anchors.set(value, data);
			ctx.onCreate = (res) => {
				data.res = res;
				delete ctx.onCreate;
			};
			const res = value.toJSON(arg, ctx);
			if (ctx.onCreate) ctx.onCreate(res);
			return res;
		}
		if (typeof value === "bigint" && !ctx?.keep) return Number(value);
		return value;
	}
	exports.toJS = toJS;
}));
//#endregion
//#region node_modules/.pnpm/yaml@2.9.1/node_modules/yaml/dist/nodes/Node.js
var require_Node = /* @__PURE__ */ __commonJSMin(((exports) => {
	var applyReviver = require_applyReviver();
	var identity = require_identity();
	var toJS = require_toJS();
	var NodeBase = class {
		constructor(type) {
			Object.defineProperty(this, identity.NODE_TYPE, { value: type });
		}
		/** Create a copy of this node.  */
		clone() {
			const copy = Object.create(Object.getPrototypeOf(this), Object.getOwnPropertyDescriptors(this));
			if (this.range) copy.range = this.range.slice();
			return copy;
		}
		/** A plain JavaScript representation of this node. */
		toJS(doc, { mapAsMap, maxAliasCount, onAnchor, reviver } = {}) {
			if (!identity.isDocument(doc)) throw new TypeError("A document argument is required");
			const ctx = {
				anchors: /* @__PURE__ */ new Map(),
				doc,
				keep: true,
				mapAsMap: mapAsMap === true,
				mapKeyWarned: false,
				maxAliasCount: typeof maxAliasCount === "number" ? maxAliasCount : 100
			};
			const res = toJS.toJS(this, "", ctx);
			if (typeof onAnchor === "function") for (const { count, res } of ctx.anchors.values()) onAnchor(res, count);
			return typeof reviver === "function" ? applyReviver.applyReviver(reviver, { "": res }, "", res) : res;
		}
	};
	exports.NodeBase = NodeBase;
}));
//#endregion
//#region node_modules/.pnpm/yaml@2.9.1/node_modules/yaml/dist/nodes/Alias.js
var require_Alias = /* @__PURE__ */ __commonJSMin(((exports) => {
	var anchors = require_anchors();
	var visit = require_visit();
	var identity = require_identity();
	var Node = require_Node();
	var toJS = require_toJS();
	var Alias = class extends Node.NodeBase {
		constructor(source) {
			super(identity.ALIAS);
			this.source = source;
			Object.defineProperty(this, "tag", { set() {
				throw new Error("Alias nodes cannot have tags");
			} });
		}
		/**
		* Resolve the value of this alias within `doc`, finding the last
		* instance of the `source` anchor before this node.
		*/
		resolve(doc, ctx) {
			if (ctx?.maxAliasCount === 0) throw new ReferenceError("Alias resolution is disabled");
			let nodes;
			if (ctx?.aliasResolveCache) nodes = ctx.aliasResolveCache;
			else {
				nodes = [];
				visit.visit(doc, { Node: (_key, node) => {
					if (identity.isAlias(node) || identity.hasAnchor(node)) nodes.push(node);
				} });
				if (ctx) ctx.aliasResolveCache = nodes;
			}
			let found = void 0;
			for (const node of nodes) {
				if (node === this) break;
				if (node.anchor === this.source) found = node;
			}
			if (found && ctx) {
				const { anchors, doc, maxAliasCount } = ctx;
				let data = anchors.get(found);
				if (!data) {
					toJS.toJS(found, null, ctx);
					data = anchors.get(found);
				}
				/* istanbul ignore if */
				if (data?.res === void 0) throw new ReferenceError("This should not happen: Alias anchor was not resolved?");
				if (maxAliasCount >= 0) {
					data.count += 1;
					if (data.aliasCount === 0) data.aliasCount = getAliasCount(doc, found, anchors);
					if (data.count * data.aliasCount > maxAliasCount) throw new ReferenceError("Excessive alias count indicates a resource exhaustion attack");
				}
			}
			return found;
		}
		toJSON(_arg, ctx) {
			if (!ctx) return { source: this.source };
			const source = this.resolve(ctx.doc, ctx);
			if (!source) {
				const msg = `Unresolved alias (the anchor must be set before the alias): ${this.source}`;
				throw new ReferenceError(msg);
			}
			return ctx.anchors.get(source).res;
		}
		toString(ctx, _onComment, _onChompKeep) {
			const src = `*${this.source}`;
			if (ctx) {
				anchors.anchorIsValid(this.source);
				if (ctx.options.verifyAliasOrder && !ctx.anchors.has(this.source)) {
					const msg = `Unresolved alias (the anchor must be set before the alias): ${this.source}`;
					throw new Error(msg);
				}
				if (ctx.implicitKey) return `${src} `;
			}
			return src;
		}
	};
	function getAliasCount(doc, node, anchors) {
		if (identity.isAlias(node)) {
			const source = node.resolve(doc);
			const anchor = anchors && source && anchors.get(source);
			return anchor ? anchor.count * anchor.aliasCount : 0;
		} else if (identity.isCollection(node)) {
			let count = 0;
			for (const item of node.items) {
				const c = getAliasCount(doc, item, anchors);
				if (c > count) count = c;
			}
			return count;
		} else if (identity.isPair(node)) {
			const kc = getAliasCount(doc, node.key, anchors);
			const vc = getAliasCount(doc, node.value, anchors);
			return Math.max(kc, vc);
		}
		return 1;
	}
	exports.Alias = Alias;
}));
//#endregion
//#region node_modules/.pnpm/yaml@2.9.1/node_modules/yaml/dist/nodes/Scalar.js
var require_Scalar = /* @__PURE__ */ __commonJSMin(((exports) => {
	var identity = require_identity();
	var Node = require_Node();
	var toJS = require_toJS();
	const isScalarValue = (value) => !value || typeof value !== "function" && typeof value !== "object";
	var Scalar = class extends Node.NodeBase {
		constructor(value) {
			super(identity.SCALAR);
			this.value = value;
		}
		toJSON(arg, ctx) {
			return ctx?.keep ? this.value : toJS.toJS(this.value, arg, ctx);
		}
		toString() {
			return String(this.value);
		}
	};
	Scalar.BLOCK_FOLDED = "BLOCK_FOLDED";
	Scalar.BLOCK_LITERAL = "BLOCK_LITERAL";
	Scalar.PLAIN = "PLAIN";
	Scalar.QUOTE_DOUBLE = "QUOTE_DOUBLE";
	Scalar.QUOTE_SINGLE = "QUOTE_SINGLE";
	exports.Scalar = Scalar;
	exports.isScalarValue = isScalarValue;
}));
//#endregion
//#region node_modules/.pnpm/yaml@2.9.1/node_modules/yaml/dist/doc/createNode.js
var require_createNode = /* @__PURE__ */ __commonJSMin(((exports) => {
	var Alias = require_Alias();
	var identity = require_identity();
	var Scalar = require_Scalar();
	const defaultTagPrefix = "tag:yaml.org,2002:";
	function findTagObject(value, tagName, tags) {
		if (tagName) {
			const match = tags.filter((t) => t.tag === tagName);
			const tagObj = match.find((t) => !t.format) ?? match[0];
			if (!tagObj) throw new Error(`Tag ${tagName} not found`);
			return tagObj;
		}
		return tags.find((t) => t.identify?.(value) && !t.format);
	}
	function createNode(value, tagName, ctx) {
		if (identity.isDocument(value)) value = value.contents;
		if (identity.isNode(value)) return value;
		if (identity.isPair(value)) {
			const map = ctx.schema[identity.MAP].createNode?.(ctx.schema, null, ctx);
			map.items.push(value);
			return map;
		}
		if (value instanceof String || value instanceof Number || value instanceof Boolean || typeof BigInt !== "undefined" && value instanceof BigInt) value = value.valueOf();
		const { aliasDuplicateObjects, onAnchor, onTagObj, schema, sourceObjects } = ctx;
		let ref = void 0;
		if (aliasDuplicateObjects && value && typeof value === "object") {
			ref = sourceObjects.get(value);
			if (ref) {
				ref.anchor ?? (ref.anchor = onAnchor(value));
				return new Alias.Alias(ref.anchor);
			} else {
				ref = {
					anchor: null,
					node: null
				};
				sourceObjects.set(value, ref);
			}
		}
		if (tagName?.startsWith("!!")) tagName = defaultTagPrefix + tagName.slice(2);
		let tagObj = findTagObject(value, tagName, schema.tags);
		if (!tagObj) {
			if (value && typeof value.toJSON === "function") value = value.toJSON();
			if (!value || typeof value !== "object") {
				const node = new Scalar.Scalar(value);
				if (ref) ref.node = node;
				return node;
			}
			tagObj = value instanceof Map ? schema[identity.MAP] : Symbol.iterator in Object(value) ? schema[identity.SEQ] : schema[identity.MAP];
		}
		if (onTagObj) {
			onTagObj(tagObj);
			delete ctx.onTagObj;
		}
		const node = tagObj?.createNode ? tagObj.createNode(ctx.schema, value, ctx) : typeof tagObj?.nodeClass?.from === "function" ? tagObj.nodeClass.from(ctx.schema, value, ctx) : new Scalar.Scalar(value);
		if (tagName) node.tag = tagName;
		else if (!tagObj.default) node.tag = tagObj.tag;
		if (ref) ref.node = node;
		return node;
	}
	exports.createNode = createNode;
}));
//#endregion
//#region node_modules/.pnpm/yaml@2.9.1/node_modules/yaml/dist/nodes/Collection.js
var require_Collection = /* @__PURE__ */ __commonJSMin(((exports) => {
	var createNode = require_createNode();
	var identity = require_identity();
	var Node = require_Node();
	function collectionFromPath(schema, path, value) {
		let v = value;
		for (let i = path.length - 1; i >= 0; --i) {
			const k = path[i];
			if (typeof k === "number" && Number.isInteger(k) && k >= 0) {
				const a = [];
				a[k] = v;
				v = a;
			} else v = /* @__PURE__ */ new Map([[k, v]]);
		}
		return createNode.createNode(v, void 0, {
			aliasDuplicateObjects: false,
			keepUndefined: false,
			onAnchor: () => {
				throw new Error("This should not happen, please report a bug.");
			},
			schema,
			sourceObjects: /* @__PURE__ */ new Map()
		});
	}
	const isEmptyPath = (path) => path == null || typeof path === "object" && !!path[Symbol.iterator]().next().done;
	var Collection = class extends Node.NodeBase {
		constructor(type, schema) {
			super(type);
			Object.defineProperty(this, "schema", {
				value: schema,
				configurable: true,
				enumerable: false,
				writable: true
			});
		}
		/**
		* Create a copy of this collection.
		*
		* @param schema - If defined, overwrites the original's schema
		*/
		clone(schema) {
			const copy = Object.create(Object.getPrototypeOf(this), Object.getOwnPropertyDescriptors(this));
			if (schema) copy.schema = schema;
			copy.items = copy.items.map((it) => identity.isNode(it) || identity.isPair(it) ? it.clone(schema) : it);
			if (this.range) copy.range = this.range.slice();
			return copy;
		}
		/**
		* Adds a value to the collection. For `!!map` and `!!omap` the value must
		* be a Pair instance or a `{ key, value }` object, which may not have a key
		* that already exists in the map.
		*/
		addIn(path, value) {
			if (isEmptyPath(path)) this.add(value);
			else {
				const [key, ...rest] = path;
				const node = this.get(key, true);
				if (identity.isCollection(node)) node.addIn(rest, value);
				else if (node === void 0 && this.schema) this.set(key, collectionFromPath(this.schema, rest, value));
				else throw new Error(`Expected YAML collection at ${key}. Remaining path: ${rest}`);
			}
		}
		/**
		* Removes a value from the collection.
		* @returns `true` if the item was found and removed.
		*/
		deleteIn(path) {
			const [key, ...rest] = path;
			if (rest.length === 0) return this.delete(key);
			const node = this.get(key, true);
			if (identity.isCollection(node)) return node.deleteIn(rest);
			else throw new Error(`Expected YAML collection at ${key}. Remaining path: ${rest}`);
		}
		/**
		* Returns item at `key`, or `undefined` if not found. By default unwraps
		* scalar values from their surrounding node; to disable set `keepScalar` to
		* `true` (collections are always returned intact).
		*/
		getIn(path, keepScalar) {
			const [key, ...rest] = path;
			const node = this.get(key, true);
			if (rest.length === 0) return !keepScalar && identity.isScalar(node) ? node.value : node;
			else return identity.isCollection(node) ? node.getIn(rest, keepScalar) : void 0;
		}
		hasAllNullValues(allowScalar) {
			return this.items.every((node) => {
				if (!identity.isPair(node)) return false;
				const n = node.value;
				return n == null || allowScalar && identity.isScalar(n) && n.value == null && !n.commentBefore && !n.comment && !n.tag;
			});
		}
		/**
		* Checks if the collection includes a value with the key `key`.
		*/
		hasIn(path) {
			const [key, ...rest] = path;
			if (rest.length === 0) return this.has(key);
			const node = this.get(key, true);
			return identity.isCollection(node) ? node.hasIn(rest) : false;
		}
		/**
		* Sets a value in this collection. For `!!set`, `value` needs to be a
		* boolean to add/remove the item from the set.
		*/
		setIn(path, value) {
			const [key, ...rest] = path;
			if (rest.length === 0) this.set(key, value);
			else {
				const node = this.get(key, true);
				if (identity.isCollection(node)) node.setIn(rest, value);
				else if (node === void 0 && this.schema) this.set(key, collectionFromPath(this.schema, rest, value));
				else throw new Error(`Expected YAML collection at ${key}. Remaining path: ${rest}`);
			}
		}
	};
	exports.Collection = Collection;
	exports.collectionFromPath = collectionFromPath;
	exports.isEmptyPath = isEmptyPath;
}));
//#endregion
//#region node_modules/.pnpm/yaml@2.9.1/node_modules/yaml/dist/stringify/stringifyComment.js
var require_stringifyComment = /* @__PURE__ */ __commonJSMin(((exports) => {
	/**
	* Stringifies a comment.
	*
	* Empty comment lines are left empty,
	* lines consisting of a single space are replaced by `#`,
	* and all other lines are prefixed with a `#`.
	*/
	const stringifyComment = (str) => str.replace(/^(?!$)(?: $)?/gm, "#");
	function indentComment(comment, indent) {
		if (/^\n+$/.test(comment)) return comment.substring(1);
		return indent ? comment.replace(/^(?! *$)/gm, indent) : comment;
	}
	const lineComment = (str, indent, comment) => str.endsWith("\n") ? indentComment(comment, indent) : comment.includes("\n") ? "\n" + indentComment(comment, indent) : (str.endsWith(" ") ? "" : " ") + comment;
	exports.indentComment = indentComment;
	exports.lineComment = lineComment;
	exports.stringifyComment = stringifyComment;
}));
//#endregion
//#region node_modules/.pnpm/yaml@2.9.1/node_modules/yaml/dist/stringify/foldFlowLines.js
var require_foldFlowLines = /* @__PURE__ */ __commonJSMin(((exports) => {
	const FOLD_FLOW = "flow";
	const FOLD_BLOCK = "block";
	const FOLD_QUOTED = "quoted";
	/**
	* Tries to keep input at up to `lineWidth` characters, splitting only on spaces
	* not followed by newlines or spaces unless `mode` is `'quoted'`. Lines are
	* terminated with `\n` and started with `indent`.
	*/
	function foldFlowLines(text, indent, mode = "flow", { indentAtStart, lineWidth = 80, minContentWidth = 20, onFold, onOverflow } = {}) {
		if (!lineWidth || lineWidth < 0) return text;
		if (lineWidth < minContentWidth) minContentWidth = 0;
		const endStep = Math.max(1 + minContentWidth, 1 + lineWidth - indent.length);
		if (text.length <= endStep) return text;
		const folds = [];
		const escapedFolds = {};
		let end = lineWidth - indent.length;
		if (typeof indentAtStart === "number") {
			if (indentAtStart > lineWidth - Math.max(2, minContentWidth)) folds.push(0);
			else end = lineWidth - indentAtStart;
		}
		let split = void 0;
		let prev = void 0;
		let overflow = false;
		let i = -1;
		let escStart = -1;
		let escEnd = -1;
		if (mode === FOLD_BLOCK) {
			i = consumeMoreIndentedLines(text, i, indent.length);
			if (i !== -1) end = i + endStep;
		}
		for (let ch; ch = text[i += 1];) {
			if (mode === FOLD_QUOTED && ch === "\\") {
				escStart = i;
				switch (text[i + 1]) {
					case "x":
						i += 3;
						break;
					case "u":
						i += 5;
						break;
					case "U":
						i += 9;
						break;
					default: i += 1;
				}
				escEnd = i;
			}
			if (ch === "\n") {
				if (mode === FOLD_BLOCK) i = consumeMoreIndentedLines(text, i, indent.length);
				end = i + indent.length + endStep;
				split = void 0;
			} else {
				if (ch === " " && prev && prev !== " " && prev !== "\n" && prev !== "	") {
					const next = text[i + 1];
					if (next && next !== " " && next !== "\n" && next !== "	") split = i;
				}
				if (i >= end) {
					if (split) {
						folds.push(split);
						end = split + endStep;
						split = void 0;
					} else if (mode === FOLD_QUOTED) {
						while (prev === " " || prev === "	") {
							prev = ch;
							ch = text[i += 1];
							overflow = true;
						}
						const j = i > escEnd + 1 ? i - 2 : escStart - 1;
						if (escapedFolds[j]) return text;
						folds.push(j);
						escapedFolds[j] = true;
						end = j + endStep;
						split = void 0;
					} else overflow = true;
				}
			}
			prev = ch;
		}
		if (overflow && onOverflow) onOverflow();
		if (folds.length === 0) return text;
		if (onFold) onFold();
		let res = text.slice(0, folds[0]);
		for (let i = 0; i < folds.length; ++i) {
			const fold = folds[i];
			const end = folds[i + 1] || text.length;
			if (fold === 0) res = `\n${indent}${text.slice(0, end)}`;
			else {
				if (mode === FOLD_QUOTED && escapedFolds[fold]) res += `${text[fold]}\\`;
				res += `\n${indent}${text.slice(fold + 1, end)}`;
			}
		}
		return res;
	}
	/**
	* Presumes `i + 1` is at the start of a line
	* @returns index of last newline in more-indented block
	*/
	function consumeMoreIndentedLines(text, i, indent) {
		let end = i;
		let start = i + 1;
		let ch = text[start];
		while (ch === " " || ch === "	") if (i < start + indent) ch = text[++i];
		else {
			do
				ch = text[++i];
			while (ch && ch !== "\n");
			end = i;
			start = i + 1;
			ch = text[start];
		}
		return end;
	}
	exports.FOLD_BLOCK = FOLD_BLOCK;
	exports.FOLD_FLOW = FOLD_FLOW;
	exports.FOLD_QUOTED = FOLD_QUOTED;
	exports.foldFlowLines = foldFlowLines;
}));
//#endregion
//#region node_modules/.pnpm/yaml@2.9.1/node_modules/yaml/dist/stringify/stringifyString.js
var require_stringifyString = /* @__PURE__ */ __commonJSMin(((exports) => {
	var Scalar = require_Scalar();
	var foldFlowLines = require_foldFlowLines();
	const getFoldOptions = (ctx, isBlock) => ({
		indentAtStart: isBlock ? ctx.indent.length : ctx.indentAtStart,
		lineWidth: ctx.options.lineWidth,
		minContentWidth: ctx.options.minContentWidth
	});
	const containsDocumentMarker = (str) => /^(%|---|\.\.\.)/m.test(str);
	function lineLengthOverLimit(str, lineWidth, indentLength) {
		if (!lineWidth || lineWidth < 0) return false;
		const limit = lineWidth - indentLength;
		const strLen = str.length;
		if (strLen <= limit) return false;
		for (let i = 0, start = 0; i < strLen; ++i) if (str[i] === "\n") {
			if (i - start > limit) return true;
			start = i + 1;
			if (strLen - start <= limit) return false;
		}
		return true;
	}
	function doubleQuotedString(value, ctx) {
		const json = JSON.stringify(value);
		if (ctx.options.doubleQuotedAsJSON) return json;
		const { implicitKey } = ctx;
		const minMultiLineLength = ctx.options.doubleQuotedMinMultiLineLength;
		const indent = ctx.indent || (containsDocumentMarker(value) ? "  " : "");
		let str = "";
		let start = 0;
		for (let i = 0, ch = json[i]; ch; ch = json[++i]) {
			if (ch === " " && json[i + 1] === "\\" && json[i + 2] === "n") {
				str += json.slice(start, i) + "\\ ";
				i += 1;
				start = i;
				ch = "\\";
			}
			if (ch === "\\") switch (json[i + 1]) {
				case "u":
					{
						str += json.slice(start, i);
						const code = json.substr(i + 2, 4);
						switch (code) {
							case "0000":
								str += "\\0";
								break;
							case "0007":
								str += "\\a";
								break;
							case "000b":
								str += "\\v";
								break;
							case "001b":
								str += "\\e";
								break;
							case "0085":
								str += "\\N";
								break;
							case "00a0":
								str += "\\_";
								break;
							case "2028":
								str += "\\L";
								break;
							case "2029":
								str += "\\P";
								break;
							default: if (code.substr(0, 2) === "00") str += "\\x" + code.substr(2);
							else str += json.substr(i, 6);
						}
						i += 5;
						start = i + 1;
					}
					break;
				case "n":
					if (implicitKey || json[i + 2] === "\"" || json.length < minMultiLineLength) i += 1;
					else {
						str += json.slice(start, i) + "\n\n";
						while (json[i + 2] === "\\" && json[i + 3] === "n" && json[i + 4] !== "\"") {
							str += "\n";
							i += 2;
						}
						str += indent;
						if (json[i + 2] === " ") str += "\\";
						i += 1;
						start = i + 1;
					}
					break;
				default: i += 1;
			}
		}
		str = start ? str + json.slice(start) : json;
		return implicitKey ? str : foldFlowLines.foldFlowLines(str, indent, foldFlowLines.FOLD_QUOTED, getFoldOptions(ctx, false));
	}
	function singleQuotedString(value, ctx) {
		if (ctx.options.singleQuote === false || ctx.implicitKey && value.includes("\n") || /[ \t]\n|\n[ \t]/.test(value)) return doubleQuotedString(value, ctx);
		const indent = ctx.indent || (containsDocumentMarker(value) ? "  " : "");
		const res = "'" + value.replace(/'/g, "''").replace(/\n+/g, `$&\n${indent}`) + "'";
		return ctx.implicitKey ? res : foldFlowLines.foldFlowLines(res, indent, foldFlowLines.FOLD_FLOW, getFoldOptions(ctx, false));
	}
	function quotedString(value, ctx) {
		const { singleQuote } = ctx.options;
		let qs;
		if (singleQuote === false) qs = doubleQuotedString;
		else {
			const hasDouble = value.includes("\"");
			const hasSingle = value.includes("'");
			if (hasDouble && !hasSingle) qs = singleQuotedString;
			else if (hasSingle && !hasDouble) qs = doubleQuotedString;
			else qs = singleQuote ? singleQuotedString : doubleQuotedString;
		}
		return qs(value, ctx);
	}
	let blockEndNewlines;
	try {
		blockEndNewlines = /* @__PURE__ */ new RegExp("(^|(?<!\n))\n+(?!\n|$)", "g");
	} catch {
		blockEndNewlines = /\n+(?!\n|$)/g;
	}
	function blockString({ comment, type, value }, ctx, onComment, onChompKeep) {
		const { blockQuote, commentString, lineWidth } = ctx.options;
		if (!blockQuote || /\n[\t ]+$/.test(value)) return quotedString(value, ctx);
		const indent = ctx.indent || (ctx.forceBlockIndent || containsDocumentMarker(value) ? "  " : "");
		const literal = blockQuote === "literal" ? true : blockQuote === "folded" || type === Scalar.Scalar.BLOCK_FOLDED ? false : type === Scalar.Scalar.BLOCK_LITERAL ? true : !lineLengthOverLimit(value, lineWidth, indent.length);
		if (!value) return literal ? "|\n" : ">\n";
		let chomp;
		let endStart;
		for (endStart = value.length; endStart > 0; --endStart) {
			const ch = value[endStart - 1];
			if (ch !== "\n" && ch !== "	" && ch !== " ") break;
		}
		let end = value.substring(endStart);
		const endNlPos = end.indexOf("\n");
		if (endNlPos === -1) chomp = "-";
		else if (value === end || endNlPos !== end.length - 1) {
			chomp = "+";
			if (onChompKeep) onChompKeep();
		} else chomp = "";
		if (end) {
			value = value.slice(0, -end.length);
			if (end[end.length - 1] === "\n") end = end.slice(0, -1);
			end = end.replace(blockEndNewlines, `$&${indent}`);
		}
		let startWithSpace = false;
		let startEnd;
		let startNlPos = -1;
		for (startEnd = 0; startEnd < value.length; ++startEnd) {
			const ch = value[startEnd];
			if (ch === " ") startWithSpace = true;
			else if (ch === "\n") startNlPos = startEnd;
			else break;
		}
		let start = value.substring(0, startNlPos < startEnd ? startNlPos + 1 : startEnd);
		if (start) {
			value = value.substring(start.length);
			start = start.replace(/\n+/g, `$&${indent}`);
		}
		let header = (startWithSpace ? indent ? "2" : "1" : "") + chomp;
		if (comment) {
			header += " " + commentString(comment.replace(/ ?[\r\n]+/g, " "));
			if (onComment) onComment();
		}
		if (!literal) {
			const foldedValue = value.replace(/\n+/g, "\n$&").replace(/(?:^|\n)([\t ].*)(?:([\n\t ]*)\n(?![\n\t ]))?/g, "$1$2").replace(/\n+/g, `$&${indent}`);
			let literalFallback = false;
			const foldOptions = getFoldOptions(ctx, true);
			if (blockQuote !== "folded" && type !== Scalar.Scalar.BLOCK_FOLDED) foldOptions.onOverflow = () => {
				literalFallback = true;
			};
			const body = foldFlowLines.foldFlowLines(`${start}${foldedValue}${end}`, indent, foldFlowLines.FOLD_BLOCK, foldOptions);
			if (!literalFallback) return `>${header}\n${indent}${body}`;
		}
		value = value.replace(/\n+/g, `$&${indent}`);
		return `|${header}\n${indent}${start}${value}${end}`;
	}
	function plainString(item, ctx, onComment, onChompKeep) {
		const { type, value } = item;
		const { actualString, implicitKey, indent, indentStep, inFlow } = ctx;
		if (implicitKey && value.includes("\n") || inFlow && /[[\]{},]/.test(value)) return quotedString(value, ctx);
		if (/^[\n\t ,[\]{}#&*!|>'"%@`]|^[?-]$|^[?-][ \t]|[\n:][ \t]|[ \t]\n|[\n\t ]#|[\n\t :]$/.test(value)) return implicitKey || inFlow || !value.includes("\n") ? quotedString(value, ctx) : blockString(item, ctx, onComment, onChompKeep);
		if (!implicitKey && !inFlow && type !== Scalar.Scalar.PLAIN && value.includes("\n")) return blockString(item, ctx, onComment, onChompKeep);
		if (containsDocumentMarker(value)) {
			if (indent === "") {
				ctx.forceBlockIndent = true;
				return blockString(item, ctx, onComment, onChompKeep);
			} else if (implicitKey && indent === indentStep) return quotedString(value, ctx);
		}
		const str = value.replace(/\n+/g, `$&\n${indent}`);
		if (actualString) {
			const test = (tag) => tag.default && tag.tag !== "tag:yaml.org,2002:str" && tag.test?.test(str);
			const { compat, tags } = ctx.doc.schema;
			if (tags.some(test) || compat?.some(test)) return quotedString(value, ctx);
		}
		return implicitKey ? str : foldFlowLines.foldFlowLines(str, indent, foldFlowLines.FOLD_FLOW, getFoldOptions(ctx, false));
	}
	function stringifyString(item, ctx, onComment, onChompKeep) {
		const { implicitKey, inFlow } = ctx;
		const ss = typeof item.value === "string" ? item : Object.assign({}, item, { value: String(item.value) });
		let { type } = item;
		if (type !== Scalar.Scalar.QUOTE_DOUBLE) {
			if (/[\x00-\x08\x0b-\x1f\x7f-\x9f\u{D800}-\u{DFFF}]/u.test(ss.value)) type = Scalar.Scalar.QUOTE_DOUBLE;
		}
		const _stringify = (_type) => {
			switch (_type) {
				case Scalar.Scalar.BLOCK_FOLDED:
				case Scalar.Scalar.BLOCK_LITERAL: return implicitKey || inFlow ? quotedString(ss.value, ctx) : blockString(ss, ctx, onComment, onChompKeep);
				case Scalar.Scalar.QUOTE_DOUBLE: return doubleQuotedString(ss.value, ctx);
				case Scalar.Scalar.QUOTE_SINGLE: return singleQuotedString(ss.value, ctx);
				case Scalar.Scalar.PLAIN: return plainString(ss, ctx, onComment, onChompKeep);
				default: return null;
			}
		};
		let res = _stringify(type);
		if (res === null) {
			const { defaultKeyType, defaultStringType } = ctx.options;
			const t = implicitKey && defaultKeyType || defaultStringType;
			res = _stringify(t);
			if (res === null) throw new Error(`Unsupported default string type ${t}`);
		}
		return res;
	}
	exports.stringifyString = stringifyString;
}));
//#endregion
//#region node_modules/.pnpm/yaml@2.9.1/node_modules/yaml/dist/stringify/stringify.js
var require_stringify = /* @__PURE__ */ __commonJSMin(((exports) => {
	var anchors = require_anchors();
	var identity = require_identity();
	var stringifyComment = require_stringifyComment();
	var stringifyString = require_stringifyString();
	function createStringifyContext(doc, options) {
		const opt = Object.assign({
			blockQuote: true,
			commentString: stringifyComment.stringifyComment,
			defaultKeyType: null,
			defaultStringType: "PLAIN",
			directives: null,
			doubleQuotedAsJSON: false,
			doubleQuotedMinMultiLineLength: 40,
			falseStr: "false",
			flowCollectionPadding: true,
			indentSeq: true,
			lineWidth: 80,
			minContentWidth: 20,
			nullStr: "null",
			simpleKeys: false,
			singleQuote: null,
			trailingComma: false,
			trueStr: "true",
			verifyAliasOrder: true
		}, doc.schema.toStringOptions, options);
		let inFlow;
		switch (opt.collectionStyle) {
			case "block":
				inFlow = false;
				break;
			case "flow":
				inFlow = true;
				break;
			default: inFlow = null;
		}
		return {
			anchors: /* @__PURE__ */ new Set(),
			doc,
			flowCollectionPadding: opt.flowCollectionPadding ? " " : "",
			indent: "",
			indentStep: typeof opt.indent === "number" ? " ".repeat(opt.indent) : "  ",
			inFlow,
			options: opt
		};
	}
	function getTagObject(tags, item) {
		if (item.tag) {
			const match = tags.filter((t) => t.tag === item.tag);
			if (match.length > 0) return match.find((t) => t.format === item.format) ?? match[0];
		}
		let tagObj = void 0;
		let obj;
		if (identity.isScalar(item)) {
			obj = item.value;
			let match = tags.filter((t) => t.identify?.(obj));
			if (match.length > 1) {
				const testMatch = match.filter((t) => t.test);
				if (testMatch.length > 0) match = testMatch;
			}
			tagObj = match.find((t) => t.format === item.format) ?? match.find((t) => !t.format);
		} else {
			obj = item;
			tagObj = tags.find((t) => t.nodeClass && obj instanceof t.nodeClass);
		}
		if (!tagObj) {
			const name = obj?.constructor?.name ?? (obj === null ? "null" : typeof obj);
			throw new Error(`Tag not resolved for ${name} value`);
		}
		return tagObj;
	}
	function stringifyProps(node, tagObj, { anchors: anchors$1, doc }) {
		if (!doc.directives) return "";
		const props = [];
		const anchor = (identity.isScalar(node) || identity.isCollection(node)) && node.anchor;
		if (anchor && anchors.anchorIsValid(anchor)) {
			anchors$1.add(anchor);
			props.push(`&${anchor}`);
		}
		const tag = node.tag ?? (tagObj.default ? null : tagObj.tag);
		if (tag) props.push(doc.directives.tagString(tag));
		return props.join(" ");
	}
	function stringify(item, ctx, onComment, onChompKeep) {
		if (identity.isPair(item)) return item.toString(ctx, onComment, onChompKeep);
		if (identity.isAlias(item)) {
			if (ctx.doc.directives) return item.toString(ctx);
			if (ctx.resolvedAliases?.has(item)) throw new TypeError(`Cannot stringify circular structure without alias nodes`);
			else {
				if (ctx.resolvedAliases) ctx.resolvedAliases.add(item);
				else ctx.resolvedAliases = /* @__PURE__ */ new Set([item]);
				item = item.resolve(ctx.doc);
			}
		}
		let tagObj = void 0;
		const node = identity.isNode(item) ? item : ctx.doc.createNode(item, { onTagObj: (o) => tagObj = o });
		tagObj ?? (tagObj = getTagObject(ctx.doc.schema.tags, node));
		const props = stringifyProps(node, tagObj, ctx);
		if (props.length > 0) ctx.indentAtStart = (ctx.indentAtStart ?? 0) + props.length + 1;
		const str = typeof tagObj.stringify === "function" ? tagObj.stringify(node, ctx, onComment, onChompKeep) : identity.isScalar(node) ? stringifyString.stringifyString(node, ctx, onComment, onChompKeep) : node.toString(ctx, onComment, onChompKeep);
		if (!props) return str;
		return identity.isScalar(node) || str[0] === "{" || str[0] === "[" ? `${props} ${str}` : `${props}\n${ctx.indent}${str}`;
	}
	exports.createStringifyContext = createStringifyContext;
	exports.stringify = stringify;
}));
//#endregion
//#region node_modules/.pnpm/yaml@2.9.1/node_modules/yaml/dist/stringify/stringifyPair.js
var require_stringifyPair = /* @__PURE__ */ __commonJSMin(((exports) => {
	var identity = require_identity();
	var Scalar = require_Scalar();
	var stringify = require_stringify();
	var stringifyComment = require_stringifyComment();
	function stringifyPair({ key, value }, ctx, onComment, onChompKeep) {
		const { allNullValues, doc, indent, indentStep, options: { commentString, indentSeq, simpleKeys } } = ctx;
		let keyComment = identity.isNode(key) && key.comment || null;
		if (simpleKeys) {
			if (keyComment) throw new Error("With simple keys, key nodes cannot have comments");
			if (identity.isCollection(key) || !identity.isNode(key) && typeof key === "object") throw new Error("With simple keys, collection cannot be used as a key value");
		}
		let explicitKey = !simpleKeys && (!key || keyComment && value == null && !ctx.inFlow || identity.isCollection(key) || (identity.isScalar(key) ? key.type === Scalar.Scalar.BLOCK_FOLDED || key.type === Scalar.Scalar.BLOCK_LITERAL : typeof key === "object"));
		ctx = Object.assign({}, ctx, {
			allNullValues: false,
			implicitKey: !explicitKey && (simpleKeys || !allNullValues),
			indent: indent + indentStep
		});
		let keyCommentDone = false;
		let chompKeep = false;
		let str = stringify.stringify(key, ctx, () => keyCommentDone = true, () => chompKeep = true);
		if (!explicitKey && !ctx.inFlow && str.length > 1024) {
			if (simpleKeys) throw new Error("With simple keys, single line scalar must not span more than 1024 characters");
			explicitKey = true;
		}
		if (ctx.inFlow) {
			if (allNullValues || value == null) {
				if (keyCommentDone && onComment) onComment();
				return str === "" ? "?" : explicitKey ? `? ${str}` : str;
			}
		} else if (allNullValues && !simpleKeys || value == null && explicitKey) {
			str = `? ${str}`;
			if (keyComment && !keyCommentDone) str += stringifyComment.lineComment(str, ctx.indent, commentString(keyComment));
			else if (chompKeep && onChompKeep) onChompKeep();
			return str;
		}
		if (keyCommentDone) keyComment = null;
		if (explicitKey) {
			if (keyComment) str += stringifyComment.lineComment(str, ctx.indent, commentString(keyComment));
			str = `? ${str}\n${indent}:`;
		} else {
			str = `${str}:`;
			if (keyComment) str += stringifyComment.lineComment(str, ctx.indent, commentString(keyComment));
		}
		let vsb, vcb, valueComment;
		if (identity.isNode(value)) {
			vsb = !!value.spaceBefore;
			vcb = value.commentBefore;
			valueComment = value.comment;
		} else {
			vsb = false;
			vcb = null;
			valueComment = null;
			if (value && typeof value === "object") value = doc.createNode(value);
		}
		ctx.implicitKey = false;
		if (!explicitKey && !keyComment && identity.isScalar(value)) ctx.indentAtStart = str.length + 1;
		chompKeep = false;
		if (!indentSeq && indentStep.length >= 2 && !ctx.inFlow && !explicitKey && identity.isSeq(value) && !value.flow && !value.tag && !value.anchor) ctx.indent = ctx.indent.substring(2);
		let valueCommentDone = false;
		const valueStr = stringify.stringify(value, ctx, () => valueCommentDone = true, () => chompKeep = true);
		let ws = " ";
		if (keyComment || vsb || vcb) {
			ws = vsb ? "\n" : "";
			if (vcb) {
				const cs = commentString(vcb);
				ws += `\n${stringifyComment.indentComment(cs, ctx.indent)}`;
			}
			if (valueStr === "" && !ctx.inFlow) {
				if (ws === "\n" && valueComment) ws = "\n\n";
			} else ws += `\n${ctx.indent}`;
		} else if (!explicitKey && identity.isCollection(value)) {
			const vs0 = valueStr[0];
			const nl0 = valueStr.indexOf("\n");
			const hasNewline = nl0 !== -1;
			const flow = ctx.inFlow ?? value.flow ?? value.items.length === 0;
			if (hasNewline || !flow) {
				let hasPropsLine = false;
				if (hasNewline && (vs0 === "&" || vs0 === "!")) {
					let sp0 = valueStr.indexOf(" ");
					if (vs0 === "&" && sp0 !== -1 && sp0 < nl0 && valueStr[sp0 + 1] === "!") sp0 = valueStr.indexOf(" ", sp0 + 1);
					if (sp0 === -1 || nl0 < sp0) hasPropsLine = true;
				}
				if (!hasPropsLine) ws = `\n${ctx.indent}`;
			}
		} else if (valueStr === "" || valueStr[0] === "\n") ws = "";
		str += ws + valueStr;
		if (ctx.inFlow) {
			if (valueCommentDone && onComment) onComment();
		} else if (valueComment && !valueCommentDone) str += stringifyComment.lineComment(str, ctx.indent, commentString(valueComment));
		else if (chompKeep && onChompKeep) onChompKeep();
		return str;
	}
	exports.stringifyPair = stringifyPair;
}));
//#endregion
//#region node_modules/.pnpm/yaml@2.9.1/node_modules/yaml/dist/log.js
var require_log = /* @__PURE__ */ __commonJSMin(((exports) => {
	var node_process$2 = __require("process");
	function debug(logLevel, ...messages) {
		if (logLevel === "debug") console.log(...messages);
	}
	function warn(logLevel, warning) {
		if (logLevel === "debug" || logLevel === "warn") {
			if (typeof node_process$2.emitWarning === "function") node_process$2.emitWarning(warning);
			else console.warn(warning);
		}
	}
	exports.debug = debug;
	exports.warn = warn;
}));
//#endregion
//#region node_modules/.pnpm/yaml@2.9.1/node_modules/yaml/dist/schema/yaml-1.1/merge.js
var require_merge = /* @__PURE__ */ __commonJSMin(((exports) => {
	var identity = require_identity();
	var Scalar = require_Scalar();
	const MERGE_KEY = "<<";
	const merge = {
		identify: (value) => value === MERGE_KEY || typeof value === "symbol" && value.description === MERGE_KEY,
		default: "key",
		tag: "tag:yaml.org,2002:merge",
		test: /^<<$/,
		resolve: () => Object.assign(new Scalar.Scalar(Symbol(MERGE_KEY)), { addToJSMap: addMergeToJSMap }),
		stringify: () => MERGE_KEY
	};
	const isMergeKey = (ctx, key) => (merge.identify(key) || identity.isScalar(key) && (!key.type || key.type === Scalar.Scalar.PLAIN) && merge.identify(key.value)) && ctx?.doc.schema.tags.some((tag) => tag.tag === merge.tag && tag.default);
	function addMergeToJSMap(ctx, map, value) {
		const source = resolveAliasValue(ctx, value);
		if (identity.isSeq(source)) for (const it of source.items) mergeValue(ctx, map, it);
		else if (Array.isArray(source)) for (const it of source) mergeValue(ctx, map, it);
		else mergeValue(ctx, map, source);
	}
	function mergeValue(ctx, map, value) {
		const source = resolveAliasValue(ctx, value);
		if (!identity.isMap(source)) throw new Error("Merge sources must be maps or map aliases");
		const srcMap = source.toJSON(null, ctx, Map);
		for (const [key, value] of srcMap) if (map instanceof Map) {
			if (!map.has(key)) map.set(key, value);
		} else if (map instanceof Set) map.add(key);
		else if (!Object.prototype.hasOwnProperty.call(map, key)) Object.defineProperty(map, key, {
			value,
			writable: true,
			enumerable: true,
			configurable: true
		});
		return map;
	}
	function resolveAliasValue(ctx, value) {
		return ctx && identity.isAlias(value) ? value.resolve(ctx.doc, ctx) : value;
	}
	exports.addMergeToJSMap = addMergeToJSMap;
	exports.isMergeKey = isMergeKey;
	exports.merge = merge;
}));
//#endregion
//#region node_modules/.pnpm/yaml@2.9.1/node_modules/yaml/dist/nodes/addPairToJSMap.js
var require_addPairToJSMap = /* @__PURE__ */ __commonJSMin(((exports) => {
	var log = require_log();
	var merge = require_merge();
	var stringify = require_stringify();
	var identity = require_identity();
	var toJS = require_toJS();
	function addPairToJSMap(ctx, map, { key, value }) {
		if (identity.isNode(key) && key.addToJSMap) key.addToJSMap(ctx, map, value);
		else if (merge.isMergeKey(ctx, key)) merge.addMergeToJSMap(ctx, map, value);
		else {
			const jsKey = toJS.toJS(key, "", ctx);
			if (map instanceof Map) map.set(jsKey, toJS.toJS(value, jsKey, ctx));
			else if (map instanceof Set) map.add(jsKey);
			else {
				const stringKey = stringifyKey(key, jsKey, ctx);
				const jsValue = toJS.toJS(value, stringKey, ctx);
				if (stringKey in map) Object.defineProperty(map, stringKey, {
					value: jsValue,
					writable: true,
					enumerable: true,
					configurable: true
				});
				else map[stringKey] = jsValue;
			}
		}
		return map;
	}
	function stringifyKey(key, jsKey, ctx) {
		if (jsKey === null) return "";
		if (typeof jsKey !== "object") return String(jsKey);
		if (identity.isNode(key) && ctx?.doc) {
			const strCtx = stringify.createStringifyContext(ctx.doc, {});
			strCtx.anchors = /* @__PURE__ */ new Set();
			for (const node of ctx.anchors.keys()) strCtx.anchors.add(node.anchor);
			strCtx.inFlow = true;
			strCtx.inStringifyKey = true;
			const strKey = key.toString(strCtx);
			if (!ctx.mapKeyWarned) {
				let jsonStr = JSON.stringify(strKey);
				if (jsonStr.length > 40) jsonStr = jsonStr.substring(0, 36) + "...\"";
				log.warn(ctx.doc.options.logLevel, `Keys with collection values will be stringified due to JS Object restrictions: ${jsonStr}. Set mapAsMap: true to use object keys.`);
				ctx.mapKeyWarned = true;
			}
			return strKey;
		}
		return JSON.stringify(jsKey);
	}
	exports.addPairToJSMap = addPairToJSMap;
}));
//#endregion
//#region node_modules/.pnpm/yaml@2.9.1/node_modules/yaml/dist/nodes/Pair.js
var require_Pair = /* @__PURE__ */ __commonJSMin(((exports) => {
	var createNode = require_createNode();
	var stringifyPair = require_stringifyPair();
	var addPairToJSMap = require_addPairToJSMap();
	var identity = require_identity();
	function createPair(key, value, ctx) {
		return new Pair(createNode.createNode(key, void 0, ctx), createNode.createNode(value, void 0, ctx));
	}
	var Pair = class Pair {
		constructor(key, value = null) {
			Object.defineProperty(this, identity.NODE_TYPE, { value: identity.PAIR });
			this.key = key;
			this.value = value;
		}
		clone(schema) {
			let { key, value } = this;
			if (identity.isNode(key)) key = key.clone(schema);
			if (identity.isNode(value)) value = value.clone(schema);
			return new Pair(key, value);
		}
		toJSON(_, ctx) {
			const pair = ctx?.mapAsMap ? /* @__PURE__ */ new Map() : {};
			return addPairToJSMap.addPairToJSMap(ctx, pair, this);
		}
		toString(ctx, onComment, onChompKeep) {
			return ctx?.doc ? stringifyPair.stringifyPair(this, ctx, onComment, onChompKeep) : JSON.stringify(this);
		}
	};
	exports.Pair = Pair;
	exports.createPair = createPair;
}));
//#endregion
//#region node_modules/.pnpm/yaml@2.9.1/node_modules/yaml/dist/stringify/stringifyCollection.js
var require_stringifyCollection = /* @__PURE__ */ __commonJSMin(((exports) => {
	var identity = require_identity();
	var stringify = require_stringify();
	var stringifyComment = require_stringifyComment();
	function stringifyCollection(collection, ctx, options) {
		return (ctx.inFlow ?? collection.flow ? stringifyFlowCollection : stringifyBlockCollection)(collection, ctx, options);
	}
	function stringifyBlockCollection({ comment, items }, ctx, { blockItemPrefix, flowChars, itemIndent, onChompKeep, onComment }) {
		const { indent, options: { commentString } } = ctx;
		const itemCtx = Object.assign({}, ctx, {
			indent: itemIndent,
			type: null
		});
		let chompKeep = false;
		const lines = [];
		for (let i = 0; i < items.length; ++i) {
			const item = items[i];
			let comment = null;
			if (identity.isNode(item)) {
				if (!chompKeep && item.spaceBefore) lines.push("");
				addCommentBefore(ctx, lines, item.commentBefore, chompKeep);
				if (item.comment) comment = item.comment;
			} else if (identity.isPair(item)) {
				const ik = identity.isNode(item.key) ? item.key : null;
				if (ik) {
					if (!chompKeep && ik.spaceBefore) lines.push("");
					addCommentBefore(ctx, lines, ik.commentBefore, chompKeep);
				}
			}
			chompKeep = false;
			let str = stringify.stringify(item, itemCtx, () => comment = null, () => chompKeep = true);
			if (comment) str += stringifyComment.lineComment(str, itemIndent, commentString(comment));
			if (chompKeep && comment) chompKeep = false;
			lines.push(blockItemPrefix + str);
		}
		let str;
		if (lines.length === 0) str = flowChars.start + flowChars.end;
		else {
			str = lines[0];
			for (let i = 1; i < lines.length; ++i) {
				const line = lines[i];
				str += line ? `\n${indent}${line}` : "\n";
			}
		}
		if (comment) {
			str += "\n" + stringifyComment.indentComment(commentString(comment), indent);
			if (onComment) onComment();
		} else if (chompKeep && onChompKeep) onChompKeep();
		return str;
	}
	function stringifyFlowCollection({ items }, ctx, { flowChars, itemIndent }) {
		const { indent, indentStep, flowCollectionPadding: fcPadding, options: { commentString } } = ctx;
		itemIndent += indentStep;
		const itemCtx = Object.assign({}, ctx, {
			indent: itemIndent,
			inFlow: true,
			type: null
		});
		let reqNewline = false;
		let linesAtValue = 0;
		const lines = [];
		for (let i = 0; i < items.length; ++i) {
			const item = items[i];
			let comment = null;
			if (identity.isNode(item)) {
				if (item.spaceBefore) lines.push("");
				addCommentBefore(ctx, lines, item.commentBefore, false);
				if (item.comment) comment = item.comment;
			} else if (identity.isPair(item)) {
				const ik = identity.isNode(item.key) ? item.key : null;
				if (ik) {
					if (ik.spaceBefore) lines.push("");
					addCommentBefore(ctx, lines, ik.commentBefore, false);
					if (ik.comment) reqNewline = true;
				}
				const iv = identity.isNode(item.value) ? item.value : null;
				if (iv) {
					if (iv.comment) comment = iv.comment;
					if (iv.commentBefore) reqNewline = true;
				} else if (item.value == null && ik?.comment) comment = ik.comment;
			}
			if (comment) reqNewline = true;
			let str = stringify.stringify(item, itemCtx, () => comment = null);
			reqNewline || (reqNewline = lines.length > linesAtValue || str.includes("\n"));
			if (i < items.length - 1) str += ",";
			else if (ctx.options.trailingComma) {
				if (ctx.options.lineWidth > 0) reqNewline || (reqNewline = lines.reduce((sum, line) => sum + line.length + 2, 2) + (str.length + 2) > ctx.options.lineWidth);
				if (reqNewline) str += ",";
			}
			if (comment) str += stringifyComment.lineComment(str, itemIndent, commentString(comment));
			lines.push(str);
			linesAtValue = lines.length;
		}
		const { start, end } = flowChars;
		if (lines.length === 0) return start + end;
		else {
			if (!reqNewline) {
				const len = lines.reduce((sum, line) => sum + line.length + 2, 2);
				reqNewline = ctx.options.lineWidth > 0 && len > ctx.options.lineWidth;
			}
			if (reqNewline) {
				let str = start;
				for (const line of lines) str += line ? `\n${indentStep}${indent}${line}` : "\n";
				return `${str}\n${indent}${end}`;
			} else return `${start}${fcPadding}${lines.join(" ")}${fcPadding}${end}`;
		}
	}
	function addCommentBefore({ indent, options: { commentString } }, lines, comment, chompKeep) {
		if (comment && chompKeep) comment = comment.replace(/^\n+/, "");
		if (comment) {
			const ic = stringifyComment.indentComment(commentString(comment), indent);
			lines.push(ic.trimStart());
		}
	}
	exports.stringifyCollection = stringifyCollection;
}));
//#endregion
//#region node_modules/.pnpm/yaml@2.9.1/node_modules/yaml/dist/nodes/YAMLMap.js
var require_YAMLMap = /* @__PURE__ */ __commonJSMin(((exports) => {
	var stringifyCollection = require_stringifyCollection();
	var addPairToJSMap = require_addPairToJSMap();
	var Collection = require_Collection();
	var identity = require_identity();
	var Pair = require_Pair();
	var Scalar = require_Scalar();
	function findPair(items, key) {
		const k = identity.isScalar(key) ? key.value : key;
		for (const it of items) if (identity.isPair(it)) {
			if (it.key === key || it.key === k) return it;
			if (identity.isScalar(it.key) && it.key.value === k) return it;
		}
	}
	var YAMLMap = class extends Collection.Collection {
		static get tagName() {
			return "tag:yaml.org,2002:map";
		}
		constructor(schema) {
			super(identity.MAP, schema);
			this.items = [];
		}
		/**
		* A generic collection parsing method that can be extended
		* to other node classes that inherit from YAMLMap
		*/
		static from(schema, obj, ctx) {
			const { keepUndefined, replacer } = ctx;
			const map = new this(schema);
			const add = (key, value) => {
				if (typeof replacer === "function") value = replacer.call(obj, key, value);
				else if (Array.isArray(replacer) && !replacer.includes(key)) return;
				if (value !== void 0 || keepUndefined) map.items.push(Pair.createPair(key, value, ctx));
			};
			if (obj instanceof Map) for (const [key, value] of obj) add(key, value);
			else if (obj && typeof obj === "object") for (const key of Object.keys(obj)) add(key, obj[key]);
			if (typeof schema.sortMapEntries === "function") map.items.sort(schema.sortMapEntries);
			return map;
		}
		/**
		* Adds a value to the collection.
		*
		* @param overwrite - If not set `true`, using a key that is already in the
		*   collection will throw. Otherwise, overwrites the previous value.
		*/
		add(pair, overwrite) {
			let _pair;
			if (identity.isPair(pair)) _pair = pair;
			else if (!pair || typeof pair !== "object" || !("key" in pair)) _pair = new Pair.Pair(pair, pair?.value);
			else _pair = new Pair.Pair(pair.key, pair.value);
			const prev = findPair(this.items, _pair.key);
			const sortEntries = this.schema?.sortMapEntries;
			if (prev) {
				if (!overwrite) throw new Error(`Key ${_pair.key} already set`);
				if (identity.isScalar(prev.value) && Scalar.isScalarValue(_pair.value)) prev.value.value = _pair.value;
				else prev.value = _pair.value;
			} else if (sortEntries) {
				const i = this.items.findIndex((item) => sortEntries(_pair, item) < 0);
				if (i === -1) this.items.push(_pair);
				else this.items.splice(i, 0, _pair);
			} else this.items.push(_pair);
		}
		delete(key) {
			const it = findPair(this.items, key);
			if (!it) return false;
			return this.items.splice(this.items.indexOf(it), 1).length > 0;
		}
		get(key, keepScalar) {
			const node = findPair(this.items, key)?.value;
			return (!keepScalar && identity.isScalar(node) ? node.value : node) ?? void 0;
		}
		has(key) {
			return !!findPair(this.items, key);
		}
		set(key, value) {
			this.add(new Pair.Pair(key, value), true);
		}
		/**
		* @param ctx - Conversion context, originally set in Document#toJS()
		* @param {Class} Type - If set, forces the returned collection type
		* @returns Instance of Type, Map, or Object
		*/
		toJSON(_, ctx, Type) {
			const map = Type ? new Type() : ctx?.mapAsMap ? /* @__PURE__ */ new Map() : {};
			if (ctx?.onCreate) ctx.onCreate(map);
			for (const item of this.items) addPairToJSMap.addPairToJSMap(ctx, map, item);
			return map;
		}
		toString(ctx, onComment, onChompKeep) {
			if (!ctx) return JSON.stringify(this);
			for (const item of this.items) if (!identity.isPair(item)) throw new Error(`Map items must all be pairs; found ${JSON.stringify(item)} instead`);
			if (!ctx.allNullValues && this.hasAllNullValues(false)) ctx = Object.assign({}, ctx, { allNullValues: true });
			return stringifyCollection.stringifyCollection(this, ctx, {
				blockItemPrefix: "",
				flowChars: {
					start: "{",
					end: "}"
				},
				itemIndent: ctx.indent || "",
				onChompKeep,
				onComment
			});
		}
	};
	exports.YAMLMap = YAMLMap;
	exports.findPair = findPair;
}));
//#endregion
//#region node_modules/.pnpm/yaml@2.9.1/node_modules/yaml/dist/schema/common/map.js
var require_map = /* @__PURE__ */ __commonJSMin(((exports) => {
	var identity = require_identity();
	var YAMLMap = require_YAMLMap();
	exports.map = {
		collection: "map",
		default: true,
		nodeClass: YAMLMap.YAMLMap,
		tag: "tag:yaml.org,2002:map",
		resolve(map, onError) {
			if (!identity.isMap(map)) onError("Expected a mapping for this tag");
			return map;
		},
		createNode: (schema, obj, ctx) => YAMLMap.YAMLMap.from(schema, obj, ctx)
	};
}));
//#endregion
//#region node_modules/.pnpm/yaml@2.9.1/node_modules/yaml/dist/nodes/YAMLSeq.js
var require_YAMLSeq = /* @__PURE__ */ __commonJSMin(((exports) => {
	var createNode = require_createNode();
	var stringifyCollection = require_stringifyCollection();
	var Collection = require_Collection();
	var identity = require_identity();
	var Scalar = require_Scalar();
	var toJS = require_toJS();
	var YAMLSeq = class extends Collection.Collection {
		static get tagName() {
			return "tag:yaml.org,2002:seq";
		}
		constructor(schema) {
			super(identity.SEQ, schema);
			this.items = [];
		}
		add(value) {
			this.items.push(value);
		}
		/**
		* Removes a value from the collection.
		*
		* `key` must contain a representation of an integer for this to succeed.
		* It may be wrapped in a `Scalar`.
		*
		* @returns `true` if the item was found and removed.
		*/
		delete(key) {
			const idx = asItemIndex(key);
			if (typeof idx !== "number") return false;
			return this.items.splice(idx, 1).length > 0;
		}
		get(key, keepScalar) {
			const idx = asItemIndex(key);
			if (typeof idx !== "number") return void 0;
			const it = this.items[idx];
			return !keepScalar && identity.isScalar(it) ? it.value : it;
		}
		/**
		* Checks if the collection includes a value with the key `key`.
		*
		* `key` must contain a representation of an integer for this to succeed.
		* It may be wrapped in a `Scalar`.
		*/
		has(key) {
			const idx = asItemIndex(key);
			return typeof idx === "number" && idx < this.items.length;
		}
		/**
		* Sets a value in this collection. For `!!set`, `value` needs to be a
		* boolean to add/remove the item from the set.
		*
		* If `key` does not contain a representation of an integer, this will throw.
		* It may be wrapped in a `Scalar`.
		*/
		set(key, value) {
			const idx = asItemIndex(key);
			if (typeof idx !== "number") throw new Error(`Expected a valid index, not ${key}.`);
			const prev = this.items[idx];
			if (identity.isScalar(prev) && Scalar.isScalarValue(value)) prev.value = value;
			else this.items[idx] = value;
		}
		toJSON(_, ctx) {
			const seq = [];
			if (ctx?.onCreate) ctx.onCreate(seq);
			let i = 0;
			for (const item of this.items) seq.push(toJS.toJS(item, String(i++), ctx));
			return seq;
		}
		toString(ctx, onComment, onChompKeep) {
			if (!ctx) return JSON.stringify(this);
			return stringifyCollection.stringifyCollection(this, ctx, {
				blockItemPrefix: "- ",
				flowChars: {
					start: "[",
					end: "]"
				},
				itemIndent: (ctx.indent || "") + "  ",
				onChompKeep,
				onComment
			});
		}
		static from(schema, obj, ctx) {
			const { replacer } = ctx;
			const seq = new this(schema);
			if (obj && Symbol.iterator in Object(obj)) {
				let i = 0;
				for (let it of obj) {
					if (typeof replacer === "function") {
						const key = obj instanceof Set ? it : String(i++);
						it = replacer.call(obj, key, it);
					}
					seq.items.push(createNode.createNode(it, void 0, ctx));
				}
			}
			return seq;
		}
	};
	function asItemIndex(key) {
		let idx = identity.isScalar(key) ? key.value : key;
		if (idx && typeof idx === "string") idx = Number(idx);
		return typeof idx === "number" && Number.isInteger(idx) && idx >= 0 ? idx : null;
	}
	exports.YAMLSeq = YAMLSeq;
}));
//#endregion
//#region node_modules/.pnpm/yaml@2.9.1/node_modules/yaml/dist/schema/common/seq.js
var require_seq = /* @__PURE__ */ __commonJSMin(((exports) => {
	var identity = require_identity();
	var YAMLSeq = require_YAMLSeq();
	exports.seq = {
		collection: "seq",
		default: true,
		nodeClass: YAMLSeq.YAMLSeq,
		tag: "tag:yaml.org,2002:seq",
		resolve(seq, onError) {
			if (!identity.isSeq(seq)) onError("Expected a sequence for this tag");
			return seq;
		},
		createNode: (schema, obj, ctx) => YAMLSeq.YAMLSeq.from(schema, obj, ctx)
	};
}));
//#endregion
//#region node_modules/.pnpm/yaml@2.9.1/node_modules/yaml/dist/schema/common/string.js
var require_string = /* @__PURE__ */ __commonJSMin(((exports) => {
	var stringifyString = require_stringifyString();
	exports.string = {
		identify: (value) => typeof value === "string",
		default: true,
		tag: "tag:yaml.org,2002:str",
		resolve: (str) => str,
		stringify(item, ctx, onComment, onChompKeep) {
			ctx = Object.assign({ actualString: true }, ctx);
			return stringifyString.stringifyString(item, ctx, onComment, onChompKeep);
		}
	};
}));
//#endregion
//#region node_modules/.pnpm/yaml@2.9.1/node_modules/yaml/dist/schema/common/null.js
var require_null = /* @__PURE__ */ __commonJSMin(((exports) => {
	var Scalar = require_Scalar();
	const nullTag = {
		identify: (value) => value == null,
		createNode: () => new Scalar.Scalar(null),
		default: true,
		tag: "tag:yaml.org,2002:null",
		test: /^(?:~|[Nn]ull|NULL)?$/,
		resolve: () => new Scalar.Scalar(null),
		stringify: ({ source }, ctx) => typeof source === "string" && nullTag.test.test(source) ? source : ctx.options.nullStr
	};
	exports.nullTag = nullTag;
}));
//#endregion
//#region node_modules/.pnpm/yaml@2.9.1/node_modules/yaml/dist/schema/core/bool.js
var require_bool$1 = /* @__PURE__ */ __commonJSMin(((exports) => {
	var Scalar = require_Scalar();
	const boolTag = {
		identify: (value) => typeof value === "boolean",
		default: true,
		tag: "tag:yaml.org,2002:bool",
		test: /^(?:[Tt]rue|TRUE|[Ff]alse|FALSE)$/,
		resolve: (str) => new Scalar.Scalar(str[0] === "t" || str[0] === "T"),
		stringify({ source, value }, ctx) {
			if (source && boolTag.test.test(source)) {
				if (value === (source[0] === "t" || source[0] === "T")) return source;
			}
			return value ? ctx.options.trueStr : ctx.options.falseStr;
		}
	};
	exports.boolTag = boolTag;
}));
//#endregion
//#region node_modules/.pnpm/yaml@2.9.1/node_modules/yaml/dist/stringify/stringifyNumber.js
var require_stringifyNumber = /* @__PURE__ */ __commonJSMin(((exports) => {
	function stringifyNumber({ format, minFractionDigits, tag, value }) {
		if (typeof value === "bigint") return String(value);
		const num = typeof value === "number" ? value : Number(value);
		if (!isFinite(num)) return isNaN(num) ? ".nan" : num < 0 ? "-.inf" : ".inf";
		let n = Object.is(value, -0) ? "-0" : JSON.stringify(value);
		if (!format && minFractionDigits && (!tag || tag === "tag:yaml.org,2002:float") && /^-?\d/.test(n) && !n.includes("e")) {
			let i = n.indexOf(".");
			if (i < 0) {
				i = n.length;
				n += ".";
			}
			let d = minFractionDigits - (n.length - i - 1);
			while (d-- > 0) n += "0";
		}
		return n;
	}
	exports.stringifyNumber = stringifyNumber;
}));
//#endregion
//#region node_modules/.pnpm/yaml@2.9.1/node_modules/yaml/dist/schema/core/float.js
var require_float$1 = /* @__PURE__ */ __commonJSMin(((exports) => {
	var Scalar = require_Scalar();
	var stringifyNumber = require_stringifyNumber();
	const floatNaN = {
		identify: (value) => typeof value === "number",
		default: true,
		tag: "tag:yaml.org,2002:float",
		test: /^(?:[-+]?\.(?:inf|Inf|INF)|\.nan|\.NaN|\.NAN)$/,
		resolve: (str) => str.slice(-3).toLowerCase() === "nan" ? NaN : str[0] === "-" ? Number.NEGATIVE_INFINITY : Number.POSITIVE_INFINITY,
		stringify: stringifyNumber.stringifyNumber
	};
	const floatExp = {
		identify: (value) => typeof value === "number",
		default: true,
		tag: "tag:yaml.org,2002:float",
		format: "EXP",
		test: /^[-+]?(?:\.[0-9]+|[0-9]+(?:\.[0-9]*)?)[eE][-+]?[0-9]+$/,
		resolve: (str) => parseFloat(str),
		stringify(node) {
			const num = Number(node.value);
			return isFinite(num) ? num.toExponential() : stringifyNumber.stringifyNumber(node);
		}
	};
	exports.float = {
		identify: (value) => typeof value === "number",
		default: true,
		tag: "tag:yaml.org,2002:float",
		test: /^[-+]?(?:\.[0-9]+|[0-9]+\.[0-9]*)$/,
		resolve(str) {
			const node = new Scalar.Scalar(parseFloat(str));
			const dot = str.indexOf(".");
			if (dot !== -1 && str[str.length - 1] === "0") node.minFractionDigits = str.length - dot - 1;
			return node;
		},
		stringify: stringifyNumber.stringifyNumber
	};
	exports.floatExp = floatExp;
	exports.floatNaN = floatNaN;
}));
//#endregion
//#region node_modules/.pnpm/yaml@2.9.1/node_modules/yaml/dist/schema/core/int.js
var require_int$1 = /* @__PURE__ */ __commonJSMin(((exports) => {
	var stringifyNumber = require_stringifyNumber();
	const intIdentify = (value) => typeof value === "bigint" || Number.isInteger(value);
	const intResolve = (str, offset, radix, { intAsBigInt }) => intAsBigInt ? BigInt(str) : parseInt(str.substring(offset), radix);
	function intStringify(node, radix, prefix) {
		const { value } = node;
		if (intIdentify(value) && value >= 0) return prefix + value.toString(radix);
		return stringifyNumber.stringifyNumber(node);
	}
	const intOct = {
		identify: (value) => intIdentify(value) && value >= 0,
		default: true,
		tag: "tag:yaml.org,2002:int",
		format: "OCT",
		test: /^0o[0-7]+$/,
		resolve: (str, _onError, opt) => intResolve(str, 2, 8, opt),
		stringify: (node) => intStringify(node, 8, "0o")
	};
	const int = {
		identify: intIdentify,
		default: true,
		tag: "tag:yaml.org,2002:int",
		test: /^[-+]?[0-9]+$/,
		resolve: (str, _onError, opt) => intResolve(str, 0, 10, opt),
		stringify: stringifyNumber.stringifyNumber
	};
	const intHex = {
		identify: (value) => intIdentify(value) && value >= 0,
		default: true,
		tag: "tag:yaml.org,2002:int",
		format: "HEX",
		test: /^0x[0-9a-fA-F]+$/,
		resolve: (str, _onError, opt) => intResolve(str, 2, 16, opt),
		stringify: (node) => intStringify(node, 16, "0x")
	};
	exports.int = int;
	exports.intHex = intHex;
	exports.intOct = intOct;
}));
//#endregion
//#region node_modules/.pnpm/yaml@2.9.1/node_modules/yaml/dist/schema/core/schema.js
var require_schema$2 = /* @__PURE__ */ __commonJSMin(((exports) => {
	var map = require_map();
	var _null = require_null();
	var seq = require_seq();
	var string = require_string();
	var bool = require_bool$1();
	var float = require_float$1();
	var int = require_int$1();
	exports.schema = [
		map.map,
		seq.seq,
		string.string,
		_null.nullTag,
		bool.boolTag,
		int.intOct,
		int.int,
		int.intHex,
		float.floatNaN,
		float.floatExp,
		float.float
	];
}));
//#endregion
//#region node_modules/.pnpm/yaml@2.9.1/node_modules/yaml/dist/schema/json/schema.js
var require_schema$1 = /* @__PURE__ */ __commonJSMin(((exports) => {
	var Scalar = require_Scalar();
	var map = require_map();
	var seq = require_seq();
	function intIdentify(value) {
		return typeof value === "bigint" || Number.isInteger(value);
	}
	const stringifyJSON = ({ value }) => JSON.stringify(value);
	const jsonScalars = [
		{
			identify: (value) => typeof value === "string",
			default: true,
			tag: "tag:yaml.org,2002:str",
			resolve: (str) => str,
			stringify: stringifyJSON
		},
		{
			identify: (value) => value == null,
			createNode: () => new Scalar.Scalar(null),
			default: true,
			tag: "tag:yaml.org,2002:null",
			test: /^null$/,
			resolve: () => null,
			stringify: stringifyJSON
		},
		{
			identify: (value) => typeof value === "boolean",
			default: true,
			tag: "tag:yaml.org,2002:bool",
			test: /^true$|^false$/,
			resolve: (str) => str === "true",
			stringify: stringifyJSON
		},
		{
			identify: intIdentify,
			default: true,
			tag: "tag:yaml.org,2002:int",
			test: /^-?(?:0|[1-9][0-9]*)$/,
			resolve: (str, _onError, { intAsBigInt }) => intAsBigInt ? BigInt(str) : parseInt(str, 10),
			stringify: ({ value }) => intIdentify(value) ? value.toString() : JSON.stringify(value)
		},
		{
			identify: (value) => typeof value === "number",
			default: true,
			tag: "tag:yaml.org,2002:float",
			test: /^-?(?:0|[1-9][0-9]*)(?:\.[0-9]*)?(?:[eE][-+]?[0-9]+)?$/,
			resolve: (str) => parseFloat(str),
			stringify: stringifyJSON
		}
	];
	exports.schema = [map.map, seq.seq].concat(jsonScalars, {
		default: true,
		tag: "",
		test: /^/,
		resolve(str, onError) {
			onError(`Unresolved plain scalar ${JSON.stringify(str)}`);
			return str;
		}
	});
}));
//#endregion
//#region node_modules/.pnpm/yaml@2.9.1/node_modules/yaml/dist/schema/yaml-1.1/binary.js
var require_binary = /* @__PURE__ */ __commonJSMin(((exports) => {
	var node_buffer = __require("buffer");
	var Scalar = require_Scalar();
	var stringifyString = require_stringifyString();
	exports.binary = {
		identify: (value) => value instanceof Uint8Array,
		default: false,
		tag: "tag:yaml.org,2002:binary",
		/**
		* Returns a Buffer in node and an Uint8Array in browsers
		*
		* To use the resulting buffer as an image, you'll want to do something like:
		*
		*   const blob = new Blob([buffer], { type: 'image/jpeg' })
		*   document.querySelector('#photo').src = URL.createObjectURL(blob)
		*/
		resolve(src, onError) {
			if (typeof node_buffer.Buffer === "function") return node_buffer.Buffer.from(src, "base64");
			else if (typeof atob === "function") {
				const str = atob(src.replace(/[\n\r]/g, ""));
				const buffer = new Uint8Array(str.length);
				for (let i = 0; i < str.length; ++i) buffer[i] = str.charCodeAt(i);
				return buffer;
			} else {
				onError("This environment does not support reading binary tags; either Buffer or atob is required");
				return src;
			}
		},
		stringify({ comment, type, value }, ctx, onComment, onChompKeep) {
			if (!value) return "";
			const buf = value;
			let str;
			if (typeof node_buffer.Buffer === "function") str = buf instanceof node_buffer.Buffer ? buf.toString("base64") : node_buffer.Buffer.from(buf.buffer).toString("base64");
			else if (typeof btoa === "function") {
				let s = "";
				for (let i = 0; i < buf.length; ++i) s += String.fromCharCode(buf[i]);
				str = btoa(s);
			} else throw new Error("This environment does not support writing binary tags; either Buffer or btoa is required");
			type ?? (type = Scalar.Scalar.BLOCK_LITERAL);
			if (type !== Scalar.Scalar.QUOTE_DOUBLE) {
				const lineWidth = Math.max(ctx.options.lineWidth - ctx.indent.length, ctx.options.minContentWidth);
				const n = Math.ceil(str.length / lineWidth);
				const lines = new Array(n);
				for (let i = 0, o = 0; i < n; ++i, o += lineWidth) lines[i] = str.substr(o, lineWidth);
				str = lines.join(type === Scalar.Scalar.BLOCK_LITERAL ? "\n" : " ");
			}
			return stringifyString.stringifyString({
				comment,
				type,
				value: str
			}, ctx, onComment, onChompKeep);
		}
	};
}));
//#endregion
//#region node_modules/.pnpm/yaml@2.9.1/node_modules/yaml/dist/schema/yaml-1.1/pairs.js
var require_pairs = /* @__PURE__ */ __commonJSMin(((exports) => {
	var identity = require_identity();
	var Pair = require_Pair();
	var Scalar = require_Scalar();
	var YAMLSeq = require_YAMLSeq();
	function resolvePairs(seq, onError) {
		if (identity.isSeq(seq)) for (let i = 0; i < seq.items.length; ++i) {
			let item = seq.items[i];
			if (identity.isPair(item)) continue;
			else if (identity.isMap(item)) {
				if (item.items.length > 1) onError("Each pair must have its own sequence indicator");
				const pair = item.items[0] || new Pair.Pair(new Scalar.Scalar(null));
				if (item.commentBefore) pair.key.commentBefore = pair.key.commentBefore ? `${item.commentBefore}\n${pair.key.commentBefore}` : item.commentBefore;
				if (item.comment) {
					const cn = pair.value ?? pair.key;
					cn.comment = cn.comment ? `${item.comment}\n${cn.comment}` : item.comment;
				}
				item = pair;
			}
			seq.items[i] = identity.isPair(item) ? item : new Pair.Pair(item);
		}
		else onError("Expected a sequence for this tag");
		return seq;
	}
	function createPairs(schema, iterable, ctx) {
		const { replacer } = ctx;
		const pairs = new YAMLSeq.YAMLSeq(schema);
		pairs.tag = "tag:yaml.org,2002:pairs";
		let i = 0;
		if (iterable && Symbol.iterator in Object(iterable)) for (let it of iterable) {
			if (typeof replacer === "function") it = replacer.call(iterable, String(i++), it);
			let key, value;
			if (Array.isArray(it)) {
				if (it.length === 2) {
					key = it[0];
					value = it[1];
				} else throw new TypeError(`Expected [key, value] tuple: ${it}`);
			} else if (it && it instanceof Object) {
				const keys = Object.keys(it);
				if (keys.length === 1) {
					key = keys[0];
					value = it[key];
				} else throw new TypeError(`Expected tuple with one key, not ${keys.length} keys`);
			} else key = it;
			pairs.items.push(Pair.createPair(key, value, ctx));
		}
		return pairs;
	}
	const pairs = {
		collection: "seq",
		default: false,
		tag: "tag:yaml.org,2002:pairs",
		resolve: resolvePairs,
		createNode: createPairs
	};
	exports.createPairs = createPairs;
	exports.pairs = pairs;
	exports.resolvePairs = resolvePairs;
}));
//#endregion
//#region node_modules/.pnpm/yaml@2.9.1/node_modules/yaml/dist/schema/yaml-1.1/omap.js
var require_omap = /* @__PURE__ */ __commonJSMin(((exports) => {
	var identity = require_identity();
	var toJS = require_toJS();
	var YAMLMap = require_YAMLMap();
	var YAMLSeq = require_YAMLSeq();
	var pairs = require_pairs();
	var YAMLOMap = class YAMLOMap extends YAMLSeq.YAMLSeq {
		constructor() {
			super();
			this.add = YAMLMap.YAMLMap.prototype.add.bind(this);
			this.delete = YAMLMap.YAMLMap.prototype.delete.bind(this);
			this.get = YAMLMap.YAMLMap.prototype.get.bind(this);
			this.has = YAMLMap.YAMLMap.prototype.has.bind(this);
			this.set = YAMLMap.YAMLMap.prototype.set.bind(this);
			this.tag = YAMLOMap.tag;
		}
		/**
		* If `ctx` is given, the return type is actually `Map<unknown, unknown>`,
		* but TypeScript won't allow widening the signature of a child method.
		*/
		toJSON(_, ctx) {
			if (!ctx) return super.toJSON(_);
			const map = /* @__PURE__ */ new Map();
			if (ctx?.onCreate) ctx.onCreate(map);
			for (const pair of this.items) {
				let key, value;
				if (identity.isPair(pair)) {
					key = toJS.toJS(pair.key, "", ctx);
					value = toJS.toJS(pair.value, key, ctx);
				} else key = toJS.toJS(pair, "", ctx);
				if (map.has(key)) throw new Error("Ordered maps must not include duplicate keys");
				map.set(key, value);
			}
			return map;
		}
		static from(schema, iterable, ctx) {
			const pairs$1 = pairs.createPairs(schema, iterable, ctx);
			const omap = new this();
			omap.items = pairs$1.items;
			return omap;
		}
	};
	YAMLOMap.tag = "tag:yaml.org,2002:omap";
	const omap = {
		collection: "seq",
		identify: (value) => value instanceof Map,
		nodeClass: YAMLOMap,
		default: false,
		tag: "tag:yaml.org,2002:omap",
		resolve(seq, onError) {
			const pairs$1 = pairs.resolvePairs(seq, onError);
			const seenKeys = [];
			for (const { key } of pairs$1.items) if (identity.isScalar(key)) {
				if (seenKeys.includes(key.value)) onError(`Ordered maps must not include duplicate keys: ${key.value}`);
				else seenKeys.push(key.value);
			}
			return Object.assign(new YAMLOMap(), pairs$1);
		},
		createNode: (schema, iterable, ctx) => YAMLOMap.from(schema, iterable, ctx)
	};
	exports.YAMLOMap = YAMLOMap;
	exports.omap = omap;
}));
//#endregion
//#region node_modules/.pnpm/yaml@2.9.1/node_modules/yaml/dist/schema/yaml-1.1/bool.js
var require_bool = /* @__PURE__ */ __commonJSMin(((exports) => {
	var Scalar = require_Scalar();
	function boolStringify({ value, source }, ctx) {
		if (source && (value ? trueTag : falseTag).test.test(source)) return source;
		return value ? ctx.options.trueStr : ctx.options.falseStr;
	}
	const trueTag = {
		identify: (value) => value === true,
		default: true,
		tag: "tag:yaml.org,2002:bool",
		test: /^(?:Y|y|[Yy]es|YES|[Tt]rue|TRUE|[Oo]n|ON)$/,
		resolve: () => new Scalar.Scalar(true),
		stringify: boolStringify
	};
	const falseTag = {
		identify: (value) => value === false,
		default: true,
		tag: "tag:yaml.org,2002:bool",
		test: /^(?:N|n|[Nn]o|NO|[Ff]alse|FALSE|[Oo]ff|OFF)$/,
		resolve: () => new Scalar.Scalar(false),
		stringify: boolStringify
	};
	exports.falseTag = falseTag;
	exports.trueTag = trueTag;
}));
//#endregion
//#region node_modules/.pnpm/yaml@2.9.1/node_modules/yaml/dist/schema/yaml-1.1/float.js
var require_float = /* @__PURE__ */ __commonJSMin(((exports) => {
	var Scalar = require_Scalar();
	var stringifyNumber = require_stringifyNumber();
	const floatNaN = {
		identify: (value) => typeof value === "number",
		default: true,
		tag: "tag:yaml.org,2002:float",
		test: /^(?:[-+]?\.(?:inf|Inf|INF)|\.nan|\.NaN|\.NAN)$/,
		resolve: (str) => str.slice(-3).toLowerCase() === "nan" ? NaN : str[0] === "-" ? Number.NEGATIVE_INFINITY : Number.POSITIVE_INFINITY,
		stringify: stringifyNumber.stringifyNumber
	};
	const floatExp = {
		identify: (value) => typeof value === "number",
		default: true,
		tag: "tag:yaml.org,2002:float",
		format: "EXP",
		test: /^[-+]?(?:[0-9][0-9_]*)?(?:\.[0-9_]*)?[eE][-+]?[0-9]+$/,
		resolve: (str) => parseFloat(str.replace(/_/g, "")),
		stringify(node) {
			const num = Number(node.value);
			return isFinite(num) ? num.toExponential() : stringifyNumber.stringifyNumber(node);
		}
	};
	exports.float = {
		identify: (value) => typeof value === "number",
		default: true,
		tag: "tag:yaml.org,2002:float",
		test: /^[-+]?(?:[0-9][0-9_]*)?\.[0-9_]*$/,
		resolve(str) {
			const node = new Scalar.Scalar(parseFloat(str.replace(/_/g, "")));
			const dot = str.indexOf(".");
			if (dot !== -1) {
				const f = str.substring(dot + 1).replace(/_/g, "");
				if (f[f.length - 1] === "0") node.minFractionDigits = f.length;
			}
			return node;
		},
		stringify: stringifyNumber.stringifyNumber
	};
	exports.floatExp = floatExp;
	exports.floatNaN = floatNaN;
}));
//#endregion
//#region node_modules/.pnpm/yaml@2.9.1/node_modules/yaml/dist/schema/yaml-1.1/int.js
var require_int = /* @__PURE__ */ __commonJSMin(((exports) => {
	var stringifyNumber = require_stringifyNumber();
	const intIdentify = (value) => typeof value === "bigint" || Number.isInteger(value);
	function intResolve(str, offset, radix, { intAsBigInt }) {
		const sign = str[0];
		if (sign === "-" || sign === "+") offset += 1;
		str = str.substring(offset).replace(/_/g, "");
		if (intAsBigInt) {
			switch (radix) {
				case 2:
					str = `0b${str}`;
					break;
				case 8:
					str = `0o${str}`;
					break;
				case 16: str = `0x${str}`;
			}
			const n = BigInt(str);
			return sign === "-" ? BigInt(-1) * n : n;
		}
		const n = parseInt(str, radix);
		return sign === "-" ? -1 * n : n;
	}
	function intStringify(node, radix, prefix) {
		const { value } = node;
		if (intIdentify(value)) {
			const str = value.toString(radix);
			return value < 0 ? "-" + prefix + str.substr(1) : prefix + str;
		}
		return stringifyNumber.stringifyNumber(node);
	}
	const intBin = {
		identify: intIdentify,
		default: true,
		tag: "tag:yaml.org,2002:int",
		format: "BIN",
		test: /^[-+]?0b[0-1_]+$/,
		resolve: (str, _onError, opt) => intResolve(str, 2, 2, opt),
		stringify: (node) => intStringify(node, 2, "0b")
	};
	const intOct = {
		identify: intIdentify,
		default: true,
		tag: "tag:yaml.org,2002:int",
		format: "OCT",
		test: /^[-+]?0[0-7_]+$/,
		resolve: (str, _onError, opt) => intResolve(str, 1, 8, opt),
		stringify: (node) => intStringify(node, 8, "0")
	};
	const int = {
		identify: intIdentify,
		default: true,
		tag: "tag:yaml.org,2002:int",
		test: /^[-+]?[0-9][0-9_]*$/,
		resolve: (str, _onError, opt) => intResolve(str, 0, 10, opt),
		stringify: stringifyNumber.stringifyNumber
	};
	const intHex = {
		identify: intIdentify,
		default: true,
		tag: "tag:yaml.org,2002:int",
		format: "HEX",
		test: /^[-+]?0x[0-9a-fA-F_]+$/,
		resolve: (str, _onError, opt) => intResolve(str, 2, 16, opt),
		stringify: (node) => intStringify(node, 16, "0x")
	};
	exports.int = int;
	exports.intBin = intBin;
	exports.intHex = intHex;
	exports.intOct = intOct;
}));
//#endregion
//#region node_modules/.pnpm/yaml@2.9.1/node_modules/yaml/dist/schema/yaml-1.1/set.js
var require_set = /* @__PURE__ */ __commonJSMin(((exports) => {
	var identity = require_identity();
	var Pair = require_Pair();
	var YAMLMap = require_YAMLMap();
	var YAMLSet = class YAMLSet extends YAMLMap.YAMLMap {
		constructor(schema) {
			super(schema);
			this.tag = YAMLSet.tag;
		}
		add(key) {
			let pair;
			if (identity.isPair(key)) pair = key;
			else if (key && typeof key === "object" && "key" in key && "value" in key && key.value === null) pair = new Pair.Pair(key.key, null);
			else pair = new Pair.Pair(key, null);
			if (!YAMLMap.findPair(this.items, pair.key)) this.items.push(pair);
		}
		/**
		* If `keepPair` is `true`, returns the Pair matching `key`.
		* Otherwise, returns the value of that Pair's key.
		*/
		get(key, keepPair) {
			const pair = YAMLMap.findPair(this.items, key);
			return !keepPair && identity.isPair(pair) ? identity.isScalar(pair.key) ? pair.key.value : pair.key : pair;
		}
		set(key, value) {
			if (typeof value !== "boolean") throw new Error(`Expected boolean value for set(key, value) in a YAML set, not ${typeof value}`);
			const prev = YAMLMap.findPair(this.items, key);
			if (prev && !value) this.items.splice(this.items.indexOf(prev), 1);
			else if (!prev && value) this.items.push(new Pair.Pair(key));
		}
		toJSON(_, ctx) {
			return super.toJSON(_, ctx, Set);
		}
		toString(ctx, onComment, onChompKeep) {
			if (!ctx) return JSON.stringify(this);
			if (this.hasAllNullValues(true)) return super.toString(Object.assign({}, ctx, { allNullValues: true }), onComment, onChompKeep);
			else throw new Error("Set items must all have null values");
		}
		static from(schema, iterable, ctx) {
			const { replacer } = ctx;
			const set = new this(schema);
			if (iterable && Symbol.iterator in Object(iterable)) for (let value of iterable) {
				if (typeof replacer === "function") value = replacer.call(iterable, value, value);
				set.items.push(Pair.createPair(value, null, ctx));
			}
			return set;
		}
	};
	YAMLSet.tag = "tag:yaml.org,2002:set";
	const set = {
		collection: "map",
		identify: (value) => value instanceof Set,
		nodeClass: YAMLSet,
		default: false,
		tag: "tag:yaml.org,2002:set",
		createNode: (schema, iterable, ctx) => YAMLSet.from(schema, iterable, ctx),
		resolve(map, onError) {
			if (identity.isMap(map)) {
				if (map.hasAllNullValues(true)) return Object.assign(new YAMLSet(), map);
				else onError("Set items must all have null values");
			} else onError("Expected a mapping for this tag");
			return map;
		}
	};
	exports.YAMLSet = YAMLSet;
	exports.set = set;
}));
//#endregion
//#region node_modules/.pnpm/yaml@2.9.1/node_modules/yaml/dist/schema/yaml-1.1/timestamp.js
var require_timestamp = /* @__PURE__ */ __commonJSMin(((exports) => {
	var stringifyNumber = require_stringifyNumber();
	/** Internal types handle bigint as number, because TS can't figure it out. */
	function parseSexagesimal(str, asBigInt) {
		const sign = str[0];
		const parts = sign === "-" || sign === "+" ? str.substring(1) : str;
		const num = (n) => asBigInt ? BigInt(n) : Number(n);
		const res = parts.replace(/_/g, "").split(":").reduce((res, p) => res * num(60) + num(p), num(0));
		return sign === "-" ? num(-1) * res : res;
	}
	/**
	* hhhh:mm:ss.sss
	*
	* Internal types handle bigint as number, because TS can't figure it out.
	*/
	function stringifySexagesimal(node) {
		let { value } = node;
		let num = (n) => n;
		if (typeof value === "bigint") num = (n) => BigInt(n);
		else if (isNaN(value) || !isFinite(value)) return stringifyNumber.stringifyNumber(node);
		let sign = "";
		if (value < 0) {
			sign = "-";
			value *= num(-1);
		}
		const _60 = num(60);
		const parts = [value % _60];
		if (value < 60) parts.unshift(0);
		else {
			value = (value - parts[0]) / _60;
			parts.unshift(value % _60);
			if (value >= 60) {
				value = (value - parts[0]) / _60;
				parts.unshift(value);
			}
		}
		return sign + parts.map((n) => String(n).padStart(2, "0")).join(":").replace(/000000\d*$/, "");
	}
	const intTime = {
		identify: (value) => typeof value === "bigint" || Number.isInteger(value),
		default: true,
		tag: "tag:yaml.org,2002:int",
		format: "TIME",
		test: /^[-+]?[0-9][0-9_]*(?::[0-5]?[0-9])+$/,
		resolve: (str, _onError, { intAsBigInt }) => parseSexagesimal(str, intAsBigInt),
		stringify: stringifySexagesimal
	};
	const floatTime = {
		identify: (value) => typeof value === "number",
		default: true,
		tag: "tag:yaml.org,2002:float",
		format: "TIME",
		test: /^[-+]?[0-9][0-9_]*(?::[0-5]?[0-9])+\.[0-9_]*$/,
		resolve: (str) => parseSexagesimal(str, false),
		stringify: stringifySexagesimal
	};
	const timestamp = {
		identify: (value) => value instanceof Date,
		default: true,
		tag: "tag:yaml.org,2002:timestamp",
		test: RegExp("^([0-9]{4})-([0-9]{1,2})-([0-9]{1,2})(?:(?:t|T|[ \\t]+)([0-9]{1,2}):([0-9]{1,2}):([0-9]{1,2}(\\.[0-9]+)?)(?:[ \\t]*(Z|[-+][012]?[0-9](?::[0-9]{2})?))?)?$"),
		resolve(str) {
			const match = str.match(timestamp.test);
			if (!match) throw new Error("!!timestamp expects a date, starting with yyyy-mm-dd");
			const [, year, month, day, hour, minute, second] = match.map(Number);
			const millisec = match[7] ? Number((match[7] + "00").substr(1, 3)) : 0;
			let date = Date.UTC(year, month - 1, day, hour || 0, minute || 0, second || 0, millisec);
			const tz = match[8];
			if (tz && tz !== "Z") {
				let d = parseSexagesimal(tz, false);
				if (Math.abs(d) < 30) d *= 60;
				date -= 6e4 * d;
			}
			return new Date(date);
		},
		stringify: ({ value }) => value?.toISOString().replace(/(T00:00:00)?\.000Z$/, "") ?? ""
	};
	exports.floatTime = floatTime;
	exports.intTime = intTime;
	exports.timestamp = timestamp;
}));
//#endregion
//#region node_modules/.pnpm/yaml@2.9.1/node_modules/yaml/dist/schema/yaml-1.1/schema.js
var require_schema = /* @__PURE__ */ __commonJSMin(((exports) => {
	var map = require_map();
	var _null = require_null();
	var seq = require_seq();
	var string = require_string();
	var binary = require_binary();
	var bool = require_bool();
	var float = require_float();
	var int = require_int();
	var merge = require_merge();
	var omap = require_omap();
	var pairs = require_pairs();
	var set = require_set();
	var timestamp = require_timestamp();
	exports.schema = [
		map.map,
		seq.seq,
		string.string,
		_null.nullTag,
		bool.trueTag,
		bool.falseTag,
		int.intBin,
		int.intOct,
		int.int,
		int.intHex,
		float.floatNaN,
		float.floatExp,
		float.float,
		binary.binary,
		merge.merge,
		omap.omap,
		pairs.pairs,
		set.set,
		timestamp.intTime,
		timestamp.floatTime,
		timestamp.timestamp
	];
}));
//#endregion
//#region node_modules/.pnpm/yaml@2.9.1/node_modules/yaml/dist/schema/tags.js
var require_tags = /* @__PURE__ */ __commonJSMin(((exports) => {
	var map = require_map();
	var _null = require_null();
	var seq = require_seq();
	var string = require_string();
	var bool = require_bool$1();
	var float = require_float$1();
	var int = require_int$1();
	var schema = require_schema$2();
	var schema$1 = require_schema$1();
	var binary = require_binary();
	var merge = require_merge();
	var omap = require_omap();
	var pairs = require_pairs();
	var schema$2 = require_schema();
	var set = require_set();
	var timestamp = require_timestamp();
	const schemas = /* @__PURE__ */ new Map([
		["core", schema.schema],
		["failsafe", [
			map.map,
			seq.seq,
			string.string
		]],
		["json", schema$1.schema],
		["yaml11", schema$2.schema],
		["yaml-1.1", schema$2.schema]
	]);
	const tagsByName = {
		binary: binary.binary,
		bool: bool.boolTag,
		float: float.float,
		floatExp: float.floatExp,
		floatNaN: float.floatNaN,
		floatTime: timestamp.floatTime,
		int: int.int,
		intHex: int.intHex,
		intOct: int.intOct,
		intTime: timestamp.intTime,
		map: map.map,
		merge: merge.merge,
		null: _null.nullTag,
		omap: omap.omap,
		pairs: pairs.pairs,
		seq: seq.seq,
		set: set.set,
		timestamp: timestamp.timestamp
	};
	const coreKnownTags = {
		"tag:yaml.org,2002:binary": binary.binary,
		"tag:yaml.org,2002:merge": merge.merge,
		"tag:yaml.org,2002:omap": omap.omap,
		"tag:yaml.org,2002:pairs": pairs.pairs,
		"tag:yaml.org,2002:set": set.set,
		"tag:yaml.org,2002:timestamp": timestamp.timestamp
	};
	function getTags(customTags, schemaName, addMergeTag) {
		const schemaTags = schemas.get(schemaName);
		if (schemaTags && !customTags) return addMergeTag && !schemaTags.includes(merge.merge) ? schemaTags.concat(merge.merge) : schemaTags.slice();
		let tags = schemaTags;
		if (!tags) {
			if (Array.isArray(customTags)) tags = [];
			else {
				const keys = Array.from(schemas.keys()).filter((key) => key !== "yaml11").map((key) => JSON.stringify(key)).join(", ");
				throw new Error(`Unknown schema "${schemaName}"; use one of ${keys} or define customTags array`);
			}
		}
		if (Array.isArray(customTags)) for (const tag of customTags) tags = tags.concat(tag);
		else if (typeof customTags === "function") tags = customTags(tags.slice());
		if (addMergeTag) tags = tags.concat(merge.merge);
		return tags.reduce((tags, tag) => {
			const tagObj = typeof tag === "string" ? tagsByName[tag] : tag;
			if (!tagObj) {
				const tagName = JSON.stringify(tag);
				const keys = Object.keys(tagsByName).map((key) => JSON.stringify(key)).join(", ");
				throw new Error(`Unknown custom tag ${tagName}; use one of ${keys}`);
			}
			if (!tags.includes(tagObj)) tags.push(tagObj);
			return tags;
		}, []);
	}
	exports.coreKnownTags = coreKnownTags;
	exports.getTags = getTags;
}));
//#endregion
//#region node_modules/.pnpm/yaml@2.9.1/node_modules/yaml/dist/schema/Schema.js
var require_Schema = /* @__PURE__ */ __commonJSMin(((exports) => {
	var identity = require_identity();
	var map = require_map();
	var seq = require_seq();
	var string = require_string();
	var tags = require_tags();
	const sortMapEntriesByKey = (a, b) => a.key < b.key ? -1 : a.key > b.key ? 1 : 0;
	exports.Schema = class Schema {
		constructor({ compat, customTags, merge, resolveKnownTags, schema, sortMapEntries, toStringDefaults }) {
			this.compat = Array.isArray(compat) ? tags.getTags(compat, "compat") : compat ? tags.getTags(null, compat) : null;
			this.name = typeof schema === "string" && schema || "core";
			this.knownTags = resolveKnownTags ? tags.coreKnownTags : {};
			this.tags = tags.getTags(customTags, this.name, merge);
			this.toStringOptions = toStringDefaults ?? null;
			Object.defineProperty(this, identity.MAP, { value: map.map });
			Object.defineProperty(this, identity.SCALAR, { value: string.string });
			Object.defineProperty(this, identity.SEQ, { value: seq.seq });
			this.sortMapEntries = typeof sortMapEntries === "function" ? sortMapEntries : sortMapEntries === true ? sortMapEntriesByKey : null;
		}
		clone() {
			const copy = Object.create(Schema.prototype, Object.getOwnPropertyDescriptors(this));
			copy.tags = this.tags.slice();
			return copy;
		}
	};
}));
//#endregion
//#region node_modules/.pnpm/yaml@2.9.1/node_modules/yaml/dist/stringify/stringifyDocument.js
var require_stringifyDocument = /* @__PURE__ */ __commonJSMin(((exports) => {
	var identity = require_identity();
	var stringify = require_stringify();
	var stringifyComment = require_stringifyComment();
	function stringifyDocument(doc, options) {
		const lines = [];
		let hasDirectives = options.directives === true;
		if (options.directives !== false && doc.directives) {
			const dir = doc.directives.toString(doc);
			if (dir) {
				lines.push(dir);
				hasDirectives = true;
			} else if (doc.directives.docStart) hasDirectives = true;
		}
		if (hasDirectives) lines.push("---");
		const ctx = stringify.createStringifyContext(doc, options);
		const { commentString } = ctx.options;
		if (doc.commentBefore) {
			if (lines.length !== 1) lines.unshift("");
			const cs = commentString(doc.commentBefore);
			lines.unshift(stringifyComment.indentComment(cs, ""));
		}
		let chompKeep = false;
		let contentComment = null;
		if (doc.contents) {
			if (identity.isNode(doc.contents)) {
				if (doc.contents.spaceBefore && hasDirectives) lines.push("");
				if (doc.contents.commentBefore) {
					const cs = commentString(doc.contents.commentBefore);
					lines.push(stringifyComment.indentComment(cs, ""));
				}
				ctx.forceBlockIndent = !!doc.comment;
				contentComment = doc.contents.comment;
			}
			const onChompKeep = contentComment ? void 0 : () => chompKeep = true;
			let body = stringify.stringify(doc.contents, ctx, () => contentComment = null, onChompKeep);
			if (contentComment) body += stringifyComment.lineComment(body, "", commentString(contentComment));
			if ((body[0] === "|" || body[0] === ">") && lines[lines.length - 1] === "---") lines[lines.length - 1] = `--- ${body}`;
			else lines.push(body);
		} else lines.push(stringify.stringify(doc.contents, ctx));
		if (doc.directives?.docEnd) {
			if (doc.comment) {
				const cs = commentString(doc.comment);
				if (cs.includes("\n")) {
					lines.push("...");
					lines.push(stringifyComment.indentComment(cs, ""));
				} else lines.push(`... ${cs}`);
			} else lines.push("...");
		} else {
			let dc = doc.comment;
			if (dc && chompKeep) dc = dc.replace(/^\n+/, "");
			if (dc) {
				if ((!chompKeep || contentComment) && lines[lines.length - 1] !== "") lines.push("");
				lines.push(stringifyComment.indentComment(commentString(dc), ""));
			}
		}
		return lines.join("\n") + "\n";
	}
	exports.stringifyDocument = stringifyDocument;
}));
//#endregion
//#region node_modules/.pnpm/yaml@2.9.1/node_modules/yaml/dist/doc/Document.js
var require_Document = /* @__PURE__ */ __commonJSMin(((exports) => {
	var Alias = require_Alias();
	var Collection = require_Collection();
	var identity = require_identity();
	var Pair = require_Pair();
	var toJS = require_toJS();
	var Schema = require_Schema();
	var stringifyDocument = require_stringifyDocument();
	var anchors = require_anchors();
	var applyReviver = require_applyReviver();
	var createNode = require_createNode();
	var directives = require_directives();
	var Document = class Document {
		constructor(value, replacer, options) {
			/** A comment before this Document */
			this.commentBefore = null;
			/** A comment immediately after this Document */
			this.comment = null;
			/** Errors encountered during parsing. */
			this.errors = [];
			/** Warnings encountered during parsing. */
			this.warnings = [];
			Object.defineProperty(this, identity.NODE_TYPE, { value: identity.DOC });
			let _replacer = null;
			if (typeof replacer === "function" || Array.isArray(replacer)) _replacer = replacer;
			else if (options === void 0 && replacer) {
				options = replacer;
				replacer = void 0;
			}
			const opt = Object.assign({
				intAsBigInt: false,
				keepSourceTokens: false,
				logLevel: "warn",
				prettyErrors: true,
				strict: true,
				stringKeys: false,
				uniqueKeys: true,
				version: "1.2"
			}, options);
			this.options = opt;
			let { version } = opt;
			if (options?._directives) {
				this.directives = options._directives.atDocument();
				if (this.directives.yaml.explicit) version = this.directives.yaml.version;
			} else this.directives = new directives.Directives({ version });
			this.setSchema(version, options);
			this.contents = value === void 0 ? null : this.createNode(value, _replacer, options);
		}
		/**
		* Create a deep copy of this Document and its contents.
		*
		* Custom Node values that inherit from `Object` still refer to their original instances.
		*/
		clone() {
			const copy = Object.create(Document.prototype, { [identity.NODE_TYPE]: { value: identity.DOC } });
			copy.commentBefore = this.commentBefore;
			copy.comment = this.comment;
			copy.errors = this.errors.slice();
			copy.warnings = this.warnings.slice();
			copy.options = Object.assign({}, this.options);
			if (this.directives) copy.directives = this.directives.clone();
			copy.schema = this.schema.clone();
			copy.contents = identity.isNode(this.contents) ? this.contents.clone(copy.schema) : this.contents;
			if (this.range) copy.range = this.range.slice();
			return copy;
		}
		/** Adds a value to the document. */
		add(value) {
			if (assertCollection(this.contents)) this.contents.add(value);
		}
		/** Adds a value to the document. */
		addIn(path, value) {
			if (assertCollection(this.contents)) this.contents.addIn(path, value);
		}
		/**
		* Create a new `Alias` node, ensuring that the target `node` has the required anchor.
		*
		* If `node` already has an anchor, `name` is ignored.
		* Otherwise, the `node.anchor` value will be set to `name`,
		* or if an anchor with that name is already present in the document,
		* `name` will be used as a prefix for a new unique anchor.
		* If `name` is undefined, the generated anchor will use 'a' as a prefix.
		*/
		createAlias(node, name) {
			if (!node.anchor) {
				const prev = anchors.anchorNames(this);
				node.anchor = !name || prev.has(name) ? anchors.findNewAnchor(name || "a", prev) : name;
			}
			return new Alias.Alias(node.anchor);
		}
		createNode(value, replacer, options) {
			let _replacer = void 0;
			if (typeof replacer === "function") {
				value = replacer.call({ "": value }, "", value);
				_replacer = replacer;
			} else if (Array.isArray(replacer)) {
				const keyToStr = (v) => typeof v === "number" || v instanceof String || v instanceof Number;
				const asStr = replacer.filter(keyToStr).map(String);
				if (asStr.length > 0) replacer = replacer.concat(asStr);
				_replacer = replacer;
			} else if (options === void 0 && replacer) {
				options = replacer;
				replacer = void 0;
			}
			const { aliasDuplicateObjects, anchorPrefix, flow, keepUndefined, onTagObj, tag } = options ?? {};
			const { onAnchor, setAnchors, sourceObjects } = anchors.createNodeAnchors(this, anchorPrefix || "a");
			const ctx = {
				aliasDuplicateObjects: aliasDuplicateObjects ?? true,
				keepUndefined: keepUndefined ?? false,
				onAnchor,
				onTagObj,
				replacer: _replacer,
				schema: this.schema,
				sourceObjects
			};
			const node = createNode.createNode(value, tag, ctx);
			if (flow && identity.isCollection(node)) node.flow = true;
			setAnchors();
			return node;
		}
		/**
		* Convert a key and a value into a `Pair` using the current schema,
		* recursively wrapping all values as `Scalar` or `Collection` nodes.
		*/
		createPair(key, value, options = {}) {
			const k = this.createNode(key, null, options);
			const v = this.createNode(value, null, options);
			return new Pair.Pair(k, v);
		}
		/**
		* Removes a value from the document.
		* @returns `true` if the item was found and removed.
		*/
		delete(key) {
			return assertCollection(this.contents) ? this.contents.delete(key) : false;
		}
		/**
		* Removes a value from the document.
		* @returns `true` if the item was found and removed.
		*/
		deleteIn(path) {
			if (Collection.isEmptyPath(path)) {
				if (this.contents == null) return false;
				this.contents = null;
				return true;
			}
			return assertCollection(this.contents) ? this.contents.deleteIn(path) : false;
		}
		/**
		* Returns item at `key`, or `undefined` if not found. By default unwraps
		* scalar values from their surrounding node; to disable set `keepScalar` to
		* `true` (collections are always returned intact).
		*/
		get(key, keepScalar) {
			return identity.isCollection(this.contents) ? this.contents.get(key, keepScalar) : void 0;
		}
		/**
		* Returns item at `path`, or `undefined` if not found. By default unwraps
		* scalar values from their surrounding node; to disable set `keepScalar` to
		* `true` (collections are always returned intact).
		*/
		getIn(path, keepScalar) {
			if (Collection.isEmptyPath(path)) return !keepScalar && identity.isScalar(this.contents) ? this.contents.value : this.contents;
			return identity.isCollection(this.contents) ? this.contents.getIn(path, keepScalar) : void 0;
		}
		/**
		* Checks if the document includes a value with the key `key`.
		*/
		has(key) {
			return identity.isCollection(this.contents) ? this.contents.has(key) : false;
		}
		/**
		* Checks if the document includes a value at `path`.
		*/
		hasIn(path) {
			if (Collection.isEmptyPath(path)) return this.contents !== void 0;
			return identity.isCollection(this.contents) ? this.contents.hasIn(path) : false;
		}
		/**
		* Sets a value in this document. For `!!set`, `value` needs to be a
		* boolean to add/remove the item from the set.
		*/
		set(key, value) {
			if (this.contents == null) this.contents = Collection.collectionFromPath(this.schema, [key], value);
			else if (assertCollection(this.contents)) this.contents.set(key, value);
		}
		/**
		* Sets a value in this document. For `!!set`, `value` needs to be a
		* boolean to add/remove the item from the set.
		*/
		setIn(path, value) {
			if (Collection.isEmptyPath(path)) this.contents = value;
			else if (this.contents == null) this.contents = Collection.collectionFromPath(this.schema, Array.from(path), value);
			else if (assertCollection(this.contents)) this.contents.setIn(path, value);
		}
		/**
		* Change the YAML version and schema used by the document.
		* A `null` version disables support for directives, explicit tags, anchors, and aliases.
		* It also requires the `schema` option to be given as a `Schema` instance value.
		*
		* Overrides all previously set schema options.
		*/
		setSchema(version, options = {}) {
			if (typeof version === "number") version = String(version);
			let opt;
			switch (version) {
				case "1.1":
					if (this.directives) this.directives.yaml.version = "1.1";
					else this.directives = new directives.Directives({ version: "1.1" });
					opt = {
						resolveKnownTags: false,
						schema: "yaml-1.1"
					};
					break;
				case "1.2":
				case "next":
					if (this.directives) this.directives.yaml.version = version;
					else this.directives = new directives.Directives({ version });
					opt = {
						resolveKnownTags: true,
						schema: "core"
					};
					break;
				case null:
					if (this.directives) delete this.directives;
					opt = null;
					break;
				default: {
					const sv = JSON.stringify(version);
					throw new Error(`Expected '1.1', '1.2' or null as first argument, but found: ${sv}`);
				}
			}
			if (options.schema instanceof Object) this.schema = options.schema;
			else if (opt) this.schema = new Schema.Schema(Object.assign(opt, options));
			else throw new Error(`With a null YAML version, the { schema: Schema } option is required`);
		}
		toJS({ json, jsonArg, mapAsMap, maxAliasCount, onAnchor, reviver } = {}) {
			const ctx = {
				anchors: /* @__PURE__ */ new Map(),
				doc: this,
				keep: !json,
				mapAsMap: mapAsMap === true,
				mapKeyWarned: false,
				maxAliasCount: typeof maxAliasCount === "number" ? maxAliasCount : 100
			};
			const res = toJS.toJS(this.contents, jsonArg ?? "", ctx);
			if (typeof onAnchor === "function") for (const { count, res } of ctx.anchors.values()) onAnchor(res, count);
			return typeof reviver === "function" ? applyReviver.applyReviver(reviver, { "": res }, "", res) : res;
		}
		/**
		* A JSON representation of the document `contents`.
		*
		* @param jsonArg Used by `JSON.stringify` to indicate the array index or
		*   property name.
		*/
		toJSON(jsonArg, onAnchor) {
			return this.toJS({
				json: true,
				jsonArg,
				mapAsMap: false,
				onAnchor
			});
		}
		/** A YAML representation of the document. */
		toString(options = {}) {
			if (this.errors.length > 0) throw new Error("Document with errors cannot be stringified");
			if ("indent" in options && (!Number.isInteger(options.indent) || Number(options.indent) <= 0)) {
				const s = JSON.stringify(options.indent);
				throw new Error(`"indent" option must be a positive integer, not ${s}`);
			}
			return stringifyDocument.stringifyDocument(this, options);
		}
	};
	function assertCollection(contents) {
		if (identity.isCollection(contents)) return true;
		throw new Error("Expected a YAML collection as document contents");
	}
	exports.Document = Document;
}));
//#endregion
//#region node_modules/.pnpm/yaml@2.9.1/node_modules/yaml/dist/errors.js
var require_errors = /* @__PURE__ */ __commonJSMin(((exports) => {
	var YAMLError = class extends Error {
		constructor(name, pos, code, message) {
			super();
			this.name = name;
			this.code = code;
			this.message = message;
			this.pos = pos;
		}
	};
	var YAMLParseError = class extends YAMLError {
		constructor(pos, code, message) {
			super("YAMLParseError", pos, code, message);
		}
	};
	var YAMLWarning = class extends YAMLError {
		constructor(pos, code, message) {
			super("YAMLWarning", pos, code, message);
		}
	};
	const prettifyError = (src, lc) => (error) => {
		if (error.pos[0] === -1) return;
		error.linePos = error.pos.map((pos) => lc.linePos(pos));
		const { line, col } = error.linePos[0];
		error.message += ` at line ${line}, column ${col}`;
		let ci = col - 1;
		let lineStr = src.substring(lc.lineStarts[line - 1], lc.lineStarts[line]).replace(/[\n\r]+$/, "");
		if (ci >= 60 && lineStr.length > 80) {
			const trimStart = Math.min(ci - 39, lineStr.length - 79);
			lineStr = "…" + lineStr.substring(trimStart);
			ci -= trimStart - 1;
		}
		if (lineStr.length > 80) lineStr = lineStr.substring(0, 79) + "…";
		if (line > 1 && /^ *$/.test(lineStr.substring(0, ci))) {
			let prev = src.substring(lc.lineStarts[line - 2], lc.lineStarts[line - 1]);
			if (prev.length > 80) prev = prev.substring(0, 79) + "…\n";
			lineStr = prev + lineStr;
		}
		if (/[^ ]/.test(lineStr)) {
			let count = 1;
			const end = error.linePos[1];
			if (end?.line === line && end.col > col) count = Math.max(1, Math.min(end.col - col, 80 - ci));
			const pointer = " ".repeat(ci) + "^".repeat(count);
			error.message += `:\n\n${lineStr}\n${pointer}\n`;
		}
	};
	exports.YAMLError = YAMLError;
	exports.YAMLParseError = YAMLParseError;
	exports.YAMLWarning = YAMLWarning;
	exports.prettifyError = prettifyError;
}));
//#endregion
//#region node_modules/.pnpm/yaml@2.9.1/node_modules/yaml/dist/compose/resolve-props.js
var require_resolve_props = /* @__PURE__ */ __commonJSMin(((exports) => {
	function resolveProps(tokens, { flow, indicator, next, offset, onError, parentIndent, startOnNewline }) {
		let spaceBefore = false;
		let atNewline = startOnNewline;
		let hasSpace = startOnNewline;
		let comment = "";
		let commentSep = "";
		let hasNewline = false;
		let reqSpace = false;
		let tab = null;
		let anchor = null;
		let tag = null;
		let newlineAfterProp = null;
		let comma = null;
		let found = null;
		let start = null;
		for (const token of tokens) {
			if (reqSpace) {
				if (token.type !== "space" && token.type !== "newline" && token.type !== "comma") onError(token.offset, "MISSING_CHAR", "Tags and anchors must be separated from the next token by white space");
				reqSpace = false;
			}
			if (tab) {
				if (atNewline && token.type !== "comment" && token.type !== "newline") onError(tab, "TAB_AS_INDENT", "Tabs are not allowed as indentation");
				tab = null;
			}
			switch (token.type) {
				case "space":
					if (!flow && (indicator !== "doc-start" || next?.type !== "flow-collection") && token.source.includes("	")) tab = token;
					hasSpace = true;
					break;
				case "comment": {
					if (!hasSpace) onError(token, "MISSING_CHAR", "Comments must be separated from other tokens by white space characters");
					const cb = token.source.substring(1) || " ";
					if (!comment) comment = cb;
					else comment += commentSep + cb;
					commentSep = "";
					atNewline = false;
					break;
				}
				case "newline":
					if (atNewline) {
						if (comment) comment += token.source;
						else if (!found || indicator !== "seq-item-ind") spaceBefore = true;
					} else commentSep += token.source;
					atNewline = true;
					hasNewline = true;
					if (anchor || tag) newlineAfterProp = token;
					hasSpace = true;
					break;
				case "anchor":
					if (anchor) onError(token, "MULTIPLE_ANCHORS", "A node can have at most one anchor");
					if (token.source.endsWith(":")) onError(token.offset + token.source.length - 1, "BAD_ALIAS", "Anchor ending in : is ambiguous", true);
					anchor = token;
					start ?? (start = token.offset);
					atNewline = false;
					hasSpace = false;
					reqSpace = true;
					break;
				case "tag":
					if (tag) onError(token, "MULTIPLE_TAGS", "A node can have at most one tag");
					tag = token;
					start ?? (start = token.offset);
					atNewline = false;
					hasSpace = false;
					reqSpace = true;
					break;
				case indicator:
					if (anchor || tag) onError(token, "BAD_PROP_ORDER", `Anchors and tags must be after the ${token.source} indicator`);
					if (found) onError(token, "UNEXPECTED_TOKEN", `Unexpected ${token.source} in ${flow ?? "collection"}`);
					found = token;
					atNewline = indicator === "seq-item-ind" || indicator === "explicit-key-ind";
					hasSpace = false;
					break;
				case "comma": if (flow) {
					if (comma) onError(token, "UNEXPECTED_TOKEN", `Unexpected , in ${flow}`);
					comma = token;
					atNewline = false;
					hasSpace = false;
					break;
				}
				default:
					onError(token, "UNEXPECTED_TOKEN", `Unexpected ${token.type} token`);
					atNewline = false;
					hasSpace = false;
			}
		}
		const last = tokens[tokens.length - 1];
		const end = last ? last.offset + last.source.length : offset;
		if (reqSpace && next && next.type !== "space" && next.type !== "newline" && next.type !== "comma" && (next.type !== "scalar" || next.source !== "")) onError(next.offset, "MISSING_CHAR", "Tags and anchors must be separated from the next token by white space");
		if (tab && (atNewline && tab.indent <= parentIndent || next?.type === "block-map" || next?.type === "block-seq")) onError(tab, "TAB_AS_INDENT", "Tabs are not allowed as indentation");
		return {
			comma,
			found,
			spaceBefore,
			comment,
			hasNewline,
			anchor,
			tag,
			newlineAfterProp,
			end,
			start: start ?? end
		};
	}
	exports.resolveProps = resolveProps;
}));
//#endregion
//#region node_modules/.pnpm/yaml@2.9.1/node_modules/yaml/dist/compose/util-contains-newline.js
var require_util_contains_newline = /* @__PURE__ */ __commonJSMin(((exports) => {
	function containsNewline(key) {
		if (!key) return null;
		switch (key.type) {
			case "alias":
			case "scalar":
			case "double-quoted-scalar":
			case "single-quoted-scalar":
				if (key.source.includes("\n")) return true;
				if (key.end) {
					for (const st of key.end) if (st.type === "newline") return true;
				}
				return false;
			case "flow-collection":
				for (const it of key.items) {
					for (const st of it.start) if (st.type === "newline") return true;
					if (it.sep) {
						for (const st of it.sep) if (st.type === "newline") return true;
					}
					if (containsNewline(it.key) || containsNewline(it.value)) return true;
				}
				return false;
			default: return true;
		}
	}
	exports.containsNewline = containsNewline;
}));
//#endregion
//#region node_modules/.pnpm/yaml@2.9.1/node_modules/yaml/dist/compose/util-flow-indent-check.js
var require_util_flow_indent_check = /* @__PURE__ */ __commonJSMin(((exports) => {
	var utilContainsNewline = require_util_contains_newline();
	function flowIndentCheck(indent, fc, onError) {
		if (fc?.type === "flow-collection") {
			const end = fc.end[0];
			if (end.indent === indent && (end.source === "]" || end.source === "}") && utilContainsNewline.containsNewline(fc)) onError(end, "BAD_INDENT", "Flow end indicator should be more indented than parent", true);
		}
	}
	exports.flowIndentCheck = flowIndentCheck;
}));
//#endregion
//#region node_modules/.pnpm/yaml@2.9.1/node_modules/yaml/dist/compose/util-map-includes.js
var require_util_map_includes = /* @__PURE__ */ __commonJSMin(((exports) => {
	var identity = require_identity();
	function mapIncludes(ctx, items, search) {
		const { uniqueKeys } = ctx.options;
		if (uniqueKeys === false) return false;
		const isEqual = typeof uniqueKeys === "function" ? uniqueKeys : (a, b) => a === b || identity.isScalar(a) && identity.isScalar(b) && a.value === b.value;
		return items.some((pair) => isEqual(pair.key, search));
	}
	exports.mapIncludes = mapIncludes;
}));
//#endregion
//#region node_modules/.pnpm/yaml@2.9.1/node_modules/yaml/dist/compose/resolve-block-map.js
var require_resolve_block_map = /* @__PURE__ */ __commonJSMin(((exports) => {
	var Pair = require_Pair();
	var YAMLMap = require_YAMLMap();
	var resolveProps = require_resolve_props();
	var utilContainsNewline = require_util_contains_newline();
	var utilFlowIndentCheck = require_util_flow_indent_check();
	var utilMapIncludes = require_util_map_includes();
	const startColMsg = "All mapping items must start at the same column";
	function resolveBlockMap({ composeNode, composeEmptyNode }, ctx, bm, onError, tag) {
		const map = new ((tag?.nodeClass) ?? YAMLMap.YAMLMap)(ctx.schema);
		if (ctx.atRoot) ctx.atRoot = false;
		let offset = bm.offset;
		let commentEnd = null;
		for (const collItem of bm.items) {
			const { start, key, sep, value } = collItem;
			const keyProps = resolveProps.resolveProps(start, {
				indicator: "explicit-key-ind",
				next: key ?? sep?.[0],
				offset,
				onError,
				parentIndent: bm.indent,
				startOnNewline: true
			});
			const implicitKey = !keyProps.found;
			if (implicitKey) {
				if (key) {
					if (key.type === "block-seq") onError(offset, "BLOCK_AS_IMPLICIT_KEY", "A block sequence may not be used as an implicit map key");
					else if ("indent" in key && key.indent !== bm.indent) onError(offset, "BAD_INDENT", startColMsg);
				}
				if (!keyProps.anchor && !keyProps.tag && !sep) {
					commentEnd = keyProps.end;
					if (keyProps.comment) {
						if (map.comment) map.comment += "\n" + keyProps.comment;
						else map.comment = keyProps.comment;
					}
					continue;
				}
				if (keyProps.newlineAfterProp || utilContainsNewline.containsNewline(key)) onError(key ?? start[start.length - 1], "MULTILINE_IMPLICIT_KEY", "Implicit keys need to be on a single line");
			} else if (keyProps.found?.indent !== bm.indent) onError(offset, "BAD_INDENT", startColMsg);
			ctx.atKey = true;
			const keyStart = keyProps.end;
			const keyNode = key ? composeNode(ctx, key, keyProps, onError) : composeEmptyNode(ctx, keyStart, start, null, keyProps, onError);
			if (ctx.schema.compat) utilFlowIndentCheck.flowIndentCheck(bm.indent, key, onError);
			ctx.atKey = false;
			if (utilMapIncludes.mapIncludes(ctx, map.items, keyNode)) onError(keyStart, "DUPLICATE_KEY", "Map keys must be unique");
			const valueProps = resolveProps.resolveProps(sep ?? [], {
				indicator: "map-value-ind",
				next: value,
				offset: keyNode.range[2],
				onError,
				parentIndent: bm.indent,
				startOnNewline: !key || key.type === "block-scalar"
			});
			offset = valueProps.end;
			if (valueProps.found) {
				if (implicitKey) {
					if (value?.type === "block-map" && !valueProps.hasNewline) onError(offset, "BLOCK_AS_IMPLICIT_KEY", "Nested mappings are not allowed in compact mappings");
					if (ctx.options.strict && keyProps.start < valueProps.found.offset - 1024) onError(keyNode.range, "KEY_OVER_1024_CHARS", "The : indicator must be at most 1024 chars after the start of an implicit block mapping key");
				}
				const valueNode = value ? composeNode(ctx, value, valueProps, onError) : composeEmptyNode(ctx, offset, sep, null, valueProps, onError);
				if (ctx.schema.compat) utilFlowIndentCheck.flowIndentCheck(bm.indent, value, onError);
				offset = valueNode.range[2];
				const pair = new Pair.Pair(keyNode, valueNode);
				if (ctx.options.keepSourceTokens) pair.srcToken = collItem;
				map.items.push(pair);
			} else {
				if (implicitKey) onError(keyNode.range, "MISSING_CHAR", "Implicit map keys need to be followed by map values");
				if (valueProps.comment) {
					if (keyNode.comment) keyNode.comment += "\n" + valueProps.comment;
					else keyNode.comment = valueProps.comment;
				}
				const pair = new Pair.Pair(keyNode);
				if (ctx.options.keepSourceTokens) pair.srcToken = collItem;
				map.items.push(pair);
			}
		}
		if (commentEnd && commentEnd < offset) onError(commentEnd, "IMPOSSIBLE", "Map comment with trailing content");
		map.range = [
			bm.offset,
			offset,
			commentEnd ?? offset
		];
		return map;
	}
	exports.resolveBlockMap = resolveBlockMap;
}));
//#endregion
//#region node_modules/.pnpm/yaml@2.9.1/node_modules/yaml/dist/compose/resolve-block-seq.js
var require_resolve_block_seq = /* @__PURE__ */ __commonJSMin(((exports) => {
	var YAMLSeq = require_YAMLSeq();
	var resolveProps = require_resolve_props();
	var utilFlowIndentCheck = require_util_flow_indent_check();
	function resolveBlockSeq({ composeNode, composeEmptyNode }, ctx, bs, onError, tag) {
		const seq = new ((tag?.nodeClass) ?? YAMLSeq.YAMLSeq)(ctx.schema);
		if (ctx.atRoot) ctx.atRoot = false;
		if (ctx.atKey) ctx.atKey = false;
		let offset = bs.offset;
		let commentEnd = null;
		for (const { start, value } of bs.items) {
			const props = resolveProps.resolveProps(start, {
				indicator: "seq-item-ind",
				next: value,
				offset,
				onError,
				parentIndent: bs.indent,
				startOnNewline: true
			});
			if (!props.found) {
				if (props.anchor || props.tag || value) {
					if (value?.type === "block-seq") onError(props.end, "BAD_INDENT", "All sequence items must start at the same column");
					else onError(offset, "MISSING_CHAR", "Sequence item without - indicator");
				} else {
					commentEnd = props.end;
					if (props.comment) seq.comment = props.comment;
					continue;
				}
			}
			const node = value ? composeNode(ctx, value, props, onError) : composeEmptyNode(ctx, props.end, start, null, props, onError);
			if (ctx.schema.compat) utilFlowIndentCheck.flowIndentCheck(bs.indent, value, onError);
			offset = node.range[2];
			seq.items.push(node);
		}
		seq.range = [
			bs.offset,
			offset,
			commentEnd ?? offset
		];
		return seq;
	}
	exports.resolveBlockSeq = resolveBlockSeq;
}));
//#endregion
//#region node_modules/.pnpm/yaml@2.9.1/node_modules/yaml/dist/compose/resolve-end.js
var require_resolve_end = /* @__PURE__ */ __commonJSMin(((exports) => {
	function resolveEnd(end, offset, reqSpace, onError) {
		let comment = "";
		if (end) {
			let hasSpace = false;
			let sep = "";
			for (const token of end) {
				const { source, type } = token;
				switch (type) {
					case "space":
						hasSpace = true;
						break;
					case "comment": {
						if (reqSpace && !hasSpace) onError(token, "MISSING_CHAR", "Comments must be separated from other tokens by white space characters");
						const cb = source.substring(1) || " ";
						if (!comment) comment = cb;
						else comment += sep + cb;
						sep = "";
						break;
					}
					case "newline":
						if (comment) sep += source;
						hasSpace = true;
						break;
					default: onError(token, "UNEXPECTED_TOKEN", `Unexpected ${type} at node end`);
				}
				offset += source.length;
			}
		}
		return {
			comment,
			offset
		};
	}
	exports.resolveEnd = resolveEnd;
}));
//#endregion
//#region node_modules/.pnpm/yaml@2.9.1/node_modules/yaml/dist/compose/resolve-flow-collection.js
var require_resolve_flow_collection = /* @__PURE__ */ __commonJSMin(((exports) => {
	var identity = require_identity();
	var Pair = require_Pair();
	var YAMLMap = require_YAMLMap();
	var YAMLSeq = require_YAMLSeq();
	var resolveEnd = require_resolve_end();
	var resolveProps = require_resolve_props();
	var utilContainsNewline = require_util_contains_newline();
	var utilMapIncludes = require_util_map_includes();
	const blockMsg = "Block collections are not allowed within flow collections";
	const isBlock = (token) => token && (token.type === "block-map" || token.type === "block-seq");
	function resolveFlowCollection({ composeNode, composeEmptyNode }, ctx, fc, onError, tag) {
		const isMap = fc.start.source === "{";
		const fcName = isMap ? "flow map" : "flow sequence";
		const coll = new ((tag?.nodeClass) ?? (isMap ? YAMLMap.YAMLMap : YAMLSeq.YAMLSeq))(ctx.schema);
		coll.flow = true;
		const atRoot = ctx.atRoot;
		if (atRoot) ctx.atRoot = false;
		if (ctx.atKey) ctx.atKey = false;
		let offset = fc.offset + fc.start.source.length;
		for (let i = 0; i < fc.items.length; ++i) {
			const collItem = fc.items[i];
			const { start, key, sep, value } = collItem;
			const props = resolveProps.resolveProps(start, {
				flow: fcName,
				indicator: "explicit-key-ind",
				next: key ?? sep?.[0],
				offset,
				onError,
				parentIndent: fc.indent,
				startOnNewline: false
			});
			if (!props.found) {
				if (!props.anchor && !props.tag && !sep && !value) {
					if (i === 0 && props.comma) onError(props.comma, "UNEXPECTED_TOKEN", `Unexpected , in ${fcName}`);
					else if (i < fc.items.length - 1) onError(props.start, "UNEXPECTED_TOKEN", `Unexpected empty item in ${fcName}`);
					if (props.comment) {
						if (coll.comment) coll.comment += "\n" + props.comment;
						else coll.comment = props.comment;
					}
					offset = props.end;
					continue;
				}
				if (!isMap && ctx.options.strict && utilContainsNewline.containsNewline(key)) onError(key, "MULTILINE_IMPLICIT_KEY", "Implicit keys of flow sequence pairs need to be on a single line");
			}
			if (i === 0) {
				if (props.comma) onError(props.comma, "UNEXPECTED_TOKEN", `Unexpected , in ${fcName}`);
			} else {
				if (!props.comma) onError(props.start, "MISSING_CHAR", `Missing , between ${fcName} items`);
				if (props.comment) {
					let prevItemComment = "";
					loop: for (const st of start) switch (st.type) {
						case "comma":
						case "space": break;
						case "comment":
							prevItemComment = st.source.substring(1);
							break loop;
						default: break loop;
					}
					if (prevItemComment) {
						let prev = coll.items[coll.items.length - 1];
						if (identity.isPair(prev)) prev = prev.value ?? prev.key;
						if (prev.comment) prev.comment += "\n" + prevItemComment;
						else prev.comment = prevItemComment;
						props.comment = props.comment.substring(prevItemComment.length + 1);
					}
				}
			}
			if (!isMap && !sep && !props.found) {
				const valueNode = value ? composeNode(ctx, value, props, onError) : composeEmptyNode(ctx, props.end, sep, null, props, onError);
				coll.items.push(valueNode);
				offset = valueNode.range[2];
				if (isBlock(value)) onError(valueNode.range, "BLOCK_IN_FLOW", blockMsg);
			} else {
				ctx.atKey = true;
				const keyStart = props.end;
				const keyNode = key ? composeNode(ctx, key, props, onError) : composeEmptyNode(ctx, keyStart, start, null, props, onError);
				if (isBlock(key)) onError(keyNode.range, "BLOCK_IN_FLOW", blockMsg);
				ctx.atKey = false;
				const valueProps = resolveProps.resolveProps(sep ?? [], {
					flow: fcName,
					indicator: "map-value-ind",
					next: value,
					offset: keyNode.range[2],
					onError,
					parentIndent: fc.indent,
					startOnNewline: false
				});
				if (valueProps.found) {
					if (!isMap && !props.found && ctx.options.strict) {
						if (sep) for (const st of sep) {
							if (st === valueProps.found) break;
							if (st.type === "newline") {
								onError(st, "MULTILINE_IMPLICIT_KEY", "Implicit keys of flow sequence pairs need to be on a single line");
								break;
							}
						}
						if (props.start < valueProps.found.offset - 1024) onError(valueProps.found, "KEY_OVER_1024_CHARS", "The : indicator must be at most 1024 chars after the start of an implicit flow sequence key");
					}
				} else if (value) {
					if ("source" in value && value.source?.[0] === ":") onError(value, "MISSING_CHAR", `Missing space after : in ${fcName}`);
					else onError(valueProps.start, "MISSING_CHAR", `Missing , or : between ${fcName} items`);
				}
				const valueNode = value ? composeNode(ctx, value, valueProps, onError) : valueProps.found ? composeEmptyNode(ctx, valueProps.end, sep, null, valueProps, onError) : null;
				if (valueNode) {
					if (isBlock(value)) onError(valueNode.range, "BLOCK_IN_FLOW", blockMsg);
				} else if (valueProps.comment) {
					if (keyNode.comment) keyNode.comment += "\n" + valueProps.comment;
					else keyNode.comment = valueProps.comment;
				}
				const pair = new Pair.Pair(keyNode, valueNode);
				if (ctx.options.keepSourceTokens) pair.srcToken = collItem;
				if (isMap) {
					const map = coll;
					if (utilMapIncludes.mapIncludes(ctx, map.items, keyNode)) onError(keyStart, "DUPLICATE_KEY", "Map keys must be unique");
					map.items.push(pair);
				} else {
					const map = new YAMLMap.YAMLMap(ctx.schema);
					map.flow = true;
					map.items.push(pair);
					const endRange = (valueNode ?? keyNode).range;
					map.range = [
						keyNode.range[0],
						endRange[1],
						endRange[2]
					];
					coll.items.push(map);
				}
				offset = valueNode ? valueNode.range[2] : valueProps.end;
			}
		}
		const expectedEnd = isMap ? "}" : "]";
		const [ce, ...ee] = fc.end;
		let cePos = offset;
		if (ce?.source === expectedEnd) cePos = ce.offset + ce.source.length;
		else {
			const name = fcName[0].toUpperCase() + fcName.substring(1);
			const msg = atRoot ? `${name} must end with a ${expectedEnd}` : `${name} in block collection must be sufficiently indented and end with a ${expectedEnd}`;
			onError(offset, atRoot ? "MISSING_CHAR" : "BAD_INDENT", msg);
			if (ce && ce.source.length !== 1) ee.unshift(ce);
		}
		if (ee.length > 0) {
			const end = resolveEnd.resolveEnd(ee, cePos, ctx.options.strict, onError);
			if (end.comment) {
				if (coll.comment) coll.comment += "\n" + end.comment;
				else coll.comment = end.comment;
			}
			coll.range = [
				fc.offset,
				cePos,
				end.offset
			];
		} else coll.range = [
			fc.offset,
			cePos,
			cePos
		];
		return coll;
	}
	exports.resolveFlowCollection = resolveFlowCollection;
}));
//#endregion
//#region node_modules/.pnpm/yaml@2.9.1/node_modules/yaml/dist/compose/compose-collection.js
var require_compose_collection = /* @__PURE__ */ __commonJSMin(((exports) => {
	var identity = require_identity();
	var Scalar = require_Scalar();
	var YAMLMap = require_YAMLMap();
	var YAMLSeq = require_YAMLSeq();
	var resolveBlockMap = require_resolve_block_map();
	var resolveBlockSeq = require_resolve_block_seq();
	var resolveFlowCollection = require_resolve_flow_collection();
	function resolveCollection(CN, ctx, token, onError, tagName, tag) {
		const coll = token.type === "block-map" ? resolveBlockMap.resolveBlockMap(CN, ctx, token, onError, tag) : token.type === "block-seq" ? resolveBlockSeq.resolveBlockSeq(CN, ctx, token, onError, tag) : resolveFlowCollection.resolveFlowCollection(CN, ctx, token, onError, tag);
		const Coll = coll.constructor;
		if (tagName === "!" || tagName === Coll.tagName) {
			coll.tag = Coll.tagName;
			return coll;
		}
		if (tagName) coll.tag = tagName;
		return coll;
	}
	function composeCollection(CN, ctx, token, props, onError) {
		const tagToken = props.tag;
		const tagName = !tagToken ? null : ctx.directives.tagName(tagToken.source, (msg) => onError(tagToken, "TAG_RESOLVE_FAILED", msg));
		if (token.type === "block-seq") {
			const { anchor, newlineAfterProp: nl } = props;
			const lastProp = anchor && tagToken ? anchor.offset > tagToken.offset ? anchor : tagToken : anchor ?? tagToken;
			if (lastProp && (!nl || nl.offset < lastProp.offset)) onError(lastProp, "MISSING_CHAR", "Missing newline after block sequence props");
		}
		const expType = token.type === "block-map" ? "map" : token.type === "block-seq" ? "seq" : token.start.source === "{" ? "map" : "seq";
		if (!tagToken || !tagName || tagName === "!" || tagName === YAMLMap.YAMLMap.tagName && expType === "map" || tagName === YAMLSeq.YAMLSeq.tagName && expType === "seq") return resolveCollection(CN, ctx, token, onError, tagName);
		let tag = ctx.schema.tags.find((t) => t.tag === tagName && t.collection === expType);
		if (!tag) {
			const kt = ctx.schema.knownTags[tagName];
			if (kt?.collection === expType) {
				ctx.schema.tags.push(Object.assign({}, kt, { default: false }));
				tag = kt;
			} else {
				if (kt) onError(tagToken, "BAD_COLLECTION_TYPE", `${kt.tag} used for ${expType} collection, but expects ${kt.collection ?? "scalar"}`, true);
				else onError(tagToken, "TAG_RESOLVE_FAILED", `Unresolved tag: ${tagName}`, true);
				return resolveCollection(CN, ctx, token, onError, tagName);
			}
		}
		const coll = resolveCollection(CN, ctx, token, onError, tagName, tag);
		const res = tag.resolve?.(coll, (msg) => onError(tagToken, "TAG_RESOLVE_FAILED", msg), ctx.options) ?? coll;
		const node = identity.isNode(res) ? res : new Scalar.Scalar(res);
		node.range = coll.range;
		node.tag = tagName;
		if (tag?.format) node.format = tag.format;
		return node;
	}
	exports.composeCollection = composeCollection;
}));
//#endregion
//#region node_modules/.pnpm/yaml@2.9.1/node_modules/yaml/dist/compose/resolve-block-scalar.js
var require_resolve_block_scalar = /* @__PURE__ */ __commonJSMin(((exports) => {
	var Scalar = require_Scalar();
	function resolveBlockScalar(ctx, scalar, onError) {
		const start = scalar.offset;
		const header = parseBlockScalarHeader(scalar, ctx.options.strict, onError);
		if (!header) return {
			value: "",
			type: null,
			comment: "",
			range: [
				start,
				start,
				start
			]
		};
		const type = header.mode === ">" ? Scalar.Scalar.BLOCK_FOLDED : Scalar.Scalar.BLOCK_LITERAL;
		const lines = scalar.source ? splitLines(scalar.source) : [];
		let chompStart = lines.length;
		for (let i = lines.length - 1; i >= 0; --i) {
			const content = lines[i][1];
			if (content === "" || content === "\r") chompStart = i;
			else break;
		}
		if (chompStart === 0) {
			const value = header.chomp === "+" && lines.length > 0 ? "\n".repeat(Math.max(1, lines.length - 1)) : "";
			let end = start + header.length;
			if (scalar.source) end += scalar.source.length;
			return {
				value,
				type,
				comment: header.comment,
				range: [
					start,
					end,
					end
				]
			};
		}
		let trimIndent = scalar.indent + header.indent;
		let offset = scalar.offset + header.length;
		let contentStart = 0;
		for (let i = 0; i < chompStart; ++i) {
			const [indent, content] = lines[i];
			if (content === "" || content === "\r") {
				if (header.indent === 0 && indent.length > trimIndent) trimIndent = indent.length;
			} else {
				if (indent.length < trimIndent) onError(offset + indent.length, "MISSING_CHAR", "Block scalars with more-indented leading empty lines must use an explicit indentation indicator");
				if (header.indent === 0) trimIndent = indent.length;
				contentStart = i;
				if (trimIndent === 0 && !ctx.atRoot) onError(offset, "BAD_INDENT", "Block scalar values in collections must be indented");
				break;
			}
			offset += indent.length + content.length + 1;
		}
		for (let i = lines.length - 1; i >= chompStart; --i) if (lines[i][0].length > trimIndent) chompStart = i + 1;
		let value = "";
		let sep = "";
		let prevMoreIndented = false;
		for (let i = 0; i < contentStart; ++i) value += lines[i][0].slice(trimIndent) + "\n";
		for (let i = contentStart; i < chompStart; ++i) {
			let [indent, content] = lines[i];
			offset += indent.length + content.length + 1;
			const crlf = content[content.length - 1] === "\r";
			if (crlf) content = content.slice(0, -1);
			/* istanbul ignore if already caught in lexer */
			if (content && indent.length < trimIndent) {
				const message = `Block scalar lines must not be less indented than their ${header.indent ? "explicit indentation indicator" : "first line"}`;
				onError(offset - content.length - (crlf ? 2 : 1), "BAD_INDENT", message);
				indent = "";
			}
			if (type === Scalar.Scalar.BLOCK_LITERAL) {
				value += sep + indent.slice(trimIndent) + content;
				sep = "\n";
			} else if (indent.length > trimIndent || content[0] === "	") {
				if (sep === " ") sep = "\n";
				else if (!prevMoreIndented && sep === "\n") sep = "\n\n";
				value += sep + indent.slice(trimIndent) + content;
				sep = "\n";
				prevMoreIndented = true;
			} else if (content === "") {
				if (sep === "\n") value += "\n";
				else sep = "\n";
			} else {
				value += sep + content;
				sep = " ";
				prevMoreIndented = false;
			}
		}
		switch (header.chomp) {
			case "-": break;
			case "+":
				for (let i = chompStart; i < lines.length; ++i) value += "\n" + lines[i][0].slice(trimIndent);
				if (value[value.length - 1] !== "\n") value += "\n";
				break;
			default: value += "\n";
		}
		const end = start + header.length + scalar.source.length;
		return {
			value,
			type,
			comment: header.comment,
			range: [
				start,
				end,
				end
			]
		};
	}
	function parseBlockScalarHeader({ offset, props }, strict, onError) {
		/* istanbul ignore if should not happen */
		if (props[0].type !== "block-scalar-header") {
			onError(props[0], "IMPOSSIBLE", "Block scalar header not found");
			return null;
		}
		const { source } = props[0];
		const mode = source[0];
		let indent = 0;
		let chomp = "";
		let error = -1;
		for (let i = 1; i < source.length; ++i) {
			const ch = source[i];
			if (!chomp && (ch === "-" || ch === "+")) chomp = ch;
			else {
				const n = Number(ch);
				if (!indent && n) indent = n;
				else if (error === -1) error = offset + i;
			}
		}
		if (error !== -1) onError(error, "UNEXPECTED_TOKEN", `Block scalar header includes extra characters: ${source}`);
		let hasSpace = false;
		let comment = "";
		let length = source.length;
		for (let i = 1; i < props.length; ++i) {
			const token = props[i];
			switch (token.type) {
				case "space": hasSpace = true;
				case "newline":
					length += token.source.length;
					break;
				case "comment":
					if (strict && !hasSpace) onError(token, "MISSING_CHAR", "Comments must be separated from other tokens by white space characters");
					length += token.source.length;
					comment = token.source.substring(1);
					break;
				case "error":
					onError(token, "UNEXPECTED_TOKEN", token.message);
					length += token.source.length;
					break;
				/* istanbul ignore next should not happen */
				default: {
					onError(token, "UNEXPECTED_TOKEN", `Unexpected token in block scalar header: ${token.type}`);
					const ts = token.source;
					if (ts && typeof ts === "string") length += ts.length;
				}
			}
		}
		return {
			mode,
			indent,
			chomp,
			comment,
			length
		};
	}
	/** @returns Array of lines split up as `[indent, content]` */
	function splitLines(source) {
		const split = source.split(/\n( *)/);
		const first = split[0];
		const m = first.match(/^( *)/);
		const lines = [m?.[1] ? [m[1], first.slice(m[1].length)] : ["", first]];
		for (let i = 1; i < split.length; i += 2) lines.push([split[i], split[i + 1]]);
		return lines;
	}
	exports.resolveBlockScalar = resolveBlockScalar;
}));
//#endregion
//#region node_modules/.pnpm/yaml@2.9.1/node_modules/yaml/dist/compose/resolve-flow-scalar.js
var require_resolve_flow_scalar = /* @__PURE__ */ __commonJSMin(((exports) => {
	var Scalar = require_Scalar();
	var resolveEnd = require_resolve_end();
	function resolveFlowScalar(scalar, strict, onError) {
		const { offset, type, source, end } = scalar;
		let _type;
		let value;
		const _onError = (rel, code, msg) => onError(offset + rel, code, msg);
		switch (type) {
			case "scalar":
				_type = Scalar.Scalar.PLAIN;
				value = plainValue(source, _onError);
				break;
			case "single-quoted-scalar":
				_type = Scalar.Scalar.QUOTE_SINGLE;
				value = singleQuotedValue(source, _onError);
				break;
			case "double-quoted-scalar":
				_type = Scalar.Scalar.QUOTE_DOUBLE;
				value = doubleQuotedValue(source, _onError);
				break;
			/* istanbul ignore next should not happen */
			default:
				onError(scalar, "UNEXPECTED_TOKEN", `Expected a flow scalar value, but found: ${type}`);
				return {
					value: "",
					type: null,
					comment: "",
					range: [
						offset,
						offset + source.length,
						offset + source.length
					]
				};
		}
		const valueEnd = offset + source.length;
		const re = resolveEnd.resolveEnd(end, valueEnd, strict, onError);
		return {
			value,
			type: _type,
			comment: re.comment,
			range: [
				offset,
				valueEnd,
				re.offset
			]
		};
	}
	function plainValue(source, onError) {
		let badChar = "";
		switch (source[0]) {
			/* istanbul ignore next should not happen */
			case "	":
				badChar = "a tab character";
				break;
			case ",":
				badChar = "flow indicator character ,";
				break;
			case "%":
				badChar = "directive indicator character %";
				break;
			case "|":
			case ">":
				badChar = `block scalar indicator ${source[0]}`;
				break;
			case "@":
			case "`": badChar = `reserved character ${source[0]}`;
		}
		if (badChar) onError(0, "BAD_SCALAR_START", `Plain value cannot start with ${badChar}`);
		return unfoldLines(source);
	}
	function singleQuotedValue(source, onError) {
		if (source[source.length - 1] !== "'" || source.length === 1) onError(source.length, "MISSING_CHAR", "Missing closing 'quote");
		return unfoldLines(source.slice(1, -1)).replace(/''/g, "'");
	}
	function unfoldLines(source) {
		const line = /(.*?)\r?\n/sy;
		let match = line.exec(source);
		if (!match) return source;
		/**
		* The negative lookbehinds in these RegExps are to
		* prevent causing a polynomial search time in certain cases.
		*
		* The try-catch is for Safari < 16.4 and other old browsers:
		* https://caniuse.com/js-regexp-lookbehind
		*/
		let trimEnd, trimBoth;
		try {
			trimEnd = /* @__PURE__ */ new RegExp("(?<![ 	])[ 	]+$");
			trimBoth = /* @__PURE__ */ new RegExp("^[ 	]+|(?<![ 	])[ 	]+$", "g");
		} catch {
			trimEnd = /[ \t]+$/;
			trimBoth = /^[ \t]+|[ \t]+$/g;
		}
		let res = match[1].replace(trimEnd, "");
		let sep = " ";
		let pos = line.lastIndex;
		while (match = line.exec(source)) {
			const lm = match[1].replace(trimBoth, "");
			if (lm === "") {
				if (sep === "\n") res += sep;
				else sep = "\n";
			} else {
				res += sep + lm;
				sep = " ";
			}
			pos = line.lastIndex;
		}
		const last = /[ \t]*(.*)/sy;
		last.lastIndex = pos;
		match = last.exec(source);
		return res + sep + (match?.[1] ?? "");
	}
	function doubleQuotedValue(source, onError) {
		let res = "";
		for (let i = 1; i < source.length - 1; ++i) {
			const ch = source[i];
			if (ch === "\r" && source[i + 1] === "\n") continue;
			if (ch === "\n") {
				const { fold, offset } = foldNewline(source, i);
				res += fold;
				i = offset;
			} else if (ch === "\\") {
				let next = source[++i];
				const cc = escapeCodes[next];
				if (cc) res += cc;
				else if (next === "\n") {
					next = source[i + 1];
					while (next === " " || next === "	") next = source[++i + 1];
				} else if (next === "\r" && source[i + 1] === "\n") {
					next = source[++i + 1];
					while (next === " " || next === "	") next = source[++i + 1];
				} else if (next === "x" || next === "u" || next === "U") {
					const length = next === "x" ? 2 : next === "u" ? 4 : 8;
					res += parseCharCode(source, i + 1, length, onError);
					i += length;
				} else {
					const raw = source.substr(i - 1, 2);
					onError(i - 1, "BAD_DQ_ESCAPE", `Invalid escape sequence ${raw}`);
					res += raw;
				}
			} else if (ch === " " || ch === "	") {
				const wsStart = i;
				let next = source[i + 1];
				while (next === " " || next === "	") next = source[++i + 1];
				if (next !== "\n" && !(next === "\r" && source[i + 2] === "\n")) res += i > wsStart ? source.slice(wsStart, i + 1) : ch;
			} else res += ch;
		}
		if (source[source.length - 1] !== "\"" || source.length === 1) onError(source.length, "MISSING_CHAR", "Missing closing \"quote");
		return res;
	}
	/**
	* Fold a single newline into a space, multiple newlines to N - 1 newlines.
	* Presumes `source[offset] === '\n'`
	*/
	function foldNewline(source, offset) {
		let fold = "";
		let ch = source[offset + 1];
		while (ch === " " || ch === "	" || ch === "\n" || ch === "\r") {
			if (ch === "\r" && source[offset + 2] !== "\n") break;
			if (ch === "\n") fold += "\n";
			offset += 1;
			ch = source[offset + 1];
		}
		if (!fold) fold = " ";
		return {
			fold,
			offset
		};
	}
	const escapeCodes = {
		"0": "\0",
		a: "\x07",
		b: "\b",
		e: "\x1B",
		f: "\f",
		n: "\n",
		r: "\r",
		t: "	",
		v: "\v",
		N: "",
		_: "\xA0",
		L: "\u2028",
		P: "\u2029",
		" ": " ",
		"\"": "\"",
		"/": "/",
		"\\": "\\",
		"	": "	"
	};
	function parseCharCode(source, offset, length, onError) {
		const cc = source.substr(offset, length);
		const code = cc.length === length && /^[0-9a-fA-F]+$/.test(cc) ? parseInt(cc, 16) : NaN;
		try {
			return String.fromCodePoint(code);
		} catch {
			const raw = source.substr(offset - 2, length + 2);
			onError(offset - 2, "BAD_DQ_ESCAPE", `Invalid escape sequence ${raw}`);
			return raw;
		}
	}
	exports.resolveFlowScalar = resolveFlowScalar;
}));
//#endregion
//#region node_modules/.pnpm/yaml@2.9.1/node_modules/yaml/dist/compose/compose-scalar.js
var require_compose_scalar = /* @__PURE__ */ __commonJSMin(((exports) => {
	var identity = require_identity();
	var Scalar = require_Scalar();
	var resolveBlockScalar = require_resolve_block_scalar();
	var resolveFlowScalar = require_resolve_flow_scalar();
	function composeScalar(ctx, token, tagToken, onError) {
		const { value, type, comment, range } = token.type === "block-scalar" ? resolveBlockScalar.resolveBlockScalar(ctx, token, onError) : resolveFlowScalar.resolveFlowScalar(token, ctx.options.strict, onError);
		const tagName = tagToken ? ctx.directives.tagName(tagToken.source, (msg) => onError(tagToken, "TAG_RESOLVE_FAILED", msg)) : null;
		let tag;
		if (ctx.options.stringKeys && ctx.atKey) tag = ctx.schema[identity.SCALAR];
		else if (tagName) tag = findScalarTagByName(ctx.schema, value, tagName, tagToken, onError);
		else if (token.type === "scalar") tag = findScalarTagByTest(ctx, value, token, onError);
		else tag = ctx.schema[identity.SCALAR];
		let scalar;
		try {
			const res = tag.resolve(value, (msg) => onError(tagToken ?? token, "TAG_RESOLVE_FAILED", msg), ctx.options);
			scalar = identity.isScalar(res) ? res : new Scalar.Scalar(res);
		} catch (error) {
			const msg = error instanceof Error ? error.message : String(error);
			onError(tagToken ?? token, "TAG_RESOLVE_FAILED", msg);
			scalar = new Scalar.Scalar(value);
		}
		scalar.range = range;
		scalar.source = value;
		if (type) scalar.type = type;
		if (tagName) scalar.tag = tagName;
		if (tag.format) scalar.format = tag.format;
		if (comment) scalar.comment = comment;
		return scalar;
	}
	function findScalarTagByName(schema, value, tagName, tagToken, onError) {
		if (tagName === "!") return schema[identity.SCALAR];
		const matchWithTest = [];
		for (const tag of schema.tags) if (!tag.collection && tag.tag === tagName) {
			if (tag.default && tag.test) matchWithTest.push(tag);
			else return tag;
		}
		for (const tag of matchWithTest) if (tag.test?.test(value)) return tag;
		const kt = schema.knownTags[tagName];
		if (kt && !kt.collection) {
			schema.tags.push(Object.assign({}, kt, {
				default: false,
				test: void 0
			}));
			return kt;
		}
		onError(tagToken, "TAG_RESOLVE_FAILED", `Unresolved tag: ${tagName}`, tagName !== "tag:yaml.org,2002:str");
		return schema[identity.SCALAR];
	}
	function findScalarTagByTest({ atKey, directives, schema }, value, token, onError) {
		const tag = schema.tags.find((tag) => (tag.default === true || atKey && tag.default === "key") && tag.test?.test(value)) || schema[identity.SCALAR];
		if (schema.compat) {
			const compat = schema.compat.find((tag) => tag.default && tag.test?.test(value)) ?? schema[identity.SCALAR];
			if (tag.tag !== compat.tag) onError(token, "TAG_RESOLVE_FAILED", `Value may be parsed as either ${directives.tagString(tag.tag)} or ${directives.tagString(compat.tag)}`, true);
		}
		return tag;
	}
	exports.composeScalar = composeScalar;
}));
//#endregion
//#region node_modules/.pnpm/yaml@2.9.1/node_modules/yaml/dist/compose/util-empty-scalar-position.js
var require_util_empty_scalar_position = /* @__PURE__ */ __commonJSMin(((exports) => {
	function emptyScalarPosition(offset, before, pos) {
		if (before) {
			pos ?? (pos = before.length);
			for (let i = pos - 1; i >= 0; --i) {
				let st = before[i];
				switch (st.type) {
					case "space":
					case "comment":
					case "newline":
						offset -= st.source.length;
						continue;
				}
				st = before[++i];
				while (st?.type === "space") {
					offset += st.source.length;
					st = before[++i];
				}
				break;
			}
		}
		return offset;
	}
	exports.emptyScalarPosition = emptyScalarPosition;
}));
//#endregion
//#region node_modules/.pnpm/yaml@2.9.1/node_modules/yaml/dist/compose/compose-node.js
var require_compose_node = /* @__PURE__ */ __commonJSMin(((exports) => {
	var Alias = require_Alias();
	var identity = require_identity();
	var composeCollection = require_compose_collection();
	var composeScalar = require_compose_scalar();
	var resolveEnd = require_resolve_end();
	var utilEmptyScalarPosition = require_util_empty_scalar_position();
	const CN = {
		composeNode,
		composeEmptyNode
	};
	function composeNode(ctx, token, props, onError) {
		const atKey = ctx.atKey;
		const { spaceBefore, comment, anchor, tag } = props;
		let node;
		let isSrcToken = true;
		switch (token.type) {
			case "alias":
				node = composeAlias(ctx, token, onError);
				if (anchor || tag) onError(token, "ALIAS_PROPS", "An alias node must not specify any properties");
				break;
			case "scalar":
			case "single-quoted-scalar":
			case "double-quoted-scalar":
			case "block-scalar":
				node = composeScalar.composeScalar(ctx, token, tag, onError);
				if (anchor) node.anchor = anchor.source.substring(1);
				break;
			case "block-map":
			case "block-seq":
			case "flow-collection":
				try {
					node = composeCollection.composeCollection(CN, ctx, token, props, onError);
					if (anchor) node.anchor = anchor.source.substring(1);
				} catch (error) {
					onError(token, "RESOURCE_EXHAUSTION", error instanceof Error ? error.message : String(error));
				}
				break;
			default:
				onError(token, "UNEXPECTED_TOKEN", token.type === "error" ? token.message : `Unsupported token (type: ${token.type})`);
				isSrcToken = false;
		}
		node ?? (node = composeEmptyNode(ctx, token.offset, void 0, null, props, onError));
		if (anchor && node.anchor === "") onError(anchor, "BAD_ALIAS", "Anchor cannot be an empty string");
		if (atKey && ctx.options.stringKeys && (!identity.isScalar(node) || typeof node.value !== "string" || node.tag && node.tag !== "tag:yaml.org,2002:str")) onError(tag ?? token, "NON_STRING_KEY", "With stringKeys, all keys must be strings");
		if (spaceBefore) node.spaceBefore = true;
		if (comment) {
			if (token.type === "scalar" && token.source === "") node.comment = comment;
			else node.commentBefore = comment;
		}
		if (ctx.options.keepSourceTokens && isSrcToken) node.srcToken = token;
		return node;
	}
	function composeEmptyNode(ctx, offset, before, pos, { spaceBefore, comment, anchor, tag, end }, onError) {
		const token = {
			type: "scalar",
			offset: utilEmptyScalarPosition.emptyScalarPosition(offset, before, pos),
			indent: -1,
			source: ""
		};
		const node = composeScalar.composeScalar(ctx, token, tag, onError);
		if (anchor) {
			node.anchor = anchor.source.substring(1);
			if (node.anchor === "") onError(anchor, "BAD_ALIAS", "Anchor cannot be an empty string");
		}
		if (spaceBefore) node.spaceBefore = true;
		if (comment) {
			node.comment = comment;
			node.range[2] = end;
		}
		return node;
	}
	function composeAlias({ options }, { offset, source, end }, onError) {
		const alias = new Alias.Alias(source.substring(1));
		if (alias.source === "") onError(offset, "BAD_ALIAS", "Alias cannot be an empty string");
		if (alias.source.endsWith(":")) onError(offset + source.length - 1, "BAD_ALIAS", "Alias ending in : is ambiguous", true);
		const valueEnd = offset + source.length;
		const re = resolveEnd.resolveEnd(end, valueEnd, options.strict, onError);
		alias.range = [
			offset,
			valueEnd,
			re.offset
		];
		if (re.comment) alias.comment = re.comment;
		return alias;
	}
	exports.composeEmptyNode = composeEmptyNode;
	exports.composeNode = composeNode;
}));
//#endregion
//#region node_modules/.pnpm/yaml@2.9.1/node_modules/yaml/dist/compose/compose-doc.js
var require_compose_doc = /* @__PURE__ */ __commonJSMin(((exports) => {
	var Document = require_Document();
	var composeNode = require_compose_node();
	var resolveEnd = require_resolve_end();
	var resolveProps = require_resolve_props();
	function composeDoc(options, directives, { offset, start, value, end }, onError) {
		const opts = Object.assign({ _directives: directives }, options);
		const doc = new Document.Document(void 0, opts);
		const ctx = {
			atKey: false,
			atRoot: true,
			directives: doc.directives,
			options: doc.options,
			schema: doc.schema
		};
		const props = resolveProps.resolveProps(start, {
			indicator: "doc-start",
			next: value ?? end?.[0],
			offset,
			onError,
			parentIndent: 0,
			startOnNewline: true
		});
		if (props.found) {
			doc.directives.docStart = true;
			if (value && (value.type === "block-map" || value.type === "block-seq") && !props.hasNewline) onError(props.end, "MISSING_CHAR", "Block collection cannot start on same line with directives-end marker");
		}
		doc.contents = value ? composeNode.composeNode(ctx, value, props, onError) : composeNode.composeEmptyNode(ctx, props.end, start, null, props, onError);
		const contentEnd = doc.contents.range[2];
		const re = resolveEnd.resolveEnd(end, contentEnd, false, onError);
		if (re.comment) doc.comment = re.comment;
		doc.range = [
			offset,
			contentEnd,
			re.offset
		];
		return doc;
	}
	exports.composeDoc = composeDoc;
}));
//#endregion
//#region node_modules/.pnpm/yaml@2.9.1/node_modules/yaml/dist/compose/composer.js
var require_composer = /* @__PURE__ */ __commonJSMin(((exports) => {
	var node_process$1 = __require("process");
	var directives = require_directives();
	var Document = require_Document();
	var errors = require_errors();
	var identity = require_identity();
	var composeDoc = require_compose_doc();
	var resolveEnd = require_resolve_end();
	function getErrorPos(src) {
		if (typeof src === "number") return [src, src + 1];
		if (Array.isArray(src)) return src.length === 2 ? src : [src[0], src[1]];
		const { offset, source } = src;
		return [offset, offset + (typeof source === "string" ? source.length : 1)];
	}
	function parsePrelude(prelude) {
		let comment = "";
		let atComment = false;
		let afterEmptyLine = false;
		for (let i = 0; i < prelude.length; ++i) {
			const source = prelude[i];
			switch (source[0]) {
				case "#":
					comment += (comment === "" ? "" : afterEmptyLine ? "\n\n" : "\n") + (source.substring(1) || " ");
					atComment = true;
					afterEmptyLine = false;
					break;
				case "%":
					if (prelude[i + 1]?.[0] !== "#") i += 1;
					atComment = false;
					break;
				default:
					if (!atComment) afterEmptyLine = true;
					atComment = false;
			}
		}
		return {
			comment,
			afterEmptyLine
		};
	}
	/**
	* Compose a stream of CST nodes into a stream of YAML Documents.
	*
	* ```ts
	* import { Composer, Parser } from 'yaml'
	*
	* const src: string = ...
	* const tokens = new Parser().parse(src)
	* const docs = new Composer().compose(tokens)
	* ```
	*/
	var Composer = class {
		constructor(options = {}) {
			this.doc = null;
			this.atDirectives = false;
			this.prelude = [];
			this.errors = [];
			this.warnings = [];
			this.onError = (source, code, message, warning) => {
				const pos = getErrorPos(source);
				if (warning) this.warnings.push(new errors.YAMLWarning(pos, code, message));
				else this.errors.push(new errors.YAMLParseError(pos, code, message));
			};
			this.directives = new directives.Directives({ version: options.version || "1.2" });
			this.options = options;
		}
		decorate(doc, afterDoc) {
			const { comment, afterEmptyLine } = parsePrelude(this.prelude);
			if (comment) {
				const dc = doc.contents;
				if (afterDoc) doc.comment = doc.comment ? `${doc.comment}\n${comment}` : comment;
				else if (afterEmptyLine || doc.directives.docStart || !dc) doc.commentBefore = comment;
				else if (identity.isCollection(dc) && !dc.flow && dc.items.length > 0) {
					let it = dc.items[0];
					if (identity.isPair(it)) it = it.key;
					const cb = it.commentBefore;
					it.commentBefore = cb ? `${comment}\n${cb}` : comment;
				} else {
					const cb = dc.commentBefore;
					dc.commentBefore = cb ? `${comment}\n${cb}` : comment;
				}
			}
			if (afterDoc) {
				for (let i = 0; i < this.errors.length; ++i) doc.errors.push(this.errors[i]);
				for (let i = 0; i < this.warnings.length; ++i) doc.warnings.push(this.warnings[i]);
			} else {
				doc.errors = this.errors;
				doc.warnings = this.warnings;
			}
			this.prelude = [];
			this.errors = [];
			this.warnings = [];
		}
		/**
		* Current stream status information.
		*
		* Mostly useful at the end of input for an empty stream.
		*/
		streamInfo() {
			return {
				comment: parsePrelude(this.prelude).comment,
				directives: this.directives,
				errors: this.errors,
				warnings: this.warnings
			};
		}
		/**
		* Compose tokens into documents.
		*
		* @param forceDoc - If the stream contains no document, still emit a final document including any comments and directives that would be applied to a subsequent document.
		* @param endOffset - Should be set if `forceDoc` is also set, to set the document range end and to indicate errors correctly.
		*/
		*compose(tokens, forceDoc = false, endOffset = -1) {
			for (const token of tokens) yield* this.next(token);
			yield* this.end(forceDoc, endOffset);
		}
		/** Advance the composer by one CST token. */
		*next(token) {
			if (node_process$1.env.LOG_STREAM) console.dir(token, { depth: null });
			switch (token.type) {
				case "directive":
					this.directives.add(token.source, (offset, message, warning) => {
						const pos = getErrorPos(token);
						pos[0] += offset;
						this.onError(pos, "BAD_DIRECTIVE", message, warning);
					});
					this.prelude.push(token.source);
					this.atDirectives = true;
					break;
				case "document": {
					const doc = composeDoc.composeDoc(this.options, this.directives, token, this.onError);
					if (this.atDirectives && !doc.directives.docStart) this.onError(token, "MISSING_CHAR", "Missing directives-end/doc-start indicator line");
					this.decorate(doc, false);
					if (this.doc) yield this.doc;
					this.doc = doc;
					this.atDirectives = false;
					break;
				}
				case "byte-order-mark":
				case "space": break;
				case "comment":
				case "newline":
					this.prelude.push(token.source);
					break;
				case "error": {
					const msg = token.source ? `${token.message}: ${JSON.stringify(token.source)}` : token.message;
					const error = new errors.YAMLParseError(getErrorPos(token), "UNEXPECTED_TOKEN", msg);
					if (this.atDirectives || !this.doc) this.errors.push(error);
					else this.doc.errors.push(error);
					break;
				}
				case "doc-end": {
					if (!this.doc) {
						this.errors.push(new errors.YAMLParseError(getErrorPos(token), "UNEXPECTED_TOKEN", "Unexpected doc-end without preceding document"));
						break;
					}
					this.doc.directives.docEnd = true;
					const end = resolveEnd.resolveEnd(token.end, token.offset + token.source.length, this.doc.options.strict, this.onError);
					this.decorate(this.doc, true);
					if (end.comment) {
						const dc = this.doc.comment;
						this.doc.comment = dc ? `${dc}\n${end.comment}` : end.comment;
					}
					this.doc.range[2] = end.offset;
					break;
				}
				default: this.errors.push(new errors.YAMLParseError(getErrorPos(token), "UNEXPECTED_TOKEN", `Unsupported token ${token.type}`));
			}
		}
		/**
		* Call at end of input to yield any remaining document.
		*
		* @param forceDoc - If the stream contains no document, still emit a final document including any comments and directives that would be applied to a subsequent document.
		* @param endOffset - Should be set if `forceDoc` is also set, to set the document range end and to indicate errors correctly.
		*/
		*end(forceDoc = false, endOffset = -1) {
			if (this.doc) {
				this.decorate(this.doc, true);
				yield this.doc;
				this.doc = null;
			} else if (forceDoc) {
				const opts = Object.assign({ _directives: this.directives }, this.options);
				const doc = new Document.Document(void 0, opts);
				if (this.atDirectives) this.onError(endOffset, "MISSING_CHAR", "Missing directives-end indicator line");
				doc.range = [
					0,
					endOffset,
					endOffset
				];
				this.decorate(doc, false);
				yield doc;
			}
		}
	};
	exports.Composer = Composer;
}));
//#endregion
//#region node_modules/.pnpm/yaml@2.9.1/node_modules/yaml/dist/parse/cst-scalar.js
var require_cst_scalar = /* @__PURE__ */ __commonJSMin(((exports) => {
	var resolveBlockScalar = require_resolve_block_scalar();
	var resolveFlowScalar = require_resolve_flow_scalar();
	var errors = require_errors();
	var stringifyString = require_stringifyString();
	function resolveAsScalar(token, strict = true, onError) {
		if (token) {
			const _onError = (pos, code, message) => {
				const offset = typeof pos === "number" ? pos : Array.isArray(pos) ? pos[0] : pos.offset;
				if (onError) onError(offset, code, message);
				else throw new errors.YAMLParseError([offset, offset + 1], code, message);
			};
			switch (token.type) {
				case "scalar":
				case "single-quoted-scalar":
				case "double-quoted-scalar": return resolveFlowScalar.resolveFlowScalar(token, strict, _onError);
				case "block-scalar": return resolveBlockScalar.resolveBlockScalar({ options: { strict } }, token, _onError);
			}
		}
		return null;
	}
	/**
	* Create a new scalar token with `value`
	*
	* Values that represent an actual string but may be parsed as a different type should use a `type` other than `'PLAIN'`,
	* as this function does not support any schema operations and won't check for such conflicts.
	*
	* @param value The string representation of the value, which will have its content properly indented.
	* @param context.end Comments and whitespace after the end of the value, or after the block scalar header. If undefined, a newline will be added.
	* @param context.implicitKey Being within an implicit key may affect the resolved type of the token's value.
	* @param context.indent The indent level of the token.
	* @param context.inFlow Is this scalar within a flow collection? This may affect the resolved type of the token's value.
	* @param context.offset The offset position of the token.
	* @param context.type The preferred type of the scalar token. If undefined, the previous type of the `token` will be used, defaulting to `'PLAIN'`.
	*/
	function createScalarToken(value, context) {
		const { implicitKey = false, indent, inFlow = false, offset = -1, type = "PLAIN" } = context;
		const source = stringifyString.stringifyString({
			type,
			value
		}, {
			implicitKey,
			indent: indent > 0 ? " ".repeat(indent) : "",
			inFlow,
			options: {
				blockQuote: true,
				lineWidth: -1
			}
		});
		const end = context.end ?? [{
			type: "newline",
			offset: -1,
			indent,
			source: "\n"
		}];
		switch (source[0]) {
			case "|":
			case ">": {
				const he = source.indexOf("\n");
				const head = source.substring(0, he);
				const body = source.substring(he + 1) + "\n";
				const props = [{
					type: "block-scalar-header",
					offset,
					indent,
					source: head
				}];
				if (!addEndtoBlockProps(props, end)) props.push({
					type: "newline",
					offset: -1,
					indent,
					source: "\n"
				});
				return {
					type: "block-scalar",
					offset,
					indent,
					props,
					source: body
				};
			}
			case "\"": return {
				type: "double-quoted-scalar",
				offset,
				indent,
				source,
				end
			};
			case "'": return {
				type: "single-quoted-scalar",
				offset,
				indent,
				source,
				end
			};
			default: return {
				type: "scalar",
				offset,
				indent,
				source,
				end
			};
		}
	}
	/**
	* Set the value of `token` to the given string `value`, overwriting any previous contents and type that it may have.
	*
	* Best efforts are made to retain any comments previously associated with the `token`,
	* though all contents within a collection's `items` will be overwritten.
	*
	* Values that represent an actual string but may be parsed as a different type should use a `type` other than `'PLAIN'`,
	* as this function does not support any schema operations and won't check for such conflicts.
	*
	* @param token Any token. If it does not include an `indent` value, the value will be stringified as if it were an implicit key.
	* @param value The string representation of the value, which will have its content properly indented.
	* @param context.afterKey In most cases, values after a key should have an additional level of indentation.
	* @param context.implicitKey Being within an implicit key may affect the resolved type of the token's value.
	* @param context.inFlow Being within a flow collection may affect the resolved type of the token's value.
	* @param context.type The preferred type of the scalar token. If undefined, the previous type of the `token` will be used, defaulting to `'PLAIN'`.
	*/
	function setScalarValue(token, value, context = {}) {
		let { afterKey = false, implicitKey = false, inFlow = false, type } = context;
		let indent = "indent" in token ? token.indent : null;
		if (afterKey && typeof indent === "number") indent += 2;
		if (!type) switch (token.type) {
			case "single-quoted-scalar":
				type = "QUOTE_SINGLE";
				break;
			case "double-quoted-scalar":
				type = "QUOTE_DOUBLE";
				break;
			case "block-scalar": {
				const header = token.props[0];
				if (header.type !== "block-scalar-header") throw new Error("Invalid block scalar header");
				type = header.source[0] === ">" ? "BLOCK_FOLDED" : "BLOCK_LITERAL";
				break;
			}
			default: type = "PLAIN";
		}
		const source = stringifyString.stringifyString({
			type,
			value
		}, {
			implicitKey: implicitKey || indent === null,
			indent: indent !== null && indent > 0 ? " ".repeat(indent) : "",
			inFlow,
			options: {
				blockQuote: true,
				lineWidth: -1
			}
		});
		switch (source[0]) {
			case "|":
			case ">":
				setBlockScalarValue(token, source);
				break;
			case "\"":
				setFlowScalarValue(token, source, "double-quoted-scalar");
				break;
			case "'":
				setFlowScalarValue(token, source, "single-quoted-scalar");
				break;
			default: setFlowScalarValue(token, source, "scalar");
		}
	}
	function setBlockScalarValue(token, source) {
		const he = source.indexOf("\n");
		const head = source.substring(0, he);
		const body = source.substring(he + 1) + "\n";
		if (token.type === "block-scalar") {
			const header = token.props[0];
			if (header.type !== "block-scalar-header") throw new Error("Invalid block scalar header");
			header.source = head;
			token.source = body;
		} else {
			const { offset } = token;
			const indent = "indent" in token ? token.indent : -1;
			const props = [{
				type: "block-scalar-header",
				offset,
				indent,
				source: head
			}];
			if (!addEndtoBlockProps(props, "end" in token ? token.end : void 0)) props.push({
				type: "newline",
				offset: -1,
				indent,
				source: "\n"
			});
			for (const key of Object.keys(token)) if (key !== "type" && key !== "offset") delete token[key];
			Object.assign(token, {
				type: "block-scalar",
				indent,
				props,
				source: body
			});
		}
	}
	/** @returns `true` if last token is a newline */
	function addEndtoBlockProps(props, end) {
		if (end) for (const st of end) switch (st.type) {
			case "space":
			case "comment":
				props.push(st);
				break;
			case "newline":
				props.push(st);
				return true;
		}
		return false;
	}
	function setFlowScalarValue(token, source, type) {
		switch (token.type) {
			case "scalar":
			case "double-quoted-scalar":
			case "single-quoted-scalar":
				token.type = type;
				token.source = source;
				break;
			case "block-scalar": {
				const end = token.props.slice(1);
				let oa = source.length;
				if (token.props[0].type === "block-scalar-header") oa -= token.props[0].source.length;
				for (const tok of end) tok.offset += oa;
				delete token.props;
				Object.assign(token, {
					type,
					source,
					end
				});
				break;
			}
			case "block-map":
			case "block-seq": {
				const nl = {
					type: "newline",
					offset: token.offset + source.length,
					indent: token.indent,
					source: "\n"
				};
				delete token.items;
				Object.assign(token, {
					type,
					source,
					end: [nl]
				});
				break;
			}
			default: {
				const indent = "indent" in token ? token.indent : -1;
				const end = "end" in token && Array.isArray(token.end) ? token.end.filter((st) => st.type === "space" || st.type === "comment" || st.type === "newline") : [];
				for (const key of Object.keys(token)) if (key !== "type" && key !== "offset") delete token[key];
				Object.assign(token, {
					type,
					indent,
					source,
					end
				});
			}
		}
	}
	exports.createScalarToken = createScalarToken;
	exports.resolveAsScalar = resolveAsScalar;
	exports.setScalarValue = setScalarValue;
}));
//#endregion
//#region node_modules/.pnpm/yaml@2.9.1/node_modules/yaml/dist/parse/cst-stringify.js
var require_cst_stringify = /* @__PURE__ */ __commonJSMin(((exports) => {
	/**
	* Stringify a CST document, token, or collection item
	*
	* Fair warning: This applies no validation whatsoever, and
	* simply concatenates the sources in their logical order.
	*/
	const stringify = (cst) => "type" in cst ? stringifyToken(cst) : stringifyItem(cst);
	function stringifyToken(token) {
		switch (token.type) {
			case "block-scalar": {
				let res = "";
				for (const tok of token.props) res += stringifyToken(tok);
				return res + token.source;
			}
			case "block-map":
			case "block-seq": {
				let res = "";
				for (const item of token.items) res += stringifyItem(item);
				return res;
			}
			case "flow-collection": {
				let res = token.start.source;
				for (const item of token.items) res += stringifyItem(item);
				for (const st of token.end) res += st.source;
				return res;
			}
			case "document": {
				let res = stringifyItem(token);
				if (token.end) for (const st of token.end) res += st.source;
				return res;
			}
			default: {
				let res = token.source;
				if ("end" in token && token.end) for (const st of token.end) res += st.source;
				return res;
			}
		}
	}
	function stringifyItem({ start, key, sep, value }) {
		let res = "";
		for (const st of start) res += st.source;
		if (key) res += stringifyToken(key);
		if (sep) for (const st of sep) res += st.source;
		if (value) res += stringifyToken(value);
		return res;
	}
	exports.stringify = stringify;
}));
//#endregion
//#region node_modules/.pnpm/yaml@2.9.1/node_modules/yaml/dist/parse/cst-visit.js
var require_cst_visit = /* @__PURE__ */ __commonJSMin(((exports) => {
	const BREAK = Symbol("break visit");
	const SKIP = Symbol("skip children");
	const REMOVE = Symbol("remove item");
	/**
	* Apply a visitor to a CST document or item.
	*
	* Walks through the tree (depth-first) starting from the root, calling a
	* `visitor` function with two arguments when entering each item:
	*   - `item`: The current item, which included the following members:
	*     - `start: SourceToken[]` – Source tokens before the key or value,
	*       possibly including its anchor or tag.
	*     - `key?: Token | null` – Set for pair values. May then be `null`, if
	*       the key before the `:` separator is empty.
	*     - `sep?: SourceToken[]` – Source tokens between the key and the value,
	*       which should include the `:` map value indicator if `value` is set.
	*     - `value?: Token` – The value of a sequence item, or of a map pair.
	*   - `path`: The steps from the root to the current node, as an array of
	*     `['key' | 'value', number]` tuples.
	*
	* The return value of the visitor may be used to control the traversal:
	*   - `undefined` (default): Do nothing and continue
	*   - `visit.SKIP`: Do not visit the children of this token, continue with
	*      next sibling
	*   - `visit.BREAK`: Terminate traversal completely
	*   - `visit.REMOVE`: Remove the current item, then continue with the next one
	*   - `number`: Set the index of the next step. This is useful especially if
	*     the index of the current token has changed.
	*   - `function`: Define the next visitor for this item. After the original
	*     visitor is called on item entry, next visitors are called after handling
	*     a non-empty `key` and when exiting the item.
	*/
	function visit(cst, visitor) {
		if ("type" in cst && cst.type === "document") cst = {
			start: cst.start,
			value: cst.value
		};
		_visit(Object.freeze([]), cst, visitor);
	}
	/** Terminate visit traversal completely */
	visit.BREAK = BREAK;
	/** Do not visit the children of the current item */
	visit.SKIP = SKIP;
	/** Remove the current item */
	visit.REMOVE = REMOVE;
	/** Find the item at `path` from `cst` as the root */
	visit.itemAtPath = (cst, path) => {
		let item = cst;
		for (const [field, index] of path) {
			const tok = item?.[field];
			if (tok && "items" in tok) item = tok.items[index];
			else return void 0;
		}
		return item;
	};
	/**
	* Get the immediate parent collection of the item at `path` from `cst` as the root.
	*
	* Throws an error if the collection is not found, which should never happen if the item itself exists.
	*/
	visit.parentCollection = (cst, path) => {
		const parent = visit.itemAtPath(cst, path.slice(0, -1));
		const field = path[path.length - 1][0];
		const coll = parent?.[field];
		if (coll && "items" in coll) return coll;
		throw new Error("Parent collection not found");
	};
	function _visit(path, item, visitor) {
		let ctrl = visitor(item, path);
		if (typeof ctrl === "symbol") return ctrl;
		for (const field of ["key", "value"]) {
			const token = item[field];
			if (token && "items" in token) {
				for (let i = 0; i < token.items.length; ++i) {
					const ci = _visit(Object.freeze(path.concat([[field, i]])), token.items[i], visitor);
					if (typeof ci === "number") i = ci - 1;
					else if (ci === BREAK) return BREAK;
					else if (ci === REMOVE) {
						token.items.splice(i, 1);
						i -= 1;
					}
				}
				if (typeof ctrl === "function" && field === "key") ctrl = ctrl(item, path);
			}
		}
		return typeof ctrl === "function" ? ctrl(item, path) : ctrl;
	}
	exports.visit = visit;
}));
//#endregion
//#region node_modules/.pnpm/yaml@2.9.1/node_modules/yaml/dist/parse/cst.js
var require_cst = /* @__PURE__ */ __commonJSMin(((exports) => {
	var cstScalar = require_cst_scalar();
	var cstStringify = require_cst_stringify();
	var cstVisit = require_cst_visit();
	/** The byte order mark */
	const BOM = "﻿";
	/** Start of doc-mode */
	const DOCUMENT = "";
	/** Unexpected end of flow-mode */
	const FLOW_END = "";
	/** Next token is a scalar value */
	const SCALAR = "";
	/** @returns `true` if `token` is a flow or block collection */
	const isCollection = (token) => !!token && "items" in token;
	/** @returns `true` if `token` is a flow or block scalar; not an alias */
	const isScalar = (token) => !!token && (token.type === "scalar" || token.type === "single-quoted-scalar" || token.type === "double-quoted-scalar" || token.type === "block-scalar");
	/* istanbul ignore next */
	/** Get a printable representation of a lexer token */
	function prettyToken(token) {
		switch (token) {
			case BOM: return "<BOM>";
			case DOCUMENT: return "<DOC>";
			case FLOW_END: return "<FLOW_END>";
			case SCALAR: return "<SCALAR>";
			default: return JSON.stringify(token);
		}
	}
	/** Identify the type of a lexer token. May return `null` for unknown tokens. */
	function tokenType(source) {
		switch (source) {
			case BOM: return "byte-order-mark";
			case DOCUMENT: return "doc-mode";
			case FLOW_END: return "flow-error-end";
			case SCALAR: return "scalar";
			case "---": return "doc-start";
			case "...": return "doc-end";
			case "":
			case "\n":
			case "\r\n": return "newline";
			case "-": return "seq-item-ind";
			case "?": return "explicit-key-ind";
			case ":": return "map-value-ind";
			case "{": return "flow-map-start";
			case "}": return "flow-map-end";
			case "[": return "flow-seq-start";
			case "]": return "flow-seq-end";
			case ",": return "comma";
		}
		switch (source[0]) {
			case " ":
			case "	": return "space";
			case "#": return "comment";
			case "%": return "directive-line";
			case "*": return "alias";
			case "&": return "anchor";
			case "!": return "tag";
			case "'": return "single-quoted-scalar";
			case "\"": return "double-quoted-scalar";
			case "|":
			case ">": return "block-scalar-header";
		}
		return null;
	}
	exports.createScalarToken = cstScalar.createScalarToken;
	exports.resolveAsScalar = cstScalar.resolveAsScalar;
	exports.setScalarValue = cstScalar.setScalarValue;
	exports.stringify = cstStringify.stringify;
	exports.visit = cstVisit.visit;
	exports.BOM = BOM;
	exports.DOCUMENT = DOCUMENT;
	exports.FLOW_END = FLOW_END;
	exports.SCALAR = SCALAR;
	exports.isCollection = isCollection;
	exports.isScalar = isScalar;
	exports.prettyToken = prettyToken;
	exports.tokenType = tokenType;
}));
//#endregion
//#region node_modules/.pnpm/yaml@2.9.1/node_modules/yaml/dist/parse/lexer.js
var require_lexer = /* @__PURE__ */ __commonJSMin(((exports) => {
	var cst = require_cst();
	function isEmpty(ch) {
		switch (ch) {
			case void 0:
			case " ":
			case "\n":
			case "\r":
			case "	": return true;
			default: return false;
		}
	}
	const hexDigits = /* @__PURE__ */ new Set("0123456789ABCDEFabcdef");
	const tagChars = /* @__PURE__ */ new Set("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz-#;/?:@&=+$_.!~*'()");
	const flowIndicatorChars = /* @__PURE__ */ new Set(",[]{}");
	const invalidAnchorChars = /* @__PURE__ */ new Set(" ,[]{}\n\r	");
	const isNotAnchorChar = (ch) => !ch || invalidAnchorChars.has(ch);
	/**
	* Splits an input string into lexical tokens, i.e. smaller strings that are
	* easily identifiable by `tokens.tokenType()`.
	*
	* Lexing starts always in a "stream" context. Incomplete input may be buffered
	* until a complete token can be emitted.
	*
	* In addition to slices of the original input, the following control characters
	* may also be emitted:
	*
	* - `\x02` (Start of Text): A document starts with the next token
	* - `\x18` (Cancel): Unexpected end of flow-mode (indicates an error)
	* - `\x1f` (Unit Separator): Next token is a scalar value
	* - `\u{FEFF}` (Byte order mark): Emitted separately outside documents
	*/
	var Lexer = class {
		constructor() {
			/**
			* Flag indicating whether the end of the current buffer marks the end of
			* all input
			*/
			this.atEnd = false;
			/**
			* Explicit indent set in block scalar header, as an offset from the current
			* minimum indent, so e.g. set to 1 from a header `|2+`. Set to -1 if not
			* explicitly set.
			*/
			this.blockScalarIndent = -1;
			/**
			* Block scalars that include a + (keep) chomping indicator in their header
			* include trailing empty lines, which are otherwise excluded from the
			* scalar's contents.
			*/
			this.blockScalarKeep = false;
			/** Current input */
			this.buffer = "";
			/**
			* Flag noting whether the map value indicator : can immediately follow this
			* node within a flow context.
			*/
			this.flowKey = false;
			/** Count of surrounding flow collection levels. */
			this.flowLevel = 0;
			/**
			* Minimum level of indentation required for next lines to be parsed as a
			* part of the current scalar value.
			*/
			this.indentNext = 0;
			/** Indentation level of the current line. */
			this.indentValue = 0;
			/** Position of the next \n character. */
			this.lineEndPos = null;
			/** Stores the state of the lexer if reaching the end of incpomplete input */
			this.next = null;
			/** A pointer to `buffer`; the current position of the lexer. */
			this.pos = 0;
		}
		/**
		* Generate YAML tokens from the `source` string. If `incomplete`,
		* a part of the last line may be left as a buffer for the next call.
		*
		* @returns A generator of lexical tokens
		*/
		*lex(source, incomplete = false) {
			if (source) {
				if (typeof source !== "string") throw TypeError("source is not a string");
				this.buffer = this.buffer ? this.buffer + source : source;
				this.lineEndPos = null;
			}
			this.atEnd = !incomplete;
			let next = this.next ?? "stream";
			while (next && (incomplete || this.hasChars(1))) next = yield* this.parseNext(next);
		}
		atLineEnd() {
			let i = this.pos;
			let ch = this.buffer[i];
			while (ch === " " || ch === "	") ch = this.buffer[++i];
			if (!ch || ch === "#" || ch === "\n") return true;
			if (ch === "\r") return this.buffer[i + 1] === "\n";
			return false;
		}
		charAt(n) {
			return this.buffer[this.pos + n];
		}
		continueScalar(offset) {
			let ch = this.buffer[offset];
			if (this.indentNext > 0) {
				let indent = 0;
				while (ch === " ") ch = this.buffer[++indent + offset];
				if (ch === "\r") {
					const next = this.buffer[indent + offset + 1];
					if (next === "\n" || !next && !this.atEnd) return offset + indent + 1;
				}
				return ch === "\n" || indent >= this.indentNext || !ch && !this.atEnd ? offset + indent : -1;
			}
			if (ch === "-" || ch === ".") {
				const dt = this.buffer.substr(offset, 3);
				if ((dt === "---" || dt === "...") && isEmpty(this.buffer[offset + 3])) return -1;
			}
			return offset;
		}
		getLine() {
			let end = this.lineEndPos;
			if (typeof end !== "number" || end !== -1 && end < this.pos) {
				end = this.buffer.indexOf("\n", this.pos);
				this.lineEndPos = end;
			}
			if (end === -1) return this.atEnd ? this.buffer.substring(this.pos) : null;
			if (this.buffer[end - 1] === "\r") end -= 1;
			return this.buffer.substring(this.pos, end);
		}
		hasChars(n) {
			return this.pos + n <= this.buffer.length;
		}
		setNext(state) {
			this.buffer = this.buffer.substring(this.pos);
			this.pos = 0;
			this.lineEndPos = null;
			this.next = state;
			return null;
		}
		peek(n) {
			return this.buffer.substr(this.pos, n);
		}
		*parseNext(next) {
			switch (next) {
				case "stream": return yield* this.parseStream();
				case "line-start": return yield* this.parseLineStart();
				case "block-start": return yield* this.parseBlockStart();
				case "doc": return yield* this.parseDocument();
				case "flow": return yield* this.parseFlowCollection();
				case "quoted-scalar": return yield* this.parseQuotedScalar();
				case "block-scalar": return yield* this.parseBlockScalar();
				case "plain-scalar": return yield* this.parsePlainScalar();
			}
		}
		*parseStream() {
			let line = this.getLine();
			if (line === null) return this.setNext("stream");
			if (line[0] === cst.BOM) {
				yield* this.pushCount(1);
				line = line.substring(1);
			}
			if (line[0] === "%") {
				let dirEnd = line.length;
				let cs = line.indexOf("#");
				while (cs !== -1) {
					const ch = line[cs - 1];
					if (ch === " " || ch === "	") {
						dirEnd = cs - 1;
						break;
					} else cs = line.indexOf("#", cs + 1);
				}
				while (true) {
					const ch = line[dirEnd - 1];
					if (ch === " " || ch === "	") dirEnd -= 1;
					else break;
				}
				const n = (yield* this.pushCount(dirEnd)) + (yield* this.pushSpaces(true));
				yield* this.pushCount(line.length - n);
				this.pushNewline();
				return "stream";
			}
			if (this.atLineEnd()) {
				const sp = yield* this.pushSpaces(true);
				yield* this.pushCount(line.length - sp);
				yield* this.pushNewline();
				return "stream";
			}
			yield cst.DOCUMENT;
			return yield* this.parseLineStart();
		}
		*parseLineStart() {
			const ch = this.charAt(0);
			if (!ch && !this.atEnd) return this.setNext("line-start");
			if (ch === "-" || ch === ".") {
				if (!this.atEnd && !this.hasChars(4)) return this.setNext("line-start");
				const s = this.peek(3);
				if ((s === "---" || s === "...") && isEmpty(this.charAt(3))) {
					yield* this.pushCount(3);
					this.indentValue = 0;
					this.indentNext = 0;
					return s === "---" ? "doc" : "stream";
				}
			}
			this.indentValue = yield* this.pushSpaces(false);
			if (this.indentNext > this.indentValue && !isEmpty(this.charAt(1))) this.indentNext = this.indentValue;
			return yield* this.parseBlockStart();
		}
		*parseBlockStart() {
			const [ch0, ch1] = this.peek(2);
			if (!ch1 && !this.atEnd) return this.setNext("block-start");
			if ((ch0 === "-" || ch0 === "?" || ch0 === ":") && isEmpty(ch1)) {
				const n = (yield* this.pushCount(1)) + (yield* this.pushSpaces(true));
				this.indentNext = this.indentValue + 1;
				this.indentValue += n;
				return "block-start";
			}
			return "doc";
		}
		*parseDocument() {
			yield* this.pushSpaces(true);
			const line = this.getLine();
			if (line === null) return this.setNext("doc");
			let n = yield* this.pushIndicators();
			switch (line[n]) {
				case "#": yield* this.pushCount(line.length - n);
				case void 0:
					yield* this.pushNewline();
					return yield* this.parseLineStart();
				case "{":
				case "[":
					yield* this.pushCount(1);
					this.flowKey = false;
					this.flowLevel = 1;
					return "flow";
				case "}":
				case "]":
					yield* this.pushCount(1);
					return "doc";
				case "*":
					yield* this.pushUntil(isNotAnchorChar);
					return "doc";
				case "\"":
				case "'": return yield* this.parseQuotedScalar();
				case "|":
				case ">":
					n += yield* this.parseBlockScalarHeader();
					n += yield* this.pushSpaces(true);
					yield* this.pushCount(line.length - n);
					yield* this.pushNewline();
					return yield* this.parseBlockScalar();
				default: return yield* this.parsePlainScalar();
			}
		}
		*parseFlowCollection() {
			let nl, sp;
			let indent = -1;
			do {
				nl = yield* this.pushNewline();
				if (nl > 0) {
					sp = yield* this.pushSpaces(false);
					this.indentValue = indent = sp;
				} else sp = 0;
				sp += yield* this.pushSpaces(true);
			} while (nl + sp > 0);
			const line = this.getLine();
			if (line === null) return this.setNext("flow");
			if (indent !== -1 && indent < this.indentNext && line[0] !== "#" || indent === 0 && (line.startsWith("---") || line.startsWith("...")) && isEmpty(line[3])) {
				if (!(indent === this.indentNext - 1 && this.flowLevel === 1 && (line[0] === "]" || line[0] === "}"))) {
					this.flowLevel = 0;
					yield cst.FLOW_END;
					return yield* this.parseLineStart();
				}
			}
			let n = 0;
			while (line[n] === ",") {
				n += yield* this.pushCount(1);
				n += yield* this.pushSpaces(true);
				this.flowKey = false;
			}
			n += yield* this.pushIndicators();
			switch (line[n]) {
				case void 0: return "flow";
				case "#":
					yield* this.pushCount(line.length - n);
					return "flow";
				case "{":
				case "[":
					yield* this.pushCount(1);
					this.flowKey = false;
					this.flowLevel += 1;
					return "flow";
				case "}":
				case "]":
					yield* this.pushCount(1);
					this.flowKey = true;
					this.flowLevel -= 1;
					return this.flowLevel ? "flow" : "doc";
				case "*":
					yield* this.pushUntil(isNotAnchorChar);
					return "flow";
				case "\"":
				case "'":
					this.flowKey = true;
					return yield* this.parseQuotedScalar();
				case ":": {
					const next = this.charAt(1);
					if (this.flowKey || isEmpty(next) || next === ",") {
						this.flowKey = false;
						yield* this.pushCount(1);
						yield* this.pushSpaces(true);
						return "flow";
					}
				}
				default:
					this.flowKey = false;
					return yield* this.parsePlainScalar();
			}
		}
		*parseQuotedScalar() {
			const quote = this.charAt(0);
			let end = this.buffer.indexOf(quote, this.pos + 1);
			if (quote === "'") while (end !== -1 && this.buffer[end + 1] === "'") end = this.buffer.indexOf("'", end + 2);
			else while (end !== -1) {
				let n = 0;
				while (this.buffer[end - 1 - n] === "\\") n += 1;
				if (n % 2 === 0) break;
				end = this.buffer.indexOf("\"", end + 1);
			}
			const qb = this.buffer.substring(0, end);
			let nl = qb.indexOf("\n", this.pos);
			if (nl !== -1) {
				while (nl !== -1) {
					const cs = this.continueScalar(nl + 1);
					if (cs === -1) break;
					nl = qb.indexOf("\n", cs);
				}
				if (nl !== -1) end = nl - (qb[nl - 1] === "\r" ? 2 : 1);
			}
			if (end === -1) {
				if (!this.atEnd) return this.setNext("quoted-scalar");
				end = this.buffer.length;
			}
			yield* this.pushToIndex(end + 1, false);
			return this.flowLevel ? "flow" : "doc";
		}
		*parseBlockScalarHeader() {
			this.blockScalarIndent = -1;
			this.blockScalarKeep = false;
			let i = this.pos;
			while (true) {
				const ch = this.buffer[++i];
				if (ch === "+") this.blockScalarKeep = true;
				else if (ch > "0" && ch <= "9") this.blockScalarIndent = Number(ch) - 1;
				else if (ch !== "-") break;
			}
			return yield* this.pushUntil((ch) => isEmpty(ch) || ch === "#");
		}
		*parseBlockScalar() {
			let nl = this.pos - 1;
			let indent = 0;
			let ch;
			loop: for (let i = this.pos; ch = this.buffer[i]; ++i) switch (ch) {
				case " ":
					indent += 1;
					break;
				case "\n":
					nl = i;
					indent = 0;
					break;
				case "\r": {
					const next = this.buffer[i + 1];
					if (!next && !this.atEnd) return this.setNext("block-scalar");
					if (next === "\n") break;
				}
				default: break loop;
			}
			if (!ch && !this.atEnd) return this.setNext("block-scalar");
			if (indent >= this.indentNext) {
				if (this.blockScalarIndent === -1) this.indentNext = indent;
				else this.indentNext = this.blockScalarIndent + (this.indentNext === 0 ? 1 : this.indentNext);
				do {
					const cs = this.continueScalar(nl + 1);
					if (cs === -1) break;
					nl = this.buffer.indexOf("\n", cs);
				} while (nl !== -1);
				if (nl === -1) {
					if (!this.atEnd) return this.setNext("block-scalar");
					nl = this.buffer.length;
				}
			}
			let i = nl + 1;
			ch = this.buffer[i];
			while (ch === " ") ch = this.buffer[++i];
			if (ch === "	") {
				while (ch === "	" || ch === " " || ch === "\r" || ch === "\n") ch = this.buffer[++i];
				nl = i - 1;
			} else if (!this.blockScalarKeep) do {
				let i = nl - 1;
				let ch = this.buffer[i];
				if (ch === "\r") ch = this.buffer[--i];
				const lastChar = i;
				while (ch === " ") ch = this.buffer[--i];
				if (ch === "\n" && i >= this.pos && i + 1 + indent > lastChar) nl = i;
				else break;
			} while (true);
			yield cst.SCALAR;
			yield* this.pushToIndex(nl + 1, true);
			return yield* this.parseLineStart();
		}
		*parsePlainScalar() {
			const inFlow = this.flowLevel > 0;
			let end = this.pos - 1;
			let i = this.pos - 1;
			let ch;
			while (ch = this.buffer[++i]) if (ch === ":") {
				const next = this.buffer[i + 1];
				if (isEmpty(next) || inFlow && flowIndicatorChars.has(next)) break;
				end = i;
			} else if (isEmpty(ch)) {
				let next = this.buffer[i + 1];
				if (ch === "\r") {
					if (next === "\n") {
						i += 1;
						ch = "\n";
						next = this.buffer[i + 1];
					} else end = i;
				}
				if (next === "#" || inFlow && flowIndicatorChars.has(next)) break;
				if (ch === "\n") {
					const cs = this.continueScalar(i + 1);
					if (cs === -1) break;
					i = Math.max(i, cs - 2);
				}
			} else {
				if (inFlow && flowIndicatorChars.has(ch)) break;
				end = i;
			}
			if (!ch && !this.atEnd) return this.setNext("plain-scalar");
			yield cst.SCALAR;
			yield* this.pushToIndex(end + 1, true);
			return inFlow ? "flow" : "doc";
		}
		*pushCount(n) {
			if (n > 0) {
				yield this.buffer.substr(this.pos, n);
				this.pos += n;
				return n;
			}
			return 0;
		}
		*pushToIndex(i, allowEmpty) {
			const s = this.buffer.slice(this.pos, i);
			if (s) {
				yield s;
				this.pos += s.length;
				return s.length;
			} else if (allowEmpty) yield "";
			return 0;
		}
		*pushIndicators() {
			let n = 0;
			loop: while (true) {
				switch (this.charAt(0)) {
					case "!":
						n += yield* this.pushTag();
						n += yield* this.pushSpaces(true);
						continue loop;
					case "&":
						n += yield* this.pushUntil(isNotAnchorChar);
						n += yield* this.pushSpaces(true);
						continue loop;
					case "-":
					case "?":
					case ":": {
						const inFlow = this.flowLevel > 0;
						const ch1 = this.charAt(1);
						if (isEmpty(ch1) || inFlow && flowIndicatorChars.has(ch1)) {
							if (!inFlow) this.indentNext = this.indentValue + 1;
							else if (this.flowKey) this.flowKey = false;
							n += yield* this.pushCount(1);
							n += yield* this.pushSpaces(true);
							continue loop;
						}
					}
				}
				break loop;
			}
			return n;
		}
		*pushTag() {
			if (this.charAt(1) === "<") {
				let i = this.pos + 2;
				let ch = this.buffer[i];
				while (!isEmpty(ch) && ch !== ">") ch = this.buffer[++i];
				return yield* this.pushToIndex(ch === ">" ? i + 1 : i, false);
			} else {
				let i = this.pos + 1;
				let ch = this.buffer[i];
				while (ch) if (tagChars.has(ch)) ch = this.buffer[++i];
				else if (ch === "%" && hexDigits.has(this.buffer[i + 1]) && hexDigits.has(this.buffer[i + 2])) ch = this.buffer[i += 3];
				else break;
				return yield* this.pushToIndex(i, false);
			}
		}
		*pushNewline() {
			const ch = this.buffer[this.pos];
			if (ch === "\n") return yield* this.pushCount(1);
			else if (ch === "\r" && this.charAt(1) === "\n") return yield* this.pushCount(2);
			else return 0;
		}
		*pushSpaces(allowTabs) {
			let i = this.pos - 1;
			let ch;
			do
				ch = this.buffer[++i];
			while (ch === " " || allowTabs && ch === "	");
			const n = i - this.pos;
			if (n > 0) {
				yield this.buffer.substr(this.pos, n);
				this.pos = i;
			}
			return n;
		}
		*pushUntil(test) {
			let i = this.pos;
			let ch = this.buffer[i];
			while (!test(ch)) ch = this.buffer[++i];
			return yield* this.pushToIndex(i, false);
		}
	};
	exports.Lexer = Lexer;
}));
//#endregion
//#region node_modules/.pnpm/yaml@2.9.1/node_modules/yaml/dist/parse/line-counter.js
var require_line_counter = /* @__PURE__ */ __commonJSMin(((exports) => {
	/**
	* Tracks newlines during parsing in order to provide an efficient API for
	* determining the one-indexed `{ line, col }` position for any offset
	* within the input.
	*/
	var LineCounter = class {
		constructor() {
			this.lineStarts = [];
			/**
			* Should be called in ascending order. Otherwise, call
			* `lineCounter.lineStarts.sort()` before calling `linePos()`.
			*/
			this.addNewLine = (offset) => this.lineStarts.push(offset);
			/**
			* Performs a binary search and returns the 1-indexed { line, col }
			* position of `offset`. If `line === 0`, `addNewLine` has never been
			* called or `offset` is before the first known newline.
			*/
			this.linePos = (offset) => {
				let low = 0;
				let high = this.lineStarts.length;
				while (low < high) {
					const mid = low + high >> 1;
					if (this.lineStarts[mid] < offset) low = mid + 1;
					else high = mid;
				}
				if (this.lineStarts[low] === offset) return {
					line: low + 1,
					col: 1
				};
				if (low === 0) return {
					line: 0,
					col: offset
				};
				const start = this.lineStarts[low - 1];
				return {
					line: low,
					col: offset - start + 1
				};
			};
		}
	};
	exports.LineCounter = LineCounter;
}));
//#endregion
//#region node_modules/.pnpm/yaml@2.9.1/node_modules/yaml/dist/parse/parser.js
var require_parser = /* @__PURE__ */ __commonJSMin(((exports) => {
	var node_process = __require("process");
	var cst = require_cst();
	var lexer = require_lexer();
	function includesToken(list, type) {
		for (let i = 0; i < list.length; ++i) if (list[i].type === type) return true;
		return false;
	}
	function findNonEmptyIndex(list) {
		for (let i = 0; i < list.length; ++i) switch (list[i].type) {
			case "space":
			case "comment":
			case "newline": break;
			default: return i;
		}
		return -1;
	}
	function isFlowToken(token) {
		switch (token?.type) {
			case "alias":
			case "scalar":
			case "single-quoted-scalar":
			case "double-quoted-scalar":
			case "flow-collection": return true;
			default: return false;
		}
	}
	function getPrevProps(parent) {
		switch (parent.type) {
			case "document": return parent.start;
			case "block-map": {
				const it = parent.items[parent.items.length - 1];
				return it.sep ?? it.start;
			}
			case "block-seq": return parent.items[parent.items.length - 1].start;
			/* istanbul ignore next should not happen */
			default: return [];
		}
	}
	/** Note: May modify input array */
	function getFirstKeyStartProps(prev) {
		if (prev.length === 0) return [];
		let i = prev.length;
		loop: while (--i >= 0) switch (prev[i].type) {
			case "doc-start":
			case "explicit-key-ind":
			case "map-value-ind":
			case "seq-item-ind":
			case "newline": break loop;
		}
		while (prev[++i]?.type === "space");
		return prev.splice(i, prev.length);
	}
	function arrayPushArray(target, source) {
		if (source.length < 1e5) Array.prototype.push.apply(target, source);
		else for (let i = 0; i < source.length; ++i) target.push(source[i]);
	}
	function fixFlowSeqItems(fc) {
		if (fc.start.type === "flow-seq-start") {
			for (const it of fc.items) if (it.sep && !it.value && !includesToken(it.start, "explicit-key-ind") && !includesToken(it.sep, "map-value-ind")) {
				if (it.key) it.value = it.key;
				delete it.key;
				if (isFlowToken(it.value)) {
					if (it.value.end) arrayPushArray(it.value.end, it.sep);
					else it.value.end = it.sep;
				} else arrayPushArray(it.start, it.sep);
				delete it.sep;
			}
		}
	}
	/**
	* A YAML concrete syntax tree (CST) parser
	*
	* ```ts
	* const src: string = ...
	* for (const token of new Parser().parse(src)) {
	*   // token: Token
	* }
	* ```
	*
	* To use the parser with a user-provided lexer:
	*
	* ```ts
	* function* parse(source: string, lexer: Lexer) {
	*   const parser = new Parser()
	*   for (const lexeme of lexer.lex(source))
	*     yield* parser.next(lexeme)
	*   yield* parser.end()
	* }
	*
	* const src: string = ...
	* const lexer = new Lexer()
	* for (const token of parse(src, lexer)) {
	*   // token: Token
	* }
	* ```
	*/
	var Parser = class {
		/**
		* @param onNewLine - If defined, called separately with the start position of
		*   each new line (in `parse()`, including the start of input).
		*/
		constructor(onNewLine) {
			/** If true, space and sequence indicators count as indentation */
			this.atNewLine = true;
			/** If true, next token is a scalar value */
			this.atScalar = false;
			/** Current indentation level */
			this.indent = 0;
			/** Current offset since the start of parsing */
			this.offset = 0;
			/** On the same line with a block map key */
			this.onKeyLine = false;
			/** Top indicates the node that's currently being built */
			this.stack = [];
			/** The source of the current token, set in parse() */
			this.source = "";
			/** The type of the current token, set in parse() */
			this.type = "";
			this.lexer = new lexer.Lexer();
			this.onNewLine = onNewLine;
		}
		/**
		* Parse `source` as a YAML stream.
		* If `incomplete`, a part of the last line may be left as a buffer for the next call.
		*
		* Errors are not thrown, but yielded as `{ type: 'error', message }` tokens.
		*
		* @returns A generator of tokens representing each directive, document, and other structure.
		*/
		*parse(source, incomplete = false) {
			if (this.onNewLine && this.offset === 0) this.onNewLine(0);
			for (const lexeme of this.lexer.lex(source, incomplete)) yield* this.next(lexeme);
			if (!incomplete) yield* this.end();
		}
		/**
		* Advance the parser by the `source` of one lexical token.
		*/
		*next(source) {
			this.source = source;
			if (node_process.env.LOG_TOKENS) console.log("|", cst.prettyToken(source));
			if (this.atScalar) {
				this.atScalar = false;
				yield* this.step();
				this.offset += source.length;
				return;
			}
			const type = cst.tokenType(source);
			if (!type) {
				const message = `Not a YAML token: ${source}`;
				yield* this.pop({
					type: "error",
					offset: this.offset,
					message,
					source
				});
				this.offset += source.length;
			} else if (type === "scalar") {
				this.atNewLine = false;
				this.atScalar = true;
				this.type = "scalar";
			} else {
				this.type = type;
				yield* this.step();
				switch (type) {
					case "newline":
						this.atNewLine = true;
						this.indent = 0;
						if (this.onNewLine) this.onNewLine(this.offset + source.length);
						break;
					case "space":
						if (this.atNewLine && source[0] === " ") this.indent += source.length;
						break;
					case "explicit-key-ind":
					case "map-value-ind":
					case "seq-item-ind":
						if (this.atNewLine) this.indent += source.length;
						break;
					case "doc-mode":
					case "flow-error-end": return;
					default: this.atNewLine = false;
				}
				this.offset += source.length;
			}
		}
		/** Call at end of input to push out any remaining constructions */
		*end() {
			while (this.stack.length > 0) yield* this.pop();
		}
		get sourceToken() {
			return {
				type: this.type,
				offset: this.offset,
				indent: this.indent,
				source: this.source
			};
		}
		*step() {
			const top = this.peek(1);
			if (this.type === "doc-end" && top?.type !== "doc-end") {
				while (this.stack.length > 0) yield* this.pop();
				this.stack.push({
					type: "doc-end",
					offset: this.offset,
					source: this.source
				});
				return;
			}
			if (!top) return yield* this.stream();
			switch (top.type) {
				case "document": return yield* this.document(top);
				case "alias":
				case "scalar":
				case "single-quoted-scalar":
				case "double-quoted-scalar": return yield* this.scalar(top);
				case "block-scalar": return yield* this.blockScalar(top);
				case "block-map": return yield* this.blockMap(top);
				case "block-seq": return yield* this.blockSequence(top);
				case "flow-collection": return yield* this.flowCollection(top);
				case "doc-end": return yield* this.documentEnd(top);
			}
			/* istanbul ignore next should not happen */
			yield* this.pop();
		}
		peek(n) {
			return this.stack[this.stack.length - n];
		}
		*pop(error) {
			const token = error ?? this.stack.pop();
			/* istanbul ignore if should not happen */
			if (!token) yield {
				type: "error",
				offset: this.offset,
				source: "",
				message: "Tried to pop an empty stack"
			};
			else if (this.stack.length === 0) yield token;
			else {
				const top = this.peek(1);
				if (token.type === "block-scalar") token.indent = "indent" in top ? top.indent : 0;
				else if (token.type === "flow-collection" && top.type === "document") token.indent = 0;
				if (token.type === "flow-collection") fixFlowSeqItems(token);
				switch (top.type) {
					case "document":
						top.value = token;
						break;
					case "block-scalar":
						top.props.push(token);
						break;
					case "block-map": {
						const it = top.items[top.items.length - 1];
						if (it.value) {
							top.items.push({
								start: [],
								key: token,
								sep: []
							});
							this.onKeyLine = true;
							return;
						} else if (it.sep) it.value = token;
						else {
							Object.assign(it, {
								key: token,
								sep: []
							});
							this.onKeyLine = !it.explicitKey;
							return;
						}
						break;
					}
					case "block-seq": {
						const it = top.items[top.items.length - 1];
						if (it.value) top.items.push({
							start: [],
							value: token
						});
						else it.value = token;
						break;
					}
					case "flow-collection": {
						const it = top.items[top.items.length - 1];
						if (!it || it.value) top.items.push({
							start: [],
							key: token,
							sep: []
						});
						else if (it.sep) it.value = token;
						else Object.assign(it, {
							key: token,
							sep: []
						});
						return;
					}
					/* istanbul ignore next should not happen */
					default:
						yield* this.pop();
						yield* this.pop(token);
				}
				if ((top.type === "document" || top.type === "block-map" || top.type === "block-seq") && (token.type === "block-map" || token.type === "block-seq")) {
					const last = token.items[token.items.length - 1];
					if (last && !last.sep && !last.value && last.start.length > 0 && findNonEmptyIndex(last.start) === -1 && (token.indent === 0 || last.start.every((st) => st.type !== "comment" || st.indent < token.indent))) {
						if (top.type === "document") top.end = last.start;
						else top.items.push({ start: last.start });
						token.items.splice(-1, 1);
					}
				}
			}
		}
		*stream() {
			switch (this.type) {
				case "directive-line":
					yield {
						type: "directive",
						offset: this.offset,
						source: this.source
					};
					return;
				case "byte-order-mark":
				case "space":
				case "comment":
				case "newline":
					yield this.sourceToken;
					return;
				case "doc-mode":
				case "doc-start": {
					const doc = {
						type: "document",
						offset: this.offset,
						start: []
					};
					if (this.type === "doc-start") doc.start.push(this.sourceToken);
					this.stack.push(doc);
					return;
				}
			}
			yield {
				type: "error",
				offset: this.offset,
				message: `Unexpected ${this.type} token in YAML stream`,
				source: this.source
			};
		}
		*document(doc) {
			if (doc.value) return yield* this.lineEnd(doc);
			switch (this.type) {
				case "doc-start":
					if (findNonEmptyIndex(doc.start) !== -1) {
						yield* this.pop();
						yield* this.step();
					} else doc.start.push(this.sourceToken);
					return;
				case "anchor":
				case "tag":
				case "space":
				case "comment":
				case "newline":
					doc.start.push(this.sourceToken);
					return;
			}
			const bv = this.startBlockValue(doc);
			if (bv) this.stack.push(bv);
			else yield {
				type: "error",
				offset: this.offset,
				message: `Unexpected ${this.type} token in YAML document`,
				source: this.source
			};
		}
		*scalar(scalar) {
			if (this.type === "map-value-ind") {
				const start = getFirstKeyStartProps(getPrevProps(this.peek(2)));
				let sep;
				if (scalar.end) {
					sep = scalar.end;
					sep.push(this.sourceToken);
					delete scalar.end;
				} else sep = [this.sourceToken];
				const map = {
					type: "block-map",
					offset: scalar.offset,
					indent: scalar.indent,
					items: [{
						start,
						key: scalar,
						sep
					}]
				};
				this.onKeyLine = true;
				this.stack[this.stack.length - 1] = map;
			} else yield* this.lineEnd(scalar);
		}
		*blockScalar(scalar) {
			switch (this.type) {
				case "space":
				case "comment":
				case "newline":
					scalar.props.push(this.sourceToken);
					return;
				case "scalar":
					scalar.source = this.source;
					this.atNewLine = true;
					this.indent = 0;
					if (this.onNewLine) {
						let nl = this.source.indexOf("\n") + 1;
						while (nl !== 0) {
							this.onNewLine(this.offset + nl);
							nl = this.source.indexOf("\n", nl) + 1;
						}
					}
					yield* this.pop();
					break;
				/* istanbul ignore next should not happen */
				default:
					yield* this.pop();
					yield* this.step();
			}
		}
		*blockMap(map) {
			const it = map.items[map.items.length - 1];
			switch (this.type) {
				case "newline":
					this.onKeyLine = false;
					if (it.value) {
						const end = "end" in it.value ? it.value.end : void 0;
						if ((Array.isArray(end) ? end[end.length - 1] : void 0)?.type === "comment") end?.push(this.sourceToken);
						else map.items.push({ start: [this.sourceToken] });
					} else if (it.sep) it.sep.push(this.sourceToken);
					else it.start.push(this.sourceToken);
					return;
				case "space":
				case "comment":
					if (it.value) map.items.push({ start: [this.sourceToken] });
					else if (it.sep) it.sep.push(this.sourceToken);
					else {
						if (this.atIndentedComment(it.start, map.indent)) {
							const end = map.items[map.items.length - 2]?.value?.end;
							if (Array.isArray(end)) {
								arrayPushArray(end, it.start);
								end.push(this.sourceToken);
								map.items.pop();
								return;
							}
						}
						it.start.push(this.sourceToken);
					}
					return;
			}
			if (this.indent >= map.indent) {
				const atMapIndent = !this.onKeyLine && this.indent === map.indent;
				const atNextItem = atMapIndent && (it.sep || it.explicitKey) && this.type !== "seq-item-ind";
				let start = [];
				if (atNextItem && it.sep && !it.value) {
					const nl = [];
					for (let i = 0; i < it.sep.length; ++i) {
						const st = it.sep[i];
						switch (st.type) {
							case "newline":
								nl.push(i);
								break;
							case "space": break;
							case "comment":
								if (st.indent > map.indent) nl.length = 0;
								break;
							default: nl.length = 0;
						}
					}
					if (nl.length >= 2) start = it.sep.splice(nl[1]);
				}
				switch (this.type) {
					case "anchor":
					case "tag":
						if (atNextItem || it.value) {
							start.push(this.sourceToken);
							map.items.push({ start });
							this.onKeyLine = true;
						} else if (it.sep) it.sep.push(this.sourceToken);
						else it.start.push(this.sourceToken);
						return;
					case "explicit-key-ind":
						if (!it.sep && !it.explicitKey) {
							it.start.push(this.sourceToken);
							it.explicitKey = true;
						} else if (atNextItem || it.value) {
							start.push(this.sourceToken);
							map.items.push({
								start,
								explicitKey: true
							});
						} else this.stack.push({
							type: "block-map",
							offset: this.offset,
							indent: this.indent,
							items: [{
								start: [this.sourceToken],
								explicitKey: true
							}]
						});
						this.onKeyLine = true;
						return;
					case "map-value-ind":
						if (it.explicitKey) {
							if (!it.sep) {
								if (includesToken(it.start, "newline")) Object.assign(it, {
									key: null,
									sep: [this.sourceToken]
								});
								else {
									const start = getFirstKeyStartProps(it.start);
									this.stack.push({
										type: "block-map",
										offset: this.offset,
										indent: this.indent,
										items: [{
											start,
											key: null,
											sep: [this.sourceToken]
										}]
									});
								}
							} else if (it.value) map.items.push({
								start: [],
								key: null,
								sep: [this.sourceToken]
							});
							else if (includesToken(it.sep, "map-value-ind")) this.stack.push({
								type: "block-map",
								offset: this.offset,
								indent: this.indent,
								items: [{
									start,
									key: null,
									sep: [this.sourceToken]
								}]
							});
							else if (isFlowToken(it.key) && !includesToken(it.sep, "newline")) {
								const start = getFirstKeyStartProps(it.start);
								const key = it.key;
								const sep = it.sep;
								sep.push(this.sourceToken);
								delete it.key;
								delete it.sep;
								this.stack.push({
									type: "block-map",
									offset: this.offset,
									indent: this.indent,
									items: [{
										start,
										key,
										sep
									}]
								});
							} else if (start.length > 0) it.sep = it.sep.concat(start, this.sourceToken);
							else it.sep.push(this.sourceToken);
						} else if (!it.sep) Object.assign(it, {
							key: null,
							sep: [this.sourceToken]
						});
						else if (it.value || atNextItem) map.items.push({
							start,
							key: null,
							sep: [this.sourceToken]
						});
						else if (includesToken(it.sep, "map-value-ind")) this.stack.push({
							type: "block-map",
							offset: this.offset,
							indent: this.indent,
							items: [{
								start: [],
								key: null,
								sep: [this.sourceToken]
							}]
						});
						else it.sep.push(this.sourceToken);
						this.onKeyLine = true;
						return;
					case "alias":
					case "scalar":
					case "single-quoted-scalar":
					case "double-quoted-scalar": {
						const fs = this.flowScalar(this.type);
						if (atNextItem || it.value) {
							map.items.push({
								start,
								key: fs,
								sep: []
							});
							this.onKeyLine = true;
						} else if (it.sep) this.stack.push(fs);
						else {
							Object.assign(it, {
								key: fs,
								sep: []
							});
							this.onKeyLine = true;
						}
						return;
					}
					default: {
						const bv = this.startBlockValue(map);
						if (bv) {
							if (bv.type === "block-seq") {
								if (!it.explicitKey && it.sep && !includesToken(it.sep, "newline")) {
									yield* this.pop({
										type: "error",
										offset: this.offset,
										message: "Unexpected block-seq-ind on same line with key",
										source: this.source
									});
									return;
								}
							} else if (atMapIndent) map.items.push({ start });
							this.stack.push(bv);
							return;
						}
					}
				}
			}
			yield* this.pop();
			yield* this.step();
		}
		*blockSequence(seq) {
			const it = seq.items[seq.items.length - 1];
			switch (this.type) {
				case "newline":
					if (it.value) {
						const end = "end" in it.value ? it.value.end : void 0;
						if ((Array.isArray(end) ? end[end.length - 1] : void 0)?.type === "comment") end?.push(this.sourceToken);
						else seq.items.push({ start: [this.sourceToken] });
					} else it.start.push(this.sourceToken);
					return;
				case "space":
				case "comment":
					if (it.value) seq.items.push({ start: [this.sourceToken] });
					else {
						if (this.atIndentedComment(it.start, seq.indent)) {
							const end = seq.items[seq.items.length - 2]?.value?.end;
							if (Array.isArray(end)) {
								arrayPushArray(end, it.start);
								end.push(this.sourceToken);
								seq.items.pop();
								return;
							}
						}
						it.start.push(this.sourceToken);
					}
					return;
				case "anchor":
				case "tag":
					if (it.value || this.indent <= seq.indent) break;
					it.start.push(this.sourceToken);
					return;
				case "seq-item-ind":
					if (this.indent !== seq.indent) break;
					if (it.value || includesToken(it.start, "seq-item-ind")) seq.items.push({ start: [this.sourceToken] });
					else it.start.push(this.sourceToken);
					return;
			}
			if (this.indent > seq.indent) {
				const bv = this.startBlockValue(seq);
				if (bv) {
					this.stack.push(bv);
					return;
				}
			}
			yield* this.pop();
			yield* this.step();
		}
		*flowCollection(fc) {
			const it = fc.items[fc.items.length - 1];
			if (this.type === "flow-error-end") {
				let top;
				do {
					yield* this.pop();
					top = this.peek(1);
				} while (top?.type === "flow-collection");
			} else if (fc.end.length === 0) {
				switch (this.type) {
					case "comma":
					case "explicit-key-ind":
						if (!it || it.sep) fc.items.push({ start: [this.sourceToken] });
						else it.start.push(this.sourceToken);
						return;
					case "map-value-ind":
						if (!it || it.value) fc.items.push({
							start: [],
							key: null,
							sep: [this.sourceToken]
						});
						else if (it.sep) it.sep.push(this.sourceToken);
						else Object.assign(it, {
							key: null,
							sep: [this.sourceToken]
						});
						return;
					case "space":
					case "comment":
					case "newline":
					case "anchor":
					case "tag":
						if (!it || it.value) fc.items.push({ start: [this.sourceToken] });
						else if (it.sep) it.sep.push(this.sourceToken);
						else it.start.push(this.sourceToken);
						return;
					case "alias":
					case "scalar":
					case "single-quoted-scalar":
					case "double-quoted-scalar": {
						const fs = this.flowScalar(this.type);
						if (!it || it.value) fc.items.push({
							start: [],
							key: fs,
							sep: []
						});
						else if (it.sep) this.stack.push(fs);
						else Object.assign(it, {
							key: fs,
							sep: []
						});
						return;
					}
					case "flow-map-end":
					case "flow-seq-end":
						fc.end.push(this.sourceToken);
						return;
				}
				const bv = this.startBlockValue(fc);
				/* istanbul ignore else should not happen */
				if (bv) this.stack.push(bv);
				else {
					yield* this.pop();
					yield* this.step();
				}
			} else {
				const parent = this.peek(2);
				if (parent.type === "block-map" && (this.type === "map-value-ind" && parent.indent === fc.indent || this.type === "newline" && !parent.items[parent.items.length - 1].sep)) {
					yield* this.pop();
					yield* this.step();
				} else if (this.type === "map-value-ind" && parent.type !== "flow-collection") {
					const start = getFirstKeyStartProps(getPrevProps(parent));
					fixFlowSeqItems(fc);
					const sep = fc.end.splice(1, fc.end.length);
					sep.push(this.sourceToken);
					const map = {
						type: "block-map",
						offset: fc.offset,
						indent: fc.indent,
						items: [{
							start,
							key: fc,
							sep
						}]
					};
					this.onKeyLine = true;
					this.stack[this.stack.length - 1] = map;
				} else yield* this.lineEnd(fc);
			}
		}
		flowScalar(type) {
			if (this.onNewLine) {
				let nl = this.source.indexOf("\n") + 1;
				while (nl !== 0) {
					this.onNewLine(this.offset + nl);
					nl = this.source.indexOf("\n", nl) + 1;
				}
			}
			return {
				type,
				offset: this.offset,
				indent: this.indent,
				source: this.source
			};
		}
		startBlockValue(parent) {
			switch (this.type) {
				case "alias":
				case "scalar":
				case "single-quoted-scalar":
				case "double-quoted-scalar": return this.flowScalar(this.type);
				case "block-scalar-header": return {
					type: "block-scalar",
					offset: this.offset,
					indent: this.indent,
					props: [this.sourceToken],
					source: ""
				};
				case "flow-map-start":
				case "flow-seq-start": return {
					type: "flow-collection",
					offset: this.offset,
					indent: this.indent,
					start: this.sourceToken,
					items: [],
					end: []
				};
				case "seq-item-ind": return {
					type: "block-seq",
					offset: this.offset,
					indent: this.indent,
					items: [{ start: [this.sourceToken] }]
				};
				case "explicit-key-ind": {
					this.onKeyLine = true;
					const start = getFirstKeyStartProps(getPrevProps(parent));
					start.push(this.sourceToken);
					return {
						type: "block-map",
						offset: this.offset,
						indent: this.indent,
						items: [{
							start,
							explicitKey: true
						}]
					};
				}
				case "map-value-ind": {
					this.onKeyLine = true;
					const start = getFirstKeyStartProps(getPrevProps(parent));
					return {
						type: "block-map",
						offset: this.offset,
						indent: this.indent,
						items: [{
							start,
							key: null,
							sep: [this.sourceToken]
						}]
					};
				}
			}
			return null;
		}
		atIndentedComment(start, indent) {
			if (this.type !== "comment") return false;
			if (this.indent <= indent) return false;
			return start.every((st) => st.type === "newline" || st.type === "space");
		}
		*documentEnd(docEnd) {
			if (this.type !== "doc-mode") {
				if (docEnd.end) docEnd.end.push(this.sourceToken);
				else docEnd.end = [this.sourceToken];
				if (this.type === "newline") yield* this.pop();
			}
		}
		*lineEnd(token) {
			switch (this.type) {
				case "comma":
				case "doc-start":
				case "doc-end":
				case "flow-seq-end":
				case "flow-map-end":
				case "map-value-ind":
					yield* this.pop();
					yield* this.step();
					break;
				case "newline": this.onKeyLine = false;
				default:
					if (token.end) token.end.push(this.sourceToken);
					else token.end = [this.sourceToken];
					if (this.type === "newline") yield* this.pop();
			}
		}
	};
	exports.Parser = Parser;
}));
//#endregion
//#region node_modules/.pnpm/yaml@2.9.1/node_modules/yaml/dist/public-api.js
var require_public_api = /* @__PURE__ */ __commonJSMin(((exports) => {
	var composer = require_composer();
	var Document = require_Document();
	var errors = require_errors();
	var log = require_log();
	var identity = require_identity();
	var lineCounter = require_line_counter();
	var parser = require_parser();
	function parseOptions(options) {
		const prettyErrors = options.prettyErrors !== false;
		return {
			lineCounter: options.lineCounter || prettyErrors && new lineCounter.LineCounter() || null,
			prettyErrors
		};
	}
	/**
	* Parse the input as a stream of YAML documents.
	*
	* Documents should be separated from each other by `...` or `---` marker lines.
	*
	* @returns If an empty `docs` array is returned, it will be of type
	*   EmptyStream and contain additional stream information. In
	*   TypeScript, you should use `'empty' in docs` as a type guard for it.
	*/
	function parseAllDocuments(source, options = {}) {
		const { lineCounter, prettyErrors } = parseOptions(options);
		const parser$1 = new parser.Parser(lineCounter?.addNewLine);
		const composer$1 = new composer.Composer(options);
		const docs = Array.from(composer$1.compose(parser$1.parse(source)));
		if (prettyErrors && lineCounter) for (const doc of docs) {
			doc.errors.forEach(errors.prettifyError(source, lineCounter));
			doc.warnings.forEach(errors.prettifyError(source, lineCounter));
		}
		if (docs.length > 0) return docs;
		return Object.assign([], { empty: true }, composer$1.streamInfo());
	}
	/** Parse an input string into a single YAML.Document */
	function parseDocument(source, options = {}) {
		const { lineCounter, prettyErrors } = parseOptions(options);
		const parser$1 = new parser.Parser(lineCounter?.addNewLine);
		const composer$1 = new composer.Composer(options);
		let doc = null;
		for (const _doc of composer$1.compose(parser$1.parse(source), true, source.length)) if (!doc) doc = _doc;
		else if (doc.options.logLevel !== "silent") {
			doc.errors.push(new errors.YAMLParseError(_doc.range.slice(0, 2), "MULTIPLE_DOCS", "Source contains multiple documents; please use YAML.parseAllDocuments()"));
			break;
		}
		if (prettyErrors && lineCounter) {
			doc.errors.forEach(errors.prettifyError(source, lineCounter));
			doc.warnings.forEach(errors.prettifyError(source, lineCounter));
		}
		return doc;
	}
	function parse(src, reviver, options) {
		let _reviver = void 0;
		if (typeof reviver === "function") _reviver = reviver;
		else if (options === void 0 && reviver && typeof reviver === "object") options = reviver;
		const doc = parseDocument(src, options);
		if (!doc) return null;
		doc.warnings.forEach((warning) => log.warn(doc.options.logLevel, warning));
		if (doc.errors.length > 0) {
			if (doc.options.logLevel !== "silent") throw doc.errors[0];
			else doc.errors = [];
		}
		return doc.toJS(Object.assign({ reviver: _reviver }, options));
	}
	function stringify(value, replacer, options) {
		let _replacer = null;
		if (typeof replacer === "function" || Array.isArray(replacer)) _replacer = replacer;
		else if (options === void 0 && replacer) options = replacer;
		if (typeof options === "string") options = options.length;
		if (typeof options === "number") {
			const indent = Math.round(options);
			options = indent < 1 ? void 0 : indent > 8 ? { indent: 8 } : { indent };
		}
		if (value === void 0) {
			const { keepUndefined } = options ?? replacer ?? {};
			if (!keepUndefined) return void 0;
		}
		if (identity.isDocument(value) && !_replacer) return value.toString(options);
		return new Document.Document(value, _replacer, options).toString(options);
	}
	exports.parse = parse;
	exports.parseAllDocuments = parseAllDocuments;
	exports.parseDocument = parseDocument;
	exports.stringify = stringify;
}));
//#endregion
//#region files/config/keybindings/decode.ts
var import_dist = (/* @__PURE__ */ __commonJSMin(((exports) => {
	var composer = require_composer();
	var Document = require_Document();
	var Schema = require_Schema();
	var errors = require_errors();
	var Alias = require_Alias();
	var identity = require_identity();
	var Pair = require_Pair();
	var Scalar = require_Scalar();
	var YAMLMap = require_YAMLMap();
	var YAMLSeq = require_YAMLSeq();
	require_cst();
	var lexer = require_lexer();
	var lineCounter = require_line_counter();
	var parser = require_parser();
	var publicApi = require_public_api();
	var visit = require_visit();
	exports.Composer = composer.Composer;
	exports.Document = Document.Document;
	exports.Schema = Schema.Schema;
	exports.YAMLError = errors.YAMLError;
	exports.YAMLParseError = errors.YAMLParseError;
	exports.YAMLWarning = errors.YAMLWarning;
	exports.Alias = Alias.Alias;
	exports.isAlias = identity.isAlias;
	exports.isCollection = identity.isCollection;
	exports.isDocument = identity.isDocument;
	exports.isMap = identity.isMap;
	exports.isNode = identity.isNode;
	exports.isPair = identity.isPair;
	exports.isScalar = identity.isScalar;
	exports.isSeq = identity.isSeq;
	exports.Pair = Pair.Pair;
	exports.Scalar = Scalar.Scalar;
	exports.YAMLMap = YAMLMap.YAMLMap;
	exports.YAMLSeq = YAMLSeq.YAMLSeq;
	exports.Lexer = lexer.Lexer;
	exports.LineCounter = lineCounter.LineCounter;
	exports.Parser = parser.Parser;
	exports.parse = publicApi.parse;
	exports.parseAllDocuments = publicApi.parseAllDocuments;
	exports.parseDocument = publicApi.parseDocument;
	exports.stringify = publicApi.stringify;
	exports.visit = visit.visit;
	exports.visitAsync = visit.visitAsync;
})))();
const ID = /^[A-Za-z0-9][A-Za-z0-9_.-]*$/;
const NAME = /^[A-Za-z][A-Za-z0-9_-]*$/;
function object(value, label) {
	if (!value || typeof value !== "object" || Array.isArray(value)) throw new Error(`${label}: expected mapping`);
	return value;
}
function known(value, fields, label) {
	const unknown = Object.keys(value).filter((key) => !fields.includes(key));
	if (unknown.length) throw new Error(`${label}: unknown fields ${unknown.join(", ")}`);
}
function text(value, label, empty = false) {
	if (typeof value !== "string" || !empty && !value || value.includes("\0")) throw new Error(`${label}: expected ${empty ? "" : "non-empty "}string without NUL`);
	return value;
}
function id(value, label) {
	const result = text(value, label);
	if (!ID.test(result)) throw new Error(`${label}: invalid identifier ${result}`);
	return result;
}
function bool(value, label) {
	if (typeof value !== "boolean") throw new Error(`${label}: expected boolean`);
	return value;
}
function sequence(value, label) {
	if (!Array.isArray(value)) throw new Error(`${label}: expected sequence`);
	return value;
}
function scalar(value, label) {
	if (typeof value === "string") return text(value, label, true);
	if (typeof value === "boolean" || typeof value === "number" && Number.isFinite(value)) return value;
	throw new Error(`${label}: expected string, boolean or finite number`);
}
function properties(value, label) {
	return Object.fromEntries(Object.entries(object(value, label)).map(([key, entry]) => {
		if (!NAME.test(key)) throw new Error(`${label}: invalid property name ${key}`);
		return [key, scalar(entry, `${label}.${key}`)];
	}));
}
function implementation(value, label, target) {
	const kinds = [
		"exec",
		"script",
		"native"
	].filter((key) => value[key] !== void 0);
	if (kinds.length > 1) throw new Error(`${label}: exec, script and native replace one another; specify only one`);
	if (!kinds.length) return void 0;
	if (kinds[0] === "exec") {
		const argv = sequence(value.exec, `${label}.exec`).map((entry, index) => text(entry, `${label}.exec[${index}]`, index > 0));
		if (!argv.length) throw new Error(`${label}.exec: command argv must not be empty`);
		return {
			kind: "exec",
			argv
		};
	}
	if (kinds[0] === "script") {
		const script = object(value.script, `${label}.script`);
		known(script, ["shell", "body"], `${label}.script`);
		return {
			kind: "script",
			shell: text(script.shell, `${label}.script.shell`),
			body: text(script.body, `${label}.script.body`)
		};
	}
	if (!target) throw new Error(`${label}: native requires a target specifier`);
	if (target === "umbriel") return {
		kind: "umbriel-native",
		value: text(value.native, `${label}.native`)
	};
	const native = object(value.native, `${label}.native`);
	known(native, [
		"name",
		"args",
		"properties"
	], `${label}.native`);
	const name = text(native.name, `${label}.native.name`);
	if (!NAME.test(name)) throw new Error(`${label}.native.name: invalid node name`);
	return {
		kind: "niri-native",
		value: {
			name,
			args: sequence(native.args ?? [], `${label}.native.args`).map((entry) => scalar(entry, `${label}.native.args`)),
			properties: native.properties === void 0 ? {} : properties(native.properties, `${label}.native.properties`)
		}
	};
}
function actionFields(raw, label, target) {
	known(raw, [
		"exec",
		"script",
		"native",
		"enabled"
	], label);
	const result = {};
	const body = implementation(raw, label, target);
	if (body) result.implementation = body;
	if (raw.enabled !== void 0) result.enabled = bool(raw.enabled, `${label}.enabled`);
	return result;
}
function bindingFields(raw, label) {
	known(raw, [
		"action",
		"keys",
		"add-keys",
		"title",
		"options",
		"enabled"
	], label);
	const result = {};
	if (raw.action !== void 0) result.action = id(raw.action, `${label}.action`);
	for (const [field, property] of [["keys", "keys"], ["add-keys", "addKeys"]]) {
		if (raw[field] === void 0) continue;
		result[property] = sequence(raw[field], `${label}.${field}`).map((entry) => {
			const chord = text(entry, `${label}.${field}`);
			if (!/^[A-Za-z0-9_]+(?:\+[A-Za-z0-9_]+)*$/.test(chord)) throw new Error(`${label}.${field}: unsupported chord syntax ${chord}`);
			return chord;
		});
	}
	if (raw.title !== void 0) result.title = text(raw.title, `${label}.title`, true);
	if (raw.options !== void 0) result.options = properties(raw.options, `${label}.options`);
	if (raw.enabled !== void 0) result.enabled = bool(raw.enabled, `${label}.enabled`);
	return result;
}
function decodeContribution(value, source) {
	const { version, kind, id: rawId, patch, niri, umbriel, ...fields } = object(value, source);
	if (version !== 1) throw new Error(`${source}: expected version: 1`);
	const common = {
		id: id(rawId, `${source}.id`),
		patch: patch === void 0 ? false : bool(patch, `${source}.patch`),
		source
	};
	if (kind === "action") return {
		...common,
		kind,
		fields: actionFields(fields, source),
		targets: {
			...niri === void 0 ? {} : { niri: actionFields(object(niri, `${source}.niri`), `${source}.niri`, "niri") },
			...umbriel === void 0 ? {} : { umbriel: actionFields(object(umbriel, `${source}.umbriel`), `${source}.umbriel`, "umbriel") }
		}
	};
	if (kind !== "keybinding") throw new Error(`${source}: kind must be action or keybinding`);
	return {
		...common,
		kind,
		fields: bindingFields(fields, source),
		targets: {
			...niri === void 0 ? {} : { niri: bindingFields(object(niri, `${source}.niri`), `${source}.niri`) },
			...umbriel === void 0 ? {} : { umbriel: bindingFields(object(umbriel, `${source}.umbriel`), `${source}.umbriel`) }
		}
	};
}
function decodeYaml(text, source) {
	const document = (0, import_dist.parseDocument)(text, {
		uniqueKeys: true,
		schema: "core"
	});
	if (document.errors.length) throw new Error(`${source}: ${document.errors.map((error) => error.message).join("; ")}`);
	if (document.warnings.length) throw new Error(`${source}: unsupported YAML syntax: ${document.warnings.map((warning) => warning.message).join("; ")}`);
	return decodeContribution(document.toJS({ maxAliasCount: 0 }), source);
}
//#endregion
//#region files/config/keybindings/model.ts
function mergeBinding(base, patch) {
	const { addKeys, ...replacement } = patch;
	return {
		...base,
		...replacement,
		keys: patch.keys ?? base.keys,
		addKeys: [...patch.keys === void 0 ? base.addKeys ?? [] : [], ...addKeys ?? []],
		options: {
			...base.options,
			...patch.options
		}
	};
}
/** Only modifier ordering/case is normalized, not target-dependent Mod resolution
* or XKB key aliases. Native whole-root validation remains necessary. */
function chordIdentity(chord) {
	const tokens = chord.split("+");
	const key = tokens.pop();
	return [...tokens.map((token) => token.toLowerCase()).sort(), key].join("+");
}
function compose(contributions, target) {
	const actions = /* @__PURE__ */ new Map();
	const bindings = /* @__PURE__ */ new Map();
	for (const contribution of contributions) {
		const prior = (contribution.kind === "action" ? actions : bindings).get(contribution.id);
		if (contribution.patch && !prior) throw new Error(`${contribution.source}: patch has no ${contribution.kind} ${contribution.id}`);
		if (!contribution.patch && prior) throw new Error(`${contribution.source}: duplicate ${contribution.kind} ${contribution.id}; use patch: true`);
		const sources = [...prior?.sources ?? [], contribution.source];
		if (contribution.kind === "action") {
			const fields = {
				...contribution.fields,
				...contribution.targets[target]
			};
			actions.set(contribution.id, {
				fields: {
					...actions.get(contribution.id)?.fields,
					...fields
				},
				sources
			});
		} else {
			const fields = mergeBinding(contribution.fields, contribution.targets[target] ?? {});
			bindings.set(contribution.id, {
				fields: mergeBinding(bindings.get(contribution.id)?.fields ?? {}, fields),
				sources
			});
		}
	}
	const effectiveActions = [];
	for (const [id, { fields, sources }] of actions) {
		if (fields.enabled === false) continue;
		if (!fields.implementation) continue;
		if (fields.implementation.kind.endsWith("native") && fields.implementation.kind !== `${target}-native`) throw new Error(`action ${id}: native implementation does not support ${target}`);
		effectiveActions.push({
			id,
			implementation: fields.implementation,
			sources
		});
	}
	const resolved = [];
	const chords = /* @__PURE__ */ new Map();
	for (const [id, { fields, sources }] of bindings) {
		if (fields.enabled === false) continue;
		const action = effectiveActions.find((entry) => entry.id === fields.action);
		if (!action) throw new Error(`keybinding ${id}: unresolved action ${String(fields.action)} (${sources.join(", ")})`);
		if (!fields.keys) throw new Error(`keybinding ${id}: keys are required; use keys: [] to suppress target bindings`);
		const keys = [];
		const local = /* @__PURE__ */ new Set();
		for (const key of [...fields.keys, ...fields.addKeys ?? []]) {
			const identity = chordIdentity(key);
			if (local.has(identity)) continue;
			local.add(identity);
			const owner = chords.get(identity);
			if (owner) throw new Error(`${target}: chord ${key} is shared by ${owner} and ${id}`);
			chords.set(identity, id);
			keys.push(key);
		}
		resolved.push({
			id,
			action,
			keys,
			title: fields.title,
			options: fields.options ?? {},
			sources
		});
	}
	return {
		target,
		actions: effectiveActions,
		bindings: resolved
	};
}
//#endregion
//#region files/config/keybindings/render.ts
function shellQuote(value) {
	return `'${value.replaceAll("'", `'"'"'`)}'`;
}
function kdlString(value) {
	return "\"" + value.replace(/["\\\u0000-\u001f\u007f]/g, (character) => {
		if (character === "\"" || character === "\\") return "\\" + character;
		if (character === "\n") return "\\n";
		if (character === "\r") return "\\r";
		if (character === "	") return "\\t";
		const code = character.codePointAt(0);
		return code < 32 || code === 127 ? `\\u{${code.toString(16)}}` : character;
	}) + "\"";
}
function kdlScalar(value) {
	return typeof value === "string" ? kdlString(value) : String(value);
}
function kdlProperties(properties) {
	return Object.entries(properties).map(([key, value]) => ` ${key}=${kdlScalar(value)}`).join("");
}
function niriAction(implementation) {
	if (implementation.kind === "exec") return `spawn ${implementation.argv.map(kdlString).join(" ")};`;
	if (implementation.kind === "script") return `spawn ${[
		implementation.shell,
		"-c",
		implementation.body
	].map(kdlString).join(" ")};`;
	if (implementation.kind === "umbriel-native") throw new Error("Umbriel native action cannot render for Niri");
	const { name, args, properties } = implementation.value;
	return `${name}${args.map((value) => " " + kdlScalar(value)).join("")}${kdlProperties(properties)};`;
}
function umbrielAction(implementation) {
	if (implementation.kind === "umbriel-native") return implementation.value;
	if (implementation.kind === "niri-native") throw new Error("Niri native action cannot render for Umbriel");
	return "spawn:" + (implementation.kind === "exec" ? implementation.argv : [
		implementation.shell,
		"-c",
		implementation.body
	]).map(shellQuote).join(" ");
}
function renderDefinition(binding, target) {
	if (target === "niri") {
		const options = {
			...binding.title === void 0 ? {} : { "hotkey-overlay-title": binding.title },
			...binding.options
		};
		return `binds {\n${binding.keys.map((key) => `  ${kdlString(key)}${kdlProperties(options)} { ${niriAction(binding.action.implementation)} }\n`).join("")}\n}\n`;
	}
	const action = JSON.stringify(umbrielAction(binding.action.implementation));
	const options = Object.entries(binding.options).map(([key, value]) => `${JSON.stringify(key)} = ${JSON.stringify(value)}`);
	if ("action" in binding.options) throw new Error(`keybinding ${binding.id}: options.action would replace resolved action`);
	const value = options.length ? `{ action = ${action}, ${options.join(", ")} }` : action;
	return `[keybinds]\n${binding.keys.map((key) => `${JSON.stringify(key)} = ${value}\n`).join("")}`;
}
/** Umbriel incorporation is an ARRAY ENTRY, deliberately not standalone TOML. */
function renderInclude(target, effectivePath) {
	if (!effectivePath || /[\0\r\n\t]/.test(effectivePath)) throw new Error("include path must be non-empty without NUL/newlines");
	return target === "niri" ? `include ${kdlString(effectivePath)}\n` : `${JSON.stringify(effectivePath)},\n`;
}
//#endregion
//#region files/config/keybindings/processor.ts
/** Current CONFIG adapter: capture selected inputs and write ONE private candidate. */
function required(value, label) {
	if (!value) throw new Error(`${label} is required; use CONFIG assembly, not a direct internal leaf`);
	return value;
}
async function runProcessor(argv, environment) {
	const { values } = parseArgs({
		args: argv,
		strict: true,
		allowPositionals: false,
		options: {
			config: { type: "string" },
			target: { type: "string" },
			binding: { type: "string" },
			material: { type: "string" }
		}
	});
	const name = required(values.config, "--config");
	if (values.target !== "niri" && values.target !== "umbriel") throw new Error("--target must be niri or umbriel");
	const target = values.target;
	if (values.material !== "definition" && values.material !== "include") throw new Error("--material must be definition or include");
	required(environment.CONFIG_TRANSACTION, "CONFIG_TRANSACTION");
	const candidate = required(environment.CONFIG_CANDIDATE, "CONFIG_CANDIDATE");
	const [specText, manifest] = await Promise.all([readFile(required(environment.CONFIG_SPEC, "CONFIG_SPEC"), "utf8"), readFile(required(environment.CONFIG_INPUTS_FILE, "CONFIG_INPUTS_FILE"), "utf8")]);
	const spec = JSON.parse(specText);
	if (!spec.configs || !Object.hasOwn(spec.configs, name)) throw new Error(`unknown config ${name}`);
	const rows = manifest.split("\n").filter(Boolean).map((row) => {
		const columns = row.split("	");
		if (columns.length !== 4 || !columns[1] || !columns[2]) throw new Error("invalid CONFIG input manifest row");
		return {
			identity: columns[1],
			path: columns[2]
		};
	});
	let text;
	if (values.material === "include") {
		if (values.binding !== void 0) throw new Error("include material does not accept --binding");
		if (rows.length !== 1) throw new Error("include material requires exactly one explicit native file input");
		text = renderInclude(target, rows[0].path);
	} else {
		const binding = required(values.binding, "--binding");
		const resolved = compose(await Promise.all(rows.map(async (row) => decodeYaml(await readFile(row.path, "utf8"), `${row.identity} (${row.path})`))), target).bindings.find((entry) => entry.id === binding);
		if (!resolved) throw new Error(`unknown or disabled keybinding ${binding}`);
		text = renderDefinition(resolved, target);
	}
	await writeFile(candidate, text);
}
//#endregion
//#region files/runtime/compfuzor-runtime.ts
/** Minimal multicall entry for Compfuzor's domain-grouped JavaScript runtimes. */
const RUNTIME_NAME = "compfuzor-runtime.mjs";
const RUNTIME_SOURCE_NAME = "compfuzor-runtime.ts";
const USAGE = `Usage: compfuzor-runtime.mjs <catalog|config|config-remote|flow|links|zim|keybindings> ...

Ordinary deployments invoke this multicall runtime through stable domain
aliases such as config/command.mjs, config-remote.mjs, links.mjs, and
zim/install.mjs.`;
function fail(message) {
	throw new Error(message);
}
function classifyCandidate(path) {
	const name = basename(path);
	if (name === "compfuzor-catalog.sh") return "catalog";
	if (name === "compfuzor-flow.sh") return "flow";
	if (name === "config-remote.mjs") return "config-remote";
	if (name === "keybinding-processor.mjs") return "keybindings";
	if (name === "links.mjs") return "links";
	if (name === "command.mjs" && basename(dirname(path)) === "config") return "config";
	if (name === "install.mjs" && basename(dirname(path)) === "zim") return "zim";
	if (name.startsWith("config-") && name.endsWith(".sh")) return "config";
}
async function invocationChain(argvPath) {
	const chain = [resolve(argvPath)];
	const seen = new Set(chain);
	for (let depth = 0; depth < 64; depth++) {
		const current = chain.at(-1);
		let target;
		try {
			target = await readlink(current);
		} catch (error) {
			const code = error.code;
			if (code === "EINVAL" || code === "ENOENT") return chain;
			throw error;
		}
		const next = resolve(dirname(current), target);
		if (seen.has(next)) fail(`cyclic runtime command symlink: ${argvPath}`);
		chain.push(next);
		seen.add(next);
	}
	fail(`runtime command symlink chain is too deep: ${argvPath}`);
}
async function selectedDomain(argvPath, argv) {
	const chain = await invocationChain(argvPath);
	for (const candidate of chain) {
		const domain = classifyCandidate(candidate);
		if (domain) return {
			domain,
			argv,
			invokedAs: basename(argvPath)
		};
	}
	if (basename(argvPath) !== RUNTIME_NAME && basename(argvPath) !== RUNTIME_SOURCE_NAME) fail(`unknown Compfuzor runtime alias: ${basename(argvPath)}\n${USAGE}`);
	const [domain, ...domainArgv] = argv;
	if (domain !== "catalog" && domain !== "config" && domain !== "config-remote" && domain !== "flow" && domain !== "links" && domain !== "zim" && domain !== "keybindings") fail(USAGE);
	return {
		domain,
		argv: domainArgv,
		invokedAs: domain === "config" ? "command.ts" : RUNTIME_NAME
	};
}
async function runDomain(domain, argv, invokedAs, deploymentDir) {
	try {
		if (domain === "catalog") return await main$4(argv, deploymentDir);
		if (domain === "flow") return await main$3(argv, deploymentDir);
		if (domain === "config") return await main$6(argv, deploymentDir, invokedAs);
		if (domain === "links") return await main$2(argv, deploymentDir);
		if (domain === "zim") return await main$1(argv, deploymentDir);
		if (domain === "keybindings") {
			await runProcessor(argv, process.env);
			return 0;
		}
		await main$5(argv, deploymentDir);
		return 0;
	} catch (error) {
		if (domain === "config-remote") {
			console.error(`error: ${error instanceof Error ? error.message : String(error)}`);
			return 1;
		}
		console.error(error instanceof Error ? error.stack : String(error));
		return 2;
	}
}
function deploymentDirectory(realModulePath) {
	return realModulePath.endsWith(".ts") ? resolve(dirname(realModulePath), "../..") : resolve(dirname(realModulePath), "..");
}
async function main(argv = process.argv.slice(2), argvPath = process.argv[1], modulePath = fileURLToPath(import.meta.url)) {
	if (!argvPath) fail(USAGE);
	const [selection, realModulePath] = await Promise.all([selectedDomain(argvPath, argv), realpath(modulePath)]);
	return runDomain(selection.domain, selection.argv, selection.invokedAs, deploymentDirectory(realModulePath));
}
const argvPath = process.argv[1];
if (argvPath) Promise.all([realpath(argvPath), realpath(fileURLToPath(import.meta.url))]).then(([realArgvPath, realModulePath]) => {
	if (realArgvPath !== realModulePath) return;
	return main(process.argv.slice(2), argvPath, realModulePath).then((code) => {
		process.exitCode = code;
	}, (error) => {
		console.error(error instanceof Error ? error.stack : String(error));
		process.exitCode = 2;
	});
}, (error) => {
	console.error(error instanceof Error ? error.stack : String(error));
	process.exitCode = 2;
});
//#endregion
export { main };
