---
type: Design
title: zimfw plugin generator per playbook
description: Re-assess compfuzor's zimfw offerings and design a good per-pb plugin generator; evaluate zimfw for mise.
resource: https://github.com/rektide/compfuzor/blob/main/.design/zim-generator/init0.gpt56.md
tags: [zim, zsh, compfuzor, generator]
status: draft
generated: { by: agent:gpt56, at: 2026-08-17 }
verified: { by: unverified }
stale_after: 2026-11-01
sources:
  - id: gen-zim-tasks
    resource: https://github.com/rektide/compfuzor/blob/main/tasks/compfuzor/gen_zim.tasks
    title: gen_zim.tasks contributor/host synthesis
  - id: zim-fragment-filter
    resource: https://github.com/rektide/compfuzor/blob/main/library/filter_plugins/zim_fragment.py
    title: zim_fragment filter (env/file/git kinds, phases)
  - id: zim-host-pb
    resource: https://github.com/rektide/compfuzor/blob/main/zim.opt.pb
    title: zim host playbook (assembly, install bridge)
  - id: joke-zim-mise
    resource: https://github.com/joke/zim-mise
    title: joke/zim-mise module (cached activate + hook-env + completions)
---

# zimfw plugin generator per playbook — init0

## What's up

Two threads landed together:

1. **bins under zsh** (`tasks/compfuzor/bins_run.tasks`): BINS now run via
   `/bin/zsh` (`BINS_SHELL`), which sources `~/.zshenv` non-interactively.
   mise.opt.pb ships a `mise activate zsh --shims` zshenv block so ansible-run
   bins see mise-managed tools. This created a **non-interactive channel**
   that did not exist before.
2. **git.etc.pb revamp**: converted from a dangling
   SHARE_FILES + install-user.sh symlink route to `ZIM_MODULES` (one env
   module + three local file modules). It exercised the whole contributor
   path with zero bespoke install code — the shape we want every pb to be
   able to trivially declare.

The direction: **every pb that has shell-facing surface (functions, aliases,
env exports, completions, wrappers) should declare a zimfw plugin cheaply,
and compfuzor should generate everything else.** Open questions: what the
generator should offer, and whether mise itself should move into zimfw.

## Current offerings (inventory)

Contributor side — a pb declares `ZIM_MODULES` (or `ZIM_MODULE`) and nothing
else; `gen_zim.tasks` + the `zim_fragment` filter render:

| kind | trigger | renders |
|---|---|---|
| `env` | `env:` mapping | generated `init.zsh` exporting each var with a don't-stomp guard (`COMPFUZOR_ENV_OVERWRITE` forces); no source |
| `file` | `source: foo.zsh` or `file: true` | `files/<TYPE>/foo.zsh` copied to `ETC/zim-modules/foo/init.zsh`; declaration is `zmodule <abspath>` (zimfw loads it as an installed module) |
| `git` | `source: <repo>` | `zmodule <repo-slug>` for zimfw to clone |

Per-entry knobs: `phase` (core 20 / prompt 40 / tools 55 / completion 70 /
late 85, or 00–99), `name`, `description` (filename slug suffix),
`args` (raw `zmodule` args, e.g. `--fpath src`), `comment` (rendered into the
fragment), `enabled: false` (→ `zim-disabled/`, still installed but inert).

Auto-generated per contributor: `install-user-zimfw.sh` which delegates to
the zim host (`/opt/zim-main`, `ZIM_HOST_DIR` overridable). The host
(`zim.opt.pb`) symlinks fragments into `zimfw.conf.d`, reassembles
`zimfw.conf` in sorted order, and owns the `.zshrc` zim bootstrap block +
`status.sh` drift detection.

Customers today: `zim.opt.pb` (host), `opencode.src.pb` (env + file),
`watchman.srv.pb` (env), `git.etc.pb` (env + 3 file).

Delivery channels that exist alongside zim:

| channel | audience | mechanism |
|---|---|---|
| zim module | interactive zsh | `ZIM_MODULES` fragments |
| `~/.zshenv` block | every zsh incl. `zsh -c`, ansible BINS | block-in-file (mise.zshenv today) |
| `env.export` | BINS scripts, `EnvironmentFile=` | ENV/ENV_LIST |
| `SYSTEMD_ENV` | systemd user manager | vars_systemd_env.tasks |
| `mise-systemd-env.sh` | systemd user manager | `mise env -J` → `systemctl --user set-environment` |

## Evaluation: mise via zimfw?

zim-mise (joke/zim-mise, already enabled at `core` phase in zim.opt.pb as
rektide's checkout) is good at the **interactive** job: cached
`mise activate zsh` + `hook-env` + zcompiled completions, regenerating on
binary mtime. It cannot cover:

- non-interactive zsh (`zsh -c`, ansible BINS, ssh one-liners) — zim loads
  from `.zshrc`, which non-interactive shells never source;
- bash, systemd user services, cron — no zim at all.

So the answer is **channels, not either/or**: keep the zshenv shims block as
the universal floor (what we just built), let zim-mise own interactive
prompt hooks, keep `mise-systemd-env.sh` for the user manager. The
remaining mise work is only de-duplication: the `mise.zshrc` block-in-file
add duplicates zim-mise on zim boxes (known TODO in mise.opt.pb — detect
zim-mise and skip, or drop the zshrc block on hosts that run the zim stack).

## Gaps for "a good generator"

1. **No shorthand kinds.** Everything must be a raw `.zsh` file or an env
   map. Cheap wins: `aliases:` and `functions:` mappings rendered into a
   generated `init.zsh` — most pbs need only these.
2. **Completions are manual.** A local module that ships `_*` completions
   must pass `--fpath` args and lay files out by hand. The generator could
   accept `completions:` and wire `fpath` + `zcompile` itself.
3. **Single-channel delivery.** The env module reaches interactive shells
   only. The mise work shows the real shape: one declaration, fanned out to
   the channels it names (zim / zshenv / systemd env / env.export). Today
   each channel is hand-rolled per pb (mise.opt.pb is ~200 lines of exactly
   this).
4. **No standalone preview.** No `zim-gen.sh` to render fragments without
   running the playbook (useful for review and for the wave docs).
5. **Host discovery is hardcoded** (`/opt/zim-main`, acknowledged TODO in
   gen_zim.tasks:60).
6. **No per-module status/drift.** Host-level `status.sh` exists; a
   contributor can't cheaply check "are my fragments promoted?".
7. **Legacy cleanup is bespoke** (git.etc.pb's cleanup-old-install.sh) —
   there's no `zim:` channel equivalent of `BINS_ABSENT` for retiring old
   delivery routes.

## Candidate directions

- **A. `zim:` declarative kinds** — extend `zim_fragment` with
  `aliases`/`functions`/`completions` shorthand kinds (pure filter work,
  no host changes).
- **B. channels fan-out** — a `CHANNELS` concept in the zim entry
  (`zshenv: true`, `systemd_env: true`, …) that generates the zshenv block,
  SYSTEMD_ENV wiring, etc. from one declaration. Biggest payoff, most
  design surface.
- **C. generator bin** — `zim-gen.sh <pb>` renders and prints fragments +
  assembled `zimfw.conf` diff for review (thin wrapper around existing
  filters).
- **D. host registry** — resolve the host location via a well-known
  symlink or ZIM_HOST marks instead of the hardcoded path.

## Research prompt

"Survey `zmodule` flags and zimfw module-loading semantics (fpath, source
files, root, on-pull) against compfuzor's `zim_fragment` rendering, and the
existing env-delivery channels (zshenv, env.export, systemd user manager);
identify the minimal declaration surface a playbook needs to ship
shell-facing functionality to each channel."

## Cross-references

- [`/mise.opt.pb`](/mise.opt.pb) — zshenv shim block + mise-systemd-env.sh;
  the multi-channel case study.
- [`/zim.opt.pb`](/zim.opt.pb) — host assembly, phase bands, module roster
  (zim-mise at `core`).
- [`/git.etc.pb`](/git.etc.pb) — first all-generator contributor (env + file
  kinds, no bespoke install).
- [`/tasks/compfuzor/bins_run.tasks`](/tasks/compfuzor/bins_run.tasks) —
  BINS_SHELL/zshenv non-interactive channel.
- [`/doc/subsys.md`](/doc/subsys.md) — subsystem evaluation contract the
  generator plugs into.
