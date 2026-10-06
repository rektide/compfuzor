---
type: ImplementationCheckpoint
title: Complete audience-bound CONFIG and keybinding action integration
description: Implemented typed domain contributions, frozen receiver admission, original body/envelope reuse and private invocation cleanup; placement/adoption remains unauthorized.
resource: /design/action-audiences/implementation1.gpt61sol.md
status: draft
generated: { by: model:gpt61sol, at: 2026-10-06 }
verified: { by: model:gpt61sol, method: source-review-controller-tests-and-isolated-generated-execution }
sources:
  - resource: /design/action-audiences/domain-admission0.gpt61sol.md
    title: Approved mapping and prepared-session/body-child direction
  - resource: /files/actions/runtime.ts
    title: Shared typed execution and single body child runner
  - resource: /files/actions/session.ts
    title: Bounded invocation transport and ownership validation
  - resource: /tests/integration/action_domains.test.py
    title: Named user/system receivers, multiple targets, overrides, producer membership and cleanup evidence
---

# Outcome

**Authorized domain integration is complete.** CONFIG and keybinding complete
operations attach to generated audience action families. All selected domain
bindings/options/receiver selectors/strategies admit before authored effects;
authored bodies can then create adopted roots and input prerequisites.

No live desktop/configuration/service changes, migrations, placement implementation
or pushes occurred. No real playbook was opted in. Legacy `USERMODE` remains intact.
Unrelated working-copy edits were excluded from source commits and the runtime
bundle. This is not final delivery of the user's placement/adoption goal.

## Commits

- `33147988` — working typed contributions, frozen receiver/strategy binding,
  prepared operation transport and generated mixed-domain execution.
- `26b7ae78` — live-owner/deployment/graph validation, setup-only body preparation,
  signal cleanup, original envelope provenance and external producer coverage.
- `bb415efa` — completed pure option admission and generated publish/sync/input
  operation coverage, plus shared cwd resolution.

The earlier admission foundations remain at `94d6d15e` and `4bd2cd1c`.

# Schema and public interface

Existing `ACTION_AUDIENCES: {default, available, actions}` remains the only general
audience policy. One real default-qualified `.mjs` and symlink aliases remain the
public action family. There is no public operation/context wrapper matrix.

Domain mappings are:

```yaml
CONFIG_ACTION_CONTEXTS: {user: desktop, system: host}

KEYBINDING_CONSUMERS:
  niri:
    action_contexts: {user: desktop, system: host}

KEYBINDING_TARGETS:
  niri:
    consumer: {env: CONSUMER_PROFILE}
    context: desktop
    scope: user
    action_contexts: {user: desktop, system: host}
```

Owned contexts infer only when unique per participating scope; explicit mappings
resolve ambiguity. Canonical CONFIG contexts never become receiver audiences.
External targets keep their existing single context/scope declaration unless both
audiences are explicitly mapped. The controller does not discover remote contexts;
effective profile/target/context/scope validation happens before body effects.
Existing raw defaults (`CONFIG_CONTEXT`, `KEYBINDING_CONTEXT`, target context/scope)
keep their meaning. Other domains' low-level CLI precedence is unchanged.

Compilers attach internal `action_operations` to compatible BINS records. The
generic composer reuses their ordering/subsystem/attribution and emits typed steps:

```json
{
  "kind": "domain",
  "id": "operation.1.install.user",
  "domain": "config",
  "operation": "install",
  "context": "desktop",
  "envelope": "bin/config-install.sh",
  "spec": "etc/config.spec.json"
}
```

Keybinding steps carry the target and declared profile selector, plus producer
manifest/identity when applicable. Host assembly asserts `mode: assemble`;
producer installation retains registration/membership. An owned host and external
producer destination remain different operations; identical owned installation is
not duplicated. `CONFIG_INSTALL_OWNER` suppresses generic duplicate config installs.

# Implemented boundary

- CONFIG attaches install/assemble/publish/sync-inputs/inputs as complete operations.
  It does not add a mandatory assemble→publish pipeline or another publisher.
- Domain admission freezes the effective loaded spec/profile/context, selected
  recipe/input arguments, receiver bindings, native placements/source selectors
  and strategies. Explicit/environment/spec/profile overrides cannot escape the
  chosen audience or declared operation/target/producer. Same-audience overrides
  remain possible where each selected domain accepts them.
- Malformed input put/remove commands, unknown recipes, invalid strategies and
  contradictory/ignored operation-specific flags fail before an earlier body.
  Admission does not require roots/inputs/candidates the body is supposed to create.
- An invalid audience/profile still fails early if apply-time bypass would skip
  it. Bypass effects/reporting remain in the original wrappers/domain operation.
- Complete domain transactions run sequentially; keybindings still delegates its
  one candidate commit to CONFIG. No committing consumer is nested inside a CONFIG
  candidate processor and no synthetic joint transaction is claimed.

## Body bridge and environment sequencing

Typed graphs collect every selected domain operation before effects. Preparation
runs only the root's verified env/variable/cwd setup, never arbitrary helpers,
early/content/generated/late blocks or a child loop. `env.export` is trusted shell
code, so this is not globally effect-free preparation.

The original shell body keeps its filename, `$0`, exports, cwd, bypass and `late`
ordering. Root environment preparation is reused instead of sourcing that root
file twice. The body calls **one** shared `actions children` runner; it does not
also execute the old child loop. Nested aliases reuse admitted operations rather
than discovering contexts again after body work. Subsystem setup and original
keybinding apply envelopes retain their ordinary later environment sourcing.
Those sources can affect operational environment, but cannot redirect frozen
domain receivers/strategies. Ordinary children inherit body exports/cwd, while
physical deployment `DIR` and lexical alias identity remain protected.

Private markers are cleared from unrelated ordinary children and before complete
domain operations launch their CONFIG processors/native validators. Prepared
application verifies the appropriate domain alias rather than treating an ambient
operation marker as a raw CLI override.

## Private invocation transport

Only typed selected graphs allocate this transport; exec-only graphs remain
session-free. The owner creates one `0700` directory and `0600` JSON files under
the invocation temporary root. The explicit versioned schema stores the selected
operations, deployment, spec digest, action/audience graph and owner/directory
identity. Payloads are bounded to 8 MiB; the graph is bounded to 128 actions/operations.

Inherited data must match the physical deployment/current spec/selected graph and
audience, and remain beneath its live owner process ancestry (Linux `/proc`). It
is not a durable registry, replay engine, lock, transaction manager or privilege
broker. Success, ordinary failure and handled interrupt/hangup/termination clean
up the owner's directory. SIGKILL/crash cleanup is not promised.

# Exact changed paths

| Area | Paths |
|---|---|
| Controller mapping/contributions | [`action_contexts.py`](/library/filter_plugins/action_contexts.py), [`action_audiences.py`](/library/filter_plugins/action_audiences.py), [`config_context_compile.py`](/library/filter_plugins/config_context_compile.py), [`keybindings_compile.py`](/library/filter_plugins/keybindings_compile.py) |
| Ansible attachment/body setup | [`sub_config.tasks`](/tasks/compfuzor/sub_config.tasks), [`gen_keybindings.tasks`](/tasks/compfuzor/gen_keybindings.tasks), [`_bin`](/files/_bin), [`environment.sh`](/files/actions/environment.sh) |
| Shared runtime | [`model.ts`](/files/actions/model.ts), [`process.ts`](/files/actions/process.ts), [`operations.ts`](/files/actions/operations.ts), [`session.ts`](/files/actions/session.ts), [`runtime.ts`](/files/actions/runtime.ts), [`compfuzor-runtime.ts`](/files/runtime/compfuzor-runtime.ts) |
| Domain admission | [`config/runtime.ts`](/files/config/runtime.ts), [`cli.ts`](/files/config/cli.ts), [`inputs.ts`](/files/config/inputs.ts), [`keybindings/runtime.ts`](/files/config/keybindings/runtime.ts), [`membership.ts`](/files/config/keybindings/membership.ts) |
| Distributed artifact | [`compfuzor-runtime.mjs`](/runtime/compfuzor-runtime.mjs) |
| New/extended tests | [`action_contexts.test.py`](/tests/filter_plugins/action_contexts.test.py), [`config-admission.test.ts`](/tests/action-audiences/config-admission.test.ts), [`keybinding-admission.test.ts`](/tests/action-audiences/keybinding-admission.test.ts), [`action_domains.test.py`](/tests/integration/action_domains.test.py), [`action_audiences.test.py`](/tests/integration/action_audiences.test.py) |
| Maintained/navigation docs | [`doc/actions/README.md`](/doc/actions/README.md), [`doc/config/README.md`](/doc/config/README.md), [`inquiry index`](/design/action-audiences/index.md), this checkpoint |

# Evidence

- Full Vitest suite under `tests/`: **8 files / 38 tests passed**. The targeted
  admission suite was rerun after final pure-option changes: **3 files / 12 passed**.
- Generated mixed-domain integration passes under **Node 20.19.0**: named desktop/
  host user/system installs and assembly; CONFIG plus Niri/Umbriel; body-created
  roots/inputs; frozen HOME/XDG/placement/strategy choices; ordinary/validator exports;
  live body/domain bypass; no duplicate body execution; publish/sync/list/put;
  invalid later context and malformed input commands before earlier body effects.
- External-profile producer install passes for both mapped audiences, retaining
  registration/membership and frozen placement despite later selector exports.
- Private `0700`/`0600` files, unknown/stale/wrong-graph sessions, unrelated domain
  aliases, handled SIGTERM and native-transaction failure cleanup are exercised.
- Existing audience integration passes: both defaults, stale/omitted aliases,
  lexical execution, regular executable checks, exact exit/signal behavior and
  isolated full SteamOS mixed-scope rendering.
- Controller mapping/composition tests, existing fixed CONFIG command integration,
  typecheck and targeted lint/format pass.

The committed bundle was built separately with current work and committed
registration source at `2ef46a05`; unrelated pending `registration.ts` edits remain
untouched/excluded. The temporary build's dependency region **comments** alone were
canonicalized, as at the accepted prior checkpoint. Final Node 20 integration
executed this artifact, not a distribution build that swept in user work.

# Concrete next placement/adoption proposal — not authorized or implemented

Prefer the **existing placement primitives**, not another whole-render switch:

1. For a representative etc-typed host, set `PREFIX_DIR` to a grouped home data
   location such as `{{XDG_DATA_HOME}}/compfuzor/etc`, and explicitly bind `ETC` to
   `DIR`. Preserve the existing etc-type structural exposure instead of moving old
   trees. An opt-typed material deployment can use the parallel `opt` group with
   `ETC: '{{DIR}}/etc'`. `BINS_DIR: '{{DIR}}/bin'` follows automatically.
2. Keep context receiver roots, systemd manager/install plans, package operations,
   archive/source checkout conventions and copy/link strategies separate. Setting
   only DIR/PREFIX_DIR does **not** relocate ETC: [`vars_hierarchy.tasks`](/tasks/compfuzor/vars_hierarchy.tasks)
   independently derives it unless explicitly bound. Audit other emitted families
   as material versus receiver state before changing them.
3. Render one Niri/Umbriel consumer and one producer into isolated home-local
   material roots. Point producers through existing `consumer` selectors to the
   chosen host profile; do not scan `/etc/opt` or delete stale producer material.
   Prove a system context operation can still use that same home-local material.
4. Review opt-in changes to those real playbooks, including explicit SYS-only
   provisioning and renderer bypass decisions. Existing Ansible render-side effects
   are not suppressed merely by omitting a public install alias.
5. Only after reviewing those renders choose a shared default declaration/helper,
   if repetition warrants one. No `MATERIAL_ROOT` API is needed merely to express
   the first placement/adoption slice. Live activation/migration remains separate
   authorization and deliberate cleanup.

This follows [`vars_base.tasks`](/tasks/compfuzor/vars_base.tasks),
[`vars_hierarchy.tasks`](/tasks/compfuzor/vars_hierarchy.tasks) and
[`compile_artifacts.tasks`](/tasks/compfuzor/compile_artifacts.tasks), rather than
assuming the action audience relocates material or repurposing legacy USERMODE.

# Cross-references

- [Maintained contract](/doc/actions/README.md): operator semantics and complete
  domain integration rather than the earlier pending-interface warning.
- [Approved admission direction](/design/action-audiences/domain-admission0.gpt61sol.md):
  predecessor decisions and the explicit pre-effects/bypass compatibility choice.
- [CONFIG stages](/design/action-audiences/config-stages0.gpt61sol.md): operation
  and commit boundaries retained by the shared adapter.
- [Intent](/design/action-audiences/intent0.gpt61sol.md): home-local material remains
  a separate obligation, not satisfied merely by these user-scoped effects.
