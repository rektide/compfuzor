/** Invocation-private transport for selected complete operations, never a durable registry. */
import { createHash } from "node:crypto";
import { lstat, mkdtemp, readFile, realpath, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { basename, dirname, isAbsolute, resolve } from "node:path";
import {
  applyOperation,
  prepareOperation,
  verifyPreparedOperation,
  type PreparedOperation,
} from "./operations.ts";
import {
  AUDIENCES,
  domainStep,
  fail,
  object,
  knownKeys,
  parseActionSpec,
  type ActionFamily,
  type ActionOutcome,
  type ActionSelection,
  type ActionSpec,
  type ActionStep,
  type Audience,
  type DomainStep,
} from "./model.ts";
import { cleanEnvironment, clearProcessMarkers, executablePath, runExecutable } from "./process.ts";

const MAX_BYTES = 8 * 1024 * 1024;
const MAX_OPERATIONS = 128;
export type SessionOperation = { family: string; step: DomainStep; prepared: PreparedOperation };
export type ActionSession = {
  version: 1;
  kind: "action-session";
  directory: string;
  ownerPid: number;
  deploymentDir: string;
  specDigest: string;
  rootAction: string;
  audience: Audience;
  actions: string[];
  operations: Record<string, SessionOperation>;
};
export type LoadedSpec = { spec: ActionSpec; digest: string };
export type SessionHandle = {
  path: string;
  data: ActionSession;
  env: NodeJS.ProcessEnv;
  cwd: string;
  dispose: () => Promise<void>;
};
type EnvironmentCapture = { version: 1; env: NodeJS.ProcessEnv; cwd: string };
type OperationRequest = {
  version: 1;
  kind: "operation-request";
  deploymentDir: string;
  specDigest: string;
  family: string;
  audience: Audience;
  step: DomainStep;
  argv: string[];
};

export async function loadActionSpec(deploymentDir: string): Promise<LoadedSpec> {
  const bytes = await readFile(resolve(deploymentDir, "etc/compfuzor-actions/spec.json"));
  if (bytes.length > MAX_BYTES) fail("action spec exceeds size bound");
  return {
    spec: parseActionSpec(JSON.parse(bytes.toString("utf8"))),
    digest: createHash("sha256").update(bytes).digest("hex"),
  };
}
async function privateDirectory(path: string): Promise<void> {
  const entry = await lstat(path);
  if (
    !entry.isDirectory() ||
    entry.mode & 0o077 ||
    entry.uid !== process.geteuid?.() ||
    basename(path).startsWith("compfuzor-actions-") === false ||
    (await realpath(path)) !== resolve(path)
  )
    fail("invalid private action directory");
}
async function writePrivate(path: string, value: unknown): Promise<void> {
  await privateDirectory(dirname(path));
  const json = JSON.stringify(value);
  if (Buffer.byteLength(json) > MAX_BYTES) fail("private action payload exceeds size bound");
  await writeFile(path, json, { mode: 0o600, flag: "wx" });
}
async function readPrivate(path: string): Promise<unknown> {
  if (!isAbsolute(path)) fail("private action path must be absolute");
  await privateDirectory(dirname(path));
  const entry = await lstat(path);
  if (
    !entry.isFile() ||
    entry.uid !== process.geteuid?.() ||
    entry.mode & 0o077 ||
    entry.size > MAX_BYTES
  )
    fail("invalid private action file");
  return JSON.parse(await readFile(path, "utf8"));
}

/** Transport must remain beneath its live owner, not become an ambient replay capability. */
async function ownsInvocation(owner: unknown): Promise<boolean> {
  if (!Number.isSafeInteger(owner) || Number(owner) <= 0) return false;
  let pid = process.pid;
  for (let depth = 0; pid > 0 && depth < MAX_OPERATIONS; depth++) {
    if (pid === owner) return true;
    const status = await readFile(`/proc/${pid}/status`, "utf8");
    pid = Number(/^PPid:\s+(\d+)$/m.exec(status)?.[1] ?? 0);
  }
  return false;
}
export function domainsIn(
  loaded: LoadedSpec,
  selection: ActionSelection,
): { actions: string[]; operations: Array<{ family: string; step: DomainStep }> } {
  const actions = new Set<string>();
  const operations = new Map<string, { family: string; step: DomainStep }>();
  const visit = (family: ActionFamily, visiting: Set<string>): void => {
    if (visiting.has(family.name)) fail(`cyclic action plan: ${family.name}`);
    actions.add(family.name);
    const next = new Set(visiting).add(family.name);
    const walk = (steps: ActionStep[]): void => {
      for (const step of steps) {
        if (step.kind === "domain") {
          const existing = operations.get(step.id);
          if (
            existing &&
            (existing.family !== family.name ||
              JSON.stringify(existing.step) !== JSON.stringify(step))
          )
            fail("duplicate operation ID");
          operations.set(step.id, { family: family.name, step });
        } else if (step.kind === "action") {
          const target = loaded.spec.actions[step.action];
          if (!target?.plans[selection.audience])
            fail(`unavailable ${selection.audience} subaction: ${step.action}`);
          visit(target, next);
        } else if (step.children) walk(step.children);
      }
    };
    walk(family.plans[selection.audience]!);
  };
  visit(selection.family, new Set());
  if (operations.size > MAX_OPERATIONS || actions.size > MAX_OPERATIONS)
    fail("selected action graph exceeds operation bound");
  return { actions: [...actions], operations: [...operations.values()] };
}

export async function readSession(
  path: string,
  deploymentDir: string,
  loaded: LoadedSpec,
): Promise<ActionSession> {
  if (basename(path) !== "session.json") fail("unknown action session path");
  const raw = object(await readPrivate(path), "action session");
  knownKeys(
    raw,
    [
      "version",
      "kind",
      "directory",
      "ownerPid",
      "deploymentDir",
      "specDigest",
      "rootAction",
      "audience",
      "actions",
      "operations",
    ],
    "action session",
  );
  if (
    raw.version !== 1 ||
    raw.kind !== "action-session" ||
    raw.directory !== dirname(path) ||
    !(await ownsInvocation(raw.ownerPid)) ||
    raw.deploymentDir !== deploymentDir ||
    raw.specDigest !== loaded.digest ||
    !AUDIENCES.includes(raw.audience as Audience) ||
    typeof raw.rootAction !== "string" ||
    !Array.isArray(raw.actions)
  )
    fail("stale or foreign action session");
  const root = loaded.spec.actions[raw.rootAction];
  if (!root?.plans[raw.audience as Audience]) fail("unavailable session root action");
  const selected = domainsIn(loaded, {
    family: root,
    audience: raw.audience as Audience,
    deploymentDir,
  });
  if (JSON.stringify(raw.actions) !== JSON.stringify(selected.actions))
    fail("session action graph mismatch");
  const values = object(raw.operations, "session operations");
  if (Object.keys(values).length !== selected.operations.length)
    fail("session operation set mismatch");
  const operations: ActionSession["operations"] = Object.create(
    null,
  ) as ActionSession["operations"];
  for (const declared of selected.operations) {
    const entry = object(values[declared.step.id], "prepared operation");
    knownKeys(entry, ["family", "step", "prepared"], "session operation");
    if (
      entry.family !== declared.family ||
      JSON.stringify(entry.step) !== JSON.stringify(declared.step)
    )
      fail("session operation declaration mismatch");
    const prepared = object(entry.prepared, "prepared state") as PreparedOperation;
    verifyPreparedOperation(prepared, declared.step, raw.audience as Audience);
    operations[declared.step.id] = { ...declared, prepared };
  }
  return {
    version: 1,
    kind: "action-session",
    directory: dirname(path),
    ownerPid: raw.ownerPid as number,
    deploymentDir,
    specDigest: loaded.digest,
    rootAction: raw.rootAction,
    audience: raw.audience as Audience,
    actions: selected.actions,
    operations,
  };
}

function setupCwd(selection: ActionSelection, env: NodeJS.ProcessEnv): string {
  const basedir = selection.family.setup?.[selection.audience]?.basedir ?? true;
  if (basedir === false || basedir === true) return selection.deploymentDir;
  return basedir.startsWith("~")
    ? resolve(env.HOME ?? fail("HOME required for action setup"), basedir.slice(2))
    : resolve(selection.deploymentDir, basedir);
}
export async function captureEnvironment(output: string): Promise<number> {
  if (!/^env-[0-9]+\.json$/.test(basename(output))) fail("invalid environment capture destination");
  await writePrivate(output, { version: 1, env: cleanEnvironment(), cwd: process.cwd() });
  return 0;
}
export async function captureSetup(
  selection: ActionSelection,
  output: string,
  env: NodeJS.ProcessEnv,
  sourceEnv: boolean,
  cwd: string,
  useBody = true,
): Promise<{ outcome: ActionOutcome; captured?: EnvironmentCapture }> {
  const body = useBody
    ? selection.family.plans[selection.audience]?.find(
        (step) => step.kind === "exec" && step.children !== undefined,
      )
    : undefined;
  const path = await executablePath(
    selection.deploymentDir,
    body?.kind === "exec" ? body.path : "bin/internal/action-environment.sh",
  );
  const setupEnv: NodeJS.ProcessEnv = { ...cleanEnvironment(env), DIR: selection.deploymentDir };
  if (body) {
    setupEnv.COMPFUZOR_ACTION_PREPARE_ENV = output;
    if (!sourceEnv) setupEnv.COMPFUZOR_ACTION_ROOT_ENV_READY = selection.family.name;
  }
  const outcome = await runExecutable(
    path,
    body ? [] : [sourceEnv ? "1" : "0", cwd, output],
    selection.deploymentDir,
    setupEnv,
  );
  if (outcome.code || outcome.signal) return { outcome };
  const raw = object(await readPrivate(output), "environment capture");
  knownKeys(raw, ["version", "env", "cwd"], "environment capture");
  const values = object(raw.env, "captured environment");
  if (
    raw.version !== 1 ||
    typeof raw.cwd !== "string" ||
    Object.values(values).some((value) => typeof value !== "string")
  )
    fail("invalid environment capture");
  return {
    outcome,
    captured: {
      version: 1,
      env: { ...(values as NodeJS.ProcessEnv), DIR: selection.deploymentDir },
      cwd: raw.cwd,
    },
  };
}

export async function createSession(
  selection: ActionSelection,
  loaded: LoadedSpec,
  argv: string[],
  runtimePath: string,
  interrupted: () => NodeJS.Signals | undefined = () => undefined,
): Promise<{ handle?: SessionHandle; outcome: ActionOutcome }> {
  const directory = await mkdtemp(resolve(tmpdir(), "compfuzor-actions-"));
  const dispose = async (): Promise<void> => {
    await rm(directory, { recursive: true, force: true });
  };
  let transferred = false;
  try {
    if (interrupted()) return { outcome: { code: 1, signal: interrupted() } };
    const sourceEnv = selection.family.setup?.[selection.audience]?.env ?? true;
    const root = await captureSetup(
      selection,
      resolve(directory, "env-0.json"),
      process.env,
      sourceEnv,
      setupCwd(selection, process.env),
    );
    if (root.outcome.code || root.outcome.signal) return { outcome: root.outcome };
    let leaf = root.captured!;
    if (
      !sourceEnv &&
      domainsIn(loaded, selection).operations.some((entry) => entry.step.domain === "keybindings")
    ) {
      const capture = await captureSetup(
        selection,
        resolve(directory, "env-1.json"),
        leaf.env,
        true,
        leaf.cwd,
        false,
      );
      if (capture.outcome.code || capture.outcome.signal) return { outcome: capture.outcome };
      leaf = capture.captured!;
    }
    const graph = domainsIn(loaded, selection);
    const data: ActionSession = {
      version: 1,
      kind: "action-session",
      directory,
      ownerPid: process.pid,
      deploymentDir: selection.deploymentDir,
      specDigest: loaded.digest,
      rootAction: selection.family.name,
      audience: selection.audience,
      actions: graph.actions,
      operations: Object.create(null) as ActionSession["operations"],
    };
    for (const [index, entry] of graph.operations.entries()) {
      if (interrupted()) return { outcome: { code: 1, signal: interrupted() } };
      const request = resolve(directory, `request-${index}.json`);
      await writePrivate(request, {
        version: 1,
        kind: "operation-request",
        deploymentDir: selection.deploymentDir,
        specDigest: loaded.digest,
        family: entry.family,
        audience: selection.audience,
        step: entry.step,
        argv,
      } satisfies OperationRequest);
      const outcome = await runExecutable(
        runtimePath,
        ["actions", "admit", request],
        selection.deploymentDir,
        {
          ...cleanEnvironment(entry.step.domain === "keybindings" ? leaf.env : root.captured!.env),
          DIR: selection.deploymentDir,
        },
      );
      if (outcome.code || outcome.signal) return { outcome };
      const prepared = object(
        await readPrivate(request + ".prepared"),
        "prepared domain",
      ) as PreparedOperation;
      verifyPreparedOperation(prepared, entry.step, selection.audience);
      if (prepared.domain === "help") {
        console.log(prepared.message);
        return { outcome: { code: 0 } };
      }
      data.operations[entry.step.id] = { ...entry, prepared };
    }
    const path = resolve(directory, "session.json");
    if (interrupted()) return { outcome: { code: 1, signal: interrupted() } };
    await writePrivate(path, data);
    for (const name of [
      "env-0.json",
      "env-1.json",
      ...graph.operations.flatMap((_, index) => [
        `request-${index}.json`,
        `request-${index}.json.prepared`,
      ]),
    ])
      await rm(resolve(directory, name), { force: true });
    transferred = true;
    return {
      outcome: { code: 0 },
      handle: { path, data, env: root.captured!.env, cwd: root.captured!.cwd, dispose },
    };
  } finally {
    if (!transferred) await dispose();
  }
}

export async function admitRequest(
  path: string,
  deploymentDir: string,
  runtimePath: string,
): Promise<number> {
  if (!/^request-[0-9]+\.json$/.test(basename(path))) fail("invalid operation request path");
  const raw = object(await readPrivate(path), "operation request");
  knownKeys(
    raw,
    ["version", "kind", "deploymentDir", "specDigest", "family", "audience", "step", "argv"],
    "operation request",
  );
  const loaded = await loadActionSpec(deploymentDir);
  if (
    raw.version !== 1 ||
    raw.kind !== "operation-request" ||
    raw.deploymentDir !== deploymentDir ||
    raw.specDigest !== loaded.digest ||
    !AUDIENCES.includes(raw.audience as Audience) ||
    typeof raw.family !== "string" ||
    !Array.isArray(raw.argv) ||
    raw.argv.some((arg) => typeof arg !== "string")
  )
    fail("stale or foreign operation request");
  const step = domainStep(raw.step);
  const family = loaded.spec.actions[raw.family];
  if (
    !family?.plans[raw.audience as Audience] ||
    !domainsIn(loaded, {
      family,
      audience: raw.audience as Audience,
      deploymentDir,
    }).operations.some(
      (entry) => entry.family === raw.family && JSON.stringify(entry.step) === JSON.stringify(step),
    )
  )
    fail("unknown operation request");
  clearProcessMarkers();
  const prepared = await prepareOperation(
    step,
    raw.audience as Audience,
    raw.argv as string[],
    deploymentDir,
    runtimePath,
  );
  await writePrivate(path + ".prepared", prepared);
  return 0;
}

export async function applyPrepared(
  path: string,
  id: string,
  domain: string,
  deploymentDir: string,
  invokedAs: string,
): Promise<number> {
  const loaded = await loadActionSpec(deploymentDir);
  const session = await readSession(path, deploymentDir, loaded);
  const entry = session.operations[id];
  if (!entry || entry.step.domain !== domain) fail("unknown or unrelated prepared operation");
  if (invokedAs !== (domain === "config" ? basename(entry.step.envelope) : "keybindings.mjs"))
    fail("prepared operation invoked through an unrelated domain alias");
  clearProcessMarkers();
  return applyOperation(entry.prepared);
}
