---
type: RoutingProposal
title: Dial-scoped Kanata normalization with media-keys-owned actions
description: Keep Surface Dial unchanged; intercept its virtual keyboard separately, suppress synthetic Shift, and give media-keys distinct direction events.
resource: /design/surface-dial-layers/dial-remap0.gpt61s.md
status: draft
generated: { by: model:gpt-6.1-sol, at: 2026-10-07 }
sources:
  - resource: https://github.com/daniel5151/surface-dial-linux/blob/43dd973092871d8ef0c452b0797b519f5a9ddfac/src/fake_input.rs
    title: Daemon virtual keyboard and chord emission
  - resource: https://github.com/jtroo/kanata/blob/2f84d17/src/oskbd/linux.rs
    title: Linux device selection, untagged event merging, and virtual output key capabilities
  - resource: https://github.com/jtroo/kanata/blob/2f84d17/docs/config.adoc
    title: Keyboard device-history platform boundary and named-device selection
  - resource: /media-keys.etc.pb
    title: Desired action-policy owner
---

# Revised direction

The user prefers not to add a substantial protocol consumer/action engine to Surface Dial. They want media-keys to own the actions, and accept a dedicated F-key vocabulary if useful. This is a simpler route than the previous sideways-state proposal: leave the daemon unchanged and normalize its emitted virtual keyboard through a device-scoped Kanata instance.

# Where the dial emits

The requested archive path `~/archive/daniel5151/surface-dial-linux` is absent. The managed upstream checkout is `/usr/local/src/surface-dial-git`, with `repo` resolving back to it; the local fork and layered variant also exist under `~/src`. These sources were read before any web retrieval.

[`fake_input.rs`](https://github.com/daniel5151/surface-dial-linux/blob/43dd973092871d8ef0c452b0797b519f5a9ddfac/src/fake_input.rs#L19-L55) creates a uinput device named **Surface Dial Virtual Keyboard/Mouse**. Volume and Media+Volume call `key_click([KEY_LEFTSHIFT, KEY_VOLUMEUP/DOWN])`; [key_click](https://github.com/daniel5151/surface-dial-linux/blob/43dd973092871d8ef0c452b0797b519f5a9ddfac/src/fake_input.rs#L149-L182) writes ordinary evdev press/report/release/report events through that virtual device. A separate virtual touchpad is not the desired media event source.

Kanata can grab this node exactly like a physical keyboard. The daemon's output capabilities do not include F23/F24, but Kanata's own [virtual output advertises key codes 0–559](https://github.com/jtroo/kanata/blob/2f84d17/src/oskbd/linux.rs#L425-L433), so **a remapper can emit the reserved keys without modifying the dial daemon's capabilities**.

# Linux multi-device boundary, verified against the installed version

Kanata knows devices when selecting and reading them, but does not expose keyboard device identity to the Linux mapping engine:

- [`KbdIn`](https://github.com/jtroo/kanata/blob/2f84d17/src/oskbd/linux.rs#L31-L42) tracks device handles/paths by poll token for capture, removal, and rediscovery.
- [`read`](https://github.com/jtroo/kanata/blob/2f84d17/src/oskbd/linux.rs#L140-L158) appends their untagged `InputEvent`s into a shared vector.
- [`KeyEvent` conversion](https://github.com/jtroo/kanata/blob/2f84d17/src/oskbd/linux.rs#L363-L371) retains key code/value, not the original device token/path.
- The [Linux event loop](https://github.com/jtroo/kanata/blob/2f84d17/src/kanata/linux.rs#L43-L110) feeds those events through shared mapped-key/pressed-key state and one processing channel.
- The config reference explicitly marks keyboard `device-history` conditions and its keyboard `definputdevices` example as **macOS-only; Linux support planned**. New gamepad device matching is a separate facility and does not make this keyboard/evdev path device-aware.

Thus **capture-time selection: yes; device-conditioned keyboard remapping inside one shared Linux instance: no**. Equal key codes from different captured devices share the remapping/state namespace. Do not put `lsft → XX` into the main instance: it would suppress physical keyboard Shift too.

# Proposed ownership graph

```text
Surface Dial daemon (unchanged)
  → Surface Dial Virtual Keyboard/Mouse
  → dial-scoped Kanata: lsft → XX, volu → F23, vold → F24
  → kanata-surface-dial output
  → media-keys-authored actions, compiled to compositor bindings

physical keyboards
  → main / existing scoped keyboard remappers
  → normal keyboard Shift contributes at the compositor matcher
```

Main must relinquish the raw dial node before the scoped instance starts. If the scoped output is renamed `kanata-surface-dial`, main must also exclude that output explicitly so it does not capture it again. The default exact name `kanata` already has an autodetection guard, but a descriptive renamed output is not covered by that guard. No exclusivity race or implicit chain should be created.

# Parse-validated candidate, not deployed

```lisp
(defcfg
  process-unmapped-keys yes
  linux-dev-names-include ("Surface Dial Virtual Keyboard/Mouse")
  linux-output-device-name "kanata-surface-dial"
  linux-continue-if-no-devs-found yes
)
(defsrc lsft volu vold)
(deflayer base XX f23 f24)
```

`XX` consumes the dial's synthetic Left Shift; it is not transparent `_`. Volume becomes two distinct unshifted direction codes. Other keys and non-key passthrough remain in the existing pipeline; Zoom, wheel, mute/transport, reconnect, and actual event counts still need verification before deployment.

The installed binary accepted `.test-agent/surface-dial-remap/dial.kbd` using `--check`. This was syntax-only: no service, input grab, key injection, package, live config, or media action was changed.

# media-keys owns the policy

Candidate vocabulary:

| Binding | Action intent |
|---|---|
| F23 | Dial normal increment up |
| F24 | Dial normal increment down |
| Shift+F23 | Dial extra-fine increment up |
| Shift+F24 | Dial extra-fine increment down |

Physical keyboard Shift remains effective, while the dial's own Shift never reaches the compositor or the keyboard's shared remapper state. Umbriel/Niri only execute generated bindings; no dial state store or substantial daemon changes are required. TCP is unnecessary for this route.

The current working media producer now declares plain `0.03` and Shift `0.01` steps, differing from the earlier `0.06/0.02` research snapshot. Preserve those user edits; do not silently choose new dial normal/extra-fine amounts. New action IDs or reuse of existing fine actions are a media-keys decision. F23/F24 remain proposed assignments until accepted; coordinate with the [Kinefolk host-signal registration](file:///home/rektide/src/kinefolk-rs/design/host-signal/idea0.glm53.md) rather than also allocating them to keyboard mode signals.

# Cross-references

- [Earlier input assessment](/design/surface-dial-input/assessment0.gpt61s.md): installed Umbriel aggregates shortcut modifiers across keyboards, so the output need not be merged with the keyboard's Shift stream.
- [TCP scheme](/design/surface-dial-layers/tcp-scheme0.gpt61s.md): genuine remote controls remain available, but are not a requirement for this simpler proposal.
- [Source Kanata deployment](/doc/input/kanata.md): reusable source binary, persistent service/account/rule ownership, and config-preserving updates.
- [Precision synthesis](/design/surface-dial-layers/syn0.gpt61s.md): prior alternatives and the separate haptic/increment/event-accounting questions.
