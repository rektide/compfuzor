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
  - id: sysusers-d
    resource: man:sysusers.d(5)
    title: Cross-file duplicate-warning and m-line implicit-creation semantics
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
   shared `media` groups) — including cross-playbook sharing with no
   duplicate-declaration warnings (see
   [Cross-playbook shared identity](#cross-playbook-shared-identity-the-media-case)).
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

Each playbook owns one fragment file named for `{{NAME}}` — the *file* is
`apt-cacher-rs-git.conf`, the *user* named inside comes from the spec. A
fragment is usually **one line**. sysusers.d lines come in three kinds:

| kind | grammar | example |
|---|---|---|
| user | `u <name> <id\|-> ["<comment>"] [<home>] [<shell>]` | `u apt-cacher-rs - "apt-cacher-rs daemon" /nonexistent /usr/sbin/nologin` |
| group | `g <name> <id\|->` | `g media -` |
| member | `m <user> <group>` | `m apt-cacher-rs media` |

### Is `SYSTEMD_SYSUSER` alone enough?

**Yes, for the common case** — one daemon user, same-name primary group, no
memberships. That's apt-cacher-rs, and most daemon playbooks:

```yaml
# apt-cacher-rs.src.pb -- everything the author writes
SYSTEMD_SERVICES:
  User: apt-cacher-rs          # ← the single declaration
  Group: apt-cacher-rs
SYSTEMD_SYSUSER: True          # ← opt in to fragment generation
```

Generated fragment — one line:

```
u apt-cacher-rs - "apt-cacher-rs-git daemon" /nonexistent /usr/sbin/nologin
```

`SYSUSERS:` specs exist for identity **a unit cannot express**. Derivation
reads only `User=`/`Group=` — deliberately *not* `SupplementaryGroups=`,
which typically names pre-existing system groups (`render`, `video`) that we
must never claim to create. The escapes:

1. **Membership** — the daemon user (or a human) joins a shared group.
2. **Unit-less identity** — a group that exists for permissions (mounts,
   media libraries) with no daemon behind it.
3. **Attribute overrides** — real home dir, different shell, pinned UID.

### `SYSUSERS:` forms → fragment lines

String entries are users with defaults; mappings override or select a
non-user kind:

```yaml
# sonarr.src.pb -- a daemon consumer
SYSUSERS:
  - sonarr                              # u sonarr - "sonarr" ...
  - { name: sonarr, member: media }     # m sonarr media
  - name: gitea                         # attribute overrides
    comment: Gitea daemon
    home: /var/lib/gitea
    shell: /bin/bash
```

→ one fragment, emitted in dependency-safe order (groups, then users, then
memberships) regardless of authoring order:

```
u sonarr - "sonarr" /nonexistent /usr/sbin/nologin
u gitea - "Gitea daemon" /var/lib/gitea /bin/bash
m sonarr media
```

Note the consumer does **not** declare `g media -` — see
[Cross-playbook shared identity](#cross-playbook-shared-identity-the-media-case).

### Cross-playbook shared identity (the `media` case)

`sysusers.d(5)` defines the two semantics that make sharing work:

- **Duplicate declarations warn.** All fragments are sorted by filename; for
  the same user/group name the lexicographically earliest file's entry wins
  and every later entry for that name "will be logged as warnings" — on every
  sysusers run. So *a name is `u`/`g`-declared in exactly one fragment.*
- **`m` lines implicitly create** their user/group if missing ("If the user
  or group do not exist yet, they will be implicitly created"). So
  memberships *consume* a name without declaring it, and run order does not
  matter: a consumer on a fresh host implicitly materializes `media`; the
  owning declaration later finds it existing and skips silently (warnings
  are per duplicate *declaration*, not per existing group).

Ownership model:

| line | role | multiplicity |
|---|---|---|
| `u` / `g` | **declare** (own) a name | exactly one declarer |
| `m` | **consume** a name | anywhere it's needed |

Shared groups and human memberships live in one dedicated identity manifest
playbook — the same host-manifest shape as `pkgs-base.pb` / `apt-repos.pb` /
`sudo.pb`:

```yaml
# identity.pb -- the one declarer for shared names (host-specific)
SYSUSERS:
  - { name: media, kind: group }
  - { name: render, kind: group }      # only if not package-provided
  - { name: rektide, member: media }   # humans join here
```

```yaml
# sonarr.src.pb, jellyfin.srv.pb, ... -- consumers
SYSUSERS:
  - sonarr
  - { name: sonarr, member: media }
```

Standalone-consumer installs converge (implicit `m` creation), and removing
a consumer never touches the shared group — removal stays nobody's job, per
requirement 8.

Tiers combine — apt-cacher-rs with the daemon user derived *and* added to a
shared group:

```yaml
SYSTEMD_SYSUSER: True
SYSUSERS:
  - { name: apt-cacher-rs, member: media }
```

```
u apt-cacher-rs - "apt-cacher-rs-git daemon" /nonexistent /usr/sbin/nologin
m apt-cacher-rs media
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

`SYSUSERS:` — list of specs; the YAML forms and their fragment output are
worked under [Mechanism](#mechanism) above. The gen task normalizes entries
and emits lines in dependency-safe order: `g`, then `u`, then `m`.

Name rationale: `SYSUSERS`, not `USERS`/`USER` (collides with deploy-ownership
vars) and not `GEN_USERS` (subsystem vars are mechanism-named: `PKGS`,
`LINKS`, `TOOL_VERSIONS`).

## Systemd derivation (opt-in)

`SYSTEMD_SYSUSER: True` is only a **generator switch**: "also emit a `u` line
for the name in `User=`." It declares no identity itself — the declaration
remains the unit's `SYSTEMD_SERVICES.User:` line. A flag is needed rather
than automatic derivation because the same `User=` directive also appears in
playbooks whose user belongs to a package (`User: nginx`, `User: postgres`);
the flag says "this name is mine to create," absence says "someone else's."

`SYSTEMD_SYSUSER: True` on a playbook → the systemd subsystem contributes a
`SYSUSERS` entry via its contrib:

- name from `SYSTEMD_SERVICES.User` (non-root string; root/absent → no-op)
- `Group=` differing from `User=` adds a `g` line
- comment: `{{NAME}} daemon`
- derivation boundary: `User=`/`Group=` only. `SupplementaryGroups=` is never
  read — memberships referencing shared groups are authored explicitly via
  `SYSUSERS:` (see [Mechanism](#mechanism))

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
4. Primary group named differently from the user: needs a `g` line ordered
   before the `u` line. The g→u→m emission normalization covers ordering;
   decide whether a `group:` override on a user spec auto-emits the `g` line
   or asserts one was declared.
5. **Verify-at-implementation** (via `systemd-sysusers --root=<fixture>`
   offline runs, which the tool supports natively):
   - duplicate `m sonarr media` lines across two fragments — warned or
     silently idempotent?
   - `m`-implicit group creation: does it allocate from the *system* GID
     range (so it converges with a later `g media -`)?
   - exact warning text/volume for duplicate `g` declarations, to calibrate
     whether a gen-time lint ("name `X` declared in two fragments") is worth
     adding on top of the one-declarer convention.
6. Bake `SYSUSERSDIR` at generation time vs export via `env.export` (units
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
