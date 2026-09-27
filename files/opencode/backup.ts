#!/usr/bin/env node
/**
 * Mirror opencode user state to backup targets, with per-run btrfs snapshot
 * versioning and an on-demand consistent-snapshot mode. TypeScript port of
 * bin/backup.sh (kept side by side until retired); CLI via node:util
 * parse-args.
 *
 * Targets are space-separated in BACKUP_TARGETS (defaults come from the
 * deployment env.export loadConfig() sources); each entry is a local path or
 * an rsync remote spec (user@host:/path — mirrored over ssh; btrfs operations
 * run by ssh'ing into the host). BACKUP_ROOT overrides with a single target
 * for ad-hoc runs. A missing or unmounted target is skipped with a warning
 * but still fails the run overall.
 *
 * Versioning, per target:
 *   * btrfs targets: the mirror at <target>/opencode is kept as a btrfs
 *     subvolume; after each successful rsync a readonly snapshot is taken
 *     into <target>/.snapshots/opencode-<stamp> and the snapshot set is
 *     pruned to BACKUP_SNAPSHOT_KEEP (default 14, 0 disables pruning).
 *     Readonly snapshot deletion needs root even with
 *     user_subvol_rm_allowed: plain delete, then sudo -n, then warn.
 *   * --snapshot: on-demand, consistent per-DB snapshots using sqlite3
 *     .backup (WAL-safe, no server stop needed) into
 *     <target>/consistent-snapshot-<stamp>/ with PRAGMA integrity_check
 *     verified and SHA256SUMS + backup.log written.
 *
 * Runtime shape: no import-time side effects. main() builds the run
 * configuration once via loadConfig() and threads it explicitly through the
 * helpers, so the module is importable without touching process.env, and
 * every helper's data flow is visible in its signature. Staged --snapshot
 * directories are cleaned on normal exits and on SIGINT/SIGTERM.
 */

import { spawn } from "node:child_process";
import { createHash } from "node:crypto";
import { createReadStream, rmSync } from "node:fs";
import {
  access,
  mkdtemp,
  readFile,
  readdir,
  realpath,
  rm,
  stat,
  writeFile,
} from "node:fs/promises";
import { tmpdir } from "node:os";
import { basename, dirname, isAbsolute, join } from "node:path";
import { parseArgs } from "node:util";

const SCRIPT_NAME = "backup.ts";
const SNAPDIR_NAME = ".snapshots";
const SNAP_PREFIX = "opencode";

class BackupError extends Error {
  readonly code: number;

  constructor(message: string, code = 1) {
    super(message);
    this.code = code;
  }
}

/** Everything derived from the environment, built once per run. */
interface Config {
  readonly dataSrc: string;
  readonly configSrc: string;
  readonly targets: string[];
  readonly snapshotKeep: number;
  readonly snapshotsEnabled: boolean;
  readonly backupSsh: string;
  readonly sshOptionArgs: string[];
}

async function exists(path: string): Promise<boolean> {
  return access(path).then(
    () => true,
    () => false,
  );
}

// Set-if-unset sourcing of the deployment env.export (envdefault semantics:
// an inherited environment always wins), so rendered defaults like
// BACKUP_TARGETS reach this bin without Jinja in this file.
async function sourceEnv(path: string): Promise<void> {
  if (!(await exists(path))) return;
  for (const line of (await readFile(path, "utf8")).split("\n")) {
    const match = line.trim().match(/^(?:export\s+)?([A-Za-z_][A-Za-z0-9_]*)=(.*)$/);
    if (match && process.env[match[1]] === undefined) {
      process.env[match[1]] = match[2].replace(/^["']|["']$/g, "");
    }
  }
}

async function loadConfig(): Promise<Config> {
  // import.meta.dirname is <DIR>/bin; the deployment root is one dirname up.
  await sourceEnv(join(dirname(import.meta.dirname), "env.export"));
  const home = process.env.HOME ?? "/home/rektide";
  const backupRoot = process.env.BACKUP_ROOT ?? "";
  const backupSsh = process.env.BACKUP_SSH ?? "";
  return {
    dataSrc: join(home, ".local/share/opencode"),
    configSrc: join(home, ".config/opencode"),
    targets: (backupRoot || process.env.BACKUP_TARGETS || "").split(/\s+/).filter(Boolean),
    snapshotKeep: Number.parseInt(process.env.BACKUP_SNAPSHOT_KEEP ?? "14", 10),
    snapshotsEnabled: (process.env.BACKUP_SNAPSHOTS ?? "1") !== "0",
    backupSsh,
    sshOptionArgs: backupSsh ? backupSsh.split(/\s+/).filter(Boolean) : [],
  };
}

const pad = (n: number): string => String(n).padStart(2, "0");

function stamp(d = new Date()): string {
  return (
    `${d.getFullYear()}${pad(d.getMonth() + 1)}${pad(d.getDate())}` +
    `T${pad(d.getHours())}${pad(d.getMinutes())}${pad(d.getSeconds())}`
  );
}

function log(message: string): void {
  const d = new Date();
  const ts =
    `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}` +
    `T${pad(d.getHours())}:${pad(d.getMinutes())}:${pad(d.getSeconds())}`;
  console.log(`[${ts}] ${message}`);
}

function isoLocal(d = new Date()): string {
  const offset = -d.getTimezoneOffset();
  const sign = offset >= 0 ? "+" : "-";
  const abs = Math.abs(offset);
  return (
    `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}` +
    `T${pad(d.getHours())}:${pad(d.getMinutes())}:${pad(d.getSeconds())}` +
    `${sign}${pad(Math.floor(abs / 60))}${pad(abs % 60)}`
  );
}

interface Result {
  code: number;
  stdout: string;
  stderr: string;
}

// Run a command on a target host (empty host = locally). cfg carries the
// BACKUP_SSH options, word-split into extra ssh args for remote runs.
function run(
  cfg: Config,
  command: string,
  args: string[],
  host = "",
  inherit = false,
): Promise<Result> {
  const argv = host ? ["ssh", ...cfg.sshOptionArgs, host, command, ...args] : [command, ...args];
  return new Promise((resolve, reject) => {
    const child = spawn(argv[0]!, argv.slice(1), {
      stdio: inherit ? "inherit" : ["ignore", "pipe", "pipe"],
    });
    let stdout = "";
    let stderr = "";
    if (!inherit) {
      child.stdout?.on("data", (chunk: Buffer) => {
        stdout += chunk;
      });
      child.stderr?.on("data", (chunk: Buffer) => {
        stderr += chunk;
      });
    }
    child.once("error", reject);
    child.once("close", (code) => resolve({ code: code ?? 1, stdout, stderr }));
  });
}

function sshE(cfg: Config, host: string): string[] {
  return host && cfg.backupSsh ? ["-e", `ssh ${cfg.backupSsh}`] : [];
}

async function runRsync(
  cfg: Config,
  label: string,
  args: string[],
  dryRun: boolean,
): Promise<void> {
  const completion = dryRun ? "dry run complete" : "complete";
  log(`starting ${label}`);
  const result = await run(cfg, "rsync", args, "", true);
  if (result.code === 0) {
    log(`${label} ${completion}`);
  } else if (result.code === 24) {
    log(
      `${label} ${completion} with warnings (rsync 24: some source files vanished during copy - usually benign for live backups)`,
    );
  } else {
    throw new BackupError(`rsync failed with code ${result.code} during ${label}`, result.code);
  }
}

// realpath -m: resolve symlinks on the deepest existing ancestor and append
// the missing remainder.
async function resolveMaybe(path: string): Promise<string> {
  const missing: string[] = [];
  let current = path;
  for (;;) {
    try {
      return join(await realpath(current), ...missing);
    } catch {
      // not here yet; walk up
    }
    const parent = dirname(current);
    if (parent === current) return join(current, ...missing);
    missing.unshift(current.slice(parent.length + 1) || basename(current));
    current = parent;
  }
}

async function guardDestination(destination: string, sources: string[]): Promise<void> {
  const destinationReal = await resolveMaybe(destination);
  for (const source of sources) {
    const sourceReal = await realpath(source);
    if (destinationReal === sourceReal || destinationReal.startsWith(`${sourceReal}/`)) {
      throw new BackupError(
        `backup destination must not equal or be inside a source: ${destination}`,
      );
    }
  }
}

// Remote specs: user@host:/path (colon before any slash) or rsync:// URLs.
// rsync:// targets mirror fine but support no ssh-driven btrfs ops.
function targetHost(target: string): string {
  if (target.startsWith("rsync://") || /^[^/]*:\/\//.test(target)) return "";
  if (target.startsWith("/") || !target.includes(":")) return "";
  return target.slice(0, target.indexOf(":"));
}

function targetPath(target: string): string {
  if (target.startsWith("rsync://")) return "";
  const host = targetHost(target);
  return host ? target.slice(target.indexOf(":") + 1) : target;
}

async function targetFsType(cfg: Config, host: string, path: string): Promise<string> {
  const result = await run(cfg, "stat", ["-f", "-c", "%T", "--", path], host);
  return result.code === 0 ? result.stdout.trim() : "unknown";
}

async function pathExists(cfg: Config, host: string, path: string): Promise<boolean> {
  // No `--`: test is not a getopt tool, the separator would be an operand.
  return (await run(cfg, "test", ["-e", path], host)).code === 0;
}

// btrfs subvolume delete, tolerating unprivileged filesystems: plain, then
// passwordless sudo, else a warning (prune failures never abort the run).
async function runSubvolumeDelete(cfg: Config, host: string, path: string): Promise<boolean> {
  if ((await run(cfg, "btrfs", ["subvolume", "delete", path], host)).code === 0) return true;
  if ((await run(cfg, "sudo", ["-n", "btrfs", "subvolume", "delete", path], host)).code === 0)
    return true;
  log(
    `warning: could not delete snapshot (mount with user_subvol_rm_allowed or allow sudo): ${path}`,
  );
  return false;
}

// Snapshot-versioned mirrors need <target>/opencode to BE a subvolume.
// Bootstrap it when absent; refuse to convert an existing plain directory.
// A btrfs subvolume root always has inode 256; `btrfs subvolume show` needs
// root privileges, so stat is the unprivileged-safe check.
async function ensureMirrorSubvolume(
  cfg: Config,
  host: string,
  target: string,
  mirror: string,
): Promise<boolean> {
  if (await pathExists(cfg, host, mirror)) {
    const inode = await run(cfg, "stat", ["-c", "%i", "--", mirror], host);
    if (inode.code !== 0 || inode.stdout.trim() !== "256") {
      console.error(
        `error: btrfs target ${target}: ${mirror} exists but is not a subvolume; move it aside (or delete it), then rerun to bootstrap a versioned subvolume`,
      );
      return false;
    }
    return true;
  }
  log(`bootstrapping btrfs subvolume: ${mirror}`);
  const created =
    (await run(cfg, "btrfs", ["subvolume", "create", mirror], host)).code === 0 ||
    (await run(cfg, "sudo", ["-n", "btrfs", "subvolume", "create", mirror], host)).code === 0;
  if (!created) {
    console.error(`error: cannot create subvolume ${mirror}`);
    return false;
  }
  return true;
}

// A name <prefix>-<stamp>[-N] that does not exist under dir yet.
async function uniqueName(
  cfg: Config,
  host: string,
  dir: string,
  prefix: string,
  stampValue: string,
): Promise<string> {
  let name = `${prefix}-${stampValue}`;
  let n = 1;
  while (await pathExists(cfg, host, join(dir, name))) {
    name = `${prefix}-${stampValue}-${n}`;
    n += 1;
  }
  return name;
}

async function pruneSnapshots(
  cfg: Config,
  host: string,
  snapdir: string,
  keep: number,
): Promise<void> {
  const listing = await run(cfg, "ls", ["-1", "--", snapdir], host);
  if (listing.code !== 0) return;
  const names = listing.stdout
    .split("\n")
    .filter((n) => n.startsWith(`${SNAP_PREFIX}-`))
    .sort();
  if (names.length <= keep) return;
  const excess = names.slice(0, names.length - keep);
  let failures = 0;
  for (const name of excess) {
    if (!(await runSubvolumeDelete(cfg, host, join(snapdir, name)))) failures += 1;
  }
  if (failures > 0) log(`warning: failed to prune ${failures} snapshot(s) under ${snapdir}`);
}

async function snapshotMirror(
  cfg: Config,
  host: string,
  path: string,
  mirror: string,
  keep: number,
): Promise<void> {
  const snapdir = join(path, SNAPDIR_NAME);
  await run(cfg, "mkdir", ["-p", "--", snapdir], host);
  const name = await uniqueName(cfg, host, snapdir, SNAP_PREFIX, stamp());
  const destination = join(snapdir, name);
  const snapped =
    (await run(cfg, "btrfs", ["subvolume", "snapshot", "-r", mirror, destination], host)).code ===
      0 ||
    (
      await run(
        cfg,
        "sudo",
        ["-n", "btrfs", "subvolume", "snapshot", "-r", mirror, destination],
        host,
      )
    ).code === 0;
  if (!snapped) {
    log(`warning: snapshot failed for ${mirror} (versioning skipped this run)`);
    return;
  }
  log(`snapshot: ${destination}`);
  if (keep > 0) await pruneSnapshots(cfg, host, snapdir, keep);
}

async function sha256(path: string): Promise<string> {
  const hash = createHash("sha256");
  for await (const chunk of createReadStream(path)) hash.update(chunk as Buffer);
  return hash.digest("hex");
}

let stagingDir: string | undefined;

// Sync rm: exit handlers and signal handlers cannot await.
function cleanupStaging(): void {
  if (stagingDir) rmSync(stagingDir, { recursive: true, force: true });
  stagingDir = undefined;
}

process.on("exit", cleanupStaging);
for (const signal of ["SIGINT", "SIGTERM"] as const) {
  process.on(signal, () => {
    // 'exit' handlers do not run on signal death: clean the staging dir
    // here, then restore the default disposition and re-raise so the
    // process still reports death-by-signal.
    cleanupStaging();
    process.removeAllListeners(signal);
    process.kill(process.pid, signal);
  });
}

// --snapshot mode: consistent per-DB copies via sqlite3 .backup, verified
// with PRAGMA integrity_check, delivered with SHA256SUMS + backup.log.
async function consistentSnapshot(cfg: Config, target: string, dbs: string[]): Promise<boolean> {
  const host = targetHost(target);
  const path = targetPath(target);
  if (!path) {
    log(`warning: cannot --snapshot to URL-style target, skipping: ${target}`);
    return false;
  }
  if (!(await pathExists(cfg, host, path))) {
    log(`warning: backup target missing or unmounted, skipping: ${target}`);
    return false;
  }
  const name = await uniqueName(cfg, host, path, "consistent-snapshot", stamp());
  const destination = `${target.replace(/\/+$/, "")}/${name}`;
  const staging = await mkdtemp(join(tmpdir(), "opencode-snapshot."));
  stagingDir = staging;
  const logLines: string[] = [
    "=== consistent SQLite online-backup snapshot ===",
    `started: ${isoLocal()}`,
    `source: ${cfg.dataSrc}`,
  ];
  try {
    for (const db of dbs) {
      log(`sqlite3 .backup: ${db}`);
      const backed = await run(cfg, "sqlite3", [
        join(cfg.dataSrc, db),
        `.backup '${join(staging, db)}'`,
      ]);
      if (backed.code !== 0) {
        throw new BackupError(`sqlite3 .backup failed (${backed.code}) for ${db}`, backed.code);
      }
      const info = await stat(join(staging, db));
      logLines.push(
        "--- sqlite3 .backup ---",
        "backup rc=0",
        `-${modeString(info.mode)} 1 ${info.uid} ${info.gid} ${info.size} ${isoLocal(info.mtime)} ${join(staging, db)}`,
      );
    }
    for (const db of dbs) {
      const integrity = await run(cfg, "sqlite3", [
        `file:${join(staging, db)}?mode=ro`,
        "PRAGMA integrity_check;",
      ]);
      if (integrity.stdout.trim() !== "ok") {
        throw new BackupError(
          `integrity_check failed for snapshot of ${db}: ${integrity.stdout.trim()}`,
        );
      }
      logLines.push("--- integrity_check ---", "ok");
    }
    const sums: string[] = [];
    for (const db of dbs) {
      sums.push(`${await sha256(join(staging, db))}  ${db}`);
    }
    logLines.push("--- sha256 ---", ...sums, `finished: ${isoLocal()}`);
    await writeFile(join(staging, "backup.log"), `${logLines.join("\n")}\n`);
    await writeFile(join(staging, "SHA256SUMS"), `${sums.join("\n")}\n`);
    await runRsync(
      cfg,
      `snapshot delivery: ${staging}/ -> ${destination}/`,
      ["-a", ...sshE(cfg, host), "--", `${staging}/`, `${destination}/`],
      false,
    );
  } finally {
    await rm(staging, { recursive: true, force: true });
    stagingDir = undefined;
  }
  log(`consistent snapshot: ${destination}`);
  return true;
}

function modeString(mode: number): string {
  const perms = ["r", "w", "x"];
  let out = "";
  for (let bit = 8; bit >= 0; bit--) {
    out += (mode >> bit) & 1 ? perms[bit % 3] : "-";
  }
  return out;
}

function usage(cfg: Config): void {
  const defaults = cfg.targets.join(" ") || "<none configured>";
  console.log(`Usage: ${SCRIPT_NAME} [options] [--snapshot [db ...]]

Mirror opencode user data to every configured backup target
(space-separated BACKUP_TARGETS; currently: ${defaults}).
Targets may be local paths or user@host:/path remote specs.

Options:
  -n, --dry-run    Show what would transfer without writing anything.
                   Not supported with --snapshot.
      --config     Also mirror ~/.config/opencode/ to
                   <target>/opencode-config/ (skills, prompts,
                   opencode.json, memory-banks).
      --db-only    Mirror only root SQLite DB and auth files. Much faster
                   (seconds) for mid-session refreshes. Destination keeps
                   all other existing content.
      --snapshot   Skip the mirror; write a consistent per-DB snapshot to
                   <target>/consistent-snapshot-<stamp>/ via sqlite3 .backup
                   + integrity_check + sha256. Optional trailing args name
                   DB files (default: all root-level *.db).
  -v, --verbose    Verbose rsync output (per-file list).
  -h, --help       Show this help.

Default (no flags): mirrors ${cfg.dataSrc}/ to <target>/opencode/ of each
target with --delete and NTFS/CIFS-safe flags (both filesystems have coarse
mtime granularity). --partial-dir=.rsync-partial makes transfers resumable
across kills. Excludes *.v2ed* migration artifacts.

On btrfs targets each successful mirror is versioned as a readonly
snapshot under <target>/${SNAPDIR_NAME}/. Non-btrfs targets mirror
unversioned.

Environment:
  BACKUP_TARGETS       space-separated target list (overrides env.export)
  BACKUP_ROOT          single-target override
  BACKUP_SNAPSHOTS     0 disables btrfs snapshotting (default 1)
  BACKUP_SNAPSHOT_KEEP snapshots retained per btrfs target (default 14;
                       0 disables pruning)
  BACKUP_SSH           extra ssh args for remote targets and their btrfs
                       ops (e.g. "-p 2222 -i /key"); also passed to rsync -e
`);
}

async function main(): Promise<void> {
  // The IIFE keeps parse-args' generic inference from the inline options
  // literal (a ReturnType annotation would widen every value to the
  // string|boolean union and defeat the per-key boolean types).
  const parsed = (() => {
    try {
      return parseArgs({
        allowPositionals: true,
        options: {
          "dry-run": { type: "boolean", short: "n" },
          config: { type: "boolean" },
          "db-only": { type: "boolean" },
          snapshot: { type: "boolean" },
          verbose: { type: "boolean", short: "v" },
          help: { type: "boolean", short: "h" },
        },
      });
    } catch (error) {
      throw new BackupError(error instanceof Error ? error.message : String(error), 2);
    }
  })();
  const { values, positionals } = parsed;

  const cfg = await loadConfig();

  if (values.help) {
    usage(cfg);
    return;
  }
  const dryRun = values["dry-run"] ?? false;
  const includeConfig = values.config ?? false;
  const dbOnly = values["db-only"] ?? false;
  const snapshotMode = values.snapshot ?? false;

  if (snapshotMode && (dryRun || includeConfig || dbOnly)) {
    throw new BackupError("--snapshot does not combine with --dry-run/--config/--db-only", 2);
  }
  if (!snapshotMode && positionals.length > 0) {
    throw new BackupError(
      `unexpected argument: ${positionals[0]} (positional args are only valid after --snapshot)`,
      2,
    );
  }

  if (!(await exists(cfg.dataSrc))) {
    throw new BackupError(`required directory missing: ${cfg.dataSrc}`);
  }
  // A source checkout must never be mirrored over backup targets: a
  // checkout copied into /mnt/fu/backup/opencode-2026-5 is exactly the
  // pollution that required a manual cleanup.
  if (
    (await exists(join(cfg.dataSrc, ".git"))) ||
    ((await exists(join(cfg.dataSrc, "package.json"))) &&
      (await exists(join(cfg.dataSrc, "bun.lock"))))
  ) {
    throw new BackupError(
      `${cfg.dataSrc} looks like a source checkout (.git / package.json+bun.lock); refusing to mirror it over backup targets`,
    );
  }

  if (cfg.targets.length === 0) {
    throw new BackupError("no backup targets configured (BACKUP_TARGETS is empty)");
  }

  if (snapshotMode) {
    if ((await run(cfg, "sqlite3", ["--version"])).code !== 0) {
      throw new BackupError("--snapshot requires sqlite3");
    }
    const entries = await readdir(cfg.dataSrc);
    const allDbs = entries.filter((entry) => entry.endsWith(".db"));
    let dbs: string[];
    if (positionals.length > 0) {
      dbs = positionals;
      for (const db of dbs) {
        if (!(await exists(join(cfg.dataSrc, db)))) {
          throw new BackupError(`no such DB in ${cfg.dataSrc}: ${db}`);
        }
      }
    } else {
      dbs = [];
      for (const db of allDbs) {
        if ((await stat(join(cfg.dataSrc, db))).isFile()) dbs.push(db);
      }
      if (dbs.length === 0) throw new BackupError(`no *.db files found in ${cfg.dataSrc}`);
    }
    let failures = 0;
    for (const target of cfg.targets) {
      if (!(await consistentSnapshot(cfg, target, dbs))) failures += 1;
    }
    if (failures > 0) {
      throw new BackupError(`${failures} target(s) could not take consistent snapshots`);
    }
    log("done");
    return;
  }

  if (includeConfig && !(await exists(cfg.configSrc))) {
    throw new BackupError(`--config requested but ${cfg.configSrc} missing`);
  }

  const common = [
    "-a",
    "--delete",
    "--modify-window=2",
    "--exclude=*.v2ed*",
    "--stats",
    "--partial-dir=.rsync-partial",
    "--no-whole-file",
    "--block-size=65536",
  ];
  if (values.verbose ?? false) common.push("-v");
  if (process.stderr.isTTY) common.push("--info=progress2");
  if (dryRun) common.push("--dry-run");
  const dataArgs = [...common];
  if (dbOnly) {
    dataArgs.push(
      "--include=/auth*.json*",
      "--include=/db.sqlite*",
      "--include=/*.db*",
      "--exclude=/*",
    );
  }
  const configArgs = [...common, "--exclude=node_modules/"];

  if ((await run(cfg, "pgrep", ["-x", "opencode"])).code === 0) {
    log(
      "warning: opencode is running; the live DB may be captured mid-write. For a guaranteed-clean snapshot, quit opencode first (or use --snapshot).",
    );
  }

  const sources = [cfg.dataSrc];
  if (await exists(cfg.configSrc)) sources.push(cfg.configSrc);

  let failures = 0;
  for (const target of cfg.targets) {
    const host = targetHost(target);
    const path = targetPath(target);
    if (!path) {
      log(`warning: URL-style target cannot be snapshot-versioned: ${target}`);
    }
    if (!(await pathExists(cfg, host, path))) {
      log(`warning: backup target missing or unmounted, skipping: ${target}`);
      failures += 1;
      continue;
    }
    const targetRoot = target.replace(/\/+$/, "");
    const mirrorPath = join(path, "opencode");
    if (!host && isAbsolute(path)) {
      await guardDestination(join(targetRoot, "opencode"), sources);
      if (includeConfig) await guardDestination(join(targetRoot, "opencode-config"), sources);
    }
    const fsType = await targetFsType(cfg, host, path);
    let versioned = false;
    if (fsType === "btrfs" && cfg.snapshotsEnabled && !dryRun && path) {
      if (!(await ensureMirrorSubvolume(cfg, host, target, mirrorPath))) {
        failures += 1;
        continue;
      }
      versioned = true;
    } else if (fsType !== "btrfs" && cfg.snapshotsEnabled && !dryRun) {
      log(`note: ${target} is ${fsType}, not btrfs; mirroring without snapshot versioning`);
    }
    await runRsync(
      cfg,
      `data mirror: ${cfg.dataSrc}/ -> ${targetRoot}/opencode/`,
      [...dataArgs, ...sshE(cfg, host), "--", `${cfg.dataSrc}/`, `${targetRoot}/opencode/`],
      dryRun,
    );
    if (includeConfig) {
      await runRsync(
        cfg,
        `config mirror: ${cfg.configSrc}/ -> ${targetRoot}/opencode-config/`,
        [
          ...configArgs,
          ...sshE(cfg, host),
          "--",
          `${cfg.configSrc}/`,
          `${targetRoot}/opencode-config/`,
        ],
        dryRun,
      );
    }
    if (versioned) await snapshotMirror(cfg, host, path, mirrorPath, cfg.snapshotKeep);
  }

  if (failures > 0) {
    throw new BackupError(
      `${failures} of ${cfg.targets.length} backup targets were missing or unmounted`,
    );
  }
  log(dryRun ? "dry run done" : "done");
}

main().catch((error: unknown) => {
  if (error instanceof BackupError) {
    console.error(`error: ${error.message}`);
    process.exitCode = error.code;
  } else {
    console.error(error);
    process.exitCode = 1;
  }
});
