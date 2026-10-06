/** Import-safe audience selection and sequential action execution.
 * Qualified names assert an audience; no CLI/env selector changes that assertion.
 * Domain leaves, not this adapter, own their options and context validation.
 */
import { spawn } from "node:child_process";
import { readFile, realpath } from "node:fs/promises";
import { basename, dirname, isAbsolute, relative, resolve, sep } from "node:path";
import { fileURLToPath } from "node:url";

export type Audience = "user" | "system";
export type ActionStep =
  | { kind: "action"; action: string }
  | { kind: "exec"; path: string; children?: ActionStep[] };
export type ActionFamily = {
  name: string;
  action: string;
  entry: string;
  aliases: string[];
  default?: Audience;
  plans: Partial<Record<Audience, ActionStep[]>>;
};
export type ActionSpec = { version: 1; actions: Record<string, ActionFamily> };
export type ActionOutcome = { code: number; signal?: NodeJS.Signals };
export type ActionSelection = {
  family: ActionFamily;
  audience: Audience;
  deploymentDir: string;
};

const AUDIENCES: readonly Audience[] = ["user", "system"];
const NAME = /^[A-Za-z0-9][A-Za-z0-9_.-]*$/;

function fail(message: string): never {
  throw new Error(`action audiences: ${message}`);
}

function object(value: unknown, label: string): Record<string, unknown> {
  if (typeof value !== "object" || value === null || Array.isArray(value))
    fail(`${label} must be an object`);
  return value as Record<string, unknown>;
}

function named(value: unknown, label: string): string {
  if (typeof value !== "string" || !NAME.test(value)) fail(`invalid ${label}`);
  return value;
}

function steps(value: unknown, label: string): ActionStep[] {
  if (!Array.isArray(value)) fail(`${label} must be an array`);
  return value.map((raw, index) => {
    const step = object(raw, `${label}[${index}]`);
    if (step.kind === "action")
      return { kind: "action", action: named(step.action, "action reference") };
    if (step.kind !== "exec" || typeof step.path !== "string") fail(`unsupported step in ${label}`);
    if (
      !step.path.startsWith("bin/") ||
      isAbsolute(step.path) ||
      step.path.split("/").some((piece) => !piece || piece === ".." || piece === ".")
    )
      fail(`executable must be contained beneath bin/: ${step.path}`);
    return {
      kind: "exec",
      path: step.path,
      ...(step.children === undefined
        ? {}
        : { children: steps(step.children, `${label} children`) }),
    };
  });
}

/** Validate data, including alias availability; files are checked before execution. */
export function parseActionSpec(value: unknown): ActionSpec {
  const spec = object(value, "spec");
  if (spec.version !== 1) fail(`unsupported spec version: ${String(spec.version)}`);
  const actions: Record<string, ActionFamily> = Object.create(null) as Record<string, ActionFamily>;
  for (const [name, raw] of Object.entries(object(spec.actions, "actions"))) {
    named(name, "action name");
    const family = object(raw, `action ${name}`);
    if (family.name !== name) fail(`action identity mismatch: ${name}`);
    const action = named(family.action, "action vocabulary");
    const declaredPlans = object(family.plans, `action ${name} plans`);
    if (Object.keys(declaredPlans).some((audience) => !AUDIENCES.includes(audience as Audience)))
      fail(`unknown audience in ${name}`);
    const available = AUDIENCES.filter((audience) => declaredPlans[audience] !== undefined);
    if (!available.length) fail(`action ${name} has no audience plans`);
    const plans: ActionFamily["plans"] = {};
    for (const audience of available)
      plans[audience] = steps(declaredPlans[audience], `${name} ${audience}`);
    const entryAudience = available.find((audience) => family.entry === `${name}-${audience}.mjs`);
    if (!entryAudience) fail(`invalid qualified real entry for ${name}`);
    if (family.default !== undefined && family.default !== entryAudience)
      fail(`default must match the real entry filename for ${name}`);
    const aliases = [
      ...(family.default === undefined ? [] : [`${name}.mjs`]),
      ...available
        .filter((audience) => audience !== entryAudience)
        .map((audience) => `${name}-${audience}.mjs`),
    ];
    const declaredAliases = family.aliases;
    if (
      !Array.isArray(declaredAliases) ||
      declaredAliases.length !== aliases.length ||
      aliases.some((alias, index) => declaredAliases[index] !== alias)
    )
      fail(`aliases do not match available audiences/default for ${name}`);
    actions[name] = {
      name,
      action,
      entry: family.entry as string,
      aliases,
      plans,
      ...(family.default === undefined ? {} : { default: entryAudience }),
    };
  }
  return { version: 1, actions };
}

/** Lexical invocation chooses the override; physical filename supplies the default. */
export function selectAction(
  spec: ActionSpec,
  invokedPath: string,
  physicalEntry: string,
): ActionSelection {
  if (basename(dirname(physicalEntry)) !== "bin")
    fail("real action entry must live in deployment/bin");
  const entry = basename(physicalEntry);
  const family = Object.values(spec.actions).find((candidate) => candidate.entry === entry);
  if (!family) fail(`unavailable or stale action entry: ${entry}`);
  const invoked = basename(invokedPath);
  if (invoked !== entry && !family.aliases.includes(invoked))
    fail(`unknown or unavailable action alias: ${invoked}`);
  const audience =
    AUDIENCES.find((candidate) => invoked === `${family.name}-${candidate}.mjs`) ??
    (invoked === `${family.name}.mjs`
      ? AUDIENCES.find((candidate) => entry === `${family.name}-${candidate}.mjs`)
      : undefined);
  if (!audience || !family.plans[audience]) fail(`unavailable audience for ${invoked}`);
  return { family, audience, deploymentDir: dirname(dirname(physicalEntry)) };
}

async function executablePath(deploymentDir: string, configured: string): Promise<string> {
  const lexical = resolve(deploymentDir, configured);
  const physical = await realpath(lexical);
  const remainder = relative(deploymentDir, physical);
  if (remainder === ".." || remainder.startsWith(`..${sep}`) || isAbsolute(remainder))
    fail(`executable escapes deployment: ${configured}`);
  return lexical; // Do not erase invocation identity after verifying containment.
}

async function actionPath(selection: ActionSelection, name: string): Promise<string> {
  return executablePath(selection.deploymentDir, `bin/${name}-${selection.audience}.mjs`);
}

/** Validate the entire selected graph before any side effect, including shell bridges' children. */
async function preflight(
  spec: ActionSpec,
  selection: ActionSelection,
  visiting = new Set<string>(),
): Promise<void> {
  if (visiting.has(selection.family.name)) fail(`cyclic action plan: ${selection.family.name}`);
  const seen = new Set(visiting).add(selection.family.name);
  const check = async (plan: ActionStep[]): Promise<void> => {
    for (const step of plan) {
      if (step.kind === "exec") {
        await executablePath(selection.deploymentDir, step.path);
        if (step.children) await check(step.children);
      } else {
        const family = spec.actions[step.action];
        if (!family?.plans[selection.audience])
          fail(`unavailable ${selection.audience} subaction: ${step.action}`);
        const lexical = await actionPath(selection, step.action);
        const physical = await realpath(lexical);
        const selected = selectAction(spec, lexical, physical);
        if (selected.family.name !== step.action || selected.audience !== selection.audience)
          fail(`subaction alias identity mismatch: ${step.action}`);
        await preflight(spec, { ...selection, family }, seen);
      }
    }
  };
  await check(selection.family.plans[selection.audience]!);
}

async function runExecutable(
  path: string,
  argv: string[],
  selection: ActionSelection,
): Promise<ActionOutcome> {
  return new Promise<ActionOutcome>((complete, reject) => {
    const child = spawn(path, argv, {
      cwd: selection.deploymentDir,
      detached: true,
      env: {
        ...process.env,
        DIR: selection.deploymentDir,
        COMPFUZOR_ACTION_AUDIENCE: selection.audience,
      },
      stdio: "inherit",
    });
    const listeners = new Map<NodeJS.Signals, () => void>();
    let interrupted: NodeJS.Signals | undefined;
    const cleanup = (): void => {
      for (const [signal, listener] of listeners) process.off(signal, listener);
    };
    for (const signal of ["SIGINT", "SIGTERM", "SIGHUP"] as const) {
      const listener = (): void => {
        interrupted ??= signal;
        if (child.pid === undefined) return;
        try {
          process.kill(-child.pid, signal);
        } catch (error) {
          if ((error as NodeJS.ErrnoException).code !== "ESRCH") {
            cleanup();
            reject(error);
          }
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
      complete({
        code: code ?? 1,
        ...(interrupted || signal ? { signal: interrupted ?? signal! } : {}),
      });
    });
  });
}

/** Installed entry adapter; source callers can supply a physical deployment entry URL. */
export async function runAction(
  argv: string[],
  invokedPath: string,
  entryUrl: string,
): Promise<ActionOutcome> {
  const physicalEntry = await realpath(fileURLToPath(entryUrl));
  const deploymentDir = dirname(dirname(physicalEntry));
  const spec = parseActionSpec(
    JSON.parse(await readFile(resolve(deploymentDir, "etc/compfuzor-actions/spec.json"), "utf8")),
  );
  const selection = selectAction(spec, invokedPath, physicalEntry);
  if (argv[0] === "--help" || argv[0] === "-h") {
    console.log(
      `Usage: ${basename(invokedPath)} [ARGS...]\n\nAudience: ${selection.audience}\nArguments are forwarded to domain commands.\n\nRuns in order:`,
    );
    for (const step of selection.family.plans[selection.audience]!)
      console.log(
        `  ${step.kind === "action" ? `${step.action}-${selection.audience}.mjs` : step.path}`,
      );
    return { code: 0 };
  }
  await preflight(spec, selection);
  for (const step of selection.family.plans[selection.audience]!) {
    const path =
      step.kind === "action"
        ? await actionPath(selection, step.action)
        : await executablePath(deploymentDir, step.path);
    const outcome = await runExecutable(path, argv, selection);
    if (outcome.code !== 0 || outcome.signal) return outcome;
  }
  return { code: 0 };
}
