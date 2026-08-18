#!/usr/bin/env node

/**
 * Manage systemd-repart profiles, persistent disk plans, mounted images, and
 * dated btrfs boot slots. Data-producing commands reserve stdout for their
 * documented result; progress and mutation messages always use stderr.
 */
const { createHash } = require("node:crypto")
const { spawn } = require("node:child_process")
const {
  cp,
  lstat,
  mkdir,
  mkdtemp,
  readFile,
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

Build and apply auditable systemd-repart plans.

Commands:
  profile render   Render a tokenized definition or mkosi tree
  disk plan        Preview and persist a format or migration plan
  disk apply       Apply an unchanged, explicitly confirmed plan
  image with       Mount an image while running a command
  slot path        Print the canonical path for a dated btrfs slot
  slot show        List known OS and home slots
  slot set         Select the default OS slot

Run "repart <command> --help" or "repart <command> <subcommand> --help"
for command options, behavior, and examples.`

const PROFILE_HELP = `Usage: repart profile render --base DIR [options]

Copy a base tree, overlay later trees, and replace @UPPERCASE@ tokens. The
rendered tree is durable state under DIR/var and its path is printed to stdout.
Remove it explicitly when it is no longer useful.

Options:
  --base DIR          Base tree (required)
  --overlay DIR       Overlay tree; repeatable, later files win
  --preserve PATH     Do not resolve tokens beneath this relative path
  --date YYYYMMDD     DATE token (default: today)
  --arch ARCH         ARCH token (default: mapped host architecture)
  --swap SIZE         SWAP token (default: 4G)
  --set NAME=VALUE    Define or override a token; repeatable
  --name NAME         State directory name (default: profile-<timestamp>)
  -h, --help          Show this help

Built-in tokens: DATE, ARCH, SWAP, OS_PREFIX, HOME_PREFIX.

Example:
  repart profile render --base etc --overlay local --set CHANNEL=stable`

const DISK_HELP = `Usage: repart disk <plan|apply> ...

"plan" renders canonical definitions, fingerprints the target, runs a dry
preview, and persists everything needed by "apply". "apply" rejects changed
plan contents, changed targets, mounted targets, and unapproved repart flags.

Commands:
  plan format TARGET [options]              Plan a fresh offline layout
  plan migrate TARGET --source MOUNT [...]  Plan btrfs BlockDeviceReplace
  apply PLAN --confirm TARGET               Apply an exact persisted plan

Run "repart disk plan --help" or "repart disk apply --help" for details.`

const DISK_PLAN_HELP = `Usage: repart disk plan <format|migrate> TARGET [options]

Persist a reviewed plan under DIR/var/<name>. Planning always invokes
systemd-repart with --dry-run=yes; apply changes only that flag to no.

Options:
  --source MOUNT      Single-device btrfs source (migrate only, required)
  --base DIR          Replace the canonical universal profile base
  --overlay DIR       Add a profile overlay; repeatable
  --date YYYYMMDD     Profile DATE token
  --arch ARCH         Profile ARCH token
  --swap SIZE         Profile SWAP token
  --set NAME=VALUE    Define a profile token; repeatable
  --name NAME         Plan directory name (default: <operation>-<target>-<time>)
  -h, --help          Show this help

Raw systemd-repart arguments are intentionally forbidden.`

const DISK_APPLY_HELP = `Usage: repart disk apply PLAN --confirm TARGET

Apply a persisted plan only after its definitions, arguments, target path, and
target fingerprint have been revalidated. The plan remains in DIR/var for
audit or explicit removal.`

const IMAGE_HELP = `Usage: repart image with IMAGE [options] [-- COMMAND...]

Attach an image to a new loop device, mount its root partition at a private
DIR/var mountpoint, and run COMMAND with REPART_IMAGE, REPART_LOOP,
REPART_DEVICE, and REPART_MOUNT exported. Unlike profiles and plans, the mount
directory and loop device are always cleaned up when the command exits.

Options:
  --partition NUMBER  Mount this partition instead of discovering root
  --subvol PATH       Mount this btrfs subvolume
  --read-only         Mount read-only
  -h, --help          Show this help

If COMMAND is omitted, the user's shell is started.`

const SLOT_HELP = `Usage: repart slot <path|show|set> ...

Manage dated btrfs subvolumes beneath REPART_OS_PREFIX and REPART_HOME_PREFIX.

Commands:
  path [--home] [YYYYMMDD]       Print a canonical slot path
  show MOUNT                     Print stable TSV slot data
  set MOUNT <YYYYMMDD|PATH|latest>  Set the default OS subvolume`

class CliError extends Error {}

const script = __filename
const scriptDir = dirname(script)
// Installed as DIR/bin/repart; source-tree execution keeps defs beside repart.ts.
const root = basename(scriptDir) === "bin" ? dirname(scriptDir) : scriptDir
const stateRoot = join(root, "var")

function fail(message) {
  throw new CliError(message)
}

function note(scope, message) {
  console.error(`repart ${scope}: ${message}`)
}

function mappedArch() {
  const value = process.env.REPART_ARCH || hostArch()
  return value === "x64" || value === "x86_64" ? "amd64" : value === "aarch64" ? "arm64" : value
}

function today() {
  const date = new Date()
  return `${date.getUTCFullYear()}${String(date.getUTCMonth() + 1).padStart(2, "0")}${String(date.getUTCDate()).padStart(2, "0")}`
}

function timestamp() {
  return new Date().toISOString().replaceAll(/[-:]/g, "").replace(/\.\d{3}Z$/, "Z")
}

function validDate(value) {
  if (!/^\d{8}$/.test(value)) fail(`bad date '${value}' (want YYYYMMDD)`)
  return value
}

function validStateName(value) {
  if (!/^[A-Za-z0-9][A-Za-z0-9._-]*$/.test(value) || value === "." || value === "..") {
    fail(`invalid state name '${value}' (use letters, digits, dot, dash, or underscore)`)
  }
  return value
}

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

function parsed(args, options) {
  try {
    return parseArgs({ args, allowPositionals: true, strict: true, options })
  } catch (error) {
    fail(error.message)
  }
}

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

async function existing(path, description = "path") {
  try {
    return await realpath(path)
  } catch {
    fail(`${description} does not exist: ${path}`)
  }
}

async function directory(path, description) {
  const canonical = await existing(path, description)
  if (!(await lstat(canonical)).isDirectory()) fail(`${description} is not a directory: ${path}`)
  return canonical
}

function profileOptions() {
  return {
    base: { type: "string" },
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

function isPreserved(file, tree, preserves) {
  const local = relative(tree, file)
  return preserves.some((path) => local === path || local.startsWith(`${path}${sep}`))
}

async function renderProfile(args, { ownedByPlan = false } = {}) {
  const { values, positionals } = parsed(args, profileOptions())
  if (values.help) {
    console.log(PROFILE_HELP)
    return undefined
  }
  if (positionals.length) fail(`unexpected profile argument: ${positionals[0]}`)
  if (!values.base) fail("--base must name a directory")

  const base = await directory(values.base, "base")
  const overlays = []
  for (const overlay of values.overlay || []) overlays.push(await directory(overlay, "overlay"))
  const preserves = (values.preserve || []).map((path) => {
    const normalized = path.replace(/^\.\//, "")
    if (!normalized || isAbsolute(normalized) || normalized.split(/[\\/]/).includes("..")) {
      fail(`--preserve must stay beneath the rendered tree: ${path}`)
    }
    return normalized
  })
  const tokens = new Map([
    ["DATE", validDate(values.date || today())],
    ["ARCH", values.arch || mappedArch()],
    ["SWAP", values.swap || "4G"],
    ["OS_PREFIX", process.env.REPART_OS_PREFIX || "/os/superbfowle"],
    ["HOME_PREFIX", process.env.REPART_HOME_PREFIX || "/home/superbfowle"],
  ])
  for (const pair of values.set || []) {
    const separator = pair.indexOf("=")
    const name = pair.slice(0, separator)
    if (separator < 1) fail("--set needs NAME=VALUE")
    if (!/^[A-Z][A-Z0-9_]*$/.test(name)) fail(`invalid token name: ${name}`)
    tokens.set(name, pair.slice(separator + 1))
  }

  const tree = await createState(values.name, ownedByPlan ? "definitions-" : "profile-")
  try {
    await cp(base, tree, { recursive: true, force: true })
    for (const overlay of overlays) await cp(overlay, tree, { recursive: true, force: true })
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
      fail("unresolved uppercase profile tokens")
    }
  } catch (error) {
    await rm(tree, { recursive: true, force: true })
    throw error
  }
  note("profile", `rendered profile at ${tree}; remove explicitly when no longer needed`)
  return tree
}

async function commandOutput(command, args, allowFailure = false) {
  const result = await run(command, args, { allowFailure })
  return result.stdout.trim()
}

async function fingerprint(target) {
  const info = await lstat(target, { bigint: true })
  const identity = `mode=${info.mode}|dev=${info.dev}|inode=${info.ino}|rdev=${info.rdev}|size=${info.size}`
  const block = await commandOutput("lsblk", ["-dnro", "MAJ:MIN,SIZE,SERIAL,WWN,MODEL", target], true)
  const table = await commandOutput("sfdisk", ["--dump", target], true)
  const tableHash = createHash("sha256").update(table).digest("hex")
  return `${identity}|block=${block}|table=${tableHash}`
}

async function planDigest(plan) {
  // Hash names as well as bytes so adding, removing, renaming, or editing any
  // reviewed input invalidates the plan before a destructive apply.
  const files = [join(plan, "plan"), join(plan, "arguments"), ...(await filesBelow(join(plan, "definitions")))]
  const hash = createHash("sha256")
  for (const file of files.sort()) hash.update(relative(plan, file)).update("\0").update(await readFile(file)).update("\0")
  return hash.digest("hex")
}

async function checkMigrateSource(source) {
  const fsType = await commandOutput("stat", ["-f", "-c", "%T", source])
  if (fsType !== "btrfs") fail(`migration source is not btrfs: ${source}`)
  const listing = await commandOutput("btrfs", ["filesystem", "show", source])
  const count = listing.split("\n").filter((line) => /\bdevid\b/.test(line)).length
  if (count !== 1) fail(`migration source must be single-device btrfs (found ${count})`)
  const versionLine = (await commandOutput("systemd-repart", ["--version"])).split("\n")[0]
  const version = Number(versionLine.trim().split(/\s+/)[1])
  if (!Number.isInteger(version)) fail("cannot parse systemd-repart version")
  if (version < 261) fail(`migration requires systemd-repart >=261 (found ${version})`)
}

async function definitionDirectory(name) {
  for (const candidate of [join(root, "etc", "defs", name), join(scriptDir, "defs", name)]) {
    try {
      if ((await lstat(candidate)).isDirectory()) return candidate
    } catch {}
  }
  fail(`canonical ${name} definitions are not installed`)
}

function defaultPlanName(operation, target) {
  const targetName = basename(target).replaceAll(/[^A-Za-z0-9._-]/g, "-") || "target"
  return `${operation}-${targetName}-${timestamp()}`
}

async function diskPlan(args) {
  if (!args.length || args[0] === "--help" || args[0] === "-h") {
    console.log(DISK_PLAN_HELP)
    return
  }
  const operation = args.shift()
  if (operation !== "format" && operation !== "migrate") fail("plan operation must be format or migrate")
  const options = profileOptions()
  delete options.preserve
  options.source = { type: "string" }
  const { values, positionals } = parsed(args, options)
  if (values.help) {
    console.log(DISK_PLAN_HELP)
    return
  }
  if (positionals.length !== 1) fail(`${operation} needs exactly one TARGET`)
  const target = await existing(positionals[0], "target")
  let source = ""
  if (values.source) {
    if (operation !== "migrate") fail("--source is only valid for migrate")
    source = await directory(values.source, "migration source")
  }
  if (operation === "migrate") {
    if (!source) fail("migrate requires --source MOUNT")
    await checkMigrateSource(source)
  }

  const base = values.base || await definitionDirectory("universal.d")
  const flavor = await definitionDirectory(operation === "migrate" ? "bdr.d" : "format.d")
  const renderArgs = ["--base", base]
  for (const overlay of values.overlay || []) renderArgs.push("--overlay", overlay)
  renderArgs.push("--overlay", flavor)
  for (const key of ["date", "arch", "swap"]) if (values[key]) renderArgs.push(`--${key}`, values[key])
  for (const value of values.set || []) renderArgs.push("--set", value)
  if (source) renderArgs.push("--set", `SOURCE=${source}`)

  const plan = await createState(values.name || defaultPlanName(operation, target), "plan-")
  let definitions
  try {
    definitions = await renderProfile(renderArgs, { ownedByPlan: true })
    await rename(definitions, join(plan, "definitions"))
    definitions = undefined
    const planText = `operation=${operation}\ntarget=${target}\nsource=${source}\nfingerprint=${await fingerprint(target)}\n`
    await writeFile(join(plan, "plan"), planText)
    const repartArgs = operation === "format"
      ? ["--offline=yes", "--empty=force", "--dry-run=yes"]
      : ["--empty=force", "--dry-run=yes"]
    await writeFile(join(plan, "arguments"), `${repartArgs.join("\n")}\n`)
    await writeFile(join(plan, "digest"), `${await planDigest(plan)}\n`)
    note("disk", `dry-run ${operation} plan for ${target}`)
    await run("systemd-repart", [`--definitions=${join(plan, "definitions")}`, ...repartArgs, target], {
      // Preserve stdout as the plan-path data channel even if repart is noisy.
      stdio: ["inherit", process.stderr, process.stderr],
    })
  } catch (error) {
    if (definitions) await rm(definitions, { recursive: true, force: true })
    await rm(plan, { recursive: true, force: true })
    throw error
  }
  note("disk", `persisted plan at ${plan}`)
  console.log(plan)
}

async function rejectMounted(target) {
  const devices = [target]
  if ((await lstat(target)).isFile()) {
    const loops = await commandOutput("losetup", ["-j", target, "-O", "NAME", "-n"], true)
    devices.push(...loops.split("\n").filter(Boolean))
  }
  for (const rootDevice of devices) {
    const listed = await commandOutput("lsblk", ["-nrpo", "NAME", rootDevice], true)
    for (const device of listed.split("\n").filter(Boolean).length ? listed.split("\n").filter(Boolean) : [rootDevice]) {
      const result = await run("findmnt", ["-rn", "-S", device], { allowFailure: true })
      if (result.status === 0) fail(`target or target partition is mounted: ${device}`)
    }
  }
}

async function diskApply(args) {
  const { values, positionals } = parsed(args, {
    confirm: { type: "string" },
    help: { type: "boolean", short: "h" },
  })
  if (values.help) {
    console.log(DISK_APPLY_HELP)
    return
  }
  if (positionals.length !== 1 || !values.confirm) fail("usage: repart disk apply PLAN --confirm TARGET")
  const plan = await directory(positionals[0], "plan")
  const confirmed = await existing(values.confirm, "confirmation target")
  for (const path of ["plan", "arguments", "digest"]) await existing(join(plan, path), `plan ${path}`)
  await directory(join(plan, "definitions"), "plan definitions")
  if (await planDigest(plan) !== (await readFile(join(plan, "digest"), "utf8")).trim()) {
    fail("plan contents changed after preview")
  }
  const metadata = new Map(
    (await readFile(join(plan, "plan"), "utf8")).trimEnd().split("\n").map((line) => {
      const index = line.indexOf("=")
      return [line.slice(0, index), line.slice(index + 1)]
    }),
  )
  const operation = metadata.get("operation")
  const target = metadata.get("target")
  const source = metadata.get("source")
  const expected = operation === "format"
    ? ["--offline=yes", "--empty=force", "--dry-run=yes"]
    : operation === "migrate" ? ["--empty=force", "--dry-run=yes"] : undefined
  if (!expected) fail(`invalid planned operation: ${operation}`)
  const repartArgs = (await readFile(join(plan, "arguments"), "utf8")).trimEnd().split("\n")
  if (JSON.stringify(repartArgs) !== JSON.stringify(expected)) fail("plan contains invalid repart arguments")
  if (confirmed !== target) fail(`confirmation target differs from planned target (${confirmed} != ${target})`)
  if (await fingerprint(target) !== metadata.get("fingerprint")) fail("target identity/fingerprint changed since planning")
  await rejectMounted(target)
  if (operation === "migrate") await checkMigrateSource(source)
  const applyArgs = repartArgs.map((arg) => arg === "--dry-run=yes" ? "--dry-run=no" : arg)
  note("disk", `applying persisted ${operation} plan to ${target}; plan retained at ${plan}`)
  await run("systemd-repart", [`--definitions=${join(plan, "definitions")}`, ...applyArgs, target], {
    // apply has no stdout contract; all mutation narration is diagnostic.
    stdio: ["inherit", process.stderr, process.stderr],
  })
}

async function diskCommand(args) {
  const command = args.shift()
  if (!command || command === "--help" || command === "-h") return console.log(DISK_HELP)
  if (command === "plan") return diskPlan(args)
  if (command === "apply") return diskApply(args)
  fail(`unknown disk command: ${command}`)
}

async function imageCommand(args) {
  const command = args.shift()
  if (!command || command === "--help" || command === "-h") return console.log(IMAGE_HELP)
  if (command !== "with") fail(`unknown image command: ${command}`)
  const separator = args.indexOf("--")
  const childCommand = separator < 0 ? [] : args.splice(separator + 1)
  if (separator >= 0) args.splice(separator)
  const { values, positionals } = parsed(args, {
    partition: { type: "string" },
    subvol: { type: "string" },
    "read-only": { type: "boolean" },
    help: { type: "boolean", short: "h" },
  })
  if (values.help) return console.log(IMAGE_HELP)
  if (positionals.length !== 1) fail("image with needs exactly one IMAGE")
  const image = await existing(positionals[0], "image")
  if (!(await lstat(image)).isFile()) fail(`not an image file: ${image}`)
  if (values.partition && !/^\d+$/.test(values.partition)) fail(`invalid partition number: ${values.partition}`)

  let loop
  let mountpoint
  let interrupted
  const onInterrupt = () => { interrupted = 130 }
  const onTerminate = () => { interrupted = 143 }
  process.on("SIGINT", onInterrupt)
  process.on("SIGTERM", onTerminate)
  try {
    loop = await commandOutput("losetup", ["-fP", "--show", image])
    note("image", `attached owned loop ${loop}`)
    let device
    if (values.partition) {
      const rows = (await commandOutput("lsblk", ["-nrpo", "NAME,TYPE", loop])).split("\n")
      const suffix = new RegExp(`p?${values.partition}$`)
      device = rows.map((line) => line.trim().split(/\s+/)).find(([name, type]) => type === "part" && suffix.test(name))?.[0]
    } else {
      const rows = (await commandOutput("lsblk", ["-nrpo", "NAME,PARTTYPE,TYPE", loop])).split("\n")
      device = rows.map((line) => line.trim().split(/\s+/)).find(([, type, kind]) =>
        kind === "part" && /^(4f68bce3-e8cd-4db1-96e7-fbcaf984b709|b921b045-1df0-41c3-af44-4c6f280d3fae)$/i.test(type))?.[0]
      if (!device) {
        const labeled = (await commandOutput("lsblk", ["-nrpo", "NAME,LABEL,TYPE", loop])).split("\n")
          .map((line) => line.trim().split(/\s+/)).filter(([, label, kind]) => label === "root" && kind === "part")
        device = labeled.at(-1)?.[0]
        if (!device) fail("no GPT root partition found; canonical-last fallback requires a partition labeled root")
        const partitions = (await commandOutput("lsblk", ["-nrpo", "NAME,TYPE", loop])).split("\n")
          .map((line) => line.trim().split(/\s+/)).filter(([, kind]) => kind === "part")
        if (device !== partitions.at(-1)?.[0]) fail("root-labeled partition is not canonical-last")
      }
    }
    if (!device) fail("partition not found")
    mountpoint = await createState(undefined, "mount-")
    const mountOptions = [values.subvol ? `subvol=${values.subvol}` : "", values["read-only"] ? "ro" : ""].filter(Boolean)
    await run("mount", [...(mountOptions.length ? ["-o", mountOptions.join(",")] : []), device, mountpoint])
    note("image", `mounted ${device} at private mountpoint ${mountpoint}`)
    const env = { ...process.env, REPART_IMAGE: image, REPART_LOOP: loop, REPART_DEVICE: device, REPART_MOUNT: mountpoint }
    const executable = childCommand.length ? childCommand[0] : process.env.SHELL || "/bin/sh"
    const childArgs = childCommand.length ? childCommand.slice(1) : []
    const result = await run(executable, childArgs, { env, stdio: "inherit", allowFailure: true })
    if (result.status !== 0) process.exitCode = result.status || interrupted || 1
  } finally {
    if (mountpoint) {
      const mounted = await run("findmnt", ["-rn", mountpoint], { allowFailure: true })
      if (mounted.status === 0) await run("umount", ["-R", mountpoint])
      await rmdir(mountpoint).catch(() => {})
    }
    if (loop) await run("losetup", ["-d", loop])
    process.off("SIGINT", onInterrupt)
    process.off("SIGTERM", onTerminate)
    if (interrupted) process.exitCode = interrupted
  }
}

function slotPath(kind, date) {
  const osPrefix = process.env.REPART_OS_PREFIX || "/os/superbfowle"
  const homePrefix = process.env.REPART_HOME_PREFIX || "/home/superbfowle"
  return kind === "home" ? `${homePrefix}/${date}` : `${osPrefix}/${mappedArch()}/${date}`
}

async function listSubvolumes(mountpoint) {
  const output = await commandOutput("btrfs", ["subvolume", "list", mountpoint])
  return output.split("\n").filter(Boolean).map((line) => ({
    id: line.match(/^ID\s+(\d+)/)?.[1],
    path: line.trim().split(/\s+/).at(-1),
  }))
}

async function knownSlots(mountpoint) {
  const osBase = `${(process.env.REPART_OS_PREFIX || "/os/superbfowle").replace(/^\//, "")}/${mappedArch()}/`
  const homeBase = `${(process.env.REPART_HOME_PREFIX || "/home/superbfowle").replace(/^\//, "")}/`
  const volumes = await listSubvolumes(mountpoint)
  return volumes.flatMap(({ id, path }) => {
    const kind = path.startsWith(osBase) ? "os" : path.startsWith(homeBase) ? "home" : undefined
    const base = kind === "os" ? osBase : homeBase
    const date = path.slice(base.length)
    return kind && /^\d{8}$/.test(date) && !date.includes("/") ? [{ id, kind, date, path: `/${path}` }] : []
  })
}

async function slotCommand(args) {
  const command = args.shift()
  if (!command || command === "--help" || command === "-h") return console.log(SLOT_HELP)
  if (command === "path") {
    const { values, positionals } = parsed(args, {
      home: { type: "boolean" },
      help: { type: "boolean", short: "h" },
    })
    if (values.help) return console.log(`${SLOT_HELP}\n\npath defaults to today's OS slot; --home selects the home prefix.`)
    if (positionals.length > 1) fail("path accepts at most one date")
    return console.log(slotPath(values.home ? "home" : "os", validDate(positionals[0] || today())))
  }
  if (command !== "show" && command !== "set") fail(`unknown slot command: ${command}`)
  const { values, positionals } = parsed(args, { help: { type: "boolean", short: "h" } })
  if (values.help) return console.log(SLOT_HELP)
  const wanted = command === "show" ? 1 : 2
  if (positionals.length !== wanted) fail(`slot ${command} needs ${wanted === 1 ? "MOUNT" : "MOUNT and DATE|PATH|latest"}`)
  const mountpoint = await directory(positionals[0], "mount")
  const slots = await knownSlots(mountpoint)
  if (command === "show") {
    const defaultOutput = await commandOutput("btrfs", ["subvolume", "get-default", mountpoint], true)
    const defaultPath = `/${defaultOutput.match(/ path (.+)$/)?.[1] || ""}`
    console.log("kind\tdate\tpath\tdefault")
    for (const slot of slots.sort((a, b) => (a.kind === b.kind ? a.date.localeCompare(b.date) : a.kind === "os" ? -1 : 1))) {
      console.log(`${slot.kind}\t${slot.date}\t${slot.path}\t${slot.path === defaultPath}`)
    }
    return
  }
  const selector = positionals[1]
  const osSlots = slots.filter((slot) => slot.kind === "os")
  const target = selector === "latest"
    ? osSlots.sort((a, b) => a.path.localeCompare(b.path)).at(-1)
    : osSlots.find((slot) => slot.path === (isAbsolute(selector) ? selector : slotPath("os", validDate(selector))))
  if (!target) fail(selector === "latest" ? "no known OS slots" : `not an exact known OS slot path: ${selector}`)
  await run("btrfs", ["subvolume", "set-default", target.id, mountpoint])
  note("slot", `default slot set to ${target.path} (id ${target.id})`)
}

async function main() {
  const args = process.argv.slice(2)
  const command = args.shift()
  if (!command || command === "--help" || command === "-h") return console.log(HELP)
  if (command === "profile") {
    const subcommand = args.shift()
    if (!subcommand || subcommand === "--help" || subcommand === "-h") return console.log(PROFILE_HELP)
    if (subcommand !== "render") fail(`unknown profile command: ${subcommand}`)
    const tree = await renderProfile(args)
    if (tree) console.log(tree)
    return
  }
  if (command === "disk") return diskCommand(args)
  if (command === "image") return imageCommand(args)
  if (command === "slot") return slotCommand(args)
  fail(`unknown command: ${command}`)
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
