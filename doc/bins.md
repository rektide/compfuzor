# Bin compositors and composers

> Status: **proposal** for a compositor *hierarchy* (the `group` axis). The
> current flat model is fully described in [`doc/subsys.md`](subsys.md) §
> "gen_bins: action composition" and "Action runner"; this doc extends it and
> should be read alongside that one.

This document specifies how action scripts (`build*.sh`, `install*.sh`,
`apply*.sh`) are assembled into runnable **compositors**, what the current
capabilities are, and the proposed extension that lets a whole subsystem's
scripts be addressed and run as a unit.

## The three layers

| Layer | Example | Produced by |
|---|---|---|
| **Leaf** | `install-socket-atuin-daemon-user.sh` | a subsystem or playbook (`BINS`) |
| **Compositor** | `install-systemd.sh` | [`bin_composers`](/library/filter_plugins/bin_composers.py) |
| **Top** | `install.sh` | `bin_composers` |

A *leaf* does one concrete thing. A *compositor* is a generated script whose
body is a sequence of child invocations (`"$DIR/bin/<child>" "$@"`). The *top*
is the compositor a user runs to do everything. Every leaf and compositor also
inherits the shared action-runner primitives from [`files/_bin.header`](/files/_bin.header)
(`_cf_action_init`, `_cf_run_guard`, `_cf_guard_bypass`, …).

## Current capabilities (flat: action × scope)

[`bin_composers`](/library/filter_plugins/bin_composers.py) groups leaves by
**(action, scope)** and emits one compositor per non-empty group:

- action ∈ {`build`, `install`, `apply`}
- scope ∈ {none (system), `user`} — inferred from the `scope` field, or from a
  name starting `install-user` / matching `*.user.sh`

So today you get `build.sh`, `install.sh`, `install-user.sh`, `apply.sh`, …,
each with a `run_all` of its leaves. See [`doc/subsys.md`](subsys.md) §
"gen_bins: action composition" for the full rules.

There is also a separate, complementary idiom — the **helper-sourcing** leaf:
the systemd per-unit installers set env vars (`UNIT_TEMPLATE`, …) and `source`
a shared [`install-unit.sh`](/files/systemd/install-unit.sh). That is leaf-level
reuse, not composition; it is unaffected by this proposal.

## The gap

The flat model has **no domain tier**. The systemd installers
(`install-socket-…`, `install-service-…`), the rust build/install, the config
merge — all land directly in `install.sh` / `install-user.sh` as an undifferentiated
list. You cannot say "re-run just the systemd tier," nor can you see systemd as
a unit in the install tree. With multi-unit subsystems (e.g. the socket+service
pair from `SYSTEMD_ROOTS`), the flat list gets noisy and opaque.

## Proposal: a `group` axis (compositor hierarchy)

Add a second grouping dimension — **group** — so a set of related leaves gets
its own compositor, and the top chains those group compositors.

### Data model

A `BINS` entry gains an optional `group`:

```yaml
BINS:
  - name: install-socket-atuin-daemon-user.sh
    scope: [user]
    group: systemd          # explicit
  - name: install-rust.sh
    # group auto-tagged from its subsystem → "rust"
```

Resolution:

| Source | group value |
|---|---|
| subsystem-contributed bin (`SUBSYSTEM.<id>.contrib.BINS`) | the subsystem id (`systemd`, `rust`, `npm`, …) — **automatic** |
| hand-written bin with `group: foo` | `foo` |
| hand-written bin with no `group` | none (ungrouped) |

Auto-tagging subsystem bins is what makes the pattern broadly usable: every
subsystem gets an `install-<subsystem>.sh` for free, with no playbook changes.

### Group-primary chaining (the chosen axis)

**Decision: `install.sh` chains the `group` axis.** For each group, `bin_composers`
emits an `install-<group>.sh` compositor; `install.sh`'s `run_all` is the set of
group compositors plus any ungrouped leaves:

```
install.sh
├─ install-systemd.sh          (group compositor)
│   ├─ install-socket-atuin-daemon-user.sh
│   └─ install-service-atuin-daemon-user.sh
├─ install-rust.sh             (group compositor)
│   └─ install-rust.sh / install-rust.user.sh …
└─ install-atuin-config.sh     (ungrouped leaf)
```

The **scope** axis (`install-user.sh`) is preserved as an *addressable
alternative entry point*, not chained by `install.sh`.

### The no-double-exec discipline

Two axes over the same leaves is a lattice, not a tree — a naive materialization
double-runs leaves. The rule that keeps it safe:

> **`install.sh` chains exactly one partition (by group). Every other
> compositor is an alternative entry point that also forms a clean partition.**
> Within any single run of any single compositor, each leaf is invoked exactly
> once.

So:

- `install.sh` → group compositors + ungrouped leaves (partition by group).
- `install-user.sh` → the user-scope slice of every group + ungrouped user
  leaves (partition by group within user scope).
- `install-<group>.sh` → all of that group's leaves (partition by scope within
  the group, when it spans scopes).

Each is a clean partition; none is nested inside another in the canonical run.
Running two of them manually may re-run shared leaves (acceptable: link/enable
ops are idempotent), but the canonical `install.sh` never double-runs.

### Naming rules (adaptive, collision-free)

| Group's leaves | Compositors emitted |
|---|---|
| one scope only | `install-<group>.sh` (= that scope's leaves) |
| both scopes | `install-<group>.sh` (spanner) + `install-<group>-system.sh` + `install-<group>-user.sh` |

`install-<group>.sh` therefore always means *"the whole group"* — whether the
group is single-scope (the bare name *is* the group) or multi-scope (the bare
name is the spanner over the two explicit-scope children). No name collision,
because the `-system`/`-user` children appear only when both scopes exist.

Scope-spanner names: `install-user.sh` (all user, across groups) and a new
`install-system.sh` (all system, across groups) for symmetry.

### Worked example — atuin (all user-scope)

```
install.sh
├─ install-systemd.sh
│   ├─ install-socket-atuin-daemon-user.sh   (enable+start)
│   └─ install-service-atuin-daemon-user.sh  (link only, SYSTEMD_ENABLE=false)
└─ install-atuin-config.sh                    (merge [daemon] config — ungrouped)
```

Addressable pieces: `install.sh` (all) · `install-systemd.sh` (the systemd
tier) · `install-user.sh` (== `install.sh` here, since everything is user) ·
each leaf. No `install-systemd-user.sh` is emitted — the group is single-scope,
so `install-systemd.sh` already is the user-scope systemd piece.

### Worked example — a group spanning both scopes

A `networkd` subsystem contributing system + user units:

```
install.sh
├─ install-networkd.sh                        (spanner)
│   ├─ install-networkd-system.sh
│   │   └─ install-network-config.sh          (system)
│   └─ install-networkd-user.sh
│       └─ install-network-user-config.sh     (user)
└─ …
```

Here you can run `install-networkd.sh` (both scopes), or just
`install-networkd-user.sh`, or `install-user.sh` (user slice across *all*
groups, including this one).

### Execution-model change (open)

Today `install.sh` and `install-user.sh` are co-equal compositors that the
action runner invokes separately (system vs user). Under group-primary,
`install.sh` becomes the **single top that runs everything once**; the scope
spanners become manual entry points. Open question for implementation:

- Does the action runner invoke only `install.sh`, with `install-user.sh` /
  `install-system.sh` reserved for manual/surgical use? (Implies `install.sh`
  must cover both scopes.)
- Or keep co-equal invocation but make the partitions non-overlapping by
  construction?

### Backward compatibility

**Additive.** When no leaf declares (or inherits) a `group`, `bin_composers`
output is byte-identical to today: `install.sh` / `install-user.sh` with flat
`run_all`. Existing playbooks are unaffected. Only subsystem-contributed and
explicitly-grouped bins gain the mid-tier.

## `bin_composers` changes (sketch)

1. Accept/derive a `group` on each leaf (subsystem auto-tag at contribution time
   in `vars/common.yaml` `SUBSYSTEM` merge, or in `gen_bins.tasks`).
2. Add group to the grouping key: `(action, group, scope)`.
3. Emit:
   - per `(action, group, scope)` → `install-<group>[-<scope>].sh` (adaptive
     per the naming table).
   - per `(action, group)` spanner when the group is multi-scope.
   - per `(action, scope)` spanner (`install-user.sh`, `install-system.sh`).
4. Chain `install.sh` over group compositors + ungrouped leaves; do **not** nest
   scope spanners under it.
5. Preserve the `compose: false` exclusion (library scripts like
   `install-unit.sh`).

## Open decisions

1. **Execution model** (above): single-top `install.sh` vs co-equal non-overlapping.
2. **Auto-tag site**: tag subsystem bins with `group = subsystem id` at contrib
   merge (`SUBSYSTEM` in [`vars/common.yaml`](/vars/common.yaml)) or in
   [`gen_bins.tasks`](/tasks/compfuzor/gen_bins.tasks)? Either keeps it off the
   playbook author's plate.
3. **Spanner emission threshold**: emit a spanner only when a group has ≥1 leaf
   in each of two scopes (proposed), or always?
4. **Ungrouped naming**: keep ungrouped leaves as direct children of `install.sh`,
   or give them an implicit `app`/`misc` group?

## References

- [`doc/subsys.md`](subsys.md) — action runner (`_cf_action`), `gen_bins`
  composition, scope, execution order.
- [`library/filter_plugins/bin_composers.py`](/library/filter_plugins/bin_composers.py)
  — the composer filter this proposal extends.
- [`files/_bin.header`](/files/_bin.header) — shared leaf material injected into
  every bin.
- [`files/systemd/install-unit.sh`](/files/systemd/install-unit.sh) — the
  helper-sourcing leaf pattern.
- [`tasks/compfuzor/vars_systemd_unit.tasks`](/tasks/compfuzor/vars_systemd_unit.tasks)
  — where `SYSTEMD_ROOTS` installers are generated (the multi-unit case that
  motivated this).
- [`library/filter_plugins/INDEX.md`](/library/filter_plugins/INDEX.md) — filter
  reference, including `bin_composers`.
