---
type: ImplementationCheckpoint
title: Symmetric rendezvous registries first executable slice
description: Figments-backed registry inspection, owner-reference registration material, Router/tab CLI and isolated keybinding/Zim proofs before native generator cutover.
resource: /design/registry-discovery/implementation0.gpt61s.md
tags: [registry, rendezvous, figments, ownership, disabled, masks, runtime]
status: draft
generated: { by: model:gpt61s, at: 2026-10-07 }
verified: { by: model:gpt61s, at: 2026-10-07 }
stale_after: 2026-11-07
sources:
  - resource: /design/registry-discovery/rendezvous0.gpt6a.md
    title: Registry-as-library and symmetric owner registration
  - resource: /design/registry-discovery/ownership0.gpt6a.md
    title: Declaration ownership and reusable runtime placement
  - resource: /runtime/registry/README.md
    title: Implemented library interface
  - resource: /tests/registry-discovery/registry.test.ts
    title: Isolated filesystem and source-CLI proofs
---

# What now works

This is the parent's requested first code/interface checkpoint, not generator or
native installation cutover. Shared code lives under `runtime/<domain>/`.

An owner can expose its exact descriptor through an invocation-bound symlink;
another pipeline can inspect the effective registry state and provenance. The
same reader/planner/CLI exercises:

- **Keybinding providers:** the current producer-owned version-1 exact manifest,
  including `producer`, finite `order`, absolute `resources[].path` and legacy
  native-adapter `targets`. No extra central provider envelope.
- **Keybinding consumers:** owner-authored descriptions with arbitrary `id`,
  independent open `adapter`, `audience`, retained `enabled`, profile locator,
  `contexts` and `defaultContext`.
- **Zim providers:** owner-authored exact `fragments` (`channel`, `name`, absolute
  `path`, optional fragment `enabled`). Registry reuse does not imply selecting
  every Zim host or activating/building any channel.

Provider/consumer payload files, native profiles, policies and resources remain
with their deployments. The registry holds references, not declaration copies.
Listing an offer is not accepting it into consumer-owned membership.

# Public seams

The [registry guide](/runtime/registry/README.md) includes executable-source usage
and caller examples. Principal modules:

| Seam | Implementation | Contract |
|---|---|---|
| Domain<T> | [model](/runtime/registry/model.ts) | Caller decoder/identity/participation/audience; no central payload union |
| Invocation roots | [policy](/runtime/registry/policy.ts) | Explicit scope, env snapshot, low-to-high roots and one writable root |
| Read/list/explain/lookup | [reader](/runtime/registry/read.ts) | Whole-definition winners, detached root policy, per-entry payload errors |
| Owner registration material | [planner/delivery](/runtime/registry/register.ts) | Exact owner link, preserved local state, replanning guard, LINKS v1 material |
| Discovery/loading | [Figments adapter](/runtime/discovery/figments.ts) | One upstream integration seam; no duplicate scanner/resolver |
| CLI/completion | [Router/tab entry](/runtime/cli/registry.ts) | Source-runnable inspection/status/registration plus awaited ID completion |

`inspectRegistry(domain, policy)` returns `{collection, policy, complete, roots,
records}`. Each record exposes `id`, effective `state`, optional decoded `payload`
or `error`, plus Figments `source` with winner, all observations, participating
observations and conflict layers. `lookup(snapshot,id)` refuses incomplete views
and reports missing identities explicitly. Read-only inspection keeps invalid
entries visible rather than treating them as absent.

`planRegistration({domain,policy,source})` returns `create|current|blocked`, an exact
destination, effective participation, reason, guard and installable link material.
`register(request)` replans and uses existing
[`replaceWithLink()`](/files/links/delivery.ts#L133-L149). Current links need no
replacement. Generated installers can reuse material **after** registry policy
admission; blindly applying stale material through generic LINKS bypasses guards.

CLI entry is `node runtime/cli/registry.ts ...`. The source multicall also accepts
`node files/runtime/compfuzor-runtime.ts registry ...` through a lazy domain import.
Published Router **0.7.1** and tab **0.0.22** use Effect StandardSchema, with no Zod.
Requiredness comes from the schema; no guessed `required()`/`dynamic()` API. This
slice needs no checkpoint/resume. Tab callbacks run over an awaited snapshot.

# Participation, masks and writes

Disabled suffix and payload `enabled:false` remain separately visible in the source
and decoded payload. Filename storage and effective participation need not agree:
an active filename with `enabled:false` is disabled. Initial disabled registration
uses a disabled slot; reinstall retains existing slots, including case-preserved
`.JSON.DISABLED` spelling, and cannot activate an operator-retained disabled slot.

Masks are effective `/dev/null` control links, not disabled descriptions.
Registration returns blocked/no-link material and leaves both mask and underlying
definition unchanged. Removing a mask explicitly reveals retained disabled state.
Regular operator descriptions and links to a different owner cannot be overwritten.
Both local slots conflict even if a stronger overlay exists.

The initial helper is deliberately conservative about owner locator changes:
existing references must identify the requested exact source. A relocated owner
needs explicit operator reconciliation; automatic retargeting without an ownership
token would risk replacing an operator's declaration. No pruning, reload, sudo,
native validation, membership acceptance or payload mutation is implicit.

# Root policy and actual dependency integration

The default user layout is the rendezvous proposal implemented as replaceable
policy: reversed XDG data search roots, reversed config override roots, then
config `.mask.d` roots. Writable registration is data-home. System scope ignores
HOME/XDG and reads `/usr/share`, `/usr/local/share`, `/var/lib`, `/etc` Compfuzor
roots, writing only its `/var/lib` collection. These defaults need parent review
before generators depend on them. Caller-supplied absolute roots replace defaults;
duplicate locations retain their last occurrence to preserve precedence.

Missing optional roots are reported. Failed roots mark `complete:false`; lookup
and registration refuse that uncertainty and list exits 2 with root provenance.

`pnpm install @bomb.sh/router@latest @bomb.sh/tab@latest figmen-ts@link:../figments`
installed the dependencies and lock state. Figments' existing package main/types
point at unbuilt `dist`, but it has no restrictive export map. Therefore the adapter
imports existing `figmen-ts/src/*.ts` source subpaths, resolved through the relative
pnpm sibling link. **No production import embeds `/home/rektide` or another absolute
checkout path.** This requires the sibling source checkout and its dependency
closure (`confbox` through that package); it is source-development wiring, not a
published/distributed runtime promise.

Observed winners load through upstream `captureDropIns()` → `dropIns({source})` →
`Figment.build()`. This does not rescan or field-merge different descriptors. Root
resolution remains upstream `discoverDropIns()` / `resolveDropIns()`. Owned-file
registration loading is required exact JSON with ancestor search disabled and a
regular-referent check; resources/profiles named inside it are not opened here.

G's completed captured-loading/operator interface is consumed directly. Parent's
upstream final review can refine that seam without changing domain interfaces.
Topology verification and replanning are best effort, not reader isolation or
immutable bytes. Consumer admission must capture exact selected resources and
apply guards across its real CONFIG publication boundary.

# Evidence and commits

Coherent saved predecessors:

- `19b837a6` / `trsqvptt`: reusable registry, adapters, CLI/source multicall, source
  dependency wiring and initial isolated integration tests.
- `6c110fbd` / `qyxxlqww`: explicit policy validation, preserved observed spelling,
  special-referent refusal, independent participation reporting and stronger tests.

Checks completed against the implemented slice:

- `pnpm exec vitest run tests/registry-discovery/registry.test.ts`: **12 tests passed**.
- `pnpm check`: full configured format/lint checks, new `check:registry`, and `tsgo`
  all passed. New source and fixture/test TS are included in `check:type`.
- `pnpm fix:registry`: targeted formatting/lint passed without warnings.
- `node .test-agent/registry-discovery/implementation/demo.ts`: registered and
  inspected all three real filesystem fixture shapes under isolated XDG roots;
  repeated registration/status stayed current; disabled rename remained inert;
  added mask blocked reinstall. Scratch README explains retained fixture trees.
- CLI tests also invoke source multicall, reject unknown flags/invalid scope,
  exercise JSON explain/provenance, and produce tab's `deck-main\tactive` candidate.
- Test-emitted registration material successfully decodes through existing LINKS
  `loadManifest()`, in addition to actual link delivery through its shared primitive.

No live HOME/XDG/native configuration was changed. Preexisting unrelated working
copy modifications were preserved and excluded from owned commits. No push.

# Parent review / proposed next coherent slice

**Not implemented:** Ansible descriptor generation, generated self-registration
operations, native adapter extension, keybinding default-all batch admission,
consumer-owned candidate membership updates, runtime changed/canonical/deployed
selection, mask/unmask/enable/disable administrative commands, shell completion
installation, and deployable bundle cutover.

The consumer schema currently admits absolute profile paths or an env selector with
an absolute fallback, not all existing `PathSelector` forms. It validates inert
description consistency, not native profile existence/health. The fixture's
`deck-main` ID proves identity ≠ `niri` adapter; selecting/executing it is later work.

Recommended next checkpoint after reviewing this code:

1. Generate producer self-registration against its existing exact manifest;
   generate consumer-owned advertisements from host profiles. Bind rendezvous at
   invocation, not Ansible's rendering HOME. Preserve media-keys/Umbriel ownership.
2. Add a domain-owned receiver selection/admission batch using enabled, unmasked
   advertised consumers. Keep arbitrary receiver IDs apart from native adapters;
   settle explicit-disabled selection before adding execution policy.
3. Before authored effects, bind all requested receiver/profile/resource paths and
   capture selected registrations. If a producer registers during that operation,
   include its prospective offer explicitly or schedule a later named collection;
   never silently widen an already-admitted batch.
4. Feed candidate producer updates through existing membership/input-batch/CONFIG
   publication seams. Accepted membership and late patches remain consumer-owned;
   absence does not authorize prune/reconciliation.
5. Package the real dependency closure for generated launchers, then verify isolated
   generated installations against that artifact. The existing committed
   `runtime/compfuzor-runtime.mjs` intentionally remains **uncut-over**, so it does
   not yet advertise this new source-only registry domain.

# Cross-references

- [Symmetric rendezvous](/design/registry-discovery/rendezvous0.gpt6a.md) — authoritative
  shared-library direction implemented here; accepted membership remains downstream.
- [Ownership clarification](/design/registry-discovery/ownership0.gpt6a.md) — authoring
  material stays with the playbook; runtime contains tools rather than contributions.
- [Source evidence](/design/registry-discovery/evidence0.gpt6a.md) — verified Router/tab
  versions and existing CONFIG/Zim delivery/state contracts reused, not replaced.
- [Figments review](/design/registry-discovery/figments-review0.gpt6a.md) — upstream
  topology/captured-selection expectations now behind one small adapter.
- [Runtime sourcing direction](/design/runtime-sourcing/direction0-syn.gpt61sol.md) —
  changed/canonical/deployed and lean runtime delivery remain a distinct follow-on.
- [Receiver plan](/design/runtime-sourcing/receiver-plan0.gpt6a.md) — useful admission,
  action and CONFIG seams, read through the newer symmetric ownership direction.
- [Producer membership](/files/config/keybindings/membership.ts) — native integration
  must retain this closed accepted-state/publication contract rather than making
  rendezvous discovery a competing authority.
