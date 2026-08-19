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

## systemic improvements (if compfuzor wants to "handle it well")

- A user-relative path vocabulary: e.g. `VAR_USER: "%h/.local/var/lib/{{NAME}}"`
  / `ETC_USER: ...`, emitted when generating user-scope units in system
  deploys — static strings, expansion stays systemd's job. This is the
  minimal fix that makes `separate`'s original bifurcation intent real
  without any per-user templating.
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
