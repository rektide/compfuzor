#!/usr/bin/env node

/**
 * depsolve — pre-solve a mkosi subimage's package list against a scratch apt
 * root, without building anything.
 *
 * A failed "full desktop" build surfaces ONE apt resolution error per
 * multi-minute mkosi run (stale package names, or pkgset conflicts like
 * busybox vs busybox-static, resolvconf vs systemd-resolved, and the
 * pulseaudio daemon vs pipewire-audio). This bin converges the same answer
 * in seconds: it simulates `apt-get install` of the subimage's Packages=
 * list against a scratch apt root whose dpkg status is EMPTY — fresh-rootfs
 * semantics, the same view mkosi gets installing into a new rootfs — with
 * indices cached under DIR/var so nothing is refetched per run.
 *
 * Findings come in two kinds with two DIFFERENT fixes (never conflate):
 *   missing  "E: Unable to locate package X" / "no installation candidate" —
 *            a stale name from an older suite. Fix: RENAME in vars/pkgs.yaml.
 *   conflict "E: Unable to satisfy dependencies. Reached two conflicting
 *            assignments" — the requested set asks for two mutually exclusive
 *            packages. Fix: DROP or REPLACE the loser in vars/pkgs.yaml.
 *            --fix drops the first explicitly-requested package named in
 *            apt's conflict block. That one heuristic covers both apt shapes:
 *            the direct "X selected / X not selected because Y ... Conflicts
 *            X" and the transitive "X selected because: Y / but none
 *            installable because Z Conflicts X". A PROTECTED candidate
 *            (systemd, linux-image-amd64, ...) stops for manual resolution.
 *
 * Ported from .test-agent/mkosi-desktop/solve.sh, which converged the
 * 846-package trixie desktop set on 2026-10-06.
 *
 * Conventions (files/repart/repart.ts is the model):
 *   - stdout is data only (the converged list with --fix, JSON with --json);
 *     all narration goes to stderr
 *   - durable scratch lives under DIR/var, never /tmp
 *   - every flag has a DEPSOLVE_* env fallback; flags always win
 *   - simulate only: no debs are downloaded, nothing installs, no root
 *     needed (trusted=yes sources avoid keyring reads inside the scratch root)
 */
const { spawn } = require("node:child_process")
const { mkdir, readFile, readdir, rm, writeFile } = require("node:fs/promises")
const { arch: hostArch } = require("node:os")
const { basename, dirname, isAbsolute, join } = require("node:path")
const { parseArgs } = require("node:util")

const HELP = `Usage: depsolve.ts [options] [package...]

Pre-solve a mkosi subimage package list against a scratch apt root: simulate
apt-get install with an empty dpkg status (fresh-rootfs semantics, the same
view mkosi gets installing into a new rootfs) and converge stale names and
pkgset conflicts in seconds instead of one failed build per apt error.

Package input (first that applies):
  positionals    package names (whitespace or comma separated)
  stdin, if piped  one package per line (or comma separated)
  --conf PATH    mkosi conf to read [Content] Packages= from (default:
                 etc/mkosi.images/disk/mkosi.conf under the instance dir)

Modes:
  (default)      verify: one simulate. Exit 0 clean; exit 1 with categorized
                 findings (missing = RENAME in vars/pkgs.yaml, conflict =
                 DROP or REPLACE there)
  --fix          iterate: drop the offending requested package each round
                 until clean (a protected candidate stops for manual
                 resolution); prints the converged list to stdout

Options (flag wins over its DEPSOLVE_* variable):
  --conf PATH      subimage conf to solve [DEPSOLVE_CONF]
  --suite NAME     apt suite (default: conf Release, else trixie)
                   [DEPSOLVE_SUITE]
  --components L   comma list (default: conf Repositories, else
                   main,contrib,non-free,non-free-firmware)
                   [DEPSOLVE_COMPONENTS]
  --arch ARCH      apt architecture (default: conf Architecture, else mapped
                   host arch) [DEPSOLVE_ARCH]
  --mirror URL     mirror base; "/debian" is appended for the debian
                   distribution unless already present (default: conf Mirror,
                   else http://deb.debian.org = vars/common.yaml
                   APT_DEBIAN_MIRROR) [DEPSOLVE_MIRROR]
  --proxy URL      apt proxy (default http://127.0.0.1:3142/, this host's
                   apt-cacher-rs from apt-cacher-rs.src.pb; "" disables, like
                   -e APT_PROXY=) [DEPSOLVE_PROXY]
  --fix            converge by dropping offending requested packages
  --protect NAME   extra protected package (repeatable; comma list ok)
                   [DEPSOLVE_PROTECT]
  --json           machine-readable report on stdout instead of the list
  --no-update      skip apt-get update and use the cached indices
  --timeout SECS   per apt-get invocation (default 600) [DEPSOLVE_TIMEOUT]
  -h, --help       Show this help

Scratch apt root: <instance>/var/cache/depsolve/aptroot (kept between runs;
indices are wiped automatically when suite/mirror/components change).

Examples:
  bin/depsolve.ts                          # verify the disk subimage
  bin/depsolve.ts --fix > solve-pkgs.txt   # converge, keep the list
  bin/depsolve.ts --json                   # findings/drops as one JSON object
  bin/depsolve.ts --conf etc/mkosi.images/vps-seed/mkosi.conf
  bin/depsolve.ts resolvconf pipewire-audio          # ad-hoc names
  cat mypkgs.txt | bin/depsolve.ts --fix`

const DEFAULT_CONF = join("etc", "mkosi.images", "disk", "mkosi.conf")
const DEFAULT_PROXY = "http://127.0.0.1:3142/"
// vars/common.yaml APT_DEBIAN_MIRROR
const DEFAULT_MIRROR = "http://deb.debian.org"
const DEFAULT_SUITE = "trixie"
const DEFAULT_COMPONENTS = "main,contrib,non-free,non-free-firmware"
// Dropping any of these silently produces an unbootable or mute image; a
// conflict inside this set needs a human decision (extend with --protect).
const PROTECTED = [
  "systemd",
  "linux-image-amd64",
  "base-files",
  "bash",
  "apt",
  "dpkg",
  "util-linux",
  "mount",
  "pipewire",
  "pipewire-audio",
]
const MAX_ROUNDS = 250

/**
 * Fatal user-facing error: printed as "depsolve: error: ..." with exit code 2.
 * Distinguished from programming/IO errors, which crash with a stack (exit 1).
 */
class CliError extends Error {}

const script = __filename
const scriptDir = dirname(script)
// Installed as DIR/bin/depsolve.ts (raw bin, no wrapper: resolve the instance
// dir ourselves, like repart.ts); source-tree execution uses files/mkosi/.
const root = basename(scriptDir) === "bin" ? dirname(scriptDir) : scriptDir
const aptRoot = join(root, "var", "cache", "depsolve", "aptroot")
const statusFile = join(aptRoot, "var", "lib", "dpkg", "status")
const listsDir = join(aptRoot, "var", "lib", "apt", "lists")

/** Abort with a user-facing error message and exit code 2. */
function fail(message) {
  throw new CliError(message)
}

/** Narrate to stderr; stdout is reserved for data. */
function note(message) {
  console.error(`depsolve: ${message}`)
}

/** Map a machine architecture to Debian's: x64/x86_64 -> amd64, aarch64 -> arm64. */
function mappedArch(value) {
  return value === "x64" || value === "x86_64" ? "amd64" : value === "aarch64" ? "arm64" : value
}

/** The DEPSOLVE_* env var name for a dashed option: "no-update" -> DEPSOLVE_NO_UPDATE. */
function envName(option) {
  return `DEPSOLVE_${option.replaceAll("-", "_").toUpperCase()}`
}

/**
 * Resolve one setting: flag > DEPSOLVE_* variable > built-in default.
 * List options split their env value on commas; empty env counts as unset.
 */
function setting(values, option, { list = false } = {}) {
  if (values[option] !== undefined) return values[option]
  const raw = process.env[envName(option)]
  if (raw === undefined || raw === "") return list ? [] : undefined
  return list ? raw.split(",").map((item) => item.trim()).filter(Boolean) : raw
}

/** parseArgs wrapper: usage errors become clean CLI errors. */
function parsed(args, options) {
  try {
    return parseArgs({ args, allowPositionals: true, strict: true, options })
  } catch (error) {
    fail(error.message)
  }
}

/** Split a package-ish string: whitespace or commas, dropping comments. */
function splitList(value) {
  return value.split(/[\s,]+/).map((item) => item.trim()).filter((item) => item && !item.startsWith("#"))
}

/** Strip :arch suffixes, validate shape, dedupe preserving order. */
function canonicalize(names) {
  const seen = new Set()
  const bad = []
  const out = []
  for (const raw of names) {
    const name = raw.replace(/:[a-z0-9][a-z0-9-]*$/i, "")
    if (!/^[a-z0-9][a-z0-9+.-]*$/i.test(name)) bad.push(raw)
    else if (!seen.has(name)) {
      seen.add(name)
      out.push(name)
    }
  }
  if (bad.length) fail(`not package names: ${bad.join(", ")}`)
  return out
}

/**
 * Parse a mkosi .conf (ini) file: [Section] headers, Key=value lines,
 * indented continuation lines, # comments. Multiple occurrences of a key
 * accumulate (mkosi merges multiple Packages= lines).
 */
async function parseConfIfExists(path) {
  let text
  try {
    text = await readFile(path, "utf8")
  } catch {
    return null
  }
  const conf = new Map()
  let section = null
  let lastKey = null
  for (const raw of text.split("\n")) {
    if (/^\s/.test(raw) && section !== null && lastKey !== null) {
      const values = conf.get(section).get(lastKey)
      values[values.length - 1] += `\n${raw.trim()}`
      continue
    }
    const line = raw.trim()
    if (!line || line.startsWith("#") || line.startsWith(";")) continue
    const header = line.match(/^\[(.+)\]$/)
    if (header) {
      section = header[1]
      if (!conf.has(section)) conf.set(section, new Map())
      lastKey = null
      continue
    }
    const pair = line.match(/^([A-Za-z][A-Za-z0-9-]*)\s*=\s*(.*)$/)
    if (pair && section !== null) {
      lastKey = pair[1]
      const values = conf.get(section).get(lastKey) || []
      values.push(pair[2])
      conf.get(section).set(lastKey, values)
    }
  }
  return conf
}

/** All [Content] Packages= entries, comma/continuation split, order kept. */
function confPackages(conf) {
  if (!conf) return []
  const out = []
  for (const value of conf.get("Content")?.get("Packages") || []) {
    for (const item of value.split(/[,\n]/)) {
      const name = item.trim()
      if (name && !name.startsWith("#")) out.push(name)
    }
  }
  return out
}

/**
 * [Distribution] defaults from the conf graph: the main etc/mkosi.conf sets
 * the universal Distribution/Release/Repositories/Mirror, a subimage conf
 * may override. Later confs win; the LAST occurrence of a key wins (mkosi).
 */
function distributionDefaults(mainConf, targetConf) {
  const dist = new Map()
  for (const conf of [mainConf, targetConf]) {
    const section = conf?.get("Distribution")
    if (!section) continue
    for (const [key, values] of section) dist.set(key, values.at(-1))
  }
  return dist
}

/**
 * Run apt-get and await {status, stdout, stderr}; killed (and rejected) after
 * timeoutMs. Streams are captured, never inherited: output is evidence.
 */
function aptRun(args, timeoutMs) {
  return new Promise((resolvePromise, rejectPromise) => {
    const child = spawn("apt-get", args, { stdio: ["ignore", "pipe", "pipe"] })
    let stdout = ""
    let stderr = ""
    let timedOut = false
    const timer = setTimeout(() => {
      timedOut = true
      child.kill("SIGTERM")
    }, timeoutMs)
    child.stdout?.on("data", (chunk) => (stdout += chunk))
    child.stderr?.on("data", (chunk) => (stderr += chunk))
    child.on("error", (error) => {
      clearTimeout(timer)
      rejectPromise(error.code === "ENOENT" ? new CliError("apt-get not found in PATH") : error)
    })
    child.on("close", (status) => {
      clearTimeout(timer)
      if (timedOut) rejectPromise(new CliError(`apt-get timed out after ${Math.round(timeoutMs / 1000)}s: apt-get ${args.join(" ").slice(0, 120)}...`))
      else resolvePromise({ status: status ?? 1, stdout, stderr })
    })
  })
}

/** The scratch-root options every apt-get invocation carries. Dir points
 * every apt path at the scratch root; the empty status file is spelled out
 * because fresh-rootfs semantics are the whole point.
 */
function aptBaseArgs() {
  return ["-o", `Dir=${aptRoot}`, "-o", `Dir::State::status=${statusFile}`]
}

/**
 * Create/refresh the scratch apt root. When sources.list changes (suite,
 * mirror, or components), cached indices from the old suite are wiped so a
 * solve can never mix lists from two suites.
 */
async function prepareAptRoot(sourcesLine, confdText) {
  const sourcesPath = join(aptRoot, "etc", "apt", "sources.list")
  for (const dir of [
    join(aptRoot, "etc", "apt", "apt.conf.d"),
    join(aptRoot, "etc", "apt", "sources.list.d"),
    join(aptRoot, "var", "lib", "dpkg"),
    join(listsDir, "partial"),
    join(aptRoot, "var", "cache", "apt", "archives", "partial"),
  ]) {
    await mkdir(dir, { recursive: true })
  }
  const previous = await readFile(sourcesPath, "utf8").catch(() => null)
  if (previous !== null && previous !== sourcesLine) {
    await rm(listsDir, { recursive: true, force: true })
    await mkdir(join(listsDir, "partial"), { recursive: true })
  }
  await writeFile(sourcesPath, sourcesLine)
  await writeFile(join(aptRoot, "etc", "apt", "apt.conf.d", "99depsolve"), confdText)
  // Empty dpkg status = fresh rootfs (mkosi installs into a new rootfs).
  await writeFile(statusFile, "")
}

/** Do the cached lists hold any indices (anything but lock/ and partial/)? */
async function hasIndices() {
  const entries = await readdir(listsDir).catch(() => [])
  return entries.some((entry) => entry !== "lock" && entry !== "partial")
}

/**
 * Extract the "Reached two conflicting assignments" block: everything from
 * the trigger line up to (excluding) the "returned non-zero" line or a "‣"
 * marker. Package names are collected in order of appearance, :arch
 * stripped, deduped — the first one that is in the explicitly-requested list
 * is the drop candidate (handles both the direct and the transitive shape).
 */
function parseConflictBlock(lines) {
  const start = lines.findIndex((line) => line.includes("Reached two conflicting assignments"))
  if (start < 0) return null
  const block = [lines[start]]
  for (let i = start + 1; i < lines.length; i++) {
    const line = lines[i]
    if (line.includes("returned non-zero") || line.startsWith("‣")) break
    block.push(line)
  }
  const evidence = block.map((line) => line.replace(/^\s*E:\s*/, "").trim()).filter(Boolean)
  const candidates = []
  for (const line of block) {
    for (const match of line.matchAll(/[a-z0-9][a-z0-9+.-]*(?::[a-z][a-z0-9-]*)?(?=[=<> ]|$)/g)) {
      const name = match[0].replace(/:.*/, "")
      if (!candidates.includes(name)) candidates.push(name)
    }
  }
  return { evidence, candidates }
}

/**
 * Categorize one failed simulate. missing and conflict are mutually
 * exclusive (missing names abort the solve before any conflict is reached);
 * anything else lands in unresolved for manual inspection.
 */
function analyze(result) {
  const text = result.stderr.trim() ? result.stderr : result.stdout
  const lines = text.split("\n")
  const missing = []
  for (const line of lines) {
    const match = line.match(/^E: Unable to locate package ([a-z0-9][a-z0-9+.-]*)/i)
      || line.match(/^E: Package '([^']+)' has no installation candidate/)
    if (match && !missing.some((finding) => finding.name === match[1])) {
      missing.push({ name: match[1], evidence: [line.trim()] })
    }
  }
  const conflict = parseConflictBlock(lines)
  const errorLines = lines.filter((line) => /^\s*E:/.test(line)).map((line) => line.trim())
  const unresolved = missing.length || conflict ? null : { evidence: errorLines.length ? errorLines : [text.trim()] }
  return { missing, conflict, unresolved }
}

/** The first conflict-block candidate that is an explicitly-requested package. */
function requestedCandidate(conflict, requestedSet) {
  return conflict?.candidates.find((name) => requestedSet.has(name))
}

/** One-line findings summary, e.g. "2 missing, conflict". */
function findingsSummary(findings) {
  const parts = []
  if (findings.missing.length) parts.push(`${findings.missing.length} missing`)
  if (findings.conflict) parts.push("conflict")
  if (findings.unresolved) parts.push("unresolved")
  return parts.join(", ") || "apt failed"
}

/** Narrate one drop with its evidence block. */
function narrateDrop(drop) {
  const advice = drop.kind === "missing"
    ? "MISSING — rename in vars/pkgs.yaml, do not just delete"
    : "CONFLICT — drop or replace in vars/pkgs.yaml"
  note(`round ${drop.round}: drop ${drop.name} (${advice})`)
  for (const line of drop.evidence.slice(0, 12)) console.error(`      ${line}`)
}

async function main() {
  const { values, positionals } = parsed(process.argv.slice(2), {
    conf: { type: "string" },
    suite: { type: "string" },
    components: { type: "string" },
    arch: { type: "string" },
    mirror: { type: "string" },
    proxy: { type: "string" },
    fix: { type: "boolean" },
    protect: { type: "string", multiple: true },
    json: { type: "boolean" },
    "no-update": { type: "boolean" },
    timeout: { type: "string" },
    help: { type: "boolean", short: "h" },
  })
  if (values.help) return console.log(HELP)
  const started = Date.now()
  const fix = !!values.fix
  const json = !!values.json
  const timeoutSetting = Number(setting(values, "timeout") || 600)
  if (!Number.isInteger(timeoutSetting) || timeoutSetting < 10) fail(`invalid --timeout (want integer seconds >= 10)`)
  const timeoutMs = timeoutSetting * 1000

  // --- conf graph: [Distribution] defaults come from the main conf, with the
  // target subimage conf overriding; packages come from the target conf.
  const mainConf = await parseConfIfExists(join(root, "etc", "mkosi.conf"))
  const confFlag = setting(values, "conf")
  const targetPath = confFlag ? (isAbsolute(confFlag) ? confFlag : join(root, confFlag)) : join(root, DEFAULT_CONF)
  const targetConf = await parseConfIfExists(targetPath)
  if (confFlag && !targetConf) fail(`--conf does not exist: ${targetPath}`)

  // --- package input: positionals, then piped stdin, then the conf. An EMPTY
  // pipe (CI, </dev/null) counts as no stdin data and falls through to conf.
  let source
  let input = null
  if (positionals.length) {
    source = "argv"
    input = positionals.join(" ")
  } else if (!process.stdin.isTTY) {
    source = "stdin"
    input = ""
    for await (const chunk of process.stdin) input += chunk
    if (!input.trim()) {
      input = null
      source = "conf"
    }
  } else {
    source = "conf"
  }
  let packages = input !== null ? splitList(input) : confPackages(targetConf)
  packages = canonicalize(packages)
  if (!packages.length) {
    fail(input !== null
      ? "no packages given on argv/stdin"
      : `no [Content] Packages= found in ${targetPath} (and it must exist; pass --conf, packages, or pipe a list)`)
  }
  const fromText = source === "conf"
    ? `from ${targetPath.startsWith(root) ? targetPath.slice(root.length + 1) : targetPath}`
    : `from ${source}`

  // --- distribution-derived defaults
  const dist = distributionDefaults(mainConf, targetConf)
  const suite = setting(values, "suite") || dist.get("Release") || DEFAULT_SUITE
  const components = splitList(setting(values, "components") || dist.get("Repositories") || DEFAULT_COMPONENTS)
  const distro = dist.get("Distribution") || "debian"
  const arch = mappedArch(setting(values, "arch") || dist.get("Architecture") || hostArch())
  const mirrorBase = (setting(values, "mirror") || dist.get("Mirror") || DEFAULT_MIRROR).replace(/\/+$/, "")
  // mkosi joins "/debian" onto the mirror base itself; do the same here.
  const suiteUri = /\/(debian|ubuntu)$/.test(mirrorBase) ? mirrorBase : distro === "debian" ? `${mirrorBase}/debian` : mirrorBase
  const proxy = values.proxy !== undefined ? values.proxy : process.env.DEPSOLVE_PROXY !== undefined ? process.env.DEPSOLVE_PROXY : DEFAULT_PROXY
  const protectedSet = new Set([
    ...PROTECTED,
    ...setting(values, "protect", { list: true }).flatMap((item) => item.split(",")).map((item) => item.trim()).filter(Boolean),
  ])

  // --- scratch apt root
  const sourcesLine = `deb [trusted=yes] ${suiteUri} ${suite} ${components.join(" ")}\n`
  const confdText = [
    ...(proxy ? [`Acquire::http::Proxy "${proxy}";`, `Acquire::https::Proxy "${proxy}";`] : []),
    `APT::Architecture "${arch}";`,
    `APT::Architectures {"${arch}";};`,
    "",
  ].join("\n")
  await prepareAptRoot(sourcesLine, confdText)

  note(`${packages.length} packages ${fromText} (suite ${suite}, ${arch}, ${components.join("+")}, ${proxy ? `via ${proxy}` : "no proxy"})`)
  if (values["no-update"] && await hasIndices()) {
    note(`using cached indices at ${listsDir}`)
  } else {
    if (values["no-update"]) note("--no-update given but no cached indices; running update anyway")
    const updateStart = Date.now()
    const update = await aptRun(["-o", `Dir=${aptRoot}`, "update"], timeoutMs)
    if (update.status !== 0) {
      fail(`apt-get update failed (is the proxy up? --proxy "" disables):\n${(update.stderr || update.stdout).trim()}`)
    }
    note(`apt-get update ok (${((Date.now() - updateStart) / 1000).toFixed(1)}s)`)
  }

  // --- solve loop
  const requestedSet = new Set(packages)
  let current = [...packages]
  const drops = []
  let manual = null
  let clean = false
  let findings = { missing: [], conflict: null, unresolved: null }
  let round = 0
  while (round < MAX_ROUNDS) {
    round++
    const simulate = await aptRun(
      [...aptBaseArgs(), "-o", "APT::Install-Recommends=false", "-o", "APT::Get::Allow-Remove-Essential=true", "-s", "install", ...current],
      timeoutMs,
    )
    if (simulate.status === 0) {
      clean = true
      break
    }
    findings = analyze(simulate)

    if (findings.missing.length) {
      const requestedMissing = findings.missing.filter((finding) => requestedSet.has(finding.name))
      const transitive = findings.missing.filter((finding) => !requestedSet.has(finding.name))
      const blocked = requestedMissing.find((finding) => protectedSet.has(finding.name))
      if (blocked) {
        manual = { reason: `missing package ${blocked.name} is protected — fix its name in vars/pkgs.yaml`, evidence: blocked.evidence }
        break
      }
      if (!fix) break
      for (const finding of requestedMissing) {
        const drop = { name: finding.name, kind: "missing", round, evidence: finding.evidence }
        drops.push(drop)
        current = current.filter((name) => name !== finding.name)
        narrateDrop(drop)
      }
      if (transitive.length) {
        manual = { reason: `missing transitive dependency ${transitive.map((f) => f.name).join(", ")} — manual`, evidence: transitive.flatMap((f) => f.evidence) }
        break
      }
      continue
    }

    if (findings.conflict) {
      const candidate = requestedCandidate(findings.conflict, requestedSet)
      if (!fix) break
      if (!candidate) {
        manual = { reason: "conflict block names no explicitly-requested package (transitive conflict) — manual", evidence: findings.conflict.evidence }
        break
      }
      if (protectedSet.has(candidate)) {
        manual = { reason: `conflict names protected ${candidate} — manual`, evidence: findings.conflict.evidence }
        break
      }
      const drop = { name: candidate, kind: "conflict", round, evidence: findings.conflict.evidence }
      drops.push(drop)
      current = current.filter((name) => name !== candidate)
      narrateDrop(drop)
      continue
    }

    manual = { reason: "apt failed in an unrecognized shape — manual", evidence: findings.unresolved?.evidence || ["(no E: lines captured)"] }
    break
  }
  if (!clean && !manual) {
    // Verify mode stops at the first findings (reported below); only a loop
    // that exhausted MAX_ROUNDS without resolving is a convergence failure.
    manual = round >= MAX_ROUNDS
      ? { reason: `no convergence after ${MAX_ROUNDS} rounds`, evidence: [] }
      : { reason: `verify found ${findingsSummary(findings)}`, evidence: [] }
  }

  // --- report
  const durationMs = Date.now() - started
  const missingDrops = drops.filter((drop) => drop.kind === "missing").length
  const conflictDrops = drops.length - missingDrops
  if (!fix && !clean) {
    for (const finding of findings.missing) {
      console.error(`  missing ${finding.name}: ${finding.evidence[0]}`)
      console.error(`    fix: RENAME in vars/pkgs.yaml (stale name from an older suite)`)
    }
    if (findings.conflict) {
      const candidate = requestedCandidate(findings.conflict, requestedSet)
      const verdict = !candidate
        ? "no explicitly-requested package in the block — manual"
        : protectedSet.has(candidate)
          ? `recommend dropping ${candidate}, but it is PROTECTED — manual`
          : `recommend dropping ${candidate}`
      console.error(`  conflict (${verdict}; DROP or REPLACE in vars/pkgs.yaml):`)
      for (const line of findings.conflict.evidence.slice(0, 12)) console.error(`    ${line}`)
    }
    if (findings.unresolved) {
      console.error("  unresolved — manual:")
      for (const line of findings.unresolved.evidence.slice(0, 12)) console.error(`    ${line}`)
    }
  }
  if (clean && !drops.length) {
    note(`clean: apt can install all ${current.length} packages (${suite} ${arch}; ${(durationMs / 1000).toFixed(1)}s total)`)
  } else if (clean) {
    note(`converged: ${packages.length} -> ${current.length} packages after ${round} rounds (${missingDrops} missing -> RENAME, ${conflictDrops} conflict -> DROP) in ${(durationMs / 1000).toFixed(1)}s`)
  } else {
    note(`not clean after ${round} rounds: ${manual?.reason}`)
    for (const line of (manual?.evidence || []).slice(0, 12)) console.error(`    ${line}`)
  }
  if (json) {
    console.log(JSON.stringify({
      tool: "depsolve",
      conf: targetPath.startsWith(root) ? targetPath.slice(root.length + 1) : targetPath,
      source: source || "conf",
      suite,
      components,
      arch,
      mirror: mirrorBase,
      proxy: proxy || null,
      aptRoot,
      requested: packages.length,
      finalCount: current.length,
      clean,
      fix,
      rounds: round,
      drops,
      findings,
      manual,
      durationMs,
    }, null, 2))
  } else if (fix) {
    for (const name of current) console.log(name)
  }
  process.exitCode = clean ? 0 : 1
}

main().catch((error) => {
  if (error instanceof CliError) {
    console.error(`depsolve: error: ${error.message}`)
    process.exitCode = 2
  } else {
    console.error(error)
    process.exitCode = 1
  }
})
