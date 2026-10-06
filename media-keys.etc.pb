---
# media-keys.etc.pb -- desktop media-key producer deployment.
#
# MODEL IMPLEMENTATION of the keybinding producer system
# (doc/config/keybinding-producers.md): a pure-binding producer with no
# source build, no ETC_FILES of its own and no authored installer body --
# only KEYBINDING_ACTIONS/KEYBINDINGS declarations packaged by the thin
# generator into etc/action/*.yaml + etc/keybinding/*.yaml, the
# keybinding-producer.json manifest, and the generated scoped target
# operations composed behind the user-default install.mjs action family.
#
# Domain: system-wide media keys (XF86Audio*). Any emitter works -- physical
# keyboards, and the Surface Dial daemon (surface-dial.src.pb), whose Volume
# and Media+Volume control modes inject Shift+VOLUMEUP/VOLUMEDOWN (fine
# steps), MUTE, PLAYPAUSE, NEXTSONG and PREVIOUSSONG through uinput. The
# chord vocabulary mirrors the hand-written binds that lived in
# ~/.config/niri/config.kdl (2026-06 era) so behavior carries over 1:1:
# coarse steps on plain keys, fine 0.02 steps on Shift+Volume for dial-style
# emitters, mute/transport bound both plain and Shift, mic mute included for
# keyboards with a mic button. That niri block is retired in favor of this
# producer when the consumer hosts are adopted.
#
# Shared producer targets from vars/common.yaml bind the compositor hosts:
#   invocation-time home-local host profiles (niri.etc.pb /
#   umbriel.etc.pb), user context/scope: installers register into the
#   durable membership those profiles own; nothing renders into ~/.config
#   at playbook time.
#
# Prerequisites (not installed here): node for the bundled keybindings
# runtime, jq, and the niri/umbriel binaries for native validation.
- hosts: all
  vars:
    TYPE: media-keys
    NAME: media-keys
    KEYBINDING_ACTIONS:
      media-volume-up:
        exec: [wpctl, set-volume, "@DEFAULT_AUDIO_SINK@", "0.06+", "-l", "1.0"]
      media-volume-down:
        exec: [wpctl, set-volume, "@DEFAULT_AUDIO_SINK@", "0.06-"]
      media-volume-up-fine:
        exec: [wpctl, set-volume, "@DEFAULT_AUDIO_SINK@", "0.02+", "-l", "1.0"]
      media-volume-down-fine:
        exec: [wpctl, set-volume, "@DEFAULT_AUDIO_SINK@", "0.02-"]
      media-mute:
        exec: [wpctl, set-mute, "@DEFAULT_AUDIO_SINK@", toggle]
      media-mic-mute:
        exec: [wpctl, set-mute, "@DEFAULT_AUDIO_SOURCE@", toggle]
      media-play-pause:
        exec: [playerctl, play-pause]
      media-stop:
        exec: [playerctl, stop]
      media-prev:
        exec: [playerctl, previous]
      media-next:
        exec: [playerctl, next]
    KEYBINDINGS:
      media-volume-up:
        action: media-volume-up
        keys: [XF86AudioRaiseVolume]
        title: Volume up
        niri:
          options: {allow-when-locked: true}
      media-volume-down:
        action: media-volume-down
        keys: [XF86AudioLowerVolume]
        title: Volume down
        niri:
          options: {allow-when-locked: true}
      media-volume-up-fine:
        action: media-volume-up-fine
        keys: [Shift+XF86AudioRaiseVolume]
        title: Volume up (fine)
        niri:
          options: {allow-when-locked: true}
      media-volume-down-fine:
        action: media-volume-down-fine
        keys: [Shift+XF86AudioLowerVolume]
        title: Volume down (fine)
        niri:
          options: {allow-when-locked: true}
      media-mute:
        action: media-mute
        keys: [XF86AudioMute]
        add-keys: [Shift+XF86AudioMute]
        title: Mute output
        niri:
          options: {allow-when-locked: true}
      media-mic-mute:
        action: media-mic-mute
        keys: [XF86AudioMicMute]
        add-keys: [Shift+XF86AudioMicMute]
        title: Mute microphone
        niri:
          options: {allow-when-locked: true}
      media-play-pause:
        action: media-play-pause
        keys: [XF86AudioPlay]
        add-keys: [Shift+XF86AudioPlay]
        title: Play/Pause
        niri:
          options: {allow-when-locked: true}
      media-stop:
        action: media-stop
        keys: [XF86AudioStop]
        add-keys: [Shift+XF86AudioStop]
        title: Stop
        niri:
          options: {allow-when-locked: true}
      media-prev:
        action: media-prev
        keys: [XF86AudioPrev]
        add-keys: [Shift+XF86AudioPrev]
        title: Previous track
        niri:
          options: {allow-when-locked: true}
      media-next:
        action: media-next
        keys: [XF86AudioNext]
        add-keys: [Shift+XF86AudioNext]
        title: Next track
        niri:
          options: {allow-when-locked: true}
    # Keep INSTANCE/NAME semantics independent of material placement.
    PREFIX_DIR: "{{ ansible_env.XDG_DATA_HOME | default(ansible_env.HOME ~ '/.local/share', true) }}/compfuzor/etc"
    ETC: "{{DIR}}"
    ACTION_AUDIENCES: {default: user}
    README: |
      # media-keys.etc.pb

      Home-local material under
      `${XDG_DATA_HOME:-$HOME/.local/share}/compfuzor/etc/{{NAME}}`, the
      **model implementation** of a pure keybinding producer: declarations
      only, generated packaging, no authored installer body.

      Owns the system-wide media keys (XF86Audio* volume/mute/transport,
      plain + Shift fine-step variants) for both compositors, replacing the
      hand-written media block in `~/.config/niri/config.kdl`. The Surface
      Dial daemon (surface-dial.src.pb) emits exactly these chords through
      uinput.

      ## Install (as the desktop user, after consumer hosts are adopted)

      ```sh
      ansible-playbook -i 'localhost,' -c local media-keys.etc.pb
      material="${XDG_DATA_HOME:-$HOME/.local/share}/compfuzor/etc/{{NAME}}"
      "$material/bin/install.mjs"
      ```

      `install.mjs` / `install-user.mjs` register the producer into
      home-local Niri/Umbriel consumer profiles (run their `install.mjs`
      adoption first) and rebuild each
      compositor's managed insertion area with native validation.

      Consumer selectors resolve HOME/XDG at invocation, not the rendering user's
      literal home. `COMPFUZOR_NIRI_PROFILE` and `COMPFUZOR_UMBRIEL_PROFILE`
      explicitly select shared/other profile JSON files. Shared producer material
      itself is separately selected with `-e PREFIX_DIR=/etc/opt`.
      Only user targets are declared: no install-system.mjs is emitted. This
      producer does not own a host assembly action; use the hosts' assemble.mjs.
      No old material, registrations or services are automatically cleaned up/reloaded.

      ## Files

      - `etc/action/*.yaml` + `etc/keybinding/*.yaml` -- packaged declarations
      - `etc/keybinding-producer.json` -- producer manifest
      - `bin/install-user.mjs` + `bin/install.mjs` -- generated user action family
      - `bin/install-keybindings-{niri,umbriel}.sh` -- generated target installers
      - `bin/keybindings.mjs` -- generated shared keybindings runtime

      Requires node, jq, `niri` and `umbriel` on PATH at invocation time;
      none are installed by this deployment.
  tasks:
    - import_tasks: tasks/compfuzor.includes
