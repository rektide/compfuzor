---
type: ResearchBrief
title: Registries, receiver roles, and layered discovery
description: Broaden the receiver-mask plan using existing Compfuzor mechanisms, disabled declarations, XDG layering precedents, and Bombshell CLI tooling.
resource: /design/registry-discovery/init0.gpt6a.md
tags: [registry, catalog, receivers, configuration, discovery, xdg, cli]
status: draft
generated: { by: model:gpt6a, at: 2026-10-06 }
verified: { by: unverified }
stale_after: 2026-11-06
sources:
  - resource: /design/runtime-sourcing/receiver-plan0.gpt6a.md
    title: Earlier keybinding-specific implementation plan
  - resource: /mise2.opt.pb
    title: Operator-supplied Mise deployment example
  - resource: /zim2.opt.pb
    title: Operator-supplied Zim host and disabled module roster
---

# What changed

The operator wants to expand the problem before implementing the earlier
[receiver-specific plan](/design/runtime-sourcing/receiver-plan0.gpt6a.md).
Important directions from the conversation:

- A target can **profess or be configured disabled**, retaining its configuration
  while remaining inert. A `.disabled` filename is a possible blunt representation.
- **Keep masks as well.** Disabled participation and an overriding mask are
  different concepts; their exact selection behavior needs a deliberate contract.
- Receiver is already an implicit role in Compfuzor's CONFIG/Zim work. Examine
  `mise2.opt.pb` and `zim2.opt.pb`; trace how Zim gains contributors and finds hosts.
- Investigate whether receiver/target collections share useful machinery with
  the existing catalog. Consider **registry** for declaration/registration lookup
  to avoid overloading catalog; do not decide by vocabulary alone.
- Collection-like structure may recur. Explore composability and useful bounded
  nesting without committing to arbitrary recursive discovery.
- Layered configuration matters beyond this immediate feature. Inspect the local
  TypeScript projects `~/src/figments`, `~/src/firmaments`,
  `~/src/gunshi-dirs-xdg`, and `~/src/xdgox` for actual capabilities and precedents.
  The operator reports Firmaments is unstable and its dependency system intricate;
  distinguish standalone overlay capabilities from live graph machinery.
- Use [`bombshell-dev/router`](https://github.com/bombshell-dev/router) for the
  intended CLI and investigate the requested `tabs` (likely Bombshell's
  [`tab`](https://github.com/bombshell-dev/tab)). Gunshi itself is not the desired
  CLI dependency. Interactive prompts are a possible later concern.

# Investigation questions

1. What do the current workload catalog, CONFIG input collections, Zim host link,
   Zim contributor roster, keybinding membership and Mise cache catalog actually
   own? Which are authoritative for selection or execution?
2. What should a shared module know about identity, source layers, disabled slots,
   masks, provenance, listing and explicit writes? What stays domain-specific?
3. Does target describe a registered object, or the role of a selected destination
   in an operation? How does that differ from a receiver that accepts contributions?
4. Which XDG-root expansion, globbing, drop-in loading and layering behavior exists
   in the named projects? Which claims are design-only?
5. Can configuration overlays be tried using Figments and standalone Firmaments
   without making dynamic dependency management part of receiver discovery?
6. Which Router/tab interfaces really exist, and how do they preserve strict
   admission and read-only completion for the proposed CLI?

Research prompt: *Trace existing collection and receiver mechanisms in Compfuzor,
then propose the smallest shared registry/discovery interface that preserves
domain-specific admission and publication. Treat disabled state, masks, source
precedence, and invocation selection as separate decisions. Ground library reuse
in the local TypeScript implementations and current Bombshell source.*

# Checkpoints

Record source-backed findings first, then revise the architectural plan. Preserve
the earlier plan as the predecessor. The first new implementation should exercise
shared machinery with at least two real domains while keeping each domain's
selection and lifecycle explicit.
