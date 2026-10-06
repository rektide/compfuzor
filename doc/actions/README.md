# Audience action families

Compfuzor has an **opt-in** JavaScript action compositor. Without
`ACTION_AUDIENCES`, existing shell composition and `USERMODE` are unchanged.
The current seam supports explicitly scoped BINS contributions; automatic
CONFIG/keybinding context attachment is a separate integration checkpoint.
Do not globally enable it on context-aware deployments before those mappings
are provided: an old unscoped CONFIG installer may internally default to user
context, despite participating in the legacy system compositor.

## Declaration

```yaml
ACTION_AUDIENCES:
  default: user
  available: [user, system]
  actions:
    install: false              # omit this public action
    assemble:
      available: [user]         # restrict this action
    build:
      default: system           # explicitly allow the bare system shortcut

BINS:
  - name: assemble-personal.sh
    action: assemble
    scope: user
    content: echo assemble personal receiver
  - name: assemble-host.sh
    action: assemble
    scope: system
    content: echo assemble host receiver
```

`ACTION_AUDIENCES: {}` enables the user-default policy with both audiences
allowed. `available` is a list; `actions` is a mapping of action names to
`false` or `{default, available}` overrides. Per-action availability can narrow,
but cannot expand, the global allowed set. Explicitly declaring a default
outside that declaration's allowed set is an error.

Actual availability also requires contributed work. **No user-to-system
fallback occurs.** A user-default action with only system work emits
`ACTION-system.mjs`, but no bare `ACTION.mjs`. Setting that action's
`default: system` enables the bare shortcut. Empty placeholder roots do not
invent successful empty plans.

The opt-in vocabulary is `build`, `install`, `apply`, `config`, `assemble`,
`publish`, `sync-inputs`, and `inputs`. This does not expand legacy
`BIN_ACTIONS`. Existing `status.sh` keeps its separate reporting contract.

## Selection and output

With both audiences available and user default:

```text
bin/assemble-user.mjs                # one real, tiny JavaScript entry
bin/assemble.mjs        -> assemble-user.mjs
bin/assemble-system.mjs -> assemble-user.mjs
bin/compfuzor-runtime.mjs             # one shared bundled implementation
etc/compfuzor-actions/spec.json       # plans and available alias spellings
```

The real filename supplies the default. A qualified **invoked spelling**
asserts its audience before symlink resolution erases that spelling. The
physical entry supplies the deployment root, not cwd or ambient `DIR`.
Unknown names, omitted audiences/actions and stale entries fail without
falling back. External same-name symlinks are allowed and still use the real
deployment's material.

There is no generic `--audience` or environment override. Ordinary arguments
are forwarded unchanged. Existing domain CLI selection precedence is not
changed; audience/context validation belongs to each domain adapter, not a
universal flag scrubber. Merely tagging a legacy leaf does not make its
arbitrary flags or hardcoded receiver paths audience-safe.

Default changes update the newly declared real-file/symlink representations.
Omission does **not** prune old files. A current spec, including an empty
spec, rejects their execution through this interface. Availability is an
interface policy, not an access-control system: independently executable
low-level leaves and arbitrary shell bodies are not sandboxed.

## Composition and compatibility

- Existing `scope` partitions BINS leaves. Unscoped legacy leaves mean system;
  a portable leaf explicitly declares `[user, system]`. User suffix inference
  applies to all actions in this lane. Unknown audience scopes fail.
- Existing phase order, stable BINS order within phases and subsystem grouping
  are reused. Subsystems receive the same qualified action families.
- Pure aggregates execute sequentially in JavaScript. Selected child paths
  are physically contained in the deployment, but their lexical alias paths
  are executed. The selected graph is checked before the first child runs.
- Authored inline shell roots keep their original `.sh` path as internal body
  bridges. This preserves `$0`, `dirname($0)`, exported state, original
  `run_all`, helpers and body-local bypass semantics. A shared-runtime guard
  verifies that the current spec still claims the body before it executes.
  Existing guarded `late` blocks run **before** composed children, as before;
  the new compositor does not silently reorder them.
- Raw/source/Node authored roots are rejected rather than moved unsafely.
  Declare such work as a named composing leaf instead.
- Child cwd and `DIR` are deployment-rooted. `COMPFUZOR_ACTION_AUDIENCE` is
  exported to specifically audience-aware children; it does not rewrite
  arbitrary leaf bodies. Nonzero child exit codes are preserved and stop the
  aggregate. Interrupt/termination/hangup signals forward to the active process
  group and terminate the action with that signal.
- The catalog observes scoped public action entries and their plans. Its
  authority is `action-audiences`, read-only. Enabling the old unscoped native
  flow executor alongside this lane is rejected; it must not run both
  audiences accidentally.

This is a sequential action aggregate, not a new cross-domain transaction,
configuration assembler, privilege escalator or placement mode. CONFIG's
candidate commit and domain-specific activation remain their own operations.
Deployment material placement is unchanged.

## Implementation and tests

- [Controller compiler](/library/filter_plugins/action_audiences.py) — policy,
  alias families, original composer reuse and body-bridge claims.
- [Runtime](/files/actions/runtime.ts) and [entry adapter](/files/actions/entry.ts)
  — import-safe selection, graph admission and process outcomes.
- [Ansible wiring](/tasks/compfuzor/gen_bins.tasks) — mutually exclusive new and
  legacy composition; no global action-vocabulary expansion.
- [Controller tests](/tests/filter_plugins/action_audiences.test.py),
  [selection tests](/tests/action-audiences/selection.test.ts), and
  [isolated execution tests](/tests/integration/action_audiences.test.py).
- [Implementation checkpoint](/design/action-audiences/implementation0.gpt61sol.md)
  — exact implemented boundary, evidence and proposed domain integration.
