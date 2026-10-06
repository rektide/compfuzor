---
type: ImplementationCheckpoint
title: Domain admission foundations and the authored-body bridge gate
description: Verified CONFIG/keybinding admission seams, plus the proposed minimal mapping and shared prepared-operation transport awaiting architectural review.
resource: /design/action-audiences/domain-admission0.gpt61sol.md
status: draft
generated: { by: model:gpt61sol, at: 2026-10-06 }
verified: { by: model:gpt61sol, method: targeted-source-and-isolated-runtime-tests }
sources:
  - resource: /design/action-audiences/implementation0.gpt61sol.md
    title: Accepted first implementation checkpoint, not full task completion
  - resource: /files/config/runtime.ts
    title: Factored CONFIG selection/admission and complete execution
  - resource: /files/config/keybindings/runtime.ts
    title: Factored keybinding profile/context admission and complete execution
  - resource: /files/_helpers/env
    title: Existing shell environment setup that a domain adapter cannot silently bypass
  - resource: /files/_bin
    title: Authored bodies currently own their composed child invocations
---

# Situation and gate

The parent authorized CONFIG/keybinding domain integration, with typed complete
operations, whole-graph admission and original shell-body/environment/bypass
semantics. Two small foundations are committed. **The typed plan schema and its
shell-bridge transport are not implemented yet.** The remaining choice is
consequential enough to report before committing it, as requested.

No live configuration/service operation, material-placement change, playbook
adoption or push occurred. Existing pending registration edits remain untouched
and excluded from the rebuilt omnibus artifact.

# Committed foundations

- `94d6d15e` — CONFIG admission/execution seam and regular executable admission.
  [`admitConfigCommand`](/files/config/runtime.ts) loads/selects the effective
  spec/action/context without effects. An optional `ConfigActionBinding` asserts
  operation and audience, rejects canonical donors and incompatible installation
  ownership, and permits named same-audience context overrides. The loaded
  selection is reusable by `runAdmittedConfigCommand`; raw CONFIG dispatch retains
  its existing precedence and operations.
- `4bd2cd1c` — keybinding profile admission separated from complete operations.
  [`admitKeybindingCommand`](/files/config/keybindings/runtime.ts) loads the actual
  profile/selector and manifest, checks effective context/scope/target/role, and
  binds concrete receiver paths without registration, membership or output writes.
  `runAdmittedKeybindingCommand` reuses that state. Shared
  [`bindProfile` and manifest validation](/files/config/keybindings/membership.ts)
  avoid copying the domain's binding rules into actions. Complete producer install,
  host assembly and toggling still own their existing transactions.

Current internal binding types are not new playbook declarations:

```text
CONFIG:     {action, audience, context}
keybinding: {command: host|install, target, audience, context,
             mode?: assemble, producer?: declared group ID}
```

The host assembly binding asserts `mode: assemble`; it cannot silently become
seed/refresh installation. Raw host CLI still defaults to seed. Producer binding
can assert the declared producer ID; it is not replaced by host-only assembly.
CONFIG's seam currently admits selection and irrelevant-flag checks; remaining
pure recipe/strategy/action-specific checks must move into admission before a typed
plan record is marked fully ready. Native/root/input validation remains inside
the complete operation where it can observe prerequisites produced by the body.

The action executor now requires physically contained **regular executable files**,
not merely successful `realpath`. A later directory or non-executable leaf fails
before an earlier leaf's effects.

## Changed code/test paths

- [`files/actions/runtime.ts`](/files/actions/runtime.ts)
- [`files/config/runtime.ts`](/files/config/runtime.ts)
- [`files/config/keybindings/runtime.ts`](/files/config/keybindings/runtime.ts)
- [`files/config/keybindings/membership.ts`](/files/config/keybindings/membership.ts)
- [`runtime/compfuzor-runtime.mjs`](/runtime/compfuzor-runtime.mjs)
- [`tests/action-audiences/config-admission.test.ts`](/tests/action-audiences/config-admission.test.ts)
- [`tests/action-audiences/keybinding-admission.test.ts`](/tests/action-audiences/keybinding-admission.test.ts)
- [`tests/integration/action_audiences.test.py`](/tests/integration/action_audiences.test.py)

# Proposed minimum declaration and plan schema — not committed

`CONFIG_ACTION_CONTEXTS: {user: desktop, system: host}` is already approved.
Infer only one noncanonical context per participating audience; explicit mappings
resolve ambiguity and must agree with declared scope. Preserve the raw
`CONFIG_CONTEXT` default contract separately from generic audience defaults.

For keybindings, existing owned profile `contexts` can already represent both
audiences. Infer unique owned contexts without adding another user-level mapping.
Use one optional **`action_contexts` audience→context mapping**, only where needed:

```yaml
KEYBINDING_CONSUMERS:
  niri:
    contexts:
      desktop: {scope: user, root: config, subpath: niri}
      alternate: {scope: user, root: config, subpath: other-niri}
      host: {scope: system, root: config, subpath: niri}
    action_contexts: {user: desktop, system: host}  # resolves same-scope ambiguity

KEYBINDING_TARGETS:
  niri:
    consumer: {env: DESKTOP_CONSUMER_PROFILE}
    context: desktop             # existing low-level installer default
    scope: user                  # existing low-level installer scope
    action_contexts: {user: desktop, system: host} # explicitly declares both plans
```

For an external consumer, retain the existing single `context`/`scope` pair when
no new mapping is supplied. Do **not** read/infer arbitrary external profile
availability on the controller. Explicit mappings are conditional assertions
validated against the effective profile at invocation. Missing default-audience
work still gives no bare shortcut. Omission remains audience policy, not mapping
magic. Profiles with arbitrary names still need a truthful low-level default;
do not rewrite all `CONTEXT_DEFAULT`/`KEYBINDING_CONTEXT` semantics implicitly.

Domain compilers can attach internal `action_operations` contributions to their
existing compatible BINS records. This retains contribution order/attribution
without new standalone wrappers per operation/context. The generic compiler
turns them into a typed domain step, conceptually:

```text
kind: domain
id: keybindings:niri:assemble:user
domain: keybindings
operation: host
binding: {target: niri, audience: user, context: desktop, mode: assemble}
defaults: declared profile selector / manifest / worker bindings
envelope: existing generated installer path, if it owns shell setup/bypass
```

CONFIG contributes complete assemble/publish/sync-inputs/inputs and config-owned
install operations. Keybinding hosts contribute install and assemble; producers
contribute complete producer install. No mandatory assemble→publish pipeline and
no committing consumer is hidden inside a CONFIG candidate processor.

# Recommended bridge solution

Merely putting a typed step into the current shell root's `run_all` is insufficient:
the body executes its children, and a second JavaScript executor would double-run
them. Also, directly calling a domain runtime instead of its existing shell
installer loses that installer's environment setup and bypass/report semantics.

Recommend one **invocation-private prepared action session**, owned/cleaned by the
outer general action runtime, with JSON data rather than generated executable code:

1. Select and validate the complete audience graph, including regular executable
   checks. Collect every selected domain operation, also beneath body bridges.
2. Admit every domain operation before authored work. Reuse the factored domain
   functions and retain their loaded spec/profile/context/bound receiver state.
   For keybinding shell envelopes, a preparation mode runs their existing
   environment setup, then calls the shared adapter **before** authored content or
   installation. This avoids reimplementing shell env/default/bypass primitives
   in a universal TypeScript flag/environment parser.
   CONFIG's fixed aliases do not source env themselves: reuse one shared internal
   environment-preparation envelope where the legacy aggregate supplied that
   setup. Respect the aggregate's helper/env opt-outs. Apply beneath an authored
   body using its inherited exports, rather than sourcing the root env file again
   and changing existing overwrite semantics. No per-context wrapper is needed.
3. Store prepared operation records in a private `0600` invocation session. Domain
   selection is sealed: operation, effective context/audience, profile/spec and
   parsed domain flags are not rediscovered after provisioning/adoption effects.
   Nested qualified action aliases inherit that session and validate their spelling
   against the selected graph; they must not start a second late admission pass.
4. A root body still runs in its original `.sh` file, with original helpers,
   `$0`, exported state, bypass and `late` ordering. Replace only its generated
   child loop with **one shared `actions children` call**. That process inherits
   the body's exports and executes the already-admitted child plan exactly once.
5. A domain child applies its prepared operation through the shared adapter.
   Reuse an existing shell envelope where its helpers/bypass matter; do not create
   a new public command for each context. Raw ordinary exec children still receive
   lexical paths/argv; a domain invocation instead receives a prepared operation
   identity. These are intentionally different contracts.
6. Clear operation-specific transport markers before complete domain execution,
   so CONFIG processors and keybinding closure-validator calls remain ordinary
   domain calls rather than recursively reapplying the parent operation.

The dispatcher remains shallow: `actions` adapter owns session/child routing;
domain-local modules own admission/execution. Domain modules do not import the
action dispatcher, avoiding dependency cycles.

Direct invocation of an internal authored shell bridge can redirect to its
qualified public `.mjs` action when no prepared session exists. This preserves
the old shell filename while ensuring the same pre-effects admission barrier,
without another session owner or an unprepared child-execution path.

## Compatibility tension to settle

To guarantee audience admission **before effects**, context/spec/profile selection
and parsed domain flags must not be rewritten by later authored body exports or
`set --`. Body exports still reach ordinary child execution, helpers, bypass and
non-selection process environment. Declared domain operations reuse their admitted
selection rather than reparse arbitrary late argv/environment.

Likewise, every selected domain's binding needs admission even if a later runtime
bypass will skip its effects. CONFIG already loads/selects its spec before install
bypass; a keybinding shell wrapper currently can bypass before reading its profile.
The general plan would therefore reject an invalid audience/profile declaration
early even under bypass, while retaining the wrapper's actual apply-time skip and
report behavior. This is a new plan-interface assertion, not a low-level CLI change.
Please confirm this distinction rather than silently weakening the admission barrier.

Environment preparation uses existing trusted generated shell setup, not a sandbox
for arbitrary authored `env.export` code. It does not run the install body, mutate
membership, assemble outputs or publish CONFIG artifacts. Whole-action admission
still does not promise that later native validation or every transaction will
succeed; it is not crash atomicity or a cross-domain transaction.

# Evidence

- CONFIG bound-admission tests: **3 passed**. Effective explicit/environment/spec
  scope escapes, operation mismatch, canonical/ownership misuse fail without
  effects; named same-audience overrides and reuse of loaded state work.
- Keybinding admission plus existing consumer/domain tests: **3 files / 22 tests
  passed**. Arbitrary named contexts, profile/env-selector/scope/target/mode escapes,
  producer identity/lifecycle, raw seed default and serializable bound state.
- Node **20.19.0** generated action integration passes, including directory and
  non-executable rejection before earlier effects.
- Existing fixed CONFIG command integration passes, preserving low-level selection,
  alias and precedence contracts.
- Existing generated keybinding producer integration passes under Node **20.19.0**:
  two producers, native/overlay composition, source/material policies, reduced
  membership, rollback and durable disable. Its first 120-second attempt timed out;
  a longer isolated run completed successfully.
- Typecheck, targeted lint/format pass. Bundle builds remain isolated from unrelated
  pending registration edits as in the previous checkpoint.

# Next authorization / remaining work

Please review the `action_contexts` addition and prepared-session/body-child
contract above before their schema/transport implementation is committed.
Then attach CONFIG/keybinding contributions, implement private admission/apply
routing, and prove named user/system complete operations beneath real generated
aggregates—especially an invalid later domain context blocking earlier authored
effects and no double execution beneath shell bodies.

Placement/adoption remain deferred. This checkpoint is **partial slice 2**, not
completion of the user's whole implementation request.

# Cross-references

- [Accepted first checkpoint](/design/action-audiences/implementation0.gpt61sol.md):
  original-path body bridge, sequential aggregation and remaining context gap.
- [CONFIG stages](/design/action-audiences/config-stages0.gpt61sol.md): existing
  complete operations and transaction boundaries that preparation must retain.
- [Shell env helper](/files/_helpers/env): why pure in-process replacement would
  lose deployment environment setup for current generated keybinding installers.
- [Generated keybinding installer](/library/filter_plugins/keybindings_compile.py):
  current one-context external target declaration and original wrapper contract.
