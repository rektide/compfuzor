---
type: ImplementationPlan
title: Advertised keybinding receivers and receiver masks
description: File-level plan for catalog-selected receiver batches, mask overlays, host advertisement publication, and generated installer cutover.
resource: /design/runtime-sourcing/receiver-plan0.gpt6a.md
tags: [keybindings, receivers, masks, admission, config]
status: draft
generated: { by: model:gpt6a, at: 2026-10-06 }
verified: { by: unverified }
stale_after: 2026-11-06
sources:
  - resource: /design/runtime-sourcing/direction0-syn.gpt61sol.md#receiver-masks
    title: Receiver mask semantics and advertised rendezvous direction
  - resource: /files/config/keybindings/runtime.ts
    title: Current single-target admission and execution
  - resource: /files/config/keybindings/membership.ts
    title: Closed producer membership and CONFIG publication
  - resource: /files/actions/operations.ts
    title: Typed domain preparation and verification
  - resource: /files/actions/session.ts
    title: Pre-effects admission and invocation-private transport
  - resource: /library/filter_plugins/keybindings_compile.py
    title: Generated target installers and action operations
---

# What is up

The operator asked for a concrete code plan after reviewing
[receiver masks](/design/runtime-sourcing/direction0-syn.gpt61sol.md#receiver-masks).
The implementation destination here is the direction's advertised-receiver
checkpoint: hosts advertise themselves; a generic producer selects all unmasked
receivers for its audience or an explicit subset; masks remain effective under
explicit target/profile selection.

The current obstacle is structural. A receiver is currently conflated with the
native `niri | umbriel` target, Python emits one installer per target, and a typed
action transports one admitted keybinding command. Adding a mask check to that
loop would retain the producer-side knowledge the direction intends to remove.

**Recommendation:** introduce a receiver-catalog module, make producer admission
return an invocation-bound batch, and have host installation publish receiver
advertisements through CONFIG. The following layout and interface choices are
proposals for this implementation, not previously accepted contracts.

# 1. Concrete decisions

## Identity and declaration

A receiver identity is `(audience, id)`. Several IDs can use the same adapter.
`niri` and `umbriel` remain convenient receiver IDs for the existing playbooks;
`deck-main` can also refer to a Niri profile.

The new catalog uses `receiver.id` and `receiver.adapter` separately. Existing
`Profile.target`, `ConsumerRequest.target`, YAML target refinements and native
rendering continue to mean the native adapter. An arbitrary receiver ID is never
passed to a serializer as its native format.

Proposed advertisement, stored under `<id>.json`:

```json
{
  "version": 1,
  "id": "niri",
  "adapter": "niri",
  "audience": "user",
  "profile": {
    "env": "COMPFUZOR_NIRI_PROFILE",
    "default": { "path": "/absolute/host-deployment/etc/keybinding-niri.json" }
  },
  "defaultContext": "user",
  "contexts": ["user"],
  "rendezvous": {
    "producers": { "relative": ".keybindings/producers.d" }
  }
}
```

The filename and declared ID must agree. Profile and rendezvous selectors reuse
[`PathSelector`](/files/config/context.ts); the rendezvous is resolved against
the selected profile's bound base. Context overrides must be both advertised and
of the selected audience. The loaded profile's native target must agree with the
advertised adapter.

## Overlay layout

Recommended highest-to-lowest lookup order:

| Audience | Mask overlay | Operator advertisements | Installed host advertisements |
|---|---|---|---|
| user | `${XDG_CONFIG_HOME}/compfuzor/keybindings/targets.mask.d` | `${XDG_CONFIG_HOME}/compfuzor/keybindings/targets.d` | `${XDG_DATA_HOME}/compfuzor/keybindings/targets.d` |
| system | `/etc/compfuzor/keybindings/targets.mask.d` | `/etc/compfuzor/keybindings/targets.d` | `/var/lib/compfuzor/keybindings/targets.d` |

Dedicated mask overlays let `mask` preserve even an operator-authored advertisement.
All layers use the same `<id>.json` basename. A direct symlink whose lexically
resolved target is `/dev/null` is a mask; empty files and indirect symlink chains
to special files are invalid advertisements. The mask-only overlay rejects other
entry types. A winning invalid entry never falls through to a lower copy.

User and system catalogs are separate: root's HOME does not choose a system
catalog, and a system invocation does not consume user-writable advertisements.
The catalog interface accepts explicit roots for isolated tests and subsequent
embedding; normal CLI roots follow the table and invocation-time XDG defaults.

`mask` can create a negative declaration before a host exists. Repeated mask or
unmask is idempotent. Unmask removes only a verified mask in the writable mask
overlay; if a lower layer also masks the ID, listing still reports it masked.
Neither command replaces a non-mask collision or follows the mask to its referent.

## Selection and observation

- Default: collect every effective unmasked advertisement in the chosen audience.
- Explicit IDs: select exactly the requested subset, reject duplicates, missing
  IDs, masked IDs and audience mismatches. A profile override follows this check.
- Default execution order is stable receiver-ID order. Explicit lists retain
  caller order. An empty default selection is a reported successful no-op;
  explicit missing IDs are errors.
- Listing reports masked/registered/invalid entries, winning paths and shadowed
  paths. It can show a mask even when no lower advertisement exists. Listing does
  not require a CONFIG runner or load native profiles.
- Selected malformed advertisements fail admission. Default selection must
  report malformed effective entries whose eligibility cannot be established;
  explicit selection need not load unrelated entries.
- Admit the complete selected set before authored installer bodies. Freeze IDs,
  audience, profiles, contexts, concrete paths and delivery policy in that set.
- Reobserve selected entries and all stronger overlay slots before dispatch and
  during CONFIG closure validation. A newly inserted mask or changed selected
  advertisement invalidates pending work. Newly registered unrelated receivers
  participate in the next invocation, not an already-admitted batch.

These are observed-state guards, like current CONFIG guards, not locking or a
promise that concurrent edits cannot occur between checking and publication.
Receivers retain independent CONFIG commits: if a later receiver fails native
validation, earlier successful receivers remain committed. Report the failing ID
and stop; do not retry it through another advertisement.

# 2. Code changes, in implementation order

## Commit 1 — Add the receiver catalog and mask operations

**New:** `files/config/keybindings/receivers/catalog.ts`.

This deep module owns advertisement admission, audience-root lookup, overlay
precedence, mask recognition, provenance, selection and mask mutation. Its public
interface supplies catalog inspection, selection, mask/unmask and selected-entry
guard verification; callers do not reproduce directory traversal.

Reuse [`inspectDeliveryEntry()`](/files/links/delivery.ts#L43-L59) for entry
topology. Detect `/dev/null` links before calling
[`captureFile()`](/files/config/capture.ts#L70-L95), which correctly rejects
nonregular referents. Ordinary advertisements retain captured content guards;
overlay absence/mask observations need an additional topology-oriented guard.

**Change:** [`runtime.ts`](/files/config/keybindings/runtime.ts) to dispatch:

```sh
node files/runtime/compfuzor-runtime.ts keybindings targets --scope user --json
node files/runtime/compfuzor-runtime.ts keybindings mask --scope user --target niri
node files/runtime/compfuzor-runtime.ts keybindings unmask --scope user --target niri
```

These branches run before the existing runner-required admission path.

**Tests:** new `tests/config-keybindings/receivers/catalog.test.ts`, exercising
the public catalog interface over real isolated files/links: overlay masks,
provenance, masks without advertisements, unmask recovery, invalid higher entries,
audience isolation, and preservation of operator and installed advertisements.

**Checkpoint:** inspect the schema, lookup table, CLI output and test evidence.

## Commit 2 — Admit a receiver batch through CLI and typed actions

**New:** `files/config/keybindings/receivers/invocation.ts`, owning catalog-to-host
binding and deterministic batch execution. It calls the catalog, then the
existing profile binding and complete membership operations.

**Change:** [`runtime.ts`](/files/config/keybindings/runtime.ts) so producer
`install` accepts repeated `--target <receiver-id>` or defaults to all. Host and
group-toggle commands bind a single receiver. Preserve `--profile`,
`--profile-selector`, context, scope, mode and runner validation; profile/context
overrides require one selected receiver rather than accidentally redirecting a
whole fan-out to one destination. Profile overrides cannot fabricate a receiver
that the catalog says is missing or masked.

Refactor the existing `admitKeybindingCommand()` into per-receiver binding behind
the new invocation interface. Keep `runAdmittedKeybindingCommand()` as the complete
single-receiver operation reused by the batch. Reject receiver selections that
alias the same physical root, membership state or generated-material root before
effects; shared native adapter identity is valid, duplicate receiver ownership
is not.

**Change:** [`files/actions/model.ts`](/files/actions/model.ts) to represent CONFIG
and keybinding domain steps as discriminated shapes. A keybinding producer step
contains a selection-policy locator and producer manifest rather than a required
native target/context. An owned-host step carries its receiver identity and
packaged advertisement for bootstrap admission. CONFIG retains its own required
context fields.

**Change:** [`operations.ts`](/files/actions/operations.ts) so one prepared
keybinding operation holds the admitted batch. Verification checks every member's
receiver/adapter/audience/context, producer identity and bound paths. Execution
uses that serialized batch, not a fresh catalog lookup. Extend
[`session.ts`](/files/actions/session.ts) validation and bounds to count admitted
receiver members as well as static operations; preserve the existing private
transport and graph matching. Update action help in
[`files/actions/runtime.ts`](/files/actions/runtime.ts) for catalog-selected steps.

**Change:** thread receiver observations through
[`membership.ts`](/files/config/keybindings/membership.ts),
[`consumer.ts`](/files/config/keybindings/consumer.ts) and
[`closure.ts`](/files/config/keybindings/closure.ts). The closure hook checks
catalog observations alongside existing profile/source guards. Internal native
processors and request-based CONFIG tooling remain lower-level functions;
receiver policy applies to receiver-selecting public commands, not arbitrary
filesystem writes by trusted scripts.

**Tests:** extend
[`keybinding-admission.test.ts`](/tests/action-audiences/keybinding-admission.test.ts)
and add receiver invocation tests. Prove multiple IDs on one adapter, default all,
explicit subset, masked explicit rejection with a profile override, malformed
later receiver rejected before authored body, serialized selection unaffected by
later HOME changes, and a mask inserted after admission aborting pending work.

**Checkpoint:** review batch shape, observation semantics and failure reporting
before changing generator defaults.

## Commit 3 — Generate advertisements and generic producer installers

**Change:** [`keybindings_compile.py`](/library/filter_plugins/keybindings_compile.py):

1. Treat `KEYBINDING_CONSUMERS` keys as receiver IDs; add `adapter` and optional
   advertisement `profile_selector` metadata. Existing `niri`/`umbriel` keys may
   imply their adapter. Arbitrary keys require an explicit adapter. Keep native
   profile compilation separate from receiver metadata.
2. Emit packaged advertisements under
   `etc/keybindings/receivers/<audience>/<id>.json`, derived from the host profile,
   its allowed audience contexts and existing `action_contexts` choice.
3. Emit one generic producer envelope `bin/install-keybindings.sh` and one typed
   producer operation per participating audience. Runtime discovery performs the
   fan-out. Per-ID compatibility wrappers, where emitted, delegate explicit IDs
   through the same admission and do not also join the aggregate.
4. Emit editable `etc/keybindings/selection.json`: default all, or the explicitly
   authored receiver list/map and its existing per-receiver overrides. The action
   step and envelope point to this one policy rather than repeating target wiring.
   CLI selection narrows an authored subset; it cannot silently widen it.
5. Emit producer manifest version 2 with producer identity, order and exact
   resources, removing the compiled native-target enrollment list. Read version 1
   manifests through an explicit compatibility adapter that treats their `targets`
   as native-adapter eligibility, not receiver IDs. For default fan-out, exclude
   incompatible v1 adapters; explicit incompatible requests fail. Empty producer
   resources remain a real update.

**Change:** [`gen_keybindings.tasks`](/tasks/compfuzor/gen_keybindings.tasks) and
[`vars/common.yaml`](/vars/common.yaml#L204-L220) to replace the hard-coded
`KEYBINDING_TARGET_DEFAULTS` map with catalog selection. Undefined producer targets
mean all; explicit `[]`/`{}` mean none; implicit consumer-only deployments retain
their owned late patch layer. Existing explicit target maps become receiver-ID
selection and overrides, checked against advertisements at invocation.

**Change:** [`membership.ts`](/files/config/keybindings/membership.ts#L400-L420)
to merge caller supplemental outputs with membership output instead of replacing
them. Host **install** stages its installed advertisement as another CONFIG
candidate, with a guard on the destination. Host **assemble/check** does not
advertise merely by inspecting the profile. Generated advertisements are JSON
copies refreshed on successful host installation; they retain portable selectors
and a source locator identifying the packaged host declaration.

Bootstrap admission uses the host's packaged advertisement when its installed
slot is absent, but still checks all higher overlays for masks or conflicting
identity. Reinstallation can refresh its own declaration; a different host
claiming the same installed identity is an error. A shadowing operator declaration
must agree with the host being operated on or host installation reports the
conflict before adoption. This avoids both the first-install discovery cycle and
silently publishing one host while configuring another.

**Change:** [`niri.etc.pb`](/niri.etc.pb), [`umbriel.etc.pb`](/umbriel.etc.pb) and
[`steamos-niri.opt.pb`](/steamos-niri.opt.pb) to declare advertisement metadata.
Move `COMPFUZOR_NIRI_PROFILE` / `COMPFUZOR_UMBRIEL_PROFILE` selectors into their
host-owned advertisements. Give the Deck receiver a distinct ID with `adapter:
niri`. Existing authored adoption bodies retain their ordering after admission
and before native assembly; a preexisting mask fails host admission before those
bodies run. A failed native publication does not publish a new advertisement.

Update producer usage/comments in [`vicinae.src.pb`](/vicinae.src.pb) and
[`media-keys.etc.pb`](/media-keys.etc.pb) to describe the generic installer. Preserve
the latter's preexisting `INSTANCE: main` working-copy edit when implementing.

**Tests:** extend
[`keybindings_compile.test.py`](/tests/filter_plugins/keybindings_compile.test.py),
[`keybindings_target_defaults.test.py`](/tests/integration/keybindings_target_defaults.test.py),
[`keybindings_consumer_hosts.test.py`](/tests/integration/keybindings_consumer_hosts.test.py),
[`action_domains.test.py`](/tests/integration/action_domains.test.py) and
[`keybindings_generated.test.py`](/tests/integration/keybindings_generated.test.py).
Render real hosts and a producer into isolated HOME/XDG trees. Assert no published
advertisement at render time, publication only after successful host installation,
one generic producer operation, and mask/unmask changes taking effect without
rerendering the producer. Cover a second Niri receiver with a distinct profile root.

**Checkpoint:** end-to-end advertised receiver selection is now usable. Review
actual generated artifacts and host/producer behavior before the next extension.

## Commit 4 — Document and complete the generated-installation proof

Update [`doc/config/keybinding-producers.md`](/doc/config/keybinding-producers.md),
[`doc/config/keybinding-consumers.md`](/doc/config/keybinding-consumers.md),
[`doc/actions/README.md`](/doc/actions/README.md), and add a maintained
`doc/config/keybinding-receivers.md` guide with the schema, roots, commands,
provenance examples and migration instructions.

Refresh the checked-in deployment artifact `runtime/compfuzor-runtime.mjs` through
the existing packaging pipeline alongside each deployable runtime change above,
before that change's generated-installation tests. This final pass checks the
complete host/producer cutover against that artifact. It is the artifact Ansible
actually copies; source-only passing tests do not verify it. Source development
and examples continue to invoke `.ts` paths directly.

Required checks for implementation: `pnpm check:type`, targeted Vite+/Vitest tests
under `tests/config-keybindings` and `tests/action-audiences`, formatting/lint for
touched TypeScript including the actions directory, relevant Python filter and
integration scripts, and syntax checks for the edited playbooks. Tests use
domain-specific `.test-agent/` scratch with README files and isolated receiver
roots. Report missing native validation prerequisites as incomplete evidence.

# 3. Producer-drop extension after the receiver checkpoint

The advertised rendezvous has a concrete next use. Add
`files/config/keybindings/receivers/producers.ts` to load only typed
`<producer-id>.json` declarations referring to an **exact producer manifest**.
Producer `install` writes that declaration into the selected receiver/context's
advertised rendezvous and invokes assembly. Host assembly admits observed
declarations as proposed updates to durable membership.

Refactor [`installProducer()`](/files/config/keybindings/membership.ts#L458-L503)
into reusable candidate-group preparation plus one batch apply:

1. Capture and validate declarations, exact manifests and resource identities.
2. Starting with committed membership, upsert each declared group, preserving its
   enabled state and source disabled-slot convention. Explicit empty resources
   clear the group's selected resources; absent declarations do not remove groups.
3. Stage all required source registrations in one `withInputBatch()` operation.
4. Offer the resulting membership and native outputs to CONFIG once. Ordinary
   failure restores managed registration updates. Candidate membership becomes
   accepted only with CONFIG's successful commit.

Thus directory contents are input proposals; `membership.json` is accepted state.
Discovery is neither automatic acceptance nor an instruction to delete previously
accepted groups. Preserve consumer patches, group ordering, native seed/copy/link
semantics and exact resources. Test multi-producer rollback and disabled-group
preservation before connecting producer drops to default host assembly.

This extension and registered native-adapter extraction are separate architectural
checkpoints in the originating direction. The receiver descriptor already gives
the implementation catalog an adapter reference, and its module accepts catalog
roots independently of provider selection. The changed/canonical/deployed runtime
resolver can subsequently supply implementations without replacing receiver or
deployment workload data.

# Cross-references

- [Receiver-mask direction](/design/runtime-sourcing/direction0-syn.gpt61sol.md#receiver-masks)
  — semantic requirements; this plan proposes the previously open overlay layout
  and explains concrete code migration.
- [Action admission](/doc/actions/README.md#admission-and-authored-work) — existing
  pre-effects selection, private transport and independent operation semantics
  that the receiver batch must retain.
- [Producer membership](/doc/config/keybinding-producers.md#durable-closed-membership-and-failure-semantics)
  — accepted-state authority and failure contract; the proposed rendezvous admits
  updates through it rather than introducing another publisher.
- [Domain-grouped native adapters](/design/keybindings/config-lifecycle0.gpt61sol.md#2-admit-typed-configurations-through-an-extensible-native-seam)
  — explains the later native implementation seam. Receiver IDs becoming open does
  not by itself make native serializers extensible.
- [CONFIG capture](/files/config/capture.ts) and
  [delivery topology](/files/links/delivery.ts) — reusable regular-file observation
  and link inspection; masks require recognizing topology before regular reads.
