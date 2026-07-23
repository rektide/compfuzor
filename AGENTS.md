# compfuzor — running playbooks locally

Compfuzor playbooks are Ansible playbooks (`.pb`). Each describes one
subsystem: it generates config files, scripts, and (optionally) systemd units
under a per-subsystem dir, then optionally installs/enables them.

## Invoking a playbook locally

Playbooks target `- hosts: all`. With no inventory Ansible SSHes to
`localhost` and fails (`Permission denied (publickey,password)`). Always pass
the **local connector**:

```
ansible-playbook -i 'localhost,' -c local <name>.pb
```

Syntax-check without running (no connector needed):

```
ansible-playbook <name>.pb --syntax-check
```

## sudo / become

Many subsystems escalate via `become` (package install, writes to
`/etc/modules-load.d`, linking into `/etc/systemd/system`, …). Runs need
passwordless sudo — check first:

```
sudo -n true && echo ok
```

If unavailable, pass bypass flags (below) to skip the become-needing subsystems
and iterate without side effects.

## Bypass flags

Every subsystem is gated by a `<NAME>_BYPASS` flag (default false). Pass any as
`-e <NAME>_BYPASS=True` to skip it for that run.

| Flag | Skips |
|---|---|
| `PKGS_BYPASS` | apt package install |
| `APT_BYPASS` | apt repo configuration |
| `MODULES_BYPASS` | `/etc/modules-load.d` kernel module loading |
| `SYSTEMD_INSTALL_BYPASS` | systemd unit-file + install-script generation |
| `SYSTEMD_THUNK_BYPASS` | systemd enable/restart (the thunk) |
| `SYSTEMD_BYPASS` | **thunk only** — does NOT skip unit generation |
| `BINS_BYPASS` / `BINS_RUN_BYPASS` | bin generation / running bins |
| `DIR_BYPASS` / `FS_BYPASS` | directory + file creation |
| `LINKS_BYPASS` | symlinks into system dirs |
| `ENV_BYPASS` | env file emission |
| `REPO_BYPASS` / `GIT_BYPASS` | source checkout |
| `DEBCONF_BYPASS` / `DBCONFIG_BYPASS` | debconf / dbconfig |
| `USERMODE=True` | user scope (user systemd, `~/.config`, no sudo) |

Common "iterate without side effects" incantation:

```
ansible-playbook -i 'localhost,' -c local <name>.pb \
  -e PKGS_BYPASS=True -e APT_BYPASS=True -e MODULES_BYPASS=True \
  -e SYSTEMD_THUNK_BYPASS=True
```

## Where output lands

Per-subsystem dir, by default `/etc/opt/<NAME>/` (`DIR`):

- `bin/` — generated scripts (installers, builders, status reporters)
- `etc/` — generated config files (symlink to the dir itself)
- `env`, `env.export` — environment
- `README.md` — rendered from the playbook's `README` var

Apply generated work manually via the compositor:

```
sudo /etc/opt/<NAME>/bin/install.sh
```

## install.sh / build.sh do NOT run automatically

By design, `bins_run.tasks` only runs bins carrying `run`/`exec`/`become`/`args`
(see `tasks/compfuzor/bins_run.tasks`). The action compositors `install.sh` and
`build.sh` exist for **manual** invocation — they orchestrate the `install-*.sh`
/ `build-*.sh` leaf scripts.

Consequence: a playbook declaring `SYSTEMD_SERVICE` generates a unit file and an
`install-service.sh`, but does **not** auto-install the unit into
`/etc/systemd/system/`. Run `sudo bin/install.sh` (or `sudo bin/install-service.sh`)
to link + enable it. Symptom pattern: a generated script that has no effect →
check whether it carries a run flag.

## systemd, in detail

- Unit generation is data-driven via section dicts — `SYSTEMD_UNITS` (`[Unit]`),
  `SYSTEMD_SERVICES` (`[Service]`), `SYSTEMD_INSTALLS` (`[Install]`) — merged
  over defaults in [`vars/systemd.yaml`](vars/systemd.yaml). See
  [`skill/systemd.md`](skill/systemd.md).
- `SYSTEMD_SERVICE: True` names the unit after `NAME`; a string overrides it.
- To **fully opt out** of systemd for a playbook:
  `SYSTEMD_INSTALL_BYPASS: True` + `SYSTEMD_THUNK_BYPASS: True`.
- `SYSTEMD_BYPASS` alone is **not** a full opt-out — it skips only the thunk,
  not unit-file generation. (Known doc/code mismatch vs `skill/systemd.md`.)
- The `SYSTEMD_EXEC` / `SYSTEMD_TYPE` shorthand documented in `skill/systemd.md`
  is **not wired** into the current `files/systemd.unit` template — use the
  `SYSTEMD_SERVICES` dict (`Type`, `ExecStart`, …) directly.
