---
type: ArchitectureCheckpoint
title: Prospective registrations and coherent invocation policies
description: Parent review of the first generated native slice and the bounded next slice for exact self-publication transitions, combined first installs and isolated system policies.
resource: /design/registry-discovery/publication0.gpt6a.md
tags: [registry, admission, publication, ownership, keybindings, policies]
status: draft
generated: { by: model:gpt6a, at: 2026-10-07 }
verified: { by: unverified }
stale_after: 2026-11-07
sources:
  - resource: /design/registry-discovery/implementation1.gpt61s.md
    title: Reviewed executable generator and native admission checkpoint
  - resource: /runtime/keybindings/invocation.ts
    title: Current producer batch admission and publication
  - resource: /runtime/registry/guard.ts
    title: Current selected-identity observation guards
  - resource: /design/registry-discovery/selection0.gpt6a.md
    title: Operator's force-enable decision
---

# Accepted implementation direction

The parent read the generated/native checkpoint and its implementation, including
the invocation, registry guards/publication, action bridge, generator and generated
native proof. The shared-library/owned-artifact direction is sound, and the reported
focused checks are accepted as evidence. They do not establish the older broad
integration matrix as passing.

The next slice has two consequential interfaces: prospective owner-held consumer
references, and one coherent provider/consumer registry policy pair. Both preserve
pre-effects admission and the existing consumer-owned CONFIG commit seam.

# Prospective consumers are explicit inputs

A combined producer/consumer deployment can name its packaged consumer descriptions
before their registration links exist. Admission may use those explicitly supplied
descriptions alongside observed registry entries. They must remain distinguishable
from observations of already-published state.

- Capture/validate the exact descriptors, native profiles, resources and audience
  bindings before authored effects.
- Existing effective registrations/control declarations take precedence. Apply
  normal mask, disabled/force-enable, schema and audience policy.
- Freeze the selected identities. Publication during execution does not open a new
  implicit discovery collection or admit unrelated receivers.
- Prefer owner-host bootstrap before its combined producer applies there, with each
  consumer's native/membership commit retaining its existing independent boundary.

# Admit the publication transition itself

An expected registration can move from its pre-admitted state to **only the planned
owner-reference state**. A reusable guard/publication contract should recognize
that exact transition and benign matching publication already completed by another
step in the same invocation.

The allowed transition retains the identity, roots, destination, exact owner
reference, descriptor byte guards, and relevant surrounding control observations.
A new mask, conflicting slot, foreign override or redirected payload is not the
planned transition. Parent/descriptor guards continue to cover source identity.

This same seam corrects the current producer publication gap: after publishing its
reference, `runAdmittedKeybindingBatch()` currently observes whatever provider state
exists and turns it into a fresh guard. A newly arrived mask could thereby become
accepted guard state. The post-publication observation must satisfy the admitted
expectation; it must not become fresh admission after effects.

# Bind the entire policy pair once

Provider publication, consumer selection, owned-host admission/publication and
guards must share one invocation-bound provider/consumer policy pair. Supplying
only consumer roots while the provider side falls back to `/var/lib` is inadequate
for both custom system registries and isolated integration tests.

The public CLI/typed/generated surface should expose an inspectable configuration
input, preferably a small owner-held versioned policy document locator. Reuse
portable `PathSelector` values during authoring and concrete `explicitPolicy`
bindings after invocation resolution. When an override is supplied, a missing
required side must be diagnosed rather than silently using live system defaults.
Exact field names/schema are being resolved in the active implementation slice.

# Additional reviewed corrections in this slice

1. Parse selection-policy content from the **same captured bytes** used for its
   guard. The current read-then-separate-capture sequence can bind one revision and
   guard a later revision.
2. Explicit owned producer installation must not silently ignore a conflicting
   effective registry offer with the same ID. For this slice, require agreement on
   operative resources/order/adapter eligibility, allowing participation controls
   to differ, or fail before authored work with an explained redirect conflict.
3. Filter authored receiver requests by invocation audience before constructing the
   default subset or looking IDs up. Mixed user/system mappings must not demand
   other-audience receivers in the current audience's registry. Explicit out-of-
   audience requests still fail clearly.
4. Preserve all empty/explicit `[]` behavior and fixed membership while permitting
   only named self-publication transitions.

# Verification and rollover

The authorized proof includes combined first install, reinstall, explicit subset,
unexpected publication/control changes, native rejection rollback and a SYSTEM
fixture isolated through the public policy pair. Existing media-keys/Niri/Umbriel
proofs must use the refreshed real bundle.

The implementing Sol medium reached this checkpoint near 320k context. Its next
slice is bounded: prepare handoff at 350k, target roughly 400k, normally stop by
450k. A fresh Sol medium is independently mapping old test/documentation migration
without modifying implementation files. The successor should use that evidence
instead of rerunning prior research or unsafe legacy system fixtures.
