/** Process boundary: physical admission, lexical execution and explicit marker inheritance. */
import { spawn } from "node:child_process";
import { access, constants, realpath, stat } from "node:fs/promises";
import { isAbsolute, relative, resolve, sep } from "node:path";
import { fail, type ActionOutcome } from "./model.ts";

export const MARKERS: readonly string[] = [
  "COMPFUZOR_ACTION_PREPARE_ENV",
  "COMPFUZOR_ACTION_SESSION",
  "COMPFUZOR_ACTION_OPERATION",
  "COMPFUZOR_ACTION_OPERATION_MODE",
  "COMPFUZOR_ACTION_BODY",
  "COMPFUZOR_ACTION_ROOT_ENV_READY",
];
export function cleanEnvironment(env: NodeJS.ProcessEnv = process.env): NodeJS.ProcessEnv {
  const result = { ...env };
  for (const key of MARKERS) delete result[key];
  return result;
}
export function clearProcessMarkers(): void {
  for (const key of MARKERS) delete process.env[key];
}
export type InvocationSignals = { signal?: NodeJS.Signals; stop: () => void };
/** Keep cleanup possible between child processes too; active children still receive forwarding. */
export function watchInvocationSignals(): InvocationSignals {
  const listeners = new Map<NodeJS.Signals, () => void>();
  const state: InvocationSignals = {
    stop: () => {
      for (const [signal, listener] of listeners) process.off(signal, listener);
    },
  };
  for (const signal of ["SIGINT", "SIGTERM", "SIGHUP"] as const) {
    const listener = (): void => {
      state.signal ??= signal;
    };
    listeners.set(signal, listener);
    process.on(signal, listener);
  }
  return state;
}
export async function executablePath(deploymentDir: string, configured: string): Promise<string> {
  const lexical = resolve(deploymentDir, configured);
  const physical = await realpath(lexical);
  const remainder = relative(deploymentDir, physical);
  if (remainder === ".." || remainder.startsWith(`..${sep}`) || isAbsolute(remainder))
    fail(`executable escapes deployment: ${configured}`);
  if (!(await stat(physical)).isFile()) fail(`executable is not a regular file: ${configured}`);
  await access(physical, constants.X_OK);
  return lexical;
}
export async function runExecutable(
  path: string,
  argv: string[],
  cwd: string,
  env: NodeJS.ProcessEnv,
): Promise<ActionOutcome> {
  return new Promise((complete, reject) => {
    const child = spawn(path, argv, { cwd, env, detached: true, stdio: "inherit" });
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
