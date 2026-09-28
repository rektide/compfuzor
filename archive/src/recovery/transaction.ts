/** Append-only receipt + pin installation. Caller must verify bundle, receipt, source/dest drift first. */
import { execFile as callbackExecFile } from "node:child_process";
import { promisify } from "node:util";
import { CustodyError, invalid } from "../custody/errors.ts";
import { oid, refName } from "../custody/codec.ts";
import type { GitObjectFormat, Oid, PinIntent, RefName } from "../custody/model.ts";

const execFile = promisify(callbackExecFile);
const utf8 = new TextDecoder("utf-8", { fatal: true });
function gitEnvironment(): NodeJS.ProcessEnv {
  const env: NodeJS.ProcessEnv = {
    ...process.env,
    GIT_CONFIG_NOSYSTEM: "1",
    GIT_CONFIG_GLOBAL: "/dev/null",
  };
  for (const key of Object.keys(env))
    if (key.startsWith("GIT_") && key !== "GIT_CONFIG_NOSYSTEM" && key !== "GIT_CONFIG_GLOBAL")
      delete env[key];
  return env;
}
type RefTarget = Readonly<{ ref: RefName; oid: Oid }>;

/** A reader/runner injection point: tests can simulate races without mutating real repositories. */
export interface RefStore {
  list(): Promise<ReadonlyMap<string, string>>;
  createAtomically(missing: readonly RefTarget[]): Promise<void>;
}

export interface RefInstall {
  readonly receiptRef: RefName;
  readonly receiptCommitOid: Oid;
  readonly pins: readonly PinIntent[];
  /** Only true after a separate caller checked existing receipt content and original plan. */
  readonly matchingReceiptApproved: boolean;
}
export interface InstallResult {
  readonly changed: boolean;
  readonly created: readonly RefName[];
  readonly alreadyPresent: readonly RefName[];
}

function requiredRefs(input: RefInstall): readonly RefTarget[] {
  const refs: RefTarget[] = [{ ref: refName(input.receiptRef), oid: input.receiptCommitOid }];
  const unique = new Set<string>([input.receiptRef]);
  for (const pin of input.pins) {
    const ref = refName(pin.destinationRef);
    if (unique.has(ref)) invalid(`duplicate custody ref: ${ref}`);
    unique.add(ref);
    refs.push({ ref, oid: pin.destinationOid });
  }
  return refs;
}

/** Ref file/directory conflicts also exist when the exact leaf does not yet exist. */
export function prefixConflict(name: string, other: string): boolean {
  return name !== other && (name.startsWith(`${other}/`) || other.startsWith(`${name}/`));
}

export function decideInstallation(
  observed: ReadonlyMap<string, string>,
  input: RefInstall,
): Readonly<{ missing: readonly RefTarget[]; alreadyPresent: readonly RefName[] }> {
  const desired = requiredRefs(input);
  const existingReceipt = observed.get(input.receiptRef);
  if (existingReceipt !== undefined && existingReceipt !== input.receiptCommitOid) {
    throw new CustodyError(
      "different-receipt",
      `receipt ref has another OID: ${input.receiptRef}`,
      input.receiptRef,
    );
  }
  if (existingReceipt !== undefined && !input.matchingReceiptApproved) {
    throw new CustodyError(
      "different-receipt",
      "existing receipt has not passed same-input/intent review",
      input.receiptRef,
    );
  }
  if (
    existingReceipt === undefined &&
    desired.some(({ ref }) => ref !== input.receiptRef && observed.has(ref))
  ) {
    throw new CustodyError(
      "occupied-namespace",
      "pin exists without an approved matching receipt; inspect manually",
    );
  }
  const label = input.receiptRef.split("/")[3];
  for (const old of [
    `refs/heads/harvest/${label}/head`,
    `refs/heads/harvest/${label}/working-copy`,
  ]) {
    if (observed.has(old))
      throw new CustodyError(
        "occupied-namespace",
        `legacy harvest namespace under this label: ${old}`,
        old,
      );
  }
  const missing: RefTarget[] = [];
  const alreadyPresent: RefName[] = [];
  for (const { ref, oid: expected } of desired) {
    for (const other of observed.keys()) {
      if (prefixConflict(ref, other))
        throw new CustodyError(
          "occupied-namespace",
          `ref prefix conflict: ${ref} versus ${other}`,
          ref,
        );
    }
    const actual = observed.get(ref);
    if (actual !== undefined && actual !== expected)
      throw new CustodyError("occupied-namespace", `ref has another OID: ${ref}`, ref);
    if (actual === expected) alreadyPresent.push(ref);
    else missing.push({ ref, oid: expected });
  }
  return { missing, alreadyPresent };
}

/** No automatic repair: even on a failed Git transaction, inspect refs again on retry. */
export async function installImmutableRefs(
  store: RefStore,
  input: RefInstall,
): Promise<InstallResult> {
  const observed = await store.list();
  const { missing, alreadyPresent } = decideInstallation(observed, input);
  if (missing.length === 0) return { changed: false, created: [], alreadyPresent };
  try {
    await store.createAtomically(missing);
  } catch (error) {
    throw new CustodyError(
      "ref-race",
      `atomic compare-and-create failed; inspect refs before retry: ${error instanceof Error ? error.message : String(error)}`,
    );
  }
  return { changed: true, created: missing.map(({ ref }) => ref), alreadyPresent };
}

/** All Git calls are scoped to a validated colocated destination, without hooks/maintenance. */
export class GitRefStore implements RefStore {
  public readonly dest: string;
  public readonly format: GitObjectFormat;
  public constructor(dest: string, format: GitObjectFormat) {
    this.dest = dest;
    this.format = format;
  }

  public async list(): Promise<ReadonlyMap<string, string>> {
    const { stdout } = await execFile(
      "git",
      [
        "-C",
        this.dest,
        "-c",
        "maintenance.auto=false",
        "for-each-ref",
        "--format=%(refname)%00%(objectname)%00%(symref)",
      ],
      {
        encoding: "buffer",
        maxBuffer: 64 * 1024 * 1024,
        env: { ...gitEnvironment(), GIT_OPTIONAL_LOCKS: "0" },
      },
    );
    const refs = new Map<string, string>();
    let output: string;
    try {
      output = utf8.decode(stdout);
    } catch {
      throw new CustodyError("inspection-failed", "destination refs contain invalid UTF-8");
    }
    for (const line of output.split("\n")) {
      if (!line) continue;
      const [name, target, symbolic, ...extra] = line.split("\0");
      if (extra.length || !name || !target || symbolic)
        throw new CustodyError("inspection-failed", "symbolic or malformed destination ref");
      const validated = refName(name);
      if (refs.has(validated))
        throw new CustodyError("inspection-failed", "duplicate destination ref");
      refs.set(validated, oid(target, this.format));
    }
    return refs;
  }

  public async createAtomically(missing: readonly RefTarget[]): Promise<void> {
    if (missing.length === 0) return;
    const commands = [
      "start",
      ...missing.map(
        ({ ref, oid: target }) => `create ${refName(ref)} ${oid(target, this.format)}`,
      ),
      "prepare",
      "commit",
      "",
    ].join("\n");
    // update-ref `create` is expected-old zero and fails if any ref appears, including
    // a packed ref. prepare+commit is one Git ref transaction; no partial success.
    const { spawn } = await import("node:child_process");
    await new Promise<void>((resolve, reject) => {
      const child = spawn(
        "git",
        [
          "-C",
          this.dest,
          "-c",
          "core.hooksPath=/dev/null",
          "-c",
          "maintenance.auto=false",
          "update-ref",
          "--no-deref",
          "--stdin",
        ],
        {
          stdio: ["pipe", "ignore", "pipe"],
          env: gitEnvironment(),
        },
      );
      const stderr: Buffer[] = [];
      child.stderr.on("data", (part: Buffer) => stderr.push(part));
      child.on("error", reject);
      child.on("close", (status) =>
        status === 0
          ? resolve()
          : reject(
              new Error(
                `git update-ref exited ${status}: ${Buffer.concat(stderr).toString("utf8").trim()}`,
              ),
            ),
      );
      child.stdin.end(commands);
    });
  }
}
