---
type: ImplementationCheckpoint
title: Combined prospective admission and coherent registry policy pairs
description: Bounded closure of combined first installation, exact publication transitions, captured selection policy and public isolated SYSTEM registry policy pair, with successor migration references.
resource: /design/registry-discovery/implementation2.gpt61s.md
tags: [registry, prospective, combined, policies, system, checkpoint, handoff]
status: draft
generated: { by: model:gpt61s, at: 2026-10-07 }
verified: { by: model:gpt61s, at: 2026-10-07 }
stale_after: 2026-11-07
sources:
  - resource: /design/registry-discovery/implementation1.gpt61s.md
    title: Generated/native predecessor
  - resource: /design/registry-discovery/handoff0.gpt61s.md
    title: Code successor handoff
  - resource: /design/registry-discovery/regression-map0.gpt61s.md
    title: Independent read-only acceptance/doc migration inventory
  - resource: /tests/integration/registry_combined_generated.test.py
    title: Real combined and SYSTEM proof
---

# Bounded seam closed

Combined producer+consumer first installation now succeeds when the consumer
advertisement is initially absent. Owner-held selection declares exact scoped
prospective consumer references; these remain separate from observed registry
records. Existing effective records/control take precedence. Admission performs no
publication and fixes only explicitly declared/observed eligible candidates.

Generated combined actions execute owned host bootstrap/native publication before
the producer's admitted batch. Multiple operations prepared against absence accept
only that exact planned publication. Reinstall and explicit subset work; neither
requires a late collection widening nor conflates receiver IDs with native formats.
Saved disable flags, masks and consumer-owned accepted group state retain the prior
contract. `--force-enable` remains one-invocation registration policy only.

# Reviewed issues and actual interfaces

| Issue | Implemented closure |
|---|---|
| Selection read then separate capture | Parse the same `CapturedFile` bytes used for its guard; intervening edits invalidate execution |
| Fresh provider snapshot blesses new mask | Remove post-publication snapshot admission; original `RegistrationPlan.expectation` guards every native member and closure hook |
| Higher producer silently redirects manifest | Effective provider must agree with explicit owner operative version/identity/order/resources/native targets; only enabled participation can differ |
| Mixed-audience list lookup | Filter scope/actionContexts before constructing the selected subset; an explicit other-audience CLI ID fails clearly |
| Combined absent→published race | Reusable exact transition guard with unchanged other observations/slots and byte/physical-parent guards; exact already-published state is idempotent |

[`RegistryGuard`](/runtime/registry/guard.ts) now carries optional admitted publication
source/destination, captured slot states and file guards. `verifyRegistryGuard()`
accepts `before|published`, never arbitrary same-ID content. It still uses Figments
observation/resolution. Failed roots remain errors. Alternative slots/directories,
new masks/conflicts/foreign references, descriptor changes and changes to higher/
lower declarations reject pending work. `applyRegistration()` verifies both sides
of delivery and tolerates another admitted operation publishing that exact reference.
These are observed-state guards, not locks/crash atomicity.

[`SelectionPolicy`](/runtime/keybindings/invocation.ts) adds
`prospectiveConsumers:{user|system:[PathSelector]}`. References bind relative to the
owner-held selection document and parse/capture before authored effects. They join
only missing observed identities, with native profile/resource admission and normal
mask/disabled/force/audience/adapter checks. The fixed member array survives exact
host publication. Explicit `receivers:[]` remains no producer delivery.

[`bindRegistryPolicies()`](/runtime/keybindings/policy.ts) binds one complete pair
from public `--registry-policy PATH` / typed `registryPolicy` / generated
`KEYBINDING_REGISTRY_POLICY`. Inspectable document schema:

```json
{"version":1,"audiences":{"system":{
  "providers":{"roots":[{"relative":"system/providers.d"}],"writeRoot":{"relative":"system/providers.d"}},
  "consumers":{"roots":[{"relative":"system/consumers.d"}],"writeRoot":{"relative":"system/consumers.d"}}
}}}
```

Both selected sides are mandatory; missing side/audience refuses fallback. Roots
use the shared PathSelector and concrete explicitPolicy contracts. Only no override
uses ordinary defaults. The same bound pair reaches provider publication, consumer
selection, owned-host admission/publication and their guards, with captured policy
bytes in typed transport. Passive register/status also accepts the public locator.
Generated wrappers carry only the owner document locator, not controller-expanded
HOME registry paths. USER offers and SYSTEM namespaces remain separate.

# Evidence

- `pnpm check`: configured format/lint and tsgo passed.
- Focused regression: **10 files / 55 tests passed**, covering registry discovery,
  action audiences and retained pure/native/source-registration boundaries.
- Expectation tests: missing→exact link, independently preplanned already-published
  idempotence, foreign publication, masks before/after publication, descriptor edit
  and alternate slot rejection.
- Admission tests: prospective input without admission writes, scoped mixed targets,
  effective producer resource/order redirect rejection, a mask injected immediately
  after publication preventing native work, and captured policy edit rejection.
- Public SYSTEM source tests spy on actual observed roots for both producer and
  host admission: only explicit disposable policy roots, no default `/var/lib`,
  `/etc`, XDG or ambient HOME registry lookup. Missing selected policy sides refuse
  default fallback.
- `registry_combined_generated.test.py`: actual generated combined first install,
  pre-body absent-advertisement marker, host-before-producer CONFIG work, reinstall,
  explicit subset, public portable USER/SYSTEM pair, separate same-ID scoped links,
  native failure preserving membership/root and copied registration rollback, and
  pre-body mask veto all passed using real Niri/native workers.
- Existing `registry_keybindings_generated.test.py` stayed green: unchanged current
  media-keys values, actual Niri/Umbriel declaration/authored-body generation,
  named Niri, Zim passive offer endpoints, force/disable/mask semantics and actual
  native rejection/rollback. It is real generation/materialization from an allowlist
  of playbook vars, **not** a full package/provisioning playbook invocation.
- `pnpm build` refreshed the real committed dependency closure (~1.17 MB). Receiver
  deployments need no sibling checkout/node_modules; source development stays `.ts`.

# Saved stages / successor

- `92f2dcf6` / `ltsporzw`: reusable exact transitions, same-capture admission,
  coherent policy pair, prospective candidate joining, typed/public/generator wiring.
- `99e516f3` / `kumvpoux`: refreshed deployment closure, combined/SYSTEM/native
  rollback proof and default-root-access coverage.
- Prior predecessors and complete source interfaces are in the
  [code handoff](/design/registry-discovery/handoff0.gpt61s.md).

The independent [regression/doc map](/design/registry-discovery/regression-map0.gpt61s.md)
is the successor's inventory. Its inspected predecessor observations about missing
combined/policy interfaces are now superseded by this bounded slice; its retained
acceptance matrix is not superseded. Do not restore retired producer-per-adapter
wrappers/defaults to make obsolete assertions pass. Do preserve two-producer
ordering/shrinking/empty acceptance, edited copy/link behavior, actual full-playbook
placement/adoption, detailed Media Keys/Vicinae semantics and transport/signal tests.

Remaining broad work: intentionally migrate those old integrations and maintained
guides; add registry enable/disable/mask/unmask administration; consume registered
Zim offers through domain host policy; consumer-driven offered-provider collection
(host assemble still reads accepted membership only); adapter extension beyond
Niri/Umbriel; separate changed/canonical/deployed runtime-source selection. None is
claimed complete here. No implicit pruning/reconciliation or global transaction.

Final checkpoint budget observation: **404,514 current/last-reported tokens
(41%)**, not lifetime totals. Handoff preparation began around347k; this session is
handing off at the ~400k target, below the450k stop. No extra agents were spawned and no live
registries/native configuration were changed. Parent/user work remains excluded from
owned explicit commits.
