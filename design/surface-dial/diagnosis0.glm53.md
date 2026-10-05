---
type: Diagnosis
title: Surface Dial ticks but no longer moves the combine sink
description: The daemon, uinput injection, kanata passthrough and audio default-sink selection are all healthy; the session compositor is Umbriel, which had no media-key bindings because the niri config carrying them is dead config. Fix runs through the keybinding producer system.
resource: /design/surface-dial/diagnosis0.glm53.md
status: stable
generated: { by: model:glm53, at: 2026-10-05 }
verified: { by: human:rektide, at: 2026-10-05 }
stale_after: 2027-01-05
sources:
  - resource: /usr/local/src/surface-dial-git/src/fake_input.rs
    title: uinput keyboard device and key injection implementation
  - resource: /etc/kanata/config.kbd
    title: kanata main instance grabbing all keyboards except the pedal
  - resource: /design/keybindings/adoption0.glm53.md
    title: Keybinding consumer-host adoption checkpoint with pending live steps
---

# Diagnosis: dial ticks, combine sink does not move

## Symptom

`systemctl --user status surface-dial` is green, haptic ticks fire, the journal
shows `volume up` / `volume down` lines, but `combine_sink` (the configured
default audio sink) never changes volume.

## The verified event chain

Each link was tested in isolation on 2026-10-05:

1. **Daemon** ([surface-dial-daemon](https://github.com/daniel5151/surface-dial-linux)):
   healthy. The Volume control mode injects
   `KEY_LEFTSHIFT + KEY_VOLUMEUP/DOWN` clicks ([volume.rs](https://github.com/daniel5151/surface-dial-linux/blob/master/src/controller/controls/volume.rs));
   media modes also emit `KEY_MUTE`, `KEY_PLAYPAUSE`, `KEY_NEXTSONG`,
   `KEY_PREVIOUSSONG` via the shared uinput keyboard
   (`fake_input.rs`, device name "Surface Dial Virtual Keyboard/Mouse",
   `/dev/input/event27`).
2. **Injection**: verified by writing a synthetic Shift+VOLUMEUP click into
   event27 with python-evdev (probe kept at
   `~/tmp-opencode/surface-dial-probe/`) and watching the events arrive.
3. **kanata** ([/etc/kanata/config.kbd](/etc/kanata/config.kbd)): grabs every
   keyboard except the iRig BlueTurn pedal, `process-unmapped-keys yes`. The
   probe confirmed Shift+VOLUMEUP passes through kanata's output device
   (event21) untouched. Not the culprit.
4. **Compositor**: the session runs **Umbriel** (umbriel.service, since
   2026-09-30 22:25), not niri. Umbriel's `defaultKeybinds()` has zero
   XF86Audio entries, and neither `~/.config/umbriel/config.toml` nor
   `keybinds-local.toml` declared any. **The keys arrive and die here.**
5. **Audio**: innocent. Default sink is `combine_sink` (34%) consistently
   across `pactl info`, WirePlumber `default.audio.sink` metadata, and
   `wpctl get-volume @DEFAULT_AUDIO_SINK@`.

## Root cause

The `wpctl set-volume @DEFAULT_AUDIO_SINK@ 0.02±` / mute / playerctl binds
that used to consume these keys live in `~/.config/niri/config.kdl`
(hand-maintained, last touched 2026-06-09). Umbriel reads
`~/.config/umbriel/*.toml`; the niri KDL is dead config. Regression window =
the niri → Umbriel session switch.

## Fix direction

Model implementation in the new keybinding producer system: a `media-keys`
producer declaring the volume/mute/transport actions and chords for both
niri and umbriel consumers, plus the pending live consumer-host adoption
from [adoption0](/design/keybindings/adoption0.glm53.md) (whose operator
steps had never been run: `/etc/opt/niri` and `/etc/opt/umbriel` did not
exist, and the umbriel runtime catalog still referenced the retired
umbriel.user.pb).

## Cross-references

- [Producer authoring guide](/doc/config/keybinding-producers.md): the
  declaration schema the fix uses.
- [Consumer assembly](/doc/config/keybinding-consumers.md): adoption and
  validation contracts the live steps exercise.
- [adoption0 checkpoint](/design/keybindings/adoption0.glm53.md): documents
  the consumer-host topology and the exact installer sequence this fix
  executes.
- [vicinae.src.pb](/vicinae.src.pb): the first real producer; the media-keys
  producer follows its shape.
