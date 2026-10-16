---
type: Report
title: Archive build-artifact cleanup completed and verified
description: Deleted the three leftover build-artifact trees from the archive era — workers-sdk node_modules (3m13s), workers-sdk .turbo (~1s), LACT target (5s) — each behind per-tree ignore/untracked git checks and per-round live-reference checks; mount turned out to be NFSv4 rather than CIFS, no retries were needed, and the only unmeasured quantity is node_modules' exact byte delta (session began with df -h granularity only).
resource: /design/archive-workspace/cleanup0.glm53fx.md
tags: [compfuzor, archive, cleanup, nfs, workers-sdk, wrangler, lact, node_modules, turbo, cargo-target, build-artifacts]
status: draft
generated: { by: model:glm5.3-flash-max, at: 2026-10-16 }
verified: { by: model:glm5.3-flash-max, at: 2026-10-16 }
sources:
  - id: commissioning
    resource: opencode://ses_eba42c532ffeGDFn343ysNvjcd
    title: Commissioning session: archive build cleanup
  - id: authoring-session
    resource: opencode://ses_eb9afc114ffeT9JqVRuBj0aXJT
    title: Ran the per-tree pre-checked deletions, re-verified references after each tree, and authored this report
  - id: cleanup-log
    resource: /tmp/opencode/archive-cleanup.log
    title: Full command log of this cleanup — every pre-check, deletion, verification, and df reading, timestamped
  - id: workers-sdk-archive
    resource: /mnt/bitblaster/archive/cloudflare/workers-sdk
    title: cloudflare/workers-sdk archive repository (git check-ignore / ls-files evidence; .git and .jj untouched)
  - id: lact-archive
    resource: /mnt/bitblaster/archive/ilya-zlobintsev/LACT
    title: ilya-zlobintsev/LACT archive repository (target/ removed; .git and .jj untouched)
---

# Archive build-artifact cleanup completed and verified

All three commissioned build-artifact trees were deleted from the bitblaster
archive on 2026-10-16, one at a time, each behind fresh ignore/untracked git
checks and live-reference checks. No check failed, no deletion needed a retry,
and nothing outside the three paths was touched. Dolt's archive was not
opened for writes (its stale `go/dolt` residue was already handled earlier).

## Result

| Tree | Outcome | Duration | Freed |
|---|---|---|---|
| `cloudflare/workers-sdk/node_modules/` | deleted, rc=0 | 3m13s | not individually measured (see Space) |
| `cloudflare/workers-sdk/.turbo/` | deleted, rc=0 | ~1s | 447,488 KiB (437 MiB) |
| `ilya-zlobintsev/LACT/target/` | deleted, rc=0 | 5s | 6,144 KiB (6.0 MiB) |

Wall clock: session start 20:05:17Z, final verification 20:12:08Z (**6m51s**
total; deletions themselves 20:07:54Z–20:11:57Z, **4m03s**). All commands are
logged verbatim with timestamps in `/tmp/opencode/archive-cleanup.log`.

## Pre-checks per tree

Run before each deletion; re-run after each. Full evidence in the log.

**Ignored, not tracked (from each archive root):**

- workers-sdk, 20:07:19Z: `git check-ignore -q node_modules` OK,
  `check-ignore -q .turbo` OK; `git ls-files --error-unmatch` failed for both
  (untracked); `git status --porcelain -- node_modules .turbo` empty; repo
  toplevel confirmed as the archive root. `.turbo` re-checked 20:11:32Z
  immediately before its deletion.
- LACT, 20:08:22Z and re-checked 20:11:45Z: `target` ignored OK, untracked OK.

**No live references (re-verified before and after every tree):**

- `/usr/local/bin/lact` → `/usr/local/src/lact-git/repo/target/release/lact`
  (readlink -f canonicalizes through `/usr/local/src/lact-git` — a real local
  workspace, not a symlink into the archive).
- `~/.local/share/pnpm/wrangler` launcher → `pnpm/bin/wrangler` shim →
  `pnpm/global/v11/21657a-…/node_modules/wrangler` → symlink (created today
  18:12) → **`/usr/local/src/wrangler-git/repo/packages/wrangler`**. The live
  chain is fully local.
- `/proc/[0-9]*/exe` readlink sweep: zero processes running from bitblaster,
  every round.
- Process scan (`wrangler|workerd|esbuild|lact`): none (an initial pgrep hit
  was my own shell's command line; a filtered `ps` pass confirmed clean).
- Services: `mk-wed` and `lact-git` both `inactive`, every round.
- Symlink sweep of `/usr/local/bin` and `~/.local/share/pnpm` (unrestricted,
  hidden included) with full target resolution: **no symlink resolves into any
  of the three deleted trees** (explicit intersection check: zero hits).

## Deletion log summary

| Tree | Start (UTC) | End (UTC) | rc |
|---|---|---|---|
| node_modules | 20:07:54 | 20:11:07 | 0 |
| .turbo | 20:11:35 | 20:11:36 | 0 |
| LACT target | 20:11:52 | 20:11:57 | 0 |

Each ran as `rm -rf -- <exact path>`, strictly sequential (no parallel
deletions). After each: parent `ls` confirmed the path gone (sibling `.git`,
`.jj`, and all tracked files intact in both archives), reference checks
re-run clean, `df` re-read. No CIFS-style partway failures; the single-attempt
retry provision was never needed.

## Space before/after

- Before (session start, `df -h`): 8.0T size, **3.6T used**, 4.5T avail, 45%.
- Exact readings (KiB, `df --output=used,avail -k`) were captured per tree
  from `.turbo` onward:
  - before `.turbo`: used 3,805,679,616
  - after `.turbo`: used 3,805,232,128 (−447,488 KiB)
  - after LACT target: used 3,805,225,984 (−6,144 KiB)
- After (final, `df -h`): 3.6T used, 4.5T avail, 45% — the freed bytes sit
  below `df -h`'s 0.1T rounding at this volume.

**Measurement gap:** the session began with only `df -h` granularity, so
node_modules' exact byte delta was not captured (an exact baseline taken just
before `.turbo` is already post-node_modules). Its 3m13s deletion is the only
recorded measure; measured freed space across the other two trees is
453,632 KiB (443 MiB). Lesson applied in-session: capture exact `df -k` before
touching anything (done for trees 2–3).

## Anything skipped or failed

Nothing skipped; nothing failed. Anomalies and observations worth keeping:

- **The mount is NFSv4.2, not CIFS.** `/mnt/bitblaster` is
  `nanomachine.lan:/mnt/bitblaster` (nfs4, nconnect=3); the Samba export lives
  behind the `smb-`-prefixed paths (a separate autofs at `/mnt/smb-bitblaster`
  also exists). The commissioning's "CIFS — SLOW" premise is stale — it
  reflects the pre-`7ba998ca` naming. Consequence: the three deletions took
  minutes, not the budgeted 30+.
- **Stale legacy-store symlinks still aim into the workers-sdk archive:**
  `~/.local/share/pnpm/global/5/node_modules/wrangler` → archive
  `packages/wrangler`, and `~/.local/share/pnpm/store/v10/projects/01b09ef…`
  → the archive root (plus similar v10 project-registry links into the
  cdk8s/remix/opentui/use.gpu/rookery/cloudflare-os archives). These are
  superseded remnants of the pre-repoint layouts; none resolve into a deleted
  tree, and they were left untouched (out of scope) — but they are harmless
  dangling-ish candidates for a future deliberate pnpm-store tidy.
- **Other archives still serve live binaries:** `/usr/local/bin/jj`,
  `jujutsu`, `wasmtime`, `bottom`, `jacquard`, `goat`, `tracey`, `tpm-ahiru`,
  `folly`, `termctrl` symlink into their (non-deleted) archives. "The archive
  is dead weight" holds only for build artifacts; the archive remains the
  backing store for several deployed binaries.
- **No standalone LACT conversion report exists** under
  `design/archive-workspace/` — LACT's conversion is attested by the wrangler
  report's status line ("all three deployments are converted (lact ✓,
  wrangler ✓, dolt pending)") and the live local `/usr/local/bin/lact` chain.

## Cross-references

- [Wrangler archive→workspace conversion report](/design/archive-workspace/wrangler-conversion0.glm53fx.md) —
  recorded that "archive node_modules/build-directory cleanup is deferred
  until all three deployments are converted"; this report completes that
  deferral, and its shim-repoint work is what makes the live wrangler chain
  local.
- [Dolt archive→workspace conversion report](/design/archive-workspace/dolt-conversion0.glm53fx.md) —
  the third deployment's conversion (dolt's archive was verified to have zero
  untracked residue before this cleanup began; it was not touched here).
- [Dolt archive dirty-state assessment](/design/archive-workspace/dolt-archive-state0.glm53fx.md) —
  the forensic baseline behind "dolt's archive has zero untracked residue".
- [Conversion mechanics waves](/design/archive-workspace/conversion0.gpt6luna.md) and
  [no-copy restoration](/design/archive-workspace/conversion1.gpt6luna.md) —
  the tested jj workspace mechanics all three conversions (including LACT's)
  followed.
