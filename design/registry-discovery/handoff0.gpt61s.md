---
type: ImplementationHandoff
title: Registry prospective publication and policy pair continuation
description: Successor notes for the bounded combined first-install and coherent registry-policy seam; maintained while implementation completes.
resource: /design/registry-discovery/handoff0.gpt61s.md
tags: [registry, handoff, prospective, publication, policies, keybindings]
status: draft
generated: { by: model:gpt61s, at: 2026-10-07 }
verified: { by: unverified }
stale_after: 2026-11-07
---

# Starting point and budget

Parent approved the bounded continuation of [implementation1](/design/registry-discovery/implementation1.gpt61s.md):
explicit audience-scoped packaged prospective consumers; exact before→intended owner
publication guards; host bootstrap before combined producer; one public versioned
provider/consumer policy pair; no admission writes or late membership widening.
Human `--force-enable` remains invocation-only registration policy, never a mask or
consumer group/binding/action override.

Latest measured context entering handoff preparation: **346,827 tokens (35%)**.
Aim to finish/hand off around400k, stop by450k without explicit parent exception.
This is current/last-reported usage, not lifetime totals.

Final measurement: **404,514 current tokens (41%)**. Bounded seam is committed and
verified; hand off now rather than starting broad migration in this context.

# Saved predecessors

- `f312f304`: passive/scoped/root-major registry corrections.
- `115955a6`: native batches/typed force and closure guards.
- `b8c26e25`: generated owner endpoints and first native artifact proof.
- `ffd01dd2`: stronger guards/resource/selector admission and regression proofs.
- `7c6acd74`: executable checkpoint and remaining architectural seams.
- `92f2dcf6`: exact prospective publication expectations and coherent public policy pair.
- `99e516f3`: refreshed closure and real combined/SYSTEM/native rollback proof.

# Bounded seam completed

1. [RegistryGuard](/runtime/registry/guard.ts) now models optional exact publication
   with captured pre-state, source/destination, both physical slot observations and
   descriptor byte guards. Verification accepts unchanged before or only the exact
   intended symlink with unchanged other same-ID observations/slots; failed roots
   remain failures. It uses upstream observation/resolution, not a new scanner.
2. [RegistrationPlan](/runtime/registry/register.ts) captures/parses owner bytes once,
   carries that expectation, verifies before/after delivery and accepts an already
   published exact transition idempotently. Passive overlays still do not imply
   activation. Native callers must gate original effective state before effects.
3. [Policy binder](/runtime/keybindings/policy.ts): owner-held document schema
   `{version:1,audiences:{user|system:{providers:{roots:[PathSelector],writeRoot:PathSelector},consumers:{roots:[PathSelector],writeRoot:PathSelector}}}}`.
   Supplied selected audience requires BOTH sides; no missing-side/audience fallback.
   Relative selectors use the policy document's physical directory. Defaults only
   apply when no policy was supplied. Public `--registry-policy`/typed field are
   are wired. Generated `KEYBINDING_REGISTRY_POLICY` compiles portable selectors into
   the owner-held document and passes its locator to native and passive endpoints.
4. [Batch admission](/runtime/keybindings/invocation.ts) parses selection from captured
   bytes, filters receiver declarations by audience before lookup, checks effective
   provider operative agreement (ignoring only enabled participation), adds scoped
   `prospectiveConsumers:{user|system:[PathSelector]}` to the candidate set only when
   no observed identity exists, and uses admitted publication expectations instead
   of blessing fresh post-publication provider snapshots.
5. Owned host admission uses the same policy pair and publication expectation, so
   multiple admitted operations may see the exact planned reference already present.

# Completed acceptance / entrypoints

- All five parent source-review issues are closed in this bounded slice. Selection
  policy parses its own captured bytes; provider post-publication is checked against
  the admitted transition, never a newly trusted snapshot; operative provider
  redirects reject; authored target lists filter audience before lookup; exact
  missing/current publication is idempotent with unchanged other observations/slots.
- Generator emits scoped prospective descriptions and orders owned host bootstrap
  before generic producer delivery. Shared `--target` flags narrow producer receiver
  delivery; typed owned-host bootstrap keeps its declared native format.
- Public `--registry-policy PATH`, typed `registryPolicy`, and generated policy data
  bind the same provider/consumer pair. Missing selected audience/side never falls
  back. Roots use PathSelector + explicitPolicy, with captured policy document guards.
- Source acceptance: **10 files/55 focused tests passed**, `pnpm check`, compiler
  tests. Native generated acceptance: both `registry_combined_generated.test.py`
  and existing media-keys/Niri/Umbriel/Zim generated proof passed against refreshed
  real committed bundled closure (~1.17MB). Combined first install body proves no
  admission publication; reinstall/subset, isolated public SYSTEM pair, no default
  registry access, copied YAML/membership/root native failure rollback all covered.
- Normal passive publication can remain underneath masks; native eligibility still
  rejects them even under force. Existing accepted groups/order/dormant patches,
  per-binding/action flags and CONFIG commit/rollback remain consumer-owned.
- Read [implementation2](/design/registry-discovery/implementation2.gpt61s.md) and
  [registry guide](/runtime/registry/README.md) before extending. Preserve unrelated
  working-copy changes, including newer Kanata work and parent docs. Explicit
  owned paths only; no push/edit/squash or automatic cleanup.

# Already verified before this bounded continuation

46 focused tests, full configured `pnpm check`, compiler tests, current bundled
media-keys/Niri/Umbriel + named Niri/Zim generated native proof and playbook syntax
checks passed. Broad native Vitest aggregate timed out at120s; do not rerun blindly.
Older `action_domains` fixture has system native roots without isolated registry
roots; never run it into live `/var/lib` while migrating. The shared-root false
replanning failure it initially exposed was fixed/tested.

# Broader destination (not this bounded slice)

Parent's read-only successor agent completed the old test/doc inventory in
[`regression-map0.gpt61s.md`](/design/registry-discovery/regression-map0.gpt61s.md).
Use that report rather than repeating corpus exploration. Still outstanding:
registry enable/disable/mask/unmask administration; Zim host/provider registry
consumption (current bridge remains legacy); consumer-driven offered-provider
collection (host assemble currently reads accepted membership only); full old
integration/doc migration; separate changed/canonical/deployed runtime sourcing.

Priority successor work from that verified source inventory (do not discard its
retained acceptance): migrate `keybindings_target_defaults`, `keybindings_generated`
and dependent empty-producer/dependencies fixtures; then paired-policy
`action_domains`/`action_placement`; then full-playbook consumer-host/media-keys/
Vicinae/SteamOS semantics and orthogonal action-audiences. Obsolete assertions are
producer-per-adapter wrappers/shared defaults/adapter-as-ID, not host wrappers,
exact native chords, update/ordering/no-prune/copy-edit and pre-body transport safety.

Maintained docs needing updates: `/doc/config/keybinding-producers.md`,
`/doc/config/keybinding-consumers.md`, `/doc/actions/README.md`, `/doc/config/README.md`,
Zim parts of `/doc/config/consumer-toolkit.md`, and outer-layer links in
`/doc/config/keybindings.md`. Runtime registry guide now covers the verified bounded
pair/prospective seam. The independent regression map's predecessor claims about
missing combined/policy support are superseded; its coverage matrix remains useful.

Long source processor/consumer tests need separate adequate outer limits; the
earlier 120s aggregate timeout is not green. No broad migration is claimed here.
