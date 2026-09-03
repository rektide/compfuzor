---
type: Design
title: proc monitoring — mission
description: Disaggregate status-inotify into a generic, parameterizable /proc monitoring facility that playbooks target at their own concerns.
resource: /.design/proc/proc.glm53.md
tags: [status, proc, inotify, gen, playbooks]
status: draft
generated: { by: model:glm53, at: 2026-09-03T00:00:00Z }
verified: { by: unverified, at: never }
stale_after: 2026-10-01
sources:
  - id: conversation-2026-09-02
    resource: file:///home/rektide/src/compfuzor
    title: compfuzor session — status-inotify disaggregation, two rejected mechanisms
    author: rektide + glm53
    last_modified: 2026-09-02
---

# proc monitoring — mission

## What is up

We keep hand-rolling per-facility `/proc` monitoring. `status-inotify.sh`
(fs-inotify) is the exemplar: a bespoke script that counts inotify
watches/instances — uid-wide totals, top consumers, a `--unit` cgroup scope,
and drift against the sysctls its playbook owns. The watcher playbooks
(watchman/watchwoman) each carry a hand-added, near-identical cgroup-scoped
inotify section inside their status scripts. Two attempts to generalize have
been rejected, and their failure mode defines the requirement:

1. `INOTIFY_STATUS_BIN` (reverted): a cross-render contract var so opencode's
   wrapper could call fs-inotify's reporter. Rejected — cross-render coupling,
   hand-jammed wiring, one bespoke wrapper per consumer.
2. Ambient `status-proc.sh` (current, to be demoted): a status-subsystem
   builtin that reports **one fixed catalog of every counter** for cgroup
   scopes, auto-registered everywhere. Rejected — it is a dashboard, not a
   toolkit. "Monitors all proc for a cgroup" is too much: no playbook can say
   *these are my proc concerns*; the generic cannot be targeted, so nobody is
   served well.

The mission, stated plainly: **blow up the special-purpose status-inotify by
extracting the generic facility it is secretly an instance of** — /proc
monitoring, parameterized, that different playbooks configure to their
relevant concerns.

## Is status-inotify really just proc monitoring? (decomposition)

| Piece of status-inotify.sh today | Generic / declarable? |
| --- | --- |
| count inotify watches (fdinfo `inotify wd:` lines over `anon_inode:inotify` fds) | yes — counter definition |
| count inotify instances (fd-kind) | yes — counter definition |
| scope to a unit's cgroup / whole uid | yes — scope parameter (subtree rollup) |
| drift %, thresholds, exit codes | yes — threshold parameter + status.sh conventions |
| STATUSES/BINS wiring | yes — gen machinery |
| which ceilings matter (`fs.inotify.max_*`) | declarable data; same playbook *owns* those sysctls |
| top-consumers interactive view | presentation; `usage.sh` already the interactive tool |
| sysctl *drift* (desired vs live limit) | already owned by gen_kernel's status-sysctl |

Nothing in it is irreducibly bespoke. The answer to "what else?" is: nothing
— and that is the point.

## Goal and objectives

- **One counting engine, N declarations.** A playbook declares
  scopes + counters + ceilings; machinery renders a reporter for exactly
  that, wired into its STATUSES. No hand-written counting code per playbook.
- **Targetability.** fs-inotify declares inotify counters against the pools
  it owns; opencode declares its unit scope and its fd/inotify concerns;
  the watcher playbooks eventually replace their hand-rolled sections with
  declarations. Each status run shows *that playbook's* proc concerns.
- **Self-contained renders.** No cross-render contracts, no ambient
  auto-registration, no shared-runtime dependencies. Baked parameters, like
  status.sh bakes its STATUSES list.
- **Demolition.** status-inotify.sh dies; its numbers must be reproducible
  from the declaration before it is deleted.

## Non-goals

- Rates/history/deltas (stateless status reporters).
- System-wide value drift — gen_kernel (status-sysctl/-sysfs) and
  status-dirs own value/dump semantics; this facility owns only per-process
  facts aggregated over scopes.
- Path-pattern fd classification (the one unbounded counter axis) until a
  real consumer appears; it is the escape hatch, not the core.
- Timers/alerting. Status first.

## Open questions (to align on)

1. Declaration surface and naming: one mapping (`PROC_STATUS:`) vs separate
   vars; gen_proc as a new gen_* leaf vs folding into gen_status.
2. Catalog home: counter ids defined core-side vs per-declaration inline
   definitions (deferred?).
3. Ceiling spelling: sysctl key (validated against the same render's
   KERNEL_SYSCTL — the owner-coherence check) vs /proc/sys path vs literal.
4. Default scope when a declaration omits one: `@slices`, `@user`, or none
   (require explicit)?
5. Whether any ambient view survives at all, or every appearance is
   declared.
6. Adoption order for the watcher playbooks' hand-rolled cgroup sections.
7. Does `--top`/top-consumers belong in the reporter or stay interactive-only
   (usage.sh)?

## Research prompt

*"compfuzor (ansible-based host config compiler; each playbook renders a
self-contained deployment dir with bin/, etc/, env, and a status.sh that runs
registered STATUSES reporters; gen_kernel turns KERNEL_SYSCTL into generated
reporters) — design a gen_proc-style subsystem where playbooks declare
/proc counter concerns (scopes = systemd cgroups with subtree rollup,
metrics = fd-kind/fdinfo-line counters like inotify watches/instances,
ceilings = sysctl-derived or literal) and get a baked, self-contained status
reporter; the existing bespoke status-inotify.sh must be expressible as a
declaration and then deleted."*
