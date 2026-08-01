# Bin compositors and composers

> The action-runner primitives and the current flat composition model are
> documented in [`doc/subsys.md`](subsys.md) § "gen_bins: action composition"
> and "Action runner". This doc specifies the **compositor hierarchy** (the
> `subsystem` field) and should be read alongside that one.

This document describes how action scripts (`build*.sh`, `install*.sh`,
`apply*.sh`, …) are assembled into runnable **compositors**, and the two-tier
hierarchy that lets a whole subsystem's scripts be addressed and run as a unit.

## The three layers

| Layer | Example | Produced by |
|---|---|---|
| **Leaf** | `install-socket-atuin-daemon-user.sh` | a subsystem or playbook (`BINS`) |
| **Subsystem compositor** | `install-systemd-user.sh` | [`bin_composers`](/library/filter_plugins/bin_composers.py) |
| **Scope compositor (top)** | `install-user.sh` | `bin_composers` |

A *leaf* does one concrete thing. A *compositor* is a generated script whose
body is a sequence of child invocations (`"$DIR/bin/<child>" "$@"`). Every leaf
and compositor inherits the shared action-runner primitives from
[`files/_bin.header`](/files/_bin.header) (`_cf_action_init`, `_cf_run_guard`,
`_cf_guard_bypass`, …). Compositors are **manual entry points** — they are never
auto-run; [`bins_run`](/tasks/compfuzor/bins_run.tasks) only fires on leaves
with `run: true`. So the hierarchy only organizes how a human invokes things; it
does not change what auto-runs during a playbook.

## Actions

The set of recognized actions is data, in `BIN_ACTIONS` at the top of
[`bin_composers.py`](/library/filter_plugins/bin_composers.py) (currently
`build`, `install`, `apply`). The composer is driven off that list, so adding an
action (e.g. `status`) is a one-line change. `bin_composers(bins, actions=…)`
also accepts an override list for ad-hoc use.

## The `subsystem` field

A bin declares its grouping via `subsystem`:

| Source | value |
|---|---|
| subsystem-generated bin | the subsystem id, auto-set at generation/contrib time (e.g. systemd installers → `systemd`) |
| hand-written bin, `subsystem: myapp` | `myapp` — joins `<action>-myapp[-user].sh` |
| hand-written bin, no field (or `subsystem: False`) | ungrouped — direct child of the scope compositor |

`subsystem` is the only grouping axis; it reuses the established "subsystem"
vocabulary rather than introducing a new concept. A bin belongs to exactly one
subsystem. There is **deliberately no special handling** for edge cases like the
subsystem id equaling the action (`status-status.sh` is silly but valid).

## Hierarchy

```
install.sh / install-user.sh            (scope entry points — the top)
├─ install-systemd-user.sh              (subsystem compositor, ≥2 leaves)
│   ├─ install-socket-atuin-daemon-user.sh
│   └─ install-service-atuin-daemon-user.sh
└─ install-app-config.sh                (ungrouped — direct child)
```

- **Scope is the top entry point.** `<action>.sh` (system) and
  `<action>-user.sh` (user) are always emitted when an action has leaves. To
  install everything, run both (as today).
- **Subsystems nest within a scope — nothing spans scopes.** A subsystem
  compositor is `<action>-<subsystem>[-user].sh`; there is no cross-scope
  spanner. If a subsystem has leaves in both scopes, you get two compositors
  (`install-systemd.sh` and `install-systemd-user.sh`).
- **The scope compositor references subsystem compositors**, not their leaves
  directly: its `run_all` is the set of subsystem compositors for that action +
  scope, plus any ungrouped leaves. So each leaf is reached through exactly one
  path.

### When a subsystem compositor is emitted

Only when a subsystem contributes **≥2 leaves** to a given (action, scope). A
single-leaf subsystem emits no compositor — its lone leaf stays a direct child
of the scope compositor (this is also what avoids a leaf wrapping itself:
`build-rust.sh` is the leaf; there is no `build-rust` wrapper around it).

### Naming

```
<action>(-<subsystem>)?(-user)?.sh
```

System scope is bare (no suffix); user scope is `-user` — matching the existing
`install-service.sh` / `install-service-user.sh` convention. The action is the
first dash-segment; the subsystem comes from the `subsystem` field, **not** from
the name.

## Worked example — atuin

All user-scope. The systemd socket+service installers are tagged
`subsystem: systemd` by [`vars_systemd_unit.tasks`](/tasks/compfuzor/vars_systemd_unit.tasks);
the `[daemon]` config merger is a hand-written, ungrouped bin.

```
install-user.sh
├─ install-systemd-user.sh
│   ├─ install-socket-atuin-daemon-user.sh   (enable+start)
│   └─ install-service-atuin-daemon-user.sh  (link only, SYSTEMD_ENABLE=false)
└─ install-atuin-config.sh                    (merge [daemon] config)
```

Addressable pieces: `install-user.sh` (all user-scope) ·
`install-systemd-user.sh` (just the systemd tier — re-link units without
re-running the rust build) · each leaf directly.

## Backward compatibility

**Additive.** With no `subsystem` fields set, `bin_composers` output is
byte-identical to the previous flat model: `<action>.sh` / `<action>-user.sh`
with flat `run_all`. Existing playbooks are unaffected. A subsystem gains the
mid-tier only when its generator tags `subsystem:` on its bins (systemd does
this as of this change; others opt in the same way).

## Making a subsystem grouping-ready

Tag the bins at the point they're generated/contributed:

```yaml
# in the generator (e.g. vars_systemd_unit.tasks), on each install _bin_item:
subsystem: systemd
```

That's the whole opt-in. Any generator that wants its leaves grouped under
`<action>-<subsystem>[-user].sh` sets `subsystem: <id>` on them; single-leaf
generators need not bother (no compositor would be emitted anyway).

## References

- [`doc/subsys.md`](subsys.md) — action runner (`_cf_action`), `gen_bins`
  composition, scope, execution order.
- [`library/filter_plugins/bin_composers.py`](/library/filter_plugins/bin_composers.py)
  — the composer; `BIN_ACTIONS` is the data-driven action list.
- [`tasks/compfuzor/gen_bins.tasks`](/tasks/compfuzor/gen_bins.tasks) — calls
  `bin_composers` and merges the compositors back into `BINS`.
- [`tasks/compfuzor/bins_run.tasks`](/tasks/compfuzor/bins_run.tasks) — auto-runs
  only `run: true` leaves (compositors are manual).
- [`files/_bin.header`](/files/_bin.header) — shared leaf material injected into
  every bin.
- [`tasks/compfuzor/vars_systemd_unit.tasks`](/tasks/compfuzor/vars_systemd_unit.tasks)
  — where `SYSTEMD_ROOTS` installers are tagged `subsystem: systemd`.
