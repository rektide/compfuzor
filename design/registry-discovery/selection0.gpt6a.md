---
type: DesignClarification
title: Invocation-only force-enable for registered participants
description: Record the operator's force-enable decision and the registration, root-policy and selector refinements directed at the generated-installation checkpoint.
resource: /design/registry-discovery/selection0.gpt6a.md
tags: [registry, selection, disabled, masks, keybindings, admission]
status: draft
generated: { by: model:gpt6a, at: 2026-10-07 }
verified: { by: unverified }
stale_after: 2026-11-07
sources:
  - resource: /design/registry-discovery/rendezvous0.gpt6a.md
    title: Symmetric self-registration and domain pipeline selection
  - resource: /design/registry-discovery/implementation0.gpt61s.md
    title: First executable Compfuzor slice reviewed before generator integration
  - resource: /design/registry-discovery/direction0.gpt6a.md
    title: Earlier open question about explicit disabled selection
---

# Operator decision

Asked whether explicitly naming a disabled consumer should activate it once or
require persistent enable, the operator answered:

> add a --force-enable mode that skips disabled directives

This supersedes the earlier recommendation that persistent enabling be required.
The implementation instruction sent to Sol medium is:

- Ordinary automatic selection excludes disabled registrations.
- An explicitly named disabled registration reports its disabled state and points
  to `--force-enable`.
- With `--force-enable`, disabled registrations become eligible **for this
  invocation**. This covers `.disabled` storage state and `enabled: false`
  registration metadata, in both default-all and explicit-subset selection.
- Stored names and enabled settings retain their prior state.
- Effective masks still veto execution. Audience, schema, profile, adapter
  compatibility and native validation remain required.
- Admission records the chosen override and original state/provenance; later argv
  changes cannot alter an already-admitted selection.

Read-only listing/explanation already includes inert registrations. The override
belongs to pipeline selection/execution rather than hiding state during inspection.

The question and decision concern registration-level participation. Consumer-owned
producer-group disables and per-binding/action enabled values remain distinct
domain policy. The implementation must not reinterpret every nested `enabled`
field as a registration directive.

# Registration and effective participation

The first executable slice correctly preserves owner-held payloads and exposes
them through references. Parent review directed one refinement before generator
cutover: **passive publication and execution eligibility are separate outcomes**.

A higher mask can keep an offer inert while its owner registers or refreshes the
reference in a lower writable registration layer. The mask stays in place and
listing reports it. A mask occupying the actual writable slot cannot be replaced
by ordinary registration.

Registration plans should therefore distinguish local publication status from
effective participation. The same applies when a higher operator description or
disabled declaration shadows the owner's reference. Applying native work still
uses the effective view and the explicit force-enable policy above.

# Other parent-reviewed integration requirements

These refinements accompany the next code slice:

1. **Generic collection locations.** Validate safe domain-grouped relative paths,
   rather than limiting the reusable root helper to names ending in providers.d
   or consumers.d.
2. **Audience-separated shared roots.** System receiver registrations need a
   distinct namespace from shared user offers in XDG data roots; identical IDs
   for different audiences must not collide or become invalid user declarations.
3. **Config root-major precedence.** Within config policy, order each root's
   definitions and masks together, low to high, preserving XDG precedence.
4. **Existing profile selectors.** Reuse Compfuzor's portable path/env/default/
   ignore forms. Registry inspection validates descriptions; selected invocation
   binds the environment and native profile.
5. **Completion correctness.** Tab option definitions use logical undashed names;
   verify flag names/values as well as dynamic identity suggestions.

Sol medium is implementing the generated-registration and advertised keybinding
admission slice against these requirements. Figments remains the reusable
inventory/selection-loading dependency; consumer membership/native publication
remains under the existing CONFIG commit contract.
