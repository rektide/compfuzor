---
type: Design
title: gen_proc — parameterized /proc monitoring for playbooks
description: A gen_* leaf where playbooks declare scopes, counters, and ceilings, and get a baked self-contained status reporter; status-inotify dies as an instance of it.
resource: /.design/proc/draft0.glm53.md
tags: [status, proc, gen, inotify, playbooks]
status: draft
generated: { by: model:glm53, at: 2026-09-03T00:00:00Z }
verified: { by: unverified, at: never }
stale_after: 2026-10-01
sources:
  - id: mission
    resource: /.design/proc/proc.glm53.md
    title: proc monitoring — mission (this wave's std doc)
    author: rektide + glm53
    last_modified: 2026-09-02
---

# draft0 — gen_proc: declare proc concerns, get a status reporter

> Wave note: glm53 session (zai-coding-plan/glm-5.3). This is a proposal for
> review against [`proc.glm53.md`](proc.glm53.md), not an implementation.

## Proposal in one paragraph

Add a **gen_proc** leaf (sibling of gen_kernel): any playbook declares a
`PROC_STATUS` mapping — **scopes** (systemd --user units / `@user` /
`@slices`), **metrics** (ids from a small closed catalog of /proc counter
definitions), and **drift** (per-metric ceilings and percentages) — and
gen_proc renders a self-contained `status-proc.sh` into that playbook's
deployment with the declaration **baked in**, registered into STATUSES.
Counting code exists exactly once; every appearance is declared; nothing is
ambient; no cross-render contracts. `status-inotify.sh` becomes a
six-line declaration and is deleted.

## The catalog (closed, kernel-bounded)

Per-process /proc facts that can be *aggregated over scopes* are exactly the
fd table plus two fdinfo line-patterns (verified by census, see mission doc):

| id | definition | ceiling source |
| --- | --- | --- |
| `procs` | processes in scope | — |
| `fds` | fd entries | literal (no kernel file; RLIMIT is per-process, cgroups don't enforce) |
| `inotify.instances` | fds `anon_inode:inotify*` | `fs.inotify.max_user_instances` |
| `inotify.watches` | fdinfo lines `^inotify wd:` on those fds | `fs.inotify.max_user_watches` |
| `epoll.fds` | fds `anon_inode:*eventpoll*` | — |
| `epoll.registrations` | fdinfo `^tfd:` lines on those fds | — |
| `eventfd.fds` / `timerfd.fds` / `signalfd.fds` | fd-kind counts | — |
| `socket.fds` / `pipe.fds` / `memfd.fds` / `pidfd.fds` | fd-kind counts | — |

(Memory/threads are deliberately absent: the kernel already rolls those up
per-cgroup — `systemctl show` territory.) Catalog ids live core-side with the
engine; a metric id is the only thing a consumer names. Inline definitions
(path patterns etc.) are the deferred escape hatch, not in this draft.

## Declaration

```yaml
# fs-inotify.etc.pb — replaces status-inotify.sh entirely
PROC_STATUS:
  scopes: ["@user"]                    # the pools are user-wide
  metrics: [inotify.watches, inotify.instances]
  drift:
    inotify.watches:
      ceiling: fs.inotify.max_user_watches   # sysctl KEY, not a path
      pct: 90
    inotify.instances:
      ceiling: fs.inotify.max_user_instances
      pct: 90
```

```yaml
# opencode.src.pb — this service's own concerns
PROC_STATUS:
  scopes: [opencode.service]
  metrics: [inotify.watches, inotify.instances, fds, socket.fds]
  drift:
    inotify.watches: {ceiling: fs.inotify.max_user_watches, pct: 90}
```

- **scopes**: `@user` (whole uid), `@slices` (active user slices), or unit
  names. No default — a declaration must name its scopes (open question 4 in
  the mission doc; the alternative is default `@slices`).
- **ceiling**: a sysctl key — gen_proc **validates it against the same
  render's `KERNEL_SYSCTL`** when present (owner-coherence: only the playbook
  that owns a limit may declare it as a ceiling; otherwise the key must be
  kernel-familiar or spelled as `/proc/sys/...` path) — or a literal number.
  The rendered reporter reads ceilings **live** at run time from
  /proc/sys, so sysctl changes track without re-render.
- **pct**: drift threshold, default 90.
- Reporters keep the status.sh convention: exit 0 clean / 1 drift / 2 n/a.

## Render mechanics

- Engine template: `files/proc/status-proc.sh` — the current
  `files/status/status-proc.sh` single-pass counting core, reworked as a
  Jinja template that bakes the declaration (selected metrics, scopes,
  ceilings, thresholds) into constants. One /proc pass computes the selected
  metrics only.
- `tasks/compfuzor/gen_proc.tasks`: validate (known metric ids; scopes
  non-empty; ceilings resolvable/owned; pct sanity) → contribute the BINS
  entry → append `status-proc.sh` to STATUSES. Runs **before** gen_status
  bakes status.sh (same ordering constraint gen_kernel already satisfies).
- Runtime flags survive for interactive use on the deployed copy
  (`--scope X` override, `--top N`); env is not the transport anymore — the
  bake is.

## Demolition and adoption plan

1. **Demote the ambient attempt**: remove gen_status's status-proc
   auto-registration, the status contrib's PROC_STATUS_SCOPES env, and
   opencode's `PROC_STATUS_SCOPES` list (the mechanism this draft replaces).
2. **fs-inotify first**: add the declaration above, render, and prove the
   reporter's numbers **byte-match** `status-inotify.sh` (user mode) before
   deleting `files/fs-inotify/status-inotify.sh` and its STATUSES entry.
   `usage.sh` stays — interactive top-consumers is presentation, not status.
3. **opencode**: switch to its declaration (replacing the scopes list).
4. **Watchers later**: watchman/watchwoman status scripts carry hand-rolled
   cgroup inotify sections; each becomes a `PROC_STATUS` declaration and the
   inline section is deleted. (Adoption is mechanical once fs-inotify
   proves the path; open question 6.)

## What stays where (boundaries)

- gen_kernel/status-sysctl: *drift of the limits themselves* (desired vs
  deployed vs live sysctl).
- gen_proc/status-proc: *consumption of the limits* (scope-aggregated
  counters vs ceilings).
- usage.sh: interactive top-consumers investigation.
- status-dirs: raw value dumps of declared dirs.

## Verification sketch

- Render fs-inotify + opencode; `bash -n` + ansible syntax-check.
- Live parity harness: run old `status-inotify.sh` (user + `--unit`) and the
  new baked reporters side by side on the same box; watches/instances must
  match exactly (they count the same /proc rows).
- Drift paths: PROC_ROOT seam against a synthetic proc tree with a tiny
  ceiling to force the ≥90% branch; inactive-scope branch; empty-scope
  branch.
- Regression: status.sh of an untouched playbook (no PROC_STATUS) is
  unchanged — nothing ambient remains.

## Open questions for reviewers

1. `PROC_STATUS` as the var name — or `PROC_MON` / `PROC_METRICS`?
2. Default scopes when omitted: required-explicit (my lean) vs `@slices`?
3. Ceiling-as-sysctl-key with same-render ownership validation — yes?
4. One reporter per playbook (single PROC_STATUS) — is there ever a case for
   two named declarations in one playbook?
5. Should the rendered reporter embed the catalog rows it needs (fully
   self-contained, inspects nothing it wasn't given) vs referencing a
   shared catalog file? (My lean: bake everything; no shared runtime state.)
6. Adoption order and whether the watcher scripts' sections migrate in this
   wave or the next.
