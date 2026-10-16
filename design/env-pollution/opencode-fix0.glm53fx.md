---
type: Report
title: "opencode.service unit-scoped env fix — deployment identity no longer exported to children"
description: "Implements the operator-scoped ('fix just opencode please specifically') unit-side fix from the env-pollution trackdown: opencode.service now loads a dedicated {{ETC}}/env-service EnvironmentFile containing only the deployment-declared runtime keys (ENV/ENV_PRIO/ENV_LIST) instead of the whole {{DIR}}/env file, so the server and every child process stop inheriting DIR/NAME/TYPE/INSTANCE/REPO/REPO_DIR/BUILD_DIR/GLOBAL_BINS_DIR/LINKS_JSON/COMPFUZOR_ENVS/STATUS_DIRS*/APT_INSTALL. env/env.export stay byte-identical for bins. Shared compfuzor machinery, atuin-daemon, and opencode-bus-proxy are deliberately untouched. Applied without restarting the service; the restart is the documented operator step."
resource: /design/env-pollution/opencode-fix0.glm53fx.md
tags: [compfuzor, env, systemd, opencode, pollution, env-service, unit-scoped, fix]
status: draft
generated: { by: model:glm5.3-flash-max, at: 2026-10-16 }
sources:
  - id: commissioning
    resource: opencode://ses_eba42c532ffeGDFn343ysNvjcd
    title: Commissioning session: opencode unit env fix
  - id: authoring-session
    resource: opencode://ses_eb9afc117ffemEdX20kkeWyYaC
    title: Implemented the fix (mechanism study, playbook edit, guarded runs, byte-identical env restore, verification), authored this report
  - id: trackdown
    resource: /design/env-pollution/trackdown0.glm53fx.md
    title: The forensics this fix implements (its option 1, scoped to opencode only)
  - id: build-lane-design
    resource: /design/build-lanes/modularization0.glm53max.md
    title: Bin-side counterpart design; operator rulings recorded there gate the sequencing
  - id: playbook
    resource: /opencode.src.pb
    title: The changed playbook (EnvironmentFile, env-service ETC_FILES entry, OPENCODE_SERVICE_ENV_KEYS snapshot task)
  - id: incident
    resource: /design/archive-workspace/dolt-conversion0.glm53fx.md
    title: Dolt conversion report — the motivating incident
---

# opencode.service unit-scoped env fix

## Result

**Applied and verified. `opencode.service` no longer points at the deployment
env file.** The unit's first `EnvironmentFile=` is now
`/etc/opt/opencode-git/env-service` — a new playbook-rendered file holding
exactly the 16 runtime keys this deployment declares in `ENV` — and the
`-{{DIR}}/env` entry is gone. The server (MainPID 1783) ran untouched
throughout; the new unit config is staged on disk with
`NeedDaemonReload=yes`, so the pollution stops at the operator's next
deliberate restart. `env` and `env.export` are byte-identical to before
(sha256-verified); bins keep reading them.

Scope held as commissioned: only `opencode.src.pb` changed. The shared
machinery (`files/_env`, `vars/systemd.yaml`
`SYSTEMD_SERVICES_DEFAULT`, `fs_env.tasks`), `atuin-daemon.service`, and
`opencode-bus-proxy.service` keep their current (polluting) surface —
that remains the fleet-wide decision the
[trackdown](#cross-references) laid out.

## Mechanism chosen and why

**Option (b) from the commissioning brief: a dedicated rendered service env
file, referenced hard.** Option (a) was checked and rejected: compfuzor's
`SYSTEMD_ENV` ([vars_systemd_env.tasks](/tasks/compfuzor/vars_systemd_env.tasks))
is *manager-wide* publishing — it injects `ExecStartPost` running
`dbus-update-activation-environment` / `systemctl set-environment`, which is
a strictly wider pollution surface than the unit, not unit-scoped
`Environment=`. opencode does not declare it, and it is the wrong tool.

The implementation has three pieces, all inside `opencode.src.pb`:

1. **`SYSTEMD_SERVICES.EnvironmentFile` swap.** The declared list
   (`["{{ETC}}/env-service", "{{ETC}}/env-credential"]`) replaces the
   generic `SYSTEMD_SERVICES_DEFAULT` injection (`-{{DIR}}/env`) because
   defaults enrich but declared keys replace
   ([vars_systemd_unit.tasks](/tasks/compfuzor/vars_systemd_unit.tasks)
   "defaults enrich, declared replaces"). The credential file stays second
   (later files win), preserving the LoadCredential pointer override.
   The first reference is **hard** (no `-` prefix): the same playbook always
   renders `env-service`, so a missing file fails the unit loudly instead of
   booting with a silently absent runtime env.

2. **`env-service` as an `ETC_FILES` entry.** Rendered by the standard
   fs_hierarchy writer to `/etc/opt/opencode-git/env-service`, next to the
   existing `env-credential` precedent. Its content loops over
   `OPENCODE_SERVICE_ENV_KEYS` and resolves each key's value **at fs render
   time from the merged `ENV`** — the same mapping `files/_env` renders — so
   every line byte-matches the deployment env file, with the same
   `KEY="value"` systemd form and the same skip-none/normalize semantics as
   the `def()`/`mdef()` macros.

3. **The `OPENCODE_SERVICE_ENV_KEYS` snapshot task.** The declared-vs-merged
   boundary is the crux: compfuzor's vars phase merges identity keys into
   `ENV` (`LINKS_JSON` via gen_links, `REPO_DIR` via vars_repo,
   `STATUS_DIRS*`/`APT_INSTALL` via common.yaml subsystems), and common.yaml
   values (`WATCHMAN_CANONICAL_SOCKET_ABS`) do not exist before it loads.
   So the playbook captures **keys only** in a task placed after the
   secondary `ENV_PRIO` set_fact and before
   `import_tasks: tasks/compfuzor.includes`:
   `ENV_PRIO keys + ENV keys + ENV_LIST names`. Values resolve later, from
   the merged `ENV` (declared keys are never overridden by the merges, only
   added to). This also carries the instance story for free: secondary
   instances snapshot their `ENV_PRIO` presence-gated keys
   (`OPENCODE_BINARY`, `OPENCODE_CONFIG_DIR`, `OPENCODE_DB`), so their units
   get the same scoped treatment.

## Before/after of the unit's env surface

Before (loaded into the server and inherited by every child):

```
EnvironmentFile=-/usr/local/src/opencode-git/env      # 28 vars
EnvironmentFile=/etc/opt/opencode-git/env-credential
```

The 28 vars included the polluting identity set — `DIR`, `NAME`, `TYPE`,
`INSTANCE`, `REPO`, `REPO_DIR`, `BUILD_DIR`, `GLOBAL_BINS_DIR`,
`LINKS_JSON`, `COMPFUZOR_ENVS`, plus the compfuzor-contributed
`STATUS_DIRS`, `STATUS_DIRS_SUDO`, `APT_INSTALL` — alongside the runtime
keys. After:

```
EnvironmentFile=/etc/opt/opencode-git/env-service     # 16 keys
EnvironmentFile=/etc/opt/opencode-git/env-credential  # unchanged
```

`env-service` contains exactly: `OPENCODE_PRINT_LOGS`, `OPENCODE_LOG_LEVEL`,
`OPENCODE_SERVER_HOSTNAME`, `OPENCODE_SERVER_PORT`, `OPENCODE_SERVER_URL`,
`OPENCODE_PASSWORD_FILE`, `OPENCODE_DISABLE_AUTOUPDATE`,
`OPENCODE_WATCHER_BACKEND`, `BACKUP_TARGETS`,
`OPENCODE_WATCHMAN_COMMAND_TIMEOUT_MS`, `WATCHMAN_SOCK`,
`OPENCODE_FFF_WATCH`, `OPENCODE_LOCATION_CACHE_TTL`, `OPENCODE_WORKING_DIR`,
`OPENCODE_PROXY_URL`, `OPENCODE_SERVICE_METADATA`. No identity variable
reaches the unit by any path: the unit declares no `Environment=` lines (the
`motel.conf` drop-in carries only the OTEL pair), `SYSTEMD_ENV` is not
declared, and the generic default injection is replaced by the declared list.

Two additive notes, both deliberate:

- `OPENCODE_SERVICE_METADATA` appears in `env-service` but not in the
  deployed env file: the deployed env predates the playbook's
  `OPENCODE_SERVICE_METADATA` ENV addition. Its value (`true`) equals the
  current `OPENCODE_DISCOVERY_METADATA` default, so behavior is unchanged.
- `OPENCODE_PROXY_URL` is `http://127.0.0.1:49372` because the run passed
  `-e OPENCODE_BUS_PROXY_DISCOVERY=true` — the deployment's actual input
  (see the env-drift note under Verification).

## Verification

| # | Check | Observed |
|---|---|---|
| 1 | `sha256sum env env.export` before (captured pre-change) vs after both runs | `4b9c6274…` / `629810d7…` — **byte-identical**. My first guarded run re-rendered them with current-playbook defaults (`OPENCODE_PROXY_URL=""`, plus `OPENCODE_SERVICE_METADATA`), drifting them; I restored both files byte-identically from the captured pre-change content (hash-equal), then re-ran with `-e ENV_BYPASS=True` so the env lane never touches them again. |
| 2 | `cat /etc/opt/opencode-git/env-service` | The 16 keys above, no identity vars, systemd `KEY="value"` form. |
| 3 | `systemctl --user cat opencode.service` | `EnvironmentFile=/etc/opt/opencode-git/env-service` + `env-credential`; no `-…/env`, no `Environment=` identity lines. Installed-unit delta vs the materialized unit was exactly the one EnvironmentFile line (copied into place with mode preserved — the installed unit is a regular file, normally refreshed by the thunk's `install-unit.sh`, which ran bypassed). |
| 4 | `systemctl --user show opencode.service -p MainPID -p ActiveState` | `MainPID=1783`, `active/running` — unchanged from the pre-run capture; the service was never restarted, reloaded, or daemon-reloaded. |
| 5 | Playbook run | `opencode.src.pb` exit 0 with the guard prefix (`env -u DIR -u NAME -u TYPE -u INSTANCE -u REPO -u REPO_DIR -u BUILD_DIR -u GLOBAL_BINS_DIR -u COMPFUZOR_ENVS -u LINKS_JSON`), `-e SYSTEMD_THUNK_BYPASS=True PKGS_BYPASS=True APT_BYPASS=True BINS_RUN_BYPASS=True GIT_BYPASS=True REPO_BYPASS=True ENV_BYPASS=True OPENCODE_BUS_PROXY_DISCOVERY=true`. Second run's only change: the `env-service` file itself. |
| 6 | `NeedDaemonReload` | `yes` after the installed unit was refreshed — systemd has seen the new config; the loaded (old) config still serves until restart, exactly as intended for a staged fix. `restart.sh` checks this property and daemon-reloads before restarting. |

The unit-env checks the playbook itself registers (STATUS_PROC
`mainpid-env` reporters for `WATCHMAN_SOCK`, `OPENCODE_FFF_WATCH`, and the
credential pair) read the *running* MainPID and stay green against the old
environment; after the operator's restart they will verify the new one —
`bin/status.sh` is the one-command post-restart check.

## Operator follow-up

**Restart when ready — it terminates all running agent sessions under
`opencode.service`.** Every active session, in-flight tool call, and
server-held process dies with the unit; clients come back per the usual
restart-clients flow. The managed path (daemon-reloads because
`NeedDaemonReload=yes`, restarts, authenticates `/api/info`, verifies the
new server inherited the canonical Watchman socket):

```sh
/usr/local/src/opencode-git/bin/restart.sh
```

Equivalent manual sequence:

```sh
systemctl --user daemon-reload
systemctl --user restart opencode.service
```

Until that restart, the running server still exports the polluted set to
every new child, so keep the interim guard on anything
env-sensitive run from inside current sessions:

```sh
env -u DIR -u NAME -u TYPE -u INSTANCE -u REPO -u REPO_DIR \
    -u BUILD_DIR -u GLOBAL_BINS_DIR -u COMPFUZOR_ENVS -u LINKS_JSON \
    <command>
```

Post-restart verification:

```sh
tr '\0' '\n' < "/proc/$(systemctl --user show opencode.service -p MainPID --value)/environ" \
  | grep -E '^(DIR|NAME|TYPE|INSTANCE|REPO|REPO_DIR|BUILD_DIR|GLOBAL_BINS_DIR|COMPFUZOR_ENVS|LINKS_JSON|STATUS_DIRS|APT_INSTALL)=' \
  || echo "opencode.service env clean"
/usr/local/src/opencode-git/bin/status.sh
```

Two standing inputs to remember for future full playbook runs (they
re-render `env`/`env.export`, which this fix deliberately froze via
`ENV_BYPASS=True`):

- The deployed env encodes `-e OPENCODE_BUS_PROXY_DISCOVERY=true`; a
  default run would render `OPENCODE_PROXY_URL=""` and silently change
  proxy discovery.
- The current playbook adds `OPENCODE_SERVICE_METADATA` to the env files
  (the deployed ones predate it) and will re-render `env-service` from the
  declared keys — that part is now self-maintaining.

## Cross-references

- [Env-pollution trackdown](/design/env-pollution/trackdown0.glm53fx.md) —
  the causal chain and fix options; this report implements its option 1
  scoped to opencode only, per operator decision. Its fleet-wide option 1
  (shared `SYSTEMD_SERVICES_DEFAULT`/template change) remains open for
  atuin-daemon and opencode-bus-proxy.
- [Build-lane modularization](/design/build-lanes/modularization0.glm53max.md)
  — the bin-side counterpart (deployment-rooted bins, inherited-`$DIR`
  deprecation window, provenance line); its operator rulings gate that
  sequencing behind this unit-side fix. Until the restart lands, bins still
  observe inherited `DIR` from live sessions.
- [Dolt conversion report](/design/archive-workspace/dolt-conversion0.glm53fx.md)
  — the incident that motivated the trackdown.
