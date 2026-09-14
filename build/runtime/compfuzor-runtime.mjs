#!/usr/bin/env -S node --disable-warning=MODULE_TYPELESS_PACKAGE_JSON
import { access, chmod, constants, copyFile, lstat, mkdir, mkdtemp, readFile, readdir, readlink, realpath, rename, rm, stat, symlink, writeFile } from "node:fs/promises";
import { basename, dirname, isAbsolute, join, matchesGlob, normalize, relative, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { execFile, spawn } from "node:child_process";
import { constants as constants$1, tmpdir } from "node:os";
import { parseArgs, promisify } from "node:util";
//#region files/config/context.ts
/** Import-safe consumer-context selection and path binding for CONFIGS specs. */
function fail$13(message) {
	throw new Error(message);
}
function object$3(value, label) {
	if (!value || typeof value !== "object" || Array.isArray(value)) fail$13(`${label} must be an object`);
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
		const home = knownRoot("HOME") ?? fail$13(`${label}: HOME is required to expand ${value}`);
		if (value.slice(1).includes("$") || value.slice(1).includes("~")) fail$13(`${label}: unsupported runtime-root expression: ${value}`);
		expanded = home + value.slice(1);
	} else if (value.startsWith("${")) {
		const match = /^\$\{(HOME|XDG_CONFIG_HOME|XDG_STATE_HOME|XDG_CACHE_HOME|XDG_DATA_HOME)\}(?:\/|$)/.exec(value);
		if (!match) fail$13(`${label}: unsupported runtime-root expression: ${value}`);
		const root = knownRoot(match[1]) ?? fail$13(`${label}: ${match[1]} or HOME is required to expand ${value}`);
		const suffix = value.slice(match[0].length - (match[0].endsWith("/") ? 1 : 0));
		if (suffix.includes("$") || suffix.includes("~")) fail$13(`${label}: unsupported runtime-root expression: ${value}`);
		expanded = root + suffix;
	} else if (value.includes("$") || value.includes("~")) fail$13(`${label}: unsupported runtime-root expression: ${value}`);
	if (!isAbsolute(expanded)) {
		if (!base) fail$13(`${label}: resolved root must be absolute: ${expanded}`);
		expanded = resolve(base, expanded);
	}
	return normalize(expanded);
}
function resolvePathSelector(raw, base, label) {
	const selector = object$3(raw, label);
	if ([
		selector.path !== void 0,
		selector.relative !== void 0,
		selector.env !== void 0
	].filter(Boolean).length !== 1) fail$13(`${label} must contain exactly one of path, relative, or env`);
	if (selector.path !== void 0) {
		if (typeof selector.path !== "string" || !selector.path) fail$13(`${label}.path must be a non-empty string`);
		return expandPath$1(selector.path, void 0, `${label}.path`);
	}
	if (selector.relative !== void 0) {
		if (typeof selector.relative !== "string" || !selector.relative || !base) fail$13(`${label}.relative requires a context root`);
		const resolved = resolve(base, selector.relative);
		const fromBase = relative(base, resolved);
		if (fromBase === ".." || fromBase.startsWith(`..${process.platform === "win32" ? "\\" : "/"}`) || isAbsolute(fromBase)) fail$13(`${label}.relative escapes the context root`);
		return normalize(resolved);
	}
	if (typeof selector.env !== "string" || !selector.env) fail$13(`${label}.env must name an environment variable`);
	const environmentValue = process.env[selector.env];
	if (environmentValue && !selector.ignore?.includes(environmentValue)) return expandPath$1(environmentValue, base, `${label}.env(${selector.env})`);
	if (selector.default !== void 0) return resolvePathSelector(selector.default, base, `${label}.default`);
	fail$13(`${label}: environment variable ${selector.env} is required`);
}
function getConfigContext(spec, contextName) {
	if (spec.version !== 2) fail$13(`unsupported config spec version: ${String(spec.version)}; rerender the deployment (expected version 2)`);
	const context = object$3(object$3(spec.contexts, "config spec contexts")[contextName], `unknown config context ${contextName}`);
	if (context.scope !== "user" && context.scope !== "system") fail$13(`context ${contextName}: invalid scope`);
	object$3(context.configs, `context ${contextName}.configs`);
	return context;
}
function contextConfigNames(spec, contextName, applyOnly = false) {
	const context = getConfigContext(spec, contextName);
	const names = Object.keys(context.configs);
	if (!applyOnly) return names;
	return names.filter((name) => {
		return object$3(spec.configs[name], `context ${contextName}: missing source config ${name}`).apply !== false;
	});
}
function selectRecipeNames(spec, contextName, requested, applyOnly = true) {
	const available = contextConfigNames(spec, contextName);
	if (requested.length === 0) return contextConfigNames(spec, contextName, applyOnly);
	const seen = /* @__PURE__ */ new Set();
	for (const name of requested) {
		if (!available.includes(name)) fail$13(`unknown config in context ${contextName}: ${name}`);
		if (seen.has(name)) fail$13(`config selected more than once in context ${contextName}: ${name}`);
		seen.add(name);
	}
	return requested;
}
function bindContextConfigs(spec, contextName, names) {
	const context = getConfigContext(spec, contextName);
	for (const name of names) if (!(name in context.configs)) fail$13(`unknown config in context ${contextName}: ${name}`);
	const root = resolvePathSelector(context.root, void 0, `context ${contextName}.root`);
	const base = context.subpath ? resolve(root, context.subpath) : root;
	const contextConfigs = object$3(context.configs, `context ${contextName}.configs`);
	const resolvedConfigs = {};
	const outputs = /* @__PURE__ */ new Map();
	for (const name of names) {
		const source = object$3(spec.configs[name], `context ${contextName}: missing source config ${name}`);
		const binding = object$3(contextConfigs[name], `context ${contextName}.configs.${name}`);
		if (!Array.isArray(source.inputs) || !Array.isArray(binding.inputs) || source.inputs.length !== binding.inputs.length) fail$13(`context ${contextName}.configs.${name}: input bindings do not match the source recipe`);
		const output = resolvePathSelector(binding.output, base, `context ${contextName}.configs.${name}.output`);
		const prior = outputs.get(output);
		if (prior) fail$13(`context ${contextName}: configs ${prior} and ${name} resolve to the same output ${output}`);
		outputs.set(output, name);
		const inputs = source.inputs.map((rawInput, index) => {
			const input = { ...object$3(rawInput, `config ${name}.inputs[${index}]`) };
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
function fail$12(message) {
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
	if (!options.invokedAs.startsWith("config-") || !options.invokedAs.endsWith(".sh")) fail$12(`unsupported config command alias ${options.invokedAs}; use a fixed config-ACTION.sh command or explicit --action and --context`);
	const body = options.invokedAs.slice(7, -3);
	const full = contextNames.flatMap((context) => CONFIG_ACTIONS.filter((action) => body === `${context}-${action}`).map((action) => ({
		action,
		context
	})));
	if (options.action === void 0 && options.context === void 0) {
		if (full.length !== 1) fail$12(`unknown or ambiguous config command alias ${options.invokedAs}`);
		return full[0];
	}
	if (options.action === void 0) {
		const actions = CONFIG_ACTIONS.filter((candidate) => body.endsWith(`-${candidate}`));
		const longest = Math.max(...actions.map((candidate) => candidate.length), -1);
		const selected = actions.filter((candidate) => candidate.length === longest);
		if (selected.length !== 1) fail$12(`unknown or ambiguous action in config command alias ${options.invokedAs}`);
		return { action: selected[0] };
	}
	const contexts = contextNames.filter((candidate) => body === candidate || body.startsWith(`${candidate}-`));
	const longest = Math.max(...contexts.map((candidate) => candidate.length), -1);
	const selected = contexts.filter((candidate) => candidate.length === longest);
	if (selected.length !== 1) fail$12(`unknown or ambiguous context in config command alias ${options.invokedAs}`);
	return { context: selected[0] };
}
function rejectIrrelevantFlags(options, action) {
	if (action !== "assemble" && (options.check || options.stdout || options.list || options.quiet)) fail$12(`${action} does not accept assembly display flags`);
	if (action !== "status" && action !== "inputs" && options.format !== "human") fail$12(`${action} does not accept status format flags`);
	if (action !== "sync-inputs" && options.seed) fail$12(`${action} does not accept --seed`);
	if (action !== "inputs" && (!options.rebuild || options.initiallyDisabled)) fail$12(`${action} does not accept input mutation flags`);
	if (action !== "install" && options.dropins !== void 0) fail$12(`${action} does not accept --dropins`);
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
function fail$11(message) {
	throw new Error(message);
}
function object$2(value, label) {
	if (!value || typeof value !== "object" || Array.isArray(value)) fail$11(`${label} must be an object`);
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
		const donorConfig = object$2(spec.configs[configName], `config ${configName}`);
		const localConfig = object$2(resolved.configs[configName], `resolved config ${configName}`);
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
			if (typeof donor.directory !== "string" || typeof donor.pattern !== "string" || typeof local.directory !== "string") fail$11(`config ${configName} input ${index} has an invalid compiled shape`);
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
	if (relation.aliasHazard) fail$11(`${relation.id}: ${relation.aliasHazard}`);
	if (relation.donorConflict) fail$11(`${relation.id}: donor has both enabled and disabled entries`);
	const sourceEntry = await inspectDeliveryEntry(relation.source);
	if (sourceEntry.kind === "missing" || sourceEntry.kind === "directory" || sourceEntry.kind === "special") fail$11(`${relation.id}: donor source is ${sourceEntry.kind}: ${relation.source}`);
	const local = await localSelection(relation);
	if (local.conflict) fail$11(`${relation.id}: both enabled and disabled local entries exist`);
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
function fail$10(message) {
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
	if (matches.length !== 1) fail$10(matches.length === 0 ? `unknown context input: ${selector}` : `ambiguous context input: ${selector}; use CONFIG/INPUT`);
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
	if (typeof selected.consumer.directory !== "string") fail$10(`${selected.config}/${inputIdentity(selected.source, selected.index)} is not a glob input`);
	const suffix = typeof selected.source.disabled_suffix === "string" ? selected.source.disabled_suffix : void 0;
	return {
		active: join(selected.consumer.directory, name),
		disabled: suffix ? join(selected.consumer.directory, `${name}${suffix}`) : void 0
	};
}
async function assertInputBindingSeparated(selected) {
	if (typeof selected.source.file === "string" && typeof selected.consumer.file === "string") {
		if (await pathsSharePhysicalEntry(selected.source.file, selected.consumer.file)) fail$10(`${selected.config}/${inputIdentity(selected.source, selected.index)} consumer file aliases canonical input: ${selected.consumer.file}`);
		return;
	}
	if (typeof selected.source.directory === "string" && typeof selected.consumer.directory === "string" && await pathsSharePhysicalDirectory(selected.source.directory, selected.consumer.directory)) fail$10(`${selected.config}/${inputIdentity(selected.source, selected.index)} consumer directory aliases canonical input directory: ${selected.consumer.directory}`);
}
function validateInputName(input, name) {
	if (!name || basename(name) !== name || name === "." || name === "..") fail$10(`invalid input filename: ${name}`);
	if (typeof input.pattern !== "string" || !filenameMatches(name, input.pattern)) fail$10(`${name} does not match input pattern ${String(input.pattern)}`);
	if (typeof input.disabled_suffix === "string" && name.endsWith(input.disabled_suffix)) fail$10(`input filename must not include disabled suffix ${input.disabled_suffix}`);
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
	if (entry.kind === "directory" || entry.kind === "special") fail$10(`local input is not a regular file or symlink: ${path}`);
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
		if (suppliedName !== void 0) fail$10(`${selector} is a direct file input and does not accept a destination name`);
		if (options.initiallyDisabled ?? false) fail$10(`${selector} is a direct file input and cannot be disabled`);
		if (typeof selected.consumer.file !== "string") fail$10(`${selector} has an invalid resolved file binding`);
		await deliver$1(source, selected.consumer.file, options.strategy ?? getConfigContext(spec, options.contextName).dropins ?? "link");
		console.log(`put\t${selected.config}/${inputIdentity(selected.source, selected.index)}\t${selected.consumer.file}`);
		return options.rebuild ?? true ? rebuild$1(options, selected.config) : 0;
	}
	const name = suppliedName ?? basename(source);
	validateInputName(selected.source, name);
	const paths = localInputPaths(selected, name);
	const pair = await inspectPair(paths);
	if (pair.conflict) fail$10(`both enabled and disabled local entries exist for ${name}`);
	const destination = pair.active.kind !== "missing" ? paths.active : pair.disabled && pair.disabled.kind !== "missing" ? paths.disabled : options.initiallyDisabled ?? false ? paths.disabled ?? fail$10(`${selector} cannot be disabled`) : paths.active;
	await deliver$1(source, destination, options.strategy ?? getConfigContext(spec, options.contextName).dropins ?? "link");
	console.log(`put\t${selected.config}/${inputIdentity(selected.source, selected.index)}\t${destination}`);
	return options.rebuild ?? true ? rebuild$1(options, selected.config) : 0;
}
async function inputMutation(options, action, args) {
	const [selector, name] = args;
	if (!selector) fail$10(`usage: config-inputs.sh ${action} INPUT [NAME]`);
	const selected = selectInput(options.spec, options.contextName, selector);
	if (!getConfigContext(options.spec, options.contextName).canonical || action === "remove") await assertInputBindingSeparated(selected);
	if (typeof selected.source.file === "string") {
		if (action !== "remove") fail$10(`${selector} is a direct file input and cannot be ${action}d`);
		if (args.length !== 1) fail$10(`usage: config-inputs.sh remove DIRECT_INPUT`);
		if (typeof selected.consumer.file !== "string") fail$10(`${selector} has an invalid resolved file binding`);
		const entry = await inspectDeliveryEntry(selected.consumer.file);
		if (entry.kind === "missing") return 0;
		replaceableLocal(entry, selected.consumer.file);
		await rm(selected.consumer.file);
		console.log(`remove\t${selected.config}/${inputIdentity(selected.source, selected.index)}\t${selected.consumer.file}`);
		return rebuild$1(options, selected.config);
	}
	if (!name || args.length !== 2) fail$10(`usage: config-inputs.sh ${action} INPUT NAME`);
	validateInputName(selected.source, name);
	const paths = localInputPaths(selected, name);
	const pair = await inspectPair(paths);
	if (pair.conflict) fail$10(`both enabled and disabled local entries exist for ${name}`);
	if (action === "remove") {
		const path = pair.active.kind !== "missing" ? paths.active : pair.disabled && pair.disabled.kind !== "missing" ? paths.disabled : void 0;
		if (!path) return 0;
		replaceableLocal(path === paths.active ? pair.active : pair.disabled, path);
		await rm(path);
		console.log(`remove\t${selected.config}/${inputIdentity(selected.source, selected.index)}\t${path}`);
		return rebuild$1(options, selected.config);
	}
	if (!paths.disabled) fail$10(`${selected.config}/${inputIdentity(selected.source, selected.index)} cannot be disabled`);
	const from = action === "disable" ? paths.active : paths.disabled;
	const to = action === "disable" ? paths.disabled : paths.active;
	const fromEntry = action === "disable" ? pair.active : pair.disabled;
	if ((action === "disable" ? pair.disabled : pair.active).kind !== "missing") return 0;
	if (fromEntry.kind === "missing") fail$10(`local input does not exist: ${from}`);
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
		if (!selector || !source || args.length > 3) fail$10("usage: config-inputs.sh put INPUT SOURCE [NAME] [--strategy copy|link]");
		return putInput({
			...options,
			selector,
			source,
			name
		});
	}
	if (action === "enable" || action === "disable" || action === "remove") return inputMutation(options, action, args);
	fail$10("usage: config-inputs.sh <list|status|put|enable|disable|remove> ...");
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
function fail$9(message) {
	throw new Error(message);
}
/**
* Resolve one declared name. Alias parsing is deliberately lazy: an explicit
* value completely bypasses it, allowing callers to escape stale aliases.
*/
function resolveSelectedName(options) {
	const declared = new Set(options.declared);
	const selected = options.explicit ?? options.inferAlias(options.invokedAs, declared) ?? options.environment ?? options.fallback;
	if (!declared.has(selected)) fail$9(`unknown ${options.label}: ${selected}`);
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
function fail$8(message) {
	throw new Error(message);
}
function parseInputStrategy$1(value, label) {
	if (value === "copy" || value === "link") return value;
	fail$8(`${label} must be copy or link`);
}
function parseInstallStrategy$1(value, label) {
	if (value === "assemble" || value === "copy" || value === "link") return value;
	fail$8(`${label} must be assemble, copy, or link`);
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
	if (context.canonical && !canonicalAllowed) fail$8(`config ${action} is not meaningful for canonical source=destination context; use assemble, status, or explicit input list/status/enable/disable`);
	if (action === "assemble") {
		if (options.check && options.stdout) fail$8("--check and --stdout are mutually exclusive");
		if (options.list) {
			if (options.args.length > 0) fail$8("--list does not accept recipe names");
			for (const name of selectRecipeNames(spec, contextName, [], false).sort()) console.log(name);
			return 0;
		}
		const names = selectRecipeNames(spec, contextName, options.args);
		if (options.stdout && names.length !== 1) fail$8("--stdout requires exactly one selected config");
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
		const strategy = inputAction === "put" ? contextInputStrategy(spec, contextName, options.strategy) : options.strategy === void 0 ? void 0 : fail$8(`${inputAction ?? "inputs"} does not accept --strategy`);
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
async function main$5(argv, deploymentDir, invokedAs) {
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
async function main$4(argv, deploymentDir) {
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
const USAGE$1 = `Usage: compfuzor-catalog.sh [--catalog PATH | --deployment DIR] [--json] [COMMAND]

Inspect the compiled read-only runtime catalog. Commands:
  contributors
  actions
  commands
  resources
  flows
  flow NAME`;
function fail$7(message) {
	throw new Error(message);
}
function object$1(value, label) {
	if (typeof value !== "object" || value === null || Array.isArray(value)) fail$7(`${label} must be an object`);
	return value;
}
function strings(value, label = "value") {
	if (value === void 0) return [];
	if (!Array.isArray(value) || value.some((item) => typeof item !== "string")) fail$7(`${label} must be an array of strings`);
	return value;
}
function phaseFor(flow, index) {
	return (FLOW_PHASES[flow]?.find((candidate) => index >= candidate.from && index <= candidate.to))?.name ?? "unknown";
}
function parseCatalog(value) {
	const record = object$1(value, "runtime catalog");
	if (record.version !== 1) fail$7(`unsupported runtime catalog version: ${String(record.version)}`);
	const flows = object$1(record.flows, "runtime catalog flows");
	return {
		version: 1,
		deployment: object$1(record.deployment, "runtime catalog deployment"),
		contributors: Array.isArray(record.contributors) ? record.contributors.map((item, index) => object$1(item, `contributor ${index}`)) : fail$7("runtime catalog contributors must be an array"),
		resources: Array.isArray(record.resources) ? record.resources.map((item, index) => object$1(item, `resource ${index}`)) : fail$7("runtime catalog resources must be an array"),
		commands: Array.isArray(record.commands) ? record.commands.map((item, index) => object$1(item, `command ${index}`)) : fail$7("runtime catalog commands must be an array"),
		actions: Array.isArray(record.actions) ? record.actions.map((item, index) => object$1(item, `action ${index}`)) : fail$7("runtime catalog actions must be an array"),
		flows: Object.fromEntries(Object.entries(flows).map(([name, item]) => {
			return [name, {
				name,
				entries: strings(object$1(item, `flow ${name}`).entries, `flow ${name} entries`)
			}];
		})),
		execution: object$1(record.execution, "runtime catalog execution")
	};
}
function parseOptions(argv, deploymentDir) {
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
		console.log(USAGE$1);
		process.exit(0);
	}
	if (values.catalog && values.deployment) fail$7("--catalog and --deployment are mutually exclusive");
	const root = resolve(values.deployment ?? deploymentDir);
	return {
		catalogPath: resolve(values.catalog ?? join(root, "etc", "compfuzor-runtime", "catalog.json")),
		json: values.json ?? false,
		positionals
	};
}
function placement(path, expectedFlow) {
	const match = /^(\d{2})-([a-z0-9-]+)-.+\.json$/.exec(basename(path));
	if (!match) fail$7(`invalid indexed flow filename: ${path}`);
	const index = Number(match[1]);
	if (index < 1 || index > 99) fail$7(`flow index must be 01-99: ${path}`);
	if (match[2] !== expectedFlow) fail$7(`flow filename ${path} does not match descriptor flow ${expectedFlow}`);
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
	const selected = names.filter((name) => name.endsWith(".json")).sort();
	return await Promise.all(selected.map(async (name) => {
		const path = join(directory, name);
		return {
			path,
			record: object$1(JSON.parse(await readFile(path, "utf8")), `flow descriptor ${path}`),
			layer
		};
	}));
}
async function loadFlow(catalogPath, flow, suppliedCatalog) {
	if (!(flow in FLOW_PHASES)) fail$7(`unknown flow: ${flow}`);
	const catalog = suppliedCatalog ?? parseCatalog(JSON.parse(await readFile(catalogPath, "utf8")));
	const declaredById = /* @__PURE__ */ new Map();
	for (const [declaredFlow, descriptor] of Object.entries(catalog.flows)) for (const id of descriptor.entries) {
		const previous = declaredById.get(id);
		if (previous) fail$7(`flow contribution id ${id} is declared by both ${previous} and ${declaredFlow}`);
		declaredById.set(id, declaredFlow);
	}
	const declaredDescriptor = catalog.flows[flow];
	if (!declaredDescriptor) fail$7(`catalog does not declare flow: ${flow}`);
	const declared = new Set(declaredDescriptor.entries);
	const root = join(dirname(catalogPath), "workflows");
	const [compiled, site] = await Promise.all([readLayer(join(root, "compiled"), "compiled"), readLayer(join(root, "site"), "site")]);
	const selected = /* @__PURE__ */ new Map();
	for (const item of compiled) {
		const id = item.record.id;
		if (typeof id !== "string" || !id) fail$7(`flow descriptor ${item.path} requires an id`);
		if (!declared.has(id)) continue;
		if (item.record.version !== 1) fail$7(`flow descriptor ${item.path} has unsupported version ${String(item.record.version)}`);
		if (item.record.flow !== flow) fail$7(`flow descriptor ${item.path} is indexed under ${flow} but declares ${String(item.record.flow)}`);
		object$1(item.record.invoke, `flow descriptor ${item.path} invocation`);
		strings(item.record.contributors, `flow descriptor ${item.path} contributors`);
		if (selected.has(id)) fail$7(`duplicate compiled flow contribution id ${id}`);
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
	for (const id of declared) if (!selected.has(id)) fail$7(`catalog flow ${flow} references missing compiled contribution ${id}`);
	const siteIds = /* @__PURE__ */ new Set();
	for (const item of site) {
		const id = item.record.id;
		if (typeof id !== "string" || !id) fail$7(`site flow descriptor ${item.path} requires an id`);
		if (siteIds.has(id)) fail$7(`duplicate site flow contribution id ${id}`);
		siteIds.add(id);
		const declaredFlow = declaredById.get(id);
		if (!declaredFlow) fail$7(`site flow descriptor ${item.path} names undeclared contribution ${id}`);
		if (declaredFlow !== flow) continue;
		const previous = selected.get(id);
		if (item.record.state === "absent") {
			if (!previous) fail$7(`site tombstone ${item.path} names unknown compiled contribution ${id}`);
			if (Object.keys(item.record).some((key) => key !== "id" && key !== "state")) fail$7(`site tombstone ${item.path} may contain only id and state`);
			selected.delete(id);
			continue;
		}
		if (item.record.version !== 1) fail$7(`site flow descriptor ${item.path} has unsupported version ${String(item.record.version)}`);
		if (item.record.flow !== flow) fail$7(`site flow descriptor ${item.path} is indexed under ${flow} but declares ${String(item.record.flow)}`);
		object$1(item.record.invoke, `site flow descriptor ${item.path} invocation`);
		strings(item.record.contributors, `site flow descriptor ${item.path} contributors`);
		const effective = placement(item.path, flow);
		if (previous && semanticDescriptor(previous) !== semanticDescriptor(item.record)) fail$7(`site flow contribution ${id} may change placement only; use a new id for changed behavior`);
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
	return [...selected.values()].sort((left, right) => basename(left.selectedPath).localeCompare(basename(right.selectedPath)));
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
	const catalog = parseCatalog(JSON.parse(await readFile(options.catalogPath, "utf8")));
	const [command, argument, ...extra] = options.positionals;
	if (extra.length > 0) fail$7(USAGE$1);
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
		if (!argument) fail$7("catalog flow requires a flow name");
		const entries = await loadFlow(options.catalogPath, argument, catalog);
		if (options.json) console.log(JSON.stringify(entries));
		else printRows(entries.map((entry) => [
			String(entry.effectiveIndex).padStart(2, "0"),
			entry.effectivePhase,
			entry.id,
			cell(object$1(entry.invoke, `flow invocation ${entry.id}`).action),
			entry.selectedLayer,
			strings(entry.contributors, `flow invocation ${entry.id} contributors`).join(",")
		]));
		return 0;
	}
	if (argument) fail$7(`${command} does not accept an argument`);
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
	if (!values) fail$7(USAGE$1);
	if (options.json) console.log(JSON.stringify(values));
	else printRows(values.map((value) => [
		cell(value.id ?? value.name),
		cell(value.action ?? value.contract ?? value.kind),
		strings(value.contributors, "catalog contributors").join(",")
	]));
	return 0;
}
async function main$3(argv, deploymentDir) {
	return runCatalog(parseOptions(argv, deploymentDir));
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
function object(value, description) {
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
	const strategies = object(value, description);
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
	const value = object(raw, `manifest ${path}`);
	if (value.version !== 1 && value.version !== 2) fail$5(`manifest ${path}: unsupported version ${String(value.version)}`);
	const version = value.version;
	if (!Array.isArray(value.links)) fail$5(`manifest ${path}: links must be an array`);
	const seen = /* @__PURE__ */ new Set();
	const links = value.links.map((entry, index) => {
		const record = object(entry, `${path}: links[${index}]`);
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
		registry: resolvePathSelector(spec.registry, void 0, `Zim context ${name}.registry`)
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
		loaderHealthy("zimrc", activation, canonical)
	])).every(Boolean);
}
//#endregion
//#region files/zim/cli.ts
/** Zim command parsing, context selection, strategy normalization, and help. */
const HELP = {
	install: `Usage: install-zim.sh [--context NAME] [--install assemble|copy|link] [--dropins copy|link]

Install and activate Zim for a selected context: install its CONFIG recipes,
project startup loaders, build both caches, and publish the registry link.

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
//#region files/runtime/compfuzor-runtime.ts
/** Minimal multicall entry for Compfuzor's domain-grouped JavaScript runtimes. */
const RUNTIME_NAME = "compfuzor-runtime.mjs";
const RUNTIME_SOURCE_NAME = "compfuzor-runtime.ts";
const USAGE = `Usage: compfuzor-runtime.mjs <catalog|config|config-remote|links|zim> ...

Ordinary deployments invoke this multicall runtime through stable domain
aliases such as config/command.mjs, config-remote.mjs, links.mjs, and
zim/install.mjs.`;
function fail(message) {
	throw new Error(message);
}
function classifyCandidate(path) {
	const name = basename(path);
	if (name === "compfuzor-catalog.sh") return "catalog";
	if (name === "config-remote.mjs") return "config-remote";
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
	if (domain !== "catalog" && domain !== "config" && domain !== "config-remote" && domain !== "links" && domain !== "zim") fail(USAGE);
	return {
		domain,
		argv: domainArgv,
		invokedAs: domain === "config" ? "command.ts" : RUNTIME_NAME
	};
}
async function runDomain(domain, argv, invokedAs, deploymentDir) {
	try {
		if (domain === "catalog") return await main$3(argv, deploymentDir);
		if (domain === "config") return await main$5(argv, deploymentDir, invokedAs);
		if (domain === "links") return await main$2(argv, deploymentDir);
		if (domain === "zim") return await main$1(argv, deploymentDir);
		await main$4(argv, deploymentDir);
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
