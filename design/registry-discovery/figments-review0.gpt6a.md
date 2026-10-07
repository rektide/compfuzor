---
type: ImplementationReview
title: Figments discovery substrate checkpoint and loader integration direction
description: Parent code review of G's discovery foundation, targeted regression observations, and the authorized captured-loader integration slice.
resource: /design/registry-discovery/figments-review0.gpt6a.md
tags: [figments, registry, discovery, review, disabled, masks]
status: draft
generated: { by: model:gpt6a, at: 2026-10-07 }
verified: { by: model:gpt6a, at: 2026-10-07 }
stale_after: 2026-11-07
sources:
  - resource: /design/registry-discovery/rendezvous0.gpt6a.md
    title: Registry library and symmetric self-registration direction
  - resource: https://github.com/rektide/figments/blob/main/src/discovery/entries.ts
    title: Locally implemented filesystem inventory
  - resource: https://github.com/rektide/figments/blob/main/src/discovery/resolve.ts
    title: Locally implemented whole-entry registry view
  - resource: https://github.com/rektide/figments/blob/main/src/core/xdg.ts
    title: Config/data search roots with an explicit environment
---

# Reviewed checkpoint

G completed the first substrate slice in `~/src/figments`, ending at change
`nmospmux`. The parent read the implementation and behavioral tests, including
the new discovery/resolve modules, literal `Keyed` provider, XDG helpers and the
written proposal/revision. Canonical source links above are navigation references;
this review describes the local checkpoint before the next corrections.

Implemented capabilities at that point:

- topology-aware inventory of owned-file symlinks, disabled slots and direct
  `/dev/null` masks;
- registry identity resolution with provenance and retained underlying observations;
- literal provider key segments, including dotted and numeric IDs;
- invocation-environment config/data search roots;
- a small Tuple syntax change allowing plain Node 26 source imports.

G reported **47 files / 439 tests passing**, plus typecheck, format and lint
(one preexisting lint warning). The parent accepted that verification report and
ran a separate targeted probe for concerns found in source review. The existing
`dropIns()` operator was deliberately still unchanged at this checkpoint.

# New parent probe

Source: `.test-agent/registry-discovery/review-substrate.ts` in Compfuzor.
It uses real isolated directories and imports Figments source directly on Node 26.

| Case | Observed checkpoint behavior | Required correction |
|---|---|---|
| Highest mask over a lower active/disabled collision | `conflict` | Effective mask wins; retain lower conflict for explanation |
| Same configured root listed twice | `conflict` | Distinguish source occurrences; do not invent a same-layer duplicate file |
| Relative discovery root | Captured entry path remains relative | Bind concrete paths during discovery so later cwd cannot redirect loading |
| Supplied `HOME: "relative-home"` | Relative XDG data root | Require an absolute usable fallback or report the invalid environment |

Other source-review findings sent to G:

- Follow-up metadata catches in root-error classification still swallow unexpected
  failures as missing. Preserve acquisition failure provenance.
- Resolution checks a mask before its attached observation error; failed observation
  must not be accepted as a successful control declaration.
- Explicit mask recognition is unnecessarily coupled to ordinary symlink following.
  Recognized control links should work when ordinary payload symlinks are skipped.
- The test labelled chained `/dev/null` currently uses an ordinary relay file;
  replace it with a real symlink chain. Check relative referents beneath a
  symlinked root as well.
- A resolved view should retain root reports/completeness evidence, so an unreadable
  higher root does not masquerade as a complete successful lower-layer selection.

# Authorized next slice

G is authorized to correct those findings and integrate the operator, in coherent
commits, before returning for final parent review.

The integration must preserve the two distinct composition contracts:

1. **Layered loading:** the existing root-major, filename-ordered chain remains
   available, including field merging from same-named files across roots.
2. **Whole-entry loading:** explicitly selected registry identities resolve to
   effective definitions without accidentally combining different owned descriptions.

Disabled/mask controls must have documented behavior in each mode. An effective
mask remains unselectable. Caller policy can deliberately include a disabled
definition at the library level; Compfuzor's eventual execution policy remains a
separate decision.

The captured-loading interface must retain the inspected observations and exact
membership, detach caller-owned selection data, avoid rescanning, and diagnose
removed/type-changed/retargeted sources. Required files must not become optional
empty contributions or trigger ancestor searches. Payload bytes are still reads
at a later point; the interface must state its observation/race limits accurately.

The final example should use the operator to inspect and load selected symlinks to
producer/consumer-owned descriptions outside the rendezvous roots. This exercises
the user's actual [registry-library model](/design/registry-discovery/rendezvous0.gpt6a.md),
rather than merely composing a manually prepared object.
