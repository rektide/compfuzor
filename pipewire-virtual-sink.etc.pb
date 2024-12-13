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
              stream.rules = [{
                matches = [{ media.class = "Audio/Sink" }]
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
