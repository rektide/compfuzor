---
type: Investigation
title: "Deployment env pollution into the opencode harness — where it is emitted, and how far it spreads"
description: "Forensic trackdown of the 'really bad pollution' the operator observed: compfuzor's env template bakes deployment-shaping variables (DIR/NAME/TYPE/INSTANCE/REPO/REPO_DIR/BUILD_DIR/GLOBAL_BINS_DIR) into every deployment's env file, and opencode.service loads that whole file via EnvironmentFile=, so every agent session, tool shell, playbook run, and materialized bin on the machine inherits another deployment's identity. Traces the full causal chain with live evidence, inventories the polluted variables (BINS is NOT among them), maps the blast radius (opencode.service, opencode-bus-proxy.service, atuin-daemon.service; NOT the systemd manager, NOT login shells, NOT cron), and lays out fix options only."
resource: /design/env-pollution/trackdown0.glm53fx.md
tags: [compfuzor, env, systemd, opencode, pollution, envdefault, build-lane, forensics]
status: draft
generated: { by: model:glm5.3-flash-max, at: 2026-10-16 }
sources:
  - id: commissioning
    resource: opencode://ses_eba42c532ffeGDFn343ysNvjcd
    title: Commissioning session: env pollution trackdown
  - id: authoring-session
    resource: opencode://ses_eb9f0f977ffea8BiPTpFSUHfe5
    title: Ran the live forensics (own environ, service cgroup, unit files, machinery sources), authored this report
  - id: incident-report
    resource: /design/archive-workspace/dolt-conversion0.glm53fx.md
    title: Dolt conversion report — the motivating incident and its build-lane assessment
  - id: build-lane-design
    resource: /design/build-lanes/modularization0.glm53max.md
    title: Build-lane modularization design (bin-side hardening counterpart; operator rulings recorded there)
  - id: env-template
    resource: /files/_env
    title: The env template that bakes deployment-shaping vars into every env/env.export (L33-42)
  - id: fs-env
    resource: /tasks/compfuzor/fs_env.tasks
    title: env/env.export emission task
  - id: unit-directive
    resource: /opencode.src.pb
    title: opencode.src.pb SYSTEMD_SERVICES EnvironmentFile declaration (L180-182)
  - id: systemd-defaults
    resource: /vars/systemd.yaml
    title: SYSTEMD_SERVICES_DEFAULT generic EnvironmentFile injection (L252-261)
  - id: unit-merge
    resource: /tasks/compfuzor/vars_systemd_unit.tasks
    title: defaults-then-declared recursive combine that renders unit sections (L106-136)
  - id: env-helper
    resource: /files/_helpers/env
    title: The bin env helper — inherited-$DIR deference and quiet envdefault sourcing (L7-9)
  - id: bin-renderer
    resource: /files/_bin
    title: Bin renderer — DEFAULT_HELPERS env floor (L19-25) and the deployment_rooted alternative (L26-31)
  - id: envdefault-tool
    resource: /usr/local/bin/envdefault
    title: envdefault implementation — only-unset contract (set vars are never overridden)
  - id: live-unit
    resource: /home/rektide/.config/systemd/user/opencode.service
    title: The deployed opencode.service unit (EnvironmentFile=-/usr/local/src/opencode-git/env)
  - id: live-env
    resource: /usr/local/src/opencode-git/env
    title: The deployed env file systemd actually loads (deployment-shaped, no export prefixes)
  - id: live-environ
    resource: "/proc/1783/environ"
    title: The running server's environment — all polluted variables observed at the source
  - id: own-environ
    resource: "/proc/self/environ (agent tool shell)"
    title: This investigation's own inherited environment — the pollution observed one hop from the server
  - id: vars-repo
    resource: /tasks/compfuzor/vars_repo.tasks
    title: REPO_DIR added into ENV (L7-13)
  - id: gen-links
    resource: /tasks/compfuzor/gen_links.tasks
    title: LINKS_JSON added into ENV/ENV_LIST (L35-36)
  - id: common-vars
    resource: /vars/common.yaml
    title: REPO_DIR/BUILD_DIR/GLOBAL_BINS_DIR defaults (L74-78), APT_INSTALL (L91), STATUS_DIRS env contributions (L814-815)
---

# Deployment env pollution into the opencode harness

## Result

**Verdict: the pollution is emitted by compfuzor's own env template and wired
into the service by the unit's `EnvironmentFile=` directive. It is not a
shell-rc, mise, or manager-environment problem.** `opencode.service` loads the
deployment's entire compfuzor env file, which by template design begins with
the deployment-shaping variables, so the server — and therefore every agent
session, tool shell, playbook run, and materialized bin it spawns — inherits
`DIR=/usr/local/src/opencode-git` and friends. `BINS` itself is **not**
exported (nor `BINS_DIR`); `GLOBAL_BINS_DIR` is.

The causal chain, link by link:

1. **Template bakes deployment identity into env files.**
   [files/_env](/files/_env) L33-42 unconditionally writes `DIR`, `NAME`,
   `TYPE`, `INSTANCE`, `REPO`, `BUILD_DIR`, `GLOBAL_BINS_DIR`, then every
   `ENV`/`ENV_PRIO` mapping key, then `COMPFUZOR_ENVS` (the joined key list)
   into *every* deployment's `env` and `env.export`. `REPO_DIR` enters the
   `ENV` mapping via [vars_repo.tasks L7-13](/tasks/compfuzor/vars_repo.tasks),
   `LINKS_JSON` via [gen_links.tasks L35-36](/tasks/compfuzor/gen_links.tasks),
   `APT_INSTALL`/`STATUS_DIRS*` from
   [vars/common.yaml](/vars/common.yaml) subsystems.
2. **fs_env renders both flavors.** [fs_env.tasks L2-21](/tasks/compfuzor/fs_env.tasks)
   templates `{{DIR}}/env` (systemd form, no `export` prefixes) and
   `{{DIR}}/env.export` (shell form) from that template — opencode has no
   `files/opencode/env` override, so both carry the deployment header.
3. **The unit loads the whole file.**
   [opencode.src.pb L180-182](/opencode.src.pb) declares
   `EnvironmentFile: ["-{{DIR}}/env", "{{ETC}}/env-credential"]`; the deployed
   unit renders `EnvironmentFile=-/usr/local/src/opencode-git/env`. The
   generic machinery would reach the same path even without the explicit line:
   [SYSTEMD_SERVICES_DEFAULT](/vars/systemd.yaml#L257) injects
   `EnvironmentFile: -{{DIR}}/env` for any playbook declaring `ENV`/`ENV_LIST`
   (that is the mechanism behind atuin-daemon's unit). The explicit declaration
   wins at [vars_systemd_unit.tasks L116-118](/tasks/compfuzor/vars_systemd_unit.tasks)
   (defaults enrich, declared replaces), but both spell out the same file.
4. **systemd loads it into the server's environ.** Verified live:
   `/proc/1783/environ` (the `opencode serve` MainPID) carries the full set.
5. **Every child inherits.** This investigation's own tool shell runs inside
   cgroup `app.slice/opencode.service` and its raw `/proc/$$/environ` carries
   the same variables before any zsh rc runs — one inherited hop from the
   server, not sourced.
6. **Bins trust the inherited identity.** The env helper baked into every
   materialized bin ([files/_helpers/env L7-9](/files/_helpers/env)) does
   `[ -z "$DIR" ] && export DIR="<own deployment>"` — deferring to an
   inherited `$DIR` — then sources `envdefault "$DIR/env.export" >/dev/null`.
   [envdefault](/usr/local/bin/envdefault) applies only variables *not already
   set*. So during the dolt build, `build-go.sh` resolved
   `DIR=/usr/local/src/opencode-git`, quietly sourced opencode's `env.export`
   (no `GO_TARGET`), and `${GO_TARGET:-./...}` fell back — the observed
   incident. Operator shells without an inherited `DIR` are unaffected.

The emission directive to change is therefore **unit-side** (which env file
the unit loads), and the content emitter is **`files/_env`'s deployment
header**. Fix options below; nothing was modified — this was read-only.

## Evidence

| # | Command | Observed |
|---|---|---|
| 1 | `env \| sort` and `cat /proc/$$/environ \| tr '\0' '\n' \| sort` (agent tool shell) | `DIR=/usr/local/src/opencode-git`, `NAME=opencode-git`, `TYPE=opencode`, `INSTANCE=git`, `REPO=https://github.com/anomalyco/opencode`, `REPO_DIR=…/opencode-git/repo`, `BUILD_DIR=…/opencode-git/repo/build`, `GLOBAL_BINS_DIR=/usr/local/bin`, `COMPFUZOR_ENVS=<23 keys>`, plus the `OPENCODE_*` runtime set. Raw environ identical → inherited, not rc-sourced. |
| 2 | `cat /proc/self/cgroup` | `0::/user.slice/user-1000.slice/user@1000.service/app.slice/opencode.service` — the tool shell lives inside the service cgroup. |
| 3 | `systemctl --user cat opencode.service`; `systemctl --user show opencode.service -p Environment -p EnvironmentFiles -p FragmentPath` | `EnvironmentFile=-/usr/local/src/opencode-git/env` + `EnvironmentFile=/etc/opt/opencode-git/env-credential`; `Environment=` lines only carry the motel OTEL pair (drop-in `opencode.service.d/motel.conf`); FragmentPath `~/.config/systemd/user/opencode.service`. No deployment vars ride `Environment=`. |
| 4 | `cat /usr/local/src/opencode-git/env` vs `env.export` | Same variable set; `env` in systemd form, `env.export` with `export` prefixes. **The unit loads `env`** — the correct flavor; the leak is the file's *content*, not the flavor choice. |
| 5 | `tr '\0' '\n' < /proc/1783/environ \| sort` | The server MainPID carries the full polluted set at the source. |
| 6 | `systemctl --user show-environment \| sort` | **Clean** — no `DIR`/`NAME`/`TYPE`. The systemd user manager is not polluted (opencode declares no `SYSTEMD_ENV`; the `vars_systemd_env.tasks` publishing path was never engaged here). |
| 7 | `rg -l 'env\.export\|/env' ~/.config/systemd/user/` | Only `opencode.service` references an env file among user units in that directory. |
| 8 | Per-running-service MainPID environ sweep (`systemctl --user list-units --type=service --state=running` loop) | Three services whose main process carries a deployment `DIR`: `opencode.service` (1783, opencode-git), `opencode-bus-proxy.service` (1805, opencode-bus-proxy-git), `atuin-daemon.service` (10445, atuin-git). |
| 9 | `systemctl --user cat atuin-daemon.service` | Line 12: `EnvironmentFile=-/usr/local/src/atuin-git/env` — the generic `SYSTEMD_SERVICES_DEFAULT` injection ([atuin.src.pb L36](/atuin.src.pb) documents it). |
| 10 | `systemctl --user cat opencode-bus-proxy.service` | Line 11: `EnvironmentFile=-/usr/local/src/opencode-bus-proxy-git/env`. (Current [opencode-bus-proxy.src.pb L90](/opencode-bus-proxy.src.pb) points at `{{ETC}}/env-projections/proxy-service.env` — the deployed unit appears to predate that source; live evidence stands regardless.) |
| 11 | `head /etc/opt/amd-epp-main/env`; `grep EnvironmentFile /etc/systemd/system/amd-epp-main.service` | The env file contains `DIR="/etc/opt/amd-epp-main"` + `COMPFUZOR_ENVS="EPP"`; the (system-scope, currently **inactive**) unit loads it. Same emission pattern, second scope. (The jellyfin `EnvironmentFile` is commented out — unrelated.) |
| 12 | `head -4 /usr/local/src/dolt-git/bin/build-go.sh` and `build-dolt.sh` | The exact fragile prologue: `[ -z "$DIR" ] && export DIR="/usr/local/src/dolt-git"` then the envdefault source line with `>/dev/null`. |
| 13 | `~/.zshenv`, `~/.zshrc`, `~/.profile`, `~/.zlogin`, `~/.config/environment.d/`, `~/.config/mise`, `/etc/zsh` | **None** source `env.export`/`envdefault` or set `DIR`/`NAME`/`TYPE`. `~/.zshenv` sets only `PNPM_HOME` and `OPENCODE_SERVICE_*`/`OPENCODE_LOCATION_CACHE_TTL` (explaining those three non-pollution values in agent shells). The deployed ZIM module (`opencode-client-env.zsh`) exports only `OPENCODE_PASSWORD` from the pointer file. |
| 14 | `crontab -l`; `rg 'env\.export\|opencode-git' /etc/cron.d /var/spool/cron` | No crontab; no cron references. Cron is not a vector. |
| 15 | [files/_env](/files/_env) L33-42 read | `def("DIR", DIR) … def("GLOBAL_BINS_DIR", …)` + `mdef(ENV_PRIO/ENV)` + `def("COMPFUZOR_ENVS", ns.keys\|join(","))` — the emission source for the content. |

## Polluted variable inventory

Inherited by every opencode.service child (values as observed in this
session's own environ and the server's):

**Deployment-shaping — the polluting core** (these are what let one
deployment's identity masquerade inside another's bins/scripts):

| Variable | Value |
|---|---|
| `DIR` | `/usr/local/src/opencode-git` |
| `NAME` | `opencode-git` |
| `TYPE` | `opencode` |
| `INSTANCE` | `git` |
| `REPO` | `https://github.com/anomalyco/opencode` |
| `REPO_DIR` | `/usr/local/src/opencode-git/repo` |
| `BUILD_DIR` | `/usr/local/src/opencode-git/repo/build` |
| `GLOBAL_BINS_DIR` | `/usr/local/bin` |

**Service-runtime** (intended for the server; leaked but mostly benign outside
it): `LINKS_JSON`, `STATUS_DIRS=""`, `STATUS_DIRS_SUDO=""`,
`APT_INSTALL=present`, `OPENCODE_PRINT_LOGS`, `OPENCODE_LOG_LEVEL`,
`OPENCODE_SERVER_HOSTNAME/PORT/URL`, `OPENCODE_PASSWORD_FILE` (a pointer — no
secret value ever enters env files), `OPENCODE_DISABLE_AUTOUPDATE`,
`OPENCODE_WATCHER_BACKEND`, `BACKUP_TARGETS`,
`OPENCODE_WATCHMAN_COMMAND_TIMEOUT_MS`, `WATCHMAN_SOCK`,
`OPENCODE_FFF_WATCH`, `OPENCODE_LOCATION_CACHE_TTL`, `OPENCODE_WORKING_DIR`,
`OPENCODE_PROXY_URL`, and `COMPFUZOR_ENVS` (comma-joined ENV key list, used by
[env-exec](/env-exec); note it enumerates only the `ENV` mapping keys, not the
deployment header).

**The operator's exact question:** `BINS` is **not** among the exported
variables, and neither is `BINS_DIR`. `BINS` is a playbook-declaration
variable ([PERSIST_VARS](/vars/common.yaml#L137) notwithstanding) that the
[env template](/files/_env) never writes. `GLOBAL_BINS_DIR` **is** exported
(its value `/usr/local/bin` is shared across root deployments, so it does not
misdirect today — but a USERMODE deployment would export its own). The
demonstrated misdirection vector is `DIR`; `NAME`/`TYPE`/`INSTANCE`/`REPO`/
`REPO_DIR`/`BUILD_DIR` are equally deployment-shaped and are trusted wherever
a bin or script reads them from the environment rather than pinning its own.

## Blast radius

- **Everything under `opencode.service`** — the harness itself. Every agent
  session, every tool shell (this investigation included), every
  `ansible-playbook -c local` run, every materialized bin those sessions
  execute, inherits the opencode deployment env. Sampled live: 5 of 30
  processes in the cgroup carried `DIR` at sampling time (long-lived carriers:
  the server and its node children; playbook/tool shells churn through
  constantly). This is the population the dolt incident fired in, and the only
  one where cross-deployment confusion is *routine*.
- **`opencode-bus-proxy.service` children** inherit the bus-proxy deployment
  env (`DIR=/usr/local/src/opencode-bus-proxy-git`) — same pattern, smaller
  population (watch helpers).
- **`atuin-daemon.service` children** inherit the atuin deployment env —
  mostly inert (daemons rarely spawn shells) but the same standing hazard.
- **System scope:** `amd-epp-main.service` carries the same pattern via
  `/etc/opt/amd-epp-main/env` (currently inactive; would export
  `DIR=/etc/opt/amd-epp-main` to its children when started).
- **NOT the systemd user manager:** `show-environment` is clean; no playbook
  in this fleet declares `SYSTEMD_ENV` for these units, so nothing was
  published manager-wide (the `dbus-update-activation-environment` path in
  [vars_systemd_env.tasks](/tasks/compfuzor/vars_systemd_env.tasks) is
  dormant here).
- **NOT interactive/login shells:** no rc file, environment.d drop-in, ZIM
  module, or mise config sources `env.export` or sets these variables; a
  fresh login shell is clean.
- **NOT cron:** no crontab, no references in `/etc/cron.d`.

## Fix options (not applied)

**1. Stop exporting deployment env from the unit — emit and load a
service-scoped env file (recommended).** The service consumes only the
runtime keys (the `OPENCODE_*`/watchman/backup set — precisely what
`COMPFUZOR_ENVS` already enumerates). Concretely: have the env emission write
an additional service-scoped file (e.g. `env.service`) containing only the
`ENV`/`ENV_PRIO` mapping keys — the [files/_env](/files/_env) template already
computes that key set (`ns.keys`) — and point the unit's first
`EnvironmentFile=` at it instead of `{{DIR}}/env`, keeping the existing
`{{ETC}}/env-credential` second file (the load-credential precedent shows the
two-file pattern is established). `env`/`env.export` stay untouched, because
bins legitimately depend on them (`envdefault` fallback, `BACKUP_TARGETS` in
backup.ts, `GLOBAL_BINS_DIR` in install bins, `${VAR}` expansion in
config assembly). Apply the same one-line change to `atuin-daemon` and
`opencode-bus-proxy` (their `EnvironmentFile`s are the generic
`SYSTEMD_SERVICES_DEFAULT` injection — so the durable fix is a
`SYSTEMD_SERVICES_DEFAULT`/template change that emits the filtered file for
every deployment, not per-playbook edits), and to `amd-epp-main` in system
scope. Note systemd has no "unset from EnvironmentFile" directive, so the
subtraction must happen at file-content level — a filtered file, not a unit
override.

**2. Minimal-allowlist inline.** Replace `EnvironmentFile=-{{DIR}}/env` with a
handful of explicit `Environment=` lines (or a tiny dedicated file) listing
only the vars the unit's ExecStart actually reads. Most precise, highest
maintenance burden (every new ENV key needs the unit updated); option 1
automates the same shape.

**3. Bin-side hardening — already designed; do not duplicate here.**
[Build-lane modularization](/design/build-lanes/modularization0.glm53max.md)
moves 3-4: default `deployment_rooted` bins (derive `$DIR` from script
location — [files/_bin L26-31](/files/_bin) already does exactly this for
compositors), a loud inherited-`DIR` mismatch warning, and an env-provenance
line replacing the `>/dev/null` silence. Operator rulings recorded there bind
this: inherited-`$DIR` deference is load-bearing (pinning needs a deprecation
window), and implementation is to be scoped together with this trackdown's
unit-side fix — they close the same incident from opposite ends. Bin-side
alone cannot suffice while the unit keeps exporting `DIR`, because
`envdefault`'s only-unset contract (correct, keep) means an inherited value
always wins over the file.

**4. Make the wrong-sourcing mechanically visible regardless** (cheap,
composes with any of the above): the env helper announces which env file it
sourced (loud mode exists via `V>2`/`COMPFUZOR_QUIET`; default the announce
on for bins), so `bin claims deployment X, sourced env of Y` is checkable in
playbook logs — the dolt failure would have printed its own diagnosis.

Sequence implied by the rulings: option 1 (fleet-wide, via the shared default)
first — it removes the emission — then build-lane moves 3-4 behind their
deprecation window, with option 4's provenance line landing in the same
change.

## Cross-references

- [Dolt conversion report](/design/archive-workspace/dolt-conversion0.glm53fx.md) —
  the motivating incident; its assessment cause 1 is the failure this
  trackdown traces to the unit directive, and its "Open / handed off" names
  this hazard as unresolved.
- [Build-lane modularization](/design/build-lanes/modularization0.glm53max.md) —
  the bin-side counterpart (deployment-rooted bins, fold precedence,
  provenance); its operator rulings (2026-10-16) gate sequencing of the fix
  described above.
- [files/_env](/files/_env) / [files/_helpers/env](/files/_helpers/env) /
  [envdefault](/envdefault.src.pb) — the three pieces of machinery whose
  composition (deployment header in every env file; inherited-`$DIR`
  deference; only-unset sourcing) produces the silent cross-deployment
  behavior.
- [vars/systemd.yaml SYSTEMD_SERVICES_DEFAULT](/vars/systemd.yaml) — the
  generic injection that gives every ENV-declaring playbook a
  `EnvironmentFile=-{{DIR}}/env`; the right lever for a fleet-wide option-1
  fix.
