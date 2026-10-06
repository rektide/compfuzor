---
type: ImplementationCheckpoint
title: General action audiences — implementation admission
description: Proposed first implementation seam, minimal opt-in declaration and staged CONFIG/keybinding integration, awaiting architectural authorization.
resource: /design/action-audiences/implementation-plan0.gpt61sol.md
status: draft
generated: { by: model:gpt61sol, at: 2026-10-06 }
verified: { by: unverified }
sources:
  - resource: /design/action-audiences/action-audiences0.gpt61sol.md
    title: Accepted general direction, with schema still open
  - resource: /library/filter_plugins/bin_composers.py
    title: Existing leaf classification, scope partitioning and phase order
  - resource: /files/runtime/compfuzor-runtime.ts
    title: Shared Node-compatible bundled runtime and lexical alias selection
  - resource: /library/filter_plugins/config_context_compile.py
    title: CONFIG fixed actions, arbitrary named contexts and install ownership
  - resource: /library/filter_plugins/keybindings_compile.py
    title: Current host/producer installers and scope-bound CLI arguments
---

# Admission checkpoint — not yet implemented

The accepted direction is a general user-first interface with one real
default-qualified JavaScript action file and aliases, while preserving different
user/system effects, existing CONFIG transactions, home-local material and legacy
`USERMODE`. `.mts` is optional; the existing Node 20.19-compatible bundled `.mjs`
runtime is the preferred implementation/distribution lane.

Source inspection confirms that the hard decisions are leaf partitioning, domain
context binding and deployment rooting—not TypeScript execution. No live operation
or implementation edit has been performed. Existing working-copy changes include
CONFIG registration tests/code, Rust-storage work and several unrelated deletions;
these are excluded from this work's commits.

# Proposed minimal declaration

One **opt-in audience policy** activates the new composition lane; absence preserves
legacy output and behavior:

```yaml
ACTION_AUDIENCES:
  default: user                    # omitted => user
  available: [user, system]         # omitted => both; filters supported plans
  actions:
    install: false                 # omit this public action entirely
    assemble:
      available: [user]            # per-action restriction
      # default: system            # optional per-action default
```

These are proposed names, not an accepted schema. Availability is the intersection
of policy and actual contributed plans. A user-first default chooses user when
present, otherwise the sole supported system audience; explicitly choosing an
unavailable default is an error. No empty success plan or implicit fallback from an
explicit audience is generated. Omission is not runtime bypass: existing leaves
continue to own their bypass/no-op behavior. No stale-file pruning is added.

Use existing BINS `scope` to partition contributions (`user`, `system`, or both).
Unscoped legacy leaves mean **system**, not “safe for either audience”; a portable
leaf explicitly uses `scope: [user, system]`. Extend audience suffix inference to
all recognized actions, not only install. Reject unknown scopes in this new lane
rather than silently assigning system operations to a user plan. Existing arbitrary
legacy scopes remain accepted in the unchanged legacy lane.

The generic vocabulary initially reuses `build/install/apply/config` and adds
`assemble/publish/sync-inputs/inputs` for domain contributions. Do not steal the
existing top-level `status.sh` reporter's namespace in the first slice; read-only
CONFIG status continues through its current command until status aggregation has
an explicit contract.

# Concrete first slice: generator + invocation + sequential execution

Introduce domain-grouped action source under `files/actions/` and its controller
compiler under `library/filter_plugins/`. Reuse the current leaf classifier,
subsystem grouping, contributor attribution and stable phase ordering rather than
inventing a second scheduling model. New mode generates action plan data and
JavaScript entries instead of scope shell compositors:

```text
bin/install-user.mjs                # real, tiny executable
bin/install.mjs       -> install-user.mjs
bin/install-system.mjs -> install-user.mjs
bin/compfuzor-runtime.mjs           # existing sole bundled runtime
etc/compfuzor-actions/spec.json     # audience plans, no executable source
```

The generated real entry imports an exported action entry adapter from the shared
runtime and passes its own `import.meta.url`. This preserves the requirement of
one real action file without copying the omnibus bundle per action or incorrectly
encoding the default in a symlink whose final file is named `compfuzor-runtime.mjs`.
Subsystem aggregates can use the same family, e.g. `install-systemd-user.mjs`.
The plan record carries the aggregate identity, so names are validated against
declarations rather than guessed through ambiguous hyphen splitting.

Selection retains separate facts:

1. `process.argv[1]`: lexical invoked name; a qualified name asserts user/system.
2. `realpath(entry URL)`: actual default-qualified action file; names the default
   and establishes physical deployment `bin/..`, independent of cwd or inherited
   `DIR`.
3. Compiled plan: validates the action identity, supported audiences and leaves.

For the new generic entrypoint, qualified aliases are hard audience assertions.
Do not introduce an environment audience override or `--audience` in this first
slice: the aliases already provide an unambiguous interface. Existing low-level
CONFIG/Zim explicit-context precedence remains unchanged. When a general action
passes context options to a domain, reject overrides that escape its selected
audience, rather than allow `assemble-system.mjs --context user` to mutate user
roots. Choosing another **same-audience** context needs explicit domain support,
not universal argument interpretation.

Execution is a sequential aggregate, not a new universal transaction. Legacy
shell leaves stay executable children with original helper/bypass bodies. Child
processes receive a deployment-rooted `DIR`, deployment cwd and forwarded ordinary
arguments; physical containment is verified while the lexical child alias path
is executed (as in the existing flow regression fix). Stop on failure. Export the
selected audience for specifically audience-aware children, but do not infer that
an arbitrary leaf body becomes audience-safe because of that environment value.

Authored aggregate bodies such as SteamOS's `install.sh` and `install-user.sh`
must not disappear. Preserve them as private body leaves before their composed
children, with audience-specific bodies and bypass behavior. This needs explicit
tests against real declaration shapes; merely copying `run_all` would drop work.

Update catalog projection to observe the new aggregate plans and aliases without
claiming that the experimental native flow runner is the new action executor.
Maintain legacy catalog/flow behavior when the new lane is absent.

# Next coherent slice: domain operations attach to general actions

CONFIG contributes complete operations for each supported audience/context:
`assemble`, `publish`, `sync-inputs`, `inputs` and config-owned `install`.
One noncanonical context of each scope may bind automatically; multiple contexts
of the same audience require an explicit mapping rather than choosing by order or
assuming the context is literally named user/system. Proposed mapping lives next
to domain declarations, e.g. `CONFIG_ACTION_CONTEXTS: {user: desktop, system: host}`.
Canonical source assembly does **not** become a system installation context.
`CONFIG_INSTALL_OWNER` still prevents generic CONFIG install duplicating a domain
installation such as Zim.

Keybinding hosts contribute `assemble` using the existing complete host assembly
operation with native placement mode `assemble`; installation continues to seed
via its existing host/producer operation. Per-audience context mappings select
different receiver roots from the profile. Producer install still performs
registration/membership with CONFIG rollback and commit semantics. Producers do
not silently gain a host-only assembly operation with unrelated membership.

General actions can sequentially run both an ordinary CONFIG operation and a
keybinding operation, each owning its existing transaction. They are not one
combined candidate set. No nested committing consumer operation will be invoked
as a CONFIG processor. A future shared candidate transaction would require the
separately accepted preparation extraction, not an unannounced change here.

Zim keeps its complete installation operation (loader/cache/registry work), and
can contribute explicit context-selected leaves without reducing installation to
CONFIG assembly. Existing `config-*.sh`/`install-zim.sh`/`keybindings.mjs` remain
compatibility/internal endpoints, not the normal new-mode operator interface.

# Home-local deployment material is a separate choice

Recommend a separate `MATERIAL_ROOT` placement declaration, e.g.:

```yaml
MATERIAL_ROOT: "{{ HOMEDIR }}/.local/share/compfuzor"
```

Bind only rendered deployment material to
`MATERIAL_ROOT/<type>/<NAME>` with `bin/`, `etc/`, env and declared artifacts
beneath it. Do not rewrite system receivers, privilege routing, service managers,
package operations, source checkout conventions or all hierarchy globals. New
audience mode and home-local material can be adopted together in appropriate
playbooks, while shared deployment material remains available explicitly.
Legacy `USERMODE` remains unchanged. No old deployment is moved or cleaned up.

This requires checking existing DIR/ETC hierarchy exposures carefully: setting
only `DIR` today does not guarantee that an opt deployment's ETC material leaves
`/etc/opt`. The first integration checkpoint should show a complete home-local
render and a different system operation using those same materials.

# Verification and next authorization

First authorize or adjust the declaration/selection seam above. Then implement:

1. Compiler and import-safe invocation/execution with default user/system families,
   unavailable audiences/actions, stale aliases, symlink-chain identity, cwd/root
   safety, scheduling and authored-body preservation; commit and checkpoint.
2. CONFIG/keybindings complete-operation contributions and mixed-scope tests;
   checkpoint the actual context/operation interfaces before broad adoption.
3. Narrow placement support, representative opt-in playbooks and maintained docs;
   isolated renders/runs only. No desktop reload, service restart or live migration.

The first slice makes real JavaScript action families and different user/system
plans possible. It does not by itself solve home-local deployment material,
domain-context mapping or cross-domain transaction unification. Those differences
remain visible, not hidden behind an action filename.

# Cross-references

- [Accepted direction](/design/action-audiences/action-audiences0.gpt61sol.md):
  constraints; this checkpoint proposes implementation decisions absent there.
- [CONFIG stage evidence](/design/action-audiences/config-stages0.gpt61sol.md):
  assembly/publication/install differences and why complete operations are reused.
- [Alias evidence](/design/action-audiences/action-variants0.gpt61sol.md): lexical
  alias versus physical identity, bundling compatibility and prior flow behavior.
- [Bin composer](/library/filter_plugins/bin_composers.py): existing phase/scope
  mechanics to retain, with legacy behavior outside the opt-in lane.
- [Shell bin template](/files/_bin): authored body, forwarded argv, deployment
  rooting and body-local bypass semantics that a replacement must preserve.
- [Runtime catalog compiler](/library/filter_plugins/runtime_catalog.py): current
  legacy-root projection must learn about new aggregates without erasing old flows.
- [SteamOS Niri playbook](/steamos-niri.opt.pb): distinct system provisioning and
  user adoption bodies, not interchangeable installs.
