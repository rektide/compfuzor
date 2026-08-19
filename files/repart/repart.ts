#!/usr/bin/env node

/**
 * repart — build disks of dated btrfs subvolumes with systemd-repart, then
 * manage the subvolumes on them. One flat verb per command, no nesting.
 *
 * Commands:
 *   render         copy a tokenized tree and stamp @TOKEN@s into it
 *   format         dry-run a blank-disk layout; persist the draft under var/
 *   pivot          dry-run a live-root migration onto a target; persist draft
 *   write          EXECUTE a draft. The only command that modifies a disk
 *   loop-mount     attach an image file's loop + root partition, privately
 *   loop-unmount   tear down everything `repart loop-mount` created
 *   subvol-path    print where a dated subvolume lives (base/flavor scheme)
 *   btrfs-subvols  list the dated subvolumes on a mounted filesystem
 *   btrfs-default  choose which subvolume boots (btrfs default subvolume)
 *
 * Subvolume scheme: /root/<flavor>/<arch>/<DATE> and /home/<flavor>/<DATE>,
 * defaults flavor=superbfowle, arch=mapped host, DATE=today. Controlled by
 * --base (root|home), --flavor, --arch and their REPART_* variables.
 *
 * Conventions:
 *   - stdout is data only (a path, or TSV); all narration goes to stderr
 *   - durable state lives under DIR/var (drafts, rendered trees, mounts);
 *     nothing is ever put in /tmp
 *   - every flag has a REPART_* env fallback, shown beside it in --help;
 *     flags always win
 *   - destructive safety: `format`/`pivot` only dry-run; `write` re-verifies
 *     the draft digest and the target fingerprint, requires --confirm to
 *     name the same target, and refuses mounted targets
 */
const { createHash } = require("node:crypto")
const { spawn } = require("node:child_process")
const {
  cp,
  lstat,
  mkdir,
  mkdtemp,
  readFile,
  readlink,
  readdir,
  realpath,
  rename,
  rm,
  rmdir,
  writeFile,
} = require("node:fs/promises")
const { arch: hostArch } = require("node:os")
const { basename, dirname, isAbsolute, join, relative, sep } = require("node:path")
const { parseArgs } = require("node:util")

const HELP = `Usage: repart <command> [options]

Build disks of dated btrfs subvolumes with systemd-repart, then manage them.

Commands:
  render         Copy a tokenized tree and stamp @TOKEN@s into it
  format         Dry-run a blank-disk layout; persist the draft
  pivot          Dry-run a live-root migration; persist the draft
  write          Execute a draft (the ONLY command that modifies a disk)
  loop-mount     Attach an image file; print its private mountpoint
  loop-unmount   Tear down a mount made by "repart loop-mount"
  subvol-path    Print where a dated subvolume lives
  btrfs-subvols  List the dated subvolumes on a mounted filesystem
  btrfs-default  Choose which subvolume boots

Disk changes are always two steps: "format"/"pivot" dry-run and persist a
draft that touches nothing; "write" later executes it after re-verification.
Every flag pairs with a REPART_* environment variable, shown beside it in
each command's --help; flags always win. Run "repart <command> --help" for
options, env vars, and examples.`

const RENDER_HELP = `Usage: repart render --from DIR [options]

Copy a source tree, overlay later trees on top, and replace @UPPERCASE@
tokens. The rendered tree is durable state under DIR/var; its path is
printed to stdout. Remove it explicitly when it is no longer useful.

Options (flag wins over its REPART_* variable):
  --from DIR          Source tree to render (required) [REPART_FROM]
  --overlay DIR       Overlay tree; repeatable, later files win
                      [REPART_OVERLAY: comma-separated]
  --preserve PATH     Do not resolve tokens beneath this relative path
                      [REPART_PRESERVE: comma-separated]
  --date YYYYMMDD     DATE token (default: today) [REPART_DATE]
  --arch ARCH         ARCH token (default: mapped host architecture) [REPART_ARCH]
  --swap SIZE         SWAP token (default: 16G) [REPART_SWAP]
  --set NAME=VALUE    Define or override a token; repeatable
                      [REPART_SET: comma-separated NAME=VALUE]
  --name NAME         State directory name (default: unique render-* name)
                      [REPART_NAME]
  -h, --help          Show this help

Built-in tokens: DATE, ARCH, SWAP, ROOT_PREFIX, HOME_PREFIX. The prefix
tokens have no flag: they are built from the subvolume scheme — /root/<flavor>
and /home/<flavor>, flavor from REPART_FLAVOR (default superbfowle).

Example:
  repart render --from etc --overlay local --set CHANNEL=stable`

const FORMAT_HELP = `Usage: repart format TARGET [options]

Preview wiping TARGET and building the canonical layout on it: GPT table,
boot area, fixed swap, and a btrfs root pre-seeded with dated root/home
subvolume skeletons. Runs systemd-repart with --dry-run=yes, so nothing is
modified. The draft persists under DIR/var and its path is printed to
stdout; execute it later with "repart write".

Options (flag wins over its REPART_* variable):
  --from DIR          Replace the canonical universal definition source
                      [REPART_FROM]
  --overlay DIR       Add a definition overlay; repeatable
                      [REPART_OVERLAY: comma-separated]
  --date YYYYMMDD     Subvolume date stamp [REPART_DATE]
  --arch ARCH         Architecture segment [REPART_ARCH]
  --swap SIZE         Swap size (default: 16G) [REPART_SWAP]
  --set NAME=VALUE    Extra profile token; repeatable
                      [REPART_SET: comma-separated NAME=VALUE]
  --name NAME         Draft directory name
                      (default: format-<target>-<time>-<id>) [REPART_NAME]
  -h, --help          Show this help

TARGET must always be given explicitly. Raw systemd-repart arguments are
intentionally forbidden.`

const PIVOT_HELP = `Usage: repart pivot TARGET --source MOUNT [options]

Preview moving the RUNNING btrfs root at MOUNT onto TARGET using
systemd-repart BlockDeviceReplace (BDR): fresh layout on TARGET, contents
copied from the source, no reboot required. Dry-run only; the draft persists
under DIR/var for later "repart write".

Requires systemd-repart >=261 and a single-device btrfs source.

Options (flag wins over its REPART_* variable):
  --source MOUNT      The mounted btrfs root to move (required) [REPART_SOURCE]
  --from DIR          Replace the canonical universal definition source
                      [REPART_FROM]
  --overlay DIR       Add a definition overlay; repeatable
                      [REPART_OVERLAY: comma-separated]
  --date YYYYMMDD     Subvolume date stamp [REPART_DATE]
  --arch ARCH         Architecture segment [REPART_ARCH]
  --swap SIZE         Swap size (default: 16G) [REPART_SWAP]
  --set NAME=VALUE    Extra profile token; repeatable
                      [REPART_SET: comma-separated NAME=VALUE]
  --name NAME         Draft directory name
                      (default: pivot-<target>-<time>-<id>) [REPART_NAME]
  -h, --help          Show this help

TARGET must always be given explicitly. Raw systemd-repart arguments are
intentionally forbidden.`

const WRITE_HELP = `Usage: repart write DRAFT --confirm TARGET

Execute a draft made by "repart format" or "repart pivot". This is the only
command that modifies disk contents. Before anything runs it re-verifies:
the draft digest (nothing edited since preview), the target fingerprint
(same device, same partition table), the --confirm target matching the
drafted target, and that the target and its partitions are not mounted.

Options (flag wins over its REPART_* variable):
  --confirm TARGET    Must equal the drafted target [REPART_CONFIRM]
  -h, --help          Show this help

DRAFT and its target stay positional and explicit. The draft remains under
DIR/var afterward for audit; remove it when done.`

const LOOP_MOUNT_HELP = `Usage: repart loop-mount IMAGE [options]

Attach IMAGE (a regular file) to a new loop device, find its root partition
(GPT root type, label "root" fallback, or --partition N), and mount it at a
private mountpoint under DIR/var. Prints the mountpoint to stdout; the
loop/device pairing is recorded for "repart loop-unmount". Works on image
files only; for real disks mount the partition yourself and use
btrfs-subvols.

Options (flag wins over its REPART_* variable):
  --partition NUMBER  Mount this partition instead of discovering root
                      [REPART_PARTITION]
  --subvol PATH       Mount this btrfs subvolume (default: the filesystem's
                      default subvolume) [REPART_SUBVOL]
  --read-only         Mount read-only [REPART_READ_ONLY: truthy]
  -h, --help          Show this help

IMAGE stays positional and explicit.`

const LOOP_UNMOUNT_HELP = `Usage: repart loop-unmount MOUNTPOINT

Tear down a mount made by "repart loop-mount": unmount it (recursively),
remove the private mountpoint directory, and detach the loop device.
MOUNTPOINT is the path that "repart loop-mount" printed. No output on
success.`

const SUBVOL_PATH_HELP = `Usage: repart subvol-path [YYYYMMDD] [options]

Print where a dated subvolume lives in the canonical scheme — a pure string
computation, nothing is touched. Defaults to today's root-base subvolume.

  /root/<flavor>/<arch>/<YYYYMMDD>   (--base root, the default)
  /home/<flavor>/<YYYYMMDD>          (--base home)

Options (flag wins over its REPART_* variable):
  --base BASE         root or home (default: root) [REPART_BASE]
  --flavor NAME       Scheme flavor (default: superbfowle) [REPART_FLAVOR]
  --arch ARCH         Architecture segment (default: mapped host arch)
                      [REPART_ARCH]
  -h, --help          Show this help

REPART_DATE supplies the default date. Example:
  repart subvol-path --base home 20260824`

const BTRFS_SUBVOLS_HELP = `Usage: repart btrfs-subvols MOUNT [options]

List the dated subvolumes on the btrfs mounted at MOUNT, as stable TSV on
stdout: kind, date, path, is-default. Only subvolumes matching the scheme
(root/<flavor>/<arch>/YYYYMMDD or home/<flavor>/YYYYMMDD) are shown;
everything else on the filesystem is invisible to this toolkit by design.
Which subvolume is the default (boots) is marked true.

Options (flag wins over its REPART_* variable):
  --base BASE         root, home, or all (default: all) [REPART_BASE]
  --flavor NAME       Scheme flavor (default: superbfowle) [REPART_FLAVOR]
  --arch ARCH         Architecture segment (default: mapped host arch)
                      [REPART_ARCH]
  -h, --help          Show this help`

const BTRFS_DEFAULT_HELP = `Usage: repart btrfs-default MOUNT <YYYYMMDD|PATH|latest>

Set the btrfs default subvolume — which subvolume boots — on the filesystem
mounted at MOUNT. The selector must resolve to an exact known root-base
subvolume: a date, an absolute subvolume path, or "latest" (highest date).
Home subvolumes are never valid defaults. No output; narration on stderr.

The candidate set always uses --base root. Flavor and arch come from
--flavor/--arch, or REPART_FLAVOR/REPART_ARCH (defaults superbfowle and the
mapped host architecture).`

/**
 * Fatal user-facing error: printed as "repart: error: ..." with exit code 2.
 * Distinguished from programming/IO errors, which crash with a stack (exit 1).
 */
class CliError extends Error {}

const script = __filename
const scriptDir = dirname(script)
// Installed as DIR/bin/repart; source-tree execution keeps defs beside repart.ts.
const root = basename(scriptDir) === "bin" ? dirname(scriptDir) : scriptDir
const stateRoot = join(root, "var")
const mountsRoot = join(stateRoot, "mounts")

/** Abort with a user-facing error message and exit code 2. */
function fail(message) {
  throw new CliError(message)
}

/** Narrate to stderr; stdout is reserved for data. */
function note(command, message) {
  console.error(`repart ${command}: ${message}`)
}

/**
 * Map a machine architecture to the scheme's arch segment.
 * x64/x86_64 -> amd64, aarch64 -> arm64, anything else passes through.
 */
function mappedArch(value) {
  return value === "x64" || value === "x86_64" ? "amd64" : value === "aarch64" ? "arm64" : value
}

/** The arch segment for the subvolume scheme: REPART_ARCH or mapped host arch. */
function archSegment() {
  return mappedArch(process.env.REPART_ARCH || hostArch())
}

/** The scheme flavor: REPART_FLAVOR or "superbfowle". Validated on use. */
function flavorSegment() {
  const value = process.env.REPART_FLAVOR || "superbfowle"
  if (!/^[A-Za-z0-9][A-Za-z0-9._-]*$/.test(value)) {
    fail(`invalid flavor '${value}' (use letters, digits, dot, dash, or underscore)`)
  }
  return value
}

/** Validate a --base value: the two scheme bases are root and home. */
function baseSegment(value) {
  if (value !== "root" && value !== "home") fail(`invalid --base '${value}' (want root or home)`)
  return value
}

/** Today's date as YYYYMMDD in local time (matches `date +%Y%m%d`). */
function today() {
  const date = new Date()
  return `${date.getFullYear()}${String(date.getMonth() + 1).padStart(2, "0")}${String(date.getDate()).padStart(2, "0")}`
}

/** Current UTC instant as a filename-safe stamp, e.g. 20260819T041250123Z. */
function timestamp() {
  return new Date().toISOString().replaceAll(/[-:.]/g, "")
}

/** Validate a YYYYMMDD date or fail. */
function validDate(value) {
  if (!/^\d{8}$/.test(value)) fail(`bad date '${value}' (want YYYYMMDD)`)
  return value
}

/**
 * Validate a state directory name. Must be a single safe path component so a
 * hostile --name can never escape DIR/var.
 */
function validStateName(value) {
  if (!/^[A-Za-z0-9][A-Za-z0-9._-]*$/.test(value) || value === "." || value === "..") {
    fail(`invalid state name '${value}' (use letters, digits, dot, dash, or underscore)`)
  }
  return value
}

/**
 * Create a durable state directory under DIR/var.
 * With a name: DIR/var/<name>, failing if it already exists (a draft or
 * render is a one-time artifact; never silently reuse a name).
 * Without: DIR/var/<prefix><random> via mkdtemp.
 */
async function createState(name, fallbackPrefix) {
  await mkdir(stateRoot, { recursive: true })
  if (name) {
    const path = join(stateRoot, validStateName(name))
    try {
      await mkdir(path)
    } catch (error) {
      if (error.code === "EEXIST") fail(`state already exists: ${path}`)
      throw error
    }
    return path
  }
  return mkdtemp(join(stateRoot, fallbackPrefix))
}

/** parseArgs wrapper: usage errors become clean CLI errors. */
function parsed(args, options) {
  try {
    return parseArgs({ args, allowPositionals: true, strict: true, options })
  } catch (error) {
    fail(error.message)
  }
}

/** The REPART_* env var name for a dashed option: "read-only" -> REPART_READ_ONLY. */
function envName(option) {
  return `REPART_${option.replaceAll("-", "_").toUpperCase()}`
}

/**
 * Resolve one setting: flag > REPART_* variable > built-in default.
 * List options split their env value on commas; empty env counts as unset.
 */
function setting(values, option, { list = false } = {}) {
  if (values[option] !== undefined) return values[option]
  const raw = process.env[envName(option)]
  if (raw === undefined || raw === "") return list ? [] : undefined
  return list ? raw.split(",").map((item) => item.trim()).filter(Boolean) : raw
}

/** Boolean setting: flag if given, else truthy env (1/true/yes/y/on). */
function settingBool(values, option) {
  if (values[option] !== undefined) return values[option]
  return /^(1|true|yes|y|on)$/i.test(process.env[envName(option)] || "")
}

/**
 * Spawn a command and await its exit.
 * Resolves {status, stdout, stderr}. Rejects with CliError on nonzero status
 * unless allowFailure (used for probe commands whose status is meaningful).
 */
async function run(command, args, { allowFailure = false, env, stdio = "pipe" } = {}) {
  return new Promise((resolvePromise, rejectPromise) => {
    const child = spawn(command, args, { env, stdio })
    let stdout = ""
    let stderr = ""
    if (child.stdout) child.stdout.on("data", (chunk) => (stdout += chunk))
    if (child.stderr) child.stderr.on("data", (chunk) => (stderr += chunk))
    child.on("error", (error) => {
      if (allowFailure && error.code === "ENOENT") resolvePromise({ status: 127, stdout: "", stderr: "" })
      else rejectPromise(error)
    })
    child.on("close", (status) => {
      if (status === 0 || allowFailure) resolvePromise({ status, stdout, stderr })
      else rejectPromise(new CliError(`${command} exited with status ${status}${stderr ? `: ${stderr.trim()}` : ""}`))
    })
  })
}

/** Run a command and return its trimmed stdout. */
async function commandOutput(command, args, allowFailure = false) {
  const result = await run(command, args, { allowFailure })
  return result.stdout.trim()
}

/** Canonicalize an existing path or fail with a description of what's missing. */
async function existing(path, description = "path") {
  try {
    return await realpath(path)
  } catch {
    fail(`${description} does not exist: ${path}`)
  }
}

/** Canonicalize an existing directory or fail. */
async function directory(path, description) {
  const canonical = await existing(path, description)
  if (!(await lstat(canonical)).isDirectory()) fail(`${description} is not a directory: ${path}`)
  return canonical
}

/** Shared option table for render and the definition-rendering previews. */
function renderOptions() {
  return {
    from: { type: "string" },
    overlay: { type: "string", multiple: true },
    preserve: { type: "string", multiple: true },
    date: { type: "string" },
    arch: { type: "string" },
    swap: { type: "string" },
    set: { type: "string", multiple: true },
    name: { type: "string" },
    help: { type: "boolean", short: "h" },
  }
}

/** All regular files beneath path, depth-first. Symlinks are skipped. */
async function filesBelow(path) {
  const files = []
  async function visit(current) {
    for (const entry of await readdir(current, { withFileTypes: true })) {
      const child = join(current, entry.name)
      if (entry.isDirectory()) await visit(child)
      else if (entry.isFile()) files.push(child)
    }
  }
  await visit(path)
  return files
}

/** Is file (inside tree) at or beneath one of the preserved relative paths? */
function isPreserved(file, tree, preserves) {
  const local = relative(tree, file)
  return preserves.some((path) => local === path || local.startsWith(`${path}${sep}`))
}

/**
 * `repart render`: copy source, overlay later trees, stamp @TOKEN@s.
 * Returns the durable rendered tree path, or undefined after printing help.
 * When internal=true the command is run by format/pivot to render definition
 * trees; the completion note is suppressed and state gets a draft-ish prefix.
 * Fails (deleting the partial tree) if any uppercase token survives.
 */
async function renderCommand(args, { internal = false } = {}) {
  const { values, positionals } = parsed(args, renderOptions())
  if (values.help) {
    console.log(RENDER_HELP)
    return undefined
  }
  if (positionals.length) fail(`unexpected argument: ${positionals[0]}`)
  const fromSetting = setting(values, "from")
  if (!fromSetting) fail("--from must name a directory (or set REPART_FROM)")
  const from = await directory(fromSetting, "source tree")
  const overlays = []
  for (const overlay of setting(values, "overlay", { list: true })) overlays.push(await directory(overlay, "overlay"))
  const preserves = setting(values, "preserve", { list: true }).map((path) => {
    const normalized = path.replace(/^\.\//, "")
    if (!normalized || isAbsolute(normalized) || normalized.split(/[\\/]/).includes("..")) {
      fail(`--preserve must stay beneath the rendered tree: ${path}`)
    }
    return normalized
  })
  const flavor = flavorSegment()
  const tokens = new Map([
    ["DATE", validDate(setting(values, "date") || today())],
    ["ARCH", mappedArch(setting(values, "arch") || hostArch())],
    ["SWAP", setting(values, "swap") || "16G"],
    ["ROOT_PREFIX", `/root/${flavor}`],
    ["HOME_PREFIX", `/home/${flavor}`],
  ])
  for (const pair of setting(values, "set", { list: true })) {
    const separator = pair.indexOf("=")
    const name = pair.slice(0, separator)
    if (separator < 1) fail("--set needs NAME=VALUE")
    if (!/^[A-Z][A-Z0-9_]*$/.test(name)) fail(`invalid token name: ${name}`)
    tokens.set(name, pair.slice(separator + 1))
  }

  const tree = await createState(setting(values, "name"), internal ? "definitions-" : "render-")
  try {
    // verbatimSymlinks keeps relative links relative (cp -a semantics) so the
    // rendered tree stays self-contained when its source is deleted.
    const copyOptions = { recursive: true, force: true, verbatimSymlinks: true }
    await cp(from, tree, copyOptions)
    for (const overlay of overlays) await cp(overlay, tree, copyOptions)
    const unresolved = []
    for (const file of await filesBelow(tree)) {
      if (isPreserved(file, tree, preserves)) continue
      const buffer = await readFile(file)
      if (buffer.includes(0)) continue
      let content = buffer.toString("utf8")
      if (!/@[A-Z][A-Z0-9_]*@/.test(content)) continue
      content = content.replaceAll(/@([A-Z][A-Z0-9_]*)@/g, (token, name) => tokens.has(name) ? tokens.get(name) : token)
      await writeFile(file, content)
      if (/@[A-Z][A-Z0-9_]*@/.test(content)) unresolved.push(file)
    }
    if (unresolved.length) {
      for (const file of unresolved) console.error(file)
      fail("unresolved uppercase tokens")
    }
  } catch (error) {
    await rm(tree, { recursive: true, force: true })
    throw error
  }
  if (!internal) note("render", `rendered tree at ${tree}; remove explicitly when no longer needed`)
  return tree
}

/**
 * Fingerprint a target so `write` can prove it is the same disk.
 * Combines lstat identity (dev/inode/rdev/size — catches device-node swaps),
 * lsblk block identity (catches same-size different-disk), and a sha256 of
 * the sfdisk partition dump (catches repartitioning between preview and
 * write). Fails closed: block identity is REQUIRED for real block devices;
 * a missing sfdisk binary is fatal; image files may legitimately have no
 * lsblk entry.
 */
async function fingerprint(target) {
  const info = await lstat(target, { bigint: true })
  const identity = `mode=${info.mode}|dev=${info.dev}|inode=${info.ino}|rdev=${info.rdev}|size=${info.size}`
  const blockResult = await run("lsblk", ["-dnro", "MAJ:MIN,SIZE,SERIAL,WWN,MODEL", target], { allowFailure: true })
  if (info.isBlockDevice() && blockResult.status !== 0) fail(`lsblk could not fingerprint block target ${target}`)
  const block = blockResult.stdout.trim()
  const tableResult = await run("sfdisk", ["--dump", target], { allowFailure: true })
  if (tableResult.status === 127) fail("sfdisk is required to fingerprint disk partition tables")
  const table = tableResult.stdout.trim()
  const tableHash = createHash("sha256").update(table).digest("hex")
  return `${identity}|block=${block}|table=${tableHash}`
}

/**
 * Digest a draft directory: sha256 over relative paths AND bytes of every
 * reviewed input (draft metadata, arguments, all definitions). Hashing names
 * means adding/removing/renaming a definition file also invalidates the
 * draft. Symlinks inside definitions are rejected outright — repart may
 * follow them post-preview, which would make an external file part of the
 * reviewed set invisibly.
 */
async function draftDigest(draft) {
  const definitions = join(draft, "definitions")
  const files = [join(draft, "draft"), join(draft, "arguments"), ...(await filesBelow(definitions))]
  async function rejectSymlinks(path) {
    for (const entry of await readdir(path, { withFileTypes: true })) {
      const child = join(path, entry.name)
      if (entry.isSymbolicLink()) fail(`draft definitions may not contain symlinks: ${relative(definitions, child)} -> ${await readlink(child)}`)
      if (entry.isDirectory()) await rejectSymlinks(child)
    }
  }
  await rejectSymlinks(definitions)
  const hash = createHash("sha256")
  for (const file of files.sort()) hash.update(relative(draft, file)).update("\0").update(await readFile(file)).update("\0")
  return hash.digest("hex")
}

/**
 * Preconditions for pivot (live migration): the source must be btrfs,
 * single-device (BDR cannot replicate RAID), and systemd-repart must be
 * >=261 (first release with BlockDeviceReplace).
 */
async function checkPivotSource(source) {
  const fsType = await commandOutput("stat", ["-f", "-c", "%T", source])
  if (fsType !== "btrfs") fail(`pivot source is not btrfs: ${source}`)
  const listing = await commandOutput("btrfs", ["filesystem", "show", source])
  const count = listing.split("\n").filter((line) => /\bdevid\b/.test(line)).length
  if (count !== 1) fail(`pivot source must be single-device btrfs (found ${count})`)
  const versionLine = (await commandOutput("systemd-repart", ["--version"])).split("\n")[0]
  const version = Number(versionLine.trim().split(/\s+/)[1])
  if (!Number.isInteger(version)) fail("cannot parse systemd-repart version")
  if (version < 261) fail(`pivot requires systemd-repart >=261 (found ${version})`)
}

/**
 * Locate a canonical definition set: installed DIR/etc/defs/<name> first,
 * then the source tree's defs/ beside this script (dev/test runs).
 */
async function definitionDirectory(name) {
  for (const candidate of [join(root, "etc", "defs", name), join(scriptDir, "defs", name)]) {
    try {
      if ((await lstat(candidate)).isDirectory()) return candidate
    } catch {}
  }
  fail(`canonical ${name} definitions are not installed`)
}

/** Default draft name: <operation>-<target basename>-<timestamp>-<random>. */
function defaultDraftName(operation, target) {
  const targetName = basename(target).replaceAll(/[^A-Za-z0-9._-]/g, "-") || "target"
  return `${operation}-${targetName}-${timestamp()}`
}

/**
 * `repart format` / `repart pivot`: preview a destructive repart run.
 * Renders the canonical definitions through the same renderer `render` uses,
 * snapshots the target fingerprint, dry-runs systemd-repart, and persists the
 * draft {definitions/, draft, arguments, digest} under DIR/var. Prints the
 * draft path. Nothing on TARGET is modified (--dry-run=yes).
 */
async function previewCommand(operation, args, helpText) {
  if (!args.length || args[0] === "--help" || args[0] === "-h") {
    console.log(helpText)
    return
  }
  const options = renderOptions()
  delete options.preserve
  options.source = { type: "string" }
  const { values, positionals } = parsed(args, options)
  if (values.help) {
    console.log(helpText)
    return
  }
  if (positionals.length !== 1) fail(`${operation} needs exactly one TARGET`)
  const target = await existing(positionals[0], "target")
  let source = ""
  const sourceSetting = setting(values, "source")
  if (sourceSetting) {
    if (operation !== "pivot") fail("--source is only valid for pivot")
    source = await directory(sourceSetting, "pivot source")
  }
  if (operation === "pivot") {
    if (!source) fail("pivot requires --source MOUNT")
    await checkPivotSource(source)
  }

  const fromSetting = setting(values, "from")
  const from = fromSetting ? await directory(fromSetting, "definition source") : await definitionDirectory("universal.d")
  const flavor = await definitionDirectory(operation === "pivot" ? "bdr.d" : "format.d")
  const renderArgs = ["--from", from]
  for (const overlay of setting(values, "overlay", { list: true })) renderArgs.push("--overlay", overlay)
  // The operation's flavor definitions always render LAST so they win.
  renderArgs.push("--overlay", flavor)
  for (const key of ["date", "arch", "swap"]) if (setting(values, key)) renderArgs.push(`--${key}`, setting(values, key))
  for (const value of setting(values, "set", { list: true })) renderArgs.push("--set", value)
  if (source) renderArgs.push("--set", `SOURCE=${source}`)

  const draft = await createState(setting(values, "name"), `${defaultDraftName(operation, target)}-`)
  let definitions
  try {
    definitions = await renderCommand(renderArgs, { internal: true })
    await rename(definitions, join(draft, "definitions"))
    definitions = undefined
    const draftText = `operation=${operation}\ntarget=${target}\nsource=${source}\nfingerprint=${await fingerprint(target)}\n`
    await writeFile(join(draft, "draft"), draftText)
    const repartArgs = operation === "format"
      ? ["--offline=yes", "--empty=force", "--dry-run=yes"]
      : ["--empty=force", "--dry-run=yes"]
    await writeFile(join(draft, "arguments"), `${repartArgs.join("\n")}\n`)
    await writeFile(join(draft, "digest"), `${await draftDigest(draft)}\n`)
    note(operation, `dry-run preview for ${target}`)
    await run("systemd-repart", [`--definitions=${join(draft, "definitions")}`, ...repartArgs, target], {
      // stdout stays the draft-path data channel; repart noise goes to stderr.
      stdio: ["inherit", process.stderr, process.stderr],
    })
  } catch (error) {
    if (definitions) await rm(definitions, { recursive: true, force: true })
    await rm(draft, { recursive: true, force: true })
    throw error
  }
  note(operation, `draft persisted at ${draft}`)
  console.log(draft)
}

/**
 * Refuse a write whose target (or any partition of it) is mounted.
 * Fails closed: losetup/lsblk/findmnt errors are fatal, not "probably fine" —
 * the next step uses --empty=force, so uncertainty must mean stop.
 * findmnt status 1 (its documented "not mounted") is the only passing answer.
 */
async function rejectMounted(target) {
  const devices = [target]
  if ((await lstat(target)).isFile()) {
    const loops = await run("losetup", ["-j", target, "-O", "NAME", "-n"], { allowFailure: true })
    if (loops.status !== 0) fail(`losetup could not inspect image target ${target}`)
    devices.push(...loops.stdout.trim().split("\n").filter(Boolean))
  }
  for (const rootDevice of devices) {
    let discovered = [rootDevice]
    if (!(await lstat(rootDevice)).isFile()) {
      const listed = await run("lsblk", ["-nrpo", "NAME", rootDevice], { allowFailure: true })
      if (listed.status !== 0) fail(`lsblk could not inspect target partitions for ${rootDevice}`)
      discovered = listed.stdout.trim().split("\n").filter(Boolean)
      if (!discovered.length) fail(`lsblk returned no target devices for ${rootDevice}`)
    }
    for (const device of discovered) {
      const result = await run("findmnt", ["-rn", "-S", device], { allowFailure: true })
      if (result.status === 0) fail(`target or target partition is mounted: ${device}`)
      if (result.status !== 1) fail(`findmnt could not determine mount state for ${device} (status ${result.status})`)
    }
  }
}

/**
 * `repart write`: execute a draft. Every safety gate is re-checked at write
 * time, not trusted from preview time:
 *   1. digest matches       — nothing in the draft changed since preview
 *   2. arguments allowlist  — only the exact known repart flag sets pass
 *   3. --confirm == target  — the operator named this disk on this command
 *   4. fingerprint matches  — same device, same partition table
 *   5. not mounted          — no partitions in use mid-destroy
 *   6. pivot preconditions  — source still single-device btrfs
 * Then repart runs with ONLY --dry-run=yes flipped to no. The draft is kept
 * afterward (audit trail) — remove it manually when satisfied.
 */
async function writeCommand(args) {
  const { values, positionals } = parsed(args, {
    confirm: { type: "string" },
    help: { type: "boolean", short: "h" },
  })
  if (values.help) {
    console.log(WRITE_HELP)
    return
  }
  if (positionals.length !== 1 || !setting(values, "confirm")) fail("usage: repart write DRAFT --confirm TARGET")
  const draft = await directory(positionals[0], "draft")
  const confirmed = await existing(setting(values, "confirm"), "confirmation target")
  for (const path of ["draft", "arguments", "digest"]) await existing(join(draft, path), `draft ${path}`)
  await directory(join(draft, "definitions"), "draft definitions")
  if (await draftDigest(draft) !== (await readFile(join(draft, "digest"), "utf8")).trim()) {
    fail("draft contents changed after preview")
  }
  const metadata = new Map(
    (await readFile(join(draft, "draft"), "utf8")).trimEnd().split("\n").map((line) => {
      const index = line.indexOf("=")
      return [line.slice(0, index), line.slice(index + 1)]
    }),
  )
  const operation = metadata.get("operation")
  const target = metadata.get("target")
  const source = metadata.get("source")
  const expected = operation === "format"
    ? ["--offline=yes", "--empty=force", "--dry-run=yes"]
    : operation === "pivot" ? ["--empty=force", "--dry-run=yes"] : undefined
  if (!expected) fail(`invalid drafted operation: ${operation}`)
  const repartArgs = (await readFile(join(draft, "arguments"), "utf8")).trimEnd().split("\n")
  if (JSON.stringify(repartArgs) !== JSON.stringify(expected)) fail("draft contains invalid repart arguments")
  if (confirmed !== target) fail(`confirmation target differs from drafted target (${confirmed} != ${target})`)
  if (await fingerprint(target) !== metadata.get("fingerprint")) fail("target identity/fingerprint changed since preview")
  await rejectMounted(target)
  if (operation === "pivot") await checkPivotSource(source)
  const writeArgs = repartArgs.map((arg) => arg === "--dry-run=yes" ? "--dry-run=no" : arg)
  note("write", `writing ${operation} to ${target}; draft retained at ${draft}`)
  await run("systemd-repart", [`--definitions=${join(draft, "definitions")}`, ...writeArgs, target], {
    stdio: ["inherit", process.stderr, process.stderr],
  })
}

/**
 * Find the root partition device on a whole-disk device node.
 * Order: GPT root type GUIDs (x86-64 and aarch64 root), then the last
 * partition labeled "root" (only accepted if it IS the last partition, since
 * the canonical layout keeps root last/growable), or an explicit number.
 */
async function findRootPartition(loop, partition) {
  if (partition !== undefined) {
    const rows = (await commandOutput("lsblk", ["-nrpo", "NAME,TYPE", loop])).split("\n")
    const suffix = new RegExp(`p?${partition}$`)
    return rows.map((line) => line.trim().split(/\s+/)).find(([name, type]) => type === "part" && suffix.test(name))?.[0]
  }
  const rows = (await commandOutput("lsblk", ["-nrpo", "NAME,PARTTYPE,TYPE", loop])).split("\n")
  const device = rows.map((line) => line.trim().split(/\s+/)).find(([, type, kind]) =>
    kind === "part" && /^(4f68bce3-e8cd-4db1-96e7-fbcaf984b709|b921b045-1df0-41c3-af44-4c6f280d3fae)$/i.test(type))?.[0]
  if (device) return device
  const labeled = (await commandOutput("lsblk", ["-nrpo", "NAME,LABEL,TYPE", loop])).split("\n")
    .map((line) => line.trim().split(/\s+/)).filter(([, label, kind]) => label === "root" && kind === "part")
  const candidate = labeled.at(-1)?.[0]
  if (!candidate) fail("no GPT root partition found; canonical-last fallback requires a partition labeled root")
  const partitions = (await commandOutput("lsblk", ["-nrpo", "NAME,TYPE", loop])).split("\n")
    .map((line) => line.trim().split(/\s+/)).filter(([, kind]) => kind === "part")
  if (candidate !== partitions.at(-1)?.[0]) fail("root-labeled partition is not canonical-last")
  return candidate
}

/**
 * Persist one mount's teardown record. The JSON lives in DIR/var/mounts keyed
 * by mountpoint basename; `loop-unmount` reads it back to detach the loop.
 */
async function saveMountRecord({ mountpoint, loop, device, image }) {
  await mkdir(mountsRoot, { recursive: true })
  const record = join(mountsRoot, `${basename(mountpoint)}.json`)
  await writeFile(record, JSON.stringify({ mountpoint, loop, device, image }, null, 2))
}

/**
 * `repart loop-mount IMAGE`: attach a loop, mount the root partition
 * privately. Prints the mountpoint. Records the loop/device pairing so
 * `loop-unmount` can fully reverse this. Requires a regular file — real
 * disks are their own device nodes and don't need (and can't have) a loop.
 */
async function loopMountCommand(args) {
  const { values, positionals } = parsed(args, {
    partition: { type: "string" },
    subvol: { type: "string" },
    "read-only": { type: "boolean" },
    help: { type: "boolean", short: "h" },
  })
  if (values.help) {
    console.log(LOOP_MOUNT_HELP)
    return
  }
  if (positionals.length !== 1) fail("loop-mount needs exactly one IMAGE")
  const image = await existing(positionals[0], "image")
  if (!(await lstat(image)).isFile()) fail(`not an image file: ${image}`)
  const partition = setting(values, "partition")
  const subvol = setting(values, "subvol")
  const readOnly = settingBool(values, "read-only")
  if (partition !== undefined && !/^\d+$/.test(partition)) fail(`invalid partition number: ${partition}`)

  const loop = await commandOutput("losetup", ["-fP", "--show", image])
  const device = await findRootPartition(loop, partition)
  if (!device) fail("partition not found")
  const mountpoint = await createState(undefined, "mount-")
  const mountOptions = [subvol ? `subvol=${subvol}` : "", readOnly ? "ro" : ""].filter(Boolean)
  try {
    await run("mount", [...(mountOptions.length ? ["-o", mountOptions.join(",")] : []), device, mountpoint])
  } catch (error) {
    await rm(mountpoint, { recursive: true, force: true })
    await run("losetup", ["-d", loop])
    throw error
  }
  await saveMountRecord({ mountpoint, loop, device, image })
  note("loop-mount", `attached ${image} as ${loop}, mounted ${device}`)
  console.log(mountpoint)
}

/**
 * `repart loop-unmount MOUNTPOINT`: reverse one `repart loop-mount`.
 * Looks up the recorded loop/device, umounts recursively, removes the private
 * mountpoint, detaches the loop, deletes the record. Fails (loudly, after
 * attempting the rest) if any teardown step fails — a leaked loop or mount
 * should be visible, not silent.
 */
async function loopUnmountCommand(args) {
  const { values, positionals } = parsed(args, { help: { type: "boolean", short: "h" } })
  if (values.help) {
    console.log(LOOP_UNMOUNT_HELP)
    return
  }
  if (positionals.length !== 1) fail("loop-unmount needs exactly one MOUNTPOINT")
  const wanted = positionals[0]
  await mkdir(mountsRoot, { recursive: true })
  const records = []
  for (const entry of await readdir(mountsRoot)) {
    if (!entry.endsWith(".json")) continue
    try {
      records.push(JSON.parse(await readFile(join(mountsRoot, entry), "utf8")))
    } catch {}
  }
  const record = records.find(({ mountpoint }) => mountpoint === wanted || basename(mountpoint) === wanted)
  if (!record) {
    const known = records.map(({ mountpoint }) => mountpoint).join("\n  ")
    fail(`not a repart mount: ${wanted}${known ? `\nknown mounts:\n  ${known}` : ""}`)
  }
  const { mountpoint, loop } = record
  const mounted = await run("findmnt", ["-rn", mountpoint], { allowFailure: true })
  if (mounted.status === 0) await run("umount", ["-R", mountpoint])
  else if (mounted.status !== 1) fail(`findmnt could not determine mount state for ${mountpoint} (status ${mounted.status})`)
  await rmdir(mountpoint).catch(() => {})
  await run("losetup", ["-d", loop])
  await rm(join(mountsRoot, `${basename(mountpoint)}.json`), { force: true })
  note("loop-unmount", `unmounted ${mountpoint}, detached ${loop}`)
}

/**
 * Where a dated subvolume lives in the canonical scheme. Pure string
 * computation against the base/flavor/arch/date rules — no filesystem access.
 * root base carries the arch segment; home base does not.
 */
function subvolPath(base, date, flavor) {
  const f = flavor || flavorSegment()
  return base === "home" ? `/home/${f}/${date}` : `/root/${f}/${archSegment()}/${date}`
}

/** Parse `btrfs subvolume list` output into {id, path} pairs. */
async function listSubvolumes(mountpoint) {
  const output = await commandOutput("btrfs", ["subvolume", "list", mountpoint])
  return output.split("\n").filter(Boolean).map((line) => ({
    id: line.match(/^ID\s+(\d+)/)?.[1],
    path: line.trim().split(/\s+/).at(-1),
  }))
}

/**
 * Dated subvolumes on a mounted filesystem, in scheme form.
 * Everything not matching root/<flavor>/<arch>/YYYYMMDD or
 * home/<flavor>/YYYYMMDD is invisible to this toolkit by design.
 */
async function knownSubvols(mountpoint, base, flavor) {
  const f = flavor || flavorSegment()
  const rootBase = `root/${f}/${archSegment()}/`
  const homeBase = `home/${f}/`
  const volumes = await listSubvolumes(mountpoint)
  return volumes.flatMap(({ id, path }) => {
    const kind = base === "all"
      ? (path.startsWith(rootBase) ? "root" : path.startsWith(homeBase) ? "home" : undefined)
      : path.startsWith(base === "root" ? rootBase : homeBase) ? base : undefined
    const schemeBase = kind === "root" ? rootBase : homeBase
    const date = path.slice(schemeBase.length)
    return kind && /^\d{8}$/.test(date) && !date.includes("/") ? [{ id, kind, date, path: `/${path}` }] : []
  })
}

/** `repart subvol-path [DATE]`: print one scheme path. */
async function subvolPathCommand(args) {
  const { values, positionals } = parsed(args, {
    base: { type: "string" },
    flavor: { type: "string" },
    help: { type: "boolean", short: "h" },
  })
  if (values.help) {
    console.log(SUBVOL_PATH_HELP)
    return
  }
  if (positionals.length > 1) fail("subvol-path accepts at most one date")
  const base = baseSegment(setting(values, "base") || "root")
  const flavor = setting(values, "flavor") || flavorSegment()
  console.log(subvolPath(base, validDate(positionals[0] || process.env.REPART_DATE || today()), flavor))
}

/** `repart btrfs-subvols MOUNT`: TSV of dated subvolumes, root rows first. */
async function btrfsSubvolsCommand(args) {
  const { values, positionals } = parsed(args, {
    base: { type: "string" },
    flavor: { type: "string" },
    help: { type: "boolean", short: "h" },
  })
  if (values.help) {
    console.log(BTRFS_SUBVOLS_HELP)
    return
  }
  if (positionals.length !== 1) fail("btrfs-subvols needs exactly one MOUNT")
  const base = setting(values, "base") || "all"
  if (base !== "root" && base !== "home" && base !== "all") fail(`invalid --base '${base}' (want root, home, or all)`)
  const flavor = setting(values, "flavor") || flavorSegment()
  const mountpoint = await directory(positionals[0], "mount")
  const subvols = await knownSubvols(mountpoint, base, flavor)
  const defaultOutput = await commandOutput("btrfs", ["subvolume", "get-default", mountpoint], true)
  const defaultPath = `/${defaultOutput.match(/ path (.+)$/)?.[1] || ""}`
  console.log("kind\tdate\tpath\tdefault")
  for (const subvol of subvols.sort((a, b) => (a.kind === b.kind ? a.date.localeCompare(b.date) : a.kind === "root" ? -1 : 1))) {
    console.log(`${subvol.kind}\t${subvol.date}\t${subvol.path}\t${subvol.path === defaultPath}`)
  }
}

/**
 * `repart btrfs-default MOUNT SELECTOR`: set the default subvolume (what
 * boots). The selector must resolve to an exact known root-base subvolume —
 * a YYYYMMDD date, an absolute scheme path, or "latest" — because a typo here
 * means an unbootable disk. Home subvols are rejected outright.
 */
async function btrfsDefaultCommand(args) {
  const { values, positionals } = parsed(args, {
    flavor: { type: "string" },
    help: { type: "boolean", short: "h" },
  })
  if (values.help) {
    console.log(BTRFS_DEFAULT_HELP)
    return
  }
  if (positionals.length !== 2) fail("btrfs-default needs MOUNT and DATE|PATH|latest")
  const mountpoint = await directory(positionals[0], "mount")
  const selector = positionals[1]
  const flavor = setting(values, "flavor") || flavorSegment()
  const subvols = await knownSubvols(mountpoint, "root", flavor)
  const target = selector === "latest"
    ? subvols.sort((a, b) => a.path.localeCompare(b.path)).at(-1)
    : subvols.find((subvol) => subvol.path === (isAbsolute(selector) ? selector : subvolPath("root", validDate(selector), flavor)))
  if (!target) fail(selector === "latest" ? "no known root-base subvolumes" : `not an exact known root-base subvolume path: ${selector}`)
  await run("btrfs", ["subvolume", "set-default", target.id, mountpoint])
  note("btrfs-default", `default subvolume set to ${target.path} (id ${target.id})`)
}

/** Flat dispatch: one command word, one function. */
const COMMANDS = {
  render: (args) => renderCommand(args).then((tree) => { if (tree) console.log(tree) }),
  format: (args) => previewCommand("format", args, FORMAT_HELP),
  pivot: (args) => previewCommand("pivot", args, PIVOT_HELP),
  write: writeCommand,
  "loop-mount": loopMountCommand,
  "loop-unmount": loopUnmountCommand,
  "subvol-path": subvolPathCommand,
  "btrfs-subvols": btrfsSubvolsCommand,
  "btrfs-default": btrfsDefaultCommand,
}

async function main() {
  const args = process.argv.slice(2)
  const command = args.shift()
  if (!command || command === "--help" || command === "-h") return console.log(HELP)
  const handler = COMMANDS[command]
  if (!handler) fail(`unknown command: ${command} (see repart --help)`)
  await handler(args)
}

main().catch((error) => {
  if (error instanceof CliError) {
    console.error(`repart: error: ${error.message}`)
    process.exitCode = 2
  } else {
    console.error(error)
    process.exitCode = 1
  }
})
