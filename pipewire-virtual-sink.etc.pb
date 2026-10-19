---
- hosts: all
  vars:
    TYPE: pipewire-virtual-sink
    INSTANCE: main
    ETC_FILES:
      - name: pipewire-virtual-sink.conf
        content: |
          context.modules = [{
            name = libpipewire-module-combine-stream
            args = {
              combine.mode = sink
              node.name = "combine_sink"
              node.description = "Combine Sink"
              combine.latency-compensate = true
              combine.props = {
                audio.position = [ FL FR]
              }
              stream.props = {
              }
              # Fan out to ALSA hardware sinks (plus eq_sink) via a positive
              # node.name regex. The 2026-10-18 EasyEffects integration first
              # tried a negated alternation ("!~(bluez_output...|easyeffects_sink).*"):
              # fan-out streams for all five hardware sinks vanished as soon
              # as the excluded easyeffects_sink appeared, leaving combine_sink
              # metering in pavucontrol but delivering to nothing (total
              # silence). The positive alsa_output.* whitelist sidesteps that
              # failure mode and excludes Bluetooth sinks (bluez_output.*)
              # implicitly - the CSR8510 adapter's firmware (missing USB
              # completion reports) corrupts audio for the BT device and any
              # linked streams. Other virtual sinks (easyeffects_sink, future
              # surround) never match.
              #
              # eq_sink (pw-eq.etc.pb) is deliberately IN the fan set: it is
              # the FiiO branch EQ insert. combine fans into eq_sink, whose
              # filter-chain delivers to the WEILIANG (FiiO E10) sink. The raw
              # WEILIANG fan stream stays too and is zeroed manually in
              # pavucontrol to avoid double playback on the FiiO (see
              # pw-eq.etc.pb).
              stream.rules = [{
                matches = [{
                  media.class = "Audio/Sink"
                  node.name = "~(alsa_output\\.|eq_sink).*"
                }]
                actions = { create-stream = {}}
              }]
            }
          }]
    BINS:
      - name: install-user.sh
        exec: |
          # TODO: figure out how to xdg again
          dest="${XDG_CONFIG_DIR:-$HOME/.config}/$APP/pipewire.conf.d"
          mkdir -p $dest
          ln -s ${ETC}/pipewire-virtual-sink.conf $dest/
    ENV:
      ETC: "{{ETC}}"
      APP: pipewire
  tasks:
    - import_tasks: tasks/compfuzor.includes
