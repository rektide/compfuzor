# Audience action families

Compfuzor has an **opt-in** JavaScript action compositor. Without
`ACTION_AUDIENCES`, existing shell composition and `USERMODE` are unchanged.
It combines explicitly scoped BINS leaves with audience-bound **complete CONFIG
and keybinding operations**. Other context-selecting domains must still acquire
their own bindings before broad adoption; merely renaming an unscoped domain
installer does not make its internal defaults audience-safe.

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

There is no generic `--audience` or environment override. Ordinary exec children
receive forwarded argv. Typed domain operations instead parse domain options and
assert the effective spec/profile/context audience **before authored effects**.
Existing low-level domain CLI precedence remains compatible. There is no universal
flag scrubber; a flag valid for CONFIG can be invalid for another selected domain.
Use a focused family such as `assemble-config.mjs` or
`assemble-keybindings-niri.mjs` when options only apply to that subsystem.

## Domain bindings

CONFIG attaches `assemble`, `publish`, `sync-inputs`, `inputs` and config-owned
`install`. An audience binds automatically only when exactly one noncanonical
declared context has that scope. Resolve ambiguity explicitly:

```yaml
CONFIG_CONTEXT: desktop              # existing low-level default
CONFIG_ACTION_CONTEXTS:
  user: desktop
  system: host
```

Context names are arbitrary; an audience is not a context name. Canonical donor
assembly stays available through the existing low-level CONFIG interface, not as
a system receiver install. `CONFIG_INSTALL_OWNER` suppresses duplicate generic
CONFIG install contributions when another domain owns installation.

Keybinding hosts attach complete install and host assembly; generic `assemble`
asserts native placement mode `assemble`, while install retains seed behavior.
Producer install uses a complete typed **`install-offer` batch** with exact manifest,
owner-held receiver selection and registry policy. It retains source registration
and membership through each consumer's CONFIG commit/rollback boundary. Declaring
both roles admits packaged prospective consumers before bodies and bootstraps owned
hosts before delivering the frozen producer batch; no late registry rescan widens it.

Owned consumer contexts infer uniquely per scope. Use `action_contexts` for
ambiguity; an external target uses it to **declare**, not discover, audiences:

```yaml
KEYBINDING_CONTEXT: desktop          # existing low-level host default
KEYBINDING_CONSUMERS:
  niri:
    contexts:
      desktop: {scope: user, root: config, subpath: niri}
      alternative: {scope: user, root: config, subpath: other-niri}
      host: {scope: system, root: /etc/niri}
    action_contexts: {user: desktop, system: host}

KEYBINDING_TARGETS:
  niri:
    consumer: {env: CONSUMER_PROFILE}
    context: desktop
    scope: user
    action_contexts: {user: desktop, system: host}
```

Without an external mapping, the existing receiver `context`/`scope` pair declares
one audience. Receiver requests are filtered by audience before lookup. The controller
does not fetch arbitrary external profiles. Actual registry identity/participation,
profile adapter/context/scope assertions happen at invocation before body effects.
Consumers' mappings govern their host operations; target mappings govern producer
delivery. Host ambiguity still requires its own explicit mapping.

`KEYBINDING_TARGETS` names receiver IDs, not native formats. An external profile
override does not advertise a missing receiver. Without explicit targets a pure
producer selects all compatible active advertised consumers; `[]`/`{}` means no
native delivery. A host per-receiver family remains distinct from the producer's
single `install-keybindings` offer family. In a combined action repeated `--target`
narrows producer receiver delivery without changing owned host native formats.

Native and passive keybinding entries accept `--registry-policy PATH`. Generated
`KEYBINDING_REGISTRY_POLICY` emits an owned version-1 document with an `audiences`
mapping, each selected audience requiring both provider and consumer roots/writeRoot.
The bound pair and same captured bytes are reused for selection, owner publication
and guards; missing sides refuse fallback. Relative selectors use the document's
physical directory. Use explicit disposable pairs for SYSTEM tests; HOME/native-root
isolation alone does not isolate default `/var/lib`/`/etc` rendezvous collections.
See the [registry interface](/runtime/registry/README.md#combined-first-install-and-custom-policy-pairs).

Explicit same-audience contexts or profiles may override a domain default if all
selected operations accept them. Other-audience overrides, different declared
targets/producers, canonical receiver misuse and operation/mode switches fail
clearly. Recipe/strategy/input-command syntax is checked early too.

## Admission and authored work

Receiver IDs/profiles, registry roots, force policy, exact provider resources,
output/input bindings, placement selectors and delivery strategies
are resolved before authored effects. Later `HOME`, XDG, selector-environment,
strategy or argv changes cannot redirect those admitted domain operations.
Operational exports still reach execution and ordinary children. No adopted root,
generated input or native candidate is required merely to bind a context: authored
work can create those prerequisites before each complete operation validates/applies.

Every selected domain binding is admitted even if an apply-time bypass will skip
its effects. Thus an invalid audience/profile fails early under bypass in the
**new general interface**. Existing low-level wrapper skip behavior is unchanged.

Typed graphs use an invocation-private, versioned JSON transport: one owner,
private `0700` directory / `0600` files, at most 128 selected operations/actions,
and bounded payloads. It belongs to the physical deployment, current action graph,
audience and live owner process ancestry (Linux `/proc`). It is not a durable
workflow, registry, replay token, locking layer or privilege broker. Success,
failure and handled signals clean it up. Pure exec-only graphs do not create it.

Preparation uses only verified env/variable/cwd setup, never early/content/generated/
late blocks or a child loop. Trusted `env.export` remains executable shell code;
preparation is **not globally effect-free**. Root setup is captured once and reused
by the body, avoiding a second root source. Subsystem setup and existing keybinding
apply envelopes keep their normal environment sourcing/bypass behavior. Domain
selection is already frozen when those later sources run.

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
  are executed. They must be regular executable files. The selected graph is
  checked before the first child runs.
- Authored inline shell roots keep their original `.sh` path as internal body
  bridges. This preserves `$0`, `dirname($0)`, exported state, original
  `run_all`, helpers and body-local bypass semantics. A shared-runtime guard
  verifies that the current spec still claims the body before it executes.
  Typed bodies execute their children through one shared runner, not through
  both the old loop and JavaScript. Direct body invocation redirects to its
  qualified action to establish the same admission barrier.
  Existing guarded `late` blocks run **before** composed children, as before;
  the new compositor does not silently reorder them.
- Raw/source/Node authored roots are rejected rather than moved unsafely.
  Declare such work as a named composing leaf instead.
- Entry rooting and `DIR` are physical-deployment based. Ordinary children under
  a body inherit its cwd; nested action aggregates retain their own setup.
  `COMPFUZOR_ACTION_AUDIENCE` is
  exported to specifically audience-aware children; it does not rewrite
  arbitrary leaf bodies. Nonzero child exit codes are preserved and stop the
  aggregate. Interrupt/termination/hangup signals forward to the active process
  group and terminate the action with that signal.
  Private session/operation markers are cleared from unrelated ordinary children
  and from complete operations' workers/native validators.
- The catalog observes scoped public action entries and their plans. Its
  authority is `action-audiences`, read-only. Enabling the old unscoped native
  flow executor alongside this lane is rejected; it must not run both
  audiences accidentally.

This is a sequential action aggregate, not a new cross-domain transaction,
configuration assembler, privilege escalator or placement mode. CONFIG's
candidate commit and domain-specific activation remain their own operations.
Audience selection itself does not choose material placement.
An offer batch is not a cross-receiver transaction: earlier receiver successes
remain if a later native validation fails. Producer advertisement can remain after
native rejection. Registration is not native activation or accepted membership.

## Adopted playbook defaults: material versus receiver

`niri.etc.pb`, `umbriel.etc.pb` and `media-keys.etc.pb` now use the existing
`PREFIX_DIR`/`DIR`/`ETC` primitives for grouped home-local material:

```text
${XDG_DATA_HOME:-$HOME/.local/share}/compfuzor/etc/<NAME>/
  bin/                 # runtime/action entries
  etc -> .             # existing etc-type structural exposure
  keybinding-*.json    # host profile, or producer manifest/declarations
```

Niri/Umbriel keep stable host NAMEs `niri` and `umbriel`. Producer NAME/group
identity follows its declaration (or explicit NAME/KEYBINDING_PRODUCER override),
independently from where material is stored. Existing prefix-level `env.NAME`
exposures remain inside this XDG-data material group.

The live receivers remain `${XDG_CONFIG_HOME:-$HOME/.config}/{niri,umbriel}`.
Generation is not adoption/registration: install is deliberate. No material-root
API or global USERMODE flip was introduced. For these user-only receiver profiles,
the emitted public families are `install-user.mjs`/`install.mjs` and
`assemble-user.mjs`/`assemble.mjs`; no system-qualified host aliases are fabricated.
The producer owns install/registration, not a synthetic host assemble operation.

Shared material is an explicit existing override:

```sh
ansible-playbook -i 'localhost,' -c local niri.etc.pb -e PREFIX_DIR=/etc/opt
export COMPFUZOR_NIRI_PROFILE=/etc/opt/niri/etc/keybinding-niri.json
/etc/opt/niri/bin/register-keybindings-consumer-niri-user.sh
```

`COMPFUZOR_NIRI_PROFILE` and `COMPFUZOR_UMBRIEL_PROFILE` are consumer-owned profile
selectors, not shared Media Keys/Vicinae discovery defaults. Those producers look up
advertised descriptions. A foreign existing same-ID owner reference requires deliberate
operator reconciliation or a distinct ID/policy; it is never silently retargeted.
Vicinae retains its existing build, source placement and service installers. Shared
material alone does not enable a system receiver.

SteamOS keeps persistent `/opt/steamos-niri-main` material. Its bare `install.mjs`
means user configuration; `install-system.mjs` selects readonly/package provisioning.
`assemble.mjs` is user assembly, with no invented system Niri fallback. Node must
already be available to execute `.mjs` entrypoints. Session switching remains an
explicit separate command; no workstation SteamOS commands were executed in tests.

See [producer/consumer operator examples](/doc/config/keybinding-producers.md#home-local-consumer-and-producer-example)
for deliberate adoption and migration, and the
[final implementation checkpoint](/design/action-audiences/implementation2.gpt61sol.md)
for placement proof and limitations. Old live material is never auto-moved/pruned;
this repository implementation does not itself migrate a live desktop.

## Implementation and tests

- [Controller compiler](/library/filter_plugins/action_audiences.py) — policy,
  alias families, original composer reuse and body-bridge claims.
- [Runtime](/files/actions/runtime.ts), [operation adapter](/files/actions/operations.ts),
  [private transport](/files/actions/session.ts) and [entry adapter](/files/actions/entry.ts)
  — selection, shared domain admission/execution and process outcomes.
- [Ansible wiring](/tasks/compfuzor/gen_bins.tasks) — mutually exclusive new and
  legacy composition; no global action-vocabulary expansion.
- [Controller tests](/tests/filter_plugins/action_audiences.test.py),
  [selection tests](/tests/action-audiences/selection.test.ts), and
  [isolated execution tests](/tests/integration/action_audiences.test.py).
- [Domain mapping tests](/tests/filter_plugins/action_contexts.test.py) and
  [compiled mixed-domain tests](/tests/integration/action_domains.test.py).
- [Domain implementation checkpoint](/design/action-audiences/implementation1.gpt61sol.md)
  — implemented boundary, evidence and next placement/adoption proposal.
- [Placement/adoption proof](/tests/integration/action_placement.test.py) — real
  playbook defaults without DIR/ETC overrides, full user install, explicit shared
  selection and both audiences from one home-local profile fixture.
