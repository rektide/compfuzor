---
type: CapabilityAssessment
title: Umbriel routing and the precision-state boundary
description: Existing shortcut and IPC capabilities, a dedicated-key alternative, and constraints on a sideways physical-modifier state feed.
resource: /design/surface-dial-layers/routing0.gpt61s.md
status: draft
generated: { by: model:gpt-6.1-sol, at: 2026-10-06 }
stale_after: 2027-01-06
sources:
  - resource: https://github.com/noctalia-dev/umbriel/tree/51e6528ecf3d787531d9f8e536df24196edea17d
    title: Installed Umbriel revision examined in the previous assessment
  - resource: https://github.com/jtroo/kanata/tree/v1.9.0
    title: Version-matched Kanata protocol, parser, and message-push implementation
  - resource: /design/surface-dial-layers/brief0.gpt61s.md
    title: Revised user intent and investigation boundaries
---

# The new dimension is intent, not another Shift count

The desired state is **keyboard-held precision**, independent of the dial's existing control mode. That does not imply changing the compositor's global shortcut layer, nor counting two simultaneous Shift sources as two modifiers. It can select a dial action in one of two places: Umbriel at shortcut dispatch, or the daemon at dial-event dispatch.

Keep three quantities independent: mechanical/haptic ticks per turn, action increment per tick, and the ratio between baseline and precision increments. Also keep ordinary keyboard media actions distinct from dial policy unless their convergence is explicitly wanted.

# Verified Umbriel boundary

The prior [installed-source assessment](/design/surface-dial-input/assessment0.gpt61s.md) established running revision `51e6528ecf3d787531d9f8e536df24196edea17d`. Reading that revision's IPC and shortcut code adds these constraints:

| Facility | Present behavior | Consequence |
|---|---|---|
| Keyboard shortcuts | [Aggregate modifiers across registered keyboards](https://github.com/noctalia-dev/umbriel/blob/51e6528ecf3d787531d9f8e536df24196edea17d/src/server/server_keybinds.cpp#L267-L275) | A dedicated dial key without synthetic Shift can be selected differently while keyboard Shift is held. |
| Modifier-only binding | [Armed on press, executed as a tap on release](https://github.com/noctalia-dev/umbriel/blob/51e6528ecf3d787531d9f8e536df24196edea17d/src/input/keyboard.cpp#L358-L383); other input cancels the tap | A `Shift` binding is **not** a held-state publisher. It cannot turn daemon precision on at Shift-down and off at Shift-up. |
| Submaps | [Global active shortcut stack with entry/reset actions](https://github.com/noctalia-dev/umbriel/blob/51e6528ecf3d787531d9f8e536df24196edea17d/src/server/server_keybinds.cpp#L348-L360) | Useful for deliberately latched modes, not equivalent to an orthogonal momentary Shift bit. Ordinary binds may stop matching inside a submap. |
| IPC subscriptions | [Six fixed event families](https://github.com/noctalia-dev/umbriel/blob/51e6528ecf3d787531d9f8e536df24196edea17d/src/server/ipc.h#L20-L36): theme, overview, keyboard layout, windows, workspaces, submap | No held-modifier stream or bind-executed event in the examined interface. `keyboard_layout` is a language/layout event, not a remapper layer or precision bit. |
| IPC commands | [Fixed command table](https://github.com/noctalia-dev/umbriel/blob/51e6528ecf3d787531d9f8e536df24196edea17d/src/server/ipc_commands.cpp#L616-L629), including `msg` | No generic variable store, keyboard-state query, or key-injection command. A `msg spawn:...` action runs a command; it does not synthesize a key. |

Both the installed revision and current archived HEAD have the same six-family IPC boundary. No live subscription or state mutation was run for this assessment.

# Dedicated direction keys: no extra state protocol needed

One contained design is for dial volume to emit **unshifted, dial-specific direction keys**, e.g. F23 up and F24 down, rather than Shift+Volume:

```text
dial rotation ── F23 / F24 ──► Umbriel shortcut matcher ──► selected dial action
                                      ▲
physical keyboard ── Shift ────────────┘
```

Conceptual binding vocabulary, not installed configuration:

| Input | Intent |
|---|---|
| F23 | Dial baseline up |
| F24 | Dial baseline down |
| Shift+F23 | Dial precision up |
| Shift+F24 | Dial precision down |

Two direction codes cover four actions because Shift supplies the extra dimension. F24 is an **event code**, not a separate mode bit. There is no need to reserve a third function key to enable precision. Ordinary keyboard Volume keys can retain the media producer's existing semantics. Dial bindings could be packaged by the Surface Dial producer rather than `media-keys.etc.pb`; that is a proposed ownership change, not an existing deployment.

Umbriel's [chord parser](https://github.com/noctalia-dev/umbriel/blob/51e6528ecf3d787531d9f8e536df24196edea17d/src/config/keybind_parse.cpp#L415-L461) resolves named XKB keysyms. Linux `KEY_F23/F24` codes must therefore be checked against the actual keymap rather than assumed to retain those names. An isolated in-memory evdev/pc105/us experiment using installed libxkbcommon produced:

```text
options=(none)
  KEY_F23: F23
  KEY_F24: F24
  Shift+KEY_F23: F23
  Shift+KEY_F24: F24
```

The same results held with `fkeys:basic_13-24`. Scratch command: `./.test-agent/surface-dial-layers/keysyms.py`; it compiled a fixture, opened no devices, and did not capture the live seat's keymap. Raw partial XKB source has historical touchpad mappings, but later definitions can override them: reading one partial is not a valid effective-keymap test.

This design still needs the daemon to advertise/emit the new keys, conflict checks, real route tests, and logged action selection. Exact modifier matching means additional held Ctrl/Alt/Super can prevent a plain/Shift binding from matching. If other modifiers should be ignored, that is another explicit policy requirement.

# Sideways state: promising, but choose the publisher first

If the daemon should own precision selection and execute the action directly, it needs a trustworthy physical-keyboard state source. Umbriel's existing public IPC does not provide one. Extending Umbriel to publish device-aware modifiers is possible in principle, but after Kanata merges a physical keyboard with dial input, original device provenance cannot be reconstructed there.

A remapper-side publisher is worth exploring, especially before merger or in a keyboard-scoped instance. Kanata v1.9.0 has a real starting point:

- [`push-msg` parser](https://github.com/jtroo/kanata/blob/v1.9.0/parser/src/cfg/mod.rs#L2617-L2625) produces `CustomAction::PushMessage`; it is present in code even though that version's config reference lacks a dedicated section.
- [Runtime dispatch](https://github.com/jtroo/kanata/blob/v1.9.0/src/kanata/mod.rs#L1531-L1557) sends an S-expression-derived JSON array in `ServerMessage::MessagePush`, conditional on TCP-server support and a running server.
- The [protocol enum](https://github.com/jtroo/kanata/blob/v1.9.0/tcp_protocol/src/lib.rs) supports layer changes and fake-key actions, **not** `SetVariable`. Config `defvar` substitution is not an externally writable runtime variable API.
- [TCP connection initialization](https://github.com/jtroo/kanata/blob/v1.9.0/src/tcp_server.rs#L83-L104) sends the current layer, not a snapshot of arbitrary pushed state. Generic pushed press/release messages are edges, not a reliable reconnectable state store.

That supports a proposed bridge, not a ready-made variable protocol. Its contract should address:

1. **Provenance:** only designated physical keyboards can contribute the precision bit; do not treat dial-generated Shift as physical intent.
2. **Aggregation:** track left/right and multiple keyboards by holder/source, then OR their contributions. Releasing one must not erase another holder.
3. **Snapshot and authority:** reconnect/startup must establish current held state; unknown is distinct from false. Disconnect/device removal must invalidate the lost source's contribution.
4. **Ordering:** a remote state update and a dial tick are separate streams. Log which state generation the daemon sampled at dispatch; do not promise zero-latency physical-time ordering.
5. **Local security:** use a deliberately scoped local endpoint. Kanata's command channel can change layers and activate fake keys, so opening it for observations has broader effects than a read-only precision feed.
6. **Action ownership:** if the daemon executes `wpctl` or emits an event for Umbriel, it should not do both for the same tick. Trace selection separately from dispatch result.

These are protocol-design requirements, not implemented facilities. The daemon investigation should determine how much the existing fork already supplies before recommending new machinery.

# Architectural checkpoint

Preserve both routes until the G reports identify the actual daemon's facilities. The dedicated-key route is simpler for **hold Shift to choose a different compositor action**; the sideways-state route is more expressive for **daemon-owned precision, layers, status, and future controllers**. A toggle can be easier to transport but is not the requested held-Shift behavior.

Do not adopt a global submap solely to model a dial-local boolean. Do not demand Kinefolk deployment for a precision layer. The next implementation decision should be based on verified unit lineage, existing fork control seams, and where observable action selection should live.

# Cross-references

- [Inquiry brief](/design/surface-dial-layers/brief0.gpt61s.md): revised intent, open amounts, and no-deployment boundary.
- [Previous overall assessment](/design/surface-dial-input/assessment0.gpt61s.md): running compositor revision and the stock dial's synthetic Shift semantics.
- [Kanata merger assessment](/design/surface-dial-input/kanata-assessment0.gpt61s.md): device-identity loss and same-key release hazards, motivating a separate physical precision signal.
- [Producer authoring guide](/doc/config/keybinding-producers.md): source deployments can declare their own action/binding resources without moving dial policy into global media keys.

# Addendum: deployed Kanata is not TCP-ready

A subsequent read-only capability check narrows the upstream message-push option. `/usr/bin/kanata --help` listed no `-p` or `--port` argument. The [v1.9.0 CLI source](https://github.com/jtroo/kanata/blob/v1.9.0/src/main_lib/args.rs) exposes that argument only with the `tcp_server` feature. This is evidence that the installed binary lacks that facility, rather than merely having no configured listener.

The installed `/usr/lib/systemd/system/kanata.service` also has:

```ini
User=_kanata
ExecStart=/usr/bin/kanata --cfg /etc/kanata/config.kbd
PrivateNetwork=true
RestrictAddressFamilies=AF_AX25
RestrictAddressFamilies=~AF_AX25
IPAddressDeny=any
```

The declared [kinata service](/kinata.srv.pb) and [BlueTurn service](/kanata-blueturn.srv.pb) follow the same network-isolation pattern. A loopback listener inside a private network namespace would not become the desktop user's host-loopback endpoint; the address-family restrictions are a separate barrier. `_kanata` also is not the desktop user that owns session audio and runtime state.

Therefore, a TCP state bridge would require **a binary with the feature plus a deliberately revised service transport/security arrangement**, not just adding `push-msg` to a keymap. No such changes were made. A local non-TCP publisher or a different trusted state source remains worth comparing; it must also account for the service's permissions and sandbox, rather than assuming arbitrary commands can reach a user-session socket.
