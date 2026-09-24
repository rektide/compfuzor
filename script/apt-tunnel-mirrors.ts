#!/usr/bin/env -S node --strip-types
/**
 * apt-tunnel-mirrors.ts - maintain the `https_tunnel_allowed_mirrors` block
 * for the apt-cacher-rs proxy (apt-cacher-rs.src.pb).
 *
 * apt-cacher-rs (post-v0.8.0) is fail-closed on HTTPS CONNECT tunnels and
 * offers no bare `*` wildcard, so every tunnel target must be listed by
 * hand. This script regenerates the marked block from what this machine's
 * apt actually uses over https, so adding a repo needs no manual conf edit:
 *
 *   - /etc/apt/sources.list + sources.list.d/*.list (deb / deb-src lines)
 *   - sources.list.d/*.sources deb822 `URIs:` lines (all URIs, not just one)
 *   - the daemon journal (default, last 30d): hostnames clients actually
 *     CONNECTed to -- both accepted tunnels and ACL-refused targets. This
 *     catches DNS-canonicalized names apt sometimes sends instead of the
 *     sources-list name (mirrors.kernel.org -> mirrors.edge.kernel.org),
 *     and repos used by other LAN clients this host does not configure.
 *   - --cname: also add current DNS CNAME targets (best-effort; the journal
 *     is the reliable record, DNS answers rotate)
 *   - --extra <host>: manual additions, EXACT hostnames only. The tunnel
 *     list is matched by exact string compare at HEAD (connect_tunnel.rs),
 *     so wildcard entries like '*.debian.org' parse but never match -- do
 *     not use them here (they do work in `allowed_mirrors`, the cache path)
 *
 * Usage:
 *   script/apt-tunnel-mirrors.ts                # sync apt-cacher-rs.src.pb
 *   script/apt-tunnel-mirrors.ts --print        # discovery report only, no writes
 *   script/apt-tunnel-mirrors.ts --journal=false # ignore the daemon journal
 *   script/apt-tunnel-mirrors.ts --check        # exit 1 on drift, no writes
 *   script/apt-tunnel-mirrors.ts --file /etc/opt/apt-cacher-rs/apt-cacher-rs.conf
 *   script/apt-tunnel-mirrors.ts --extra '*.debian.org' --extra host.example.org
 *
 * After updating the playbook conf, re-render and reinstall as usual:
 *   ansible-playbook -i 'localhost,' -c local apt-cacher-rs.src.pb
 *   sudo bash <DIR>/bin/install.sh
 */

import { execFile } from "node:child_process";
import { resolveCname } from "node:dns/promises";
import { readFile, readdir, writeFile } from "node:fs/promises";
import { join } from "node:path";
import { parseArgs } from "node:util";
import { promisify } from "node:util";

const execFileP = promisify(execFile);

const BEGIN_MARK = "# BEGIN tunnel-mirrors";
const END_MARK = "# END tunnel-mirrors";
const MAX_LINE = 96;

const args = parseArgs({
  options: {
    file: {
      type: "string",
      default: join(import.meta.dirname, "..", "apt-cacher-rs.src.pb"),
    },
    sources: { type: "string", default: "/etc/apt" },
    journal: { type: "boolean", default: true },
    cname: { type: "boolean" },
    unit: { type: "string", multiple: true, default: ["apt-cacher-rs", "apt-cacher-rs-git"] },
    extra: { type: "string", multiple: true, default: [] },
    print: { type: "boolean" },
    check: { type: "boolean" },
  },
});

interface Found {
  host: string;
  origin: string;
}

const LABEL = /^[a-z0-9]([a-z0-9-]*[a-z0-9])?$/;

function isIPv4(host: string): boolean {
  if (!/^\d{1,3}(\.\d{1,3}){3}$/.test(host)) return false;
  return host.split(".").every((octet) => Number(octet) <= 255);
}

/** Mirrors upstream config.rs `is_valid_config_domain` for plain hosts
 *  (the tunnel list is exact-match, so wildcards are rejected up front). */
function isValidDomain(raw: string): boolean {
  const host = raw.toLowerCase();
  if (isIPv4(host)) return true;
  return host.split(".").every((label) => LABEL.test(label));
}

function hostFromUri(uri: string): string | null {
  if (!uri.startsWith("https://")) return null;
  try {
    return new URL(uri).hostname.toLowerCase();
  } catch {
    return null;
  }
}

/** one-line-format `deb [opts] uri suite...` and deb822 `URIs: a b c` */
async function fromSources(sourcesDir: string): Promise<Found[]> {
  const found: Found[] = [];
  const entries = new Set<string>([join(sourcesDir, "sources.list")]);
  try {
    for (const ent of await readdir(join(sourcesDir, "sources.list.d")))
      if (ent.endsWith(".list") || ent.endsWith(".sources"))
        entries.add(join(sourcesDir, "sources.list.d", ent));
  } catch {
    console.warn(`warn: no ${sourcesDir}/sources.list.d; parsing sources.list only`);
  }

  for (const path of entries) {
    let text: string;
    try {
      text = await readFile(path, "utf8");
    } catch {
      continue;
    }
    for (const rawLine of text.split("\n")) {
      const line = rawLine.trim();
      if (line.startsWith("URIs:")) {
        for (const uri of line.slice(5).trim().split(/\s+/)) {
          const host = hostFromUri(uri);
          if (host) found.push({ host, origin: path });
        }
      } else if (line.startsWith("deb") && !line.startsWith("#")) {
        const fields = line.split(/\s+/);
        if (fields[0] !== "deb" && fields[0] !== "deb-src") continue;
        // options bracket may span several fields: [ signed-by=x arch=amd64 ]
        let i = 1;
        if (fields[i]?.startsWith("[")) {
          while (i < fields.length && !fields[i]!.endsWith("]")) i++;
          i++;
        }
        const uri = fields[i];
        const host = uri ? hostFromUri(uri) : null;
        if (host) found.push({ host, origin: path });
      }
    }
  }
  return found;
}

/** accepted tunnels + ACL-refused targets from the daemon journal */
async function fromJournal(units: string[]): Promise<Found[]> {
  const found: Found[] = [];
  for (const unit of units) {
    try {
      const { stdout } = await execFileP("journalctl", [
        "-u",
        unit,
        "--no-pager",
        "-o",
        "cat",
        "--since",
        "-30d",
      ]);
      for (const line of stdout.split("\n")) {
        let m = line.match(/Using uncached tunnel for client .+ to (.+?):\d+/);
        if (m) {
          found.push({ host: m[1], origin: `journal:${unit}` });
          continue;
        }
        m = line.match(/due to disallowed host (\S+)/);
        if (m) found.push({ host: m[1], origin: `journal-refused:${unit}` });
      }
    } catch (err) {
      console.warn(`warn: journalctl -u ${unit} failed (${(err as Error).message}); skipping`);
    }
  }
  return found;
}

/** apt CONNECTs to the canonical name, so CNAME targets need listing too */
async function cnameTargets(host: string, depth = 2): Promise<string[]> {
  if (depth === 0) return [];
  let names: string[];
  try {
    names = await resolveCname(host);
  } catch {
    return [];
  }
  const out = [...names];
  for (const name of names) out.push(...(await cnameTargets(name, depth - 1)));
  return out;
}

function renderList(indent: string, hosts: string[]): string[] {
  const pad = indent + "  ";
  const lines: string[] = [];
  let cur = "";
  for (const host of hosts) {
    const item = `'${host}',`;
    if (!cur) {
      cur = pad + item;
    } else if (cur.length + 1 + item.length <= MAX_LINE) {
      cur += " " + item;
    } else {
      lines.push(cur);
      cur = pad + item;
    }
  }
  if (cur) lines.push(cur.replace(/,$/, ""));
  return [`${indent}https_tunnel_allowed_mirrors = [`, ...lines, `${indent}]`];
}

async function main(): Promise<number> {
  const found: Found[] = [];
  found.push(...(await fromSources(args.values.sources)));
  if (args.values.journal) found.push(...(await fromJournal(args.values.unit)));
  found.push(...args.values.extra.map((host) => ({ host, origin: "extra" })));

  const origins = new Map<string, Set<string>>();
  const hosts = new Set<string>();
  for (const { host, origin } of found) {
    if (host.includes("*")) {
      console.warn(
        `warn: skipping '${host}' (${origin}): the tunnel mirror list is exact-match, wildcards never match`,
      );
      continue;
    }
    if (!isValidDomain(host)) {
      console.warn(`warn: skipping invalid host '${host}' (${origin})`);
      continue;
    }
    hosts.add(host.toLowerCase());
    const set = origins.get(host.toLowerCase()) ?? new Set<string>();
    set.add(origin);
    origins.set(host.toLowerCase(), set);
  }

  if (args.values.cname) {
    const before = [...hosts];
    for (const host of before) {
      for (const cname of await cnameTargets(host)) {
        if (isValidDomain(cname) && !hosts.has(cname.toLowerCase())) {
          hosts.add(cname.toLowerCase());
          origins.set(cname.toLowerCase(), new Set([`cname of ${host}`]));
        }
      }
    }
  }
  const sorted = [...hosts].sort((a, b) => a.localeCompare(b));

  console.log(`discovered ${sorted.length} tunnel mirror hosts:`);
  for (const host of sorted)
    console.log(`  ${host}  [ ${[...origins.get(host)!].sort().join(", ")} ]`);

  if (args.values.print) {
    console.log("\n" + renderList("", sorted).join("\n"));
    return 0;
  }

  const file = args.values.file;
  let text: string;
  try {
    text = await readFile(file, "utf8");
  } catch (err) {
    console.error(`error: cannot read ${file}: ${(err as Error).message}`);
    return 1;
  }

  const lines = text.split("\n");
  const beginIdx = lines.findIndex((l) => l.trim().startsWith(BEGIN_MARK));
  if (beginIdx === -1) {
    console.error(
      `error: no '${BEGIN_MARK}' marker in ${file}. Add around the tunnel mirror list:\n` +
        `  ${BEGIN_MARK} (managed by script/apt-tunnel-mirrors.ts - do not edit)\n` +
        `  https_tunnel_allowed_mirrors = [ ... ]\n` +
        `  ${END_MARK}`,
    );
    return 1;
  }
  const endIdx = lines.findIndex((l, i) => i > beginIdx && l.trim().startsWith(END_MARK));
  if (endIdx === -1) {
    console.error(`error: '${BEGIN_MARK}' in ${file} has no matching '${END_MARK}'`);
    return 1;
  }

  const indent = lines[beginIdx]!.match(/^\s*/)![0];
  const oldHosts = [
    ...lines
      .slice(beginIdx + 1, endIdx)
      .join("\n")
      .matchAll(/'([^']+)'/g),
  ].map((m) => m[1]);
  const added = sorted.filter((h) => !oldHosts.includes(h));
  const removed = oldHosts.filter((h) => !sorted.includes(h));

  if (added.length === 0 && removed.length === 0) {
    console.log(`${file}: tunnel mirror list up to date (${sorted.length} hosts)`);
    return 0;
  }

  const summary = `+ [${added.join(", ")}] - [${removed.join(", ")}]`;
  if (args.values.check) {
    console.error(`${file}: tunnel mirror list drifts ${summary}`);
    return 1;
  }

  lines.splice(beginIdx + 1, endIdx - beginIdx - 1, ...renderList(indent, sorted));
  await writeFile(file, lines.join("\n"));
  console.log(`${file}: updated ${summary}`);
  return 0;
}

const code = await main();
process.exitCode = code;
