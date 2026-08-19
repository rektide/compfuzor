# global deploy, user service — does the hybrid mode exist?

## what's up

`watchman.srv.pb` deploys fully USERMODE (everything under `~/.local`), because
watchman is inherently per-user (state keyed by username, per-user inotify).
The ask: deploy artifacts once to a global place (`/srv/watchman-main`), but
install a **user** service for the invoking user — "anyone should be able to
use this playbook... set up a user service for the user, from this global
place." Constraint: **no per-user templating of config into place** — absolute
per-user paths baked at deploy time are exactly the muck to avoid. "It is
better to do nothing than go hard on that."

## verdict up front

**The mode exists today and is proven in production — by opencode.** It is
`SYSTEMD_INSTALL: user` on a system-scope playbook + literal `%h` specifiers
in the unit + `scope: user` BINS for per-user activation. Zero per-user file
generation: all per-user-ness rides on systemd's `%h` expansion at unit-load
time, and `$HOME` expansion at shell-source time. What does *not* work is
`SYSTEMD_INSTALL: separate` (half-implemented, empirically broken — see
below).

## what exists

- `SYSTEMD_INSTALL: user|both|separate` gates per-scope install scripts
  (`vars/systemd.yaml:32-39`). `user` yields `install-service-<type>-user.sh`
  with `UNIT_DIR=${HOME}/.config/systemd/user`, `SYSTEMCTL="systemctl --user"`,
  `SUDO_CMD=""` (`tasks/compfuzor/vars_systemd_unit.tasks:294-313`).
- Proven deploys: `opencode.src.pb` (system DIR `/usr/local/src/opencode-git`,
  user unit linked into `~/.config/systemd/user/`), `atuin.src.pb`,
  `mise.opt.pb`.
- `scope: user` BINS auto-compose into `install-user.sh` — per-user activation
  without root. `watchman.srv.pb` already uses this (`install-cli-symlink.sh`,
  which is inherently per-user via `$(id -un)`).
- `%h` already in use: opencode's deployed unit has `WorkingDirectory=%h`.

## specifier semantics (verified empirically, systemd 257 user manager)

| location | `%h` expansion | note |
|---|---|---|
| `ExecStart` args | ✅ | `--statefile=%h/...` works for CLI flags |
| `Environment=` | ✅ | per-user vars expressible in-unit |
| `EnvironmentFile=` *path* | ✅ | global file path is fine |
| `EnvironmentFile=` *contents* | ❌ `$HOME` stays literal | env-export files cannot carry per-user paths |
| `ExecStartPre` | ✅ | same as ExecStart |

So the two expansion worlds: systemd expands `%h` in directives; POSIX
shells expand `$HOME` when *sourcing* env files. A static global env file
with `$HOME/...` literals works for shells, fails for systemd — per-user
vars must live in `Environment=` lines, not the env file.

## what's broken / missing

1. **`separate` mode is inert-aspirational.** It merges `{'USERMODE': True}`
   into `UNIT_VARS` (`vars_systemd_unit.tasks:58`), but playbook-level vars
   like `rclone.srv.pb`'s `target: "{{ '%h' if USERMODE|def else '' }}/mnt/%i"`
   resolve in playbook context where USERMODE is falsy. Empirical: the
   deployed `rclone-main-user@.service` has `/mnt/%i'` — no `%h`, plus a
   stray quote from the broken render — and `WantedBy=multi-user.target`
   (system-scope default; should be `default.target`). The author's own
   comment ("AH! This is the gotcha") marks the unfinished seam.
2. **No user-relative path vocabulary.** `VAR`/`ETC` are frozen strings from
   `vars_hierarchy.tasks` `set_fact`; `USERMODE` flips them wholesale
   (`vars/common.user.yaml`). There is no way to say "this path is per-user
   at unit-load time" (`%h/...`) — authors hand-write `%h` and bypass
   `{{VAR}}`, as opencode and rclone both do.
3. **env.export / ENV / ZIM_ENV carry absolute `{{VAR}}` values** — under the
   hybrid these would be either system paths or the deploying user's home.
   The shell side (zim module, sourced per-user) wants `$HOME` literals; the
   systemd side wants `Environment=` with `%h`. Two consumers, incompatible
   expansion — no vocabulary for the split today.
4. **User-bin namespace collisions.** `install-cli-symlink.sh` exists in both
   opencode's and watchman's user bins; watchman's `install-user.sh` was
   observed (2026-08-19) resolving the *opencode* copy via a `~/.local/bin`
   PATH lookup. Same-named user bins across playbooks collide.

## watchman on the hybrid — sketch (no templating)

- Drop `USERMODE`; keep `.srv` → `DIR=/srv/watchman-main`, deployed once with
  sudo (bin/, etc/, unit template).
- `SYSTEMD_INSTALL: user` → per-user activation is
  `/srv/watchman-main/bin/install-user.sh`, no sudo (unit link + enable --now
  + CLI-routing symlink, both already per-user).
- Unit paths: `--statefile=%h/.local/var/lib/watchman-main/state` (etc.) in
  `ExecStart`; `takeover.sh` computes paths from `${HOME}` at runtime (user
  services have `HOME` set in the manager env, systemd ≥ 248).
- Guard config `watchman.json` stays global (`{{ETC}}`) — it is
  user-agnostic; `WATCHMAN_CONFIG_FILE=/srv/.../etc/watchman.json` absolute
  is correct for every user.
- `WATCHMAN_SOCK` per-user: `Environment="WATCHMAN_SOCK=%h/.local/var/lib/..."`
  in the unit (NOT the env file); shell clients get the `$HOME` literal via
  the zim module (per-user already).
- What stays per-user on disk: only `~/.local/var/lib/watchman-main/` (state,
  sock, pid, log) and the `<user>-state` CLI symlink.

## user-path-variable precedent (already loaded, both)

Two existing families do dual-scope paths, both always loaded:

- `USERMODE_*_DIR` (`vars/common.yaml:28-42`): `USERMODE_SRVS_DIR`,
  `USERMODE_VARS_DIR`, `USERMODE_ETCS_DIR`, ... defined unconditionally
  alongside the system dirs; `vars/common.user.yaml` flips the base names
  onto them under USERMODE. Load mechanics are include_defaults-only-sets-
  undefined (`tasks/compfuzor/vars_base.tasks:3-13`), so playbook vars win
  and both families always coexist.
- systemd scope family (`vars/systemd.yaml:56-65`): `SYSTEMD_SYSTEM_UNIT_DIR`
  and `SYSTEMD_USER_UNIT_DIR` (+CONF/PRESET dirs, from pkg-config) defined
  side by side; the scope selector `SYSTEMD_UNIT_DIR: lookup('vars',
  'SYSTEMD_'+SYSTEMD_SCOPE|upper+'_UNIT_DIR')` (`vars/systemd.yaml:5`) picks
  at use. The cleanest dual-scope pattern in the repo.

Crucial distinction: both precedents hold absolute paths **resolved for the
deploying actor** (USERMODE_VARS_DIR → `/home/rektide/.local/var/lib`) —
correct for full-USERMODE where deployer == service user, wrong for the
global hybrid where any user activates later. The missing family member is
the runtime-per-user variant below.

## systemic improvements (if compfuzor wants to "handle it well")

- A user-relative path vocabulary following the existing parallel-family
  shape: e.g. `VARS_USER_DIR: "%h/.local/var/lib"` (specifier-valued, NOT
  resolved-home-valued) alongside `USERMODE_VARS_DIR`, consumed by unit
  generation when emitting user-scope units in system deploys — static
  strings, expansion stays systemd's job. This is the minimal fix that
  makes `separate`'s original bifurcation intent real without any per-user
  templating.
- Or: deprecate `separate` in favor of explicit dual specs
  (`SYSTEMD_SERVICES` vs `SYSTEMD_SERVICES_USER`) and fix the user-scope
  `[Install]` defaults.
- Namespace user-scope bins (`watchman/install-cli-symlink.sh`) or resolve
  them `$DIR`-relative to kill cross-playbook collisions.

## cross-references

- [`/watchman.srv.pb`](/watchman.srv.pb) — current USERMODE deploy this
  rethinks; header documents the CLI-routing symlink rationale that carries
  over unchanged.
- [`/rclone.srv.pb`](/rclone.srv.pb) — the `separate`-mode guinea pig; its
  inline comment documents the same seam this doc externalizes.
- [`/opencode.src.pb`](/opencode.src.pb) — the working hybrid precedent
  (system DIR, `SYSTEMD_INSTALL: user`, `%h` in unit).
- [`/vars/common.user.yaml`](/vars/common.user.yaml) — wholesale USERMODE
  dir flip; the all-or-nothing semantics the hybrid needs to break up.
- [`/tasks/compfuzor/vars_systemd_unit.tasks`](/tasks/compfuzor/vars_systemd_unit.tasks)
  — install-spec generation incl. the inert `USERMODE` merge at line 58.
- [`.design/opencode/service.md`](/doc/../.design/opencode/service.md) —
  linger discussion (user services surviving logout), prerequisite for the
  hybrid's activation model.

# addendum: the fsh lookup plugin exists now

The "missing vocabulary" gap above is closed by
[`library/lookup_plugins/fsh.py`](/library/lookup_plugins/fsh.py):

- `lookup('fsh', 'var')` — deploy-mode base (follows the USERMODE flip).
- `lookup('fsh', 'var', user=True)` — USERMODE family, resolved for the
  deploying user.
- `USER_FSH` top-level var (or the reserved `_fsh_user` that unit
  generation sets for user-scope `separate` iterations) flips the source to
  the `%h`/`%t` specifier family — exactly the "flips the source if set"
  semantics. `USER_FSH_DIRS` overrides the table per-kind.
- `name=True` appends `NAME`, preferring frozen hierarchy vars (`VAR`,
  `ETC`, ...) — the "implicit vars" integration.

One SYSTEMD_SERVICES block now bifurcates correctly under
`SYSTEMD_INSTALL: separate` (verified end-to-end: system unit renders
absolute deploy paths, user unit renders `%h/.local/...` and `%t/...`),
which un-breaks the rclone-style pattern and gives the watchman hybrid its
path vocabulary. The remaining known gaps from the assessment: user-bin
namespacing (cross-playbook `install-cli-symlink.sh` collisions) and the
user-scope `[Install]` default (`WantedBy=multi-user.target` should be
`default.target` under user scope).
