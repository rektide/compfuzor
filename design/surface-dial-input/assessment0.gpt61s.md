---
type: CapabilityAssessment
title: Fine media adjustment across Surface Dial, Kanata, and Umbriel
description: Installed Umbriel already aggregates shortcut modifiers; Kanata consolidation is possible but carries same-key collision risks.
resource: /design/surface-dial-input/assessment0.gpt61s.md
status: draft
generated: { by: model:gpt-6.1-sol, at: 2026-10-06 }
stale_after: 2027-01-06
sources:
  - resource: https://github.com/noctalia-dev/umbriel/tree/51e6528ecf3d787531d9f8e536df24196edea17d
    title: Source revision reported by the running Umbriel executable
  - resource: /design/surface-dial-input/kanata-assessment0.gpt61s.md
    title: Version-matched Kanata capability assessment
  - resource: /media-keys.etc.pb
    title: Declared coarse and fine media actions
  - resource: /design/surface-dial/diagnosis0.glm53.md
    title: Prior live Surface Dial media-binding diagnosis
---

# Question and result

Fine volume adjustment is reported broken. The proposed explanation is that Umbriel only sees Shift on the device emitting the media key; the proposed workaround is to merge keyboard and dial events through [`kanata.srv.pb`](/kanata.srv.pb).

**Kanata can consolidate the streams, but the reported Umbriel limitation is not what the installed shortcut code does.** Diagnose the precise failing interaction before changing input ownership. In particular, distinguish physical keyboard Shift plus a separate media node from a dial click: the stock dial supplies its own Shift.

This is a source-backed assessment, **not a reproduced diagnosis or a fix**. No service, deployed configuration, or playbook was changed.

# Umbriel: shortcuts already combine keyboards

Both `/usr/local/bin/umbriel --version` and `/proc/2405771/exe --version` reported:

```text
umbriel 0.1.0 (51e6528ecf3d)
```

The matching commit is `51e6528ecf3d787531d9f8e536df24196edea17d`, dated 2026-09-22. Its source was read from the local archived checkout, rather than inferring deployed behavior from current HEAD:

- [`Keyboard::handleKey`](https://github.com/noctalia-dev/umbriel/blob/51e6528ecf3d787531d9f8e536df24196edea17d/src/input/keyboard.cpp#L260-L262) calls `m_server->keyboardModifiers()` for shortcut matching. Its comment explicitly describes XF86 keys arriving from a dedicated hotkey device while modifiers are held on a main keyboard.
- [`Server::keyboardModifiers`](https://github.com/noctalia-dev/umbriel/blob/51e6528ecf3d787531d9f8e536df24196edea17d/src/server/server_keybinds.cpp#L267-L275) ORs `wlr_keyboard_get_modifiers()` across registered keyboards.
- [`Server::matchKeybind`](https://github.com/noctalia-dev/umbriel/blob/51e6528ecf3d787531d9f8e536df24196edea17d/src/server/server_keybinds.cpp#L224-L264) ignores Caps/Num Lock masks but otherwise requires the effective modifier mask to equal the binding's mask. Shift plus another held modifier is not equivalent to Shift alone.

Do not generalize this to every input path. [`handleModifiers`](https://github.com/noctalia-dev/umbriel/blob/51e6528ecf3d787531d9f8e536df24196edea17d/src/input/keyboard.cpp#L210-L239) forwards the emitting keyboard's state to the seat/input method, and unhandled keys select that keyboard before client delivery. Compositor shortcut matching and application-facing modifier behavior are distinct. The media producer uses compositor shortcuts.

# Dial: external Shift is unnecessary for its existing fine chord

The inspected daemon's Volume and Media+Volume modes generate `KEY_LEFTSHIFT` plus `KEY_VOLUMEUP/DOWN` through one virtual keyboard. See [`Volume::on_dial`](https://github.com/daniel5151/surface-dial-linux/blob/43dd973092871d8ef0c452b0797b519f5a9ddfac/src/controller/controls/volume.rs#L36-L44), [`MediaWithVolume`](https://github.com/daniel5151/surface-dial-linux/blob/43dd973092871d8ef0c452b0797b519f5a9ddfac/src/controller/controls/media_with_volume.rs#L95-L104), and [`key_click/press/release`](https://github.com/daniel5151/surface-dial-linux/blob/43dd973092871d8ef0c452b0797b519f5a9ddfac/src/fake_input.rs#L149-L182).

[`media-keys.etc.pb`](/media-keys.etc.pb) maps plain volume to 0.06 and Shift+volume to 0.02. Therefore:

- A stock dial tick is already intended to be fine, without touching the keyboard.
- Holding additional keyboard Shift does not express a second, finer level: Shift is a modifier bit, not a count.
- If a second dial speed is desired, that is a policy/design change, not merely modifier aggregation. Preserve this distinction before choosing an input-merging workaround.

# Kanata: feasible merging, not a free repair

The [version-matched Kanata assessment](/design/surface-dial-input/kanata-assessment0.gpt61s.md) establishes multiple inputs → one output, device discovery, and candidate chaining syntax against upstream v1.9.0. Its important architectural conclusions are:

1. Main already supports consolidation. `process-unmapped-keys yes` keeps Shift/media meanings; it does not require listing them in the caps-only map.
2. The **declared** Kinesis split leaves keyboard Shift in kinata and Consumer Control in main. Default-named `kanata` outputs are not automatically captured by main, so those instances do not implicitly form a merger.
3. A renamed `kanata-kinata` output can deliberately feed main, while keeping final output named `kanata` and kinata restricted to its physical keyboard. This preserves device-specific F21/F22 remapping upstream. It is a candidate, not an authorized or tested deployment.
4. Consolidation discards source identity. A dial Left Shift release can clear the same merged coordinate as physically held Left Shift. Source inspection confirms coordinate-wide release, not per-device holder counting. Chaining does not repair that loss.

Consequently, do not consolidate solely to provide a shortcut capability Umbriel already has. If consolidation is useful for other reasons, explicitly test overlapping same-key presses and prevent capture cycles.

# Observed deployment and evidence limits

Read-only observations on 2026-10-06:

- The deployed `/etc/kanata/config.kbd` excluded only the BlueTurn pedal, **not** Kinesis, unlike the current main playbook. The queried `kanata-kinata.service` unit was absent. The declared split must not be presented as confirmed live routing.
- Main's journal recorded registering `Surface Dial Virtual Keyboard/Mouse` on October 5. That is historical registration evidence, not a current capture or successful action assertion.
- The installed Umbriel binding files contained both the 0.06 plain and 0.02 Shift commands. File presence alone does not establish runtime matching.
- [Earlier diagnosis](/design/surface-dial/diagnosis0.glm53.md#addendum-resolved-2026-10-05) reports a successful end-to-end synthetic dial chord on October 5. Its retained `kan21.log` records Shift down → Volume Up down → Shift up → Volume Up up on one Kanata output. That prior result does not settle today's physical symptom.
- This session's `/dev/input` exposed no `event*` nodes, and the available `/proc/bus/input/devices` listing omitted the expected keyboards/dial outputs. No live evdev capture, injection, or unattended red/green reproducer was possible here. Do not infer actual device disconnection from that visibility limit.

# Next discriminating observation

First identify which interaction fails, then capture the intended action and input events at the same time:

| Interaction | What it distinguishes |
|---|---|
| Dial alone | Its self-generated Shift chord and the 0.02 action, without cross-device modifiers. |
| Keyboard Shift + plain media key | Cross-keyboard shortcut matching; compare Left and Right Shift. |
| Keyboard Shift + dial | Existing fine action versus a requested second speed; check both expected deltas explicitly. |
| Hold Shift, tick dial, then type | Premature Shift release after merged same-code input; compare Left and Right Shift. |

Observe one isolated volume action away from the volume cap; action-command selection is a sharper signal than judging dial feel or counting haptic ticks. Keep a read-only trace before experimenting with ownership, and avoid hard-coded historical `eventN` paths. No live root cause is ranked or claimed without that missing reproduction.

# Cross-references

- [Kanata capability assessment](/design/surface-dial-input/kanata-assessment0.gpt61s.md): detailed selector behavior, acyclic chaining candidate, and modifier-collision source evidence.
- [Original Surface Dial diagnosis](/design/surface-dial/diagnosis0.glm53.md): prior binding-installation failure and synthetic fine-step success; different from a confirmed current cross-device failure.
- [Producer authoring guide](/doc/config/keybinding-producers.md): rendering declarations is distinct from installing consumer membership, relevant when comparing intended and deployed bindings.
- [Main Kanata](/kanata.srv.pb), [kinata](/kinata.srv.pb), and [media producer](/media-keys.etc.pb): declared ownership and action policy; observed live configuration currently differs from the declared split.
