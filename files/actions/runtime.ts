/** Shared execution over admitted scoped plans; domain transactions remain independent. */
import { realpath, rm } from "node:fs/promises";
import { basename, dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import {
  AUDIENCES,
  fail,
  selectAction,
  type ActionOutcome,
  type ActionSelection,
  type ActionStep,
} from "./model.ts";
import {
  cleanEnvironment,
  executablePath,
  runExecutable,
  watchInvocationSignals,
  type InvocationSignals,
} from "./process.ts";
import {
  admitRequest,
  captureEnvironment,
  captureSetup,
  createSession,
  domainsIn,
  loadActionSpec,
  readSession,
  setupCwd,
  type ActionSession,
  type LoadedSpec,
  type SessionHandle,
} from "./session.ts";

export { parseActionSpec, selectAction } from "./model.ts";
export type {
  Audience,
  ActionSpec,
  ActionFamily,
  ActionStep,
  ActionOutcome,
  ActionSelection,
} from "./model.ts";
type Execution = {
  selection: ActionSelection;
  loaded: LoadedSpec;
  env: NodeJS.ProcessEnv;
  cwd: string;
  session?: { path: string; data: ActionSession };
  envReady: boolean;
  interrupted?: () => NodeJS.Signals | undefined;
};
let captureSequence = 0;

async function preflight(
  loaded: LoadedSpec,
  selection: ActionSelection,
  visiting = new Set<string>(),
): Promise<void> {
  if (visiting.has(selection.family.name)) fail(`cyclic action plan: ${selection.family.name}`);
  const seen = new Set(visiting).add(selection.family.name);
  const check = async (steps: ActionStep[]): Promise<void> => {
    for (const step of steps) {
      if (step.kind === "domain") await executablePath(selection.deploymentDir, step.envelope);
      else if (step.kind === "exec") {
        await executablePath(selection.deploymentDir, step.path);
        if (step.children) await check(step.children);
      } else {
        const family = loaded.spec.actions[step.action];
        if (!family?.plans[selection.audience])
          fail(`unavailable ${selection.audience} subaction: ${step.action}`);
        const lexical = await executablePath(
          selection.deploymentDir,
          `bin/${step.action}-${selection.audience}.mjs`,
        );
        const selected = selectAction(loaded.spec, lexical, await realpath(lexical));
        if (selected.family.name !== step.action || selected.audience !== selection.audience)
          fail(`subaction alias identity mismatch: ${step.action}`);
        await preflight(loaded, { ...selection, family }, seen);
      }
    }
  };
  await check(selection.family.plans[selection.audience]!);
}

async function executeSteps(
  steps: ActionStep[],
  argv: string[],
  execution: Execution,
): Promise<ActionOutcome> {
  const { selection, session } = execution;
  for (const step of steps) {
    if (execution.interrupted?.()) return { code: 1, signal: execution.interrupted() };
    const env: NodeJS.ProcessEnv = {
      ...cleanEnvironment(execution.env),
      DIR: selection.deploymentDir,
      COMPFUZOR_ACTION_AUDIENCE: selection.audience,
    };
    let configured: string;
    if (step.kind === "domain") {
      if (!session?.data.operations[step.id]) fail(`operation was not admitted: ${step.id}`);
      configured = step.envelope;
      env.COMPFUZOR_ACTION_SESSION = session.path;
      env.COMPFUZOR_ACTION_OPERATION = step.id;
      env.COMPFUZOR_ACTION_OPERATION_MODE = "apply";
    } else if (step.kind === "action") {
      configured = `bin/${step.action}-${selection.audience}.mjs`;
      if (session) env.COMPFUZOR_ACTION_SESSION = session.path;
    } else {
      configured = step.path;
      if (step.children) {
        env.COMPFUZOR_ACTION_BODY = step.path;
        if (session) {
          env.COMPFUZOR_ACTION_SESSION = session.path;
          if (execution.envReady) env.COMPFUZOR_ACTION_ROOT_ENV_READY = selection.family.name;
        }
      }
    }
    const path = await executablePath(selection.deploymentDir, configured);
    const outcome = await runExecutable(path, argv, execution.cwd, env);
    if (outcome.code || outcome.signal) return outcome;
  }
  return { code: 0 };
}

/** Public entries preserve lexical audience identity while rooting in their real file. */
export async function runAction(
  argv: string[],
  invokedPath: string,
  entryUrl: string,
): Promise<ActionOutcome> {
  const physicalEntry = await realpath(fileURLToPath(entryUrl));
  const deploymentDir = dirname(dirname(physicalEntry));
  const loaded = await loadActionSpec(deploymentDir);
  const selection = selectAction(loaded.spec, invokedPath, physicalEntry);
  const inherited = process.env.COMPFUZOR_ACTION_SESSION;
  let session: Execution["session"];
  if (inherited) {
    const data = await readSession(inherited, deploymentDir, loaded);
    if (data.audience !== selection.audience || !data.actions.includes(selection.family.name))
      fail("action is unrelated to inherited session");
    session = { path: inherited, data };
  }
  if (argv[0] === "--help" || argv[0] === "-h") {
    console.log(
      `Usage: ${basename(invokedPath)} [DOMAIN OPTIONS... | CHILD ARGS...]\n\nAudience: ${selection.audience}\nRuns in order:`,
    );
    for (const step of selection.family.plans[selection.audience]!)
      console.log(
        `  ${step.kind === "domain" ? `${step.domain} ${step.operation} context=${step.context}` : step.kind === "action" ? `${step.action}-${selection.audience}.mjs` : step.path}`,
      );
    return { code: 0 };
  }
  await preflight(loaded, selection);
  let owner: SessionHandle | undefined;
  let signals: InvocationSignals | undefined;
  let env = cleanEnvironment();
  let cwd = deploymentDir;
  let envReady = false;
  try {
    if (!session && domainsIn(loaded, selection).operations.length) {
      signals = watchInvocationSignals();
      const prepared = await createSession(
        selection,
        loaded,
        argv,
        resolve(deploymentDir, "bin/compfuzor-runtime.mjs"),
        () => signals?.signal,
      );
      if (!prepared.handle) return prepared.outcome;
      owner = prepared.handle;
      session = { path: owner.path, data: owner.data };
      env = owner.env;
      cwd = owner.cwd;
      envReady = true;
    } else if (session) {
      const output = resolve(dirname(session.path), `env-${process.pid}${captureSequence++}.json`);
      try {
        const setup = selection.family.setup?.[selection.audience] ?? { env: true, basedir: true };
        const directory = setupCwd(selection, process.env);
        const capture = await captureSetup(selection, output, process.env, setup.env, directory);
        if (!capture.captured) return capture.outcome;
        env = capture.captured.env;
        cwd = capture.captured.cwd;
        envReady = true;
      } finally {
        await rm(output, { force: true });
      }
    }
    const outcome = await executeSteps(selection.family.plans[selection.audience]!, argv, {
      selection,
      loaded,
      session,
      env,
      cwd,
      envReady,
      interrupted: () => signals?.signal,
    });
    return signals?.signal ? { code: 1, signal: signals.signal } : outcome;
  } finally {
    await owner?.dispose();
    signals?.stop();
  }
}

/** Private bridge admission and single child runner; no public operation/context wrappers. */
export async function main(
  argv: string[],
  deploymentDir: string,
  runtimePath: string,
): Promise<ActionOutcome> {
  const [command, ...args] = argv;
  if (command === "capture-env" && args.length === 1)
    return { code: await captureEnvironment(args[0]) };
  if (command === "admit" && args.length === 1)
    return { code: await admitRequest(args[0], deploymentDir, runtimePath) };
  if (command !== "guard" && command !== "children")
    fail("internal actions command is guard, children, admit, or capture-env");
  const [name, audience, path, ...childArgv] = args;
  if (
    !name ||
    !path ||
    !AUDIENCES.includes(audience as "user" | "system") ||
    (command === "guard" && childArgv.length)
  )
    fail("internal usage: actions guard|children NAME user|system bin/BODY [ARGS...]");
  const loaded = await loadActionSpec(deploymentDir);
  const family = loaded.spec.actions[name];
  const body = family?.plans[audience as "user" | "system"]?.find(
    (step) => step.kind === "exec" && step.path === path && step.children !== undefined,
  );
  if (!body || body.kind !== "exec") fail(`unavailable or stale authored action body: ${path}`);
  const selection: ActionSelection = {
    family,
    audience: audience as "user" | "system",
    deploymentDir,
  };
  await preflight(loaded, selection);
  const inherited = process.env.COMPFUZOR_ACTION_SESSION;
  if (!inherited) {
    if (domainsIn(loaded, selection).operations.length || command === "children")
      fail("typed action body requires a prepared invocation");
    return { code: 0 };
  }
  const data = await readSession(inherited, deploymentDir, loaded);
  if (data.audience !== selection.audience || !data.actions.includes(name))
    fail("body is unrelated to prepared action graph");
  if (command === "guard") return { code: 0 };
  return executeSteps(body.children!, childArgv, {
    selection,
    loaded,
    env: process.env,
    cwd: process.cwd(),
    session: { path: inherited, data },
    envReady: false,
  });
}

/** Legacy exported guard retained for existing source consumers. */
export async function guardActionBody(argv: string[], deploymentDir: string): Promise<number> {
  return (await main(argv, deploymentDir, resolve(deploymentDir, "bin/compfuzor-runtime.mjs")))
    .code;
}
