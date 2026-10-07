---
type: InquiryBrief
title: Surface Dial precision layers and sideways modifier state
description: Explore smaller baseline steps, a keyboard-Shift precision layer, observable action selection, and daemon-side state transport.
resource: /design/surface-dial-layers/brief0.gpt61s.md
status: draft
generated: { by: model:gpt-6.1-sol, at: 2026-10-06 }
sources:
  - resource: /design/surface-dial-input/assessment0.gpt61s.md
    title: Previous installed-Umbriel and dial input assessment
---

# Situation and revised intent

The user now thinks existing fine adjustment may work. This is a new behavior inquiry, not a confirmed missing-Shift bug: make normal dial ticks significantly smaller, reduce the ratio between normal and finer increments, and add an even-finer action when **physical keyboard Shift is also held**. Exact amounts and the ratio's interpretation remain to be agreed.

The current daemon emits its own Shift+Volume chord, so additional physical Shift does not create another modifier bit at Umbriel's shortcut matcher. The proposed new modality needs a distinguishable state or action vocabulary. It may be a layer rather than another ordinary chord.

# Requested investigations

1. Start with the Surface Dial systemd unit: identify the running daemon/build/config and what logs or interfaces distinguish normal and finer events.
2. Explore daemon-owned actions and a stateful sideways channel: remote variable updates, modifier-state ownership, transport options, and failure/reconnection semantics. Avoid assuming that Kanata consolidation preserves physical Shift identity.
3. Learn Kinefolk for background and register this idea there, without treating it as a deployment dependency. The available checkout is `~/src/kinefolk-rs`, not the requested shorthand `~/src/kinefolk`.
4. Parent assessment: verified Umbriel IPC/input capabilities, preservation of a separate physical modifier signal, and whether a reserved key such as F24 is necessary or just one encoding option.

# Boundaries

- Investigation and idea registration only; no service restarts, grabs, injected keys, live binding edits, or hardware/profile writes.
- Preserve existing media-key actions for ordinary keyboards unless explicitly agreed otherwise. Dial-specific precision need not silently redefine global keyboard behavior.
- Keep current baseline Shift, physical keyboard Shift, selected control mode, and precision layer separate in terminology.
- Prefer source-verified capabilities over speculative API syntax; distinguish an existing facility from a proposed protocol.
- Capture individual G findings independently before synthesis. Authors commit their own coherent documents, with current model suffixes and canonical references.

# Prior evidence

- [Overall input assessment](/design/surface-dial-input/assessment0.gpt61s.md): installed Umbriel already aggregates modifier masks, while stock dial ticks carry their own Left Shift.
- [Kanata assessment](/design/surface-dial-input/kanata-assessment0.gpt61s.md): consolidation and candidate chaining work in principle but lose input identity and introduce same-key release collisions.
- [Earlier dial diagnosis](/design/surface-dial/diagnosis0.glm53.md): historical bindings installation and synthetic fine-step success; not evidence for a newly selected precision layer.

# Research prompt

How can Surface Dial select an observable, smaller normal increment and an additional keyboard-Shift precision layer while keeping keyboard modifier provenance separate from its own synthetic Shift? Compare verified unit/config/protocol facilities, compositor IPC or distinct-key encodings, and daemon-side action ownership; record Kinefolk's relevant future extension without requiring it for deployment.
