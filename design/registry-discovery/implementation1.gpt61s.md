---
type: ImplementationCheckpoint
title: Generated owner registration and advertised keybinding native batches
description: Executable generator and bundled native admission checkpoint, with passive publication, force enable, transaction guards and explicit first-install/root-policy boundaries requiring architectural review.
resource: /design/registry-discovery/implementation1.gpt61s.md
tags: [registry, rendezvous, keybindings, generation, admission, force-enable, ownership]
status: draft
generated: { by: model:gpt61s, at: 2026-10-07 }
verified: { by: model:gpt61s, at: 2026-10-07 }
stale_after: 2026-11-07
sources:
  - resource: /design/registry-discovery/implementation0.gpt61s.md
    title: Committed shared-library predecessor
  - resource: /design/registry-discovery/selection0.gpt6a.md
    title: Human invocation-only force-enable decision
  - resource: /runtime/keybindings/invocation.ts
    title: Native batch admission and execution
  - resource: /tests/integration/registry_keybindings_generated.test.py
    title: Generated artifact and real native publication proof
---

# What became executable

This advances the approved library shape through generated owner endpoints and
real keybinding native publication, not just another plan. The current source
media-keys values were used unchanged. Producer manifests/resources remain in their
own ETC; Niri/Umbriel profiles, late patches and descriptions remain in theirs.

The isolated generated proof renders the actual declarations and authored host
bodies from `media-keys.etc.pb`, `niri.etc.pb` and `umbriel.etc.pb`, plus a second
named Niri receiver (`deck-main`). It executes the committed bundled artifact,
stock CONFIG workers, block-in-file and actual Niri/Umbriel validators. All native
outputs and registration links are beneath the proof's HOME/XDG trees.

Generated material is now:

| Owner | Owned payload | Public endpoints | Published reference |
|---|---|---|---|
| media-keys | `<ETC>/keybinding-producer.json`, exact action/binding YAML, `<ETC>/keybindings/selection.json` | `register-keybindings-provider.sh`, `status-keybindings-provider.sh`, one `install-keybindings.sh` | data-home `compfuzor/keybindings/providers.d/media-keys-main.json` → exact owner manifest |
| Niri/Umbriel/named host | `<ETC>/keybinding-<receiver-id>.json`, `<ETC>/keybindings/consumers/<audience>/<id>.json` | scoped passive register/status endpoints and owned native host entry | data-home `compfuzor/keybindings/consumers.d/<id>.json` → owned description |
| Zim contributor | `<ETC>/zim-provider.json` naming exact generated active/disabled channel contributions | `register-zim-provider.sh`, `status-zim-provider.sh` | data-home `compfuzor/zim/providers.d/<producer>.json` → owned offer |

For `.etc.pb` deployments where ETC is DIR, conventional `etc/` exposure may alias
the owner root; generated references use the exact ETC rather than reconstructing
it from that alias. Zim's existing native host selection/import bridge is unchanged.

# Reviewed corrections incorporated

- Collection policy accepts contained domain-grouped `.d` paths such as
  `another-domain/hooks.d`; no providers/consumers-only grammar.
- System audience uses `/compfuzor/system/<collection>` under its standard system
  roots, separate from shared USER offers in XDG_DATA_DIRS.
- Config precedence is root-major: each low→high root contributes definitions then
  its masks. A higher root's definition overrides a lower root's mask; the highest
  local mask remains the operator veto.
- Passive registration may create/retain a lower owner reference beneath a higher
  mask or override. `disposition`/local `participation` differ from `effective.state`
  observed before publication. A mask or foreign/regular declaration occupying the
  writable slot remains blocked. No implicit unmask/retarget/prune.
- Replanning tolerates unrelated publishers creating an optional shared root. It
  still refuses failed roots and changed selected identity/physical slots.
- Consumer profiles use the existing shared `PathSelector` validator/binder, including
  recursive env/default/ignore and HOME/XDG expressions. Relative selectors bind at
  selected invocation against the owned descriptor's physical directory. Inspection
  never opens a native profile or demands its environment variables.
- Tab uses logical undashed option names and supports its normal `complete --`
  protocol and shell setup output. Collection choices derive from CLI descriptors.

# Concrete admission/publication interfaces

[`admitKeybindingBatch()`](/runtime/keybindings/invocation.ts) consumes an explicit
owned manifest and an optional owner-held selection policy:

```json
{"version":1,"receivers":null}
```

`null` means all eligible registered consumers. `[]` means no native delivery.
Explicit entries are `{id, profile?, context?, scope?, actionContexts?}`; generated
`KEYBINDING_TARGETS` settings compile into this policy. CLI repeated `--target`
narrows a declared subset, never widens it. The old shared Niri/Umbriel producer
profile defaults have been removed from `vars/common.yaml`. Host descriptions own
`COMPFUZOR_NIRI_PROFILE` / `COMPFUZOR_UMBRIEL_PROFILE` selectors.

The returned serializable `AdmittedKeybindingBatch` contains audience, force policy,
fixed member IDs, original states/forced markers, existing admitted single-receiver
commands, captured byte guards, and planned prospective owner publication. Native
adapter compatibility remains domain-local (`niri|umbriel` initially). Arbitrary
receiver IDs are never passed to native serializers as formats.

[`KeybindingBatchStep`](/files/actions/model.ts) is a separate typed
`operation:"install-offer"` shape: envelope, exact manifest, producer identity and
selection policy, without a pretend scalar receiver context/native target. Existing
legacy/config steps remain readable. [`operations.ts`](/files/actions/operations.ts)
prepares/verifies the whole batch before authored bodies; private transport includes
`forceEnable` and bounds aggregate receiver/operation count.

`runAdmittedKeybindingBatch()` rechecks inputs/selected registrations, publishes the
explicit prospective producer reference, captures that named publication's guard,
then runs only the already-admitted receivers. This later observation cannot add
receivers or change the admitted manifest/resource set.

Owned host commands bind their packaged description when its registration is absent,
but still honor effective masks/disabled policy before authored host bodies. Ordinary
successful host installation publishes its owner reference after native work.
Native assemble/check does not advertise; passive registration remains a separate
generated entry so availability does not require activation or successful assembly.

# Force and commit boundaries

The human's `--force-enable` decision is implemented for default collection and
explicit selection, including owned-host admission. It skips only registration-level
disabled suffix/metadata for that invocation. Original state/provenance remains in
admission and execution reports. Saved filenames/settings are not changed. Masks,
audience, adapter/schema/profile checks and native validation remain authoritative.
Consumer-owned producer-group disable and action/binding enabled flags are untouched.

Exact resource YAML is structurally admitted before authored work when receivers are
selected; malformed/missing/duplicate resources cannot reach authored bodies. Native
schema validity remains the existing CONFIG transaction validator's responsibility.
Selected descriptor bytes are checked against the inspection projection before
binding, avoiding a second-read silently replacing the inspected description.

Each member delegates to existing `installProducer()` / `assembleHost()` and the
consumer's closed accepted membership. Registry guards and upstream input guards
now pass through the closure plan and are checked before/after native validation.
Native output and membership still commit together through CONFIG; normal failure
restores managed registration updates. A batch is **not** one cross-receiver
transaction: earlier successful receiver commits remain if a later receiver fails.
Producer advertisement can remain available after native rejection. No reload,
reconciliation or cleanup is implicit.

# Dependency closure and checks

Source wiring remains `figmen-ts: link:../figments` through existing source subpaths,
all behind [`runtime/discovery/figments.ts`](/runtime/discovery/figments.ts). Parent
accepted all six upstream discovery/loading contracts; no upstream files were edited
here. Current captured reads use its detached selection/read-time guard directly.

[`vite.config.ts`](/vite.config.ts) explicitly bundles Figments source, confbox and
Router/tab. The committed `runtime/compfuzor-runtime.mjs` now contains the actual
closure (about 1.16 MB), with no external npm/source imports. Generated deployments
need neither receiver-side node_modules nor a sibling Figments checkout. Runtime
changed/canonical/deployed selection is still the separate follow-on.

Completed evidence:

- Focused source regression: **8 files / 46 tests passed** across registry discovery,
  action audiences, keybinding domain/native/registration tests.
- `pnpm check`: configured formatting/lint and `tsgo` passed, including new runtime
  sources/tests and targeted touched action/native modules. Session lint/format also
  ran directly.
- `pnpm build`: real closure bundled; generated proof ran against that artifact.
- `registry_keybindings_generated.test.py`: actual media-keys + Niri/Umbriel, second
  named Niri, exact symlink ownership, Zim generated offer endpoints, default fan-out,
  explicit disabled rejection, forced subset/default, mask veto under force, no saved
  disable mutation, retained consumer group disable, copied YAML rollback after actual
  native rejection, and no advertisement from check/assembly all passed.
- Updated keybindings compiler and new Zim registry compiler unit scripts passed.
- Syntax checks for media-keys, Niri and Umbriel playbooks passed.

Not claimed green: the broad combined Vitest native suite exceeded its initial
120-second limit; the focused 46-test regression and real generated native proof
were used instead. Existing older integration scripts assert retired per-target
producer wrappers/defaults and need migration, not restoration of hard-coded paths.
`action_domains.test.py` exposed the shared-root replanning issue (now covered/fixed);
its custom system-output fixture also lacks isolated system registry roots, so it
must not be blindly rerun into live `/var/lib` during migration.

# Architecture checkpoint: consequential first-install seam

Standalone producers and separately installed/advertised hosts work end-to-end.
**Combined producer+host first installation is not complete.** Typed action
preparation admits the producer batch before the host has published its own new
advertisement. An explicitly selected new owned receiver is therefore missing;
default collection does not include that new owned host either. Publishing inside
read-only admission, or rescanning to widen the batch after authored work, would
violate the agreed boundary. This is the requested meaningful midpoint rather than
silently changing that architecture.

Recommended next slice for parent authorization:

1. Make owner-held selection carry explicit packaged prospective consumer references,
   e.g. `prospectiveConsumers:["/owner/consumer.json"]`, separately from registry
   observations. Admit their identities/profiles/resources before authored work.
2. A selected absent identity needs a guard that permits **only** its planned exact
   owner-reference publication, still vetoing new masks/conflicts/foreign overrides.
   Current generic guards intentionally require unchanged state and do not permit
   this missing→planned-publication transition yet.
3. Specify producer/host publication and native-operation ordering for combined
   workloads. Keep selected identity/resource membership fixed; each consumer's
   existing membership/native commit remains its own transaction.
4. Expose a coherent invocation-bound pair of provider/consumer root policies to the
   keybinding caller/typed step (the library already supports explicit policy).
   Current batch injection covers consumer roots only, while provider publication
   and owned host defaults still use normal roots. This is needed for isolated
   generated SYSTEM proofs and operator-owned custom system registries, rather than
   inventing a test-only hidden override or touching live system locations.
5. Migrate combined-role, system-context and old default/per-target integration
   fixtures through those interfaces; then complete the maintained producer/consumer
   guides and wider generated regression matrix.

No extra agents were spawned. Context readout during this checkpoint was **286,447
current/last-reported tokens (29% of 990,000)**, not lifetime usage; below the operator's
350–450k rollover band. This is an architectural checkpoint, not a mandatory rollover.

# Saved stages and successor references

- `f312f304` / `ukqmzmkn`: generic/scoped/root-major policy, passive publication,
  shared selector shape validation and tab corrections.
- `115955a6` / `rmmwtkwz`: advertised native batch, force policy, typed action transport,
  native closure guards and source admission tests.
- `b8c26e25` / `vnqzxwtk`: generated owner endpoints/descriptions, generic producer
  installer/default removal, host-owned selectors, real bundled artifact and first
  native generated proof.
- `ffd01dd2` / `oxrloswm`: shared-root/check-publication corrections, selector-relative
  binding, source/resource admission strengthening, aggregate transport bounds,
  updated proofs and final bundle.

Start a successor from [rendezvous ownership](/design/registry-discovery/rendezvous0.gpt6a.md),
[human selection decision](/design/registry-discovery/selection0.gpt6a.md), this checkpoint,
[invocation code](/runtime/keybindings/invocation.ts), [typed operations](/files/actions/operations.ts),
[generator](/library/filter_plugins/keybindings_compile.py), and the
[real generated proof](/tests/integration/registry_keybindings_generated.test.py). Do not
repeat upstream research or tests already accepted by the parent. Preserve unrelated
preexisting working-copy changes and parent documentation. No push/edit/squash was run.
