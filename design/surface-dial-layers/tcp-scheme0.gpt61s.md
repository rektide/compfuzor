---
type: ProtocolAssessment
title: What Kanata TCP can control and how it can feed dial precision
description: Verified default-layer switching, virtual-key activation, outbound messages, and the remaining Surface Dial consumer boundary.
resource: /design/surface-dial-layers/tcp-scheme0.gpt61s.md
status: draft
generated: { by: model:gpt-6.1-sol, at: 2026-10-07 }
sources:
  - resource: https://github.com/jtroo/kanata/blob/2f84d17/tcp_protocol/src/lib.rs
    title: Protocol commands and events in the installed source revision
  - resource: https://github.com/jtroo/kanata/blob/2f84d17/src/tcp_server.rs
    title: Command dispatch, initial layer snapshot, and message serialization
  - resource: https://github.com/jtroo/kanata/blob/2f84d17/src/kanata/mod.rs
    title: Default-layer changes and outbound push actions
  - resource: /doc/input/kanata.md
    title: Active source deployment and current no-listener policy
---

# Yes: a real layer/action control protocol

The installed source build has actual TCP operations, not merely a listening socket waiting for a protocol to be invented. It is plain JSON over a persistent TCP connection; newline-delimited messages are the normal framing. Each configured Kanata instance can have its own endpoint.

| Operation | Existing facility |
|---|---|
| Discover server | `Hello` returns version and capability names. |
| List/query layers | `RequestLayerNames`, `RequestCurrentLayerName`, `RequestCurrentLayerInfo`. |
| Change a layer | `ChangeLayer` selects an existing **default/base layer** in that Kanata instance. |
| Momentary layer/action | `ActOnFakeKey` presses/releases/taps/toggles an internal virtual key defined in `.kbd`; its action can be `layer-while-held`. |
| Follow layer selection | Server sends current `LayerChange` on connection, then notifications when effective layer changes. |
| Publish semantic events | Configured `push-msg` actions send `MessagePush` to connected clients. |
| Reload authored configuration | Reload commands load configured files; some support waiting for completion. |

**Not present:** a generic `SetVariable` API, creation of arbitrary new layers over TCP, a built-in Surface Dial endpoint, or a complete queryable physical-modifier state store. `defvar` is configuration substitution, not a mutable remote value.

# Incoming control: external software changes Kanata

Commands, illustrative only — no live endpoint was enabled:

```json
{"RequestLayerNames":{}}
{"ChangeLayer":{"new":"precision"}}
{"RequestCurrentLayerName":{}}
```

`ChangeLayer` [calls `set_default_layer`](https://github.com/jtroo/kanata/blob/2f84d17/src/kanata/mod.rs#L2241-L2249). It is a latched base selection, not pushing a temporary overlay. Held layers can still take precedence. An unknown layer name is silently ignored in this implementation, so discover names and observe/query the resulting state rather than assuming a universal success acknowledgement.

For a temporary overlay, define a logical handle:

```lisp
(defvirtualkeys
  precision-hold (layer-while-held precision)
)
```

Then a client can issue:

```json
{"ActOnFakeKey":{"name":"precision-hold","action":"Press"}}
{"ActOnFakeKey":{"name":"precision-hold","action":"Release"}}
```

This **does not require F24 or another physical/function key**. The virtual key is an internal named action handle. It emits an OS key only if its configured action does so.

A minimal fixture with base and precision layers passed `/usr/local/bin/kanata --check --cfg .test-agent/kanata-tcp/precision.kbd` on the installed build. This proves syntax only: no socket, device, or remote action was exercised. TCP disconnect is not an automatic virtual-key release; the implementation does not track fake-key ownership per client. A held-state controller needs an explicit reset/recovery policy.

# Outgoing state: Kanata tells Surface Dial what to do

For keyboard Shift selecting a **dial-owned** precision tier, the useful direction is usually the reverse:

```text
designated keyboard input → small Kanata signal/layer mapping
                         → TCP notifications
                         → Surface Dial consumer/bridge
                         → dial-owned selection + action + logs
```

Two possible signal schemes:

1. **Follow a named momentary layer.** Keyboard Shift preserves its normal Shift output while holding an appropriately transparent precision layer. The dial consumer follows `LayerChange`; it gets the current effective layer on reconnect. This is a useful simple prototype, but only exposes the top effective layer. Another temporary layer can hide precision; it is not a general held-bit snapshot.
2. **Publish a dedicated semantic signal.** `push-msg` on the appropriate configured actions reports precision acquire/release or modifier state. A bridge interprets that signal and updates the daemon's precision state. This separates precision from unrelated layer selection, but generic pushes have no built-in reconnect snapshot or lease/heartbeat store.

The source serializer converts S-expression atoms to strings inside JSON arrays. For example, `(push-msg precision on)` produces the message payload `['precision', 'on']` (JSON shown below):

```json
{"MessagePush":{"message":["precision","on"]}}
```

Use the installed [serializer](https://github.com/jtroo/kanata/blob/2f84d17/src/tcp_server.rs#L470-L482) as authority: the config reference's bare-string example differs from this array conversion. Do not assume a pushed `false` atom becomes a JSON boolean or that a message directly mutates a variable anywhere.

**Surface Dial has no consumer for these messages today.** Adding one is the proposed code slice. The small keyboard mapping publishes intent; volume amounts, tier policy, and action execution belong in Surface Dial/media-keys. Umbriel need not hold that state or policy.

# Preconditions before ports help

- Designate a trustworthy keyboard signal source. Main currently merges the dial's own synthetic Shift; publishing every Shift from that merged stream would self-trigger precision. Isolate the publisher or remove the dial's synthetic modifier as a separate agreed change.
- Configure a loopback endpoint and narrowly revise the service's network restrictions. `PrivateNetwork=true` creates a separate loopback namespace; changing the command line alone does not make that endpoint reachable from the user-session daemon.
- Treat the socket as **input control**, not read-only telemetry: its commands can activate key-emitting actions and reload configuration. No authentication/TLS is shown in this implementation; loopback restricts remote reach but not every local process/user.
- Separate latched mode selection from momentary held intent. Prefer press/release to toggle for held precision, and define reconnect/unknown-state behavior before relying on it.

# Suggested scheme for this project

Start with a small loopback notification consumer and one clearly defined precision signal, with a trustworthy publisher. Let Surface Dial consume that signal and own the action policy/logging. Layer-following is the quickest demonstration of existing facilities; a dedicated snapshot-capable precision signal is a cleaner destination if multiple layers/controllers must coexist.

No ports, service settings, live mappings, or dial behavior were changed during this assessment.

# Cross-references

- [Maintained Kanata deployment](/doc/input/kanata.md): source binary active, networking/listener still deliberately disabled.
- [Precision synthesis](/design/surface-dial-layers/syn0.gpt61s.md): action ownership, tuning dimensions, and publisher provenance/liveness requirements.
- [Daemon assessment](/design/surface-dial-layers/daemon-state0.glm53.md): the currently absent dial control/consumer surface and the existing shared-state dispatch seam.
