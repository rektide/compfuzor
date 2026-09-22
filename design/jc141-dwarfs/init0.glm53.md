---
type: Design
title: jc141 dwarfs game stack breakdown & playbook menu
description: What the jc141 wrapper does, what compfuzor now owns (automount), and a pick-and-choose menu for DIYing the rest
tags: [compfuzor, dwarfs, jc141, games, systemd]
status: draft
generated: { by: agent:glm53, at: 2026-09-22 }
sources:
  - id: rimworld-jc141
    resource: file:///mnt/bitblaster/torrent/RimWorld-jc141/actions.sh
    title: jc141 RimWorld release wrapper (actions.sh + start.n.sh)
  - id: dwarfs-doc
    resource: file:///usr/local/src/dwarfs-git/repo/doc/dwarfs.md
    title: DwarFS docs (fstab helper, overlay-on-dwarfs patterns)
---

# jc141 dwarfs game stack breakdown & playbook menu

## What's up

The RimWorld release at `/mnt/bitblaster/torrent/RimWorld-jc141` is a jc141-style
repack: the game tree is compressed into `files/game-root.dwarfs` (DwarFS
image, 456M), a bundled static `files/dwarfs-binary` (v0.14.1 multiplexer:
`--tool=dwarfs|mkdwarfs|dwarfsextract|dwarfsck`, also argv0-dispatched) mounts
it, and `start.n.sh` + `actions.sh` wrap the whole play session: mount, sandbox,
gamescope, run, unmount.

The goal here is not to run their wrapper but to **break it down and pick and
choose**, DIYing our own copy in compfuzor. The first slice — a systemd
automount for the dwarf — is done and deployed ([`/rimworld.opt.pb`](/rimworld.opt.pb)).

Also discovered along the way: the compfuzor-managed dwarfs install
([`/dwarfs.src.pb`](/dwarfs.src.pb)) is currently broken — `/usr/local/bin/dwarfs`
dangles into a cleaned build dir and the copied `dwarfsextract`/`mkdwarfs` bins
can't load `libboost_chrono.so.1.83` (Debian moved past boost 1.83). The jc141
bundled binary is self-sufficient, so nothing blocks on that fix, but the
playbook's helper deliberately points at the bundled binary (pinned to the
image's format) rather than any system dwarfs.

## What the jc141 wrapper actually does

`actions.sh` (261 lines) + `start.n.sh` (57 lines) decompose into six concerns:

### 1. Dwarfs lifecycle (`dwarfs-mount/-unmount/-extract/-compress`)

- **mount**: two-layer FUSE stack —
  `dwarfs image files/.game-root-mnt` (ro, `cachesize=25%RAM`, `clone_fd`,
  `tidy_strategy=time,tidy_interval=15m,tidy_max_age=30m`) then
  `fuse-overlayfs` (`squash_to_uid/gid=<user>`, lower=`.game-root-mnt`,
  upper=`files/overlay-storage`, work=`files/.game-root-work`) onto
  `files/game-root`. The rw overlay is where mods and updates land.
- **unmount**: `fuser -k` both layers, `fusermount3 -u -z`, delete the
  transient mnt/work dirs and an empty game-root.
- **extract**: `dwarfsextract` to a plain tree (the `EXTRACT=1` no-FUSE path).
- **compress**: `mkdwarfs -l7 -B26 -S26 --order=nilsimsa --set-owner=1000 ...`
  back into an image (repack after modding).
- Bailout if `game-root` is non-empty ("already mounted or extracted").

### 2. Config system (`~/.jc141rc` + `script_default_settings`)

Global config sourced first, per-game overrides (all commented out) second;
auto-generated on first run. Keys: `UNMOUNT`, `EXTRACT`, `TERMINAL_OUTPUT`,
`SYSWINE`, `ISOLATE`, `BLOCK_NET`, `JC_DIRECTORY` (sandbox home + wine prefix
root), `GAMESCOPE` + resolution/flag set. This is a hand-rolled two-layer
env-file config — exactly what compfuzor's `ENV`/`ETC_FILES` already do.

### 3. Sandbox (`bwrap-run_in_sandbox`)

`bwrap --ro-bind / / --dev-bind /dev --bind-try /tmp` + per-type extras:
native games get `$JC_DIRECTORY/native-docs` bound as `$HOME` (saves/configs
stay out of the game tree), wine games get `$WINEPREFIX` bound; `BLOCK_NET`
adds `--unshare-net`; finally `--bind $PWD` (the game dir). Also an
`.Xauthority` symlink dance for X.

### 4. Gamescope composition (`gamescope-run_embedded`)

`-f`/`-b`, screen/game resolutions, `ADDITIONAL_FLAGS` (e.g.
`--force-grab-cursor`), wrapping the whole run.

### 5. Wine plumbing (not exercised by this native release)

`wine-initiate_prefix` (`wineboot -i`, fixup `$WINEPREFIX/drive_c/users`
symlinks, `wineserver -w`), `wine-setup_external_vulkan` (bundled vulkan
tarball). The `start.e-w.sh`/`start.n-w.sh` family variants use these.

### 6. Session lifecycle (`start.n.sh`)

Create sandbox home → (optionally) silence output → mount or extract → trap
`jc141-cleanup` (unmount on exit) → build the command array
(gamescope? bwrap? game) → run. Plus dependency checks (`fuse-overlayfs`,
`fuser`) and a Matrix support banner.

## What's already replaced: the automount

[`rimworld.opt.pb`](/rimworld.opt.pb) (deployed at `/opt/rimworld-main`) maps
concern 1's *mount/unmount* onto systemd, with lifecycle in concern 6's place:

| jc141 | compfuzor |
|---|---|
| `dwarfs-mount` at launch | `.automount` (10min idle) + `.mount` (Type=dwarfs) on `files/.game-root-mnt`, dispatched via `/usr/sbin/mount.dwarfs` → `bin/mount.dwarfs` wrapper → bundled `dwarfs-binary` |
| fuse-overlayfs stack at launch | `rimworld-overlay.service` (oneshot, RemainAfterExit; `Requires=` the automount; `squash_to_uid/gid`; ExecStop = `fusermount3 -u`) |
| `UNMOUNT=1` exit trap | `bin/run.sh`: `systemctl start` → game → `systemctl stop`; ro layer follows on idle timeout |
| dep checks | `PKGS: [fuse3, fuse-overlayfs]` |
| `chmod +x dwarfs-binary` at every run | playbook task (the systemd helper path has no such step — this bit us once) |

Validated end-to-end: lazy mount on access, write-through to
`files/overlay-storage` as the user, clean teardown, idle unmount. En route this
also fixed a compfuzor gap: systemd-escaped installer filenames
(`install-automount-mnt-...-RimWorld\x2djc141-....sh`) fell out of the
`bin_composers` regex, so mount/automount units silently never installed —
fixed in `library/filter_plugins/bin_composers.py`.

The stock jc141 wrapper still works standalone (its "already mounted" bailout
triggers our automount), but mixing the two is not a goal — don't run
`start.n.sh` while our units are active.

## Pick-and-choose menu for the rest

Candidates, roughly in value order:

### A. Generic jc141/dwarfs game playbook (recommended next)

`rimworld.opt.pb` is one game away from a pattern: parameterize `game_dir`,
the in-image start script, and the unit names, and each new repack is one
`.pb` (or one `-e game_dir=...` run) instead of a copy. Natural shape: a
shared `jc141` type dir under compfuzor with per-game INSTANCEs, or a
`dwarfs-game.etc.pb` in the `cifs.etc.pb` style (one deployment per image).
Covers: mount/automount/overlay/run.sh + `DESKTOP` entries for the launcher
(the `desktop` subsystem already exists).

### B. Dwarfs extract/compress bins (small, self-contained)

`dwarfsextract` / `mkdwarfs` wrappers as playbook bins — the `EXTRACT=1`
fallback and the post-mod repack path. The bundled multiplexer already
supports both (`--tool=`), so these are thin. Worth having before modding
RimWorld in earnest; also the natural place to write `dwarfs-tree` listings.

### C. Sandbox runner (bwrap) — reusable beyond games

jc141's sandbox is game-specific only in its `$HOME` choice; the core
(`--ro-bind / /`, dev/tmp binds, `--unshare-net`, workdir bind last) is a
generic "run untrusted thing contained" bin. A `sandbox-run` bin/playbook
with HOME/net/workdir knobs would serve jc141 games and general untrusted
exec. Tension: jc141's sandbox is quite porous (binds all of `/` ro, keeps
`/tmp` shared); decide whether compfuzor's version keeps that compatibility
or tightens.

### D. Gamescope runner (composition knob, not a playbook)

The gamescope flags are launcher composition — it belongs in run.sh (or a
`gamescope-run` bin next to it), driven by `ENV` vars, not in a separate
playbook. `gamescope.src.pb` already builds the binary. Keep the jc141
semantics (fullscreen default, resolution splits, extra flags).

### E. Config layers → ENV/ETC_FILES (fold into A)

The `~/.jc141rc`/`script_default_settings` two-layer config maps directly to
compfuzor's `ENV` (deployed `env.export`) plus per-game `ETC_FILES`. Nothing
new needed — just don't port the sourcing machinery.

### F. Wine plumbing (defer)

`start.*-w.sh` releases (prefix bootstrap, vulkan setup, `SYSWINE` selection)
are a whole subsystem with its own lifecycle; only worth touching when a wine
jc141 game actually shows up. Note the interplay: wine prefix under
`JC_DIRECTORY` + bwrap `--bind $WINEPREFIX` + our automount stack would all
compose at the run.sh layer.

## Tensions / open questions

- **Overlay state in the torrent dir**: jc141 keeps `overlay-storage` inside
  the release dir; so do we (compat + self-containment). But it mutates the
  torrent tree (re-seed/re-check friction). Alternative: upper/work under
  `/opt/rimworld-main/var` with only the image in the torrent dir — one-line
  change to the playbook, but diverges from the stock wrapper's expectations.
- **sudo in run.sh**: starting/stopping the system overlay unit uses sudo
  (passwordless here). Alternatives: a polkit rule for the unit, or a
  user-scope overlay service (fuse-overlayfs mounts fine as a user; it even
  auto-triggers the *system* automount by touching lowerdir — ordering "just
  works" via access, no Requires needed). The user-scope variant removes sudo
  entirely and drops squash_to_uid; worth trying before calling A done.
- **cachesize rendered at playbook time**: jc141 computes 25% of RAM at every
  launch; we render it into the unit at playbook time. Fine until RAM changes;
  `-e cachesize=...` rerun is the answer. The tidy options make oversizing
  cheap anyway.
- **Broken `dwarfs.src.pb` install**: rebuild or retire? If retired, the
  playbook's mount.dwarfs wrapper already only needs the bundled binary.
- **Idle timeout vs play sessions**: 10min idle only reaps the ro layer when
  the overlay service is down (the overlay holds it busy — validated). If we
  later want the overlay itself lazy, that's autofs-on-a-service and probably
  not worth it.

## Cross-references

- [`/rimworld.opt.pb`](/rimworld.opt.pb) — the delivered automount playbook
- [`/cifs.etc.pb`](/cifs.etc.pb) — the `.mount`+`.automount` SYSTEMD_ROOTS
  pattern this follows
- [`/google-drive-ocamlfuse.mount.pb`](/google-drive-ocamlfuse.mount.pb) —
  user-scope FUSE service precedent (ExecStop=fusermount) for the sudoless
  variant
- [`/dwarfs.src.pb`](/dwarfs.src.pb) — (broken) system dwarfs install
- [`/wh40k-dow.opt.pb`](/wh40k-dow.opt.pb) — existing per-game opt playbook
- [`/skill/systemd.md`](/skill/systemd.md) — unit generation, SYSTEMD_ROOTS,
  socket-activation/link-only installs
- [`/doc/subsys.md`](/doc/subsys.md) — subsystem contract vocabulary
- DwarFS upstream doc: fstab `mount.dwarfs` helper + overlay-on-dwarfs
  patterns (`/usr/local/src/dwarfs-git/repo/doc/dwarfs.md`)
