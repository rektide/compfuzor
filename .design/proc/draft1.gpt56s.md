---
type: Design
title: Typed proc-backed status providers
description: Defines STATUS_PROC as a provider-level collection whose typed rows selectively generate purpose-built status reporters.
resource: /.design/proc/draft1.gpt56s.md
tags: [status, proc, gen, playbooks]
status: draft
generated: { by: model:gpt-5.6-sol, at: 2026-09-04T00:00:00Z }
verified: { by: unverified, at: never }
stale_after: 2026-12-04
sources:
  - id: proc-mission
    resource: /.design/proc/proc.glm53.md
    title: proc monitoring mission
    author: rektide + glm53
    last_modified: 2026-09-03
  - id: proc-draft0
    resource: /.design/proc/draft0.glm53.md
    title: gen_proc parameterized monitoring proposal
    author: glm53
    last_modified: 2026-09-03
---

# Typed proc-backed status providers

## Decision

Proc inspection is a **status provider**, not a general metric subsystem.
Playbooks declare a typed list under the broad `STATUS_PROC` header. Internal
status leaves select rows by `check`; each active leaf contributes one
purpose-built reporter that batches every matching row. The existing
`gen_status` task remains the final `status.sh` compositor.

This replaces both rejected extremes:

- no check-specific top-level variables such as `STATUS_MAINPID_ENV`;
- no universal `status-proc.sh` dispatcher or flat counter catalog.

The public grain is broad and extensible. Runtime implementations remain
specific enough to preserve each check's identity, accounting, and verdict
semantics.

## Interface

```yaml
STATUS_PROC:
  - name: opencode-watchman-env
    check: mainpid-env
    unit: opencode.service
    manager: user
    expected:
      WATCHMAN_SOCK: /run/user/1000/watchman/user-state/sock

  - name: opencode-executable
    check: exe-current
    unit: opencode.service
    manager: user
    expected: /usr/local/bin/opencode2
```

Common row fields:

| Field | Contract |
|---|---|
| `name` | Unique lowercase status label. |
| `check` | Known proc-backed check kind. |
| `unit` | Concrete `.service` unit whose `MainPID` is inspected. |
| `manager` | `system` or `user`; defaults to the playbook's `SYSTEMD_SCOPE`, then `system`. |
| check-specific fields | Validated by the selected status leaf. |

`STATUS_PROC_BYPASS` suppresses every proc-backed leaf. `STATUS_BYPASS`
suppresses the whole status domain. A leaf remains independently bypassable by
its subsystem-derived bypass variable.

## Initial Checks

### `mainpid-env`

Generates `status-mainpid-env.sh`. `expected` is a non-empty mapping of
environment names to exact expected string values. The reporter resolves the unit's
live `MainPID` and compares its `/proc/<pid>/environ` without printing either
the expected or actual values.

Expected values are baked into the executable reporter, so this check is for
non-sensitive configuration only. Secret checks require a different protected
specification mechanism.

### `exe-current`

Generates `status-exe-current.sh`. `expected` is an absolute path. The reporter
compares inode identity between that path and `/proc/<MainPID>/exe`, allowing a
managed symlink while detecting replaced or deleted running executables.

## Generation

`sub_status_proc.tasks` validates and normalizes the whole collection, then
publishes one internal subsystem leaf for each selected check kind.
`gen_status_proc.tasks` merges each active leaf's `BINS` and `STATUSES`
contributions. One kind produces one reporter regardless of how many rows
select it. Empty input produces no status artifacts.

The old ambient `status-proc.sh` is removed. Proc inspection now appears only
where a playbook states an operational invariant.

## Ownership Rule

Provider headers are named for the authoritative observation source:

| Provider | Owns |
|---|---|
| `STATUS_PROC` | Live facts whose truth comes from `/proc`, even when systemd locates the PID. |
| future `STATUS_SYSTEMD` | Unit state and systemd-native properties. |
| future `STATUS_CGROUP` | Native cgroup counters, limits, pressure, and events. |
| domain reporters | Protocol health, socket behavior, and application-specific identity. |

This rule puts `mainpid-env`, `exe-current`, FD headroom, and process placement
under `STATUS_PROC`. It keeps CPU, memory, task pressure, and OOM events out of
proc status because cgroup interfaces already account those resources.

## Next Checks

- `fd-headroom`: compare each process's FD count with its own `RLIMIT_NOFILE`.
- `process-placement`: find matching processes outside declared cgroups.
- `inotify-pool`: only after unique-instance identity, shared-pool scope, and
  incomplete-observation behavior are resolved.

Raw memfd, eventfd, socket, or epoll counts do not become status checks without
a declared invariant or meaningful denominator.

## Cross-references

- [`/doc/arch.md`](/doc/arch.md) defines `gen_*` as the shared-artifact
  concretization layer. `gen_status_proc` follows that role and leaves runtime
  collection inside generated reporters.
- [`/doc/subsys.md`](/doc/subsys.md) documents activation, contribution, and
  bypass behavior for the internal status leaves.
- [`/doc/watcher-ops.md`](/doc/watcher-ops.md) provides the incidents that make
  live environment and executable currency actionable rather than generic
  telemetry.
- [`/files/fs-inotify/status-inotify.sh`](/files/fs-inotify/status-inotify.sh)
  remains the domain-specific inotify pool reporter while exact shared-object
  accounting is unresolved.
