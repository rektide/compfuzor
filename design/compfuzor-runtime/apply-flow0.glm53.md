---
type: Design proposal
title: apply as composed action and runtime flow
description: State of the world for apply-side composition (apply-* leaves, gen_bins compositors, runtime catalog flows) as observed on the iface playbooks, walked as a gradient ending in explicitly non-binding ideas.
resource: /design/compfuzor-runtime/apply-flow0.glm53.md
tags: [compfuzor, bins, apply, runtime, catalog, flows]
status: draft
generated: { by: agent:glm53 (GLM 5.3 max via OpenCode), at: 2026-09-26 }
verified: { by: none, at: null }
stale_after: 2026-11-15
sources:
  - id: this-session
    resource: ses_f21dff9f9ffexXD92U6fKYKgIb
    title: iface playbook hardening, workhorse redeploy, runtime audit
  - id: composer
    resource: /library/filter_plugins/bin_composers.py
    title: bin_composers filter (BIN_ACTIONS, phases, compositors)
  - id: catalog
    resource: /library/filter_plugins/runtime_catalog.py
    title: attributed catalog compiler (_ACTION, _ROOT, flows)
  - id: prior-assessment
    resource: /design/compfuzor-runtime/assess0.glm53fm.md
    title: compfuzor-runtime effort state of the world (Sep 18)
  - id: concurrent
    resource: /design/confext/runtime0.sm.md
    title: Runtime lifecycle seams under confext and btrfs pressure (Sep 26, concurrent)
  - id: execution-model
    resource: /design/config-anneal/execution-model0.gpt6.md
    title: Original attributed-flow checkpoint
---

# apply as composed action and runtime flow (apply-flow0)

## Overview: what's up

Two iface playbooks were hardened and deployed this week:
`systemd-iface-extra-addr.etc.pb` (live on workhorse as
`/etc/opt/systemd-iface-extra-addr-eno1`, drop-in verified idempotent no-op on
re-apply) and `systemd-iface-static-only.etc.pb` (awaiting a VPS). Both
hand-author a monolithic `apply.sh`. That choice bypassed compfuzor's existing
bin-composition machinery — machinery that already speaks `apply` — and left
the runtime catalog unable to represent apply as a flow at all.

This document is written **for the concurrent cf-runtime session** (confext /
btrfs / execution-model work). The operator's read: that session might already
provide what apply-flow wants, so everything below the state-of-the-world is
recorded as **SUGGESTION / IDEA — explicitly not a hard requirement**. Hold
implementation until that session has passed through here.

Research prompt, if one is wanted: *what would it take for `apply` to compose
like `install` does — `apply-*` leaves composed by gen_bins into an `apply.sh`
entry point, reflected as a first-class flow in the runtime catalog — and does
any of that fall out of (or conflict with) the confext/btrfs/execution-model
direction already underway?*

## State of the world (verified this session)

**Composition side — exists, and `apply` is already first-class:**

- [`bin_composers.py`](/library/filter_plugins/bin_composers.py) line 15:
  `BIN_ACTIONS = ("build", "install", "apply")`. Author an `apply-<thing>.sh`
  leaf and gen_bins emits a scope compositor `apply.sh` (plus
  `apply-<subsystem>.sh` when leaves group by subsystem), with `run_all`
  ordering by phase lanes (line 21: `packages/identity/main/units/records`),
  contributor attribution, and reserved-name checks.
- Wiring is automatic at [`gen_bins.tasks`](/tasks/compfuzor/gen_bins.tasks)
  line 15: `BINS | merge_list(BINS | bin_composers, preset='bins_generated')`.
- Live precedent for the leaf pattern: `apollo.src.pb` and
  `sunshine.src.pb` author `apply-udev.sh` leaves.
- The iface playbooks instead hand-author `apply.sh` — the canonical
  *compositor* name — with all logic inline. Nothing composes because there
  are no leaves. (Historical note: the shape predates this week; the hardening
  pass kept it.)

**Runtime side — `apply` is known as an action, unrepresentable as a flow:**

- [`runtime_catalog.py`](/library/filter_plugins/runtime_catalog.py) line 16:
  `_ACTION = ^(build|install|apply)(?:-|\.|$)` — so apply bins land in
  `actions[]` (workhorse's catalog carries `command:apply.sh` with
  `action: apply`, classified by filename).
- Line 17: `_ROOT = ^(build|install)(?:-([A-Za-z0-9_-]+))?\.sh$` and line 251:
  `flows = {"build": [], "install": [], "status": []}` — flow emission (lines
  258–273) requires a gen_bins-generated root compositor matching `_ROOT`.
  **A composed `apply.sh` would today be silently skipped for flows**, and no
  `apply` flow key exists to receive it.
- Deployment evidence (`/etc/opt/systemd-iface-extra-addr-eno1/compfuzor-runtime/catalog.json`):
  `"execution": {"authority": "legacy-shell", "catalogOnly": true}`. Flows
  present: `build` (empty), `install` (one legacy wrapper:
  `legacy:install:system:install-links.sh`), `status`. The only
  native-executing runtime piece today is the links subsystem
  (`compfuzor.links/v2` records consumed by `bin/links.mjs`); every flow entry
  is `native: false` with a `legacy-exit-v1` exec handler.

**Execution reality (deliberate, worth preserving):** apply is
operator-invoked, not deploy-chained — `bins_run.tasks` only auto-runs bins
with `args`/`run`/`exec` set, and iface apply deliberately stays manual
(`networkctl reconfigure` briefly drops the DHCP lease; the idempotence
short-circuit makes manual re-runs free). Composition should not silently
change *when* apply runs, only how it is assembled and described.

## The gradient

**L0 — today.** Monolithic `apply.sh`, hand-invoked. Works; zero composition;
catalog records the action but no flow. This is the state of both iface
playbooks and any playbook authoring bare `apply.sh`.

**L1 — classic composition.** Rename logic to `apply-networkd.sh` (leaf);
gen_bins emits `apply.sh` with the standard helper prelude and `run_all`.
Runtime-agnostic: valuable regardless of the runtime's fate. Buys: entry-point
standardization, ordering lanes if apply ever has multiple steps (e.g. a
future `apply-drift-check.sh` verify leaf), consistent attribution. Costs: the
playbook rework, and `apply.sh` stops being a file you read in the playbook
(becomes generated). Note this changes assembly only — invocation stays
operator-gated.

**L2 — catalog recognition.** `_ROOT` gains `apply`; `flows` gains an `apply`
key. Delta is ~3 lines plus a test, mirroring install exactly. Buys: the
catalog becomes a complete self-description; a future native executor could
run apply flows without new schema. Risk: the flows schema itself is
provisional (see below), so hardening it now could be wasted motion.

**L3 — runtime-native apply.** Apply flows actually executed/supervised by
the runtime; apply-state introspection alongside the status flow. This is
where the concurrent work plausibly lands — or where it decides the runtime
gets repackaged (confext/sysext) with a different lifecycle entirely.

## Asks for the concurrent cf-runtime session

Enumerated so they can be checked against that direction (answers welcome in
this directory or inline here):

1. **Composed apply entry points** — should deployments standardize on
   gen_bins-composed `apply.sh` over hand-authored monoliths (L1)?
2. **apply as a first-class flow** next to `build`/`install`/`status` (L2) —
   does the attributed-flow schema survive the execution-model reconsideration
   ([`execution-model0`](/design/config-anneal/execution-model0.gpt6.md)),
   and does confext repackaging change the answer?
3. **Apply-state introspection** — the iface idempotence short-circuit
   ("already applied: drop-in + address + DHCP route present") is effectively
   a status answer; should such predicates become status-flow entries,
   apply-flow preflights, or stay private to the leaf?
4. **Operator gating** — confirmation that composition never implies
   auto-execution at deploy time for network-touching applies.

## Suggestions / IDEAS (non-binding)

- **Idea A — leaf rework of the iface playbooks (L1).** extra-addr first as
  pilot: rename `apply.sh` → `apply-networkd.sh`, drop the hand-authored
  wrapper, let the composer emit `apply.sh`. Cheap, reversible, improves the
  two newest playbooks to the apollo/sunshine pattern. *Hold pending the
  concurrent session's read.*
- **Idea B — the L2 patch.** In `runtime_catalog.py`: add `apply` to `_ROOT`
  and `flows`. Only worth landing if the flows schema is expected to survive;
  otherwise it belongs in that session's consolidation.
- **Idea C — extra-addr as pilot canary.** Small blast radius, live
  verification loop, safe idempotence semantics; a good first deployment to
  exercise whatever apply-flow mechanism emerges, before k3s or anything
  stateful adopts it.

## Open questions

- Do apply flows want phase lanes distinct from install's
  (`packages/identity/main/units/records`), e.g. a `verify` lane for
  post-conditions like the DHCP-route wait?
- Does confext/sysext packaging change where `apply.sh` entry points live
  (deployment dir vs extension payload), making L1's shape different there?
- Should the iface playbooks' README/apply comments reference the composed
  shape once (if) it lands, so the documented manual invocation stays true?

## Cross-references

- [`assess0.glm53fm.md`](/design/compfuzor-runtime/assess0.glm53fm.md) —
  prior state-of-the-world for this same effort: the "one runtime, not many"
  philosophy, catalog flow-execution blockers, dormancy. This doc's L2/L3 sit
  directly on top of those blockers.
- [`runtime0.sm.md`](/design/confext/runtime0.sm.md) — the concurrent
  assessment this doc defers to: confext-first packaging and btrfs subvolume
  lifecycle pressures on the same runtime.
- [`execution-model0.gpt6.md`](/design/config-anneal/execution-model0.gpt6.md)
  — originating attributed-flow checkpoint; the schema whose survival
  determines whether Idea B is motion or waste.
- [`systemd-iface-extra-addr.etc.pb`](/systemd-iface-extra-addr.etc.pb) and
  [`systemd-iface-static-only.etc.pb`](/systemd-iface-static-only.etc.pb) —
  the L0 exemplars and Idea A/C subjects.
- [`doc/k3s-drift-recovery.md`](/doc/k3s-drift-recovery.md) — the operational
  context that makes the iface apply semantics (DHCP-authoritative, lease-blip
  aware) what they are; any apply-flow mechanism must respect it.
