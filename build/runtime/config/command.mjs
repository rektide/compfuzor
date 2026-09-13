#!/usr/bin/env -S node --disable-warning=MODULE_TYPELESS_PACKAGE_JSON
import { chmod, copyFile, lstat, mkdir, mkdtemp, readFile, readdir, readlink, realpath, rename, rm, stat, symlink, writeFile } from "node:fs/promises";
import { basename, dirname, isAbsolute, join, matchesGlob, normalize, relative, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { spawn } from "node:child_process";
import { constants, tmpdir } from "node:os";
import { parseArgs } from "node:util";
//#region files/config/context.ts
/** Import-safe consumer-context selection and path binding for CONFIGS specs. */
function fail$5(message) {
	throw new Error(message);
}
function object$1(value, label) {
	if (!value || typeof value !== "object" || Array.isArray(value)) fail$5(`${label} must be an object`);
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
function expandPath(value, base, label) {
	let expanded = value;
	if (value === "~" || value.startsWith("~/")) {
		const home = knownRoot("HOME") ?? fail$5(`${label}: HOME is required to expand ${value}`);
		if (value.slice(1).includes("$") || value.slice(1).includes("~")) fail$5(`${label}: unsupported runtime-root expression: ${value}`);
		expanded = home + value.slice(1);
	} else if (value.startsWith("${")) {
		const match = /^\$\{(HOME|XDG_CONFIG_HOME|XDG_STATE_HOME|XDG_CACHE_HOME|XDG_DATA_HOME)\}(?:\/|$)/.exec(value);
		if (!match) fail$5(`${label}: unsupported runtime-root expression: ${value}`);
		const root = knownRoot(match[1]) ?? fail$5(`${label}: ${match[1]} or HOME is required to expand ${value}`);
		const suffix = value.slice(match[0].length - (match[0].endsWith("/") ? 1 : 0));
		if (suffix.includes("$") || suffix.includes("~")) fail$5(`${label}: unsupported runtime-root expression: ${value}`);
		expanded = root + suffix;
	} else if (value.includes("$") || value.includes("~")) fail$5(`${label}: unsupported runtime-root expression: ${value}`);
	if (!isAbsolute(expanded)) {
		if (!base) fail$5(`${label}: resolved root must be absolute: ${expanded}`);
		expanded = resolve(base, expanded);
	}
	return normalize(expanded);
}
function resolvePathSelector(raw, base, label) {
	const selector = object$1(raw, label);
	if ([
		selector.path !== void 0,
		selector.relative !== void 0,
		selector.env !== void 0
	].filter(Boolean).length !== 1) fail$5(`${label} must contain exactly one of path, relative, or env`);
	if (selector.path !== void 0) {
		if (typeof selector.path !== "string" || !selector.path) fail$5(`${label}.path must be a non-empty string`);
		return expandPath(selector.path, void 0, `${label}.path`);
	}
	if (selector.relative !== void 0) {
		if (typeof selector.relative !== "string" || !selector.relative || !base) fail$5(`${label}.relative requires a context root`);
		const resolved = resolve(base, selector.relative);
		const fromBase = relative(base, resolved);
		if (fromBase === ".." || fromBase.startsWith(`..${process.platform === "win32" ? "\\" : "/"}`) || isAbsolute(fromBase)) fail$5(`${label}.relative escapes the context root`);
		return normalize(resolved);
	}
	if (typeof selector.env !== "string" || !selector.env) fail$5(`${label}.env must name an environment variable`);
	const environmentValue = process.env[selector.env];
	if (environmentValue && !selector.ignore?.includes(environmentValue)) return expandPath(environmentValue, base, `${label}.env(${selector.env})`);
	if (selector.default !== void 0) return resolvePathSelector(selector.default, base, `${label}.default`);
	fail$5(`${label}: environment variable ${selector.env} is required`);
}
function getConfigContext(spec, contextName) {
	if (spec.version !== 2) fail$5(`unsupported config spec version: ${String(spec.version)}; rerender the deployment (expected version 2)`);
	const context = object$1(object$1(spec.contexts, "config spec contexts")[contextName], `unknown config context ${contextName}`);
	if (context.scope !== "user" && context.scope !== "system") fail$5(`context ${contextName}: invalid scope`);
	object$1(context.configs, `context ${contextName}.configs`);
	return context;
}
function contextConfigNames(spec, contextName, applyOnly = false) {
	const context = getConfigContext(spec, contextName);
	const names = Object.keys(context.configs);
	if (!applyOnly) return names;
	return names.filter((name) => {
		return object$1(spec.configs[name], `context ${contextName}: missing source config ${name}`).apply !== false;
	});
}
function selectRecipeNames(spec, contextName, requested, applyOnly = true) {
	const available = contextConfigNames(spec, contextName);
	if (requested.length === 0) return contextConfigNames(spec, contextName, applyOnly);
	const seen = /* @__PURE__ */ new Set();
	for (const name of requested) {
		if (!available.includes(name)) fail$5(`unknown config in context ${contextName}: ${name}`);
		if (seen.has(name)) fail$5(`config selected more than once in context ${contextName}: ${name}`);
		seen.add(name);
	}
	return requested;
}
function bindContextConfigs(spec, contextName, names) {
	const context = getConfigContext(spec, contextName);
	for (const name of names) if (!(name in context.configs)) fail$5(`unknown config in context ${contextName}: ${name}`);
	const root = resolvePathSelector(context.root, void 0, `context ${contextName}.root`);
	const base = context.subpath ? resolve(root, context.subpath) : root;
	const contextConfigs = object$1(context.configs, `context ${contextName}.configs`);
	const resolvedConfigs = {};
	const outputs = /* @__PURE__ */ new Map();
	for (const name of names) {
		const source = object$1(spec.configs[name], `context ${contextName}: missing source config ${name}`);
		const binding = object$1(contextConfigs[name], `context ${contextName}.configs.${name}`);
		if (!Array.isArray(source.inputs) || !Array.isArray(binding.inputs) || source.inputs.length !== binding.inputs.length) fail$5(`context ${contextName}.configs.${name}: input bindings do not match the source recipe`);
		const output = resolvePathSelector(binding.output, base, `context ${contextName}.configs.${name}.output`);
		const prior = outputs.get(output);
		if (prior) fail$5(`context ${contextName}: configs ${prior} and ${name} resolve to the same output ${output}`);
		outputs.set(output, name);
		const inputs = source.inputs.map((rawInput, index) => {
			const input = { ...object$1(rawInput, `config ${name}.inputs[${index}]`) };
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
	const number = constants.signals[signal];
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
function fail$4(message) {
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
	if (!options.invokedAs.startsWith("config-") || !options.invokedAs.endsWith(".sh")) fail$4(`unsupported config command alias ${options.invokedAs}; use a fixed config-ACTION.sh command or explicit --action and --context`);
	const body = options.invokedAs.slice(7, -3);
	const full = contextNames.flatMap((context) => CONFIG_ACTIONS.filter((action) => body === `${context}-${action}`).map((action) => ({
		action,
		context
	})));
	if (options.action === void 0 && options.context === void 0) {
		if (full.length !== 1) fail$4(`unknown or ambiguous config command alias ${options.invokedAs}`);
		return full[0];
	}
	if (options.action === void 0) {
		const actions = CONFIG_ACTIONS.filter((candidate) => body.endsWith(`-${candidate}`));
		const longest = Math.max(...actions.map((candidate) => candidate.length), -1);
		const selected = actions.filter((candidate) => candidate.length === longest);
		if (selected.length !== 1) fail$4(`unknown or ambiguous action in config command alias ${options.invokedAs}`);
		return { action: selected[0] };
	}
	const contexts = contextNames.filter((candidate) => body === candidate || body.startsWith(`${candidate}-`));
	const longest = Math.max(...contexts.map((candidate) => candidate.length), -1);
	const selected = contexts.filter((candidate) => candidate.length === longest);
	if (selected.length !== 1) fail$4(`unknown or ambiguous context in config command alias ${options.invokedAs}`);
	return { context: selected[0] };
}
function rejectIrrelevantFlags(options, action) {
	if (action !== "assemble" && (options.check || options.stdout || options.list || options.quiet)) fail$4(`${action} does not accept assembly display flags`);
	if (action !== "status" && action !== "inputs" && options.format !== "human") fail$4(`${action} does not accept status format flags`);
	if (action !== "sync-inputs" && options.seed) fail$4(`${action} does not accept --seed`);
	if (action !== "inputs" && (!options.rebuild || options.initiallyDisabled)) fail$4(`${action} does not accept input mutation flags`);
	if (action !== "install" && options.dropins !== void 0) fail$4(`${action} does not accept --dropins`);
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
function fail$3(message) {
	throw new Error(message);
}
function object(value, label) {
	if (!value || typeof value !== "object" || Array.isArray(value)) fail$3(`${label} must be an object`);
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
		const donorConfig = object(spec.configs[configName], `config ${configName}`);
		const localConfig = object(resolved.configs[configName], `resolved config ${configName}`);
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
			if (typeof donor.directory !== "string" || typeof donor.pattern !== "string" || typeof local.directory !== "string") fail$3(`config ${configName} input ${index} has an invalid compiled shape`);
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
async function deliver$1(source, destination, strategy) {
	if (strategy === "link") await replaceWithLink(source, destination);
	else await replaceWithCopy(source, destination);
}
async function applyRelation(relation, strategy, seed) {
	if (relation.aliasHazard) fail$3(`${relation.id}: ${relation.aliasHazard}`);
	if (relation.donorConflict) fail$3(`${relation.id}: donor has both enabled and disabled entries`);
	const sourceEntry = await inspectDeliveryEntry(relation.source);
	if (sourceEntry.kind === "missing" || sourceEntry.kind === "directory" || sourceEntry.kind === "special") fail$3(`${relation.id}: donor source is ${sourceEntry.kind}: ${relation.source}`);
	const local = await localSelection(relation);
	if (local.conflict) fail$3(`${relation.id}: both enabled and disabled local entries exist`);
	if (seed && local.selectedPath) return `preserved\t${relation.id}\t${local.selectedState}\t${local.selectedPath}`;
	const state = local.selectedState ?? relation.donorState;
	const destination = state === "disabled" && relation.suffix && relation.destinationDirectory ? join(relation.destinationDirectory, `${relation.logicalName}${relation.suffix}`) : relation.destinationDirectory ? join(relation.destinationDirectory, relation.logicalName) : relation.destination;
	await deliver$1(relation.source, destination, strategy);
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
function fail$2(message) {
	throw new Error(message);
}
function filenameMatches(value, pattern) {
	return matchesGlob(`x${value}`, `x${pattern}`);
}
function inputIdentity(input, index) {
	return typeof input.name === "string" && input.name ? input.name : String(index);
}
async function deliver(source, destination, strategy) {
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
	if (matches.length !== 1) fail$2(matches.length === 0 ? `unknown context input: ${selector}` : `ambiguous context input: ${selector}; use CONFIG/INPUT`);
	const selected = matches[0];
	const consumer = bindContextConfigs(spec, contextName, [selected.config]).configs[selected.config].inputs[selected.index];
	return {
		...selected,
		consumer
	};
}
async function rebuild(options, config) {
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
	if (typeof selected.consumer.directory !== "string") fail$2(`${selected.config}/${inputIdentity(selected.source, selected.index)} is not a glob input`);
	const suffix = typeof selected.source.disabled_suffix === "string" ? selected.source.disabled_suffix : void 0;
	return {
		active: join(selected.consumer.directory, name),
		disabled: suffix ? join(selected.consumer.directory, `${name}${suffix}`) : void 0
	};
}
async function assertInputBindingSeparated(selected) {
	if (typeof selected.source.file === "string" && typeof selected.consumer.file === "string") {
		if (await pathsSharePhysicalEntry(selected.source.file, selected.consumer.file)) fail$2(`${selected.config}/${inputIdentity(selected.source, selected.index)} consumer file aliases canonical input: ${selected.consumer.file}`);
		return;
	}
	if (typeof selected.source.directory === "string" && typeof selected.consumer.directory === "string" && await pathsSharePhysicalDirectory(selected.source.directory, selected.consumer.directory)) fail$2(`${selected.config}/${inputIdentity(selected.source, selected.index)} consumer directory aliases canonical input directory: ${selected.consumer.directory}`);
}
function validateInputName(input, name) {
	if (!name || basename(name) !== name || name === "." || name === "..") fail$2(`invalid input filename: ${name}`);
	if (typeof input.pattern !== "string" || !filenameMatches(name, input.pattern)) fail$2(`${name} does not match input pattern ${String(input.pattern)}`);
	if (typeof input.disabled_suffix === "string" && name.endsWith(input.disabled_suffix)) fail$2(`input filename must not include disabled suffix ${input.disabled_suffix}`);
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
	if (entry.kind === "directory" || entry.kind === "special") fail$2(`local input is not a regular file or symlink: ${path}`);
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
		if (suppliedName !== void 0) fail$2(`${selector} is a direct file input and does not accept a destination name`);
		if (options.initiallyDisabled ?? false) fail$2(`${selector} is a direct file input and cannot be disabled`);
		if (typeof selected.consumer.file !== "string") fail$2(`${selector} has an invalid resolved file binding`);
		await deliver(source, selected.consumer.file, options.strategy ?? getConfigContext(spec, options.contextName).dropins ?? "link");
		console.log(`put\t${selected.config}/${inputIdentity(selected.source, selected.index)}\t${selected.consumer.file}`);
		return options.rebuild ?? true ? rebuild(options, selected.config) : 0;
	}
	const name = suppliedName ?? basename(source);
	validateInputName(selected.source, name);
	const paths = localInputPaths(selected, name);
	const pair = await inspectPair(paths);
	if (pair.conflict) fail$2(`both enabled and disabled local entries exist for ${name}`);
	const destination = pair.active.kind !== "missing" ? paths.active : pair.disabled && pair.disabled.kind !== "missing" ? paths.disabled : options.initiallyDisabled ?? false ? paths.disabled ?? fail$2(`${selector} cannot be disabled`) : paths.active;
	await deliver(source, destination, options.strategy ?? getConfigContext(spec, options.contextName).dropins ?? "link");
	console.log(`put\t${selected.config}/${inputIdentity(selected.source, selected.index)}\t${destination}`);
	return options.rebuild ?? true ? rebuild(options, selected.config) : 0;
}
async function inputMutation(options, action, args) {
	const [selector, name] = args;
	if (!selector) fail$2(`usage: config-inputs.sh ${action} INPUT [NAME]`);
	const selected = selectInput(options.spec, options.contextName, selector);
	await assertInputBindingSeparated(selected);
	if (typeof selected.source.file === "string") {
		if (action !== "remove") fail$2(`${selector} is a direct file input and cannot be ${action}d`);
		if (args.length !== 1) fail$2(`usage: config-inputs.sh remove DIRECT_INPUT`);
		if (typeof selected.consumer.file !== "string") fail$2(`${selector} has an invalid resolved file binding`);
		const entry = await inspectDeliveryEntry(selected.consumer.file);
		if (entry.kind === "missing") return 0;
		replaceableLocal(entry, selected.consumer.file);
		await rm(selected.consumer.file);
		console.log(`remove\t${selected.config}/${inputIdentity(selected.source, selected.index)}\t${selected.consumer.file}`);
		return rebuild(options, selected.config);
	}
	if (!name || args.length !== 2) fail$2(`usage: config-inputs.sh ${action} INPUT NAME`);
	validateInputName(selected.source, name);
	const paths = localInputPaths(selected, name);
	const pair = await inspectPair(paths);
	if (pair.conflict) fail$2(`both enabled and disabled local entries exist for ${name}`);
	if (action === "remove") {
		const path = pair.active.kind !== "missing" ? paths.active : pair.disabled && pair.disabled.kind !== "missing" ? paths.disabled : void 0;
		if (!path) return 0;
		replaceableLocal(path === paths.active ? pair.active : pair.disabled, path);
		await rm(path);
		console.log(`remove\t${selected.config}/${inputIdentity(selected.source, selected.index)}\t${path}`);
		return rebuild(options, selected.config);
	}
	if (!paths.disabled) fail$2(`${selected.config}/${inputIdentity(selected.source, selected.index)} cannot be disabled`);
	const from = action === "disable" ? paths.active : paths.disabled;
	const to = action === "disable" ? paths.disabled : paths.active;
	const fromEntry = action === "disable" ? pair.active : pair.disabled;
	if ((action === "disable" ? pair.disabled : pair.active).kind !== "missing") return 0;
	if (fromEntry.kind === "missing") fail$2(`local input does not exist: ${from}`);
	replaceableLocal(fromEntry, from);
	await rename(from, to);
	console.log(`${action}\t${selected.config}/${inputIdentity(selected.source, selected.index)}\t${to}`);
	return rebuild(options, selected.config);
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
		if (!selector || !source || args.length > 3) fail$2("usage: config-inputs.sh put INPUT SOURCE [NAME] [--strategy copy|link]");
		return putInput({
			...options,
			selector,
			source,
			name
		});
	}
	if (action === "enable" || action === "disable" || action === "remove") return inputMutation(options, action, args);
	fail$2("usage: config-inputs.sh <list|status|put|enable|disable|remove> ...");
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
function truthy(value) {
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
	const reason = truthy(process.env.COMPFUZOR_CONFIG_CONTEXTS_BYPASS) ? "COMPFUZOR_CONFIG_CONTEXTS_BYPASS" : truthy(process.env.COMPFUZOR_CONFIG_BYPASS) ? "COMPFUZOR_CONFIG_BYPASS" : void 0;
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
function fail$1(message) {
	throw new Error(message);
}
/**
* Resolve one declared name. Alias parsing is deliberately lazy: an explicit
* value completely bypasses it, allowing callers to escape stale aliases.
*/
function resolveSelectedName(options) {
	const declared = new Set(options.declared);
	const selected = options.explicit ?? options.inferAlias(options.invokedAs, declared) ?? options.environment ?? options.fallback;
	if (!declared.has(selected)) fail$1(`unknown ${options.label}: ${selected}`);
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
//#region files/config/command.ts
/** Thin multicall dispatcher for the fixed CONFIG action vocabulary. */
function fail(message) {
	throw new Error(message);
}
function parseInputStrategy(value, label) {
	if (value === "copy" || value === "link") return value;
	fail(`${label} must be copy or link`);
}
function parseInstallStrategy(value, label) {
	if (value === "assemble" || value === "copy" || value === "link") return value;
	fail(`${label} must be assemble, copy, or link`);
}
function contextInputStrategy(spec, contextName, explicit) {
	return parseInputStrategy(explicit ?? process.env.COMPFUZOR_CONFIG_DROPINS_STRATEGY ?? getConfigContext(spec, contextName).dropins ?? "link", "effective config input strategy");
}
function contextInstallStrategy(spec, contextName, explicit) {
	return parseInstallStrategy(explicit ?? process.env.COMPFUZOR_CONFIG_INSTALL_STRATEGY ?? getConfigContext(spec, contextName).install ?? "assemble", "effective config install strategy");
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
	if (context.canonical && !["assemble", "status"].includes(action)) fail(`config ${action} is not meaningful for canonical source=destination context; use assemble or status`);
	if (action === "assemble") {
		if (options.check && options.stdout) fail("--check and --stdout are mutually exclusive");
		if (options.list) {
			if (options.args.length > 0) fail("--list does not accept recipe names");
			for (const name of selectRecipeNames(spec, contextName, [], false).sort()) console.log(name);
			return 0;
		}
		const names = selectRecipeNames(spec, contextName, options.args);
		if (options.stdout && names.length !== 1) fail("--stdout requires exactly one selected config");
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
		strategy: parseInputStrategy(options.strategy ?? process.env.COMPFUZOR_CONFIG_PUBLISH_STRATEGY, "config publish strategy")
	});
	if (action === "inputs") {
		const inputAction = options.args[0];
		const strategy = inputAction === "put" ? contextInputStrategy(spec, contextName, options.strategy) : options.strategy === void 0 ? void 0 : fail(`${inputAction ?? "inputs"} does not accept --strategy`);
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
async function main(argv = process.argv.slice(2), modulePath = fileURLToPath(import.meta.url), invokedAs = basename(process.argv[1] ?? modulePath)) {
	const realModulePath = await realpath(modulePath);
	return runConfigCommand(parseConfigCommandArgs(argv, resolve(dirname(realModulePath), "../.."), invokedAs));
}
const argvPath = process.argv[1];
if (argvPath) Promise.all([realpath(argvPath), realpath(fileURLToPath(import.meta.url))]).then(([realArgvPath, realModulePath]) => {
	if (realArgvPath !== realModulePath) return;
	return main(process.argv.slice(2), realModulePath, basename(argvPath)).then((code) => {
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
export { CONFIG_ACTIONS, main, parseConfigCommandArgs, runConfigCommand };
