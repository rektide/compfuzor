---
type: Design
title: gen_user — declarative daemon identity via sysusers.d
description: Subsystem design for file-first daemon user/group creation, replacing inline `user:` pre-tasks.
resource: /.design/gen-user/init.0.gpt56t.md
tags: [compfuzor, sysusers, systemd, identity, subsystem]
status: draft
generated: { by: model:gpt56t, at: 2026-08-20T00:00:00Z }
stale_after: 2026-10-01
sources:
  - id: motivating-case
    resource: /apt-cacher-rs.src.pb
    title: apt-cacher-rs playbook (inline user pre-task + TODO)
  - id: subsys-conventions
    resource: /doc/subsys.md
    title: Subsystem contrib/merge/disarm conventions
  - id: systemd-vars
    resource: /tasks/compfuzor/vars_systemd.tasks
    title: pkg-config systemd facts (sysusersdir, systemuidmax already queried)
  - id: install-unit-pattern
    resource: /files/systemd/install-unit.sh
    title: SUDO_CMD install-bin pattern to mirror
  - id: upstream-deb
    resource: https://github.com/cgzones/apt-cacher-rs/blob/main/debian/postinst
    title: Upstream adduser --system --group postinst (the action being declarativized)
  - id: systemd-exec
    resource: man:systemd.exec(5)
    title: StateDirectory recursive chown semantics
---

# gen_user: declarative daemon identity

## What's up

Compfuzor's praxis is that generated files do the work. Daemon run-as identity
never got a file-first home, so every playbook needing one hand-rolls an inline
`user:` ansible pre-task — the one place playbooks break the praxis.
[`/apt-cacher-rs.src.pb`](/apt-cacher-rs.src.pb) is the motivating case: the
daemon refuses root euid ([`main.rs:808`](https://github.com/cgzones/apt-cacher-rs/blob/main/src/main.rs#L808)),
needs a stable named owner for its persistent cache (DynamicUser= rejected for
inspectability), and its unit keeps upstream's `ProtectHome=yes`. The pre-task
is also the only thing forcing **sudo before the build**.

Compounding confusion: compfuzor's `USER`/`OWNER`/`GROUP` vars mean
*deploy-time file ownership* ([`become_calc`](/library/filter_plugins/become.py)
reads them) — a different concept from daemon identity, with colliding names.
That's why this felt un-designed: it was never one design problem, it was an
unnamed concept.

Directions settled with the user (2026-08-19 session):

- **Shape A**: standalone sysusers gen subsystem owning a `SYSUSERS:` var;
  the systemd subsystem *derives* an entry from `SYSTEMD_SERVICES.User=` when
  opted in (contrib-merge, same pattern as rust contributing `PKGS`).
- **Opt-in default**: package-provided users (`nginx`, `postfix`, `bind`) are
  never claimed automatically.
- This doc plus a shallow beads ticket; implementation is follow-up work.

Research prompt: *Design a compfuzor subsystem that turns `SYSUSERS:` specs
plus opted-in `SYSTEMD_SERVICES.User=` into sysusers.d fragments and an install
bin that materializes them before unit enable — file-first, idempotent,
USERMODE-inert, bypass-aligned, sudo only at install phase.*

## Requirements

1. Named system users/groups creatable from generated files alone. Fresh-boot
   sufficiency: a fragment sitting in `/etc/sysusers.d` is read by
   `systemd-sysusers.service` at boot even if our install bin never ran.
2. Defaults matching today's inline task: system UID range, no home
   (`/nonexistent`), `/usr/sbin/nologin`.
3. Single declaration source for unit-run-as users: `SYSTEMD_SERVICES.User=`
   stays authoritative; the fragment is derived, so no drift.
4. Identity beyond units: group-only (`g`) and membership (`m`) specs (e.g.
   shared `media`/`render` groups).
5. Sudo only where it already lives: the install phase (unit linking,
   `GLOBAL_BINS_DIR` writes). Build stays sudoless.
6. `USERMODE`: inert — user-scope units never need system users.
7. Bypass: `SYSUSERS_BYPASS` broad scope + nested action entries, per the
   [disarm conventions](/doc/subsys.md).
8. Never auto-remove users. Fragment tombstoning may remove the file; the
   account stays (matches upstream postrm practice).

## Mechanism

**Staging** — mirror how units stage under `DIR/etc/`:

```
{{DIR}}/etc/sysusers.d/{{NAME}}.conf     (ETC_DIRS: [sysusers.d])
```

**Fragment line forms:**

```
u apt-cacher-rs - "apt-cacher-rs daemon" /nonexistent /usr/sbin/nologin
g media -
m rektide media
```

**Install bin** — `install-sysusers.sh`, structurally a copy of
[`install-unit.sh`](/files/systemd/install-unit.sh)'s first half:

1. `SUDO_CMD` link (default) or `--copy` the fragment into `SYSUSERSDIR`
   (default `/etc/sysusers.d`; wire the already-queried
   `pkg-config systemd --variable=sysusersdir` fact from
   [`vars_systemd.tasks`](/tasks/compfuzor/vars_systemd.tasks) into
   `vars/systemd.yaml` — it is currently queried but unused).
2. Run `systemd-sysusers` (idempotent; skips existing names; allocates from
   the system UID range).

## Var model

`SYSUSERS:` — list; string shorthand (`apt-cacher-rs`) expands to the default
u-spec; mapping form overrides `{name, comment, home, shell, kind:
user|group|member, group}`.

Name rationale: `SYSUSERS`, not `USERS`/`USER` (collides with deploy-ownership
vars) and not `GEN_USERS` (subsystem vars are mechanism-named: `PKGS`,
`LINKS`, `TOOL_VERSIONS`).

## Systemd derivation (opt-in)

`SYSTEMD_SYSUSER: True` on a playbook → the systemd subsystem contributes a
`SYSUSERS` entry via its contrib:

- name from `SYSTEMD_SERVICES.User` (non-root string; root/absent → no-op)
- `Group=` differing from `User=` adds a `g` line
- comment: `{{NAME}} daemon`

The unit remains the single declaration; the fragment is derived. No new
collision: `SYSTEMD_SYSUSER` is unused today.

## Ordering

`install-sysusers.sh` must run **before** unit enable/start (User= resolution
and StateDirectory chown happen at start). Systemd install bins already render
with a late `generatedAt: end` phase; a normal-phase sysusers leaf should land
before them in `install.sh`'s `run_all`. **Verify at implementation**
(compositor order in `bin_composers`/`bins.tasks`); fallback: same end-phase
mechanism ordered earlier, or a hook sourced by `install-unit.sh`.

## Interactions / edge cases

- **Package users**: opt-in means we never claim them. (`systemd-sysusers`
  skips existing names, but we do not lean on that for correctness.)
- **StateDirectory**: unchanged — recursive chown on owner mismatch per
  `systemd.exec(5)`, once the user exists.
- **USERMODE**: subsystem inactive; explicit `SYSUSERS:` under USERMODE
  renders a warning (not an error — user-scope playbooks may carry the var
  for symmetric authoring).
- **Removal**: BINS-style `state: absent` tombstone removes the fragment only.

## Migration

`apt-cacher-rs.src.pb`: drop the inline `user:` task, set `SYSTEMD_SYSUSER:
True`. Sudo then needed only for the `/usr/local/bin` copy (RUST_COPY), the
fragment install, and unit linking — all install-phase. Out of scope:
package-user playbooks (bind/postfix/dovecot — they're fine), login users,
UID pinning.

## Validation

- Render harness like [`.test-agent/rustcopy/`](/.test-agent/rustcopy/README.md):
  fragment staged, `ETC_DIRS` created, install bin emitted *before* systemd
  install bins, USERMODE inert, apt-cacher-rs unit renders identically.
- Offline idempotency: `systemd-sysusers --root=<fixture>` exercises creation
  without root.

## Open questions

1. One fragment per `{{NAME}}` (proposed — clean namespace) vs per-entry.
2. Link vs copy default into `/etc/sysusers.d` — propose mirroring
   install-unit.sh (link default, `--copy` opt-in).
3. Should the `SYSTEMD_USER` run-as *hint* var be retired in favor of
   `SYSTEMD_SYSUSER` + `User=`? It never emitted the directive anyway;
   cleanup candidate.
4. `g`-before-`u` ordering inside a fragment when a user's primary group is a
   named group (sysusers requires the group to exist first).
5. Bake `SYSUSERSDIR` at generation time vs export via `env.export` (units
   bake `UNIT_DIR`; follow that precedent).

## Cross-references

- [`/apt-cacher-rs.src.pb`](/apt-cacher-rs.src.pb) — motivating case; its TODO
  comment points here.
- [`/doc/subsys.md`](/doc/subsys.md) — subsystem contrib/`merge_subsys` and
  disarm/bypass vocabulary this design follows.
- [`/.design/config-mcp/init.0.md`](/.design/config-mcp/init.0.md) — sibling
  subsystem design; structural/OKF precedent.
- [`/tasks/compfuzor/vars_systemd.tasks`](/tasks/compfuzor/vars_systemd.tasks)
  and [`/files/systemd/install-unit.sh`](/files/systemd/install-unit.sh) — the
  two existing mechanics this design composes rather than reinvents.
