---
type: Design
title: rimworld two-automount stack — decisions from the init0 discussion
description: System dwarfs only, two auto-composing system automounts, XDG state root, no services or cleanup; init0 menu resolved
tags: [compfuzor, dwarfs, jc141, games, systemd]
status: draft
generated: { by: agent:glm53, at: 2026-09-23 }
sources:
  - id: init0
    resource: file:///home/rektide/src/compfuzor/design/jc141-dwarfs/init0.glm53.md
    title: init0 breakdown & menu
---

# rimworld two-automount stack — decisions from the init0 discussion

## What changed since init0

The [init0](init0.glm53.md) menu was discussed and resolved. The deployed
design is now **two system automounts, auto-composing; nothing else**:

```
/mnt/dwarfs/rimworld   ro dwarfs layer   (mnt-dwarfs-rimworld.{mount,automount})
/mnt/rimworld          rw overlay        (mnt-rimworld.{mount,automount},
                                          lower=/mnt/dwarfs/rimworld,
                                          upper/work under STATE_DIR)
```

`ls /mnt/rimworld` → overlay automount fires → mount.fuse-overlayfs helper
runs → opens lowerdir → dwarfs automount fires → system dwarfs mounts the
image. Idle → overlay unmounts; the ro layer follows on its own idle.
No cleanup logic, no service, no launcher bin: **idle timeouts are the
cleanup**, and Lutris is the launcher (points at
`/mnt/rimworld/start_RimWorld.sh`).

## Decisions

| Question | Decision |
|---|---|
| bundled `files/dwarfs-binary` | **dropped** — system dwarfs only ([dwarfs.src.pb](/dwarfs.src.pb) rebuilt, boost pins unversioned, `/usr/sbin/mount.dwarfs` bridged since mount(8) doesn't search `/usr/local/sbin`) |
| overlay as service | **dropped** — Type=fuse-overlayfs `.mount` via a new [fuse-overlayfs.etc.pb](/fuse-overlayfs.etc.pb) mount helper (Debian ships none) |
| automounts user-scope? | **impossible** — mount/automount units are system-manager-only; the split is: system owns the mounts, userland owns consumption (Lutris, saves-HOME later, gamescope later) |
| mountpoints | `/mnt/rimworld` merged (game-facing), `/mnt/dwarfs/rimworld` ro (implementation detail) |
| state | one per-game portable root `STATE_DIR` (own var, not game_dir), default `~/.local/share/rimworld` (XDG data home): `overlay/{upper,work}` now, a fake game `$HOME` (jc141 native-docs) later |
| config (init0 row E) | yes — compfuzor `ENV`/`ETC_FILES`; nothing ported from `~/.jc141rc` |
| bwrap/net sandbox | approved in principle, **not built** — matters little under Lutris |
| extract/compress (init0 row B) | not built; bundled multiplexer no longer referenced — would use system `dwarfsextract`/`mkdwarfs` if wanted |

## Deployed shape

- [`rimworld.opt.pb`](/rimworld.opt.pb) — four units via SYSTEMD_ROOTS (two
  `.mount` link-only + two `.automount` enabled), `DIRS` for state,
  parameterized `where`/`ro_where`/`state_dir`/`idle`/`cachesize`.
- [`fuse-overlayfs.etc.pb`](/fuse-overlayfs.etc.pb) — `/usr/sbin/mount.fuse-overlayfs`
  helper: drops the mount(8) source positional (FUSE has none), mkdirs
  upper/work (`.mount` units cannot ExecStartPre), execs the binary.
- [`dwarfs.src.pb`](/dwarfs.src.pb) — rebuilt v0.15.3+358; LINKS the helper
  into `/usr/sbin`.

Validated: single-`ls` composition, write-through as the user landing in
`~/.local/share/rimworld/overlay/upper`, clean teardown via automount stop,
torrent dir left pristine (image only).

## Gotchas hit (and fixed)

- **helper protocol**: mount(8) calls `mount.fuse-overlayfs <source> <dir>
  -o <opts>`; the first version of the parser dropped *both* positionals
  (`if [ -z "$mp" ]` never flips on the first arg) → "failed to access
  mountpoint :". Fixed with an explicit `src_seen` flag. libmount also
  injects `rw`/`lazytime` into opts — fuse-overlayfs warns and ignores.
- **CIFS archive corruption**: the dwarfs checkout on `//nanomachine/bitblaster`
  had a missing blob + a Sep 17 `core.symlinks=false` typechange artifact,
  which made every fetch refuse and made stash/checkout actively dangerous
  (symlink loops, phantom dentries, mode-600 rewrites). Resolved by
  exporting the (content-identical-to-upstream) local edit to
  `~/tmp-opencode/dwarfs-dockerfile-edit.patch` and re-cloning fresh.
  Watch for repeat performances from this share.

## Open

## Addendum: the empty-first-mount race (2026-09-29)

Six days of real use surfaced it: `/mnt/rimworld` mounted successfully but
showed an **empty** view. Journal correlation showed the overlay
mounting at 18:08:29 while the dwarfs layer only mounted at 18:08:35 —
`Requires=<ro>.automount` only guarantees the autofs trigger is *armed*;
nothing ordered the actual dwarfs *mount* before the overlay helper ran.
fuse-overlayfs scanned the untriggered (empty) lowerdir and built its
inode table on it — it never re-scans, so the view stays empty until
remounted ("i restarted it huh now it worked").

Fix: `Requires=<ro>.mount` + `After=<ro>.mount` on the overlay mount —
systemd mounts the dwarfs layer first, on demand, then runs the overlay
helper against a populated lowerdir. Dependencies between .mount units
are ordinary unit machinery (what fstab's `x-systemd.requires-mounts-for=`
generates); the automount stays for direct access and idle reaping.
Journal now shows dwarfs `Mounted` strictly before overlay `Mounting`,
content on first access, cold-verified.

## Open (updated)

- The saves fake-`$HOME` (STATE_DIR/home) is reserved but unbuilt — it
  belongs to the sandbox/launcher layer, which now likely belongs to Lutris
  config rather than compfuzor.
- 10min idle both layers; tune via `-e idle=`.
- init0's generic per-game playbook question stands, now parameterized by
  `where`/`ro_where`/`state_dir`/`game_dir` — a second jc141 game would tell
  us if the var set is right.
