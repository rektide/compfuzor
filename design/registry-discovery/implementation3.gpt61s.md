---
type: ImplementationCheckpoint
title: Advertised native cutover regression and maintained guide migration
description: Retained generated native/action acceptance migrated to owned advertisements and explicit paired policies, with a selected-graph target semantics correction and documented scope boundaries.
resource: /design/registry-discovery/implementation3.gpt61s.md
tags: [registry, regression, cutover, native, fixtures, policy, documentation]
status: draft
generated: { by: model:gpt61s, at: 2026-10-07 }
verified: { by: model:gpt61s, at: 2026-10-07 }
stale_after: 2026-11-07
sources:
  - resource: /design/registry-discovery/implementation2.gpt61s.md
    title: Completed prospective publication and policy pair predecessor
  - resource: /design/registry-discovery/regression-map0.gpt61s.md
    title: Retained behavioral acceptance and migration inventory
  - resource: /tests/integration/keybindings/fixtures.py
    title: Complete XDG isolation and portable paired policies
  - resource: /files/actions/session.ts
    title: Selected root graph binding for operation preparation
  - resource: /doc/config/keybinding-producers.md
    title: Maintained advertised producer entry contract
---

# What changed

The successor reviewed [implementation2](/design/registry-discovery/implementation2.gpt61s.md),
[publication instructions](/design/registry-discovery/publication0.gpt6a.md), and actual
policy/admission/guard/publication code before migrating the regressions. The bounded
predecessor is accepted, not reimplemented: same captured policy bytes; explicit
provider/consumer pair with no missing-side fallback; effective operative provider
agreement; audience filtering before lookup; explicitly packaged prospective consumers;
exact pre-state→planned-reference guards and fixed membership after authored effects.

The next slice migrated old fixtures without restoring retired producer-per-adapter
wrappers or shared hardcoded profile defaults. It keeps producer and consumer ownership,
native semantics and independent CONFIG commit boundaries. Maintained guides and
playbook-generated READMEs now describe the actual public registry interface.
The authorized **advertised-native cutover is complete for this bounded scope**:
all migrated retained acceptance paths below passed. This does not declare the
separate registry/pipeline futures implemented or authorize live deployment.

# Fixture migration and acceptance retained

- [Shared fixture helpers](/tests/integration/keybindings/README.md) supply complete
  disposable HOME/XDG roots/search directories and portable USER/SYSTEM policy pairs.
  Generated fixtures declare `KEYBINDING_REGISTRY_POLICY`; both collections bind at
  admission before bodies can change HOME/XDG. SYSTEM tests never use normal registry roots.
- [Selection compiler integration](/tests/integration/keybindings_target_defaults.test.py)
  retains declaration entry gating, render-no-effects, empty producer and host patch
  roles. It now proves one producer offer entry and selection `null`/subset/empty,
  profile/context overrides in owner-held data, scoped prospective owned consumers,
  host-before-producer ordering and nonrevival of retired common profile defaults.
- [Two-producer generated proof](/tests/integration/keybindings_generated.test.py),
  [empty update](/tests/integration/keybindings_empty_producer.test.py) and
  [dependency metadata](/tests/integration/keybindings_dependencies.test.py) preserve
  jq/stock workers, exactly-once authored bodies, dormant conditional patches, direct
  native/personal inputs, edited-copy preservation, linked refresh, shrinking/empty exact
  membership, no stale-file prune, invalid-native source/root/state rollback and saved
  group/source-slot disables. Hosts advertise before separate producer delivery.
- [Full-playbook consumer hosts](/tests/integration/keybindings_consumer_hosts.test.py)
  retain Niri fresh skeleton/conservative adoption/idempotence and Umbriel historical
  hash/byte-match migration, unreferenced retained fragment and preserved user edits.
  Every render starts fresh: old proof trees may contain intentionally unpruned retired
  launchers and cannot prove their absence. Owned descriptors/reference checks replace
  the obsolete host-wrapper `--profile` text assertion.
- [Media Keys](/tests/integration/keybindings_media_keys.test.py) and
  [Vicinae](/tests/integration/keybindings_vicinae_proposal.test.py) retain detailed native
  commands/chords/options, modifier additions, Niri locked/title behavior, Umbriel quoting,
  late clipboard patch/toggle policy and exact membership. One generic offer entry delivers
  to advertised receiver IDs; no producer profile defaults or per-adapter launchers return.
- [SteamOS host](/tests/integration/keybindings_steamos_niri.test.py) remains host-only:
  seven native deck bindings, old overlay removal, unknown native text preserved, no
  fabricated producer group, fresh/existing roots, idempotence and stubbed add-wants.
- [Typed domains](/tests/integration/action_domains.test.py) preserve USER/SYSTEM scope,
  frozen roots/placements/strategies/selected profiles despite body exports, operational
  exports to validators, marker stripping, bypass admission, early errors, input/publish
  operations, session ownership/cleanup, signals and external producer delivery.
  Separate external producer ownership now has a distinct stable ID: silently replacing
  another owner's same-ID reference is not an acceptable fixture shortcut.
- [Default placement](/tests/integration/action_placement.test.py) retains actual imported
  playbooks without DIR/ETC overrides, home fallback, ETC exposure/template separation,
  deliberate shared placement, copy registration and both receiver audiences. Shared
  same-ID material uses a separately selected public pair; the explicit env profile
  override remains covered rather than conflating registry selection with profile binding.

Full-playbook tests remain separate from the generated declaration/subtask proofs.
Native source/CONFIG validators are real except `action_domains`, whose stub validators
deliberately test exports/private transport/failure propagation rather than compositor
grammar. Session/privileged commands are stubbed or never executed. No live installation,
service work, upstream Figments research or extra agents occurred.

# Consequential real regression corrected

During review, descriptor-bound host preparation discarded every `--target` regardless
of the selected action graph. That made a standalone host assembly silently ignore a
wrong native format, although only combined producer delivery should give that flag
receiver-subset meaning.

The private [operation request](/files/actions/session.ts) now retains and verifies
the selected `rootAction` against the current spec/graph. Only when that graph contains
`install-offer` does [prepareOperation](/files/actions/operations.ts) strip receiver
subset flags from owned-host bootstrap. A focused standalone host keeps native-format
assertions. This adds no global flag scrubber or persistent workflow schema: transport
is still private, invocation-lived and digest/graph-bound.

[Source admission coverage](/tests/action-audiences/keybinding-admission.test.ts) proves
wrong standalone adapter rejection and combined receiver subset preservation. The
[combined deployed proof](/tests/integration/registry_combined_generated.test.py) now
also rejects a wrong `--target` on focused host assembly without changing native bytes,
while combined first install/subset and isolated SYSTEM execution stay valid.

Two additional [batch tests](/tests/registry-discovery/invocation.test.ts) distinguish
new eligible consumer publication **after** default-all admission from a selected
identity's mask mutation, and show sequential failure behavior without pretending to
roll back earlier receiver execution. Their native execution is mocked: they establish
orchestration/fixed selection, not native transaction atomicity. Existing actual native
rollback tests remain the evidence for per-consumer CONFIG publication.

# Verification ledger

| Check | Outcome |
|---|---|
| `pnpm exec vitest run tests/registry-discovery tests/action-audiences tests/config-keybindings/domain.test.ts tests/config-keybindings/native.test.ts tests/config-keybindings/registration.test.ts` | **10 files / 58 tests passed** after the selected-graph correction. |
| `pnpm exec vitest run tests/config-keybindings/processor.test.ts tests/config-keybindings/consumer.test.ts` | **2 files / 12 tests passed**, 207.33 s, adequate 600 s outer limit; no skip reported. These unchanged lower native paths were checked at the migrated fixture checkpoint. |
| Final `tests/registry-discovery/invocation.test.ts` focused rerun | **11 tests passed** after giving the late consumer a distinct native profile/root and proving fresh admission sees it while the earlier batch does not. |
| `pnpm check`, `pnpm build` | Final correction passed configured format/lint/tsgo; actual ~1.17 MB bundled closure refreshed. Final late-consumer test refinement also passed `pnpm check:type` and targeted formatting. |
| Four compiler scripts: keybindings_compile, registry_compile, action_contexts, action_audiences | Passed. External producer controller assertions moved from retired scalar wrapper to batch/selection document; owned-host assertions retained. |
| target_defaults, generated, empty_producer, dependencies, packaging integrations | All passed. |
| consumer_hosts, media_keys, vicinae_proposal, steamos_niri integrations | All passed; detailed native/adoption semantics retained. |
| `registry_keybindings_generated.test.py` | Passed against the refreshed artifact at the public-help checkpoint: unchanged real declarations, named Niri, exact Zim offer references, native force/mask/group disable/rollback. |
| `registry_combined_generated.test.py` | Passed against final graph-correction artifact: prospective USER/SYSTEM first install, reinstall/subset, actual native rollback, pre-body mask veto and standalone host adapter rejection. |
| `action_domains.test.py` | Passed after final graph correction: paired-policy USER/SYSTEM and retained transport/body semantics. |
| `action_audiences.test.py` | Passed after final graph correction: exec-only alias/phase/body/omission semantics, fail-fast/containment/cycles/signals and actual SteamOS render-only plan. |
| `action_placement.test.py` | Passed after final graph correction: real default placement/native publication, explicit paired-policy SYSTEM, deliberate shared registry/profile selection and target HOME fallback. |
| media-keys/Niri/Umbriel/Vicinae playbook syntax checks | Passed; final README edits also parsed as YAML. Maintained local documentation link paths checked. |

Do not count earlier failures as green: initial target-scope diagnostics now fail at
advertised context rather than lower profile scope; fixed-tree launcher absence and
same-ID producer ownership were invalid fixture assumptions; shared-root policy alone
didn't override an explicitly selected old profile; initial placement run exceeded
240 s and was rerun with 600 s. None justified restoring old wrappers, bypassing masks,
retargeting owners, adding implicit prune, or claiming broad native success from timeout.

# Maintained interface and scope

Updated [producer](/doc/config/keybinding-producers.md),
[consumer](/doc/config/keybinding-consumers.md), [actions](/doc/actions/README.md),
[CONFIG overview](/doc/config/README.md), [Zim toolkit distinction](/doc/config/consumer-toolkit.md),
[pure grammar cross-reference](/doc/config/keybindings.md),
[registry guide](/runtime/registry/README.md), and
[isolated update log](/doc/config/log.md#2026-10-07). Media Keys/Niri/Umbriel/Vicinae
comments and generated README payloads no longer advertise retired shared defaults.
Public help exposes `--registry-policy`; `.ts` remains the source development entry,
the bundled `.mjs` is deployment material.

The advertised-native cutover does **not** implement registry administration,
consumer-driven collection of new provider offers, Zim registered-offer consumption,
native adapters beyond Niri/Umbriel, or changed/canonical/deployed runtime-source
selection. These directions remain visible and require their own authorized slice.
Host assembly reads closed accepted membership. Advertisement is not native activation;
force is not persistent enable; batches are not cross-receiver transactions.

# Saved stages and budget

- `74795c18`: advertised fixture migration and paired-policy isolation.
- `66065477`: maintained guides/playbook README cutover.
- `ec25cec1`: retained acceptance, extra fixed-selection/sequential tests, public policy help and refreshed bundle.
- `dca6c740`: selected-root graph target semantics correction, source/generated coverage and bundle.
- `b3689799`: fixture ownership/shared-profile and remaining guide/log refinements.
- `d42a9a96`: late consumer eligibility proved through fresh admission, preserving the earlier fixed batch.

Latest passive measurement at completion: **224,910 last-reported tokens
(23% of nominal 990,000)**, not lifetime usage. Normal rollover remains 350–450k,
target 400k; no exception needed.
Unrelated user work and parent-owned handoff/index files were preserved and excluded
from explicit owned commits. No push/edit/squash or implicit live cleanup was performed.
