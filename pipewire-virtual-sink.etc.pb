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
              # Sinks excluded from the combine_sink fan-out, by node.name regex:
              # - bluez_output.B0_C2_C7_FA_76_D7: Bluetooth. A2DP transport
              #   failures caused by the CSR8510 adapter's firmware (missing
              #   USB completion reports) corrupt audio for both the BT device
              #   and any linked streams. Add more bluez_output.* alternatives
              #   to the group as needed.
              # - easyeffects_sink: EasyEffects' virtual sink (2026-10-18).
              #   combine fed EasyEffects' own output back into its input
              #   (apps -> easyeffects_sink -> effects -> combine ->
              #   easyeffects_sink ...): a feedback loop, and a dead end while
              #   EE's player stream was down (total silence). Effects/virtual
              #   processing sinks must never be fan-out targets.
              stream.rules = [{
                matches = [{
                  media.class = "Audio/Sink"
                  node.name = "!~(bluez_output.B0_C2_C7_FA_76_D7|easyeffects_sink).*"
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
