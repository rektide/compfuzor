---
type: Design
title: the sandbox built — run.sh, runner-not-wrapper, and two porting bugs
description: init0-C/init1's "approved in principle" bwrap sandbox delivered as bin/run.sh in rimworld.opt.pb; decisions and validation evidence
tags: [compfuzor, dwarfs, jc141, games, bwrap, sandbox]
status: draft
generated: { by: agent:glm53, at: 2026-10-05 }
sources:
  - id: init0
    resource: file:///home/rektide/src/compfuzor/design/jc141-dwarfs/init0.glm53.md
    title: init0 breakdown & menu (item C: sandbox runner)
  - id: init1
    resource: file:///home/rektide/src/compfuzor/design/jc141-dwarfs/init1.glm53.md
    title: init1 decisions ("bwrap: approved in principle, not built")
  - id: actions
    resource: file:///mnt/bitblaster/torrent/RimWorld-jc141/actions.sh
    title: jc141 wrapper (bwrap-run_in_sandbox, start.n.sh composition)
---

# The sandbox built — run.sh, runner-not-wrapper, and two porting bugs

## What changed since init1

init1's decision row said the bwrap/net sandbox was "approved in principle,
**not built** — matters little under Lutris". [Lutris itself has no bwrap
support](https://github.com/lutris/lutris/issues/4755) (open FRs since 2022;
nothing in the 0.5.22 launch path), so if the sandbox was going to exist, it
had to be ours. It now does: [`rimworld.opt.pb`](/rimworld.opt.pb) grew a
`bin/run.sh` (deployed `/opt/rimworld-main/bin/run.sh`) — the launcher
entrypoint Lutris points at.

## What run.sh is

A port of jc141's `start.n.sh` + `actions.sh bwrap-run_in_sandbox` (native
branch) onto the automount stack, faithful on sandbox shape:

- `--ro-bind / / --dev-bind-try /dev /dev --bind-try /tmp /tmp` — porous by
  design (init0's tension, deliberately kept open; tightening is a separate
  decision)
- fake `$HOME`: `$STATE_DIR/home` bound over `$HOME` (jc141's native-docs),
  resolving init1's "reserved but unbuilt" STATE_DIR/home row
- `--unshare-net` by default (`BLOCK_NET=0` opts out), `ISOLATE=0` skips
  bwrap entirely — jc141's two knobs, ported as caller-env overrides rather
  than playbook vars (env.export owns paths; prefs stay runtime)
- Xauthority hardlink dance for X11, with a guard jc141 lacks (below)
- game dir bound rw **last** + `--chdir`, jc141's ordering

Two departures, both user-directed:

1. **Runner, not wrapper**: run.sh execs `RimWorldLinux` itself (with the
   stock `start_RimWorld.sh`'s semantics inlined — `LC_ALL=C`, exec-bit
   guard). The release's start script is dead weight we don't delegate to;
   we are the runner. Args pass through; `GAME_BIN` env-overridable.
2. **README over comments**: usage/knobs/notes live in the deployed
   `README.md` (compfuzor `README:` var), not in script comment blocks —
   consumers of `/opt/rimworld-main` see the docs, the script stays lean.

Plus one addition: a `run.sh -- CMD` seam running an arbitrary command
inside the sandbox instead of the game, which is how everything below was
validated without a display.

## The automount arming problem

autofs does not fire inside bwrap's mount namespace, so the overlay must be
up *before* the sandbox starts. run.sh arms it with the sanctioned
path-access trigger (no sudo, no services — consistent with init1's
"nothing else" posture), verified via findmnt before proceeding.

## Two porting bugs worth remembering

- **findmnt FSTYPE is `fuse.fuse-overlayfs`**, not `fuse-overlayfs` — an
  equality check on the latter loops to timeout while the mount is actually
  fine. Match with a glob (`*fuse-overlayfs`). Same trap presumably applies
  to dwarfs (`fuse.dwarfs`).
- **Stale host `XAUTHORITY`**: the env var can point at a nonexistent file
  (observed in an SSH session). jc141's bare `ln` under our strict-shell
  wrapper turns that into a hard failure; the dance now guards on the
  source existing and falls back ln → cp (cross-device).

## Validation evidence

`run.sh -- sh -c ...` inside the sandbox: `/opt` read-only (ro-bind proof),
game dir writable (rw overlay bind), `$HOME` writable at the bound path,
DNS lookup blocked (`--unshare-net`) and unblocked with `BLOCK_NET=0`; a
`$HOME` marker landed in `$STATE_DIR/home`, absent from the real home.
End-to-end: `run.sh -- ./RimWorldLinux -batchmode -nographics -quit` boots
Unity fully inside the sandbox (Mono/PhysX from `/mnt/rimworld`), and
player data lands in
`$STATE_DIR/home/.config/unity3d/Ludeon Studios/RimWorld by Ludeon Studios`
— the real `~/.config/unity3d` has no Ludeon dir. A pulse cookie in the
fake home confirms PipeWire audio works through the sandbox. Not yet
graphically tested (no display from the agent session); Lutris should
point at `/opt/rimworld-main/bin/run.sh`.

## Open

- Graphical run from the real session (wayland/Xwayland + gamepad) — user
  validation pending.
- Sandbox tightening (init0's porous-vs-tight tension) still open, now
  cheap to explore since the runner owns the bwrap flags.
- gamescope composition (init0-D) would wrap outside bwrap in run.sh,
  driven by env, when wanted.
- Second jc141 game still the test for parameterizing
  `where`/`ro_where`/`state_dir`/`game_dir`/`GAME_BIN` into a shared type.

## Cross-references

- [`init0.glm53.md`](init0.glm53.md) — menu item C (sandbox runner) and the
  porousness tension
- [`init1.glm53.md`](init1.glm53.md) — the "not built" decision this
  closes out; STATE_DIR/home reservation honored
- [`/rimworld.opt.pb`](/rimworld.opt.pb) — the delivered playbook
- Lutris sandbox FRs: [#4556](https://github.com/lutris/lutris/issues/4556),
  [#4755](https://github.com/lutris/lutris/issues/4755)
