---
type: ImplementationBrief
title: Optional Kanata dial contribution and TCP precision relay
description: Implement kanata-dial.etc.pb as a separately selectable media-key enhancement, leaving Surface Dial unchanged and defining keyboard-to-dial TCP signaling.
resource: /design/kanata-dial/brief0.gpt61s.md
status: draft
generated: { by: model:gpt-6.1-sol, at: 2026-10-07 }
sources:
  - resource: /design/surface-dial-layers/dial-remap0.gpt61s.md
    title: Device-scoped normalization and media-keys ownership
  - resource: /design/surface-dial-layers/tcp-scheme0.gpt61s.md
    title: Verified TCP layer/virtual-key interfaces and signaling limits
  - resource: /doc/input/kanata.md
    title: Existing source binary and service ownership
  - resource: /doc/config/keybinding-producers.md
    title: Separate producer membership and explicit enable/disable
---

# User authorization

Use Sol M to implement `kanata-dial.etc.pb`, enhancing media-keys as a separate contribution that can be toggled on/off. This should pioneer TCP control; the user asks how the keyboard instance can send the virtual signal. No live deployment or input-service reconfiguration was requested yet.

# Agreed direction and remaining choices

- Do not modify Surface Dial source or add a TCP consumer there. Intercept its existing virtual keyboard in a dedicated Kanata instance.
- Keep volume actions in the media-key producer/contribution layer, not in Umbriel or a new dial actuation engine.
- Kanata is a TCP server, not a built-in peer client: keyboard layer/events are published to a relay, which sends `ActOnFakeKey` to the dial instance.
- Distinguish whole-extension enablement from the momentary precision bit. Disabling the enhancement should fall back to existing media volume behavior, not leave F-key events unbound or a precision key held.
- Current user-authored media actions are `0.03` plain and `0.01` Shift. Preserve these edits. Proposed extra precision `0.005` is only a configurable initial candidate; amounts remain a user decision.

Subsequent user confirmation: [decisions0](/design/kanata-dial/decisions0.gpt61s.md) selects **`0.003`** and enhancement-only OFF with legacy fallback. The earlier numeric candidate is retained here as inquiry history, not the implementation default. Device-ID work is parked while this contribution is finished.

# Functional TCP encoding candidate

To avoid a redundant relay whose effect is already supplied by compositor keyboard Shift, consider:

1. Dial-only Kanata consumes raw synthetic `lsft` from the dial.
2. Baseline volume emits the legacy `Shift+Volume` chord on its isolated output, so existing media-keys fine actions remain the fallback.
3. Holding an internal `precision-hold` virtual key selects a temporary dial layer that emits F23/F24 instead.
4. The separate keybinding contribution maps F23/F24 (plain and keyboard-Shift variants) to extra-fine actions. The emitted vocabulary now genuinely depends on TCP layer control, using only two reserved direction codes.
5. Main excludes the raw dial node and renamed normalized output. Main's keyboard signal is therefore not contaminated by the dial's synthetic Shift; no raw/output re-grab loop is created.

This is a candidate to validate at the implementation checkpoint, not an accepted live key allocation. Other dial keys, wheel, and Zoom semantics must remain accounted for.

# Keyboard signal boundary

A small transparent momentary keyboard layer driven by physical Left/Right Shift can publish `LayerChange`, including initial/reconnect state, while still outputting normal Shift. The current main map has only a base layer; a layer-name signal is therefore a plausible first adapter, not a general held-bit snapshot for arbitrary future layer stacks. Explicit `push-msg` signals are another option, but need snapshot/liveness design. Preserve existing caps/device semantics, including the live-versus-authored Kinesis drift; do not silently adopt kinata.

The relay must define source unknown/disconnect, target restart, duplicate states, clean shutdown, crash recovery, and release/reset. Kanata does not release a remotely pressed virtual key automatically when the client disconnects.

# Deployment and implementation checkpoints

First coherent slice: code the TCP relay and mock-server tests, draft the separately selectable producer/playbook and dial config, and report exact main/service integration and toggle contracts. Do not edit/redeploy the main input config or open ports before parent review.

Investigate a shared private network namespace (`JoinsNamespaceOf` + `PrivateNetwork`) as a way to connect keyboard/dial/relay loopback endpoints without exposing unauthenticated keyboard control to all host-local users. Verify current systemd capabilities before selecting it; no broad sandbox removal.

Use established systemd/sysusers/source-binary and keybinding membership mechanisms. Producer enable/disable and service/relay orchestration must have explicit ordering and rollback boundaries rather than pretending CONFIG transactions cover systemd state. Do not prune artifacts or enable services merely by rendering the playbook.

No package/source rebuild, device grabs, synthetic input, compositor reload, live file writes, or listener activation during the offline implementation slices. Sol M commits coherent owned stages and returns architectural checkpoints for parent review.
